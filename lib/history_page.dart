import 'package:flutter/material.dart';

/// Satu entri riwayat: URL + judul halaman saat dikunjungi.
class HistoryEntry {
  HistoryEntry({required this.url, required this.title});

  final String url;
  final String title;
}

/// Halaman Riwayat.
///
/// Menerima salinan daftar riwayat; penghapusan per item dan hapus semua
/// diteruskan ke pemilik lewat callback agar sumber (_history) ikut
/// diperbarui.
class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.entries,
    required this.onOpen,
    required this.onDelete,
    required this.onClearAll,
  });

  final List<HistoryEntry> entries;
  final void Function(String url) onOpen;
  final void Function(String url) onDelete;
  final VoidCallback onClearAll;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late List<HistoryEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = List<HistoryEntry>.of(widget.entries);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat'),
        actions: <Widget>[
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Hapus semua',
              onPressed: () {
                widget.onClearAll();
                setState(() => _entries.clear());
              },
            ),
        ],
      ),
      body: _entries.isEmpty
          ? const Center(child: Text('Belum ada riwayat.'))
          : ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(
                    entry.title.isEmpty ? entry.url : entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    entry.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onOpen(entry.url);
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: 'Hapus',
                    onPressed: () {
                      widget.onDelete(entry.url);
                      setState(() => _entries.removeAt(index));
                    },
                  ),
                );
              },
            ),
    );
  }
}
