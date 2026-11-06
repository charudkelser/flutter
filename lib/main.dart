import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'downloads.dart';
import 'home_view.dart';
import 'settings_page.dart';
import 'tab.dart';
import 'tab_switcher.dart';
import 'utils.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chrome Lite Flutter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const BrowserScreen(),
    );
  }
}

/// Layar utama browser: bilah URL, WebView, tab, menu.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final List<BrowserTab> _tabs = <BrowserTab>[];
  int _activeTabId = 0;
  int _nextTabId = 1;

  /// Riwayat tab biasa saja (tab samaran tidak dicatat).
  final List<String> _history = <String>[];

  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();

  BrowserTab get _activeTab =>
      _tabs.firstWhere((tab) => tab.id == _activeTabId);

  @override
  void initState() {
    super.initState();
    _createTabInternal();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  // ---------- Tab ----------

  BrowserTab _createTabInternal({bool incognito = false}) {
    final tab = BrowserTab(id: _nextTabId++, isIncognito: incognito);
    _setupController(tab);
    _tabs.add(tab);
    _activeTabId = tab.id;
    return tab;
  }

  void _newTab({bool incognito = false}) {
    setState(() {
      _createTabInternal(incognito: incognito);
      _syncUrlBar();
    });
  }

  void _closeTab(int tabId) {
    setState(() {
      final wasActive = tabId == _activeTabId;
      _tabs.removeWhere((tab) => tab.id == tabId);
      if (_tabs.isEmpty) {
        _createTabInternal();
      } else if (wasActive) {
        _activeTabId = _tabs.last.id;
      }
      _syncUrlBar();
    });
  }

  void _selectTab(int tabId) {
    _urlFocusNode.unfocus();
    setState(() {
      _activeTabId = tabId;
      _syncUrlBar();
    });
  }

  // ---------- WebView ----------

  void _setupController(BrowserTab tab) {
    tab.controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => tab.progress = progress);
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              tab.isLoading = true;
              tab.url = url;
              _syncUrlBar();
            });
          },
          onPageFinished: (url) async {
            tab.isLoading = false;
            final title = await tab.controller.getTitle();
            if (!mounted) return;
            setState(() {
              tab.url = url;
              if (title != null && title.isNotEmpty) tab.title = title;
              _syncUrlBar();
            });
            if (!tab.isIncognito) _addHistory(url);
          },
          onNavigationRequest: (request) {
            if (request.isMainFrame && isDownloadUrl(request.url)) {
              DownloadManager.instance.startDownload(request.url);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Mengunduh ${fileNameFromUrl(request.url)}',
                  ),
                ),
              );
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            // v1: biarkan halaman menampilkan apa adanya.
          },
        ),
      );
  }

  void _navigate(String input) {
    final url = toNavigationUrl(input);
    _activeTab.controller.loadRequest(Uri.parse(url));
    _urlFocusNode.unfocus();
  }

  void _syncUrlBar() {
    if (_urlFocusNode.hasFocus) return;
    _urlController.text = _activeTab.url ?? '';
  }

  void _addHistory(String url) {
    if (_history.isEmpty || _history.first != url) {
      _history.insert(0, url);
      if (_history.length > 100) _history.removeLast();
    }
  }

  Future<void> _goBack() async {
    if (await _activeTab.controller.canGoBack()) {
      await _activeTab.controller.goBack();
    }
  }

  Future<void> _goForward() async {
    if (await _activeTab.controller.canGoForward()) {
      await _activeTab.controller.goForward();
    }
  }

  Future<void> _reload() async {
    if (_activeTab.url != null) {
      await _activeTab.controller.reload();
    }
  }

  Future<void> _toggleDesktop() async {
    final tab = _activeTab;
    tab.isDesktop = !tab.isDesktop;
    await tab.controller
        .setUserAgent(tab.isDesktop ? desktopUserAgent : null);
    if (tab.url != null) {
      await tab.controller.reload();
    }
    if (mounted) setState(() {});
  }

  // ---------- Menu & halaman ----------

  Future<void> _openTabSwitcher() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TabSwitcherPage(
          tabs: _tabs,
          activeTabId: _activeTabId,
          onSelect: (tabId) {
            _selectTab(tabId);
            Navigator.of(context).pop();
          },
          onClose: (tabId) => _closeTab(tabId),
          onNewTab: () {
            _newTab();
            Navigator.of(context).pop();
          },
        ),
      ),
    );
    if (mounted) setState(() => _syncUrlBar());
  }

  Future<void> _openDownloads() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const DownloadsPage()),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          onClearHistory: () => _history.clear(),
          onClearCookies: () {
            WebViewCookieManager().clearCookies();
          },
          onClearCache: () {
            _activeTab.controller.clearCache();
          },
        ),
      ),
    );
  }

  Future<void> _share() async {
    final url = _activeTab.url;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada halaman untuk dibagikan')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tautan disalin')),
    );
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'new_tab':
        _newTab();
      case 'new_incognito':
        _newTab(incognito: true);
      case 'downloads':
        _openDownloads();
      case 'share':
        _share();
      case 'reload':
        _reload();
      case 'desktop':
        _toggleDesktop();
      case 'settings':
        _openSettings();
    }
  }

  // ---------- Tampilan ----------

  @override
  Widget build(BuildContext context) {
    final tab = _activeTab;
    final incognito = tab.isIncognito;
    final loading = tab.isLoading && tab.progress < 100;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (tab.url != null && await tab.controller.canGoBack()) {
          await tab.controller.goBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: incognito ? Colors.grey[900] : null,
          foregroundColor: incognito ? Colors.white : null,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Kembali',
            onPressed: _goBack,
          ),
          title: TextField(
            controller: _urlController,
            focusNode: _urlFocusNode,
            textInputAction: TextInputAction.go,
            onSubmitted: _navigate,
            style: TextStyle(
              fontSize: 14,
              color: incognito ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: incognito
                  ? 'Samaran: cari atau ketik URL'
                  : 'Cari atau ketik URL',
              hintStyle: TextStyle(
                fontSize: 14,
                color: incognito ? Colors.white54 : Colors.black45,
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 18,
                color: incognito ? Colors.white54 : Colors.black45,
              ),
              filled: true,
              fillColor:
                  incognito ? Colors.grey[800] : Colors.grey[200],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_forward),
              tooltip: 'Maju',
              onPressed: _goForward,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Muat ulang',
              onPressed: _reload,
            ),
            _TabCountButton(
              count: _tabs.length,
              incognito: incognito,
              onPressed: _openTabSwitcher,
            ),
            PopupMenuButton<String>(
              tooltip: 'Menu',
              onSelected: _onMenuSelected,
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'new_tab',
                  child: Text('Tab baru'),
                ),
                const PopupMenuItem<String>(
                  value: 'new_incognito',
                  child: Text('Tab samaran baru'),
                ),
                const PopupMenuItem<String>(
                  value: 'downloads',
                  child: Text('Unduhan'),
                ),
                const PopupMenuItem<String>(
                  value: 'share',
                  child: Text('Bagikan'),
                ),
                const PopupMenuItem<String>(
                  value: 'reload',
                  child: Text('Muat ulang'),
                ),
                PopupMenuItem<String>(
                  value: 'desktop',
                  child: Row(
                    children: <Widget>[
                      Icon(
                        tab.isDesktop ? Icons.check : null,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      const Text('Situs desktop'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'settings',
                  child: Text('Setelan'),
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: loading
                ? LinearProgressIndicator(
                    value: tab.progress > 0 ? tab.progress / 100 : null,
                    minHeight: 3,
                  )
                : const SizedBox(height: 3),
          ),
        ),
        body: tab.url == null
            ? HomeView(onNavigate: _navigate)
            : WebViewWidget(controller: tab.controller),
      ),
    );
  }
}

/// Tombol jumlah tab (kotak berisi angka).
class _TabCountButton extends StatelessWidget {
  const _TabCountButton({
    required this.count,
    required this.incognito,
    required this.onPressed,
  });

  final int count;
  final bool incognito;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Tab',
      onPressed: onPressed,
      icon: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          border: Border.all(
            color: incognito ? Colors.white70 : Colors.black54,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: incognito ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
