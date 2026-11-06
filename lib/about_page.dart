import 'package:flutter/material.dart';

/// Halaman Tentang Chrome Lite.
///
/// Menampilkan nama aplikasi, versi, deskripsi singkat, dan tautan
/// pembuat. Mengetuk tautan membuka situsnya di browser (lewat
/// [onOpenLink]).
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.onOpenLink});

  final void Function(String url) onOpenLink;

  Widget _linkTile({
    required IconData icon,
    required String label,
    required String url,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(url),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => onOpenLink(url),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tentang Chrome Lite')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const SizedBox(height: 8),
          // Logo teks.
          const Center(
            child: Text(
              'Chrome Lite',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              'Versi 1.0.0 (Flutter)',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Browser ringan ala Chrome, dibuat ulang dengan Flutter. '
            'WebView, tab, mode samaran, unduhan, bookmark, riwayat, '
            'dan AdBlock dalam satu aplikasi.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.person),
            title: Text('Pembuat'),
            subtitle: Text('Kang Modol'),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 8, bottom: 4),
            child: Text(
              'Tautan',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          _linkTile(
            icon: Icons.code,
            label: 'GitHub',
            url: 'https://github.com/charudkelser',
          ),
          _linkTile(
            icon: Icons.thumb_up,
            label: 'Facebook',
            url: 'https://www.facebook.com/syahrudin30',
          ),
          _linkTile(
            icon: Icons.camera_alt,
            label: 'Instagram',
            url: 'https://www.instagram.com/kangmodol30',
          ),
        ],
      ),
    );
  }
}
