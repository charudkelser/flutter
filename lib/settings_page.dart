import 'package:flutter/material.dart';

/// Setelan minimal: hapus riwayat, cookie, dan cache.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.onClearHistory,
    required this.onClearCookies,
    required this.onClearCache,
  });

  final VoidCallback onClearHistory;
  final VoidCallback onClearCookies;
  final VoidCallback onClearCache;

  void _showDone(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setelan')),
      body: ListView(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Hapus riwayat'),
            subtitle: const Text('Menghapus daftar situs yang dikunjungi'),
            onTap: () {
              onClearHistory();
              _showDone(context, 'Riwayat dihapus');
            },
          ),
          ListTile(
            leading: const Icon(Icons.cookie),
            title: const Text('Hapus cookie'),
            subtitle: const Text('Keluar dari situs yang sedang masuk'),
            onTap: () async {
              onClearCookies();
              _showDone(context, 'Cookie dihapus');
            },
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services),
            title: const Text('Hapus cache'),
            subtitle: const Text('Menghapus cache halaman web'),
            onTap: () async {
              onClearCache();
              _showDone(context, 'Cache dihapus');
            },
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info),
            title: Text('Tentang'),
            subtitle: Text(
              'Chrome Lite Flutter v1.0\n'
              'Rebuild Flutter dari Chrome Lite (Java).',
            ),
          ),
        ],
      ),
    );
  }
}
