import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../states/theme_state.dart';
import '../../services/native_bridge.dart';

class ChromeTab {
  final String id;
  String title;
  String url;
  bool isLoading;
  double progress;
  bool hasError;
  String errorMessage;
  bool canGoBack;
  bool canGoForward;
  bool isDesktopMode;
  bool isIncognito;
  DateTime? lastIntentLaunch;
  InAppWebViewController? controller;
  late final TextEditingController urlController;

  ChromeTab({
    required this.id,
    this.title = 'New Tab',
    this.url = 'https://www.google.com',
    this.isLoading = true,
    this.progress = 0.0,
    this.hasError = false,
    this.errorMessage = '',
    this.canGoBack = false,
    this.canGoForward = false,
    this.isDesktopMode = false,
    this.isIncognito = false,
  }) {
    urlController = TextEditingController(text: url);
  }

  void dispose() {
    urlController.dispose();
  }
}

class BrowserBookmark {
  final String title;
  final String url;
  final int timestamp;

  BrowserBookmark({required this.title, required this.url, required this.timestamp});

  Map<String, dynamic> toJson() => {'title': title, 'url': url, 'timestamp': timestamp};
  factory BrowserBookmark.fromJson(Map<String, dynamic> json) => BrowserBookmark(
    title: json['title'] ?? '',
    url: json['url'] ?? '',
    timestamp: json['timestamp'] ?? 0,
  );
}

class BrowserDownloadsScreen extends StatefulWidget {
  final VoidCallback onBack;
  const BrowserDownloadsScreen({Key? key, required this.onBack}) : super(key: key);

  @override
  State<BrowserDownloadsScreen> createState() => _BrowserDownloadsScreenState();
}

class _BrowserDownloadsScreenState extends State<BrowserDownloadsScreen> {
  List<FileSystemEntity> _downloadedFiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDownloads();
  }

  Future<void> _fetchDownloads() async {
    setState(() => _isLoading = true);
    List<FileSystemEntity> files = [];
    final paths = ['/storage/emulated/0/Download', '/storage/emulated/0/Downloads'];

    for (var path in paths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        try {
          final dirFiles = await dir.list().toList();
          files.addAll(dirFiles.where((f) => f is File && !f.path.split('/').last.startsWith('.')));
        } catch (_) {}
      }
    }

    files.sort((a, b) {
      try { return b.statSync().modified.compareTo(a.statSync().modified); } 
      catch (_) { return 0; }
    });

    if (mounted) setState(() { _downloadedFiles = files; _isLoading = false; });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    int i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  Widget _buildFileIcon(String extension, bool isDark) {
    IconData icon = Icons.insert_drive_file_outlined;
    Color color = isDark ? Colors.white70 : Colors.black54;
    Color bgColor = isDark ? Colors.white12 : Colors.black.withOpacity(0.05);

    if (['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(extension)) { icon = Icons.image; color = Colors.blue; bgColor = Colors.blue.withOpacity(0.15); } 
    else if (['pdf'].contains(extension)) { icon = Icons.picture_as_pdf; color = Colors.red; bgColor = Colors.red.withOpacity(0.15); } 
    else if (['mp4', 'mkv', 'avi'].contains(extension)) { icon = Icons.video_file; color = Colors.purple; bgColor = Colors.purple.withOpacity(0.15); } 
    else if (['mp3', 'wav', 'm4a'].contains(extension)) { icon = Icons.audio_file; color = Colors.orange; bgColor = Colors.orange.withOpacity(0.15); } 
    else if (['zip', 'rar', '7z'].contains(extension)) { icon = Icons.folder_zip; color = Colors.amber.shade600; bgColor = Colors.amber.withOpacity(0.15); } 
    else if (['apk'].contains(extension)) { icon = Icons.android; color = Colors.green; bgColor = Colors.green.withOpacity(0.15); }

    return Container(width: 40, height: 40, decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 20));
  }

  void _deleteFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
        _fetchDownloads();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File deleted')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete file')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;
    final borderColor = isDark ? Colors.white12 : Colors.black12;

    return Container(
      color: bgColor,
      child: Column(
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor)), color: isDark ? const Color(0xFF2B2B2B) : Colors.white),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(icon: Icon(Icons.arrow_back, color: textColor, size: 20), onPressed: widget.onBack),
                const SizedBox(width: 8),
                Text('Downloads', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: Icon(Icons.folder_open, color: textColor, size: 20), onPressed: () => NativeBridge.instance.launchApp('com.google.android.documentsui')),
              ],
            ),
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _downloadedFiles.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.download_done, size: 48, color: borderColor), const SizedBox(height: 16), Text('No downloaded files', style: TextStyle(color: subTextColor, fontSize: 14))]))
                : ListView.separated(
                    padding: const EdgeInsets.all(12), itemCount: _downloadedFiles.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                    itemBuilder: (context, index) {
                      final file = _downloadedFiles[index] as File;
                      final fileName = file.path.split('/').last;
                      final extension = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
                      int size = 0;
                      try { size = file.statSync().size; } catch (_) {}

                      return InkWell(
                        onTap: () => NativeBridge.instance.openFile(file.path),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          child: Row(
                            children: [
                              _buildFileIcon(extension, isDark),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(fileName, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Text(_formatBytes(size), style: TextStyle(color: subTextColor, fontSize: 11)),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert, color: subTextColor, size: 20),
                                color: isDark ? const Color(0xFF2B2B2B) : Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                onSelected: (val) {
                                  if (val == 'open') NativeBridge.instance.openFile(file.path);
                                  else if (val == 'share') NativeBridge.instance.shareFile(file.path);
                                  else if (val == 'delete') _deleteFile(file);
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(value: 'open', height: 36, child: Row(children: [Icon(Icons.open_in_new, size: 18, color: textColor), const SizedBox(width: 12), Text('Open', style: TextStyle(color: textColor, fontSize: 13))])),
                                  PopupMenuItem(value: 'share', height: 36, child: Row(children: [Icon(Icons.share, size: 18, color: textColor), const SizedBox(width: 12), Text('Share', style: TextStyle(color: textColor, fontSize: 13))])),
                                  PopupMenuItem(value: 'delete', height: 36, child: Row(children: [const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), const SizedBox(width: 12), const Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 13))])),
                                ],
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class BrowserHistoryScreen extends StatefulWidget {
  final VoidCallback onBack;
  final Function(String) onOpenUrl;
  const BrowserHistoryScreen({Key? key, required this.onBack, required this.onOpenUrl}) : super(key: key);

  @override
  State<BrowserHistoryScreen> createState() => _BrowserHistoryScreenState();
}

class _BrowserHistoryScreenState extends State<BrowserHistoryScreen> {
  List<Map<String, dynamic>> _historyItems = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('browser_history') ?? [];
    final parsedList = list.map((item) => Map<String, dynamic>.from(jsonDecode(item))).toList();
    if (mounted) setState(() => _historyItems = parsedList);
  }

  Future<void> _clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('browser_history');
    setState(() => _historyItems.clear());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white12 : Colors.black12;

    return Container(
      color: bgColor,
      child: Column(
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor)), color: isDark ? const Color(0xFF2B2B2B) : Colors.white),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(icon: Icon(Icons.arrow_back, color: textColor, size: 20), onPressed: widget.onBack),
                const SizedBox(width: 8),
                Text('History', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_historyItems.isNotEmpty)
                  IconButton(icon: Icon(Icons.delete_sweep, color: textColor, size: 22), onPressed: _clearAll),
              ],
            ),
          ),
          Expanded(
            child: _historyItems.isEmpty
                ? Center(child: Text('No browsing history', style: TextStyle(color: textColor.withOpacity(0.5))))
                : ListView.separated(
                    padding: const EdgeInsets.all(12), itemCount: _historyItems.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                    itemBuilder: (context, index) {
                      final item = _historyItems[index];
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => widget.onOpenUrl(item['url']),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item['title'] ?? item['url'], style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text(item['url'], style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class BrowserBookmarksScreen extends StatefulWidget {
  final VoidCallback onBack;
  final Function(String) onOpenUrl;
  const BrowserBookmarksScreen({Key? key, required this.onBack, required this.onOpenUrl}) : super(key: key);

  @override
  State<BrowserBookmarksScreen> createState() => _BrowserBookmarksScreenState();
}

class _BrowserBookmarksScreenState extends State<BrowserBookmarksScreen> {
  List<BrowserBookmark> _bookmarks = [];

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('browser_bookmarks') ?? [];
    if (mounted) {
      setState(() {
        _bookmarks = list.map((item) => BrowserBookmark.fromJson(jsonDecode(item))).toList();
      });
    }
  }

  Future<void> _removeBookmark(int index) async {
    _bookmarks.removeAt(index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('browser_bookmarks', _bookmarks.map((e) => jsonEncode(e.toJson())).toList());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white12 : Colors.black12;

    return Container(
      color: bgColor,
      child: Column(
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor)), color: isDark ? const Color(0xFF2B2B2B) : Colors.white),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(icon: Icon(Icons.arrow_back, color: textColor, size: 20), onPressed: widget.onBack),
                const SizedBox(width: 8),
                Text('Bookmarks', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: _bookmarks.isEmpty
                ? Center(child: Text('No bookmarks yet', style: TextStyle(color: textColor.withOpacity(0.5))))
                : ListView.separated(
                    padding: const EdgeInsets.all(12), itemCount: _bookmarks.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                    itemBuilder: (context, index) {
                      final item = _bookmarks[index];
                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                            child: Icon(Icons.star, color: Colors.amber.shade600, size: 20),
                          ),
                          title: Text(item.title, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(item.url, style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _removeBookmark(index)),
                          onTap: () => widget.onOpenUrl(item.url),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class BrowserRecentTabsScreen extends StatelessWidget {
  final VoidCallback onBack;
  final Function(String) onOpenUrl;
  final List<Map<String, String>> closedTabs;
  
  const BrowserRecentTabsScreen({Key? key, required this.onBack, required this.onOpenUrl, required this.closedTabs}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white12 : Colors.black12;

    return Container(
      color: bgColor,
      child: Column(
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor)), color: isDark ? const Color(0xFF2B2B2B) : Colors.white),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(icon: Icon(Icons.arrow_back, color: textColor, size: 20), onPressed: onBack),
                const SizedBox(width: 8),
                Text('Recent Tabs', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: closedTabs.isEmpty
                ? Center(child: Text('No recently closed tabs', style: TextStyle(color: textColor.withOpacity(0.5))))
                : ListView.separated(
                    padding: const EdgeInsets.all(12), itemCount: closedTabs.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                    itemBuilder: (context, index) {
                      final item = closedTabs[index];
                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.restore_page_outlined, color: textColor.withOpacity(0.7)),
                          title: Text(item['title'] ?? 'Unknown', style: TextStyle(color: textColor, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(item['url'] ?? '', style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => onOpenUrl(item['url']!),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class BrowserSettingsScreen extends StatefulWidget {
  final VoidCallback onBack;
  const BrowserSettingsScreen({Key? key, required this.onBack}) : super(key: key);

  @override
  State<BrowserSettingsScreen> createState() => _BrowserSettingsScreenState();
}

class _BrowserSettingsScreenState extends State<BrowserSettingsScreen> {
  bool _clearOnExit = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _clearOnExit = prefs.getBool('browser_clear_on_exit') ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
    final textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      color: bgColor,
      child: Column(
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12)), color: isDark ? const Color(0xFF2B2B2B) : Colors.white),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(icon: Icon(Icons.arrow_back, color: textColor, size: 20), onPressed: widget.onBack),
                const SizedBox(width: 8),
                Text('Settings', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    title: Text('Clear browsing data on exit', style: TextStyle(color: textColor, fontSize: 14)),
                    subtitle: Text('Automatically clears cache and history when the app is closed', style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 11)),
                    value: _clearOnExit,
                    activeColor: Colors.blueAccent,
                    onChanged: (val) async {
                      setState(() => _clearOnExit = val);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('browser_clear_on_exit', val);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}