import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../main.dart';
import '../models.dart';
import '../offline/offline_store.dart';
import '../theme.dart';
import 'pending_page.dart';

/// Hareketler sekmesinin filtresi. [type] null = hepsi; [days] 1 = bugün.
typedef MovementFilter = ({MovementType? type, int days});

/// Tüm depodaki hareketler; tip ve döneme göre filtre.
class MovementsTab extends StatefulWidget {
  const MovementsTab({
    super.key,
    required this.refresh,
    required this.filter,
    required this.onOpenProductByBarcode,
    this.loader,
  });

  final ValueNotifier<int> refresh;

  /// Seçili filtre. Özet ekranındaki kartlar da bunu değiştirir (ör. "Bugün çıkış").
  final ValueNotifier<MovementFilter> filter;

  final Future<void> Function(String barcode) onOpenProductByBarcode;

  /// Hareketleri getiren fonksiyon; testlerde sahte veri için. Varsayılan: API.
  final Future<List<MovementListItem>> Function(MovementType? type, int days)? loader;

  @override
  State<MovementsTab> createState() => _MovementsTabState();
}

class _MovementsTabState extends State<MovementsTab> {
  static const _periods = {1: 'Bugün', 7: '7 gün', 30: '30 gün'};

  final _offline = OfflineStore.instance;
  List<MovementListItem> _items = [];
  bool _loading = true;
  String? _error;

  /// Her yüklemede artar; filtre hızla değişince geç gelen eski yanıt yok sayılır.
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_load);
    widget.filter.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_load);
    widget.filter.removeListener(_load);
    super.dispose();
  }

  MovementType? get _type => widget.filter.value.type;
  int get _days => widget.filter.value.days;

  void _setFilter({required MovementType? type, required int days}) =>
      widget.filter.value = (type: type, days: days);

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final seq = ++_requestSeq;
    try {
      final items = await (widget.loader?.call(_type, _days) ??
          ApiClient.instance.getAllMovements(type: _type, days: _days));
      if (!mounted || seq != _requestSeq) return;
      setState(() => _items = items);
      _offline.setOffline(false);
    } on ApiException catch (e) {
      if (!mounted || seq != _requestSeq) return;
      if (e.isUnauthorized) return handleUnauthorized(context);
      if (e.isNetworkError) _offline.setOffline(true);
      setState(() {
        _items = []; // başka filtreye ait eski liste gösterilmesin
        _error = e.isNetworkError ? 'Sunucuya ulaşılamıyor; sunucudaki hareketler gösterilemiyor.' : e.message;
      });
    } finally {
      if (mounted && seq == _requestSeq) setState(() => _loading = false);
    }
  }

  /// Telefonda bekleyen/reddedilen kayıtlardan seçili filtreye uyanlar (en yeni üstte).
  /// Dönem sunucudaki gibi gün başından sayılır: 1 = bugün, 7 = bugün dahil son 7 gün.
  List<PendingMovement> _pendingMatches() {
    final now = DateTime.now();
    final since = DateTime(now.year, now.month, now.day).subtract(Duration(days: _days - 1));
    return _offline.pending
        .where((m) => _type == null || m.type == _type)
        .where((m) => !m.createdAt.isBefore(since))
        .toList()
        .reversed
        .toList();
  }

  Future<void> _openPending() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PendingPage()));
    if (mounted) _load();
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
                  onSelected: (_) => _setFilter(type: t, days: _days),
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
            onSelectionChanged: (s) => _setFilter(type: _type, days: s.first),
          ),
        ),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    // Bekleyen kuyruk değişince (eklendi, gönderildi, reddedildi) liste de güncellensin.
    return ListenableBuilder(listenable: _offline, builder: (context, _) => _buildListContent());
  }

  Widget _buildListContent() {
    final theme = Theme.of(context);
    final pending = _pendingMatches();
    if (_loading && _items.isEmpty && pending.isEmpty) return const Center(child: CircularProgressIndicator());

    // Sunucuya ulaşılamadı ve gösterecek bekleyen kayıt da yok: tam sayfa hata.
    if (_error != null && pending.isEmpty) {
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

    final children = <Widget>[
      if (_error != null)
        Material(
          color: theme.colorScheme.secondaryContainer,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.cloud_off),
            title: Text(_error!),
            trailing: TextButton(onPressed: _load, child: const Text('Tekrar dene')),
          ),
        ),
      if (pending.isNotEmpty) ...[
        _ListHeader('Telefonda bekleyen (${pending.length})'),
        for (final m in pending) ...[
          PendingMovementTile(movement: m, onTap: _openPending),
          const Divider(height: 1),
        ],
        if (_items.isNotEmpty) const _ListHeader('Sunucudaki hareketler'),
      ],
      for (final (i, m) in _items.indexed) ...[
        if (i > 0) const Divider(height: 1),
        MovementTile(movement: m, onTap: () => widget.onOpenProductByBarcode(m.barcode)),
      ],
      if (_items.isEmpty && pending.isEmpty) ...[
        const SizedBox(height: 120),
        const Center(child: Text('Bu dönemde hareket yok.')),
      ],
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 96), children: children),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

/// Henüz sunucuya gitmemiş (ya da sunucunun reddettiği) hareket satırı.
class PendingMovementTile extends StatelessWidget {
  const PendingMovementTile({super.key, required this.movement, this.onTap});

  final PendingMovement movement;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final theme = Theme.of(context);
    final failed = m.error != null;
    final summary = switch (m.type) {
      MovementType.inbound => 'Giriş +${formatQty(m.quantity)} ${m.unit}',
      MovementType.outbound => 'Çıkış -${formatQty(m.quantity)} ${m.unit}',
      MovementType.count => 'Sayım ${formatQty(m.quantity)} ${m.unit}',
    };
    return ListTile(
      leading: MovementIcon(m.type),
      title: Text(m.productName),
      subtitle: Text(
        [
          summary,
          failed ? 'Reddedildi: ${m.error}' : 'Telefonda bekliyor · ${formatDateTime(m.createdAt)}',
        ].join('\n'),
        style: failed ? TextStyle(color: theme.colorScheme.error) : null,
      ),
      isThreeLine: true,
      trailing: Icon(
        failed ? Icons.error_outline : Icons.schedule,
        color: failed ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
        semanticLabel: failed ? 'Reddedildi' : 'Gönderilmeyi bekliyor',
      ),
      onTap: onTap,
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
    return ListTile(
      leading: MovementIcon(m.type),
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
