import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stok_takip/models.dart';
import 'package:stok_takip/offline/offline_store.dart';
import 'package:stok_takip/pages/login_page.dart';
import 'package:stok_takip/pages/movements_tab.dart';
import 'package:stok_takip/pages/products_tab.dart';
import 'package:stok_takip/theme.dart';

Widget _app(Widget body) => MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: body));

Product _product(String name) =>
    Product(id: name.hashCode, barcode: '869$name', name: name, unit: 'Adet', stock: 1, minStock: 0, isCritical: false);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OfflineStore.instance.load();
  });

  group('Hareketler sekmesi', () {
    PendingMovement pending(String id, MovementType type, DateTime at, {String? error}) => PendingMovement(
          id: id,
          productId: 1,
          productName: 'Ürün $id',
          unit: 'Adet',
          type: type,
          quantity: 5,
          note: null,
          createdAt: at,
          error: error,
        );

    testWidgets('telefonda bekleyen kayıtlar filtreye göre listenin üstünde', (tester) async {
      final now = DateTime.now();
      await OfflineStore.instance.add(pending('bugün-giriş', MovementType.inbound, now));
      await OfflineStore.instance.add(pending('eski-giriş', MovementType.inbound, now.subtract(const Duration(days: 10))));
      await OfflineStore.instance.add(pending('bugün-çıkış', MovementType.outbound, now, error: 'Yetersiz stok'));

      final filter = ValueNotifier<MovementFilter>((type: MovementType.inbound, days: 7));
      await tester.pumpWidget(_app(MovementsTab(
        refresh: ValueNotifier(0),
        filter: filter,
        onOpenProductByBarcode: (_) async {},
        loader: (_, __) async => [],
      )));
      await tester.pump();

      expect(find.text('Telefonda bekleyen (1)'), findsOneWidget);
      expect(find.text('Ürün bugün-giriş'), findsOneWidget);
      expect(find.text('Ürün eski-giriş'), findsNothing); // 7 günden eski
      expect(find.text('Ürün bugün-çıkış'), findsNothing); // tip farklı

      filter.value = (type: null, days: 30);
      await tester.pump();
      expect(find.text('Telefonda bekleyen (3)'), findsOneWidget);
      expect(find.textContaining('Reddedildi: Yetersiz stok'), findsOneWidget);

      // Kuyruk değişince liste kendiliğinden güncellenir (ör. arka planda gönderildi).
      await OfflineStore.instance.remove('bugün-giriş');
      await tester.pump();
      expect(find.text('Telefonda bekleyen (2)'), findsOneWidget);
    });
  });

  group('Ürün arama', () {
    testWidgets('yazarken 300 ms sonra arar, her tuşta değil', (tester) async {
      final searches = <String>[];
      await tester.pumpWidget(_app(ProductsTab(
        refresh: ValueNotifier(0),
        criticalOnly: ValueNotifier(false),
        onOpenProduct: (_) async {},
        loader: (search, _, __) async {
          searches.add(search);
          return [_product(search.isEmpty ? 'Hepsi' : search)];
        },
      )));
      await tester.pump();
      expect(searches, ['']); // ilk yükleme

      await tester.enterText(find.byType(TextField), 'k');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'ko');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'kol');
      await tester.pump(const Duration(milliseconds: 299));
      expect(searches, ['']); // henüz istek yok

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(searches, ['', 'kol']);
      expect(find.text('kol'), findsWidgets);
    });

    testWidgets('geç gelen eski yanıt yeni sonucun üstüne yazılmaz', (tester) async {
      final slow = Completer<List<Product>>();
      await tester.pumpWidget(_app(ProductsTab(
        refresh: ValueNotifier(0),
        criticalOnly: ValueNotifier(false),
        onOpenProduct: (_) async {},
        loader: (search, _, __) async => search == 'eski' ? slow.future : [_product('Yeni sonuç')],
      )));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'eski');
      await tester.pump(const Duration(milliseconds: 300)); // 'eski' isteği gitti, yanıt gecikiyor
      await tester.enterText(find.byType(TextField), 'yeni');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Yeni sonuç'), findsOneWidget);

      slow.complete([_product('Eski sonuç')]);
      await tester.pumpAndSettle(); // eski yanıt tamamen işlensin
      expect(find.text('Eski sonuç'), findsNothing);
      expect(find.text('Yeni sonuç'), findsOneWidget);
    });
  });

  testWidgets('giriş ekranında "Giriş yap" yalnızca düğmede', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: const LoginPage()));
    await tester.pump(const Duration(seconds: 5)); // sunucu kontrolünün zaman aşımı
    expect(find.text('Hoş geldin'), findsOneWidget);
    expect(find.text('Giriş yap'), findsOneWidget);
  });
}
