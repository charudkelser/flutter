import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'about_page.dart';
import 'app_settings.dart';
import 'bookmarks.dart';
import 'downloads.dart';
import 'history_page.dart';
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
  final List<HistoryEntry> _history = <HistoryEntry>[];

  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();
  final GlobalKey<HomeViewState> _homeKey = GlobalKey<HomeViewState>();
  bool _homeScrolled = false;

  BrowserTab get _activeTab =>
      _tabs.firstWhere((tab) => tab.id == _activeTabId);

  @override
  void initState() {
    super.initState();
    _createTabInternal();
    // Muat setelan (AdBlock) dan bookmark yang tersimpan.
    BrowserSettings.instance.init().then((_) {
      if (mounted) setState(() {});
    });
    BookmarkStore.instance.init();
    // Siapkan notifikasi unduhan + pulihkan daftar unduhan tersimpan.
    DownloadManager.instance.init();
    // Ketukan pada notifikasi unduhan membuka halaman Unduhan.
    DownloadManager.onOpenDownloads = () {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const DownloadsPage()),
      );
    };
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
            if (!tab.isIncognito) {
              _addHistory(url, title ?? '');
            }
            // AdBlock: sembunyikan elemen iklan di halaman.
            if (BrowserSettings.instance.adBlockEnabled) {
              try {
                await tab.controller.runJavaScript(adBlockHideJs);
              } catch (_) {
                // Halaman sudah pergi; abaikan.
              }
            }
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
            // AdBlock: blokir navigasi ke host iklan (bukan googlevideo).
            if (BrowserSettings.instance.adBlockEnabled &&
                isAdUrl(request.url)) {
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
    // Tampilkan WebView segera (tab.url diset optimistis) — WebView sudah
    // menempel di tree sejak awal (lihat body: Stack), jadi loadRequest
    // tidak lagi dipanggil saat WebView belum ada (itu penyebab
    // net::ERR_CACHE_MISS di v1).
    setState(() {
      _activeTab.url = url;
    });
    _activeTab.controller.loadRequest(Uri.parse(url));
    _urlFocusNode.unfocus();
  }

  void _syncUrlBar() {
    if (_urlFocusNode.hasFocus) return;
    _urlController.text = _activeTab.url ?? '';
  }

  void _addHistory(String url, String title) {
    if (_history.isEmpty || _history.first.url != url) {
      _history.insert(0, HistoryEntry(url: url, title: title));
      if (_history.length > 100) _history.removeLast();
    }
  }

  /// Ke beranda aplikasi (ikon home). Halaman WebView tetap tersimpan
  /// di riwayat tab.
  void _goHome() {
    _urlFocusNode.unfocus();
    setState(() {
      _activeTab.url = null;
      _syncUrlBar();
    });
  }

  /// Kapsul cari di bilah atas saat beranda digulir (ala Chrome): ketuk
  /// = kembali ke atas dan fokuskan kolom cari beranda.
  Widget _homeToolbarCapsule() {
    final incognito = _activeTab.isIncognito;
    return InkWell(
      onTap: () => _homeKey.currentState?.focusSearch(),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: incognito ? const Color(0xFF424242) : Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.add,
              size: 28,
              color: incognito ? Colors.white : Colors.black87,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Telusuri Google atau ketik URL',
                style: TextStyle(
                  fontSize: 17,
                  color: incognito ? Colors.white54 : Colors.black45,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.photo_camera,
                color: incognito ? Colors.white70 : Colors.black54,
              ),
              tooltip: 'Telusuri dengan kamera',
              onPressed: () => _navigate('https://lens.google.com'),
            ),
          ],
        ),
      ),
    );
  }

  /// Tombol kembali HP: mundur di riwayat WebView; bila tidak ada riwayat,
  /// kembali ke beranda. Tidak pernah diam tanpa hasil: bila baca riwayat
  /// gagal, langsung ke beranda.
  Future<void> _goBack() async {
    try {
      if (await _activeTab.controller.canGoBack()) {
        await _activeTab.controller.goBack();
        return;
      }
    } catch (_) {
      // WebView belum siap / gagal baca riwayat: jatuh ke beranda.
    }
    if (_activeTab.url != null) {
      setState(() {
        _activeTab.url = null;
        _syncUrlBar();
      });
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

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HistoryPage(
          entries: _history,
          onOpen: (url) => _navigate(url),
          onDelete: (url) {
            setState(
              () => _history.removeWhere((entry) => entry.url == url),
            );
          },
          onClearAll: () => setState(() => _history.clear()),
        ),
      ),
    );
  }

  Future<void> _openBookmarks() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BookmarkPage(
          onOpen: (url) => _navigate(url),
        ),
      ),
    );
  }

  Future<void> _openAbout() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AboutPage(
          onOpenLink: (url) {
            Navigator.of(context).pop();
            _navigate(url);
          },
        ),
      ),
    );
  }

  Future<void> _toggleBookmark() async {
    final tab = _activeTab;
    final url = tab.url;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada halaman untuk disimpan')),
      );
      return;
    }
    if (BookmarkStore.instance.isBookmarked(url)) {
      await BookmarkStore.instance.remove(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bookmark dihapus')),
      );
    } else {
      await BookmarkStore.instance.add(tab.title, url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bookmark disimpan')),
      );
    }
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
          adBlockEnabled: BrowserSettings.instance.adBlockEnabled,
          onAdBlockChanged: (value) {
            BrowserSettings.instance.setAdBlockEnabled(value);
            if (mounted) setState(() {});
          },
          onClearHistory: () => _history.clear(),
          onClearCookies: () {
            WebViewCookieManager().clearCookies();
          },
          onClearCache: () {
            _activeTab.controller.clearCache();
          },
          onOpenLink: (url) => _navigate(url),
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
    // Lembar berbagi sistem; bila gagal, jatuh ke salin tautan.
    try {
      await Share.share(url);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tautan disalin')),
      );
    }
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'new_tab':
        _newTab();
      case 'new_incognito':
        _newTab(incognito: true);
      case 'history':
        _openHistory();
      case 'bookmarks':
        _openBookmarks();
      case 'bookmark_add':
        _toggleBookmark();
      case 'downloads':
        _openDownloads();
      case 'share':
        _share();
      case 'forward':
        _goForward();
      case 'reload':
        _reload();
      case 'desktop':
        _toggleDesktop();
      case 'settings':
        _openSettings();
      case 'about':
        _openAbout();
    }
  }

  // ---------- Tampilan ----------

  @override
  Widget build(BuildContext context) {
    final tab = _activeTab;
    final incognito = tab.isIncognito;
    final loading = tab.isLoading && tab.progress < 100;
    // Beranda digulir = bilah atas berubah jadi kapsul cari (ala Chrome).
    final showHomeToolbarCapsule = tab.url == null && _homeScrolled;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (tab.url != null) {
          // Masih membuka halaman: mundur (atau ke beranda bila tidak
          // ada riwayat), bukan keluar aplikasi.
          await _goBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        // Latar layar penuh (termasuk di balik status bar) ikut warna beranda.
        backgroundColor:
            tab.url == null ? (incognito ? homeBgDark : homeBgLight) : null,
        appBar: AppBar(
          // Di beranda: samakan dengan latar beranda supaya tidak belang.
          backgroundColor: tab.url == null
              ? (incognito ? homeBgDark : homeBgLight)
              : (incognito ? Colors.grey[900] : null),
          foregroundColor: incognito ? Colors.white : null,
          // Ikon home selalu di kiri atas seperti Chrome; ketuk = beranda.
          // Kembali ke halaman sebelumnya pakai tombol kembali HP.
          // Saat beranda digulir, bilah atas hanya berisi kapsul cari.
          leading: showHomeToolbarCapsule
              ? null
              : IconButton(
                  icon: const Icon(Icons.home_outlined),
                  tooltip: 'Beranda',
                  onPressed: _goHome,
                ),
          // Di beranda (belum ada halaman): bilah URL disembunyikan —
          // beranda sudah punya kapsul carinya sendiri. Saat beranda
          // digulir, bilah atas berubah jadi kapsul cari (ala Chrome).
          title: tab.url == null
              ? (showHomeToolbarCapsule ? _homeToolbarCapsule() : null)
              : TextField(
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
            // Tombol + (tab baru) ala Chrome; hanya saat membuka halaman
            // situs, tidak di beranda.
            if (tab.url != null)
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Tab baru',
                onPressed: _newTab,
              ),
            if (!showHomeToolbarCapsule)
              _TabCountButton(
                count: _tabs.length,
                incognito: incognito,
                onPressed: _openTabSwitcher,
              ),
            if (!showHomeToolbarCapsule)
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
                  value: 'history',
                  child: Text('Riwayat'),
                ),
                const PopupMenuItem<String>(
                  value: 'bookmarks',
                  child: Text('Bookmark'),
                ),
                PopupMenuItem<String>(
                  value: 'bookmark_add',
                  child: Text(
                    tab.url != null &&
                            BookmarkStore.instance.isBookmarked(tab.url!)
                        ? 'Hapus bookmark'
                        : 'Simpan bookmark',
                  ),
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
                  value: 'forward',
                  child: Text('Maju'),
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
                const PopupMenuItem<String>(
                  value: 'about',
                  child: Text('Tentang Chrome Lite'),
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
        // WebView SELALU ada di tree (di bawah). Beranda hanya menutupinya
        // saat tab belum membuka halaman. Ini penting: loadRequest yang
        // dipanggil saat WebView belum menempel gagal dengan
        // net::ERR_CACHE_MISS (bug v1).
        body: Stack(
          children: <Widget>[
            WebViewWidget(controller: tab.controller),
            if (tab.url == null)
              HomeView(
                key: _homeKey,
                onNavigate: _navigate,
                onNewIncognito: () => _newTab(incognito: true),
                incognito: incognito,
                onScrolledChanged: (scrolled) {
                  if (scrolled != _homeScrolled) {
                    setState(() => _homeScrolled = scrolled);
                  }
                },
              ),
          ],
        ),
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
