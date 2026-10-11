import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stok_takip/models.dart';
import 'package:stok_takip/offline/offline_store.dart';

void main() {
  test('özet önbelleği kaydedilip yeniden yüklenince aynı veriyi verir', () async {
    SharedPreferences.setMockInitialValues({});
    final dashboard = Dashboard.fromJson({
      'productCount': 12,
      'criticalCount': 1,
      'todayIn': 3,
      'todayOut': 2,
      'todayCount': 0,
      'criticalProducts': [
        {'id': 1, 'barcode': '8690000000011', 'name': 'Koli bandı', 'unit': 'Adet', 'stock': 2, 'minStock': 5, 'isCritical': true},
      ],
      'lastMovements': [
        {
          'id': 7,
          'productId': 1,
          'barcode': '8690000000011',
          'productName': 'Koli bandı',
          'unit': 'Adet',
          'type': 'Out',
          'quantity': -3,
          'countedQuantity': null,
          'note': null,
          'userName': 'depo',
          'createdAtUtc': '2026-10-11T08:30:00Z',
        },
      ],
    });

    await OfflineStore.instance.cacheDashboard(dashboard);
    await OfflineStore.instance.load(); // diskten tekrar oku

    final cached = OfflineStore.instance.cachedDashboard!;
    expect(cached.data.toJson(), dashboard.toJson());
    expect(cached.data.lastMovements.single.type, MovementType.outbound);
    expect(cached.data.lastMovements.single.createdAt, DateTime.utc(2026, 10, 11, 8, 30).toLocal());
  });
}
