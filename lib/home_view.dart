import 'package:flutter/material.dart';

import 'utils.dart';

/// Beranda tab baru ala Chrome: wordmark Google, kapsul cari, dan grid
/// pintasan situs.
class HomeView extends StatefulWidget {
  const HomeView({super.key, required this.onNavigate});

  /// Dipanggil dengan URL tujuan saat pintasan ditekan atau pencarian
  /// dikirim.
  final void Function(String url) onNavigate;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
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
        fontSize: 44,
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
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
          const SizedBox(height: 24),
          // Kapsul cari.
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submitSearch(),
            decoration: InputDecoration(
              hintText: 'Cari di Google atau ketik URL',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _submitSearch,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
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
        ],
      ),
    );
  }
}
