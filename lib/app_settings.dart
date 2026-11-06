import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Setelan browser yang tersimpan permanen (SharedPreferences).
///
/// Dipakai untuk saklar AdBlock. Nilai bawaan di memori sama dengan nilai
/// bawaan yang tersimpan (AdBlock ON), jadi aman dibaca sebelum [init]
/// selesai.
class BrowserSettings {
  BrowserSettings._();
  static final BrowserSettings instance = BrowserSettings._();

  static const String _adBlockKey = 'adblock_enabled';

  SharedPreferences? _prefs;

  /// Saklar AdBlock. Bawaan: ON (true).
  final ValueNotifier<bool> adBlockNotifier = ValueNotifier<bool>(true);

  bool get adBlockEnabled => adBlockNotifier.value;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    adBlockNotifier.value = _prefs!.getBool(_adBlockKey) ?? true;
  }

  Future<void> setAdBlockEnabled(bool value) async {
    adBlockNotifier.value = value;
    await _prefs?.setBool(_adBlockKey, value);
  }
}
