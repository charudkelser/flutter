import 'dart:async';

import 'package:flutter/material.dart';

import 'trending.dart';
import 'utils.dart';

/// Teks hint kapsul cari yang berputar tiap beberapa detik.
const List<String> _searchHints = <String>[
  'Telusuri Google atau ketik URL',
  'Coba cari berita hari ini',
  'Ketik alamat situs, mis. youtube.com',
  'Cari resep, lagu, atau apa saja',
  'Apa yang ingin kamu cari?',
];

/// Warna latar beranda ala Chrome (biru pucat); samaran gelap.
const Color _homeBgLight = Color(0xFFE9EEF6);
const Color _homeBgDark = Color(0xFF212121);

/// Warna kapsul cari dan tombol pil ala Chrome.
const Color _pillLight = Color(0xFFD7E3F4);
const Color _pillDark = Color(0xFF424242);

/// Beranda tab baru ala Chrome: wordmark Google, kapsul cari besar,
/// tombol Mode AI dan Samaran, grid pintasan situs.
class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    required this.onNavigate,
    required this.onNewIncognito,
    this.incognito = false,
  });

  /// Dipanggil dengan URL tujuan saat pintasan ditekan atau pencarian
  /// dikirim.
  final void Function(String url) onNavigate;

  /// Dipanggil saat tombol Samaran ditekan (buka tab samaran baru).
  final VoidCallback onNewIncognito;

  /// Tab samaran: beranda ikut gelap seperti bilah atas.
  final bool incognito;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _hintTimer;
  int _hintIndex = 0;
  List<TrendingItem> _trending = <TrendingItem>[];

  @override
  void initState() {
    super.initState();
    // Hint cari berputar tiap 4 detik.
    _hintTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() => _hintIndex = (_hintIndex + 1) % _searchHints.length);
    });
    // Berita trending (gagal dimuat = beranda tetap jalan tanpa berita).
    fetchTrendingNews().then((items) {
      if (!mounted) return;
      setState(() => _trending = items);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _submitSearch() {
    final text = _searchController.text.trim();
    if (text.isEmpty) return;
    widget.onNavigate(toNavigationUrl(text));
  }

  /// Satu huruf wordmark Google dengan warnanya masing-masing.
  Widget _wordmarkLetter(String letter, Color color) {
    return Text(
      letter,
      style: TextStyle(
        color: color,
        fontSize: 48,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _shortcut({
    required String label,
    required String url,
    required Color color,
    required Widget child,
  }) {
    return InkWell(
      onTap: () => widget.onNavigate(url),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(28),
            ),
            alignment: Alignment.center,
            child: child,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: widget.incognito ? Colors.white70 : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Satu tombol pil di bawah kapsul cari (Mode AI / Samaran).
  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final incognito = widget.incognito;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: incognito ? _pillDark : _pillLight,
            borderRadius: BorderRadius.circular(28),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 24,
                color: incognito ? Colors.white : Colors.black87,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: incognito ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final incognito = widget.incognito;
    // Latar penuh dan tidak tembus pandang: halaman situs di bawah
    // (WebView) tidak boleh berbayang menembus beranda.
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: incognito ? _homeBgDark : _homeBgLight,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: <Widget>[
            const SizedBox(height: 24),
            // Wordmark Google (teks berwarna).
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _wordmarkLetter('G', const Color(0xFF4285F4)),
                _wordmarkLetter('o', const Color(0xFFEA4335)),
                _wordmarkLetter('o', const Color(0xFFFBBC05)),
                _wordmarkLetter('g', const Color(0xFF4285F4)),
                _wordmarkLetter('l', const Color(0xFF34A853)),
                _wordmarkLetter('e', const Color(0xFFEA4335)),
              ],
            ),
            const SizedBox(height: 32),
            // Kapsul cari besar ala Chrome.
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submitSearch(),
              style: TextStyle(
                fontSize: 17,
                color: incognito ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: _searchHints[_hintIndex],
                hintStyle: TextStyle(
                  fontSize: 17,
                  color: incognito ? Colors.white54 : Colors.black45,
                ),
                prefixIcon: Icon(
                  Icons.add,
                  size: 28,
                  color: incognito ? Colors.white : Colors.black87,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    Icons.photo_camera,
                    color: incognito ? Colors.white70 : Colors.black54,
                  ),
                  tooltip: 'Telusuri dengan kamera',
                  onPressed: () =>
                      widget.onNavigate('https://lens.google.com'),
                ),
                filled: true,
                fillColor: incognito ? _pillDark : _pillLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(32),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Tombol Mode AI dan Samaran.
            Row(
              children: <Widget>[
                _pillButton(
                  icon: Icons.auto_awesome,
                  label: 'Mode AI',
                  onTap: () => widget.onNavigate(
                    'https://www.google.com/search?udm=50',
                  ),
                ),
                const SizedBox(width: 12),
                _pillButton(
                  icon: Icons.visibility_off,
                  label: 'Samaran',
                  onTap: widget.onNewIncognito,
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Grid pintasan.
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 8,
              children: <Widget>[
                _shortcut(
                  label: 'Google',
                  url: 'https://www.google.com',
                  color: const Color(0xFF4285F4),
                  child: const Text(
                    'G',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _shortcut(
                  label: 'YouTube',
                  url: 'https://www.youtube.com',
                  color: const Color(0xFFFF0000),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                _shortcut(
                  label: 'Facebook',
                  url: 'https://www.facebook.com',
                  color: const Color(0xFF1877F2),
                  child: const Text(
                    'f',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _shortcut(
                  label: 'Instagram',
                  url: 'https://www.instagram.com',
                  color: const Color(0xFFE1306C),
                  child: const Icon(
                    Icons.camera_alt,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                _shortcut(
                  label: 'Wikipedia',
                  url: 'https://www.wikipedia.org',
                  color: const Color(0xFF616161),
                  child: const Text(
                    'W',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            // Berita trending (tidak muncul bila gagal dimuat).
            TrendingSection(
              items: _trending,
              onOpen: (url) => widget.onNavigate(url),
            ),
          ],
        ),
      ),
    );
  }
}
