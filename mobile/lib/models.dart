class Product {
  final int id;
  final String barcode;
  final String name;
  final String unit;
  final double stock;
  final double minStock;
  final bool isCritical;
  final int? categoryId;
  final String? categoryName;

  const Product({
    required this.id,
    required this.barcode,
    required this.name,
    required this.unit,
    required this.stock,
    required this.minStock,
    required this.isCritical,
    this.categoryId,
    this.categoryName,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as int,
        barcode: json['barcode'] as String,
        name: json['name'] as String,
        unit: json['unit'] as String,
        stock: (json['stock'] as num).toDouble(),
        minStock: (json['minStock'] as num? ?? 0).toDouble(),
        isCritical: json['isCritical'] as bool? ?? false,
        categoryId: json['categoryId'] as int?,
        categoryName: json['categoryName'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'barcode': barcode,
        'name': name,
        'unit': unit,
        'stock': stock,
        'minStock': minStock,
        'isCritical': isCritical,
        'categoryId': categoryId,
        'categoryName': categoryName,
      };
}

class Category {
  final int id;
  final String name;
  final int productCount;

  const Category({required this.id, required this.name, required this.productCount});

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as int,
        name: json['name'] as String,
        productCount: json['productCount'] as int? ?? 0,
      );
}

/// API'deki MovementType ile aynı isimler (JSON'da string olarak gider).
enum MovementType {
  inbound('In', 'Giriş'),
  outbound('Out', 'Çıkış'),
  count('Count', 'Sayım');

  const MovementType(this.apiName, this.label);
  final String apiName;
  final String label;

  static MovementType fromApi(String value) =>
      MovementType.values.firstWhere((t) => t.apiName == value, orElse: () => MovementType.inbound);
}

class Movement {
  final int id;
  final MovementType type;

  /// Stoka etkisi: giriş +, çıkış -, sayımda fark.
  final double quantity;
  final double? countedQuantity;
  final String? note;
  final String userName;
  final DateTime createdAt;

  const Movement({
    required this.id,
    required this.type,
    required this.quantity,
    required this.countedQuantity,
    required this.note,
    required this.userName,
    required this.createdAt,
  });

  factory Movement.fromJson(Map<String, dynamic> json) => Movement(
        id: json['id'] as int,
        type: MovementType.fromApi(json['type'] as String),
        quantity: (json['quantity'] as num).toDouble(),
        countedQuantity: (json['countedQuantity'] as num?)?.toDouble(),
        note: json['note'] as String?,
        userName: json['userName'] as String,
        createdAt: _parseUtc(json['createdAtUtc'] as String),
      );

  /// API tarihi UTC gönderir; sonunda saat dilimi yoksa yine de UTC kabul et.
  static DateTime _parseUtc(String value) {
    final hasZone = value.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(value);
    return DateTime.parse(hasZone ? value : '${value}Z').toLocal();
  }
}

/// Tüm depo hareket listesindeki satır (ürün bilgisiyle).
class MovementListItem {
  final int id;
  final int productId;
  final String barcode;
  final String productName;
  final String unit;
  final MovementType type;
  final double quantity;
  final double? countedQuantity;
  final String? note;
  final String userName;
  final DateTime createdAt;

  const MovementListItem({
    required this.id,
    required this.productId,
    required this.barcode,
    required this.productName,
    required this.unit,
    required this.type,
    required this.quantity,
    required this.countedQuantity,
    required this.note,
    required this.userName,
    required this.createdAt,
  });

  factory MovementListItem.fromJson(Map<String, dynamic> json) => MovementListItem(
        id: json['id'] as int,
        productId: json['productId'] as int,
        barcode: json['barcode'] as String,
        productName: json['productName'] as String,
        unit: json['unit'] as String,
        type: MovementType.fromApi(json['type'] as String),
        quantity: (json['quantity'] as num).toDouble(),
        countedQuantity: (json['countedQuantity'] as num?)?.toDouble(),
        note: json['note'] as String?,
        userName: json['userName'] as String,
        createdAt: Movement._parseUtc(json['createdAtUtc'] as String),
      );

  /// "Giriş +5 Adet", "Çıkış -3 Kg", "Sayım 77 Adet (fark -3)"
  String get summary => describeMovement(type, quantity, countedQuantity, unit);

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'barcode': barcode,
        'productName': productName,
        'unit': unit,
        'type': type.apiName,
        'quantity': quantity,
        'countedQuantity': countedQuantity,
        'note': note,
        'userName': userName,
        'createdAtUtc': createdAt.toUtc().toIso8601String(),
      };
}

class Dashboard {
  final int productCount;
  final int criticalCount;
  final int todayIn;
  final int todayOut;
  final int todayCount;
  final List<Product> criticalProducts;
  final List<MovementListItem> lastMovements;

  const Dashboard({
    required this.productCount,
    required this.criticalCount,
    required this.todayIn,
    required this.todayOut,
    required this.todayCount,
    required this.criticalProducts,
    required this.lastMovements,
  });

  factory Dashboard.fromJson(Map<String, dynamic> json) => Dashboard(
        productCount: json['productCount'] as int,
        criticalCount: json['criticalCount'] as int,
        todayIn: json['todayIn'] as int,
        todayOut: json['todayOut'] as int,
        todayCount: json['todayCount'] as int,
        criticalProducts: (json['criticalProducts'] as List<dynamic>)
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList(),
        lastMovements: (json['lastMovements'] as List<dynamic>)
            .map((e) => MovementListItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'productCount': productCount,
        'criticalCount': criticalCount,
        'todayIn': todayIn,
        'todayOut': todayOut,
        'todayCount': todayCount,
        'criticalProducts': [for (final p in criticalProducts) p.toJson()],
        'lastMovements': [for (final m in lastMovements) m.toJson()],
      };
}

/// Ürünün tüketim tahmini (GET /api/products/{id}/forecast).
/// İstatistik: son [windowDays] günün ortalama günlük çıkışı.
class ProductForecast {
  final double avgDailyOut;

  /// Bu hızla stok kaç gün yeter. Çıkış yoksa null.
  final double? daysLeft;
  final DateTime? stockoutDate;

  /// Günlük çıkış × (tedarik süresi + emniyet payı).
  final double suggestedMinStock;
  final int windowDays;
  final int leadTimeDays;
  final int safetyDays;

  const ProductForecast({
    required this.avgDailyOut,
    required this.daysLeft,
    required this.stockoutDate,
    required this.suggestedMinStock,
    required this.windowDays,
    required this.leadTimeDays,
    required this.safetyDays,
  });

  /// Pencerede hiç çıkış yoksa tahmin yapılamaz.
  bool get hasData => avgDailyOut > 0;

  /// Stok, tedarikçiden yeni mal gelmeden bitebilir.
  bool get endsBeforeResupply => daysLeft != null && daysLeft! <= leadTimeDays;

  factory ProductForecast.fromJson(Map<String, dynamic> json) => ProductForecast(
        avgDailyOut: (json['avgDailyOut'] as num).toDouble(),
        daysLeft: (json['daysLeft'] as num?)?.toDouble(),
        stockoutDate: json['stockoutDateUtc'] == null ? null : Movement._parseUtc(json['stockoutDateUtc'] as String),
        suggestedMinStock: (json['suggestedMinStock'] as num).toDouble(),
        windowDays: json['windowDays'] as int,
        leadTimeDays: json['leadTimeDays'] as int,
        safetyDays: json['safetyDays'] as int,
      );
}

/// Özet ekranındaki "Yakında tükenecek" satırı.
class StockoutForecast {
  final Product product;
  final double avgDailyOut;
  final double daysLeft;
  final DateTime stockoutDate;
  final double suggestedMinStock;

  const StockoutForecast({
    required this.product,
    required this.avgDailyOut,
    required this.daysLeft,
    required this.stockoutDate,
    required this.suggestedMinStock,
  });

  factory StockoutForecast.fromJson(Map<String, dynamic> json) => StockoutForecast(
        product: Product.fromJson(json['product'] as Map<String, dynamic>),
        avgDailyOut: (json['avgDailyOut'] as num).toDouble(),
        daysLeft: (json['daysLeft'] as num).toDouble(),
        stockoutDate: Movement._parseUtc(json['stockoutDateUtc'] as String),
        suggestedMinStock: (json['suggestedMinStock'] as num).toDouble(),
      );
}

/// Özet ekranındaki "İncelenmesi gereken hareketler" satırı: olağan dışı çıkış veya büyük sayım farkı.
class MovementAnomaly {
  final int movementId;
  final int productId;
  final String barcode;
  final String productName;
  final String unit;
  final MovementType type;
  final double quantity;
  final double? countedQuantity;
  final String userName;
  final DateTime createdAt;

  /// Sunucunun açıklaması: "Normalin 6 katı çıkış (ortalama 10 Adet)".
  final String reason;

  const MovementAnomaly({
    required this.movementId,
    required this.productId,
    required this.barcode,
    required this.productName,
    required this.unit,
    required this.type,
    required this.quantity,
    required this.countedQuantity,
    required this.userName,
    required this.createdAt,
    required this.reason,
  });

  factory MovementAnomaly.fromJson(Map<String, dynamic> json) => MovementAnomaly(
        movementId: json['movementId'] as int,
        productId: json['productId'] as int,
        barcode: json['barcode'] as String,
        productName: json['productName'] as String,
        unit: json['unit'] as String,
        type: MovementType.fromApi(json['type'] as String),
        quantity: (json['quantity'] as num).toDouble(),
        countedQuantity: (json['countedQuantity'] as num?)?.toDouble(),
        userName: json['userName'] as String,
        createdAt: Movement._parseUtc(json['createdAtUtc'] as String),
        reason: json['reason'] as String,
      );
}

/// GET /api/insights
class Insights {
  final List<StockoutForecast> stockouts;
  final List<MovementAnomaly> anomalies;
  final int windowDays;
  final int leadTimeDays;

  const Insights({
    required this.stockouts,
    required this.anomalies,
    required this.windowDays,
    required this.leadTimeDays,
  });

  factory Insights.fromJson(Map<String, dynamic> json) => Insights(
        stockouts: (json['stockouts'] as List<dynamic>)
            .map((e) => StockoutForecast.fromJson(e as Map<String, dynamic>))
            .toList(),
        anomalies: (json['anomalies'] as List<dynamic>)
            .map((e) => MovementAnomaly.fromJson(e as Map<String, dynamic>))
            .toList(),
        windowDays: json['windowDays'] as int,
        leadTimeDays: json['leadTimeDays'] as int,
      );
}

/// "~5 gün", "1 günden az", "tükendi".
String formatDaysLeft(double days) {
  if (days <= 0) return 'tükendi';
  if (days < 1) return '1 günden az';
  return '~${days.round()} gün';
}

/// Günlük ortalama gibi oranlar için okunur yuvarlama: 2,143 → 2,1; 0,043 → 0,04; 123,4 → 123.
String formatRate(double value) {
  if (value >= 10) return formatQty(value.roundToDouble());
  if (value >= 0.1) return formatQty((value * 10).round() / 10);
  return formatQty((value * 100).round() / 100);
}

String describeMovement(MovementType type, double quantity, double? countedQuantity, String unit) {
  switch (type) {
    case MovementType.inbound:
      return 'Giriş +${formatQty(quantity)} $unit';
    case MovementType.outbound:
      return 'Çıkış ${formatQty(quantity)} $unit';
    case MovementType.count:
      final diff = quantity >= 0 ? '+${formatQty(quantity)}' : formatQty(quantity);
      return 'Sayım ${formatQty(countedQuantity ?? 0)} $unit (fark $diff)';
  }
}

class MovementResult {
  final double newStock;

  const MovementResult({required this.newStock});

  factory MovementResult.fromJson(Map<String, dynamic> json) =>
      MovementResult(newStock: (json['newStock'] as num).toDouble());
}

class Session {
  final String token;
  final String fullName;
  final String role;

  const Session({required this.token, required this.fullName, required this.role});

  bool get isAdmin => role == 'Admin';
}

const List<String> units = ['Adet', 'Kg', 'Lt', 'Mt', 'Paket', 'Koli', 'Rulo'];

/// Ekranda gösterim için Türkçe miktar: 1.250 / 1,5 / 12.500,25 (en fazla 3 ondalık).
/// Metin alanına yazılacak değer için [formatQtyInput] kullan.
String formatQty(double value) {
  final fixed = value.abs().toStringAsFixed(3);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => '.');
  final frac = parts[1].replaceFirst(RegExp(r'0+$'), '');
  final sign = value < 0 && double.parse(fixed) != 0 ? '-' : '';
  return '$sign$whole${frac.isEmpty ? '' : ',$frac'}';
}

/// Metin alanı için binlik ayırıcısız miktar: 1250 / 1,5. Ayrıştırırken ',' → '.' yapılır.
String formatQtyInput(double value) => formatQty(value).replaceAll('.', '');

/// Tartılan/ölçülen birimler: toplu okutmada her okutma +1 sayılmaz, miktar sorulur.
bool isMeasuredUnit(String unit) => const {'Kg', 'Lt', 'Mt'}.contains(unit);

/// 16.10.2026
String formatDate(DateTime d) => formatDateTime(d).substring(0, 10);

String formatDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}
