import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../main.dart';
import '../models.dart';
import '../offline/offline_store.dart';
import '../theme.dart';
import 'add_product_page.dart';
import 'batch_scan_page.dart';
import 'dashboard_tab.dart';
import 'movements_tab.dart';
import 'pending_page.dart';
import 'product_page.dart';
import 'products_tab.dart';
import 'scan_page.dart';

enum _MenuAction { batchCount, batchIn, batchOut, logout }

/// Uygulamanın kabuğu: alt menü (Özet / Ürünler / Hareketler), barkod okutma düğmesi,
/// raporlar, çevrimdışı şeridi ve bekleyen kayıtların arka planda gönderimi.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _titles = ['Özet', 'Ürünler', 'Hareketler'];

  final _api = ApiClient.instance;
  final _offline = OfflineStore.instance;

  /// Sekmeler bunu dinler; değer artınca verilerini yeniden yükler.
  final _refresh = ValueNotifier<int>(0);
  final _criticalOnly = ValueNotifier<bool>(false);
  final _movementsFilter = ValueNotifier<MovementFilter>((type: null, days: 7));

  int _tab = 0;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Bekleyen kayıt varsa 30 sn'de bir göndermeyi dener.
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_offline.waitingCount > 0) _trySync();
    });
    _trySync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _refresh.dispose();
    _criticalOnly.dispose();
    _movementsFilter.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadAll(); // uygulamaya dönünce tazele
      _trySync();
    }
  }

  void _reloadAll() => _refresh.value++;

  /// Bekleyen kayıtları gönderir; gönderilen olduysa ekranları tazeler.
  Future<void> _trySync() async {
    final result = await _offline.sync();
    if (!mounted || (result.sent == 0 && result.failed == 0)) return;
    final text = '${result.sent} bekleyen kayıt gönderildi'
        '${result.failed > 0 ? ', ${result.failed} kayıt reddedildi' : ''}.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    if (result.sent > 0) _reloadAll();
  }

  // --- Ürün açma ---

  /// [fromScan]: barkod okutularak açıldı; miktar alanı odaklanır.
  /// Ürün ekranı "Kaydet ve sıradakini okut" ile kapanırsa tarama yeniden açılır.
  Future<void> _openProduct(Product product, {bool fromScan = false}) async {
    final scanNext = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProductPage(product: product, autofocusQuantity: fromScan)),
    );
    if (!mounted) return;
    _reloadAll(); // stok değişmiş olabilir
    _trySync();
    if (scanNext == true) await _scan();
  }

  /// Barkoddan ürünü bulup açar. Çevrimdışıysa son bilinen listeden.
  /// [fromScan]: barkod kamerayla/elle okutuldu (listeden dokunulmadı).
  Future<void> _openByBarcode(String barcode, {bool fromScan = false}) async {
    try {
      final product = await _api.getProductByBarcode(barcode);
      if (!mounted) return;
      await _openProduct(product, fromScan: fromScan);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) return handleUnauthorized(context);
      if (e.isNotFound) return _onUnknownBarcode(barcode);
      if (e.isNetworkError) {
        _offline.setOffline(true);
        final cached = _offline.findCached(barcode);
        if (cached != null) return _openProduct(cached, fromScan: fromScan);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Çevrimdışısın ve $barcode cihazdaki listede yok.'),
        ));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Seri sayım / toplu giriş / toplu çıkış.
  Future<void> _startBatch(MovementType mode) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BatchScanPage(mode: mode)));
    if (!mounted) return;
    _reloadAll();
    _trySync();
  }

  Future<void> _scan() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (barcode == null || !mounted) return;
    await _openByBarcode(barcode, fromScan: true);
  }

  /// Barkod sistemde yok: yönetici ise ürün eklemeyi önerir.
  Future<void> _onUnknownBarcode(String barcode) async {
    final isAdmin = _api.session?.isAdmin ?? false;
    if (!isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$barcode kayıtlı değil. Ürün eklemek için yöneticiye bildir.'),
      ));
      return;
    }

    final add = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ürün bulunamadı'),
        content: Text('$barcode barkodlu ürün kayıtlı değil. Şimdi eklemek ister misin?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Ürün ekle')),
        ],
      ),
    );
    if (add != true || !mounted) return;

    final product = await Navigator.of(context).push<Product>(
      MaterialPageRoute(builder: (_) => AddProductPage(barcode: barcode)),
    );
    if (product == null || !mounted) return;
    await _openProduct(product, fromScan: true);
  }

  // --- Raporlar ---

  Future<void> _showReports() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Stok raporu'),
              subtitle: const Text('Tüm ürünler, anlık stok, kritik olanlar işaretli'),
              onTap: () => Navigator.of(ctx).pop('stock'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_vert),
              title: const Text('Hareket raporu'),
              subtitle: const Text('Son 30 günün giriş, çıkış ve sayımları'),
              onTap: () => Navigator.of(ctx).pop('movements'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (choice == 'stock') {
      await _exportReport('/api/reports/stock.xlsx', 'stok-raporu-$today.xlsx');
    } else {
      await _exportReport('/api/reports/movements.xlsx', 'hareketler-$today.xlsx', query: {'days': '30'});
    }
  }

  /// Raporu indirir, geçici dosyaya yazar ve paylaşım menüsünü açar (WhatsApp, Mail, Dosyalar'a kaydet...).
  Future<void> _exportReport(String path, String fileName, {Map<String, String>? query}) async {
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    messenger.showSnackBar(const SnackBar(content: Text('Rapor hazırlanıyor...'), duration: Duration(seconds: 1)));

    try {
      final bytes = await _api.downloadReport(path, query: query);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(ShareParams(
        files: [
          XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
        ],
        // iPad'de paylaşım penceresinin konumu için gerekli.
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) return handleUnauthorized(context);
      messenger.showSnackBar(SnackBar(content: Text(e.isNetworkError ? 'Rapor için sunucu bağlantısı gerekiyor.' : e.message)));
    } on FileSystemException {
      messenger.showSnackBar(const SnackBar(content: Text('Rapor dosyası kaydedilemedi.')));
    }
  }

  // --- Çıkış ---

  Future<void> _logout() async {
    if (_offline.pending.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Gönderilmemiş kayıtlar var'),
          content: Text('${_offline.pending.length} kayıt henüz sunucuya gitmedi. '
              'Cihazda kalırlar ve bir sonraki girişte gönderilirler. Yine de çıkılsın mı?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Çıkış yap')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await handleUnauthorized(context);
  }

  // --- Ekran ---

  Widget _buildStatusBanner() {
    return ListenableBuilder(
      listenable: _offline,
      builder: (context, _) {
        final theme = Theme.of(context);
        final isOffline = _offline.isOffline;
        final waiting = _offline.waitingCount;
        final failed = _offline.failedCount;
        if (!isOffline && waiting == 0 && failed == 0) return const SizedBox.shrink();

        final parts = <String>[
          if (isOffline) 'Çevrimdışı: son bilinen stok gösteriliyor',
          if (waiting > 0) '$waiting kayıt gönderilmeyi bekliyor',
          if (failed > 0) '$failed kayıt reddedildi',
        ];
        final hasQueue = (waiting + failed) > 0;
        return Material(
          color: failed > 0 ? theme.colorScheme.errorContainer : theme.colorScheme.secondaryContainer,
          child: ListTile(
            dense: true,
            leading: Icon(isOffline ? Icons.cloud_off : Icons.cloud_upload_outlined),
            title: Text(parts.join(' · ')),
            trailing: hasQueue ? const Icon(Icons.chevron_right) : null,
            onTap: hasQueue
                ? () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PendingPage()));
                    if (mounted) _reloadAll();
                  }
                : null,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          IconButton(
            tooltip: 'Excel raporu',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _showReports,
          ),
          // Seri işlemler (Özet ekranında da var; özet yüklenemezse buradan ulaşılır) ve oturumu kapatma.
          // Çıkış, rapor ikonunun yanında durup yanlışlıkla basılmasın diye menüde.
          PopupMenuButton<_MenuAction>(
            tooltip: 'Diğer',
            onSelected: (action) => switch (action) {
              _MenuAction.batchCount => _startBatch(MovementType.count),
              _MenuAction.batchIn => _startBatch(MovementType.inbound),
              _MenuAction.batchOut => _startBatch(MovementType.outbound),
              _MenuAction.logout => _logout(),
            },
            itemBuilder: (_) => [
              for (final (action, mode) in const [
                (_MenuAction.batchCount, MovementType.count),
                (_MenuAction.batchIn, MovementType.inbound),
                (_MenuAction.batchOut, MovementType.outbound),
              ])
                PopupMenuItem(
                  value: action,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: MovementIcon(mode),
                    title: Text(BatchScanPage.titleFor(mode)),
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _MenuAction.logout,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout),
                  title: const Text('Çıkış yap'),
                  subtitle: _api.session == null ? null : Text(_api.session!.fullName),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusBanner(),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                DashboardTab(
                  refresh: _refresh,
                  onOpenProduct: _openProduct,
                  onOpenProductByBarcode: _openByBarcode,
                  onShowCritical: () {
                    _criticalOnly.value = true;
                    setState(() => _tab = 1);
                  },
                  onShowMovements: (filter) {
                    _movementsFilter.value = filter;
                    setState(() => _tab = 2);
                  },
                  onStartBatch: _startBatch,
                ),
                ProductsTab(
                  refresh: _refresh,
                  criticalOnly: _criticalOnly,
                  onOpenProduct: _openProduct,
                ),
                MovementsTab(
                  refresh: _refresh,
                  filter: _movementsFilter,
                  onOpenProductByBarcode: _openByBarcode,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Barkod okut'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Özet'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Ürünler'),
          NavigationDestination(icon: Icon(Icons.swap_vert), label: 'Hareketler'),
        ],
      ),
    );
  }
}
