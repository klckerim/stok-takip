import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stok_takip/models.dart';
import 'package:stok_takip/pages/product_page.dart';
import 'package:stok_takip/theme.dart';

void main() {
  const product = Product(
    id: 1,
    barcode: '8690000000011',
    name: 'Koli bandı',
    unit: 'Adet',
    stock: 10,
    minStock: 0,
    isCritical: false,
  );

  testWidgets('Kaydet düğmesi seçili işlemi ve miktarı söyler', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const ProductPage(product: product),
    ));
    await tester.pump();

    expect(find.text('Girişi kaydet'), findsOneWidget);

    await tester.tap(find.text('Çıkış'));
    await tester.pump();
    expect(find.text('Çıkışı kaydet'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '5');
    await tester.pump();
    expect(find.text('Çıkışı kaydet · 5 Adet'), findsOneWidget);

    // Düğme çıkış rengini kullanır (kırmızı/hata rengini değil).
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(of: find.text('Çıkışı kaydet · 5 Adet'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
    );
    expect(button.style?.backgroundColor?.resolve({}), MovementColors.light.outbound);
  });
}
