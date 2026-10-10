import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Kamerayla barkod okur ve okunan değeri geri döndürür.
/// Kamerası olmayan emülatörde "Elle gir" ile barkod yazılabilir.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _handled = true;
    HapticFeedback.mediumImpact(); // okundu geri bildirimi
    Navigator.of(context).pop(value);
  }

  Future<void> _manualEntry() async {
    final text = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Barkodu elle gir'),
        content: TextField(
          controller: text,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '8690000000011'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(text.text.trim()), child: const Text('Tamam')),
        ],
      ),
    );
    // Not: controller'ı burada dispose etmiyoruz; dialog kapanma animasyonu sürerken hâlâ kullanılıyor.
    if (!mounted || value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Barkod okut'),
        actions: [
          IconButton(
            tooltip: 'Fener',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: FilledButton.tonalIcon(
              onPressed: _manualEntry,
              icon: const Icon(Icons.keyboard),
              label: const Text('Elle gir'),
            ),
          ),
        ],
      ),
    );
  }
}
