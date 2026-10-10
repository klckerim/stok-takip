import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../main.dart';
import '../models.dart';

class ProductPage extends StatefulWidget {
  const ProductPage({super.key, required this.product});

  final Product product;

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  static const _uuid = Uuid();

  final _api = ApiClient.instance;
  final _quantity = TextEditingController();
  final _note = TextEditingController();
  late Product _product = widget.product;
  late double _stock = widget.product.stock;
  MovementType _type = MovementType.inbound;
  bool _saving = false;

  List<Movement> _movements = [];
  bool _loadingMovements = true;

  // Aynı kayıt için sabit kalır: ağ hatasından sonra "Kaydet"e tekrar basılırsa
  // sunucu hareketi iki kez yazmaz. Başarılı kayıttan sonra yenilenir.
  String _requestId = _uuid.v4();

  bool get _isCritical => _product.minStock > 0 && _stock <= _product.minStock;

  @override
  void initState() {
    super.initState();
    _loadMovements();
  }

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadMovements() async {
    try {
      final items = await _api.getMovements(_product.id);
      if (mounted) setState(() => _movements = items);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) return handleUnauthorized(context);
    } finally {
      if (mounted) setState(() => _loadingMovements = false);
    }
  }

  double? _parseQuantity() => double.tryParse(_quantity.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final quantity = _parseQuantity();
    final messenger = ScaffoldMessenger.of(context);
    if (quantity == null || quantity < 0 || (quantity == 0 && _type != MovementType.count)) {
      messenger.showSnackBar(const SnackBar(content: Text('Geçerli bir miktar gir.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await _api.createMovement(
        productId: _product.id,
        type: _type,
        quantity: quantity,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        clientRequestId: _requestId,
      );
      if (!mounted) return;
      setState(() {
        _stock = result.newStock;
        _requestId = _uuid.v4();
        _quantity.clear();
        _note.clear();
      });
      FocusScope.of(context).unfocus();
      messenger.showSnackBar(SnackBar(
        content: Text('${_type.label} kaydedildi. Yeni stok: ${formatQty(_stock)} ${_product.unit}'),
      ));
      _loadMovements();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) return handleUnauthorized(context);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Sadece yönetici: kritik seviyeyi değiştir.
  Future<void> _editMinStock() async {
    final controller = TextEditingController(text: formatQty(_product.minStock));
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kritik seviye'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            suffixText: _product.unit,
            helperText: '0 = takip yok',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(double.tryParse(controller.text.trim().replaceAll(',', '.'))),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (value == null || value < 0 || !mounted) return;

    try {
      final updated = await _api.updateProduct(_product, minStock: value);
      if (!mounted) return;
      setState(() {
        _product = updated;
        _stock = updated.stock;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) return handleUnauthorized(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _product;
    final isAdmin = _api.session?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ürün'),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Kritik seviye',
              icon: const Icon(Icons.tune),
              onPressed: _editMinStock,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(p.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(p.barcode, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          Card(
            color: _isCritical ? theme.colorScheme.errorContainer : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('Mevcut stok', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text('${formatQty(_stock)} ${p.unit}', style: theme.textTheme.displaySmall),
                  if (p.minStock > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      _isCritical
                          ? 'Kritik seviyede! (sınır ${formatQty(p.minStock)} ${p.unit})'
                          : 'Kritik seviye: ${formatQty(p.minStock)} ${p.unit}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _isCritical ? theme.colorScheme.onErrorContainer : null,
                        fontWeight: _isCritical ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SegmentedButton<MovementType>(
            segments: [
              for (final t in MovementType.values) ButtonSegment(value: t, label: Text(t.label)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _requestId = _uuid.v4(); // farklı işlem = farklı istek
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _type == MovementType.count ? 'Sayılan miktar (${p.unit})' : 'Miktar (${p.unit})',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Kaydet'),
            ),
          ),
          const SizedBox(height: 32),
          Text('Son hareketler', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._buildMovements(theme),
        ],
      ),
    );
  }

  List<Widget> _buildMovements(ThemeData theme) {
    if (_loadingMovements && _movements.isEmpty) {
      return const [Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))];
    }
    if (_movements.isEmpty) {
      return [Text('Henüz hareket yok.', style: theme.textTheme.bodyMedium)];
    }

    return [
      for (final m in _movements)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            switch (m.type) {
              MovementType.inbound => Icons.south_west,
              MovementType.outbound => Icons.north_east,
              MovementType.count => Icons.fact_check_outlined,
            },
            color: m.quantity < 0 ? theme.colorScheme.error : theme.colorScheme.primary,
          ),
          title: Text(_movementTitle(m)),
          subtitle: Text([
            formatDateTime(m.createdAt),
            m.userName,
            if (m.note != null) m.note!,
          ].join(' · ')),
        ),
    ];
  }

  String _movementTitle(Movement m) {
    final unit = _product.unit;
    switch (m.type) {
      case MovementType.inbound:
        return 'Giriş +${formatQty(m.quantity)} $unit';
      case MovementType.outbound:
        return 'Çıkış ${formatQty(m.quantity)} $unit';
      case MovementType.count:
        final diff = m.quantity >= 0 ? '+${formatQty(m.quantity)}' : formatQty(m.quantity);
        return 'Sayım ${formatQty(m.countedQuantity ?? 0)} $unit (fark $diff)';
    }
  }
}
