// Utilitas URL dan konstanta browser.
//
// Dipakai bersama oleh layar utama, tab, dan pengelola unduhan.

/// User agent desktop (Chrome di Windows) untuk mode "Situs desktop".
const String desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/// Apakah teks yang diketik terlihat seperti URL (bukan kata kunci cari).
bool looksLikeUrl(String input) {
  final text = input.trim();
  if (text.isEmpty) return false;
  if (text.contains(' ')) return false;
  if (text.startsWith('http://') || text.startsWith('https://')) return true;
  // Bentuk domain: ada titik, tidak diawali/diakhiri titik.
  return text.contains('.') && !text.startsWith('.') && !text.endsWith('.');
}

/// Tambah skema https:// bila belum ada.
String normalizeUrl(String input) {
  var text = input.trim();
  if (!text.startsWith('http://') && !text.startsWith('https://')) {
    text = 'https://$text';
  }
  return text;
}

/// Ubah ketikan bilah alamat menjadi URL tujuan:
/// URL langsung bila mirip URL, selebihnya cari di Google.
String toNavigationUrl(String input) {
  final text = input.trim();
  if (text.isEmpty) return 'https://www.google.com';
  if (looksLikeUrl(text)) return normalizeUrl(text);
  return 'https://www.google.com/search?q=${Uri.encodeComponent(text)}';
}

/// Ekstensi berkas yang dianggap unduhan (bukan halaman web).
const List<String> downloadExtensions = <String>[
  'apk', 'zip', 'rar', '7z', 'tar', 'gz', 'iso', 'exe', 'dmg',
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'epub', 'mobi',
  'mp3', 'mp4', 'mkv', 'avi', 'mov', 'jpg', 'jpeg', 'png', 'gif', 'webp',
];

/// Apakah URL ini menunjuk ke berkas unduhan (berdasarkan ekstensi path).
bool isDownloadUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final path = uri.path.toLowerCase();
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return false;
  return downloadExtensions.contains(path.substring(dot + 1));
}

/// Nama berkas dari URL (segmen path terakhir).
String fileNameFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.pathSegments.isEmpty) return 'unduhan';
  final name = uri.pathSegments.last;
  return name.isEmpty ? 'unduhan' : name;
}
