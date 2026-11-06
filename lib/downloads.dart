import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils.dart';

enum DownloadStatus { downloading, paused, done, failed }

/// Satu entri unduhan.
class DownloadItem {
  DownloadItem({
    required this.taskId,
    required this.url,
    required this.fileName,
    this.task,
  });

  final String taskId;
  final String url;
  final String fileName;

  /// Tugas plugin (untuk jeda/lanjut/batal). Diisi saat dibuat atau
  /// dipulihkan dari database plugin.
  DownloadTask? task;

  DownloadStatus status = DownloadStatus.downloading;
  double progress = 0;
  int received = 0;
  int total = -1;
  double speed = 0; // byte/detik
  int etaSeconds = -1; // -1 = tidak diketahui
  String? savedPath; // path berkas (folder aplikasi, atau publik sesudah dipindah)
  String? sharedPath; // path publik sesudah dipindah (null = belum dipindah)
  String? error;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': taskId,
        'url': url,
        'fileName': fileName,
        'status': status.name,
        'progress': progress,
        'received': received,
        'total': total,
        'savedPath': savedPath,
        'sharedPath': sharedPath,
        'error': error,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    final item = DownloadItem(
      taskId: json['id']?.toString() ?? '',
      url: json['url'] as String? ?? '',
      fileName: json['fileName'] as String? ?? 'unduhan',
    );
    final statusName = json['status'] as String? ?? 'failed';
    item.status = DownloadStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => DownloadStatus.failed,
    );
    item.progress = (json['progress'] as num?)?.toDouble() ?? 0;
    item.received = (json['received'] as num?)?.toInt() ?? 0;
    item.total = (json['total'] as num?)?.toInt() ?? -1;
    item.savedPath = json['savedPath'] as String?;
    item.sharedPath = json['sharedPath'] as String?;
    item.error = json['error'] as String?;
    return item;
  }
}

/// Pengelola unduhan (singleton).
///
/// Unduhan berjalan lewat plugin background_downloader: tugas diantrekan
/// ke pekerja latar Android, sehingga unduhan TETAP BERJALAN meskipun
/// aplikasi ditutup atau pengguna membuka aplikasi lain. Plugin juga yang
/// menampilkan notifikasi progres (tombol Jeda/Batal) dan menyimpan tugas
/// di database-nya supaya bisa dilanjutkan sesudah aplikasi dimatikan.
///
/// Daftar unduhan untuk halaman Unduhan disiarkan lewat [items].
/// Berkas selesai dipindah ke folder Unduhan publik via
/// moveToSharedStorage (MediaStore).
class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  static const String _prefsKey = 'downloads_v1';

  /// Dipanggil saat notifikasi unduhan ditekan: buka halaman Unduhan.
  /// Diisi dari main.dart.
  static void Function()? onOpenDownloads;

  final ValueNotifier<List<DownloadItem>> items =
      ValueNotifier<List<DownloadItem>>(<DownloadItem>[]);

  bool _started = false;
  final Set<String> _moving = <String>{};
  DateTime _lastRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSaveAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Siapkan plugin + pulihkan daftar unduhan. Dipanggil sekali saat
  /// aplikasi mulai (dari initState halaman utama).
  Future<void> init() async {
    if (_started) return;
    _started = true;
    // Daftarkan pendengar SEBELUM start() supaya pembaruan dari latar
    // (tugas yang selesai saat aplikasi mati) tidak hilang.
    FileDownloader().updates.listen(_onUpdate);
    FileDownloader().registerCallbacks(
      taskNotificationTapCallback: (task, type) {
        onOpenDownloads?.call();
      },
    );
    FileDownloader().configureNotification(
      running: const TaskNotification(
        'Mengunduh',
        '{filename} • {progress}',
      ),
      paused: const TaskNotification('Unduhan dijeda', '{filename}'),
      complete: const TaskNotification('Unduhan selesai', '{filename}'),
      error: const TaskNotification('Unduhan gagal', '{filename}'),
      progressBar: true,
    );
    await FileDownloader().start();
    await restore();
  }

  DownloadItem? _findByTaskId(String taskId) {
    for (final item in items.value) {
      if (item.taskId == taskId) return item;
    }
    return null;
  }

  /// Beri tahu pendengar bahwa isi item berubah (progress/status).
  /// Dibatasi ~5x/detik supaya halaman Unduhan tidak dibangun ulang
  /// tiap pembaruan; perubahan status selalu dipaksa.
  void _refresh({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastRefreshAt).inMilliseconds < 200) {
      return;
    }
    _lastRefreshAt = now;
    items.value = List<DownloadItem>.of(items.value);
    _saveSoon();
  }

  Future<void> _saveSoon() async {
    final now = DateTime.now();
    if (now.difference(_lastSaveAt).inSeconds < 2) return;
    _lastSaveAt = now;
    await _saveNow();
  }

  Future<void> _saveNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = items.value.map((e) => e.toJson()).toList();
      await prefs.setString(_prefsKey, jsonEncode(list));
    } catch (_) {
      // Abaikan; unduhan tetap jalan tanpa tersimpan.
    }
  }

  /// Pulihkan daftar unduhan dari penyimpanan, dicocokkan dengan database
  /// plugin (status terkini tiap tugas). Tugas yang selesai saat aplikasi
  /// mati dan belum sempat dipindah akan dipindah di sini.
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as List<dynamic>;
      final restored = <DownloadItem>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        final item = DownloadItem.fromJson(entry);
        if (item.taskId.isEmpty) continue;
        restored.add(item);
      }
      if (restored.isEmpty) return;
      final records = <String, TaskRecord>{};
      try {
        for (final record in await FileDownloader().database.allRecords()) {
          records[record.taskId] = record;
        }
      } catch (_) {
        // Abaikan; lanjut tanpa pencocokan.
      }
      final finalList = <DownloadItem>[];
      for (final item in restored) {
        final record = records[item.taskId];
        if (record != null) {
          if (record.task is DownloadTask) {
            item.task = record.task as DownloadTask;
          }
          item.progress = record.progress.clamp(0, 1);
          if (record.expectedFileSize > 0) {
            item.total = record.expectedFileSize;
          }
          if (item.total > 0) {
            item.received = (item.progress * item.total).round();
          }
          switch (record.status) {
            case TaskStatus.enqueued:
            case TaskStatus.running:
            case TaskStatus.waitingToRetry:
              item.status = DownloadStatus.downloading;
              break;
            case TaskStatus.paused:
              item.status = DownloadStatus.paused;
              break;
            case TaskStatus.complete:
              item.status = DownloadStatus.done;
              item.progress = 1;
              if (item.total > 0) item.received = item.total;
              if (item.sharedPath == null) {
                _moveToShared(item);
              }
              break;
            case TaskStatus.failed:
            case TaskStatus.notFound:
              item.status = DownloadStatus.failed;
              item.error = record.exception?.toString();
              break;
            case TaskStatus.canceled:
              // Dibatalkan — jangan tampilkan lagi.
              continue;
          }
        } else {
          // Tidak ada catatan tugas: bila dulu selesai, biarkan sebagai
          // riwayat; bila dulu berjalan/dijeda, tugasnya hilang → gagal.
          if (item.status == DownloadStatus.downloading ||
              item.status == DownloadStatus.paused) {
            item.status = DownloadStatus.failed;
            item.error = 'Unduhan terputus';
            item.task = null;
          }
        }
        finalList.add(item);
      }
      items.value = finalList;
    } catch (_) {
      // Abaikan; mulai dengan daftar kosong.
    }
  }

  void _onUpdate(TaskUpdate update) {
    final item = _findByTaskId(update.task.taskId);
    if (item == null) return;
    if (update is TaskProgressUpdate) {
      item.progress = update.progress.clamp(0, 1);
      if (update.expectedFileSize > 0) {
        item.total = update.expectedFileSize;
      }
      if (item.total > 0) {
        item.received = (item.progress * item.total).round();
      }
      if (update.networkSpeed > 0) {
        item.speed = update.networkSpeed * 1024 * 1024;
      }
      if (update.timeRemaining.inSeconds >= 0) {
        item.etaSeconds = update.timeRemaining.inSeconds;
      }
      _refresh();
      return;
    }
    if (update is TaskStatusUpdate) {
      switch (update.status) {
        case TaskStatus.enqueued:
        case TaskStatus.running:
        case TaskStatus.waitingToRetry:
          item.status = DownloadStatus.downloading;
          item.error = null;
          _refresh(force: true);
          break;
        case TaskStatus.paused:
          item.status = DownloadStatus.paused;
          item.speed = 0;
          item.etaSeconds = -1;
          _refresh(force: true);
          _saveNow();
          break;
        case TaskStatus.complete:
          item.progress = 1;
          if (item.total > 0) item.received = item.total;
          item.speed = 0;
          item.etaSeconds = -1;
          item.status = DownloadStatus.done;
          _refresh(force: true);
          _saveNow();
          _moveToShared(item);
          break;
        case TaskStatus.failed:
          item.status = DownloadStatus.failed;
          item.error = update.exception?.toString();
          item.speed = 0;
          item.etaSeconds = -1;
          _refresh(force: true);
          _saveNow();
          break;
        case TaskStatus.canceled:
          _removeItemInternal(item, deleteFile: true);
          break;
        case TaskStatus.notFound:
          item.status = DownloadStatus.failed;
          item.error = 'Unduhan tidak ditemukan';
          _refresh(force: true);
          _saveNow();
          break;
      }
    }
  }

  /// Pindahkan berkas selesai ke folder Unduhan publik. Dijaga supaya
  /// hanya berjalan sekali per item.
  Future<void> _moveToShared(DownloadItem item) async {
    if (item.sharedPath != null) return;
    if (!_moving.add(item.taskId)) return;
    try {
      final task = item.task;
      if (task == null) return;
      final newPath = await FileDownloader().moveToSharedStorage(
        task,
        SharedStorage.downloads,
      );
      if (newPath != null) {
        item.sharedPath = newPath;
        item.savedPath = newPath;
        _refresh(force: true);
        _saveNow();
      }
    } catch (_) {
      // Abaikan; berkas tetap di folder aplikasi.
    } finally {
      _moving.remove(item.taskId);
    }
  }

  /// Buat tugas unduhan dengan nama berkas yang belum dipakai di folder
  /// tujuan plugin.
  Future<DownloadTask> _buildTask(String url, String baseName) async {
    var name = baseName;
    var n = 1;
    while (true) {
      final task = DownloadTask(
        url: url,
        filename: name,
        directory: 'downloads',
        baseDirectory: BaseDirectory.applicationDocuments,
        updates: Updates.statusAndProgress,
        allowPause: true,
        retries: 3,
        displayName: name,
      );
      final path = await task.filePath();
      if (!await File(path).exists()) return task;
      final dot = baseName.lastIndexOf('.');
      final base = dot > 0 ? baseName.substring(0, dot) : baseName;
      final ext = dot > 0 ? baseName.substring(dot) : '';
      name = '$base ($n)$ext';
      n++;
    }
  }

  /// Mulai unduhan baru untuk [url]. Tidak melempar; kegagalan dicatat
  /// di status item.
  Future<void> startDownload(String url) async {
    final task = await _buildTask(url, fileNameFromUrl(url));
    final item = DownloadItem(
      taskId: task.taskId,
      url: url,
      fileName: task.filename,
      task: task,
    );
    item.savedPath = await task.filePath();
    items.value = <DownloadItem>[...items.value, item];
    _refresh(force: true);
    _saveNow();
    final enqueued = await FileDownloader().enqueue(task);
    if (!enqueued) {
      item.status = DownloadStatus.failed;
      item.error = 'Tidak bisa memulai unduhan';
      _refresh(force: true);
      _saveNow();
    }
  }

  /// Jeda unduhan yang sedang berjalan. Status 'dijeda' datang lewat
  /// pembaruan plugin.
  Future<void> pauseDownload(DownloadItem item) async {
    final task = item.task;
    if (task == null || item.status != DownloadStatus.downloading) return;
    await FileDownloader().pause(task);
  }

  /// Lanjutkan unduhan yang dijeda.
  Future<void> resumeDownload(DownloadItem item) async {
    final task = item.task;
    if (task == null || item.status != DownloadStatus.paused) return;
    await FileDownloader().resume(task);
  }

  /// Batalkan unduhan (berjalan atau dijeda). Item dihapus dari daftar
  /// saat pembaruan 'dibatalkan' tiba; berkas setengah jadi ikut dihapus.
  Future<void> cancelDownload(DownloadItem item) async {
    final task = item.task;
    if (task == null) return;
    if (item.status != DownloadStatus.downloading &&
        item.status != DownloadStatus.paused) {
      return;
    }
    await FileDownloader().cancel(task);
  }

  Future<void> _removeItemInternal(
    DownloadItem item, {
    bool deleteFile = false,
  }) async {
    if (!items.value.contains(item)) return;
    if (deleteFile) {
      final path = item.savedPath;
      if (path != null && item.sharedPath == null) {
        try {
          await File(path).delete();
        } catch (_) {
          // Abaikan.
        }
      }
    }
    try {
      await FileDownloader().database.deleteRecordWithId(item.taskId);
    } catch (_) {
      // Abaikan.
    }
    items.value.remove(item);
    _refresh(force: true);
    _saveNow();
  }

  /// Hapus entri dari daftar (berkas di folder Unduhan TIDAK dihapus).
  /// Hanya untuk unduhan yang sudah selesai atau gagal.
  void removeItem(DownloadItem item) {
    if (item.status == DownloadStatus.downloading ||
        item.status == DownloadStatus.paused) {
      return;
    }
    _removeItemInternal(item);
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

String _formatEta(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (m >= 60) {
    final h = m ~/ 60;
    return '${h.toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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

  String _speedText(DownloadItem item) {
    if (item.speed <= 0) return '';
    final speed = ' • ${_formatBytes(item.speed.round())}/s';
    if (item.etaSeconds < 0) return speed;
    return '$speed • sisa ${_formatEta(item.etaSeconds)}';
  }

  String _statusText(DownloadItem item) {
    final size = _sizeText(item);
    switch (item.status) {
      case DownloadStatus.downloading:
        return 'Mengunduh... ${(item.progress * 100).toStringAsFixed(0)}%$size${_speedText(item)}';
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
                    if (item.status == DownloadStatus.done ||
                        item.status == DownloadStatus.failed)
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Hapus dari daftar',
                        onPressed: () =>
                            DownloadManager.instance.removeItem(item),
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
