/// API adresi derleme sırasında verilir:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8080
/// Verilmezse Android emülatöründen bilgisayardaki API'ye giden adres kullanılır.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);
