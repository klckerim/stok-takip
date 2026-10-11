import 'package:flutter_test/flutter_test.dart';
import 'package:stok_takip/models.dart';

void main() {
  group('formatQty (Türkçe gösterim)', () {
    test('tam sayılar binlik ayırıcıyla', () {
      expect(formatQty(0), '0');
      expect(formatQty(5), '5');
      expect(formatQty(1250), '1.250');
      expect(formatQty(1234567), '1.234.567');
    });

    test('ondalık virgülle, sondaki sıfırlar atılır', () {
      expect(formatQty(1.5), '1,5');
      expect(formatQty(0.25), '0,25');
      expect(formatQty(12500.125), '12.500,125');
    });

    test('negatif değerler', () {
      expect(formatQty(-3), '-3');
      expect(formatQty(-1250.5), '-1.250,5');
      expect(formatQty(-0.0001), '0'); // yuvarlanınca sıfır: "-0" yazılmaz
    });
  });

  test('formatQtyInput metin alanına geri okunabilir değer üretir', () {
    double parse(String s) => double.parse(s.replaceAll(',', '.'));
    for (final v in [0.0, 5.0, 1.5, 1250.0, 12500.125]) {
      expect(parse(formatQtyInput(v)), v);
    }
    expect(formatQtyInput(1250), '1250');
  });

  test('isMeasuredUnit', () {
    expect(isMeasuredUnit('Kg'), isTrue);
    expect(isMeasuredUnit('Lt'), isTrue);
    expect(isMeasuredUnit('Adet'), isFalse);
  });

  test('formatRate okunur yuvarlar', () {
    expect(formatRate(2.143), '2,1');
    expect(formatRate(0.043), '0,04');
    expect(formatRate(123.4), '123');
    expect(formatRate(1250), '1.250');
  });

  test('formatDaysLeft', () {
    expect(formatDaysLeft(0), 'tükendi');
    expect(formatDaysLeft(0.4), '1 günden az');
    expect(formatDaysLeft(4.7), '~5 gün');
  });

  test('ProductForecast API cevabını okur', () {
    final f = ProductForecast.fromJson({
      'avgDailyOut': 2.143,
      'daysLeft': 4.7,
      'stockoutDateUtc': '2026-10-16T08:00:00Z',
      'suggestedMinStock': 22,
      'windowDays': 30,
      'leadTimeDays': 7,
      'safetyDays': 3,
    });
    expect(f.hasData, isTrue);
    expect(f.endsBeforeResupply, isTrue);
    expect(f.stockoutDate!.isUtc, isFalse); // yerel saate çevrilir

    final empty = ProductForecast.fromJson({
      'avgDailyOut': 0,
      'daysLeft': null,
      'stockoutDateUtc': null,
      'suggestedMinStock': 0,
      'windowDays': 30,
      'leadTimeDays': 7,
      'safetyDays': 3,
    });
    expect(empty.hasData, isFalse);
    expect(empty.endsBeforeResupply, isFalse);
  });

  test('Insights API cevabını okur', () {
    final i = Insights.fromJson({
      'stockouts': [
        {
          'product': {'id': 1, 'barcode': '869', 'name': 'Koli bandı', 'unit': 'Adet', 'stock': 10, 'minStock': 5},
          'avgDailyOut': 2,
          'daysLeft': 5,
          'stockoutDateUtc': '2026-10-16T08:00:00',
          'suggestedMinStock': 20,
        }
      ],
      'anomalies': [
        {
          'movementId': 7,
          'productId': 1,
          'barcode': '869',
          'productName': 'Koli bandı',
          'unit': 'Adet',
          'type': 'Out',
          'quantity': -60,
          'countedQuantity': null,
          'userName': 'Depo Personeli',
          'createdAtUtc': '2026-10-09T11:20:00Z',
          'reason': 'Normalin 6 katı çıkış (ortalama 10 Adet)',
        }
      ],
      'windowDays': 30,
      'leadTimeDays': 7,
    });
    expect(i.stockouts.single.product.name, 'Koli bandı');
    expect(i.anomalies.single.type, MovementType.outbound);
    expect(i.anomalies.single.reason, contains('6 katı'));
  });
}
