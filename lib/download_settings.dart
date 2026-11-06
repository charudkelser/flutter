import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';

/// Halaman Setelan unduhan (dibuka dari ikon gerigi di halaman Download).
///
/// - "Lokasi unduhan": folder bersama tujuan berkas selesai
///   (Unduhan, Gambar, Video, Musik, Dokumen, Penyimpanan eksternal).
/// - "Subfolder": nama subfolder opsional di dalam lokasi itu
///   (mis. "ROM" → berkas selesai masuk Unduhan/ROM).
///
/// Pilihan tersimpan permanen dan hanya berlaku untuk unduhan BARU;
/// unduhan yang sedang berjalan tidak dipindah tujuannya.
class DownloadSettingsPage extends StatefulWidget {
  const DownloadSettingsPage({super.key});

  @override
  State<DownloadSettingsPage> createState() => _DownloadSettingsPageState();
}

class _DownloadSettingsPageState extends State<DownloadSettingsPage> {
  late SharedStorage _location;
  late TextEditingController _subfolderController;

  static const List<SharedStorage> _locations = <SharedStorage>[
    SharedStorage.downloads,
    SharedStorage.images,
    SharedStorage.video,
    SharedStorage.audio,
    SharedStorage.files,
    SharedStorage.external,
  ];

  @override
  void initState() {
    super.initState();
    final settings = BrowserSettings.instance;
    _location = settings.downloadLocation;
    _subfolderController =
        TextEditingController(text: settings.downloadSubfolder);
  }

  @override
  void dispose() {
    _subfolderController.dispose();
    super.dispose();
  }

  String _subfolderPreview() {
    final sub = sanitizeSubfolder(_subfolderController.text);
    final base = downloadLocationHint(_location);
    if (sub.isEmpty) return base;
    return '$base/$sub';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setelan unduhan')),
      body: ListView(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Lokasi unduhan',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ..._locations.map(
            (location) => RadioListTile<SharedStorage>(
              title: Text(downloadLocationLabel(location)),
              subtitle: Text(downloadLocationHint(location)),
              value: location,
              groupValue: _location,
              onChanged: (value) {
                if (value == null) return;
                setState(() => _location = value);
                BrowserSettings.instance.setDownloadLocation(value);
              },
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Subfolder',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              controller: _subfolderController,
              decoration: const InputDecoration(
                hintText: 'Mis. ROM (kosongkan bila tidak perlu)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                BrowserSettings.instance.setDownloadSubfolder(value);
                setState(() {});
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              'Berkas selesai disimpan di ${_subfolderPreview()}.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              'Berlaku untuk unduhan baru. Unduhan yang sedang berjalan tidak dipindah tujuannya.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
