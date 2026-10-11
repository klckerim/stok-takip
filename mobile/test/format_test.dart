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
}
