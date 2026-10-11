import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../main.dart';
import '../models.dart';
import '../offline/offline_store.dart';
import '../theme.dart';
import 'batch_scan_page.dart';
import 'movements_tab.dart';
import 'products_tab.dart';

/// Özet: ürün ve kritik sayısı, bugünün hareketleri, kritik ürünler, son hareketler.
class DashboardTab extends StatefulWidget {
  const DashboardTab({
    super.key,
    required this.refresh,
    required this.onOpenProduct,
    required this.onOpenProductByBarcode,
    required this.onShowCritical,
    required this.onShowMovements,
    required this.onStartBatch,
    this.loader,
  });

  final ValueNotifier<int> refresh;
  final Future<void> Function(Product product) onOpenProduct;
  final Future<void> Function(String barcode) onOpenProductByBarcode;
  final VoidCallback onShowCritical;
  /// Hareketler sekmesini verilen filtreyle açar (ör. "Bugün çıkış" kartı → çıkış + bugün).
  final void Function(MovementFilter filter) onShowMovements;
  final void Function(MovementType mode) onStartBatch;

  /// Özeti getiren fonksiyon; testlerde sahte veri vermek için. Varsayılan: API.
  final Future<Dashboard> Function()? loader;

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final _offline = OfflineStore.instance;
  Dashboard? _data;
  bool _loading = true;
  String? _error;

  /// Gösterilen veri önbellekten geliyorsa kaydedildiği an; canlı veride null.
  DateTime? _cachedAt;

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
      final data = await (widget.loader ?? ApiClient.instance.getDashboard)();
      if (!mounted) return;
      setState(() {
        _data = data;
        _cachedAt = null;
      });
      _offline.setOffline(false);
      await _offline.cacheDashboard(data);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) return handleUnauthorized(context);
      if (e.isNetworkError) {
        _offline.setOffline(true);
        final cached = _offline.cachedDashboard;
        if (cached != null) {
          setState(() {
            _data = cached.data;
            _cachedAt = cached.savedAt;
          });
          return;
        }
      }
      setState(() => _error = e.isNetworkError ? 'Özet için sunucu bağlantısı gerekiyor.' : e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MovementColors.of(context);
    final data = _data;
    final session = ApiClient.instance.session;
    final cachedAt = _cachedAt;

    if (data == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 40),
            const SizedBox(height: 12),
            Text(_error ?? 'Özet yüklenemedi.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Tekrar dene')),
          ]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Text('Merhaba${session == null ? '' : ', ${session.fullName}'}', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(formatDateTime(DateTime.now()).substring(0, 10), style: theme.textTheme.bodyMedium),
          if (cachedAt != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.history, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Çevrimdışı · son güncelleme ${formatDateTime(cachedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 16),
          Row(children: [
            for (final mode in const [MovementType.count, MovementType.inbound, MovementType.outbound])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: mode == MovementType.outbound ? 0 : 8),
                  child: FilledButton.tonal(
                    onPressed: () => widget.onStartBatch(mode),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: Column(children: [
                      MovementIcon(mode),
                      const SizedBox(height: 4),
                      Text(BatchScanPage.titleFor(mode), textAlign: TextAlign.center),
                    ]),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          _equalHeightRow([
            Expanded(
              child: _StatCard(
                icon: Icons.inventory_2_outlined,
                label: 'Toplam ürün',
                value: '${data.productCount}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.warning_amber_rounded,
                label: 'Kritik stok',
                value: '${data.criticalCount}',
                highlight: data.criticalCount > 0,
                onTap: widget.onShowCritical,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _equalHeightRow([
            Expanded(
              child: _StatCard(
                icon: movementIconData(MovementType.inbound),
                iconColor: colors.inbound,
                label: 'Bugün giriş',
                value: '${data.todayIn}',
                onTap: () => widget.onShowMovements((type: MovementType.inbound, days: 1)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: movementIconData(MovementType.outbound),
                iconColor: colors.outbound,
                label: 'Bugün çıkış',
                value: '${data.todayOut}',
                onTap: () => widget.onShowMovements((type: MovementType.outbound, days: 1)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: movementIconData(MovementType.count),
                iconColor: colors.count,
                label: 'Bugün sayım',
                value: '${data.todayCount}',
                onTap: () => widget.onShowMovements((type: MovementType.count, days: 1)),
              ),
            ),
          ]),
          if (data.criticalProducts.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionHeader(title: 'Kritik ürünler', action: 'Tümü', onAction: widget.onShowCritical),
            Card(
              margin: EdgeInsets.zero,
              child: Column(children: [
                for (final p in data.criticalProducts)
                  ProductTile(product: p, onTap: () => widget.onOpenProduct(p)),
              ]),
            ),
          ],
          const SizedBox(height: 24),
          _SectionHeader(
            title: 'Son hareketler',
            action: 'Tümü',
            onAction: () => widget.onShowMovements((type: null, days: 7)),
          ),
          if (data.lastMovements.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Henüz hareket yok.'))
          else
            Card(
              margin: EdgeInsets.zero,
              child: Column(children: [
                for (final m in data.lastMovements)
                  MovementTile(movement: m, onTap: () => widget.onOpenProductByBarcode(m.barcode)),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Kartlar yan yana aynı yükseklikte dursun (büyük yazıda biri iki satıra kayınca da).
Widget _equalHeightRow(List<Widget> children) => IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.highlight = false,
    this.onTap,
  });

  final IconData icon;
  final Color? iconColor;
  final String label;
  final String value;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = highlight ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSurface;
    return Card(
      margin: EdgeInsets.zero,
      color: highlight ? theme.colorScheme.errorContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: highlight ? fg : (iconColor ?? fg)),
              const SizedBox(height: 8),
              // Sayı asla bölünmesin ("1032" → "10/32"); sığmazsa küçülür.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: theme.textTheme.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
                ),
              ),
              Text(label, style: theme.textTheme.bodySmall?.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
      ]),
    );
  }
}
