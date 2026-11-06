import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'download_settings.dart';
import 'utils.dart';

/// Saluran ke kode Android (MainActivity.kt) untuk info penyimpanan
/// perangkat dan membuka berkas dengan aplikasi lain.
const MethodChannel _storageChannel = MethodChannel('modol/storage');

/// Info penyimpanan perangkat: (terpakai, total) dalam byte.
Future<(int, int)?> getStorageInfo() async {
  try {
    final result =
        await _storageChannel.invokeMapMethod<String, dynamic>('getStorageInfo');
    if (result == null) return null;
    final used = (result['usedBytes'] as num?)?.toInt();
    final total = (result['totalBytes'] as num?)?.toInt();
    if (used == null || total == null || total <= 0) return null;
    return (used, total);
  } catch (_) {
    return null;
  }
}

/// Buka berkas dengan aplikasi lain (pemutar, penampil, dst).
/// Mengembalikan false bila tidak ada aplikasi yang bisa membukanya.
Future<bool> openFile(String path) async {
  try {
    final ok = await _storageChannel.invokeMethod<bool>('openFile', path);
    return ok ?? false;
  } catch (_) {
    return false;
  }
}

enum DownloadStatus { downloading, paused, done, failed }

/// Satu entri unduhan.
class DownloadItem {
  DownloadItem({
    required this.taskId,
    required this.url,
    required this.fileName,
    this.task,
    this.destination = 'downloads',
    this.subfolder = '',
  });

  final String taskId;
  final String url;
  final String fileName;

  /// Tujuan berkas selesai (nama [SharedStorage], mis. 'downloads').
  /// Dicatat saat unduhan dibuat, jadi perubahan setelan lokasi hanya
  /// berlaku untuk unduhan BARU; yang sedang berjalan tidak pindah.
  final String destination;

  /// Subfolder di dalam tujuan (mis. 'ROM'), '' = langsung di tujuan.
  final String subfolder;

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
        'destination': destination,
        'subfolder': subfolder,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    final item = DownloadItem(
      taskId: json['id']?.toString() ?? '',
      url: json['url'] as String? ?? '',
      fileName: json['fileName'] as String? ?? 'unduhan',
      destination: json['destination'] as String? ?? 'downloads',
      subfolder: json['subfolder'] as String? ?? '',
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

  /// Pindahkan berkas selesai ke lokasi tujuan yang dicatat saat
  /// unduhan dibuat (folder bersama + subfolder). Dijaga supaya hanya
  /// berjalan sekali per item.
  Future<void> _moveToShared(DownloadItem item) async {
    if (item.sharedPath != null) return;
    if (!_moving.add(item.taskId)) return;
    try {
      final task = item.task;
      if (task == null) return;
      final destination = SharedStorage.values.firstWhere(
        (s) => s.name == item.destination,
        orElse: () => SharedStorage.downloads,
      );
      final newPath = await FileDownloader().moveToSharedStorage(
        task,
        destination,
        directory: item.subfolder,
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
  /// di status item. Lokasi tujuan dicatat dari setelan saat ini, jadi
  /// perubahan setelan sesudahnya tidak mengubah unduhan ini.
  Future<void> startDownload(String url) async {
    final task = await _buildTask(url, fileNameFromUrl(url));
    final settings = BrowserSettings.instance;
    final item = DownloadItem(
      taskId: task.taskId,
      url: url,
      fileName: task.filename,
      task: task,
      destination: settings.downloadLocation.name,
      subfolder: settings.downloadSubfolder,
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

  /// Bagikan berkas selesai lewat lembar berbagi sistem.
  /// Mengembalikan false bila berkas belum ada di penyimpanan.
  Future<bool> shareFile(DownloadItem item) async {
    final path = item.sharedPath ?? item.savedPath;
    if (path == null) return false;
    if (!await File(path).exists()) return false;
    try {
      await Share.shareXFiles(<XFile>[XFile(path)]);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Format ukuran ala Chrome Indonesia: koma sebagai desimal,
/// 2 angka di belakang koma untuk MB/GB ("48,38 MB", "3,80 GB").
String formatBytesId(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1).replaceAll('.', ',')} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2).replaceAll('.', ',')} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2).replaceAll('.', ',')} GB';
}

/// Format sisa waktu ala Chrome Indonesia: "45 detik lagi",
/// "13 menit lagi", "1 jam 5 menit lagi".
String formatEtaId(int seconds) {
  if (seconds < 60) return '$seconds detik lagi';
  if (seconds < 3600) return '${seconds ~/ 60} menit lagi';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (minutes == 0) return '$hours jam lagi';
  return '$hours jam $minutes menit lagi';
}

/// Halaman Unduhan ala Chrome asli.
///
/// - AppBar: judul "Download", gerigi (Setelan unduhan), kaca pembesar
///   (cari berdasarkan nama berkas), X (tutup halaman).
/// - Baris pemakaian penyimpanan perangkat di bawah AppBar.
/// - Seksi "Baru saja" di atas daftar.
/// - Tiap item: lingkaran di kiri (jeda biru saat mengunduh, berkas
///   abu-abu saat selesai), nama berkas dipotong elipsis, baris status
///   ala Chrome ("48,38 MB / 3,80 GB • 13 menit lagi"). Tanpa progress
///   bar dan tanpa jalur berkas internal.
/// - Kanan item: X (batalkan) saat mengunduh/dijeda; menu ⋮ saat
///   selesai (Buka, Bagikan, Hapus dari daftar).
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  bool _searching = false;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  /// Teks "69,99 MB terpakai dari 116,56 GB"; null = belum termuat
  /// atau gagal dibaca (baris disembunyikan).
  String? _storageText;

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStorageInfo() async {
    final info = await getStorageInfo();
    if (!mounted || info == null) return;
    setState(() {
      _storageText =
          '${formatBytesId(info.$1)} terpakai dari ${formatBytesId(info.$2)}';
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Baris status ala Chrome untuk satu item.
  String _statusText(DownloadItem item) {
    final String size;
    if (item.total > 0) {
      size =
          '${formatBytesId(item.received)} / ${formatBytesId(item.total)}';
    } else if (item.received > 0) {
      size = formatBytesId(item.received);
    } else {
      size = '';
    }
    switch (item.status) {
      case DownloadStatus.downloading:
        if (size.isEmpty) return 'Mengunduh…';
        if (item.etaSeconds >= 0) {
          return '$size • ${formatEtaId(item.etaSeconds)}';
        }
        return size;
      case DownloadStatus.paused:
        return size.isEmpty ? 'Dijeda' : 'Dijeda • $size';
      case DownloadStatus.done:
        return size;
      case DownloadStatus.failed:
        return item.error == null ? 'Gagal' : 'Gagal: ${item.error}';
    }
  }

  /// Lingkaran di kiri item. Diketuk untuk jeda/lanjutkan saat
  /// mengunduh atau dijeda (seperti Chrome).
  Widget _leadingCircle(DownloadItem item) {
    final bool active = item.status == DownloadStatus.downloading ||
        item.status == DownloadStatus.paused;
    final Color bg =
        active ? const Color(0xFFE8F0FE) : const Color(0xFFF1F3F4);
    final Color fg =
        active ? const Color(0xFF1A73E8) : const Color(0xFF5F6368);
    final IconData icon;
    switch (item.status) {
      case DownloadStatus.downloading:
        icon = Icons.pause;
        break;
      case DownloadStatus.paused:
        icon = Icons.play_arrow;
        break;
      case DownloadStatus.done:
        icon = Icons.insert_drive_file;
        break;
      case DownloadStatus.failed:
        icon = Icons.error_outline;
        break;
    }
    final VoidCallback? onTap;
    if (item.status == DownloadStatus.downloading) {
      onTap = () => DownloadManager.instance.pauseDownload(item);
    } else if (item.status == DownloadStatus.paused) {
      onTap = () => DownloadManager.instance.resumeDownload(item);
    } else {
      onTap = null;
    }
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: fg, size: 24),
      ),
    );
  }

  Widget _trailing(DownloadItem item) {
    if (item.status == DownloadStatus.downloading ||
        item.status == DownloadStatus.paused) {
      return IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Batalkan',
        onPressed: () => DownloadManager.instance.cancelDownload(item),
      );
    }
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) async {
        if (value == 'hapus') {
          DownloadManager.instance.removeItem(item);
          return;
        }
        if (item.status != DownloadStatus.done) return;
        final path = item.sharedPath ?? item.savedPath;
        if (path == null) {
          _showMessage('Berkas tidak ditemukan');
          return;
        }
        if (value == 'buka') {
          final ok = await openFile(path);
          if (!ok && mounted) {
            _showMessage('Tidak ada aplikasi untuk membuka berkas ini');
          }
        } else if (value == 'bagikan') {
          final ok = await DownloadManager.instance.shareFile(item);
          if (!ok && mounted) {
            _showMessage('Berkas tidak bisa dibagikan');
          }
        }
      },
      itemBuilder: (context) {
        final entries = <PopupMenuEntry<String>>[];
        if (item.status == DownloadStatus.done) {
          entries.add(const PopupMenuItem<String>(
            value: 'buka',
            child: Text('Buka'),
          ));
          entries.add(const PopupMenuItem<String>(
            value: 'bagikan',
            child: Text('Bagikan'),
          ));
        }
        entries.add(const PopupMenuItem<String>(
          value: 'hapus',
          child: Text('Hapus dari daftar'),
        ));
        return entries;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Cari unduhan',
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  setState(() => _query = value.trim().toLowerCase());
                },
              )
            : const Text('Download'),
        actions: <Widget>[
          if (!_searching)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Setelan unduhan',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const DownloadSettingsPage(),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Cari',
            onPressed: () {
              setState(() {
                if (_searching) {
                  _searching = false;
                  _query = '';
                  _searchController.clear();
                } else {
                  _searching = true;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Tutup',
            onPressed: () {
              if (_searching) {
                setState(() {
                  _searching = false;
                  _query = '';
                  _searchController.clear();
                });
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<DownloadItem>>(
        valueListenable: DownloadManager.instance.items,
        builder: (context, downloads, _) {
          final shown = _query.isEmpty
              ? downloads
              : downloads
                  .where((item) =>
                      item.fileName.toLowerCase().contains(_query))
                  .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_storageText != null)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    _storageText!,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'Baru saja',
                  style: TextStyle(fontSize: 15),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Text(
                          downloads.isEmpty
                              ? 'Belum ada unduhan.'
                              : 'Tidak ada yang cocok.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, index) {
                          final item = shown[index];
                          return ListTile(
                            leading: _leadingCircle(item),
                            title: Text(
                              item.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _statusText(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: _trailing(item),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
