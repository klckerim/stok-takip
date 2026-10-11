import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../main.dart';
import '../models.dart';
import '../widgets/category_field.dart';

/// Okutulan barkod sistemde yoksa yönetici ürünü buradan ekler.
/// Kaydedilen ürünü geri döndürür.
class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key, required this.barcode});

  final String barcode;

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _name = TextEditingController();
  final _minStock = TextEditingController();
  final _initialStock = TextEditingController();
  String _unit = units.first;
  int? _categoryId;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _minStock.dispose();
    _initialStock.dispose();
    super.dispose();
  }

  double _parse(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_name.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Ürün adı gir.')));
      return;
    }
    final minStock = _parse(_minStock);
    final initialStock = _parse(_initialStock);
    if (minStock < 0 || initialStock < 0) {
      messenger.showSnackBar(const SnackBar(content: Text('Miktarlar negatif olamaz.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final product = await ApiClient.instance.createProduct(
        barcode: widget.barcode,
        name: _name.text.trim(),
        unit: _unit,
        minStock: minStock,
        initialStock: initialStock,
        categoryId: _categoryId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(product);
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
      appBar: AppBar(title: const Text('Yeni ürün')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Barkod', border: OutlineInputBorder()),
            child: Text(widget.barcode),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: true,
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
            controller: _initialStock,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Açılış stoğu',
              helperText: 'Şu an depoda kaç tane var? Boş bırakılırsa 0.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _minStock,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Kritik seviye',
              helperText: 'Stok bu değere düşünce uyarı verilir. 0 = takip yok.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Ürünü kaydet'),
            ),
          ),
        ],
      ),
    );
  }
}
