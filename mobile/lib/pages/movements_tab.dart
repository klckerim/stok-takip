import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../main.dart';
import '../models.dart';

/// Tüm depodaki hareketler; tip ve döneme göre filtre.
class MovementsTab extends StatefulWidget {
  const MovementsTab({super.key, required this.refresh, required this.onOpenProductByBarcode});

  final ValueNotifier<int> refresh;
  final Future<void> Function(String barcode) onOpenProductByBarcode;

  @override
  State<MovementsTab> createState() => _MovementsTabState();
}

class _MovementsTabState extends State<MovementsTab> {
  static const _periods = {1: 'Bugün', 7: '7 gün', 30: '30 gün'};

  List<MovementListItem> _items = [];
  MovementType? _type; // null = hepsi
  int _days = 7;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ApiClient.instance.getAllMovements(type: _type, days: _days);
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) return handleUnauthorized(context);
      setState(() => _error = e.isNetworkError ? 'Hareketler için sunucu bağlantısı gerekiyor.' : e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            for (final t in <MovementType?>[null, ...MovementType.values])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(t?.label ?? 'Tümü'),
                  selected: _type == t,
                  onSelected: (_) {
                    setState(() => _type = t);
                    _load();
                  },
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SegmentedButton<int>(
            segments: [
              for (final e in _periods.entries) ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {_days},
            onSelectionChanged: (s) {
              setState(() => _days = s.first);
              _load();
            },
          ),
        ),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_loading && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Tekrar dene')),
          ]),
        ),
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: const [
          SizedBox(height: 120),
          Center(child: Text('Bu dönemde hareket yok.')),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) => MovementTile(
          movement: _items[i],
          onTap: () => widget.onOpenProductByBarcode(_items[i].barcode),
        ),
      ),
    );
  }
}

/// Hareket satırı: ürün adı, hareket özeti, tarih ve kullanıcı.
class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.movement, this.onTap});

  final MovementListItem movement;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final theme = Theme.of(context);
    final negative = m.quantity < 0;
    return ListTile(
      leading: Icon(
        switch (m.type) {
          MovementType.inbound => Icons.south_west,
          MovementType.outbound => Icons.north_east,
          MovementType.count => Icons.fact_check_outlined,
        },
        color: negative ? theme.colorScheme.error : theme.colorScheme.primary,
      ),
      title: Text(m.productName),
      subtitle: Text([
        m.summary,
        '${formatDateTime(m.createdAt)} · ${m.userName}',
        if (m.note != null) m.note!,
      ].join('\n')),
      isThreeLine: true,
      onTap: onTap,
    );
  }
}
