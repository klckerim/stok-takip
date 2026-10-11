import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';

/// Son 28 günün gerçek çıkışları (çubuk) + önümüzdeki 14 günün tahmini (çizgi) ve %90 aralığı (gölge).
/// Paket bağımlılığı olmadan CustomPainter ile çizilir.
class DemandChart extends StatelessWidget {
  const DemandChart({super.key, required this.history, required this.forecast, this.height = 170});

  final List<DemandDay> history;
  final List<DemandForecastDay> forecast;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Grafik içi etiketler büyük yazıda grafiği ezmesin.
    final textScaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant) ??
        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Son ${history.length} günün çıkışları ve ${forecast.length} günlük tahmin grafiği',
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _DemandChartPainter(
                history: history,
                forecast: forecast,
                barColor: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                lineColor: scheme.primary,
                bandColor: scheme.primary.withValues(alpha: 0.16),
                gridColor: scheme.outlineVariant,
                labelStyle: labelStyle,
                textScaler: textScaler,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _Legend(color: scheme.onSurfaceVariant.withValues(alpha: 0.35), label: 'Gerçek çıkış'),
            _Legend(color: scheme.primary, label: 'Tahmin', line: true),
            _Legend(color: scheme.primary.withValues(alpha: 0.16), label: '%90 aralık'),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.line = false});

  final Color color;
  final String label;
  final bool line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 14, height: line ? 3 : 10, color: color),
      const SizedBox(width: 6),
      Text(label, style: theme.textTheme.bodySmall),
    ]);
  }
}

class _DemandChartPainter extends CustomPainter {
  _DemandChartPainter({
    required this.history,
    required this.forecast,
    required this.barColor,
    required this.lineColor,
    required this.bandColor,
    required this.gridColor,
    required this.labelStyle,
    required this.textScaler,
  });

  final List<DemandDay> history;
  final List<DemandForecastDay> forecast;
  final Color barColor;
  final Color lineColor;
  final Color bandColor;
  final Color gridColor;
  final TextStyle labelStyle;
  final TextScaler textScaler;

  TextPainter _text(String s) => TextPainter(
        text: TextSpan(text: s, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();

  String _day(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  @override
  void paint(Canvas canvas, Size size) {
    final n = history.length + forecast.length;
    if (n == 0) return;

    final topLabel = _text('0');
    final top = topLabel.height + 4;
    final bottom = size.height - topLabel.height - 6;
    final chartHeight = math.max(1.0, bottom - top);
    final slot = size.width / n;

    var maxValue = 1.0;
    for (final h in history) {
      maxValue = math.max(maxValue, h.quantity);
    }
    for (final f in forecast) {
      maxValue = math.max(maxValue, f.upper);
    }

    double y(double v) => bottom - (v / maxValue) * chartHeight;
    double centerX(int i) => slot * i + slot / 2;

    // Izgara: tepe ve orta çizgisi, değer etiketiyle.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final fraction in const [0.5, 1.0]) {
      final gy = y(maxValue * fraction);
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
      final label = _text(formatQty((maxValue * fraction).roundToDouble()));
      label.paint(canvas, Offset(0, gy - label.height - 1));
    }
    canvas.drawLine(Offset(0, bottom), Offset(size.width, bottom), grid);

    // Gerçek çıkışlar: çubuk.
    final bar = Paint()..color = barColor;
    for (var i = 0; i < history.length; i++) {
      final v = history[i].quantity;
      if (v <= 0) continue;
      final w = math.max(1.0, slot * 0.7);
      canvas.drawRect(Rect.fromLTRB(centerX(i) - w / 2, y(v), centerX(i) + w / 2, bottom), bar);
    }

    if (forecast.isNotEmpty) {
      final start = history.length;

      // %90 aralık: üst sınırdan ileri, alt sınırdan geri giden kapalı şekil.
      final band = Path()..moveTo(centerX(start), y(forecast.first.upper));
      for (var i = 1; i < forecast.length; i++) {
        band.lineTo(centerX(start + i), y(forecast[i].upper));
      }
      for (var i = forecast.length - 1; i >= 0; i--) {
        band.lineTo(centerX(start + i), y(forecast[i].lower));
      }
      band.close();
      canvas.drawPath(band, Paint()..color = bandColor);

      // Tahmin çizgisi ve noktalar.
      final line = Path()..moveTo(centerX(start), y(forecast.first.forecast));
      for (var i = 1; i < forecast.length; i++) {
        line.lineTo(centerX(start + i), y(forecast[i].forecast));
      }
      final stroke = Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(line, stroke);
      final dot = Paint()..color = lineColor;
      for (var i = 0; i < forecast.length; i++) {
        canvas.drawCircle(Offset(centerX(start + i), y(forecast[i].forecast)), 2, dot);
      }

      // "Bugün" ayracı (kesikli dikey çizgi).
      final todayX = slot * start;
      final dash = Paint()
        ..color = lineColor.withValues(alpha: 0.6)
        ..strokeWidth = 1;
      for (var dy = top; dy < bottom; dy += 6) {
        canvas.drawLine(Offset(todayX, dy), Offset(todayX, math.min(dy + 3, bottom)), dash);
      }
    }

    // Alt etiketler: ilk gün, bugün, son gün. Çakışanlar çizilmez.
    final labels = <(double, String)>[
      if (history.isNotEmpty) (0.0, _day(history.first.date)),
      if (forecast.isNotEmpty) (slot * history.length, 'Bugün'),
      if (forecast.isNotEmpty) (size.width, _day(forecast.last.date)),
    ];
    var lastRight = -double.infinity;
    for (final (x, s) in labels) {
      final tp = _text(s);
      final left = (x - tp.width / 2).clamp(0.0, math.max(0.0, size.width - tp.width)).toDouble();
      if (left < lastRight + 4) continue;
      tp.paint(canvas, Offset(left, bottom + 3));
      lastRight = left + tp.width;
    }
  }

  @override
  bool shouldRepaint(_DemandChartPainter old) =>
      old.history != history ||
      old.forecast != forecast ||
      old.lineColor != lineColor ||
      old.barColor != barColor ||
      old.textScaler != textScaler;
}
