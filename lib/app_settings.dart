import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Setelan browser yang tersimpan permanen (SharedPreferences).
///
/// Dipakai untuk saklar AdBlock dan lokasi unduhan. Nilai bawaan di
/// memori sama dengan nilai bawaan yang tersimpan, jadi aman dibaca
/// sebelum [init] selesai.
class BrowserSettings {
  BrowserSettings._();
  static final BrowserSettings instance = BrowserSettings._();

  static const String _adBlockKey = 'adblock_enabled';
  static const String _downloadLocationKey = 'download_location';
  static const String _downloadSubfolderKey = 'download_subfolder';

  SharedPreferences? _prefs;

  /// Saklar AdBlock. Bawaan: ON (true).
  final ValueNotifier<bool> adBlockNotifier = ValueNotifier<bool>(true);

  bool get adBlockEnabled => adBlockNotifier.value;

  /// Lokasi tujuan berkas selesai diunduh (folder bersama Android).
  /// Bawaan: [SharedStorage.downloads] (folder Unduhan).
  final ValueNotifier<SharedStorage> downloadLocationNotifier =
      ValueNotifier<SharedStorage>(SharedStorage.downloads);

  SharedStorage get downloadLocation => downloadLocationNotifier.value;

  /// Subfolder opsional di dalam lokasi tujuan (mis. "ROM" →
  /// Unduhan/ROM). Bawaan: '' (langsung di lokasi tujuan).
  final ValueNotifier<String> downloadSubfolderNotifier =
      ValueNotifier<String>('');

  String get downloadSubfolder => downloadSubfolderNotifier.value;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    adBlockNotifier.value = _prefs!.getBool(_adBlockKey) ?? true;
    final locationName = _prefs!.getString(_downloadLocationKey);
    if (locationName != null) {
      downloadLocationNotifier.value = SharedStorage.values.firstWhere(
        (s) => s.name == locationName,
        orElse: () => SharedStorage.downloads,
      );
    }
    downloadSubfolderNotifier.value =
        _prefs!.getString(_downloadSubfolderKey) ?? '';
  }

  Future<void> setAdBlockEnabled(bool value) async {
    adBlockNotifier.value = value;
    await _prefs?.setBool(_adBlockKey, value);
  }

  Future<void> setDownloadLocation(SharedStorage value) async {
    downloadLocationNotifier.value = value;
    await _prefs?.setString(_downloadLocationKey, value.name);
  }

  /// Simpan subfolder sesudah dibersihkan (tanpa garis miring di ujung
  /// dan tanpa segmen '..' supaya tidak keluar dari lokasi tujuan).
  Future<void> setDownloadSubfolder(String value) async {
    final clean = sanitizeSubfolder(value);
    downloadSubfolderNotifier.value = clean;
    await _prefs?.setString(_downloadSubfolderKey, clean);
  }
}

/// Bersihkan nama subfolder: buang garis miring di ujung, segmen kosong,
/// '.' dan '..'. Hasil '' berarti langsung di lokasi tujuan.
String sanitizeSubfolder(String value) {
  final parts = value.replaceAll('\\', '/').split('/');
  final kept = <String>[];
  for (final part in parts) {
    final p = part.trim();
    if (p.isEmpty || p == '.' || p == '..') continue;
    kept.add(p);
  }
  return kept.join('/');
}

/// Nama tampilan tiap lokasi tujuan unduhan.
String downloadLocationLabel(SharedStorage location) {
  switch (location) {
    case SharedStorage.downloads:
      return 'Unduhan';
    case SharedStorage.images:
      return 'Gambar';
    case SharedStorage.video:
      return 'Video';
    case SharedStorage.audio:
      return 'Musik';
    case SharedStorage.files:
      return 'Dokumen';
    case SharedStorage.external:
      return 'Penyimpanan eksternal';
  }
}

/// Keterangan folder tempat berkas selesai disimpan.
String downloadLocationHint(SharedStorage location) {
  switch (location) {
    case SharedStorage.downloads:
      return 'Folder Unduhan';
    case SharedStorage.images:
      return 'Folder Gambar';
    case SharedStorage.video:
      return 'Folder Video';
    case SharedStorage.audio:
      return 'Folder Musik';
    case SharedStorage.files:
      return 'Folder Dokumen';
    case SharedStorage.external:
      return 'Akar penyimpanan perangkat';
  }
}
