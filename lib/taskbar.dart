import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'launcher_state.dart';
import 'services/native_bridge.dart';

class Win11Taskbar extends StatefulWidget {
  final bool isStartMenuOpen;
  final VoidCallback onStartToggled;
  final VoidCallback onQuickSettingsToggled;
  final VoidCallback onNotificationCenterToggled;
  final VoidCallback onOverlaysClosed;
  
  final int batteryLevel;
  final BatteryState batteryState;
  final int unreadNotifications;

  const Win11Taskbar({
    Key? key,
    required this.isStartMenuOpen,
    required this.onStartToggled,
    required this.onQuickSettingsToggled,
    required this.onNotificationCenterToggled,
    required this.onOverlaysClosed,
    required this.batteryLevel,
    required this.batteryState,
    required this.unreadNotifications,
  }) : super(key: key);

  @override
  State<Win11Taskbar> createState() => _Win11TaskbarState();
}

class _Win11TaskbarState extends State<Win11Taskbar> {

  String _formatTime(DateTime time) {
    int h = time.hour; int m = time.minute;
    String ampm = h >= 12 ? 'PM' : 'AM';
    h = h % 12; if (h == 0) h = 12;
    return '$h:${m.toString().padLeft(2, '0')} $ampm';
  }

  String _formatDate(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _openSearchOverlay(BuildContext context, LauncherState state) {
    final theme = state.win11Themes.firstWhere((t) => t.name == state.currentThemeName, orElse: () => state.win11Themes.first);
    
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Search',
      barrierColor: Colors.transparent, 
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return Stack(
          children: [
            Positioned(
              bottom: 54.0, 
              left: 8.0, 
              child: _AppSearchOverlay(installedApps: state.installedApps, isDark: state.isDarkMode, accentColor: theme.accentColor),
            )
          ],
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween(begin: const Offset(0, 0.05), end: const Offset(0, 0)).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOut)),
          child: FadeTransition(opacity: anim1, child: child),
        );
      }
    );
  }

  void _showAccessibilityPrompt(bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        title: Text('Accessibility Required', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          "To use the Recent Apps button, Android requires Accessibility permissions.\n\n1. Tap 'Go to Settings'\n2. Select 'Downloaded Apps' or 'Installed Services'\n3. Turn ON 'Windows 11 Launcher'",
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              NativeBridge.instance.openSettings('accessibility');
            },
            child: const Text('Go to Settings', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskbarButton({
    required bool isActive,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    required Widget child,
    bool indicator = false,
    bool isApp = false,
    bool isActiveApp = false,
  }) {
    final state = context.watch<LauncherState>();
    final iconColor = state.isDarkMode ? Colors.white : Colors.black87;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 34, height: 34,
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: isActive ? iconColor.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            child,
            if (indicator)
              Positioned(
                bottom: 0, 
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  width: isApp ? (isActiveApp ? 14 : 6) : 10,
                  height: 3,
                  decoration: BoxDecoration(
                    color: isApp
                        ? (isActiveApp ? Colors.blue.shade400 : (state.isDarkMode ? Colors.white54 : Colors.black45))
                        : Colors.blue.shade400,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _getRawAppIcon(String windowId, LauncherState state) {
    if (windowId.contains('.')) {
      final matchedApps = state.installedApps.where((a) => a.packageName == windowId);
      final Uint8List? iconBytes = matchedApps.isNotEmpty ? matchedApps.first.icon : null;
      return iconBytes != null && iconBytes.isNotEmpty ? Image.memory(iconBytes, width: 20, height: 20) : const Icon(Icons.android, size: 20, color: Colors.green);
    }
    switch (windowId) {
      case 'browser': return Image.asset('assets/icons/edge.png', width: 20, height: 20);
      case 'explorer': return Image.asset('assets/icons/folder.png', width: 20, height: 20);
      case 'calculator': return Image.asset('assets/icons/calculator.png', width: 20, height: 20);
      case 'settings': return Image.asset('assets/icons/settings.png', width: 20, height: 20);
      default: return Icon(Icons.apps, size: 20, color: state.isDarkMode ? Colors.white : Colors.black87);
    }
  }

  Widget _buildBatteryGauge(int level, bool isCharging, Color color) {
    double fillWidth = 12 * (level / 100).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCharging) Padding(padding: const EdgeInsets.only(right: 2), child: Icon(Icons.bolt, size: 12, color: Colors.green.shade500)),
        Container(
          width: 16, height: 9,
          decoration: BoxDecoration(border: Border.all(color: color, width: 1.2), borderRadius: BorderRadius.circular(2)),
          padding: const EdgeInsets.all(1),
          alignment: Alignment.centerLeft,
          child: Container(width: fillWidth, color: isCharging ? Colors.green.shade500 : color),
        ),
        Container(width: 1.5, height: 3, decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)))),
      ],
    );
  }

  Widget _buildSystemTray(LauncherState state, Color iconColor, bool isDark) {
    final bool isCharging = widget.batteryState == BatteryState.charging || widget.batteryState == BatteryState.full;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: widget.onQuickSettingsToggled,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0), 
            child: Transform.scale(
              scaleX: 1.3,
              scaleY: 0.9,
              child: Icon(
                Icons.keyboard_arrow_up, 
                size: 18, 
                color: iconColor,
                shadows: [Shadow(color: iconColor, blurRadius: 0.5, offset: const Offset(0.2, 0.2))],
              )
            )
          ),
        ),
        
        const SizedBox(width: 14),
        
        Tooltip(
          message: '${widget.batteryLevel}% ${isCharging ? '(Charging)' : ''}',
          child: Padding(
            padding: const EdgeInsets.only(left: 0.0, right: 4.0), 
            child: _buildBatteryGauge(widget.batteryLevel, isCharging, iconColor)
          ),
        ),

        InkWell(
          onTap: widget.onNotificationCenterToggled,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: StreamBuilder<DateTime>(
              stream: TimeService.clockStream,
              builder: (context, snapshot) {
                final now = snapshot.data ?? DateTime.now();
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_formatTime(now), style: TextStyle(fontSize: 11, color: iconColor, fontWeight: FontWeight.w500)),
                    Text(_formatDate(now), style: TextStyle(fontSize: 10, color: iconColor)),
                  ],
                );
              }
            ),
          ),
        ),
        
        InkWell(
          onTap: () {
             for (var app in state.windowStack) { state.minimizeApp(app); }
             widget.onOverlaysClosed();
          },
          child: Container(
            width: 6, height: double.infinity, margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: isDark ? Colors.white24 : Colors.black26, width: 1))),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    final theme = state.win11Themes.firstWhere((t) => t.name == state.currentThemeName, orElse: () => state.win11Themes.first);
    
    final baseColor = isDark ? const Color(0xFF141414) : const Color(0xFFF3F3F3);
    final taskbarColor = Color.alphaBlend(theme.accentColor.withOpacity(0.05), baseColor).withOpacity(0.96);
    final iconColor = isDark ? Colors.white : Colors.black87;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: taskbarColor,
        border: Border(top: BorderSide(color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08), width: 1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.1), blurRadius: 4, offset: const Offset(0, -1))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: state.taskbarAlignment == 'center' ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                const SizedBox(width: 4),
                
                _buildTaskbarButton(
                  isActive: widget.isStartMenuOpen,
                  onTap: widget.onStartToggled,
                  child: Image.asset('assets/icons/start.png', width: 20, height: 20, errorBuilder: (c, e, s) => const Icon(Icons.window, color: Colors.blue, size: 20)),
                  indicator: widget.isStartMenuOpen,
                ),
                
                _buildTaskbarButton(
                  isActive: false,
                  onTap: () { widget.onOverlaysClosed(); _openSearchOverlay(context, state); },
                  child: Image.asset(
                    'assets/icons/search.png', 
                    width: 18, height: 18, color: iconColor, 
                    errorBuilder: (c, e, s) => Icon(Icons.search, size: 18, color: iconColor)
                  ),
                ),
                
                _buildTaskbarButton(
                  isActive: false,
                  onTap: () async {
                    widget.onOverlaysClosed();
                    final success = await NativeBridge.instance.toggleRecents(); 
                    if (!success) _showAccessibilityPrompt(isDark);
                  },
                  child: Image.asset(
                    'assets/icons/task_view.png', 
                    width: 18, height: 18, color: iconColor, 
                    errorBuilder: (c, e, s) => Icon(Icons.filter_none, size: 16, color: iconColor)
                  ),
                ),
                
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: state.windowStack.map((appId) {
                        bool isActive = state.windowStack.last == appId && !state.minimizedApps.contains(appId);
                        return _buildTaskbarButton(
                          isActive: isActive,
                          onTap: () { if (appId.contains('.')) NativeBridge.instance.launchApp(appId); else state.openApp(appId); },
                          onLongPress: () => state.closeApp(appId), 
                          child: _getRawAppIcon(appId, state),
                          indicator: true,
                          isApp: true,
                          isActiveApp: isActive,
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(right: 0),
            child: _buildSystemTray(state, iconColor, isDark),
          ),
        ],
      ),
    );
  }
}

class _AppSearchOverlay extends StatefulWidget {
  final List<AppInfo> installedApps;
  final bool isDark;
  final Color accentColor;

  const _AppSearchOverlay({Key? key, required this.installedApps, required this.isDark, required this.accentColor}) : super(key: key);

  @override
  State<_AppSearchOverlay> createState() => _AppSearchOverlayState();
}

class _AppSearchOverlayState extends State<_AppSearchOverlay> {
  final TextEditingController _searchController = TextEditingController();
  
  Timer? _debounce;
  List<AppInfo> _filteredApps = [];
  Map<String, dynamic> _mediaResults = {};
  
  bool _isSearching = false;
  bool _hasStoragePermission = false;
  bool _isCheckingPermissions = true; 
  
  String _activeTab = 'All';
  final List<String> _tabs = ['All', 'Apps', 'Documents', 'Photos', 'Video', 'Audio', 'Web'];

  @override
  void initState() {
    super.initState();
    _filteredApps = widget.installedApps;
    _checkPermissions();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch();
    });
  }

  Future<void> _checkPermissions() async {
    setState(() => _isCheckingPermissions = true);
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      bool storageGranted = false;

      if (androidInfo.version.sdkInt >= 30) {
        final manageStorage = await Permission.manageExternalStorage.request();
        if (androidInfo.version.sdkInt >= 33) {
           final photos = await Permission.photos.request();
           final videos = await Permission.videos.request();
           final audio = await Permission.audio.request();
           storageGranted = manageStorage.isGranted || photos.isGranted || videos.isGranted || audio.isGranted;
        } else {
           storageGranted = manageStorage.isGranted;
        }
      } else {
        final status = await Permission.storage.request();
        storageGranted = status.isGranted;
      }

      if (mounted) {
        setState(() {
          _hasStoragePermission = storageGranted;
          _isCheckingPermissions = false;
        });
      }
    } else {
      if (mounted) setState(() => _isCheckingPermissions = false);
    }
  }

  void _performSearch() async {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredApps = widget.installedApps;
        _mediaResults = {};
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    List<AppInfo> apps = widget.installedApps.where((app) => (app.name ?? '').toLowerCase().contains(query)).toList();

    Map<String, dynamic> media = {};
    if (_hasStoragePermission) {
      try {
        final result = await NativeBridge.instance.searchMedia(query);
        if (result != null) media = result;
      } catch (e) {
        debugPrint("Native Media Search Error: $e");
      }
    } else {
      _checkPermissions();
    }

    if (mounted) {
      setState(() {
        _filteredApps = apps;
        _mediaResults = media;
        _isSearching = false;
      });
    }
  }

  void _launchFile(String path) {
    NativeBridge.instance.openFile(path);
    Navigator.of(context).pop();
  }

  void _launchWebSearch(String query) {
    NativeBridge.instance.openWebSearch(query);
    Navigator.of(context).pop();
  }

  void _showContextMenu(BuildContext context, Offset position, Map<String, String> item, LauncherState state) {
    final bgColor = widget.isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final path = item['path'] ?? '';
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(Rect.fromLTWH(position.dx, position.dy, 0, 0), Offset.zero & MediaQuery.of(context).size),
      color: bgColor, elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: widget.isDark ? Colors.white24 : Colors.grey.shade300)),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'open', onTap: () => _launchFile(path), child: Row(children: [Icon(Icons.open_in_new, size: 18, color: textColor), const SizedBox(width: 12), Text('Open', style: TextStyle(color: textColor, fontSize: 13))])),
        PopupMenuItem<String>(value: 'location', onTap: () { int lastSlash = path.lastIndexOf('/'); if (lastSlash != -1) { String dirPath = path.substring(0, lastSlash); state.currentExplorerPath = dirPath; state.openApp('explorer'); Navigator.of(context).pop(); } }, child: Row(children: [Icon(Icons.folder_open, size: 18, color: textColor), const SizedBox(width: 12), Text('Open file location', style: TextStyle(color: textColor, fontSize: 13))])),
        PopupMenuItem<String>(value: 'share', onTap: () => NativeBridge.instance.shareFile(path), child: Row(children: [Icon(Icons.share, size: 18, color: textColor), const SizedBox(width: 12), Text('Share', style: TextStyle(color: textColor, fontSize: 13))])),
        const PopupMenuDivider(),
        PopupMenuItem<String>(value: 'properties', onTap: () { Future.delayed(const Duration(milliseconds: 100), () { _showPropertiesDialog(item, textColor, bgColor); }); }, child: Row(children: [Icon(Icons.info_outline, size: 18, color: textColor), const SizedBox(width: 12), Text('Properties', style: TextStyle(color: textColor, fontSize: 13))])),
      ]
    );
  }

  void _showPropertiesDialog(Map<String, String> item, Color textColor, Color bgColor) async {
    File file = File(item['path'] ?? '');
    String sizeStr = "Unknown Size";
    
    if (await file.exists()) {
      int length = await file.length();
      double sizeMb = length / (1024 * 1024);
      sizeStr = "${sizeMb.toStringAsFixed(2)} MB";
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Properties', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${item['name']}', style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.8))), const SizedBox(height: 8),
            Text('Location: ${item['path']}', style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.8))), const SizedBox(height: 8),
            Text('Size: $sizeStr', style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.8))),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Colors.blue)))],
      )
    );
  }

  Widget _buildCategory(String title, List<dynamic> items, IconData fallbackIcon, Color textColor, LauncherState state) {
    if (items.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.6))),
        ),
        ...items.map((item) {
          final map = Map<String, String>.from(item);
          Offset tapPosition = Offset.zero;
          
          return Material(
            type: MaterialType.transparency, 
            child: Listener(
              onPointerDown: (details) => tapPosition = details.position,
              child: InkWell(
                onTap: () => _launchFile(map['path'] ?? ''),
                onLongPress: () => _showContextMenu(context, tapPosition, map, state),
                onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition, map, state),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      Icon(fallbackIcon, color: textColor.withOpacity(0.8), size: 24), const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(map['name'] ?? 'Unknown', style: TextStyle(color: textColor, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(map['path'] ?? '', style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  List<Widget> _buildFilteredResults(Color textColor, LauncherState state) {
    List<Widget> children = [];
    
    if (!_isCheckingPermissions && !_hasStoragePermission) {
      children.add(Padding(padding: const EdgeInsets.all(16.0), child: Text("Storage permission required to search files.", style: TextStyle(color: Colors.red.shade400, fontSize: 12), textAlign: TextAlign.center)));
    }

    if (_activeTab == 'All' || _activeTab == 'Apps') {
      if (_filteredApps.isNotEmpty) {
        children.add(Padding(padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4), child: Text('Apps', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.6)))));
        children.addAll(_filteredApps.map((app) => Material(
          type: MaterialType.transparency,
          child: ListTile(
            leading: app.icon != null ? Image.memory(app.icon!, width: 32, height: 32) : const Icon(Icons.android),
            title: Text(app.name ?? 'Unknown App', style: TextStyle(color: textColor, fontSize: 13)),
            onTap: () { Navigator.of(context).pop(); InstalledApps.startApp(app.packageName!); },
          ),
        )));
      }
    }

    if (_activeTab == 'All' || _activeTab == 'Documents') children.add(_buildCategory('Documents', _mediaResults['Documents'] ?? [], Icons.description, textColor, state));
    if (_activeTab == 'All' || _activeTab == 'Photos') children.add(_buildCategory('Images', _mediaResults['Images'] ?? [], Icons.image, textColor, state));
    if (_activeTab == 'All' || _activeTab == 'Video') children.add(_buildCategory('Video', _mediaResults['Video'] ?? [], Icons.videocam, textColor, state));
    if (_activeTab == 'All' || _activeTab == 'Audio') children.add(_buildCategory('Audio', _mediaResults['Audio'] ?? [], Icons.music_note, textColor, state));
    
    if (_activeTab == 'All' || _activeTab == 'Web') {
      if (_searchController.text.isNotEmpty) {
         children.add(
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: const Icon(Icons.travel_explore, color: Colors.blue, size: 24),
              title: Text("Search Web for '${_searchController.text}'", style: TextStyle(color: Colors.blue.shade400, fontSize: 13, fontWeight: FontWeight.bold)),
              onTap: () => _launchWebSearch(_searchController.text),
            ),
          )
        );
      }
    }

    if (children.isEmpty && !_isSearching && _searchController.text.isNotEmpty && !_isCheckingPermissions) {
      children.add(Padding(padding: const EdgeInsets.all(32.0), child: Center(child: Text("No results found in $_activeTab", style: TextStyle(color: textColor.withOpacity(0.5))))));
    }

    return children;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    
    final baseBg = widget.isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
    final bgColor = Color.alphaBlend(widget.accentColor.withOpacity(0.08), baseBg).withOpacity(0.98);
    
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final borderColor = widget.isDark ? Colors.white24 : Colors.grey.shade300;
    
    final searchBgColor = widget.isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0);
    final chipInactiveBg = widget.isDark ? Colors.transparent : Colors.white;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 315, 
        height: 520,
        decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 15, offset: Offset(0, 10))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 12.0),
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(color: textColor, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true, hintText: 'Type here to search...', hintStyle: TextStyle(color: textColor.withOpacity(0.5), fontSize: 13), prefixIcon: const Icon(Icons.search, color: Colors.blue, size: 18),
                    filled: true, fillColor: searchBgColor, contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ),
            
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  Padding(padding: const EdgeInsets.only(left: 12, right: 4), child: Icon(Icons.arrow_back, size: 16, color: textColor.withOpacity(0.7))),
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(),
                      itemCount: _tabs.length,
                      itemBuilder: (context, index) {
                        final tab = _tabs[index];
                        final isActive = _activeTab == tab;
                        return GestureDetector(
                          onTap: () => setState(() => _activeTab = tab),
                          child: Container(
                            margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(color: isActive ? Colors.blue.shade600 : chipInactiveBg, borderRadius: BorderRadius.circular(16), border: isActive ? null : Border.all(color: borderColor)),
                            child: Center(child: Text(tab, style: TextStyle(fontSize: 12, color: isActive ? Colors.white : textColor, fontWeight: isActive ? FontWeight.bold : FontWeight.w500))),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(padding: const EdgeInsets.only(left: 4, right: 12), child: Icon(Icons.play_arrow, size: 12, color: textColor.withOpacity(0.7))),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            Expanded(
              child: _isSearching 
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      physics: const BouncingScrollPhysics(),
                      children: _buildFilteredResults(textColor, state),
                    ),
            )
          ],
        ),
      ),
    );
  }
}