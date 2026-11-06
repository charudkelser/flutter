import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'utils.dart';

enum DownloadStatus { downloading, paused, done, failed }

/// Satu entri unduhan.
class DownloadItem {
  DownloadItem({required this.url, required this.fileName});

  final String url;
  final String fileName;
  DownloadStatus status = DownloadStatus.downloading;
  double progress = 0;
  int received = 0;
  int total = -1;
  String? savedPath;
  String? error;
}

/// Dilempar ke dalam saat unduhan dihentikan (dijeda/dibatalkan) supaya
/// penantian stream selesai tanpa menandai gagal.
class _DownloadStopped implements Exception {}

/// Unduhan yang sedang berjalan (disimpan per item supaya bisa dijeda).
class _ActiveDownload {
  _ActiveDownload({required this.client});

  final http.Client client;
  IOSink? sink;
  StreamSubscription<List<int>>? subscription;
  Completer<void>? done;
  bool stopping = false;
}

/// Pengelola unduhan (singleton).
///
/// Unduh via paket http (streaming, ada progres). Tujuan pertama folder
/// Download publik perangkat; bila tidak bisa ditulis (scoped storage
/// Android 11+), jatuh ke folder eksternal aplikasi, lalu ke dokumen
/// aplikasi. Daftar unduhan disiarkan lewat [items] agar halaman Unduhan
/// ikut diperbarui.
///
/// Jeda/lanjut: saat dijeda, stream dihentikan dan berkas setengah jadi
/// TETAP disimpan; lanjut memakai header HTTP Range sehingga unduhan
/// berlanjut dari byte terakhir. Bila server tidak mendukung Range,
/// unduhan dimulai dari awal lagi.
class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  final ValueNotifier<List<DownloadItem>> items =
      ValueNotifier<List<DownloadItem>>(<DownloadItem>[]);

  final Map<DownloadItem, _ActiveDownload> _active =
      <DownloadItem, _ActiveDownload>{};
  final Map<DownloadItem, Future<void>> _tasks =
      <DownloadItem, Future<void>>{};

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

  /// Unduh [url] ke [file], mulai dari [startByte] (0 = dari awal).
  /// Melempar bila gagal; pemanggil yang memutuskan lanjut atau berhenti.
  Future<void> _downloadFrom(
    String url,
    DownloadItem item,
    File file,
    int startByte,
  ) async {
    final client = http.Client();
    final active = _ActiveDownload(client: client);
    _active[item] = active;
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(url));
      if (startByte > 0) {
        request.headers['Range'] = 'bytes=$startByte-';
      }
      final response = await client.send(request);
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      var effectiveStart = startByte;
      if (response.statusCode == 200 && startByte > 0) {
        // Server tidak mendukung lanjut: mulai dari awal lagi.
        effectiveStart = 0;
        item.received = 0;
        item.total = -1;
      }
      final remaining = response.contentLength ?? -1;
      if (remaining > 0) {
        item.total = response.statusCode == 206
            ? effectiveStart + remaining
            : remaining;
      }
      sink = file.openWrite(
        mode: effectiveStart > 0 ? FileMode.append : FileMode.write,
      );
      active.sink = sink;
      item.progress = item.total > 0 ? item.received / item.total : 0;
      _refresh();
      final done = Completer<void>();
      active.done = done;
      active.subscription = response.stream.listen(
        (chunk) {
          sink!.add(chunk);
          item.received += chunk.length;
          if (item.total > 0) item.progress = item.received / item.total;
          _refresh();
        },
        onError: (Object e) {
          if (!done.isCompleted) done.completeError(e);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await done.future;
      await sink.flush();
      await sink.close();
      sink = null;
      item.progress = 1;
      item.status = DownloadStatus.done;
      _refresh();
    } catch (e) {
      if (active.stopping) return; // Dijeda/dibatalkan.
      try {
        await sink?.close();
      } catch (_) {
        // Abaikan.
      }
      sink = null;
      if (startByte > 0) {
        // Gagal saat melanjutkan: simpan berkas setengah jadi supaya
        // masih bisa dicoba lanjut lagi.
        item.status = DownloadStatus.paused;
        item.error = e.toString();
        _refresh();
        return;
      }
      // Unduhan baru gagal: hapus berkas setengah jadi supaya tidak
      // mengotori folder.
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Abaikan.
      }
      rethrow;
    } finally {
      _active.remove(item);
      try {
        await sink?.close();
      } catch (_) {
        // Abaikan.
      }
      client.close();
    }
  }

  /// Coba unduh dari awal di folder tujuan pertama yang berhasil.
  Future<void> _runDownload(DownloadItem item) async {
    Object? lastError;
    for (final dir in await _targetDirs()) {
      try {
        final file = await _uniqueFile(dir, item.fileName);
        item.savedPath = file.path;
        await _downloadFrom(item.url, item, file, 0);
        return;
      } catch (e) {
        lastError = e;
      }
    }
    item.savedPath = null;
    item.status = DownloadStatus.failed;
    item.error = lastError?.toString();
    _refresh();
  }

  /// Mulai unduhan baru untuk [url]. Tidak melempar; kegagalan dicatat
  /// di status item.
  Future<void> startDownload(String url) async {
    final item =
        DownloadItem(url: url, fileName: fileNameFromUrl(url));
    items.value = <DownloadItem>[...items.value, item];
    final task = _runDownload(item);
    _tasks[item] = task;
    try {
      await task;
    } finally {
      _tasks.remove(item);
    }
  }

  /// Jeda unduhan yang sedang berjalan. Berkas setengah jadi TETAP
  /// disimpan supaya bisa dilanjutkan.
  Future<void> pauseDownload(DownloadItem item) async {
    final active = _active[item];
    if (active == null || item.status != DownloadStatus.downloading) return;
    active.stopping = true;
    await active.subscription?.cancel();
    active.client.close();
    if (active.done != null && !active.done!.isCompleted) {
      active.done!.completeError(_DownloadStopped());
    }
    if (item.status != DownloadStatus.downloading) return;
    item.status = DownloadStatus.paused;
    _refresh();
    // Tunggu penutupan berkas selesai supaya lanjut tidak bentrok.
    final previous = _tasks[item];
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // Abaikan.
      }
    }
  }

  /// Lanjutkan unduhan yang dijeda (HTTP Range; bila server tidak
  /// mendukung, mulai dari awal lagi).
  Future<void> resumeDownload(DownloadItem item) async {
    if (item.status != DownloadStatus.paused) return;
    if (item.savedPath == null) return;
    // Tunggu unduhan sebelumnya benar-benar berhenti (penutupan berkas).
    final previous = _tasks[item];
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // Abaikan.
      }
    }
    if (item.status != DownloadStatus.paused) return;
    final file = File(item.savedPath!);
    if (!await file.exists()) {
      // Berkas setengah jadi hilang: unduh ulang dari awal.
      item.received = 0;
      item.total = -1;
      item.status = DownloadStatus.downloading;
      item.error = null;
      _refresh();
      final task = _runDownload(item);
      _tasks[item] = task;
      try {
        await task;
      } finally {
        _tasks.remove(item);
      }
      return;
    }
    // Panjang berkas di disk adalah kebenaran (bukan angka yang dicatat).
    final startByte = await file.length();
    item.received = startByte;
    if (item.total > 0 && startByte >= item.total) {
      item.progress = 1;
      item.status = DownloadStatus.done;
      _refresh();
      return;
    }
    item.status = DownloadStatus.downloading;
    item.error = null;
    _refresh();
    final task = _downloadFrom(item.url, item, file, startByte);
    _tasks[item] = task;
    try {
      await task;
    } finally {
      _tasks.remove(item);
    }
  }

  /// Batalkan unduhan (berjalan atau dijeda): hentikan, hapus berkas
  /// setengah jadi, dan hapus dari daftar.
  Future<void> cancelDownload(DownloadItem item) async {
    if (item.status == DownloadStatus.done) return;
    final active = _active[item];
    if (active != null) {
      active.stopping = true;
      await active.subscription?.cancel();
      active.client.close();
      if (active.done != null && !active.done!.isCompleted) {
        active.done!.completeError(_DownloadStopped());
      }
      final previous = _tasks[item];
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // Abaikan.
        }
      }
    }
    final path = item.savedPath;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {
        // Abaikan.
      }
    }
    items.value.remove(item);
    _refresh();
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Halaman Daftar Unduhan.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  String _sizeText(DownloadItem item) {
    if (item.total <= 0) {
      return item.received > 0 ? ' • ${_formatBytes(item.received)}' : '';
    }
    return ' • ${_formatBytes(item.received)} / ${_formatBytes(item.total)}';
  }

  String _statusText(DownloadItem item) {
    final size = _sizeText(item);
    switch (item.status) {
      case DownloadStatus.downloading:
        return 'Mengunduh... ${(item.progress * 100).toStringAsFixed(0)}%$size';
      case DownloadStatus.paused:
        return 'Dijeda ${(item.progress * 100).toStringAsFixed(0)}%$size';
      case DownloadStatus.done:
        return 'Selesai$size';
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (item.status == DownloadStatus.downloading)
                      IconButton(
                        icon: const Icon(Icons.pause),
                        tooltip: 'Jeda',
                        onPressed: () =>
                            DownloadManager.instance.pauseDownload(item),
                      ),
                    if (item.status == DownloadStatus.paused)
                      IconButton(
                        icon: const Icon(Icons.play_arrow),
                        tooltip: 'Lanjutkan',
                        onPressed: () =>
                            DownloadManager.instance.resumeDownload(item),
                      ),
                    if (item.status == DownloadStatus.downloading ||
                        item.status == DownloadStatus.paused)
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Batalkan',
                        onPressed: () =>
                            DownloadManager.instance.cancelDownload(item),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
