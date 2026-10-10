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

  final _quantity = TextEditingController();
  final _note = TextEditingController();
  late double _stock = widget.product.stock;
  MovementType _type = MovementType.inbound;
  bool _saving = false;

  // Aynı kayıt için sabit kalır: ağ hatasından sonra "Kaydet"e tekrar basılırsa
  // sunucu hareketi iki kez yazmaz. Başarılı kayıttan sonra yenilenir.
  String _requestId = _uuid.v4();

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
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
      final result = await ApiClient.instance.createMovement(
        productId: widget.product.id,
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
      messenger.showSnackBar(SnackBar(
        content: Text('${_type.label} kaydedildi. Yeni stok: ${formatQty(_stock)} ${widget.product.unit}'),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) return handleUnauthorized(context);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.product;

    return Scaffold(
      appBar: AppBar(title: const Text('Ürün')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(p.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(p.barcode, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('Mevcut stok', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text('${formatQty(_stock)} ${p.unit}', style: theme.textTheme.displaySmall),
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
        ],
      ),
    );
  }
}
