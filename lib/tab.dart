import 'package:webview_flutter/webview_flutter.dart';

/// Satu tab browser.
///
/// [url] null berarti tab baru yang masih menampilkan beranda.
/// [controller] adalah WebViewController milik tab ini; dibuat sekali dan
/// dipertahankan selama tab hidup, sehingga pindah tab tidak memuat ulang
/// halaman.
class BrowserTab {
  BrowserTab({required this.id, this.isIncognito = false});

  final int id;
  final bool isIncognito;
  final WebViewController controller = WebViewController();

  String? url;
  String title = 'Tab baru';
  int progress = 0;
  bool isLoading = false;
  bool isDesktop = false;
}
