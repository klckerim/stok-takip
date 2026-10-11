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
/// bulunamazsa testler atlanır. CI'da (CI=true) atlanmak yerine kırmızı olur: aksi halde testler hiç
/// çalışmadığı halde yeşil görünürdü.
void main() {
  final fontsDir = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final hasFonts = File('$fontsDir/Roboto-Regular.ttf').existsSync();

  test('CI ortamında Roboto bulunur (yazı boyutu testleri atlanmasın)', () {
    expect(hasFonts, isTrue, reason: '$fontsDir altında Roboto-Regular.ttf yok');
  }, skip: Platform.environment['CI'] != 'true');

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

  final insights = Insights(
    stockouts: [
      StockoutForecast(
        product: product,
        avgDailyOut: 1250.5,
        daysLeft: 3.2,
        stockoutDate: DateTime(2026, 10, 14, 12),
        suggestedMinStock: 12505,
      ),
    ],
    anomalies: [
      MovementAnomaly(
        movementId: 2,
        productId: 1,
        barcode: product.barcode,
        productName: product.name,
        unit: product.unit,
        type: MovementType.outbound,
        quantity: -7500,
        countedQuantity: null,
        userName: 'Depo Personeli',
        createdAt: DateTime(2026, 10, 10, 14, 20),
        reason: 'Normalin 6 katı çıkış (ortalama 1.250,5 Paket)',
      ),
    ],
    windowDays: 30,
    leadTimeDays: 7,
  );

  final forecast = ProductForecast(
    avgDailyOut: 1250.5,
    daysLeft: 3.2,
    stockoutDate: DateTime(2026, 10, 14, 12),
    suggestedMinStock: 12505,
    windowDays: 30,
    leadTimeDays: 7,
    safetyDays: 3,
  );

  final demand = DemandForecast(
    available: true,
    reason: null,
    history: [
      for (var i = 0; i < 28; i++)
        DemandDay(DateTime(2026, 9, 13).add(Duration(days: i)), i % 7 == 0 ? 0.0 : 1100.0 + (i % 5) * 120),
    ],
    forecast: [
      for (var i = 0; i < 14; i++)
        DemandForecastDay(DateTime(2026, 10, 11).add(Duration(days: i)), 1250.5, 900, 1600),
    ],
    total: 15200,
    totalLower: 13100,
    totalUpper: 17300,
    stockoutDate: DateTime(2026, 10, 20),
    model: const DemandModelInfo(
      trained: true,
      reason: null,
      algorithm: 'ML.NET LbfgsPoissonRegression',
      trainedAt: null,
      trainingRows: 12345,
      productCount: 10,
      historyDays: 120,
      confidenceLevel: 0.9,
      calibrated: true,
      testMae: 12.85,
      baselineMae: 19.9,
      dailyCoverage: 0.82,
      totalHits: 9,
      totalCount: 10,
      usesDemoData: true,
    ),
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
        await pumpScaled(
          tester,
          scale,
          ProductPage(
            product: product,
            forecastLoader: (_) async => forecast,
            demandLoader: (_) async => demand,
          ),
        );
        await tester.pump();
        final list = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(find.text('Sayım'), 100, scrollable: list);
        await tester.tap(find.text('Sayım'));
        await tester.scrollUntilVisible(find.text('+50'), 100, scrollable: list);
        await tester.enterText(find.byType(TextField).first, '12488');
        await tester.pump();
        expect(find.textContaining('Sayımı kaydet'), findsOneWidget);
        // Analiz kartları formun altında; grafik ve açıklamalar taşmadan çizilmeli.
        await tester.scrollUntilVisible(find.text('Tüketim tahmini'), 100, scrollable: list);
        await tester.scrollUntilVisible(find.text('Talep tahmini · ML'), 100, scrollable: list);
        await tester.scrollUntilVisible(find.textContaining('sentetik'), 100, scrollable: list);
        expect(find.textContaining('%35 daha iyi'), findsOneWidget);
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
              insightsLoader: () async => insights,
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
        // Tahmin bölümleri de taşmadan çizilmeli.
        final list = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(find.text('Yakında tükenecek'), 100, scrollable: list);
        await tester.scrollUntilVisible(find.text('İncelenmesi gereken hareketler'), 100, scrollable: list);
        expect(find.textContaining('6 katı', findRichText: true), findsOneWidget);
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
