class Product {
  final int id;
  final String barcode;
  final String name;
  final String unit;
  final double stock;
  final double minStock;
  final bool isCritical;

  const Product({
    required this.id,
    required this.barcode,
    required this.name,
    required this.unit,
    required this.stock,
    required this.minStock,
    required this.isCritical,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as int,
        barcode: json['barcode'] as String,
        name: json['name'] as String,
        unit: json['unit'] as String,
        stock: (json['stock'] as num).toDouble(),
        minStock: (json['minStock'] as num? ?? 0).toDouble(),
        isCritical: json['isCritical'] as bool? ?? false,
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
