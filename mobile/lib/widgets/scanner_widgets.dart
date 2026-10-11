import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Fener düğmesi: ikon ve ipucu fenerin gerçek durumunu gösterir; fener yoksa düğme pasif.
class TorchButton extends StatelessWidget {
  const TorchButton({super.key, required this.controller});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, _) {
        final torch = state.torchState;
        final on = torch == TorchState.on;
        return IconButton(
          tooltip: switch (torch) {
            TorchState.unavailable => 'Fener yok',
            TorchState.on => 'Feneri kapat',
            _ => 'Feneri aç',
          },
          isSelected: on,
          icon: const Icon(Icons.flashlight_off_outlined),
          selectedIcon: const Icon(Icons.flashlight_on),
          onPressed: torch == TorchState.unavailable ? null : controller.toggleTorch,
        );
      },
    );
  }
}

/// Kamera açılamadığında (izin yok, kamera yok) gösterilir; elle giriş hâlâ kullanılabilir.
Widget scannerErrorBuilder(BuildContext context, MobileScannerException error) {
  final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
  return ColoredBox(
    color: Colors.black,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white, size: 40),
            const SizedBox(height: 12),
            Text(
              denied
                  ? 'Kamera izni verilmedi. Ayarlardan izin ver ya da barkodu elle gir.'
                  : 'Kamera açılamadı. Barkodu elle girebilirsin.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Kamera görüntüsü üstündeki hizalama çerçevesi ve kısa yönlendirme.
class ScanFrame extends StatelessWidget {
  const ScanFrame({super.key, required this.width, required this.height, this.active = true, this.hint});

  final double width;
  final double height;

  /// false ise (ör. dialog açıkken okuma duraklatıldı) çerçeve gri çizilir.
  final bool active;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              border: Border.all(color: active ? Colors.white : Colors.grey, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text(hint!, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
