import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Satu berita trending: judul + tautan.
class TrendingItem {
  TrendingItem({required this.title, required this.url});

  final String title;
  final String url;
}

/// RSS Google News Indonesia.
const String _trendingRssUrl =
    'https://news.google.com/rss?hl=id&gl=ID&ceid=ID:id';

/// Bersihkan CDATA dan entitas HTML umum dari teks RSS.
String _cleanRssText(String raw) {
  var text = raw.trim();
  if (text.startsWith('<![CDATA[') && text.endsWith(']]>')) {
    text = text.substring(9, text.length - 3);
  }
  return text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .trim();
}

/// Ambil berita teratas dari RSS Google News Indonesia.
///
/// Mengembalikan daftar kosong bila gagal (jaringan mati, RSS berubah,
/// dsb.) — pemanggil tetap menampilkan beranda tanpa berita.
Future<List<TrendingItem>> fetchTrendingNews({int limit = 6}) async {
  try {
    final response = await http
        .get(Uri.parse(_trendingRssUrl))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return <TrendingItem>[];
    final body = response.body;
    final items = <TrendingItem>[];
    final itemReg = RegExp(r'<item>(.*?)</item>', dotAll: true);
    final titleReg = RegExp(r'<title>(.*?)</title>', dotAll: true);
    final linkReg = RegExp(r'<link>(.*?)</link>', dotAll: true);
    for (final m in itemReg.allMatches(body)) {
      if (items.length >= limit) break;
      final block = m.group(1) ?? '';
      final titleMatch = titleReg.firstMatch(block);
      final linkMatch = linkReg.firstMatch(block);
      if (titleMatch == null || linkMatch == null) continue;
      final title = _cleanRssText(titleMatch.group(1) ?? '');
      final url = _cleanRssText(linkMatch.group(1) ?? '');
      if (title.isEmpty || url.isEmpty) continue;
      items.add(TrendingItem(title: title, url: url));
    }
    return items;
  } catch (_) {
    return <TrendingItem>[];
  }
}

/// Bagian "Trending" di beranda: daftar berita teratas, ketuk untuk buka.
class TrendingSection extends StatelessWidget {
  const TrendingSection({
    super.key,
    required this.items,
    required this.onOpen,
  });

  final List<TrendingItem> items;
  final void Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 32),
        const Row(
          children: <Widget>[
            Icon(Icons.trending_up, size: 20),
            SizedBox(width: 6),
            Text(
              'Trending',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...items.map(
          (item) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.article, size: 20),
              title: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              onTap: () => onOpen(item.url),
            ),
          ),
        ),
      ],
    );
  }
}
