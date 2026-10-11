import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../main.dart';
import '../models.dart';
import '../offline/offline_store.dart';

/// Ürün listesi: arama, "sadece kritik" filtresi, çevrimdışıyken son bilinen liste.
class ProductsTab extends StatefulWidget {
  const ProductsTab({
    super.key,
    required this.refresh,
    required this.criticalOnly,
    required this.onOpenProduct,
    this.loader,
  });

  /// Değeri değişince liste yeniden yüklenir (ör. hareket kaydedildikten sonra).
  final ValueNotifier<int> refresh;

  /// Özet ekranından "kritik stok"a basınca kabuk bunu true yapar.
  final ValueNotifier<bool> criticalOnly;

  final Future<void> Function(Product product) onOpenProduct;

  /// Ürünleri getiren fonksiyon; testlerde sahte veri için. Varsayılan: API.
  final Future<List<Product>> Function(String search, bool criticalOnly, int? categoryId)? loader;

  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  final _api = ApiClient.instance;
  final _offline = OfflineStore.instance;
  final _search = TextEditingController();

  /// Yazarken arama: son tuştan 300 ms sonra istek atılır.
  Timer? _debounce;

  /// Her yüklemede artar; geç gelen eski yanıt yeni sonucun üstüne yazılmasın diye.
  int _requestSeq = 0;
  List<Product> _products = [];
  List<Category> _categories = [];
  int? _categoryId; // null = tüm kategoriler
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_load);
    widget.criticalOnly.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_load);
    widget.criticalOnly.removeListener(_load);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool get _criticalOnly => widget.criticalOnly.value;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final search = _search.text.trim();
    final seq = ++_requestSeq;
    try {
      final items = await (widget.loader?.call(search, _criticalOnly, _categoryId) ??
          _api.getProducts(search: search, criticalOnly: _criticalOnly, categoryId: _categoryId));
      if (!mounted || seq != _requestSeq) return;
      setState(() => _products = items);
      _offline.setOffline(false);
      if (search.isEmpty && !_criticalOnly && _categoryId == null) await _offline.cacheProducts(items);
      _loadCategories();
    } on ApiException catch (e) {
      if (!mounted || seq != _requestSeq) return;
      if (e.isUnauthorized) return handleUnauthorized(context);
      if (e.isNetworkError) {
        _offline.setOffline(true);
        setState(() => _products = _filterCached(search));
        return;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted && seq == _requestSeq) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    setState(() {}); // temizle düğmesi görünürlüğü
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _loadCategories() async {
    try {
      final items = await _api.getCategories();
      if (mounted) setState(() => _categories = items);
    } on ApiException {
      // Kategori çubuğu gizli kalır.
    }
  }

  /// Çevrimdışıyken son bilinen ürün listesinde arama/filtre.
  List<Product> _filterCached(String search) {
    final s = search.toLowerCase();
    return _offline.cachedProducts
        .where((p) => s.isEmpty || p.name.toLowerCase().contains(s) || p.barcode.contains(s))
        .where((p) => !_criticalOnly || p.isCritical)
        .where((p) => _categoryId == null || p.categoryId == _categoryId)
        .toList();
  }

  void _selectCategory(int? id) {
    setState(() => _categoryId = id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SearchBar(
            controller: _search,
            hintText: 'Ürün adı veya barkod ara',
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            trailing: [
              if (_search.text.isNotEmpty)
                IconButton(
                  tooltip: 'Aramayı temizle',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _debounce?.cancel();
                    _search.clear();
                    _load();
                  },
                ),
            ],
            onChanged: _onSearchChanged,
            onSubmitted: (_) {
              _debounce?.cancel();
              _load();
            },
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              FilterChip(
                avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                label: const Text('Kritik'),
                selected: _criticalOnly,
                onSelected: (v) => widget.criticalOnly.value = v,
              ),
              if (_categories.isNotEmpty) ...[
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Tüm kategoriler'),
                  selected: _categoryId == null,
                  onSelected: (_) => _selectCategory(null),
                ),
                for (final c in _categories)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text('${c.name} (${c.productCount})'),
                      selected: _categoryId == c.id,
                      onSelected: (_) => _selectCategory(c.id),
                    ),
                  ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text('${_products.length} ürün', style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
        Expanded(child: _buildList()),
      ],
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
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          const SizedBox(height: 120),
          Center(child: Text(_criticalOnly ? 'Kritik seviyede ürün yok.' : 'Ürün bulunamadı.')),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _products.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) => ProductTile(
          product: _products[i],
          onTap: () => widget.onOpenProduct(_products[i]),
        ),
      ),
    );
  }
}

/// Listelerde kullanılan ürün satırı. Kritikse kırmızı uyarı ikonu ve stok.
class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, this.onTap});

  final Product product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: p.isCritical ? theme.colorScheme.errorContainer : theme.colorScheme.secondaryContainer,
        child: Icon(
          p.isCritical ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
          color: p.isCritical ? error : theme.colorScheme.onSecondaryContainer,
          size: 20,
        ),
      ),
      title: Text(p.name),
      subtitle: Text([
        p.barcode,
        if (p.categoryName != null) p.categoryName!,
        if (p.isCritical) 'kritik seviye ${formatQty(p.minStock)}',
      ].join(' · ')),
      trailing: Text(
        '${formatQty(p.stock)} ${p.unit}',
        style: theme.textTheme.titleMedium?.copyWith(color: p.isCritical ? error : null),
      ),
      onTap: onTap,
    );
  }
}
