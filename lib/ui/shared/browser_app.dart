import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; 
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';   
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../states/desktop_state.dart';
import '../../states/apps_state.dart';
import '../../states/theme_state.dart';
import '../../services/native_bridge.dart';

import 'browser_screens.dart';
import 'browser_downloads.dart';

class BrowserApp extends StatefulWidget {
  const BrowserApp({Key? key}) : super(key: key);

  @override
  State<BrowserApp> createState() => _BrowserAppState();
}

class _BrowserAppState extends State<BrowserApp> with SingleTickerProviderStateMixin {
  final List<ChromeTab> _tabs = [];
  final List<Map<String, String>> _recentlyClosedTabs = [];
  int _activeTabIndex = 0;
  
  AppsState? _appsState;
  bool _isImageMenuOpen = false;
  
  // Overlay Routing States
  bool _showDownloads = false; 
  bool _showHistory = false;
  bool _showBookmarks = false;
  bool _showRecentTabs = false;
  bool _showSettings = false;

  final String _desktopUserAgent = 
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0";

  @override
  void initState() {
    super.initState();
    _createNewTab('https://www.google.com');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appsState ??= context.read<AppsState>();
    _appsState?.registerBackHandler('browser', _handleBack);
  }

  @override
  void dispose() {
    _appsState?.unregisterBackHandler('browser');
    _handleDataOnExit();
    for (var tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }

  Future<void> _handleDataOnExit() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('browser_clear_on_exit') == true) {
      await CookieManager.instance().deleteAllCookies();
      await prefs.remove('browser_history');
    }
  }

  Future<bool> _handleBack() async {
    if (_showDownloads) { setState(() => _showDownloads = false); return true; }
    if (_showHistory) { setState(() => _showHistory = false); return true; }
    if (_showBookmarks) { setState(() => _showBookmarks = false); return true; }
    if (_showRecentTabs) { setState(() => _showRecentTabs = false); return true; }
    if (_showSettings) { setState(() => _showSettings = false); return true; }

    if (_tabs.isEmpty) return false;
    final currentTab = _tabs[_activeTabIndex];
    if (currentTab.controller != null && await currentTab.controller!.canGoBack()) {
      await currentTab.controller!.goBack();
      _updateNavigationButtons(currentTab);
      return true;
    }
    return false;
  }

  String _sanitizeUrl(String input) {
    final query = input.trim();
    if (query.isEmpty) return 'https://www.google.com';

    if (!query.contains('.') || query.contains(' ') || !query.contains(RegExp(r'\.[a-zA-Z]{2,}'))) {
      return "https://www.google.com/search?q=${Uri.encodeComponent(query)}";
    }

    if (!query.startsWith("http://") && !query.startsWith("https://")) {
      return "https://$query";
    }
    return query;
  }

  Future<void> _addToHistory(ChromeTab tab, String url, String title) async {
    if (url.isEmpty || url == 'about:blank' || url.startsWith('data:')) return;
    if (tab.isIncognito) return; 

    final prefs = await SharedPreferences.getInstance();
    List<String> historyList = prefs.getStringList('browser_history') ?? [];
    
    final newItem = jsonEncode({
      'url': url,
      'title': title.trim().isEmpty ? url : title.trim(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    if (historyList.isNotEmpty) {
      try {
        final lastItem = jsonDecode(historyList.first);
        if (lastItem['url'] == url) return; 
      } catch (_) {}
    }

    historyList.insert(0, newItem);
    if (historyList.length > 200) historyList = historyList.sublist(0, 200); 
    await prefs.setStringList('browser_history', historyList);
  }

  Future<void> _addBookmark(String url, String title) async {
    if (url.isEmpty || url.startsWith('data:')) return;
    final prefs = await SharedPreferences.getInstance();
    List<String> rawBookmarks = prefs.getStringList('browser_bookmarks') ?? [];
    
    final bookmark = BrowserBookmark(title: title.trim().isEmpty ? url : title, url: url, timestamp: DateTime.now().millisecondsSinceEpoch);
    rawBookmarks.add(jsonEncode(bookmark.toJson()));
    
    await prefs.setStringList('browser_bookmarks', rawBookmarks);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to Bookmarks')));
  }

  void _createNewTab([String initialUrl = 'https://www.google.com', bool isIncognito = false]) {
    if (_tabs.length >= 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum tab limit reached to optimize memory.')));
      return;
    }

    final newId = DateTime.now().microsecondsSinceEpoch.toString();
    final newTab = ChromeTab(
      id: newId,
      url: initialUrl,
      isDesktopMode: context.read<DesktopState>().experimentalEngine,
      isIncognito: isIncognito,
    );

    setState(() {
      _tabs.add(newTab);
      _activeTabIndex = _tabs.length - 1;
    });
  }

  void _closeTab(int index) {
    if (_tabs.isEmpty) return;
    final tabToClose = _tabs[index];
    
    if (!tabToClose.isIncognito && !tabToClose.url.startsWith('data:') && tabToClose.url != 'about:blank') {
      _recentlyClosedTabs.insert(0, {'title': tabToClose.title, 'url': tabToClose.url});
      if (_recentlyClosedTabs.length > 20) _recentlyClosedTabs.removeLast();
    }
    
    tabToClose.controller?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
    tabToClose.dispose();

    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _createNewTab('https://www.google.com');
      } else if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
    });
  }

  void _updateNavigationButtons(ChromeTab tab) async {
    if (tab.controller == null) return;
    final canBack = await tab.controller!.canGoBack();
    final canFwd = await tab.controller!.canGoForward();
    if (mounted) {
      setState(() {
        tab.canGoBack = canBack;
        tab.canGoForward = canFwd;
      });
    }
  }

  void _loadUrl(ChromeTab tab, String text) {
    if (text.trim().isEmpty || tab.controller == null) return;
    final finalUrl = _sanitizeUrl(text);
    tab.controller!.loadUrl(urlRequest: URLRequest(url: WebUri(finalUrl)));
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _toggleDesktopMode(ChromeTab tab) {
    if (tab.controller == null) return;
    setState(() => tab.isDesktopMode = !tab.isDesktopMode);
    tab.controller!.setSettings(settings: InAppWebViewSettings(
      userAgent: tab.isDesktopMode ? _desktopUserAgent : "",
    ));
    tab.controller!.reload();
  }

  void _forceEnableZoom(ChromeTab tab) {
    if (tab.controller == null) return;
    tab.controller!.evaluateJavascript(source: 
      "document.querySelector('meta[name=\"viewport\"]').setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes');"
    );
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pinch-to-zoom force enabled on this page.')));
  }

  Future<void> _downloadMedia(String url, {String? suggestedName}) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attempting to download file...')));
      
      String fileName = suggestedName ?? 'downloaded_file_${DateTime.now().millisecondsSinceEpoch}';
      final tempDir = await getApplicationDocumentsDirectory();

      if (url.startsWith('data:')) {
        final split = url.split(',');
        if (split.length > 1) {
          final mimeStr = split.first;
          String ext = 'jpg';
          if (mimeStr.contains('png')) ext = 'png';
          else if (mimeStr.contains('gif')) ext = 'gif';
          else if (mimeStr.contains('webp')) ext = 'webp';
          else if (mimeStr.contains('pdf')) ext = 'pdf';
          else if (mimeStr.contains('csv')) ext = 'csv';
          else if (mimeStr.contains('txt')) ext = 'txt';
          
          fileName = 'file_${DateTime.now().millisecondsSinceEpoch}.$ext';
          
          String newPath = '${tempDir.path}/$fileName';
          int counter = 1;
          while (File(newPath).existsSync()) {
            newPath = '${tempDir.path}/${fileName.split('.').first} ($counter).$ext';
            counter++;
          }
          final file = File(newPath);
          
          if (mimeStr.contains(';base64')) {
            await file.writeAsBytes(base64Decode(split.last));
          } else {
            await file.writeAsString(Uri.decodeComponent(split.last));
          }
          
          bool success = await NativeBridge.instance.saveToDownloads(file.path, fileName);
          if (await file.exists()) await file.delete();
          if (success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to Downloads: $fileName')));
          }
        }
        return;
      } 
      
      if (url.startsWith('blob:')) {
        if (_tabs.isNotEmpty) {
          final activeTab = _tabs[_activeTabIndex];
          final dynamic base64DataUrl = await activeTab.controller?.evaluateJavascript(source: '''
            (async function() {
              try {
                const res = await fetch("$url");
                const blob = await res.blob();
                return await new Promise((resolve) => {
                  const reader = new FileReader();
                  reader.onloadend = () => resolve(reader.result);
                  reader.onerror = () => resolve(null);
                  reader.readAsDataURL(blob);
                });
              } catch (e) {
                return null;
              }
            })()
          ''');

          if (base64DataUrl is String && base64DataUrl.isNotEmpty) {
            await _downloadMedia(base64DataUrl, suggestedName: suggestedName);
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to read blob data.')));
            }
          }
        }
        return;
      }

      final uri = Uri.parse(url);
      if (suggestedName == null || suggestedName.isEmpty) {
        fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'downloaded_file';
        if (fileName.contains('?')) fileName = fileName.split('?').first;
        if (!fileName.contains('.')) fileName += '.bin';
      }
      
      fileName = fileName.replaceAll(RegExp(r'[/\\]'), '_');
      
      String newPath = '${tempDir.path}/$fileName';
      int counter = 1;
      while (File(newPath).existsSync()) {
        final extIdx = fileName.lastIndexOf('.');
        if (extIdx != -1) {
          newPath = '${tempDir.path}/${fileName.substring(0, extIdx)} ($counter)${fileName.substring(extIdx)}';
        } else {
          newPath = '${tempDir.path}/$fileName ($counter)';
        }
        counter++;
      }
      final file = File(newPath);
      
      final request = http.Request('GET', uri);

      String? cookieString;
      try {
        final cookies = await CookieManager.instance().getCookies(url: WebUri(url));
        if (cookies.isNotEmpty) {
          cookieString = cookies.map((c) => '${c.name}=${c.value}').join('; ');
        }
      } catch (_) {}

      if (cookieString != null && cookieString.isNotEmpty) {
        request.headers['Cookie'] = cookieString;
      }
      request.headers['User-Agent'] = _desktopUserAgent;
      request.headers['Accept'] = '*/*';

      final client = http.Client();
      try {
        final response = await client.send(request);
        if (response.statusCode == 200) {
          final sink = file.openWrite();
          await response.stream.pipe(sink);
          await sink.close();
        } else {
          throw Exception('HTTP Error ${response.statusCode}');
        }
      } catch (httpError) {
        debugPrint('Internal download failed: $httpError. Falling back to native handler.');
        final bool launched = await NativeBridge.instance.launchApp(url);
        if (launched && mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download handed over to system browser...')));
          return;
        } else {
          throw Exception('Access is restricted by the host server.');
        }
      } finally {
        client.close();
      }

      bool success = await NativeBridge.instance.saveToDownloads(file.path, fileName);
      if (await file.exists()) await file.delete();
      
      if (success && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to Downloads: $fileName')));
      
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: ${e.toString().replaceAll("Exception: ", "")}')));
    }
  }

  void _showChromeOverflowMenu(ChromeTab activeTab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2A2D2C) : const Color(0xFFF8F9FA);
    final textColor = isDark ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F);
    final iconColor = isDark ? const Color(0xFFC4C7C5) : const Color(0xFF444746);
    final dividerColor = isDark ? Colors.white12 : Colors.black12;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ChromeMenu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, anim1, anim2) {
        return Stack(
          children: [
            Positioned(
              top: 50, 
              right: 8,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 270,
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height - 120),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildTopMenuIcon(Icons.arrow_forward, iconColor, activeTab.canGoForward, () async {
                                Navigator.pop(ctx);
                                await activeTab.controller?.goForward();
                                _updateNavigationButtons(activeTab);
                              }),
                              _buildTopMenuIcon(Icons.star_border, iconColor, true, () {
                                Navigator.pop(ctx);
                                _addBookmark(activeTab.url, activeTab.title);
                              }),
                              _buildTopMenuIcon(Icons.download_outlined, iconColor, true, () {
                                Navigator.pop(ctx);
                                _downloadMedia(activeTab.url);
                              }),
                              _buildTopMenuIcon(Icons.info_outline, iconColor, true, () {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Page Info: ${activeTab.url}')));
                              }),
                              _buildTopMenuIcon(Icons.refresh, iconColor, true, () {
                                Navigator.pop(ctx);
                                activeTab.controller?.reload();
                              }),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: dividerColor),
                        
                        _buildMenuListItem('New tab', Icons.add_box_outlined, textColor, iconColor, () {
                          Navigator.pop(ctx);
                          _createNewTab();
                        }),
                        _buildMenuListItem('New Incognito tab', Icons.privacy_tip_outlined, textColor, iconColor, () {
                          Navigator.pop(ctx);
                          _createNewTab('https://www.google.com', true);
                        }),
                        
                        Divider(height: 1, color: dividerColor),
                        
                        _buildMenuListItem('History', Icons.history, textColor, iconColor, () {
                          Navigator.pop(ctx);
                          setState(() => _showHistory = true);
                        }),
                        _buildMenuListItem('Delete browsing data', Icons.delete_outline, textColor, iconColor, () async {
                          Navigator.pop(ctx);
                          await activeTab.controller?.clearCache();
                          await CookieManager.instance().deleteAllCookies();
                          activeTab.controller?.reload();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Browsing data cleared')));
                        }),
                        
                        Divider(height: 1, color: dividerColor),
                        
                        _buildMenuListItem('Downloads', Icons.download_done, textColor, iconColor, () {
                          Navigator.pop(ctx);
                          setState(() => _showDownloads = true);
                        }),
                        _buildMenuListItem('Bookmarks', Icons.star_border, textColor, iconColor, () {
                          Navigator.pop(ctx);
                          setState(() => _showBookmarks = true);
                        }),
                        _buildMenuListItem('Recent tabs', Icons.devices, textColor, iconColor, () {
                          Navigator.pop(ctx);
                          setState(() => _showRecentTabs = true);
                        }),
                        
                        Divider(height: 1, color: dividerColor),
                        
                        _buildMenuListItem('Zoom', Icons.zoom_in, textColor, iconColor, () {
                          Navigator.pop(ctx);
                          _forceEnableZoom(activeTab);
                        }),
                        _buildMenuListItem('Share...', Icons.share_outlined, textColor, iconColor, () {
                          Navigator.pop(ctx);
                          NativeBridge.instance.shareText(activeTab.url);
                        }),
                        
                        Divider(height: 1, color: dividerColor),
                        
                        _buildMenuListItem('Add to Home screen', Icons.add_to_home_screen, textColor, iconColor, () {
                          Navigator.pop(ctx);
                          final desktopState = context.read<DesktopState>();
                          int safeCol = desktopState.portraitGridX > 1 ? 1 : 0;
                          desktopState.addDesktopApp(activeTab.url, activeTab.title, 0, safeCol, 1);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shortcut added to Desktop')));
                        }),
                        _buildMenuListItem('Desktop site', Icons.desktop_windows_outlined, textColor, iconColor, () {
                          Navigator.pop(ctx);
                          _toggleDesktopMode(activeTab);
                        }, trailing: Icon(activeTab.isDesktopMode ? Icons.check_box : Icons.check_box_outline_blank, color: Colors.blueAccent, size: 20)),
                        
                        Divider(height: 1, color: dividerColor),
                        
                        _buildMenuListItem('Settings', Icons.settings, textColor, iconColor, () {
                          Navigator.pop(ctx);
                          setState(() => _showSettings = true);
                        }),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(opacity: anim1, child: child);
      },
    );
  }

  Widget _buildTopMenuIcon(IconData icon, Color color, bool isEnabled, VoidCallback onTap) {
    return InkWell(
      onTap: isEnabled ? onTap : null,
      customBorder: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.transparent),
        child: Icon(icon, size: 22, color: isEnabled ? color : color.withOpacity(0.3)),
      ),
    );
  }

  Widget _buildMenuListItem(String title, IconData icon, Color textColor, Color iconColor, VoidCallback onTap, {Widget? trailing}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500))),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(bool isDark) {
    final tabStripBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE3E5E8);
    
    final screenWidth = MediaQuery.of(context).size.width;
    final double dynamicTabWidth = ((screenWidth - 48) / _tabs.length);
    final double finalTabWidth = dynamicTabWidth.clamp(85.0, 130.0);

    return Container(
      height: 34,
      color: tabStripBg,
      padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _tabs.length,
              itemBuilder: (context, index) {
                final tab = _tabs[index];
                final isActive = index == _activeTabIndex;
                
                final activeTabBg = tab.isIncognito ? const Color(0xFF333333) : (isDark ? const Color(0xFF2B2B2B) : Colors.white);
                final inactiveTabBg = Colors.transparent;
                final textColor = (tab.isIncognito || isDark) ? Colors.white : Colors.black87;
                final borderCol = isDark ? Colors.white12 : Colors.grey.shade300;

                return GestureDetector(
                  onTap: () {
                    setState(() => _activeTabIndex = index);
                    _updateNavigationButtons(tab);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: finalTabWidth,
                    margin: const EdgeInsets.only(right: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: isActive ? activeTabBg : inactiveTabBg,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      border: Border(
                        top: BorderSide(color: isActive ? borderCol : Colors.transparent),
                        left: BorderSide(color: isActive ? borderCol : Colors.transparent),
                        right: BorderSide(color: isActive ? borderCol : Colors.transparent),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          tab.isIncognito ? Icons.privacy_tip : (tab.url.startsWith('https') ? Icons.public : Icons.language),
                          size: 13,
                          color: isActive ? (tab.isIncognito ? Colors.grey.shade400 : Colors.blueAccent) : (isDark ? Colors.white54 : Colors.black45),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tab.title,
                            style: TextStyle(color: textColor, fontSize: 11, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: () => _closeTab(index),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.all(2.0),
                            child: Icon(Icons.close, size: 13, color: isDark ? Colors.white54 : Colors.black45),
                          ),
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          InkWell(
            onTap: () => _createNewTab(),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(4),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.add, size: 16, color: isDark ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactNavButton(IconData icon, Color color, VoidCallback? onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Widget _buildOmniboxToolbar(ChromeTab activeTab, bool isDark) {
    final toolbarBg = activeTab.isIncognito ? const Color(0xFF191919) : (isDark ? const Color(0xFF2B2B2B) : Colors.white);
    final omniboxBg = activeTab.isIncognito ? const Color(0xFF2B2B2B) : (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F3F4));
    final textColor = (activeTab.isIncognito || isDark) ? Colors.white : Colors.black87;
    final iconColor = (activeTab.isIncognito || isDark) ? Colors.white70 : Colors.black87;
    final disabledIconColor = (activeTab.isIncognito || isDark) ? Colors.white24 : Colors.black26;

    final isHttps = activeTab.url.startsWith('https://');

    return Container(
      color: toolbarBg,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildCompactNavButton(
                Icons.arrow_back,
                activeTab.canGoBack ? iconColor : disabledIconColor,
                activeTab.canGoBack ? () async { await activeTab.controller?.goBack(); _updateNavigationButtons(activeTab); } : null,
              ),
              _buildCompactNavButton(
                Icons.arrow_forward,
                activeTab.canGoForward ? iconColor : disabledIconColor,
                activeTab.canGoForward ? () async { await activeTab.controller?.goForward(); _updateNavigationButtons(activeTab); } : null,
              ),
              _buildCompactNavButton(
                activeTab.isLoading ? Icons.close : Icons.refresh,
                iconColor,
                () {
                  if (activeTab.isLoading) {
                    activeTab.controller?.stopLoading();
                    setState(() => activeTab.isLoading = false);
                  } else {
                    activeTab.controller?.reload();
                  }
                },
              ),
              _buildCompactNavButton(
                Icons.home_outlined,
                iconColor,
                () => _loadUrl(activeTab, 'https://www.google.com'),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 34,
                  decoration: BoxDecoration(
                    color: omniboxBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(
                        activeTab.isIncognito ? Icons.privacy_tip : (isHttps ? Icons.lock : Icons.info_outline),
                        size: 14,
                        color: activeTab.isIncognito ? Colors.grey.shade400 : (isHttps ? Colors.green.shade600 : Colors.amber.shade700),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: activeTab.urlController,
                          style: TextStyle(color: textColor, fontSize: 12.5),
                          decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                          onSubmitted: (val) => _loadUrl(activeTab, val),
                        ),
                      ),
                      if (activeTab.urlController.text.isNotEmpty)
                        GestureDetector(
                          onTap: () { activeTab.urlController.clear(); setState(() {}); },
                          child: Icon(Icons.cancel, size: 14, color: isDark ? Colors.white38 : Colors.black38),
                        ),
                    ],
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showChromeOverflowMenu(activeTab),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Icon(Icons.more_vert, size: 18, color: iconColor),
                  ),
                ),
              ),
            ],
          ),
          if (activeTab.isLoading)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(value: activeTab.progress > 0 ? activeTab.progress : null, minHeight: 2, backgroundColor: Colors.transparent, color: Colors.blueAccent),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen(ChromeTab tab) {
    return Container(
      color: const Color(0xFFF7F9FA),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text("This site can't be reached", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 8),
          Text(tab.errorMessage.isNotEmpty ? tab.errorMessage : "Check your connection or website address.", style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () { setState(() => tab.hasError = false); tab.controller?.reload(); },
            icon: const Icon(Icons.refresh, size: 16), label: const Text("Reload"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          )
        ],
      ),
    );
  }

  Widget _buildBrowserContent(bool isDark) {
    if (_tabs.isEmpty) return const SizedBox.shrink(key: ValueKey('empty_browser'));
    final activeTab = _tabs[_activeTabIndex];

    return Column(
      key: const ValueKey('browser_content'),
      children: [
        _buildTabBar(isDark),
        _buildOmniboxToolbar(activeTab, isDark),
        Expanded(
          child: activeTab.hasError
              ? _buildErrorScreen(activeTab)
              : InAppWebView(
                  key: ValueKey(activeTab.id),
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<VerticalDragGestureRecognizer>(() => VerticalDragGestureRecognizer()),
                    Factory<HorizontalDragGestureRecognizer>(() => HorizontalDragGestureRecognizer()),
                    Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
                    Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
                    Factory<LongPressGestureRecognizer>(() => LongPressGestureRecognizer()),
                  },
                  
                  initialUrlRequest: URLRequest(url: WebUri(activeTab.url)),
                  initialSettings: InAppWebViewSettings(
                    useShouldOverrideUrlLoading: true,
                    mediaPlaybackRequiresUserGesture: false,
                    allowsInlineMediaPlayback: true,
                    supportZoom: true,
                    builtInZoomControls: true,
                    displayZoomControls: false,
                    incognito: activeTab.isIncognito,
                    userAgent: activeTab.isDesktopMode ? _desktopUserAgent : "",
                  ),
                  onWebViewCreated: (controller) {
                    activeTab.controller = controller;
                  },
                  onLoadStart: (controller, url) {
                    if (!mounted) return;
                    setState(() {
                      activeTab.isLoading = true;
                      activeTab.hasError = false;
                      activeTab.progress = 0.05;
                      activeTab.url = url.toString();
                    });
                    if (!activeTab.url.startsWith('data:') && activeTab.url.isNotEmpty) {
                      activeTab.urlController.text = activeTab.url;
                    }
                    _updateNavigationButtons(activeTab);
                  },
                  onProgressChanged: (controller, progress) {
                    if (!mounted) return;
                    setState(() { activeTab.progress = progress / 100.0; });
                  },
                  onLoadStop: (controller, url) async {
                    if (!mounted) return;
                    final title = await controller.getTitle();
                    
                    setState(() {
                      activeTab.isLoading = false;
                      activeTab.progress = 1.0;
                      activeTab.url = url.toString();
                      if (title != null && title.trim().isNotEmpty) {
                        activeTab.title = title.trim();
                      }
                    });
                    _updateNavigationButtons(activeTab);

                    if (!activeTab.url.startsWith('data:') && activeTab.url != 'about:blank') {
                      _addToHistory(activeTab, activeTab.url, title ?? activeTab.url);
                    }
                  },
                  onReceivedError: (controller, request, error) {
                    if (request.isForMainFrame ?? false) {
                      if (error.description.contains('ERR_ABORTED') || error.description.contains('net::ERR_CACHE_MISS')) return;
                      if (mounted) {
                        setState(() {
                          activeTab.isLoading = false;
                          activeTab.hasError = true;
                          activeTab.errorMessage = error.description;
                        });
                      }
                    }
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final url = navigationAction.request.url.toString();
                    if (!url.startsWith('http://') && !url.startsWith('https://')) {
                      final now = DateTime.now();
                      if (activeTab.lastIntentLaunch != null && now.difference(activeTab.lastIntentLaunch!).inSeconds < 2) {
                        return NavigationActionPolicy.CANCEL;
                      }
                      activeTab.lastIntentLaunch = now;
                      
                      if (url.startsWith('mailto:') || url.startsWith('tel:') || url.startsWith('market:')) {
                         bool success = await NativeBridge.instance.launchApp(url); 
                         if (!success && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No application found to handle this link.')));
                      } else {
                         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unsafe or unsupported link blocked for security.')));
                      }
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  onDownloadStartRequest: (controller, downloadRequest) {
                    _downloadMedia(downloadRequest.url.toString(), suggestedName: downloadRequest.suggestedFilename);
                  },
                  onEnterFullscreen: (controller) {
                    final appsState = context.read<AppsState>();
                    if (!appsState.maximizedApps.contains('browser')) {
                      appsState.toggleMaximizeApp('browser');
                    }
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_showDownloads) return BrowserDownloadsScreen(key: const ValueKey('downloads_screen'), onBack: () => setState(() => _showDownloads = false));
    if (_showHistory) return BrowserHistoryScreen(key: const ValueKey('history_screen'), onBack: () => setState(() => _showHistory = false), onOpenUrl: (url) { setState(() => _showHistory = false); if (_tabs.isNotEmpty) { _loadUrl(_tabs[_activeTabIndex], url); } else { _createNewTab(url); } });
    if (_showBookmarks) return BrowserBookmarksScreen(key: const ValueKey('bookmarks_screen'), onBack: () => setState(() => _showBookmarks = false), onOpenUrl: (url) { setState(() => _showBookmarks = false); if (_tabs.isNotEmpty) { _loadUrl(_tabs[_activeTabIndex], url); } else { _createNewTab(url); } });
    if (_showRecentTabs) return BrowserRecentTabsScreen(key: const ValueKey('recent_tabs_screen'), closedTabs: _recentlyClosedTabs, onBack: () => setState(() => _showRecentTabs = false), onOpenUrl: (url) { setState(() => _showRecentTabs = false); _createNewTab(url); });
    if (_showSettings) return BrowserSettingsScreen(key: const ValueKey('settings_screen'), onBack: () => setState(() => _showSettings = false));
    
    return _buildBrowserContent(isDark);
  }
}