class Product {
  final int id;
  final String barcode;
  final String name;
  final String unit;
  final double stock;

  const Product({
    required this.id,
    required this.barcode,
    required this.name,
    required this.unit,
    required this.stock,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as int,
        barcode: json['barcode'] as String,
        name: json['name'] as String,
        unit: json['unit'] as String,
        stock: (json['stock'] as num).toDouble(),
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
}

String formatQty(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(3);
