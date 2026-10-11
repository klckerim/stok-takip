import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models.dart';

/// Sunucuya ulaşılamadığında kaydedilen, gönderilmeyi bekleyen hareket.
class PendingMovement {
  /// Sunucudaki ClientRequestId ile aynı: tekrar gönderilse de bir kez yazılır.
  final String id;
  final int productId;
  final String productName;
  final String unit;
  final MovementType type;
  final double quantity;
  final String? note;
  final DateTime createdAt;

  /// Sunucu reddettiyse sebebi (ör. "Yetersiz stok"). null = sırada bekliyor.
  final String? error;

  const PendingMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.unit,
    required this.type,
    required this.quantity,
    required this.note,
    required this.createdAt,
    this.error,
  });

  PendingMovement withError(String? error) => PendingMovement(
        id: id,
        productId: productId,
        productName: productName,
        unit: unit,
        type: type,
        quantity: quantity,
        note: note,
        createdAt: createdAt,
        error: error,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'productName': productName,
        'unit': unit,
        'type': type.apiName,
        'quantity': quantity,
        'note': note,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'error': error,
      };

  factory PendingMovement.fromJson(Map<String, dynamic> json) => PendingMovement(
        id: json['id'] as String,
        productId: json['productId'] as int,
        productName: json['productName'] as String,
        unit: json['unit'] as String,
        type: MovementType.fromApi(json['type'] as String),
        quantity: (json['quantity'] as num).toDouble(),
        note: json['note'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        error: json['error'] as String?,
      );
}

class SyncResult {
  final int sent;
  final int failed;
  final bool offline;

  const SyncResult({required this.sent, required this.failed, required this.offline});
}

/// Çevrimdışı çalışma: bekleyen hareket kuyruğu + son bilinen ürün listesi.
/// İkisi de cihazda (SharedPreferences) saklanır; uygulama kapansa da kaybolmaz.
class OfflineStore extends ChangeNotifier {
  OfflineStore._();
  static final OfflineStore instance = OfflineStore._();

  static const _queueKey = 'pending_movements';
  static const _productsKey = 'product_cache';
  static const _dashboardKey = 'dashboard_cache';

  List<PendingMovement> _pending = [];
  List<Product> _products = [];
  ({Dashboard data, DateTime savedAt})? _dashboard;
  bool _syncing = false;

  List<PendingMovement> get pending => List.unmodifiable(_pending);
  int get waitingCount => _pending.where((p) => p.error == null).length;
  int get failedCount => _pending.where((p) => p.error != null).length;
  bool get syncing => _syncing;

  /// Son ürün listesi isteği sunucuya ulaşamadı mı? (Ana ekrandaki "Çevrimdışı" şeridi için.)
  bool _isOffline = false;
  bool get isOffline => _isOffline;
  void setOffline(bool value) {
    if (_isOffline == value) return;
    _isOffline = value;
    notifyListeners();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _pending = _decodeList(prefs.getString(_queueKey), PendingMovement.fromJson);
    _products = _decodeList(prefs.getString(_productsKey), Product.fromJson);
    _dashboard = _decodeDashboard(prefs.getString(_dashboardKey));
    notifyListeners();
  }

  // --- Ürün önbelleği ---

  /// Çevrimiçiyken çekilen tam ürün listesi (arama/filtre yokken) saklanır.
  Future<void> cacheProducts(List<Product> products) async {
    _products = products;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_productsKey, jsonEncode(products.map((p) => p.toJson()).toList()));
  }

  List<Product> get cachedProducts => List.unmodifiable(_products);

  Product? findCached(String barcode) {
    for (final p in _products) {
      if (p.barcode == barcode) return p;
    }
    return null;
  }

  // --- Özet önbelleği ---

  /// Son başarılı özet; çevrimdışı açılışta "son güncelleme" etiketiyle gösterilir.
  ({Dashboard data, DateTime savedAt})? get cachedDashboard => _dashboard;

  Future<void> cacheDashboard(Dashboard data) async {
    final savedAt = DateTime.now();
    _dashboard = (data: data, savedAt: savedAt);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _dashboardKey,
      jsonEncode({'savedAt': savedAt.toUtc().toIso8601String(), 'data': data.toJson()}),
    );
  }

  static ({Dashboard data, DateTime savedAt})? _decodeDashboard(String? raw) {
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return (
        data: Dashboard.fromJson(json['data'] as Map<String, dynamic>),
        savedAt: DateTime.parse(json['savedAt'] as String).toLocal(),
      );
    } catch (_) {
      return null; // eski/bozuk kayıt: önbellek yok say
    }
  }

  // --- Kuyruk ---

  Future<void> add(PendingMovement movement) async {
    _pending = [..._pending, movement];
    await _saveQueue();
  }

  Future<void> remove(String id) async {
    _pending = _pending.where((p) => p.id != id).toList();
    await _saveQueue();
  }

  /// Reddedilmiş kaydı tekrar sıraya alır (ör. stok girildikten sonra çıkışı yeniden denemek için).
  Future<void> retry(String id) async {
    _pending = [for (final p in _pending) p.id == id ? p.withError(null) : p];
    await _saveQueue();
  }

  /// Sırayla (eskiden yeniye) gönderir.
  /// Ağ yoksa durur; sunucu reddederse kaydı hatalı işaretleyip devam eder.
  Future<SyncResult> sync() async {
    if (_syncing || waitingCount == 0 || ApiClient.instance.session == null) {
      return const SyncResult(sent: 0, failed: 0, offline: false);
    }

    _syncing = true;
    notifyListeners();
    var sent = 0, failed = 0;
    var offline = false;

    try {
      for (final item in _pending.where((p) => p.error == null).toList()) {
        try {
          await ApiClient.instance.createMovement(
            productId: item.productId,
            type: item.type,
            quantity: item.quantity,
            note: item.note,
            clientRequestId: item.id,
            occurredAt: item.createdAt,
          );
          _pending = _pending.where((p) => p.id != item.id).toList();
          sent++;
        } on ApiException catch (e) {
          if (e.isNetworkError) {
            offline = true;
            break;
          }
          if (e.isUnauthorized) break; // tekrar giriş yapınca devam eder
          _pending = [for (final p in _pending) p.id == item.id ? p.withError(e.message) : p];
          failed++;
        }
      }
    } finally {
      _syncing = false;
      await _saveQueue();
    }

    return SyncResult(sent: sent, failed: failed, offline: offline);
  }

  Future<void> _saveQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, jsonEncode(_pending.map((p) => p.toJson()).toList()));
    notifyListeners();
  }

  static List<T> _decodeList<T>(String? raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>).map((e) => fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return []; // bozuk veri uygulamayı kilitlemesin
    }
  }
}
