import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'config.dart';
import 'offline/offline_store.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.load();
  await ApiClient.instance.restoreSession();
  await OfflineStore.instance.load();
  runApp(const StokTakipApp());
}

class StokTakipApp extends StatelessWidget {
  const StokTakipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stok Takip',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: ApiClient.instance.session == null ? const LoginPage() : const HomePage(),
    );
  }
}

/// Token süresi dolduysa (401) oturumu kapatıp giriş ekranına döner.
Future<void> handleUnauthorized(BuildContext context) async {
  await ApiClient.instance.logout();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginPage()),
    (_) => false,
  );
}
