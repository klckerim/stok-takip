import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient.instance.restoreSession();
  runApp(const StokTakipApp());
}

class StokTakipApp extends StatelessWidget {
  const StokTakipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stok Takip',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1F6F5C),
        useMaterial3: true,
      ),
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
