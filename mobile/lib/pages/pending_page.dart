import 'package:flutter/material.dart';

import '../models.dart';
import '../offline/offline_store.dart';

/// Çevrimdışıyken kaydedilip henüz sunucuya gitmemiş hareketler.
class PendingPage extends StatelessWidget {
  const PendingPage({super.key});

  Future<void> _sync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await OfflineStore.instance.sync();
    final text = result.offline
        ? 'Sunucuya hâlâ ulaşılamıyor. ${result.sent} kayıt gönderildi.'
        : '${result.sent} kayıt gönderildi${result.failed > 0 ? ', ${result.failed} kayıt reddedildi' : ''}.';
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _delete(BuildContext context, PendingMovement m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kaydı sil'),
        content: Text('${m.productName} için ${m.type.label.toLowerCase()} kaydı silinsin mi? Bu kayıt sunucuya hiç gönderilmeyecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) await OfflineStore.instance.remove(m.id);
  }

  @override
  Widget build(BuildContext context) {
    final store = OfflineStore.instance;
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final items = store.pending;
        return Scaffold(
          appBar: AppBar(title: const Text('Gönderilmeyi bekleyenler')),
          floatingActionButton: store.waitingCount == 0
              ? null
              : FloatingActionButton.extended(
                  onPressed: store.syncing ? null : () => _sync(context),
                  icon: store.syncing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Şimdi gönder'),
                ),
          body: items.isEmpty
              ? const Center(child: Text('Bekleyen kayıt yok.'))
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final m = items[i];
                    final failed = m.error != null;
                    final qty = m.type == MovementType.count
                        ? 'sayılan ${formatQty(m.quantity)}'
                        : formatQty(m.quantity);
                    return ListTile(
                      leading: Icon(
                        failed ? Icons.error_outline : Icons.schedule,
                        color: failed ? theme.colorScheme.error : null,
                      ),
                      title: Text('${m.productName} · ${m.type.label} $qty ${m.unit}'),
                      subtitle: Text(
                        failed ? 'Reddedildi: ${m.error}' : 'Kaydedildi: ${formatDateTime(m.createdAt)}',
                        style: failed ? TextStyle(color: theme.colorScheme.error) : null,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (failed)
                            IconButton(
                              tooltip: 'Tekrar dene',
                              icon: const Icon(Icons.refresh),
                              onPressed: () => store.retry(m.id),
                            ),
                          IconButton(
                            tooltip: 'Sil',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(context, m),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
