import 'package:flutter/material.dart';

import 'about_page.dart';

/// Halaman Setelan: saklar AdBlock, bersihkan data, dan Tentang.
///
/// Saklar AdBlock tersimpan permanen (default ON) dan bisa dimatikan
/// kapan saja.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.adBlockEnabled,
    required this.onAdBlockChanged,
    required this.onClearHistory,
    required this.onClearCookies,
    required this.onClearCache,
    required this.onOpenLink,
  });

  final bool adBlockEnabled;
  final ValueChanged<bool> onAdBlockChanged;
  final VoidCallback onClearHistory;
  final VoidCallback onClearCookies;
  final VoidCallback onClearCache;

  /// Dipanggil dengan URL saat tautan di halaman Tentang diketuk.
  final void Function(String url) onOpenLink;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _adBlock;

  @override
  void initState() {
    super.initState();
    _adBlock = widget.adBlockEnabled;
  }

  void _showDone(String message) {
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Umum',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.block),
            title: const Text('AdBlock'),
            subtitle: const Text(
              'Blokir iklan di halaman web. Matikan bila ada situs yang tidak bisa dibuka.',
            ),
            value: _adBlock,
            onChanged: (value) {
              setState(() => _adBlock = value);
              widget.onAdBlockChanged(value);
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Privasi',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Hapus riwayat'),
            subtitle: const Text('Menghapus daftar situs yang dikunjungi'),
            onTap: () {
              widget.onClearHistory();
              _showDone('Riwayat dihapus');
            },
          ),
          ListTile(
            leading: const Icon(Icons.cookie),
            title: const Text('Hapus cookie'),
            subtitle: const Text('Keluar dari situs yang sedang masuk'),
            onTap: () {
              widget.onClearCookies();
              _showDone('Cookie dihapus');
            },
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services),
            title: const Text('Hapus cache'),
            subtitle: const Text('Menghapus cache halaman web'),
            onTap: () {
              widget.onClearCache();
              _showDone('Cache dihapus');
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Tentang',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('Tentang Chrome Lite'),
            subtitle: const Text('Versi 1.0.0 (Flutter)'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (aboutContext) => AboutPage(
                    onOpenLink: (url) {
                      // Tutup Tentang, lalu tutup Setelan, baru buka tautan
                      // di browser supaya halamannya langsung terlihat.
                      Navigator.of(aboutContext).pop();
                      Navigator.of(context).pop();
                      widget.onOpenLink(url);
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
