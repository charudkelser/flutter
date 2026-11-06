import 'package:flutter/material.dart';

import 'tab.dart';

/// Halaman pengalih tab: daftar semua tab dengan tombol tutup,
/// plus tombol tab baru.
///
/// Stateful supaya menutup tab langsung memperbarui daftar di halaman ini
/// (setState layar utama tidak membangun ulang route yang sedang dibuka).
class TabSwitcherPage extends StatefulWidget {
  const TabSwitcherPage({
    super.key,
    required this.tabs,
    required this.activeTabId,
    required this.onSelect,
    required this.onClose,
    required this.onNewTab,
  });

  final List<BrowserTab> tabs;
  final int activeTabId;
  final void Function(int tabId) onSelect;
  final void Function(int tabId) onClose;
  final VoidCallback onNewTab;

  @override
  State<TabSwitcherPage> createState() => _TabSwitcherPageState();
}

class _TabSwitcherPageState extends State<TabSwitcherPage> {
  late List<BrowserTab> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = List<BrowserTab>.of(widget.tabs);
  }

  void _closeTab(int tabId) {
    setState(() {
      _tabs.removeWhere((tab) => tab.id == tabId);
    });
    widget.onClose(tabId);
    if (_tabs.isEmpty && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_tabs.length} tab'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Tab baru',
            onPressed: widget.onNewTab,
          ),
        ],
      ),
      body: _tabs.isEmpty
          ? const Center(child: Text('Tidak ada tab.'))
          : ListView.builder(
              itemCount: _tabs.length,
              itemBuilder: (context, index) {
                final tab = _tabs[index];
                final isActive = tab.id == widget.activeTabId;
                return Card(
                  color: isActive
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: Icon(
                      tab.isIncognito
                          ? Icons.visibility_off
                          : Icons.language,
                    ),
                    title: Text(
                      tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      tab.url ?? 'Tab baru',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (tab.isIncognito)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Text(
                              'Samaran',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Tutup tab',
                          onPressed: () => _closeTab(tab.id),
                        ),
                      ],
                    ),
                    onTap: () => widget.onSelect(tab.id),
                  ),
                );
              },
            ),
    );
  }
}
