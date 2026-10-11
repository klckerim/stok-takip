import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stok_takip/models.dart';
import 'package:stok_takip/offline/offline_store.dart';
import 'package:stok_takip/pages/dashboard_tab.dart';
import 'package:stok_takip/pages/login_page.dart';
import 'package:stok_takip/pages/pending_page.dart';
import 'package:stok_takip/pages/product_page.dart';
import 'package:stok_takip/theme.dart';

/// Büyük yazı boyutunda (erişilebilirlik ayarı) ekranlarda taşma olmamalı.
/// Test fontu her harfi kare çizip gerçeğinden ~2 kat geniş ölçtüğü için SDK'daki Roboto yüklenir;
/// bulunamazsa testler atlanır.
void main() {
  final fontsDir = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final hasFonts = File('$fontsDir/Roboto-Regular.ttf').existsSync();

  setUpAll(() async {
    if (!hasFonts) return;
    final loader = FontLoader('Roboto');
    for (final w in ['Regular', 'Medium', 'Bold']) {
      final bytes = File('$fontsDir/Roboto-$w.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  const product = Product(
    id: 1,
    barcode: '8690000000011',
    name: 'Streç film 50 cm x 300 m şeffaf',
    unit: 'Paket',
    stock: 12500.5,
    minStock: 20000,
    isCritical: true,
    categoryName: 'Ambalaj malzemeleri',
  );

  final dashboard = Dashboard(
    productCount: 1250,
    criticalCount: 12,
    todayIn: 148,
    todayOut: 1032,
    todayCount: 7,
    criticalProducts: const [product],
    lastMovements: [
      MovementListItem(
        id: 1,
        productId: 1,
        barcode: product.barcode,
        productName: product.name,
        unit: product.unit,
        type: MovementType.count,
        quantity: -12.5,
        countedQuantity: 12488,
        note: 'Raf B3 sayımı',
        userName: 'Depo Personeli',
        createdAt: DateTime(2026, 10, 11, 9, 30),
      ),
    ],
  );

  Future<void> pumpScaled(WidgetTester tester, double scale, Widget home) async {
    tester.view.physicalSize = const Size(360, 640); // küçük Android telefon
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    ));
    await tester.pump();
  }

  for (final scale in [1.0, 1.5, 2.0]) {
    group('yazı boyutu ${scale}x', () {
      testWidgets('Ürün ekranı', (tester) async {
        await pumpScaled(tester, scale, const ProductPage(product: product));
        final list = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(find.text('Sayım'), 100, scrollable: list);
        await tester.tap(find.text('Sayım'));
        await tester.scrollUntilVisible(find.text('+50'), 100, scrollable: list);
        await tester.enterText(find.byType(TextField).first, '12488');
        await tester.pump();
        expect(find.textContaining('Sayımı kaydet'), findsOneWidget);
      }, skip: !hasFonts);

      testWidgets('Özet ekranı', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await pumpScaled(
          tester,
          scale,
          Scaffold(
            body: DashboardTab(
              refresh: ValueNotifier(0),
              loader: () async => dashboard,
              onOpenProduct: (_) async {},
              onOpenProductByBarcode: (_) async {},
              onShowCritical: () {},
              onShowMovements: (_) {},
              onStartBatch: (_) {},
            ),
          ),
        );
        await tester.pump();
        // Sayılar bölünmemeli: "1032" tek satır kalmalı ("10" / "32" değil).
        final oneLine = tester.getSize(find.text('7')).height;
        expect(tester.getSize(find.text('1032')).height, lessThanOrEqualTo(oneLine));
        expect(tester.getSize(find.text('1250')).height, lessThanOrEqualTo(oneLine));
      }, skip: !hasFonts);

      testWidgets('Giriş ekranı', (tester) async {
        await pumpScaled(tester, scale, const LoginPage());
        await tester.pump(const Duration(seconds: 5)); // sunucu kontrolünün zaman aşımı
        expect(find.text('Şifre'), findsOneWidget);
      }, skip: !hasFonts);

      testWidgets('Bekleyen kayıtlar', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await OfflineStore.instance.load();
        await OfflineStore.instance.add(PendingMovement(
          id: 'a',
          productId: 1,
          productName: product.name,
          unit: product.unit,
          type: MovementType.outbound,
          quantity: 1250.5,
          note: null,
          createdAt: DateTime(2026, 10, 11, 9, 30),
        ));
        await pumpScaled(tester, scale, const PendingPage());
        expect(find.textContaining('Telefonda bekliyor'), findsOneWidget);
        await OfflineStore.instance.remove('a');
      }, skip: !hasFonts);
    });
  }
}
