import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'utils.dart';

enum DownloadStatus { downloading, done, failed }

/// Satu entri unduhan.
class DownloadItem {
  DownloadItem({required this.url, required this.fileName});

  final String url;
  final String fileName;
  DownloadStatus status = DownloadStatus.downloading;
  double progress = 0;
  String? savedPath;
  String? error;
}

/// Pengelola unduhan sederhana (singleton).
///
/// Unduh via paket http (streaming, ada progres). Tujuan pertama folder
/// Download publik perangkat; bila tidak bisa ditulis (scoped storage
/// Android 11+), jatuh ke folder eksternal aplikasi, lalu ke dokumen
/// aplikasi. Daftar unduhan disiarkan lewat [items] agar halaman Unduhan
/// ikut diperbarui.
class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  final ValueNotifier<List<DownloadItem>> items =
      ValueNotifier<List<DownloadItem>>(<DownloadItem>[]);

  /// Beri tahu pendengar bahwa isi item berubah (progress/status).
  /// ValueNotifier hanya memberi notifikasi saat [items].value diganti,
  /// jadi tugaskan salinan list yang sama.
  void _refresh() {
    items.value = List<DownloadItem>.of(items.value);
  }

  /// Daftar folder tujuan, dari yang paling diinginkan ke cadangan.
  Future<List<Directory>> _targetDirs() async {
    final dirs = <Directory>[];
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) dirs.add(downloads);
    } catch (_) {
      // Abaikan; lanjut ke cadangan.
    }
    try {
      final external = await getExternalStorageDirectory();
      if (external != null) dirs.add(external);
    } catch (_) {
      // Abaikan; lanjut ke cadangan.
    }
    dirs.add(await getApplicationDocumentsDirectory());
    return dirs;
  }

  /// Cari nama berkas yang belum dipakai di [dir].
  Future<File> _uniqueFile(Directory dir, String name) async {
    var file = File('${dir.path}/$name');
    var n = 1;
    while (await file.exists()) {
      final dot = name.lastIndexOf('.');
      final base = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      file = File('${dir.path}/$base ($n)$ext');
      n++;
    }
    return file;
  }

  /// Unduh [url] ke [dir]; lempar bila gagal (pemanggil mencoba dir berikut).
  Future<void> _downloadTo(String url, DownloadItem item, Directory dir) async {
    final file = await _uniqueFile(dir, item.fileName);
    final client = http.Client();
    try {
      final response =
          await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? -1;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) {
            item.progress = received / total;
            _refresh();
          }
        }
      } finally {
        await sink.close();
      }
      item.progress = 1;
      item.savedPath = file.path;
      item.status = DownloadStatus.done;
    } catch (e) {
      // Hapus berkas setengah jadi supaya tidak mengotori folder.
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Abaikan.
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Mulai unduhan baru untuk [url]. Tidak melempar; kegagalan dicatat
  /// di status item.
  Future<void> startDownload(String url) async {
    final item =
        DownloadItem(url: url, fileName: fileNameFromUrl(url));
    items.value = <DownloadItem>[...items.value, item];
    Object? lastError;
    for (final dir in await _targetDirs()) {
      try {
        await _downloadTo(url, item, dir);
        _refresh();
        return;
      } catch (e) {
        lastError = e;
      }
    }
    item.status = DownloadStatus.failed;
    item.error = lastError?.toString();
    _refresh();
  }
}

/// Halaman Daftar Unduhan.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  String _statusText(DownloadItem item) {
    switch (item.status) {
      case DownloadStatus.downloading:
        return 'Mengunduh... ${(item.progress * 100).toStringAsFixed(0)}%';
      case DownloadStatus.done:
        return 'Selesai';
      case DownloadStatus.failed:
        return 'Gagal${item.error == null ? '' : ': ${item.error}'}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unduhan')),
      body: ValueListenableBuilder<List<DownloadItem>>(
        valueListenable: DownloadManager.instance.items,
        builder: (context, downloads, _) {
          if (downloads.isEmpty) {
            return const Center(
              child: Text('Belum ada unduhan.'),
            );
          }
          return ListView.builder(
            itemCount: downloads.length,
            itemBuilder: (context, index) {
              final item = downloads[index];
              return ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: Text(item.fileName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(_statusText(item)),
                    if (item.savedPath != null)
                      Text(
                        item.savedPath!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    if (item.status == DownloadStatus.downloading)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: LinearProgressIndicator(
                          value: item.progress > 0 ? item.progress : null,
                        ),
                      ),
                  ],
                ),
                isThreeLine: item.savedPath != null,
              );
            },
          );
        },
      ),
    );
  }
}
