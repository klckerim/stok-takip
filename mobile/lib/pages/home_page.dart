import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../main.dart';
import '../models.dart';
import 'add_product_page.dart';
import 'product_page.dart';
import 'scan_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _api = ApiClient.instance;
  final _search = TextEditingController();
  List<Product> _products = [];
  bool _loading = true;
  bool _criticalOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.getProducts(search: _search.text.trim(), criticalOnly: _criticalOnly);
      if (!mounted) return;
      setState(() => _products = items);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        if (mounted) await handleUnauthorized(context);
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scan() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (barcode == null || !mounted) return;

    try {
      final product = await _api.getProductByBarcode(barcode);
      if (!mounted) return;
      await _openProduct(product);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) return handleUnauthorized(context);
      if (e.isNotFound) return _onUnknownBarcode(barcode);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
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
    await _openProduct(product);
  }

  /// Excel raporu seçimi.
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
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on FileSystemException {
      messenger.showSnackBar(const SnackBar(content: Text('Rapor dosyası kaydedilemedi.')));
    }
  }

  Future<void> _openProduct(Product product) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductPage(product: product)));
    if (mounted) _load(); // stok değişmiş olabilir
  }

  @override
  Widget build(BuildContext context) {
    final session = _api.session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok'),
        actions: [
          if (session != null)
            Center(child: Text(session.fullName, style: Theme.of(context).textTheme.bodySmall)),
          IconButton(
            tooltip: 'Excel raporu',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _showReports,
          ),
          IconButton(
            tooltip: 'Çıkış',
            icon: const Icon(Icons.logout),
            onPressed: () => handleUnauthorized(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Ürün adı veya barkod ara',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _search.clear();
                    _load();
                  },
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                label: const Text('Sadece kritik stok'),
                selected: _criticalOnly,
                onSelected: (v) {
                  setState(() => _criticalOnly = v);
                  _load();
                },
              ),
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Barkod okut'),
      ),
    );
  }

  Widget _buildList() {
    if (_loading && _products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Tekrar dene')),
            ],
          ),
        ),
      );
    }
    if (_products.isEmpty) {
      return Center(child: Text(_criticalOnly ? 'Kritik seviyede ürün yok.' : 'Ürün bulunamadı.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _products.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final p = _products[i];
          final error = Theme.of(context).colorScheme.error;
          return ListTile(
            leading: p.isCritical ? Icon(Icons.warning_amber_rounded, color: error) : null,
            title: Text(p.name),
            subtitle: Text(p.isCritical
                ? '${p.barcode} · kritik seviye ${formatQty(p.minStock)}'
                : p.barcode),
            trailing: Text(
              '${formatQty(p.stock)} ${p.unit}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: p.isCritical ? error : null),
            ),
            onTap: () => _openProduct(p),
          );
        },
      ),
    );
  }
}
