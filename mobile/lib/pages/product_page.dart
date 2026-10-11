import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../main.dart';
import '../models.dart';
import '../offline/offline_store.dart';
import '../theme.dart';
import 'edit_product_page.dart';

/// Ürün ekranı: stok, tüketim tahmini, giriş/çıkış/sayım kaydı, son hareketler.
/// "Kaydet ve sıradakini okut" ile kaydedilirse `true` döndürür; çağıran taramayı yeniden açar.
class ProductPage extends StatefulWidget {
  const ProductPage({super.key, required this.product, this.autofocusQuantity = false, this.forecastLoader});

  final Product product;

  /// Barkod okutularak açıldıysa miktar alanı odaklanır (bir dokunuş daha az).
  final bool autofocusQuantity;

  /// Tahmini getiren fonksiyon; testlerde sahte veri için. Varsayılan: API.
  final Future<ProductForecast> Function(int productId)? forecastLoader;

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  static const _uuid = Uuid();

  /// Uygulama açık kaldığı sürece son seçilen işlem tipi hatırlanır
  /// (personel genelde art arda aynı işlemi yapar: ör. bir dizi çıkış).
  static MovementType _lastType = MovementType.inbound;

  final _api = ApiClient.instance;
  final _quantity = TextEditingController();
  final _note = TextEditingController();
  late Product _product = widget.product;
  late double _stock = widget.product.stock;
  MovementType _type = _lastType;
  bool _saving = false;

  /// Bu ekranda çevrimdışı kayıt yapıldı; gösterilen stok tahmini.
  bool _pendingOffline = false;

  List<Movement> _movements = [];
  bool _loadingMovements = true;

  /// Tüketim tahmini. Yüklenemezse (çevrimdışı, eski sunucu) null: kart görünmez.
  ProductForecast? _forecast;
  bool _applyingMinStock = false;

  // Aynı kayıt için sabit kalır: ağ hatasından sonra "Kaydet"e tekrar basılırsa
  // sunucu hareketi iki kez yazmaz. Başarılı kayıttan sonra yenilenir.
  String _requestId = _uuid.v4();

  bool get _isCritical => _product.minStock > 0 && _stock <= _product.minStock;

  @override
  void initState() {
    super.initState();
    _quantity.addListener(_onQuantityChanged);
    _loadMovements();
    _loadForecast();
  }

  // Kaydet etiketi, stok uyarısı ve sayım farkı girilen miktara göre güncellenir.
  void _onQuantityChanged() => setState(() {});

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

  Future<void> _loadForecast() async {
    try {
      final f = await (widget.forecastLoader ?? _api.getProductForecast)(_product.id);
      if (mounted) setState(() => _forecast = f);
    } catch (_) {
      // Ek bilgi; yüklenemezse kart gizli kalır.
    }
  }

  /// Sadece yönetici: önerilen kritik seviyeyi tek dokunuşla uygula.
  Future<void> _applySuggestedMinStock(double value) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _applyingMinStock = true);
    try {
      final updated = await _api.updateProduct(
        _product.id,
        name: _product.name,
        unit: _product.unit,
        minStock: value,
        categoryId: _product.categoryId,
      );
      if (!mounted) return;
      setState(() => _product = updated);
      messenger.showSnackBar(SnackBar(
        content: Text('Kritik seviye ${formatQty(value)} ${updated.unit} olarak kaydedildi.'),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) return handleUnauthorized(context);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _applyingMinStock = false);
    }
  }

  /// Hızlı miktar düğmeleri: mevcut değerin üstüne ekler.
  void _addToQuantity(double step) {
    final current = _parseQuantity() ?? 0;
    _quantity.text = formatQtyInput(current + step);
  }

  double? _parseQuantity() => double.tryParse(_quantity.text.trim().replaceAll(',', '.'));

  /// [scanNext]: kayıt (çevrimiçi ya da kuyruğa) başarılıysa ekranı kapatıp sıradaki barkodu okut.
  Future<void> _save({bool scanNext = false}) async {
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
      if (scanNext) {
        Navigator.of(context).pop(true);
        return;
      }
      _loadMovements();
      _loadForecast();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) return handleUnauthorized(context);
      if (e.isNetworkError) {
        await _saveOffline(quantity, messenger);
        if (scanNext && mounted) Navigator.of(context).pop(true);
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Sunucuya ulaşılamadı: hareketi cihazdaki kuyruğa yaz, bağlantı gelince gönderilsin.
  /// Aynı _requestId kullanıldığı için, istek aslında sunucuya ulaşmışsa bile ikinci kez yazılmaz.
  Future<void> _saveOffline(double quantity, ScaffoldMessengerState messenger) async {
    await OfflineStore.instance.add(PendingMovement(
      id: _requestId,
      productId: _product.id,
      productName: _product.name,
      unit: _product.unit,
      type: _type,
      quantity: quantity,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      createdAt: DateTime.now(),
    ));
    if (!mounted) return;

    setState(() {
      // Tahmini stok; kesin değer gönderim sonrası sunucudan gelir.
      _stock = switch (_type) {
        MovementType.inbound => _stock + quantity,
        MovementType.outbound => _stock - quantity,
        MovementType.count => quantity,
      };
      _pendingOffline = true;
      _requestId = _uuid.v4();
      _quantity.clear();
      _note.clear();
    });
    FocusScope.of(context).unfocus();
    messenger.showSnackBar(const SnackBar(
      content: Text('Çevrimdışı: kayıt telefonda saklandı, bağlantı gelince gönderilecek.'),
    ));
  }

  /// Sadece yönetici: ürün bilgilerini düzenle.
  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<Product>(
      MaterialPageRoute(builder: (_) => EditProductPage(product: _product)),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _product = updated;
      _stock = updated.stock;
    });
    _loadForecast();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _product;
    final isAdmin = _api.session?.isAdmin ?? false;
    final colors = MovementColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ürün'),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Düzenle',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
        ],
      ),
      // Kaydet düğmeleri listenin dışında, altta sabit: klavye açıkken de görünür kalır.
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(p.name, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  p.categoryName == null ? p.barcode : '${p.barcode} · ${p.categoryName}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                _buildStockCard(theme),
                if (_forecast != null) ...[
                  const SizedBox(height: 8),
                  _buildForecastCard(theme, _forecast!, isAdmin),
                ],
                const SizedBox(height: 24),
                SegmentedButton<MovementType>(
                  segments: [
                    for (final t in MovementType.values)
                      ButtonSegment(value: t, icon: Icon(movementIconData(t)), label: Text(t.label)),
                  ],
                  selected: {_type},
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: colors.colorFor(_type),
                    selectedForegroundColor: colors.onColorFor(_type),
                  ),
                  onSelectionChanged: (s) => setState(() {
                    _type = _lastType = s.first;
                    _requestId = _uuid.v4(); // farklı işlem = farklı istek
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _quantity,
                  autofocus: widget.autofocusQuantity,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _type == MovementType.count ? 'Sayılan miktar (${p.unit})' : 'Miktar (${p.unit})',
                    border: const OutlineInputBorder(),
                    errorText: _stockWarning(p.unit),
                    errorMaxLines: 3,
                    helperText: _countDiffHint(p.unit),
                    helperMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final step in const [1, 5, 10, 50])
                      ActionChip(label: Text('+$step'), onPressed: () => _addToQuantity(step.toDouble())),
                    ActionChip(
                      avatar: const Icon(Icons.backspace_outlined, size: 16),
                      label: const Text('Temizle'),
                      onPressed: _quantity.clear,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 32),
                Text('Son hareketler', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._buildMovements(theme),
              ],
            ),
          ),
          _buildSaveBar(theme, colors, p.unit),
        ],
      ),
    );
  }

  Widget _buildStockCard(ThemeData theme) {
    final p = _product;
    return Card(
      color: _isCritical ? theme.colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Mevcut stok', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text('${formatQty(_stock)} ${p.unit}', style: theme.textTheme.displaySmall, textAlign: TextAlign.center),
            if (_pendingOffline)
              Text('Tahmini: gönderilmeyi bekleyen kayıt var', style: theme.textTheme.bodySmall),
            if (p.minStock > 0) ...[
              const SizedBox(height: 4),
              Text(
                _isCritical
                    ? 'Kritik seviyede! (sınır ${formatQty(p.minStock)} ${p.unit})'
                    : 'Kritik seviye: ${formatQty(p.minStock)} ${p.unit}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _isCritical ? theme.colorScheme.onErrorContainer : null,
                  fontWeight: _isCritical ? FontWeight.w600 : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "Günde ortalama 2,1 Adet çıkış · ~6 gün yeter · önerilen kritik seviye 21".
  /// Tahmin sunucudaki stoğa göredir; çevrimdışı kayıttan sonra eski kalabilir.
  Widget _buildForecastCard(ThemeData theme, ProductForecast f, bool isAdmin) {
    final unit = _product.unit;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final left = f.daysLeft;
    final canApply = isAdmin && f.hasData && f.suggestedMinStock != _product.minStock;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.insights_outlined, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Tüketim tahmini', style: theme.textTheme.titleSmall)),
            ]),
            const SizedBox(height: 8),
            if (!f.hasData)
              Text('Son ${f.windowDays} günde çıkış yok; tahmin için veri yetersiz.', style: muted)
            else ...[
              Text('Günde ortalama ${formatRate(f.avgDailyOut)} $unit çıkış (son ${f.windowDays} gün)'),
              if (left != null) ...[
                const SizedBox(height: 4),
                Text(
                  left <= 0
                      ? 'Stok bitti.'
                      : 'Bu hızla ${formatDaysLeft(left)} yeter'
                          '${f.stockoutDate == null ? '' : ' (${formatDate(f.stockoutDate!)})'}',
                  style: TextStyle(
                    color: f.endsBeforeResupply ? theme.colorScheme.error : null,
                    fontWeight: f.endsBeforeResupply ? FontWeight.w600 : null,
                  ),
                ),
                if (f.endsBeforeResupply && left > 0)
                  Text('Tedarik süresi ${f.leadTimeDays} gün: sipariş verme zamanı.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 12),
              Text('Önerilen kritik seviye: ${formatQty(f.suggestedMinStock)} $unit'),
              Text(
                'Günlük çıkış × (${f.leadTimeDays} gün tedarik + ${f.safetyDays} gün emniyet payı)',
                style: muted,
              ),
              if (canApply) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: _applyingMinStock ? null : () => _applySuggestedMinStock(f.suggestedMinStock),
                    icon: _applyingMinStock
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: Text('Kritik seviyeyi ${formatQty(f.suggestedMinStock)} yap'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Altta sabit kaydetme alanı. Düğme hangi işlemin kaydedileceğini rengi ve metniyle söyler;
  /// yanlış tipte kayıt riskini azaltır.
  /// Büyük yazı boyutunda çubuk ekranın üçte birini kaplamasın diye yazı ölçeği 1.3'te sınırlanır
  /// (NavigationBar gibi sabit çubuklarda olağan yaklaşım).
  Widget _buildSaveBar(ThemeData theme, MovementColors colors, String unit) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: _buildSaveBarContent(theme, colors, unit),
    );
  }

  Widget _buildSaveBarContent(ThemeData theme, MovementColors colors, String unit) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.colorFor(_type),
                  foregroundColor: colors.onColorFor(_type),
                ),
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(movementIconData(_type)),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_saveLabel(unit), textAlign: TextAlign.center),
                ),
              ),
              TextButton.icon(
                onPressed: _saving ? null : () => _save(scanNext: true),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Kaydet ve sıradakini okut'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Çıkış stoktan fazlaysa uyarır. Engellemez: gösterilen stok eski olabilir, son karar sunucunun.
  String? _stockWarning(String unit) {
    final qty = _parseQuantity();
    if (_type != MovementType.outbound || qty == null || qty <= _stock) return null;
    return 'Stokta ${formatQty(_stock)} $unit görünüyor; fazlası reddedilir.';
  }

  /// Sayımda yazılacak farkı önceden gösterir: "Sistemde 10 Adet · fark -2".
  String? _countDiffHint(String unit) {
    final qty = _parseQuantity();
    if (_type != MovementType.count || qty == null) return null;
    final diff = qty - _stock;
    final diffText = diff > 0 ? '+${formatQty(diff)}' : formatQty(diff);
    return 'Sistemde ${formatQty(_stock)} $unit · fark $diffText';
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
          leading: MovementIcon(m.type),
          title: Text(describeMovement(m.type, m.quantity, m.countedQuantity, _product.unit)),
          subtitle: Text([
            formatDateTime(m.createdAt),
            m.userName,
            if (m.note != null) m.note!,
          ].join(' · ')),
        ),
    ];
  }

  /// "Çıkışı kaydet · 5 Adet" — miktar girilmemişse sadece işlem adı.
  String _saveLabel(String unit) {
    final action = switch (_type) {
      MovementType.inbound => 'Girişi kaydet',
      MovementType.outbound => 'Çıkışı kaydet',
      MovementType.count => 'Sayımı kaydet',
    };
    final qty = _parseQuantity();
    return qty == null ? action : '$action · ${formatQty(qty)} $unit';
  }
}
