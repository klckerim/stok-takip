import 'package:shared_preferences/shared_preferences.dart';

/// Uygulama sürümü (giriş ekranında gösterilir). pubspec.yaml ile aynı tutulmalı.
const String appVersion = '0.2.0';

/// Giriş ekranında demo hesap düğmeleri (şifreler uygulamaya gömülü). Varsayılan kapalı;
/// demo/geliştirme derlemesinde açmak için:
///   flutter run --dart-define=DEMO=true
const bool showDemoAccounts = bool.fromEnvironment('DEMO', defaultValue: false);

/// API adresi. Varsayılan derleme sırasında verilir:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8080
/// Kullanıcı giriş ekranındaki ayarlardan değiştirirse o değer cihazda saklanır ve öncelik alır.
class ApiConfig {
  ApiConfig._();

  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  static const _prefsKey = 'api_base_url';
  static String _baseUrl = defaultBaseUrl;

  static String get baseUrl => _baseUrl;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_prefsKey) ?? defaultBaseUrl;
  }

  /// Adresi kaydeder. Boş verilirse derleme sırasındaki varsayılana döner.
  static Future<void> save(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = normalize(value);
    if (normalized.isEmpty || normalized == defaultBaseUrl) {
      await prefs.remove(_prefsKey);
      _baseUrl = defaultBaseUrl;
    } else {
      await prefs.setString(_prefsKey, normalized);
      _baseUrl = normalized;
    }
  }

  /// "192.168.0.101:8080" → "http://192.168.0.101:8080", sondaki "/" atılır.
  static String normalize(String value) {
    var v = value.trim();
    if (v.isEmpty) return v;
    if (!v.startsWith('http://') && !v.startsWith('https://')) v = 'http://$v';
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  /// Ekranda gösterim için: "192.168.0.101:8080"
  static String display(String url) => url.replaceFirst(RegExp(r'^https?://'), '');
}
