import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../main.dart';
import '../models.dart';
import '../offline/offline_store.dart';

/// Seri işlem: barkodlar art arda okutulur, her okutma ilgili ürünün miktarını 1 artırır.
/// Sonunda tüm kalemler tek seferde kaydedilir.
/// - Sayım: sayılan miktar stok olarak yazılır (fark hareketi).
/// - Giriş / Çıkış: toplam miktar kadar hareket.
/// Sunucuya ulaşılamazsa kalemler çevrimdışı kuyruğa alınır.
class BatchScanPage extends StatefulWidget {
  const BatchScanPage({super.key, required this.mode});

  final MovementType mode;

  static String titleFor(MovementType mode) => switch (mode) {
        MovementType.count => 'Seri sayım',
        MovementType.inbound => 'Toplu giriş',
        MovementType.outbound => 'Toplu çıkış',
      };

  @override
  State<BatchScanPage> createState() => _BatchScanPageState();
}

class _Line {
  _Line(this.barcode);

  final String barcode;
  Product? product;
  double quantity = 0;
  bool looking = false;
  String? problem; // "Kayıtlı değil" vb.

  bool get canSave => product != null && problem == null;
}

class _BatchScanPageState extends State<BatchScanPage> {
  static const _uuid = Uuid();

  /// Aynı barkod kamerada dururken tekrar tekrar sayılmasın.
  static const _sameBarcodeGap = Duration(milliseconds: 1500);

  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.normal);
  final _api = ApiClient.instance;
  final _offline = OfflineStore.instance;
  final _lastSeen = <String, DateTime>{};
  final _lines = <_Line>[];
  bool _saving = false;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _refreshCache();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Okutmalar hızlı eşleşsin diye ürün listesi baştan önbelleğe alınır.
  Future<void> _refreshCache() async {
    try {
      await _offline.cacheProducts(await _api.getProducts());
    } on ApiException {
      // Çevrimdışıysa son bilinen liste kullanılır.
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_paused || _saving) return;
    final now = DateTime.now();
    for (final b in capture.barcodes) {
      final value = b.rawValue;
      if (value == null || value.isEmpty) continue;
      final last = _lastSeen[value];
      if (last != null && now.difference(last) < _sameBarcodeGap) continue;
      _lastSeen[value] = now;
      _addScan(value);
    }
  }

  void _addScan(String barcode) {
    HapticFeedback.mediumImpact();
    final existing = _findLine(barcode);
    setState(() {
      if (existing != null) {
        existing.quantity += 1;
        _lines
          ..remove(existing)
          ..insert(0, existing); // son okutulan en üstte
      } else {
        final line = _Line(barcode)..quantity = 1;
        line.product = _offline.findCached(barcode);
        _lines.insert(0, line);
        if (line.product == null) _lookup(line);
      }
    });
  }

  _Line? _findLine(String barcode) {
    for (final l in _lines) {
      if (l.barcode == barcode) return l;
    }
    return null;
  }

  /// Önbellekte olmayan barkodu sunucuda arar.
  Future<void> _lookup(_Line line) async {
    setState(() => line.looking = true);
    try {
      final product = await _api.getProductByBarcode(line.barcode);
      line.product = product;
    } on ApiException catch (e) {
      line.problem = e.isNotFound
          ? 'Kayıtlı değil, kaydedilmeyecek'
          : e.isNetworkError
              ? 'Çevrimdışı ve cihazdaki listede yok'
              : e.message;
    } finally {
      if (mounted) setState(() => line.looking = false);
    }
  }

  Future<void> _manualEntry() async {
    setState(() => _paused = true);
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Barkodu elle gir'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('Ekle')),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _paused = false);
    if (value != null && value.isNotEmpty) _addScan(value);
  }

  Future<void> _editQuantity(_Line line) async {
    setState(() => _paused = true);
    final controller = TextEditingController(text: formatQty(line.quantity));
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(line.product?.name ?? line.barcode),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: line.product?.unit),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(double.tryParse(controller.text.trim().replaceAll(',', '.'))),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      _paused = false;
      if (value != null && value >= 0) line.quantity = value;
    });
  }

  void _change(_Line line, double delta) {
    setState(() {
      line.quantity = (line.quantity + delta).clamp(0, double.infinity).toDouble();
    });
  }

  List<_Line> get _saveable => _lines
      .where((l) => l.canSave && (l.quantity > 0 || widget.mode == MovementType.count))
      .toList();

  Future<void> _save() async {
    final lines = _saveable;
    if (lines.isEmpty) return;
    setState(() => _paused = true);

    final skipped = _lines.length - lines.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${BatchScanPage.titleFor(widget.mode)} kaydedilsin mi?'),
        content: Text([
          '${lines.length} ürün kaydedilecek.',
          if (widget.mode == MovementType.count)
            'Sayılan miktarlar stok olarak yazılır. Okutulmayan ürünlerin stoğu değişmez.',
          if (skipped > 0) '$skipped kalem (kayıtsız barkod veya 0 miktar) atlanacak.',
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok != true || !mounted) {
      if (mounted) setState(() => _paused = false);
      return;
    }

    setState(() => _saving = true);
    var sent = 0, queued = 0;
    final rejected = <String>[];
    var offline = false;
    final note = BatchScanPage.titleFor(widget.mode);

    for (final line in lines) {
      final product = line.product!;
      final requestId = _uuid.v4();
      final now = DateTime.now();

      Future<void> queue() => _offline.add(PendingMovement(
            id: requestId,
            productId: product.id,
            productName: product.name,
            unit: product.unit,
            type: widget.mode,
            quantity: line.quantity,
            note: note,
            createdAt: now,
          ));

      if (offline) {
        await queue();
        queued++;
        continue;
      }
      try {
        await _api.createMovement(
          productId: product.id,
          type: widget.mode,
          quantity: line.quantity,
          note: note,
          clientRequestId: requestId,
          occurredAt: now,
        );
        sent++;
      } on ApiException catch (e) {
        if (e.isUnauthorized) {
          if (mounted) await handleUnauthorized(context);
          return;
        }
        if (e.isNetworkError) {
          offline = true; // kalanları denemeden kuyruğa al
          await queue();
          queued++;
        } else {
          rejected.add('${product.name}: ${e.message}');
        }
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kayıt sonucu'),
        content: Text([
          if (sent > 0) '$sent ürün kaydedildi.',
          if (queued > 0) '$queued ürün çevrimdışı kuyruğa alındı; bağlantı gelince gönderilecek.',
          if (rejected.isNotEmpty) 'Reddedilenler:\n${rejected.join('\n')}',
        ].join('\n\n')),
        actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Tamam'))],
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kaydedilmedi'),
        content: Text('${_lines.length} kalem okuttun. Kaydetmeden çıkılsın mı?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Devam et')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Çık')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _lines.fold<double>(0, (sum, l) => sum + l.quantity);
    final saveCount = _saveable.length;

    return PopScope(
      canPop: _lines.isEmpty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(BatchScanPage.titleFor(widget.mode)),
          actions: [
            IconButton(tooltip: 'Elle gir', icon: const Icon(Icons.keyboard), onPressed: _manualEntry),
            IconButton(
              tooltip: 'Fener',
              icon: const Icon(Icons.flashlight_on_outlined),
              onPressed: () => _controller.toggleTorch(),
            ),
          ],
        ),
        body: Column(
          children: [
            SizedBox(
              height: 200,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(controller: _controller, onDetect: _onDetect),
                  Center(
                    child: Container(
                      width: 240,
                      height: 110,
                      decoration: BoxDecoration(
                        border: Border.all(color: _paused ? Colors.grey : Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: theme.colorScheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _lines.isEmpty
                    ? 'Barkodları art arda okut. Her okutma miktarı 1 artırır.'
                    : '${_lines.length} kalem · toplam ${formatQty(total)}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: _lines.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _buildLine(_lines[i], theme),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: FilledButton.icon(
              onPressed: saveCount == 0 || _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(saveCount == 0 ? 'Kaydet' : 'Kaydet ($saveCount ürün)'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLine(_Line line, ThemeData theme) {
    final p = line.product;
    final hasProblem = line.problem != null;
    return Dismissible(
      key: ObjectKey(line),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => setState(() => _lines.remove(line)),
      child: ListTile(
        title: Text(
          p?.name ?? line.barcode,
          style: hasProblem ? TextStyle(color: theme.colorScheme.error) : null,
        ),
        subtitle: Text(
          line.looking
              ? 'Aranıyor…'
              : hasProblem
                  ? '${line.barcode} · ${line.problem}'
                  : widget.mode == MovementType.count
                      ? '${line.barcode} · sistemde ${formatQty(p!.stock)} ${p.unit}'
                      : line.barcode,
          style: hasProblem ? TextStyle(color: theme.colorScheme.error) : null,
        ),
        trailing: hasProblem || line.looking
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _change(line, -1)),
                  InkWell(
                    onTap: () => _editQuantity(line),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: Text(
                        '${formatQty(line.quantity)} ${p?.unit ?? ''}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _change(line, 1)),
                ],
              ),
      ),
    );
  }
}
