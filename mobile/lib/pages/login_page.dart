import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../theme.dart';
import 'home_page.dart';

enum _ServerStatus { checking, online, offline }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userName = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  bool _errorIsConnection = false;
  _ServerStatus _server = _ServerStatus.checking;

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  @override
  void dispose() {
    _userName.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _checkServer() async {
    setState(() => _server = _ServerStatus.checking);
    final ok = await ApiClient.instance.checkHealth();
    if (mounted) setState(() => _server = ok ? _ServerStatus.online : _ServerStatus.offline);
  }

  Future<void> _login([String? userName, String? password]) async {
    if (userName != null) _userName.text = userName;
    if (password != null) _password.text = password;
    if (_userName.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() {
        _error = 'Kullanıcı adı ve şifre gir.';
        _errorIsConnection = false;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiClient.instance.login(_userName.text.trim(), _password.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
    } on ApiException catch (e) {
      setState(() {
        _errorIsConnection = e.isNetworkError;
        _error = e.isNetworkError
            ? 'Sunucuya bağlanılamadı. Sunucu adresini ve Wi-Fi bağlantını kontrol et.'
            : e.message;
        if (e.isNetworkError) _server = _ServerStatus.offline;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openServerSettings() async {
    final saved = await showDialog<bool>(context: context, builder: (_) => const _ServerSettingsDialog());
    if (saved == true && mounted) {
      setState(() => _error = null);
      _checkServer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(theme),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // "Giriş yap" düğmede yazıyor; başlıkta tekrarlanmaz.
                    Text('Hoş geldin', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Depo hesabınla giriş yap', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _userName,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      onSubmitted: (_) => _passwordFocus.requestFocus(),
                      decoration: const InputDecoration(
                        labelText: 'Kullanıcı adı',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      focusNode: _passwordFocus,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        labelText: 'Şifre',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Şifreyi göster' : 'Şifreyi gizle',
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBox(
                        message: _error!,
                        actionLabel: _errorIsConnection ? 'Sunucu ayarları' : null,
                        onAction: _openServerSettings,
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loading ? null : () => _login(),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: _loading
                          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Giriş yap', style: TextStyle(fontSize: 16)),
                    ),
                    if (showDemoAccounts) ...[
                      const SizedBox(height: 24),
                      Row(children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('veya demo hesapla dene', style: theme.textTheme.bodySmall),
                        ),
                        const Expanded(child: Divider()),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _loading ? null : () => _login('depo', 'Depo123!'),
                            icon: const Icon(Icons.badge_outlined),
                            label: const Text('Depo personeli'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _loading ? null : () => _login('admin', 'Admin123!'),
                            icon: const Icon(Icons.admin_panel_settings_outlined),
                            label: const Text('Yönetici'),
                          ),
                        ),
                      ]),
                    ],
                    const SizedBox(height: 28),
                    Center(child: _buildServerChip(scheme)),
                    const SizedBox(height: 8),
                    Center(child: Text('Sürüm $appVersion', style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [brandDark, brandSeed],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 32),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Sunucu ayarları',
                  icon: const Icon(Icons.settings_outlined, color: Colors.white),
                  onPressed: _openServerSettings,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 6))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset('assets/icon/app_icon.png', width: 88, height: 88),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Stok Takip',
                style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Barkodla depo ve stok yönetimi',
                style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerChip(ColorScheme scheme) {
    final (color, text) = switch (_server) {
      _ServerStatus.checking => (scheme.outline, 'kontrol ediliyor'),
      _ServerStatus.online => (MovementColors.of(context).success, 'bağlı'),
      _ServerStatus.offline => (scheme.error, 'ulaşılamıyor'),
    };
    return ActionChip(
      avatar: Icon(Icons.circle, size: 12, color: color),
      label: Text('Sunucu ${ApiConfig.display(ApiConfig.baseUrl)} · $text'),
      onPressed: _openServerSettings,
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: scheme.onErrorContainer))),
          if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// Sunucu adresini değiştirme ve bağlantıyı test etme.
class _ServerSettingsDialog extends StatefulWidget {
  const _ServerSettingsDialog();

  @override
  State<_ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<_ServerSettingsDialog> {
  late final _controller = TextEditingController(text: ApiConfig.display(ApiConfig.baseUrl));
  bool _testing = false;
  bool? _testOk;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testOk = null;
    });
    final ok = await ApiClient.instance.checkHealth(baseUrl: ApiConfig.normalize(_controller.text));
    if (mounted) {
      setState(() {
        _testing = false;
        _testOk = ok;
      });
    }
  }

  Future<void> _save() async {
    await ApiConfig.save(_controller.text);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Sunucu adresi'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: '192.168.0.101:8080',
              helperText: 'Örn. 192.168.1.20:8080 veya https://stok.firma.com',
            ),
            onChanged: (_) => setState(() => _testOk = null),
          ),
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering),
              label: const Text('Bağlantıyı test et'),
            ),
            const SizedBox(width: 12),
            if (_testOk != null)
              Icon(
                _testOk! ? Icons.check_circle : Icons.cancel,
                color: _testOk! ? MovementColors.of(context).success : scheme.error,
              ),
          ]),
          if (_testOk == false) ...[
            const SizedBox(height: 8),
            Text('Ulaşılamadı. Adresi ve aynı Wi-Fi\'de olduğunu kontrol et.',
                style: TextStyle(color: scheme.error, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _controller.text = ApiConfig.display(ApiConfig.defaultBaseUrl),
          child: const Text('Varsayılan'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Vazgeç')),
        FilledButton(onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}
