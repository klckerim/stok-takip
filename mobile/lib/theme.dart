import 'package:flutter/material.dart';

import 'models.dart';

/// Marka renkleri. Giriş ekranı başlığı temadan bağımsız olarak bu iki tonla çizilir.
const brandSeed = Color(0xFF1F6F5C);
const brandDark = Color(0xFF175A4A);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return ThemeData(
    colorSchemeSeed: brandSeed,
    brightness: brightness,
    useMaterial3: true,
    extensions: [dark ? MovementColors.dark : MovementColors.light],
  );
}

/// Hareket tiplerinin anlamsal renkleri. Kırmızı (colorScheme.error) yalnızca hata ve kritik stok içindir;
/// çıkış normal bir işlem olduğu için kendi rengini kullanır.
@immutable
class MovementColors extends ThemeExtension<MovementColors> {
  const MovementColors({
    required this.inbound,
    required this.onInbound,
    required this.outbound,
    required this.onOutbound,
    required this.count,
    required this.onCount,
  });

  final Color inbound;
  final Color onInbound;
  final Color outbound;
  final Color onOutbound;
  final Color count;
  final Color onCount;

  /// Başarılı durum (ör. "sunucu bağlı") için de giriş yeşili kullanılır.
  Color get success => inbound;

  static const light = MovementColors(
    inbound: Color(0xFF2E7D32),
    onInbound: Colors.white,
    outbound: Color(0xFFB45309),
    onOutbound: Colors.white,
    count: Color(0xFF1565C0),
    onCount: Colors.white,
  );

  static const dark = MovementColors(
    inbound: Color(0xFF81C784),
    onInbound: Color(0xFF00390A),
    outbound: Color(0xFFFBBF24),
    onOutbound: Color(0xFF3D2800),
    count: Color(0xFF90CAF9),
    onCount: Color(0xFF00315C),
  );

  static MovementColors of(BuildContext context) =>
      Theme.of(context).extension<MovementColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  Color colorFor(MovementType type) => switch (type) {
        MovementType.inbound => inbound,
        MovementType.outbound => outbound,
        MovementType.count => count,
      };

  Color onColorFor(MovementType type) => switch (type) {
        MovementType.inbound => onInbound,
        MovementType.outbound => onOutbound,
        MovementType.count => onCount,
      };

  @override
  MovementColors copyWith({
    Color? inbound,
    Color? onInbound,
    Color? outbound,
    Color? onOutbound,
    Color? count,
    Color? onCount,
  }) =>
      MovementColors(
        inbound: inbound ?? this.inbound,
        onInbound: onInbound ?? this.onInbound,
        outbound: outbound ?? this.outbound,
        onOutbound: onOutbound ?? this.onOutbound,
        count: count ?? this.count,
        onCount: onCount ?? this.onCount,
      );

  @override
  MovementColors lerp(MovementColors? other, double t) {
    if (other == null) return this;
    return MovementColors(
      inbound: Color.lerp(inbound, other.inbound, t)!,
      onInbound: Color.lerp(onInbound, other.onInbound, t)!,
      outbound: Color.lerp(outbound, other.outbound, t)!,
      onOutbound: Color.lerp(onOutbound, other.onOutbound, t)!,
      count: Color.lerp(count, other.count, t)!,
      onCount: Color.lerp(onCount, other.onCount, t)!,
    );
  }
}

/// Hareket tipinin ikonu. Tüm ekranlarda aynı ikon kullanılsın diye tek yerde.
IconData movementIconData(MovementType type) => switch (type) {
      MovementType.inbound => Icons.move_to_inbox_outlined,
      MovementType.outbound => Icons.outbox_outlined,
      MovementType.count => Icons.fact_check_outlined,
    };

/// Hareket tipinin rengiyle çizilmiş ikonu.
class MovementIcon extends StatelessWidget {
  const MovementIcon(this.type, {super.key, this.size});

  final MovementType type;
  final double? size;

  @override
  Widget build(BuildContext context) => Icon(
        movementIconData(type),
        size: size,
        color: MovementColors.of(context).colorFor(type),
        semanticLabel: type.label,
      );
}
