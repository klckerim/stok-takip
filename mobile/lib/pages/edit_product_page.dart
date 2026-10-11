import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../main.dart';
import '../models.dart';
import '../widgets/category_field.dart';

/// Yönetici: ürün adı, birim, kategori ve kritik seviye düzenleme. Güncel ürünü geri döndürür.
class EditProductPage extends StatefulWidget {
  const EditProductPage({super.key, required this.product});

  final Product product;

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  late final _name = TextEditingController(text: widget.product.name);
  late final _minStock = TextEditingController(text: formatQty(widget.product.minStock));
  late String _unit = units.contains(widget.product.unit) ? widget.product.unit : units.first;
  late int? _categoryId = widget.product.categoryId;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _minStock.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final minStock = double.tryParse(_minStock.text.trim().replaceAll(',', '.')) ?? 0;
    if (_name.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Ürün adı gir.')));
      return;
    }
    if (minStock < 0) {
      messenger.showSnackBar(const SnackBar(content: Text('Kritik seviye negatif olamaz.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = await ApiClient.instance.updateProduct(
        widget.product.id,
        name: _name.text.trim(),
        unit: _unit,
        minStock: minStock,
        categoryId: _categoryId,
      );
      if (mounted) Navigator.of(context).pop(updated);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Ürünü düzenle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Barkod', border: OutlineInputBorder()),
            child: Text(widget.product.barcode),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Ürün adı', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _unit,
            decoration: const InputDecoration(labelText: 'Birim', border: OutlineInputBorder()),
            items: [for (final u in units) DropdownMenuItem(value: u, child: Text(u))],
            onChanged: (v) => setState(() => _unit = v ?? _unit),
          ),
          const SizedBox(height: 12),
          CategoryField(value: _categoryId, onChanged: (v) => setState(() => _categoryId = v)),
          const SizedBox(height: 12),
          TextField(
            controller: _minStock,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Kritik seviye',
              suffixText: _unit,
              helperText: 'Stok bu değere düşünce uyarı verilir. 0 = takip yok.',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Kaydet')),
          ),
        ],
      ),
    );
  }
}
