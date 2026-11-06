import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils.dart';

enum DownloadStatus { downloading, paused, done, failed }

/// Satu entri unduhan.
class DownloadItem {
  DownloadItem({required this.url, required this.fileName, int? id})
      : id = id ?? DownloadItem._newId();

  static int _lastId = 0;

  static int _newId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now <= _lastId) return ++_lastId;
    _lastId = now;
    return now;
  }

  static void noteId(int id) {
    if (id > _lastId) _lastId = id;
  }

  final int id;
  final String url;
  final String fileName;
  DownloadStatus status = DownloadStatus.downloading;
  double progress = 0;
  int received = 0;
  int total = -1;
  double speed = 0; // byte/detik
  int etaSeconds = -1; // -1 = tidak diketahui
  String? savedPath;
  String? error;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'url': url,
        'fileName': fileName,
        'status': status.name,
        'progress': progress,
        'received': received,
        'total': total,
        'savedPath': savedPath,
        'error': error,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    final item = DownloadItem(
      url: json['url'] as String? ?? '',
      fileName: json['fileName'] as String? ?? 'unduhan',
      id: json['id'] as int? ?? DownloadItem._newId(),
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
    item.error = json['error'] as String?;
    return item;
  }
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

/// Sampel terakhir untuk menghitung kecepatan unduhan.
class _SpeedSample {
  _SpeedSample(this.time, this.received);

  DateTime time;
  int received;
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
///
/// Final: daftar unduhan tersimpan (tahan aplikasi ditutup), ada kecepatan
/// dan sisa waktu, ada notifikasi progres dengan tombol aksi, dan berkas
/// selesai dipindah ke folder Unduhan publik via MediaStore.
class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  static const String _prefsKey = 'downloads_v1';
  static const MethodChannel _channel =
      MethodChannel('com.modol.chrome_lite_flutter/downloads');

  /// Dipanggil saat notifikasi ditekan (bukan tombol aksi): buka halaman
  /// Unduhan. Diisi dari main.dart.
  static void Function()? onOpenDownloads;

  final ValueNotifier<List<DownloadItem>> items =
      ValueNotifier<List<DownloadItem>>(<DownloadItem>[]);

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;

  final Map<DownloadItem, _ActiveDownload> _active =
      <DownloadItem, _ActiveDownload>{};
  final Map<DownloadItem, Future<void>> _tasks =
      <DownloadItem, Future<void>>{};
  final Map<int, _SpeedSample> _speedSamples = <int, _SpeedSample>{};
  final Map<int, int> _notifIds = <int, int>{};
  int _nextNotifId = 1000;
  final Map<int, DateTime> _lastNotifyAt = <int, DateTime>{};
  DateTime _lastRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSaveAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Siapkan notifikasi + pulihkan unduhan tersimpan. Dipanggil sekali
  /// saat aplikasi mulai (dari initState halaman utama).
  Future<void> init() async {
    await _initNotifications();
    await restore();
  }

  Future<void> _initNotifications() async {
    if (_notificationsReady) return;
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final id = int.tryParse(response.payload ?? '');
        if (id == null) return;
        final action = response.actionId ?? 'open';
        final item = _findById(id);
        switch (action) {
          case 'pause':
            if (item != null) pauseDownload(item);
            break;
          case 'resume':
            if (item != null) resumeDownload(item);
            break;
          case 'cancel':
            if (item != null) cancelDownload(item);
            break;
          default:
            onOpenDownloads?.call();
            break;
        }
      },
    );
    // Android 13+ butuh izin notifikasi saat runtime; di bawah itu no-op.
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _notificationsReady = true;
  }

  DownloadItem? _findById(int id) {
    for (final item in items.value) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Beri tahu pendengar bahwa isi item berubah (progress/status).
  /// Dibatasi ~5x/detik supaya halaman Unduhan tidak dibangun ulang
  /// tiap chunk; perubahan status selalu dipaksa.
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

  /// Pulihkan daftar unduhan dari penyimpanan. Unduhan yang terputus
  /// saat aplikasi ditutup kembali sebagai dijeda (bila berkas setengah
  /// jadinya masih ada) atau gagal (bila berkasnya hilang).
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
        DownloadItem.noteId(item.id);
        if (item.status == DownloadStatus.downloading) {
          final path = item.savedPath;
          if (path != null && await File(path).exists()) {
            item.received = await File(path).length();
            item.status = DownloadStatus.paused;
            item.progress =
                item.total > 0 ? item.received / item.total : 0;
          } else {
            item.status = DownloadStatus.failed;
            item.error = 'Unduhan terputus';
            item.savedPath = null;
          }
        }
        restored.add(item);
      }
      if (restored.isNotEmpty) {
        items.value = restored;
      }
    } catch (_) {
      // Abaikan; mulai dengan daftar kosong.
    }
  }

  // ---------- Notifikasi ----------

  int _notifIdFor(DownloadItem item) {
    return _notifIds.putIfAbsent(item.id, () => _nextNotifId++);
  }

  String _notifyBody(DownloadItem item) {
    final size = item.total > 0
        ? ' • ${_formatBytes(item.received)} / ${_formatBytes(item.total)}'
        : (item.received > 0 ? ' • ${_formatBytes(item.received)}' : '');
    switch (item.status) {
      case DownloadStatus.downloading:
        final speed = item.speed > 0
            ? ' • ${_formatBytes(item.speed.round())}/s'
            : '';
        final eta = item.etaSeconds >= 0
            ? ' • sisa ${_formatEta(item.etaSeconds)}'
            : '';
        return 'Mengunduh... ${(item.progress * 100).toStringAsFixed(0)}%$size$speed$eta';
      case DownloadStatus.paused:
        return 'Dijeda ${(item.progress * 100).toStringAsFixed(0)}%$size';
      case DownloadStatus.done:
        return 'Selesai$size';
      case DownloadStatus.failed:
        return 'Gagal${item.error == null ? '' : ': ${item.error}'}';
    }
  }

  AndroidNotificationDetails _notifyDetails(DownloadItem item) {
    final downloading = item.status == DownloadStatus.downloading;
    final paused = item.status == DownloadStatus.paused;
    return AndroidNotificationDetails(
      'downloads',
      'Unduhan',
      channelDescription: 'Progres unduhan Chrome Lite',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: downloading || paused,
      maxProgress: 100,
      progress: (item.progress * 100).round().clamp(0, 100),
      ongoing: downloading,
      autoCancel: !downloading,
      onlyAlertOnce: true,
      actions: downloading
          ? const <AndroidNotificationAction>[
              AndroidNotificationAction(
                'pause',
                'Jeda',
                showsUserInterface: true,
              ),
              AndroidNotificationAction(
                'cancel',
                'Batal',
                showsUserInterface: true,
              ),
            ]
          : paused
              ? const <AndroidNotificationAction>[
                  AndroidNotificationAction(
                    'resume',
                    'Lanjutkan',
                    showsUserInterface: true,
                  ),
                  AndroidNotificationAction(
                    'cancel',
                    'Batal',
                    showsUserInterface: true,
                  ),
                ]
              : null,
    );
  }

  Future<void> _showNotification(DownloadItem item) async {
    if (!_notificationsReady) return;
    try {
      await _notifications.show(
        _notifIdFor(item),
        item.fileName,
        _notifyBody(item),
        NotificationDetails(android: _notifyDetails(item)),
        payload: '${item.id}',
      );
    } catch (_) {
      // Abaikan; unduhan tetap jalan tanpa notifikasi.
    }
  }

  /// Perbarui notifikasi progres, paling sering 1x/detik.
  void _notifySoon(DownloadItem item) {
    if (!_notificationsReady) return;
    final now = DateTime.now();
    final last = _lastNotifyAt[item.id];
    if (last != null && now.difference(last).inMilliseconds < 1000) return;
    _lastNotifyAt[item.id] = now;
    _showNotification(item);
  }

  /// Perbarui notifikasi segera (perubahan status).
  void _notifyNow(DownloadItem item) {
    if (!_notificationsReady) return;
    _lastNotifyAt[item.id] = DateTime.now();
    _showNotification(item);
  }

  Future<void> _hideNotification(DownloadItem item) async {
    if (!_notificationsReady) return;
    try {
      await _notifications.cancel(_notifIdFor(item));
    } catch (_) {
      // Abaikan.
    }
  }

  // ---------- Folder tujuan ----------

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

  /// Pindahkan berkas selesai ke folder Unduhan publik (via kanal Android).
  /// Kembalikan path tampilan tujuan, atau null bila gagal (berkas tetap
  /// di folder aplikasi).
  Future<String?> _moveToPublicDownloads(DownloadItem item) async {
    final path = item.savedPath;
    if (path == null) return null;
    try {
      final dest = await _channel.invokeMethod<String>(
        'moveToDownloads',
        <String, dynamic>{'path': path, 'fileName': item.fileName},
      );
      return dest;
    } catch (_) {
      return null;
    }
  }

  // ---------- Unduh ----------

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
          final now = DateTime.now();
          final sample = _speedSamples[item.id];
          if (sample == null) {
            _speedSamples[item.id] = _SpeedSample(now, item.received);
          } else if (now.difference(sample.time).inMilliseconds >= 500) {
            final elapsed =
                now.difference(sample.time).inMilliseconds / 1000;
            if (elapsed > 0) {
              item.speed = (item.received - sample.received) / elapsed;
              item.etaSeconds = item.total > 0 && item.speed > 0
                  ? ((item.total - item.received) / item.speed).round()
                  : -1;
            }
            _speedSamples[item.id] = _SpeedSample(now, item.received);
          }
          if (item.total > 0) item.progress = item.received / item.total;
          _refresh();
          _notifySoon(item);
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
      item.speed = 0;
      item.etaSeconds = -1;
      _speedSamples.remove(item.id);
      // Pindahkan ke folder Unduhan publik (bila bisa).
      final publicPath = await _moveToPublicDownloads(item);
      if (publicPath != null) item.savedPath = publicPath;
      item.status = DownloadStatus.done;
      _refresh(force: true);
      _saveNow();
      _notifyNow(item);
    } catch (e) {
      if (active.stopping) return; // Dijeda/dibatalkan.
      try {
        await sink?.close();
      } catch (_) {
        // Abaikan.
      }
      sink = null;
      _speedSamples.remove(item.id);
      if (startByte > 0) {
        // Gagal saat melanjutkan: simpan berkas setengah jadi supaya
        // masih bisa dicoba lanjut lagi.
        item.status = DownloadStatus.paused;
        item.error = e.toString();
        item.speed = 0;
        item.etaSeconds = -1;
        _refresh(force: true);
        _saveNow();
        _notifyNow(item);
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
    _refresh(force: true);
    _saveNow();
    _notifyNow(item);
  }

  /// Mulai unduhan baru untuk [url]. Tidak melempar; kegagalan dicatat
  /// di status item.
  Future<void> startDownload(String url) async {
    final item =
        DownloadItem(url: url, fileName: fileNameFromUrl(url));
    items.value = <DownloadItem>[...items.value, item];
    _refresh(force: true);
    _saveNow();
    _notifyNow(item);
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
    item.speed = 0;
    item.etaSeconds = -1;
    _refresh(force: true);
    _saveNow();
    _notifyNow(item);
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
      _refresh(force: true);
      _saveNow();
      _notifyNow(item);
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
      _refresh(force: true);
      _saveNow();
      _notifyNow(item);
      return;
    }
    item.status = DownloadStatus.downloading;
    item.error = null;
    _refresh(force: true);
    _saveNow();
    _notifyNow(item);
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
    _hideNotification(item);
    final path = item.savedPath;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {
        // Abaikan.
      }
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
    _hideNotification(item);
    items.value.remove(item);
    _refresh(force: true);
    _saveNow();
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
