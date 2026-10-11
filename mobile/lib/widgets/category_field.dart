import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models.dart';

/// Kategori seçimi. Yönetici listeden "Yeni kategori…" seçerek kategori ekleyebilir.
class CategoryField extends StatefulWidget {
  const CategoryField({super.key, required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  State<CategoryField> createState() => _CategoryFieldState();
}

class _CategoryFieldState extends State<CategoryField> {
  static const _newCategory = -1;

  List<Category> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ApiClient.instance.getCategories();
      if (mounted) setState(() => _categories = items);
    } on ApiException {
      // Kategori listesi gelmezse alan "Kategorisiz" olarak kullanılabilir.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni kategori'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'ör. Ambalaj'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('Ekle')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    try {
      final category = await ApiClient.instance.createCategory(name);
      if (!mounted) return;
      setState(() => _categories = [..._categories, category]..sort((a, b) => a.name.compareTo(b.name)));
      widget.onChanged(category.id);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ApiClient.instance.session?.isAdmin ?? false;
    // Seçili kategori listede yoksa (silinmiş vb.) boş göster.
    final value = _categories.any((c) => c.id == widget.value) ? widget.value : null;

    return DropdownButtonFormField<int?>(
      key: ValueKey('category-${_categories.length}-$value'),
      initialValue: value,
      decoration: InputDecoration(
        labelText: 'Kategori',
        border: const OutlineInputBorder(),
        suffixIcon: _loading
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : null,
      ),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('Kategorisiz')),
        for (final c in _categories) DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
        if (isAdmin)
          const DropdownMenuItem<int?>(
            value: _newCategory,
            child: Row(children: [Icon(Icons.add, size: 18), SizedBox(width: 8), Text('Yeni kategori…')]),
          ),
      ],
      onChanged: (v) {
        if (v == _newCategory) {
          _create();
          return;
        }
        widget.onChanged(v);
      },
    );
  }
}
