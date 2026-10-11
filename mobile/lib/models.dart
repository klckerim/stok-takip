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

String formatQty(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(3);

String formatDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}
