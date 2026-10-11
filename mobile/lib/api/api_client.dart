import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../models.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;

  const ApiException(this.message, {this.statusCode});

  bool get isNotFound => statusCode == 404;
  bool get isUnauthorized => statusCode == 401;

  /// Sunucuya hiç ulaşılamadı (ağ yok, zaman aşımı). Sunucu cevap verdiyse false.
  bool get isNetworkError => statusCode == null;

  @override
  String toString() => message;
}

/// API ile konuşan tek sınıf. Token'ı cihazda saklar.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _timeout = Duration(seconds: 15);
  static const _uuid = Uuid();

  Session? session;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (session != null) 'Authorization': 'Bearer ${session!.token}',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  /// Sunucu ayakta mı? [baseUrl] verilirse o adres denenir (ayar ekranındaki test için).
  Future<bool> checkHealth({String? baseUrl}) async {
    try {
      final res = await http
          .get(Uri.parse('${baseUrl ?? ApiConfig.baseUrl}/health'))
          .timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) {
      session = Session(
        token: token,
        fullName: prefs.getString('fullName') ?? '',
        role: prefs.getString('role') ?? '',
      );
    }
  }

  Future<Session> login(String userName, String password) async {
    final res = await _send(() => http.post(
          _uri('/api/auth/login'),
          headers: _headers,
          body: jsonEncode({'userName': userName, 'password': password}),
        ));
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    session = Session(
      token: json['token'] as String,
      fullName: json['fullName'] as String,
      role: json['role'] as String,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', session!.token);
    await prefs.setString('fullName', session!.fullName);
    await prefs.setString('role', session!.role);
    return session!;
  }

  /// Sadece oturum bilgisini siler; çevrimdışı kuyruk ve ürün önbelleği cihazda kalır.
  Future<void> logout() async {
    session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('fullName');
    await prefs.remove('role');
  }

  Future<List<Product>> getProducts({String? search, bool criticalOnly = false, int? categoryId}) async {
    final query = <String, String>{
      if (search != null && search.isNotEmpty) 'search': search,
      if (criticalOnly) 'criticalOnly': 'true',
      if (categoryId != null) 'categoryId': '$categoryId',
    };
    final res = await _send(() => http.get(_uri('/api/products', query.isEmpty ? null : query), headers: _headers));
    final list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Movement>> getMovements(int productId, {int take = 20}) async {
    final res = await _send(() => http.get(
          _uri('/api/products/$productId/movements', {'take': '$take'}),
          headers: _headers,
        ));
    final list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) => Movement.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Dashboard> getDashboard() async {
    final res = await _send(() => http.get(_uri('/api/dashboard'), headers: _headers));
    return Dashboard.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Tüm depo hareketleri. [type] null = hepsi; [days] 1 = bugün.
  Future<List<MovementListItem>> getAllMovements({MovementType? type, int days = 7, int take = 100}) async {
    final query = <String, String>{
      'days': '$days',
      'take': '$take',
      if (type != null) 'type': type.apiName,
    };
    final res = await _send(() => http.get(_uri('/api/movements', query), headers: _headers));
    final list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) => MovementListItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Sadece Admin.
  Future<Product> createProduct({
    required String barcode,
    required String name,
    required String unit,
    double minStock = 0,
    double initialStock = 0,
    int? categoryId,
  }) async {
    final body = jsonEncode({
      'barcode': barcode,
      'name': name,
      'unit': unit,
      'minStock': minStock,
      'initialStock': initialStock,
      'categoryId': categoryId,
    });
    final res = await _send(() => http.post(_uri('/api/products'), headers: _headers, body: body));
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Sadece Admin. Barkod değişmez; diğer alanlar verilen değerlerle değişir.
  Future<Product> updateProduct(
    int productId, {
    required String name,
    required String unit,
    required double minStock,
    int? categoryId,
  }) async {
    final body = jsonEncode({'name': name, 'unit': unit, 'minStock': minStock, 'categoryId': categoryId});
    final res = await _send(() => http.put(_uri('/api/products/$productId'), headers: _headers, body: body));
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<Category>> getCategories() async {
    final res = await _send(() => http.get(_uri('/api/categories'), headers: _headers));
    final list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Sadece Admin.
  Future<Category> createCategory(String name) async {
    final res = await _send(() => http.post(
          _uri('/api/categories'),
          headers: _headers,
          body: jsonEncode({'name': name}),
        ));
    return Category.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Product> getProductByBarcode(String barcode) async {
    final encoded = Uri.encodeComponent(barcode);
    final res = await _send(() => http.get(_uri('/api/products/barcode/$encoded'), headers: _headers));
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Excel raporunu indirir (ör. '/api/reports/stock.xlsx').
  Future<List<int>> downloadReport(String path, {Map<String, String>? query}) async {
    final res = await _send(() => http.get(_uri(path, query), headers: _headers));
    return res.bodyBytes;
  }

  /// Her kayıt için yeni bir clientRequestId üretilir. Ağ hatasında aynı istek
  /// tekrar gönderilirse sunucu hareketi ikinci kez yazmaz.
  Future<MovementResult> createMovement({
    required int productId,
    required MovementType type,
    required double quantity,
    String? note,
    String? clientRequestId,
    DateTime? occurredAt,
  }) async {
    final body = jsonEncode({
      'productId': productId,
      'type': type.apiName,
      'quantity': quantity,
      'note': note,
      'clientRequestId': clientRequestId ?? _uuid.v4(),
      if (occurredAt != null) 'occurredAtUtc': occurredAt.toUtc().toIso8601String(),
    });
    final res = await _send(() => http.post(_uri('/api/movements'), headers: _headers, body: body));
    return MovementResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(_timeout);
    } on TimeoutException {
      throw const ApiException('Sunucu yanıt vermedi. Bağlantını kontrol et.');
    } on Exception {
      throw const ApiException('Sunucuya bağlanılamadı. API adresini ve ağı kontrol et.');
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    throw ApiException(_errorMessage(res), statusCode: res.statusCode);
  }

  /// API ProblemDetails döner: { title, detail, errors }.
  String _errorMessage(http.Response res) {
    try {
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final errors = json['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
      }
      final title = json['title'] as String?;
      final detail = json['detail'] as String?;
      if (title != null && detail != null) return '$title $detail';
      if (title != null) return title;
    } catch (_) {
      // gövde JSON değil
    }
    return 'İşlem başarısız (HTTP ${res.statusCode}).';
  }
}
