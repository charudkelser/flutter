import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Satu bookmark: judul + URL.
class BookmarkItem {
  BookmarkItem({required this.title, required this.url});

  factory BookmarkItem.fromJson(Map<String, dynamic> json) {
    return BookmarkItem(
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }

  final String title;
  final String url;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'url': url,
      };
}

/// Penyimpanan bookmark permanen (SharedPreferences, daftar JSON).
class BookmarkStore {
  BookmarkStore._();
  static final BookmarkStore instance = BookmarkStore._();

  static const String _key = 'bookmarks';

  SharedPreferences? _prefs;
  final ValueNotifier<List<BookmarkItem>> items =
      ValueNotifier<List<BookmarkItem>>(<BookmarkItem>[]);

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getStringList(_key) ?? <String>[];
    final loaded = <BookmarkItem>[];
    for (final s in raw) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map<String, dynamic>) {
          loaded.add(BookmarkItem.fromJson(decoded));
        }
      } catch (_) {
        // Entri rusak dilewati.
      }
    }
    items.value = loaded;
  }

  Future<void> _save() async {
    await _prefs?.setStringList(
      _key,
      items.value.map((b) => jsonEncode(b.toJson())).toList(),
    );
  }

  bool isBookmarked(String url) {
    return items.value.any((b) => b.url == url);
  }

  Future<void> add(String title, String url) async {
    if (isBookmarked(url)) return;
    items.value = <BookmarkItem>[
      ...items.value,
      BookmarkItem(title: title, url: url),
    ];
    await _save();
  }

  Future<void> remove(String url) async {
    items.value =
        items.value.where((b) => b.url != url).toList();
    await _save();
  }
}

/// Halaman Daftar Bookmark.
class BookmarkPage extends StatelessWidget {
  const BookmarkPage({super.key, required this.onOpen});

  /// Dipanggil dengan URL saat bookmark diketuk.
  final void Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmark')),
      body: ValueListenableBuilder<List<BookmarkItem>>(
        valueListenable: BookmarkStore.instance.items,
        builder: (context, bookmarks, _) {
          if (bookmarks.isEmpty) {
            return const Center(
              child: Text('Belum ada bookmark.\nBuka halaman lalu pilih "Simpan bookmark" di menu.'),
            );
          }
          return ListView.builder(
            itemCount: bookmarks.length,
            itemBuilder: (context, index) {
              final item = bookmarks[index];
              return ListTile(
                leading: const Icon(Icons.star),
                title: Text(
                  item.title.isEmpty ? item.url : item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  item.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  onOpen(item.url);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Hapus bookmark',
                  onPressed: () =>
                      BookmarkStore.instance.remove(item.url),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
