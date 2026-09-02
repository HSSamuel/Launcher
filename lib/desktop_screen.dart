import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:torch_light/torch_light.dart';

import 'launcher_state.dart';
import 'lock_screen.dart';
import 'taskbar.dart';
import 'desktop_icon.dart';
import 'app_window.dart';
import 'calculator_app.dart';
import 'browser_app.dart';
import 'settings_app.dart';
import 'file_explorer_app.dart';
import 'widget_board.dart';
import 'start_menu.dart';
import 'quick_settings.dart';
import 'notification_center.dart';

class DesktopScreen extends StatefulWidget {
  const DesktopScreen({Key? key}) : super(key: key);
  @override
  State<DesktopScreen> createState() => _DesktopScreenState();
}

class _DesktopScreenState extends State<DesktopScreen> {
  bool _isStartMenuOpen = false; bool _isWidgetBoardOpen = false; bool _isQuickSettingsOpen = false; 
  bool _isNotificationCenterOpen = false; 
  
  bool _isContextMenuOpen = false; 
  Offset _contextMenuPos = Offset.zero;
  String _contextMenuType = 'desktop'; 
  
  String? _activeSubMenu; 
  double _subMenuYOffset = 0;
  
  String _contextTargetName = '';
  VoidCallback? _contextOpenAction;

  double _volume = 0.5; double _brightness = 0.5; int _batteryLevel = 100; BatteryState _batteryState = BatteryState.discharging;
  List<Map<String, dynamic>> _realNotifications = []; int _unreadNotifications = 0; 
  
  final Map<String, bool> _quickSettings = { 
    'Airplane mode': false, 'Battery saver': false, 'Wi-Fi': false, 'Bluetooth': false, 'Flash': false, 'Data': false, 'Rotate': false, 'Location': false, 'Hotspot': false, 'VPN': false, 'Brightness': false, 'Accessibility': false,
    'Play': false, 'Ring': true, 'ChatGPT': false, 'Storage': false, 'Dark Theme': false, 'Calculator': false, 'Song Search': false, 'DND': false, 'Screen Cast': false, 'Eye Care': false, 'Scan QR Code': false, 'PC Connection': false, 'Kids Mode': false,
    'Adaptive Brightness': false
  };
  final double taskbarHeight = 48.0; 

  int _maxPointers = 0;
  static const platform = MethodChannel('win_launcher/native');
  static const notificationStream = EventChannel('win_launcher/notifications');

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) { _initHardware(); _initNotifications(); }
  }

  void _initHardware() async {
    try {
      _batteryLevel = await Battery().batteryLevel;
      _batteryState = await Battery().batteryState;
      Battery().onBatteryStateChanged.listen((state) async { if (!mounted) return; final level = await Battery().batteryLevel; setState(() { _batteryState = state; _batteryLevel = level; }); });
    } catch (_) {}
    try { _volume = await VolumeController.instance.getVolume(); VolumeController.instance.addListener((vol) { if (mounted) setState(() => _volume = vol); }); } catch (_) {}
    try { _brightness = await ScreenBrightness().current; ScreenBrightness().onCurrentBrightnessChanged.listen((b) { if (mounted) setState(() => _brightness = b); }); } catch (_) {}
  }

  void _initNotifications() async {
    try {
      final perms = await platform.invokeMapMethod<String, bool>('getPermissionStatuses');
      if (perms?['notification'] != true) {
        platform.invokeMethod('openSettings', {'type': 'notification_access'});
      }

      // Initial Fetch
      _fetchActiveNotifications();

      notificationStream.receiveBroadcastStream().listen((event) {
        if (!mounted) return;
        final data = Map<String, dynamic>.from(event);
        setState(() {
          if (data['removed'] == true) {
            _realNotifications.removeWhere((n) => n['key'] == data['key']);
          } else {
            _realNotifications.removeWhere((n) => n['key'] == data['key']);
            _realNotifications.insert(0, data);
            if (!_isNotificationCenterOpen) _unreadNotifications++;
          }
        });
      });
    } catch (_) {}
  }

  // Helper method to sync edge notifications
  void _fetchActiveNotifications() async {
    try {
      final List<dynamic> active = await platform.invokeMethod('getActiveNotifications');
      if (mounted) {
        setState(() {
          _realNotifications = active.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (_) {}
  }

  void _updateBrightness(double val) { setState(() => _brightness = val); if (!kIsWeb) ScreenBrightness().setScreenBrightness(val); }
  void _updateVolume(double val) { setState(() => _volume = val); if (!kIsWeb) VolumeController.instance.setVolume(val); }
  
  void _handleHardwareToggle(String key) async {
    final state = context.read<LauncherState>();
    bool currentVal = _quickSettings[key] ?? false;
    bool newVal = !currentVal;

    if (key == 'Calculator') { state.openApp('calculator'); _toggleOverlay('quick'); return; }
    if (key == 'Storage') { state.currentExplorerPath = '/storage/emulated/0'; state.openApp('explorer'); _toggleOverlay('quick'); return; }
    if (key == 'ChatGPT') { _toggleOverlay('quick'); final success = await platform.invokeMethod('launchApp', {'package': 'com.openai.chatgpt'}); if (success != true) _showToast('ChatGPT app not installed'); return; }
    if (key == 'Dark Theme') { state.setDarkMode(newVal); setState(() { _quickSettings[key] = state.isDarkMode; }); platform.invokeMethod('toggleHardware', {'key': key, 'enable': state.isDarkMode}); return; }

    if (['Bluetooth', 'Rotate', 'Adaptive Brightness', 'Ring', 'DND'].contains(key)) { setState(() { _quickSettings[key] = newVal; }); platform.invokeMethod('toggleHardware', {'key': key, 'enable': newVal}); return; }

    if (key == 'Flash') {
      try { 
        if (currentVal) { await TorchLight.disableTorch(); setState(() => _quickSettings['Flash'] = false); } 
        else { await TorchLight.enableTorch(); setState(() => _quickSettings['Flash'] = true); } 
      } catch (e) { _showToast('Flashlight not available'); }
      return;
    }

    String settingsType = 'default';
    switch (key) {
      case 'Wi-Fi': settingsType = 'wifi'; break;
      case 'Data': settingsType = 'data'; break;
      case 'Battery saver': settingsType = 'battery_saver'; break;
      case 'Airplane mode': settingsType = 'airplane'; break;
      case 'Location': settingsType = 'location'; break;
      case 'Hotspot': settingsType = 'hotspot'; break;
      case 'VPN': settingsType = 'vpn'; break;
      case 'Accessibility': settingsType = 'accessibility'; break;
      case 'Brightness': settingsType = 'display'; break;
    }

    setState(() { _quickSettings[key] = newVal; });
    _toggleOverlay('quick'); 
    
    try {
      if (['Airplane mode', 'Location', 'Hotspot'].contains(key)) { await platform.invokeMethod('toggleHardware', {'key': key, 'enable': newVal}); } 
      else { await platform.invokeMethod('openSettings', {'type': settingsType}); }
    } catch (_) {}
  }

  Size _getResponsiveWindowSize(BuildContext context, double targetWidth, double targetHeight) {
    final screenSize = MediaQuery.of(context).size; final isMobile = screenSize.width < 600;
    if (isMobile) return Size(screenSize.width * 0.94, screenSize.height * 0.84);
    final maxWidth = screenSize.width * 0.90; final maxHeight = screenSize.height * 0.80; 
    return Size(targetWidth > maxWidth ? maxWidth : targetWidth, targetHeight > maxHeight ? maxHeight : targetHeight);
  }

  int _getGridCrossAxisCount(LauncherState state, bool isMobile) { return isMobile ? state.portraitGridX : state.landscapeGridX; }
  double _getIconScale(LauncherState state) { if (state.iconSize == 'Small') return 0.70; if (state.iconSize == 'Large') return 1.10; return 0.85; }

  void _closeOverlays() { 
    setState(() { 
      _isStartMenuOpen = false; _isContextMenuOpen = false; 
      _activeSubMenu = null; _isWidgetBoardOpen = false; 
      _isQuickSettingsOpen = false; _isNotificationCenterOpen = false; 
    }); 
  }
  
  void _toggleOverlay(String overlay) {
    setState(() {
      _isStartMenuOpen = overlay == 'start' ? !_isStartMenuOpen : false; 
      _isQuickSettingsOpen = overlay == 'quick' ? !_isQuickSettingsOpen : false; 
      _isWidgetBoardOpen = false; _isContextMenuOpen = false; _activeSubMenu = null;
      
      if (overlay == 'notification') { 
        _isNotificationCenterOpen = !_isNotificationCenterOpen; 
        if (_isNotificationCenterOpen) {
          _unreadNotifications = 0; 
          _fetchActiveNotifications(); // FIX 2: Live Sync every time panel is opened
        }
      } else { 
        _isNotificationCenterOpen = false; 
      }
    });
  }

  void _handleGestureAction(String action) async {
    if (action == 'None') return;
    if (action == 'Start Menu' || action == 'Apps Menu') _toggleOverlay('start');
    if (action == 'Notification Center') _toggleOverlay('notification');
    if (action == 'Quick Settings') _toggleOverlay('quick');
    if (action == 'Widget Board') setState(() { _closeOverlays(); _isWidgetBoardOpen = true; });
    if (action == 'Device Notification Bar') { try { await platform.invokeMethod('expandNotificationPanel'); } catch (e) { debugPrint("Failed to expand native panel: $e"); } }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(fontSize: 13)), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))));
  }

  Widget _buildContextMenuItem(String title, IconData? icon, {Color? iconColor, String? shortcut, bool hasSubMenu = false, String? subMenuKey, double subMenuY = 0, VoidCallback? onTap}) {
    return InkWell(
      onTap: () {
        if (hasSubMenu) { setState(() { _activeSubMenu = subMenuKey; _subMenuYOffset = subMenuY; }); } 
        else { _closeOverlays(); if (onTap != null) onTap(); }
      },
      hoverColor: Colors.black.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            if (icon != null) Icon(icon, size: 16, color: iconColor ?? Colors.black87),
            if (icon != null) const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w400))),
            if (shortcut != null) Text(shortcut, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            if (hasSubMenu) Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  Widget _buildSubMenuItem(String title, IconData? icon, {bool isActive = false, bool isChecked = false, bool isDot = false, VoidCallback? onTap}) {
    bool hasLeading = icon != null || isActive || isDot || isChecked;
    return InkWell(
      onTap: () { if (onTap != null) onTap(); _closeOverlays(); },
      hoverColor: Colors.black.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (hasLeading) ...[
              SizedBox(width: 16, child: isActive || isDot ? const Icon(Icons.circle, size: 6, color: Colors.black87) : (isChecked ? const Icon(Icons.check, size: 14, color: Colors.black87) : null)),
              const SizedBox(width: 8),
              if (icon != null) Icon(icon, size: 16, color: Colors.black87),
              if (icon != null) const SizedBox(width: 12),
            ],
            Expanded(child: Text(title, style: const TextStyle(fontSize: 13, color: Colors.black87))),
          ],
        ),
      ),
    );
  }

  Widget _buildContextDivider() => Container(height: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(vertical: 4));

  Widget _buildDesktopContextMenu(LauncherState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildContextMenuItem('View', Icons.grid_view, hasSubMenu: true, subMenuKey: 'view', subMenuY: 0),
        _buildContextMenuItem('Sort by', Icons.swap_vert, hasSubMenu: true, subMenuKey: 'sort', subMenuY: 36),
        _buildContextMenuItem('Refresh', Icons.refresh, onTap: () => _showToast('Desktop refreshed')),
        _buildContextDivider(),
        _buildContextMenuItem('New', Icons.add_circle_outline, onTap: () => _showToast('Create new...')),
        _buildContextDivider(),
        _buildContextMenuItem('Next desktop background', Icons.wallpaper, onTap: () => state.nextWallpaper()),
        _buildContextMenuItem('Display settings', Icons.monitor, onTap: () => state.openApp('settings')),
        _buildContextMenuItem('Personalize', Icons.brush_outlined, iconColor: const Color(0xFF0078D4), onTap: () => state.openApp('settings')),
      ],
    );
  }

  Widget _buildFolderContextMenu(LauncherState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildContextMenuItem('Open', Icons.folder, iconColor: Colors.amber.shade400, onTap: _contextOpenAction),
        _buildContextMenuItem('Pin to Quick access', Icons.push_pin_outlined, iconColor: const Color(0xFF0078D4), onTap: () { state.pinToQuickAccess(_contextTargetName); _showToast('Pinned $_contextTargetName to Quick access'); }),
        _buildContextMenuItem('Pin to Start', Icons.push_pin, iconColor: const Color(0xFF0078D4), onTap: () { state.pinToStart(_contextTargetName); _showToast('Pinned $_contextTargetName to Start'); }),
        _buildContextMenuItem('Compress to...', Icons.folder_zip_outlined, hasSubMenu: true, subMenuKey: 'compress', subMenuY: 108),
        _buildContextMenuItem('Properties', Icons.build_circle_outlined, onTap: () => _showPropertiesDialog()),
        _buildContextDivider(),
        _buildContextMenuItem('Show more options', Icons.layers_outlined, hasSubMenu: true, subMenuKey: 'more_options', subMenuY: 160),
        _buildContextDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomContextAction(Icons.content_cut, 'Cut'),
              _buildBottomContextAction(Icons.content_copy, 'Copy'),
              _buildBottomContextAction(Icons.drive_file_rename_outline, 'Rename'),
              _buildBottomContextAction(Icons.delete_outline, 'Delete'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomContextAction(IconData icon, String label) {
    return InkWell(
      onTap: () { _closeOverlays(); _showToast('$label action recorded.'); },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF0078D4)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _buildSubMenuContent(LauncherState state) {
    if (_activeSubMenu == 'view') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSubMenuItem('Large icons', Icons.crop_square, isActive: state.iconSize == 'Large', onTap: () => state.updateDesktopSetting('iconSize', 'Large')),
          _buildSubMenuItem('Medium icons', Icons.crop_7_5, isActive: state.iconSize == 'Medium', onTap: () => state.updateDesktopSetting('iconSize', 'Medium')),
          _buildSubMenuItem('Small icons', Icons.apps, isActive: state.iconSize == 'Small', onTap: () => state.updateDesktopSetting('iconSize', 'Small')),
          _buildContextDivider(),
          _buildSubMenuItem('Auto arrange icons', Icons.bolt, isChecked: true, onTap: () => _showToast('Auto arrange toggled')),
          _buildSubMenuItem('Align icons to grid', Icons.grid_4x4, isChecked: true, onTap: () => _showToast('Grid alignment toggled')),
          _buildSubMenuItem('Show desktop icons', Icons.desktop_windows, isChecked: true, onTap: () => _showToast('Desktop icons toggled')),
        ],
      );
    } else if (_activeSubMenu == 'sort') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSubMenuItem('Name', null, isDot: true, onTap: () => _showToast('Sorted by Name')),
          _buildSubMenuItem('Size', null, onTap: () => _showToast('Sorted by Size')),
          _buildSubMenuItem('Item type', null, onTap: () => _showToast('Sorted by Type')),
          _buildSubMenuItem('Date modified', null, onTap: () => _showToast('Sorted by Date')),
        ],
      );
    } else if (_activeSubMenu == 'compress') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSubMenuItem('ZIP File', null, onTap: () => _mockZipCreation('.zip')),
          _buildSubMenuItem('7z File', null, onTap: () => _mockZipCreation('.7z')),
        ],
      );
    } else if (_activeSubMenu == 'more_options') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSubMenuItem('Send to', null, onTap: () => _showToast('Opening Share menu...')),
          _buildContextDivider(),
          _buildSubMenuItem('Cut', null, onTap: () => _showToast('Cut to clipboard')),
          _buildSubMenuItem('Copy', null, onTap: () => _showToast('Copied to clipboard')),
          _buildContextDivider(),
          _buildSubMenuItem('Delete', null, onTap: () => _showToast('Moved to Recycle Bin')),
          _buildSubMenuItem('Rename', null, onTap: () => _showToast('Renaming file...')),
          _buildContextDivider(),
          _buildSubMenuItem('Properties', null, onTap: () => _showPropertiesDialog()),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  void _mockZipCreation(String extension) {
    try {
      final newZipPath = '/storage/emulated/0/$_contextTargetName$extension';
      File(newZipPath).createSync();
      _showToast('Successfully compressed to $_contextTargetName$extension');
    } catch (_) {
      _showToast('Storage permission required to compress.');
    }
  }

  void _showPropertiesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$_contextTargetName Properties', style: const TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: System App / Shortcut', style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
            const SizedBox(height: 8),
            Text('Location: Desktop > $_contextTargetName', style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
            const SizedBox(height: 8),
            Text('Size: ${(12 + _contextTargetName.length * 0.5).toStringAsFixed(2)} MB', style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      )
    );
  }

  Widget _buildContextMenuOverlay(LauncherState state) {
    if (!_isContextMenuOpen) return const SizedBox.shrink();

    double menuWidth = 240;
    double menuHeight = _contextMenuType == 'folder' ? 300 : 250; 
    double dx = _contextMenuPos.dx; double dy = _contextMenuPos.dy;
    final screenSize = MediaQuery.of(context).size;
    
    if (dx + menuWidth > screenSize.width) dx = screenSize.width - menuWidth - 8;
    if (dx < 8) dx = 8;
    if (dy + menuHeight > screenSize.height) dy = screenSize.height - menuHeight - 8;
    if (dy < 8) dy = 8;

    Widget mainMenu = Container(
      width: menuWidth,
      decoration: BoxDecoration(color: const Color(0xFFF3F3F3).withOpacity(0.95), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300, width: 1), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))]),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _contextMenuType == 'desktop' ? _buildDesktopContextMenu(state) : _buildFolderContextMenu(state),
    );

    Widget? subMenu;
    if (_activeSubMenu != null) {
      double subMenuWidth = 190; double subMenuX = dx + menuWidth - 4; 
      if (subMenuX + subMenuWidth > screenSize.width) subMenuX = dx - subMenuWidth + 4;
      if (subMenuX < 8) subMenuX = 8; 
      double subMenuY = dy + _subMenuYOffset;
      if (subMenuY + 220 > screenSize.height) subMenuY = screenSize.height - 230; 
      if (subMenuY < 8) subMenuY = 8;

      subMenu = Positioned(
        left: subMenuX, top: subMenuY,
        child: Container(
          width: subMenuWidth,
          decoration: BoxDecoration(color: const Color(0xFFF3F3F3).withOpacity(0.95), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300, width: 1), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))]),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _buildSubMenuContent(state),
        ),
      );
    }

    return Stack(children: [Positioned(left: dx, top: dy, child: mainMenu), if (subMenu != null) subMenu]);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height; 
    final isMobile = screenWidth < 600;
    
    final quickSettingsWidth = screenWidth > 300 ? 270.0 : screenWidth * 0.9;
    final notificationWidth = screenWidth > 340 ? 320.0 : screenWidth * 0.94;
    final overlayMaxHeight = screenHeight * 0.85; 

    return PopScope(
      canPop: false, 
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_isStartMenuOpen || _isQuickSettingsOpen || _isNotificationCenterOpen || _isWidgetBoardOpen || _isContextMenuOpen) { _closeOverlays(); return; }
        if (state.windowStack.isNotEmpty) state.closeApp(state.windowStack.last);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _closeOverlays, 
          onSecondaryTapDown: (details) => setState(() { _closeOverlays(); _isContextMenuOpen = true; _contextMenuPos = details.globalPosition; _contextMenuType = 'desktop'; }), 
          onLongPressStart: (details) => setState(() { _closeOverlays(); _isContextMenuOpen = true; _contextMenuPos = details.globalPosition; _contextMenuType = 'desktop'; }),
          onScaleStart: (details) { _maxPointers = details.pointerCount; },
          onScaleUpdate: (details) { if (details.pointerCount > _maxPointers) _maxPointers = details.pointerCount; },
          onScaleEnd: (details) {
            final dx = details.velocity.pixelsPerSecond.dx; final dy = details.velocity.pixelsPerSecond.dy;
            if (dx.abs() > 500 || dy.abs() > 500) {
              if (dx.abs() > dy.abs()) {
                if (dx > 500 && !_isQuickSettingsOpen && !_isNotificationCenterOpen) { setState(() { _isWidgetBoardOpen = true; _isStartMenuOpen = false; }); } else if (dx < -500) { if (_isWidgetBoardOpen) setState(() => _isWidgetBoardOpen = false); else setState(() { _isNotificationCenterOpen = true; _isStartMenuOpen = false; }); }
              } else {
                if (dy < -500) { _handleGestureAction(_maxPointers >= 2 ? state.gestureTwoFingerUpAction : state.gestureUpAction); } else if (dy > 500) { _handleGestureAction(_maxPointers >= 2 ? state.gestureTwoFingerDownAction : state.gestureDownAction); }
              }
            }
            _maxPointers = 0; 
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onDoubleTap: () async {
                    if (state.doubleTapToSleep) {
                      _closeOverlays();
                      try { await platform.invokeMethod('lockScreen'); } catch (_) {}
                      if (mounted) Navigator.of(context).pushReplacement(PageRouteBuilder(pageBuilder: (context, animation, secondaryAnimation) => const LockScreen(), transitionsBuilder: (context, animation, secondaryAnimation, child) { return FadeTransition(opacity: animation, child: child); }));
                    }
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: SizedBox.expand( 
                      key: ValueKey<String>(state.actualWallpaperUrl),
                      child: CachedNetworkImage(
                        imageUrl: state.actualWallpaperUrl, fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: const Color(0xFF003D73)),
                        errorWidget: (_, __, ___) => Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF003D73), Color(0xFF191919)]))),
                      ),
                    ),
                  ),
                ),
              ),

              Positioned.fill(
                child: SafeArea(
                  top: false, 
                  child: Stack(
                    children: [
                      Positioned.fill(
                        top: 10 + MediaQuery.of(context).padding.top, left: 10, bottom: taskbarHeight,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: screenWidth * 0.8,
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                              child: GridView.count(
                              physics: const BouncingScrollPhysics(),
                              crossAxisCount: _getGridCrossAxisCount(state, isMobile), 
                              childAspectRatio: 0.80, 
                              mainAxisSpacing: 16, crossAxisSpacing: 8,
                              children: [
                                GestureDetector(
                                  onSecondaryTapDown: (details) => setState(() { _closeOverlays(); _isContextMenuOpen = true; _contextMenuPos = details.globalPosition; _contextMenuType = 'folder'; _contextTargetName = 'Recycle Bin'; _contextOpenAction = () { final rb = Directory('/storage/emulated/0/.RecycleBin'); if (!rb.existsSync()) { try{ rb.createSync(); }catch(_){} } state.currentExplorerPath = rb.path; state.openApp('explorer'); }; }), 
                                  onLongPressStart: (details) => setState(() { _closeOverlays(); _isContextMenuOpen = true; _contextMenuPos = details.globalPosition; _contextMenuType = 'folder'; _contextTargetName = 'Recycle Bin'; _contextOpenAction = () { final rb = Directory('/storage/emulated/0/.RecycleBin'); if (!rb.existsSync()) { try{ rb.createSync(); }catch(_){} } state.currentExplorerPath = rb.path; state.openApp('explorer'); }; }),
                                  child: Transform.scale(scale: _getIconScale(state), child: DesktopIcon(icon: Icons.delete_outline, label: 'Recycle Bin', iconColor: Colors.white70, onTap: () { _closeOverlays(); final rb = Directory('/storage/emulated/0/.RecycleBin'); if (!rb.existsSync()) { try{ rb.createSync(); }catch(_){} } state.currentExplorerPath = rb.path; state.openApp('explorer'); }))
                                ),
                                GestureDetector(
                                  onSecondaryTapDown: (details) => setState(() { _closeOverlays(); _isContextMenuOpen = true; _contextMenuPos = details.globalPosition; _contextMenuType = 'folder'; _contextTargetName = 'My Files'; _contextOpenAction = () { state.currentExplorerPath = '/storage/emulated/0'; state.openApp('explorer'); }; }), 
                                  onLongPressStart: (details) => setState(() { _closeOverlays(); _isContextMenuOpen = true; _contextMenuPos = details.globalPosition; _contextMenuType = 'folder'; _contextTargetName = 'My Files'; _contextOpenAction = () { state.currentExplorerPath = '/storage/emulated/0'; state.openApp('explorer'); }; }),
                                  child: Transform.scale(scale: _getIconScale(state), child: DesktopIcon(customIcon: Image.asset('assets/icons/folder.png', width: 36, height: 36, errorBuilder: (context, error, stackTrace) => const Icon(Icons.folder, color: Colors.amber, size: 36)), label: 'My Files', onTap: () { _closeOverlays(); state.currentExplorerPath = '/storage/emulated/0'; state.openApp('explorer'); }))
                                ),
                                GestureDetector(
                                  onSecondaryTapDown: (details) => setState(() { _closeOverlays(); _isContextMenuOpen = true; _contextMenuPos = details.globalPosition; _contextMenuType = 'folder'; _contextTargetName = 'Calculator'; _contextOpenAction = () => state.openApp('calculator'); }), 
                                  onLongPressStart: (details) => setState(() { _closeOverlays(); _isContextMenuOpen = true; _contextMenuPos = details.globalPosition; _contextMenuType = 'folder'; _contextTargetName = 'Calculator'; _contextOpenAction = () => state.openApp('calculator'); }),
                                  child: Transform.scale(scale: _getIconScale(state), child: DesktopIcon(icon: Icons.calculate, label: 'Calculator', iconColor: Colors.grey, onTap: () { _closeOverlays(); state.openApp('calculator'); }))
                                ),
                                GestureDetector(
                                  onSecondaryTapDown: (details) => setState(() { _closeOverlays(); _isContextMenuOpen = true; _contextMenuPos = details.globalPosition; _contextMenuType = 'folder'; _contextTargetName = 'Edge'; _contextOpenAction = () => state.openApp('browser'); }), 
                                  onLongPressStart: (details) => setState(() { _closeOverlays(); _isContextMenuOpen = true; _contextMenuPos = details.globalPosition; _contextMenuType = 'folder'; _contextTargetName = 'Edge'; _contextOpenAction = () => state.openApp('browser'); }),
                                  child: Transform.scale(scale: _getIconScale(state), child: DesktopIcon(icon: Icons.language, label: 'Edge', iconColor: Colors.blue, onTap: () { _closeOverlays(); state.openApp('browser'); }))
                                ),
                                GestureDetector(
                                  onSecondaryTapDown: (details) => setState(() { _closeOverlays(); _isContextMenuOpen = true; _contextMenuPos = details.globalPosition; _contextMenuType = 'folder'; _contextTargetName = 'Settings'; _contextOpenAction = () => state.openApp('settings'); }), 
                                  onLongPressStart: (details) => setState(() { _closeOverlays(); _isContextMenuOpen = true; _contextMenuPos = details.globalPosition; _contextMenuType = 'folder'; _contextTargetName = 'Settings'; _contextOpenAction = () => state.openApp('settings'); }),
                                  child: Transform.scale(scale: _getIconScale(state), child: DesktopIcon(icon: Icons.settings, label: 'Settings', iconColor: Colors.blueGrey, onTap: () { _closeOverlays(); state.openApp('settings'); }))
                                ),
                              ],
                            ),
                            ),
                          ),
                        ),
                      ),

                      ...state.windowStack.map((windowId) {
                        final isMinimized = state.minimizedApps.contains(windowId);
                        final isMaximized = state.maximizedApps.contains(windowId) || isMobile;

                        final size = isMobile ? Size(screenWidth, screenHeight - taskbarHeight) : _getResponsiveWindowSize(context, windowId == 'explorer' ? 580 : (windowId == 'calculator' ? 320 : 600), windowId == 'calculator' ? 480 : 420);
                        final pos = isMobile ? Offset.zero : (windowId == 'explorer' ? state.fileExplorerPos : (windowId == 'calculator' ? state.calculatorPos : (windowId == 'browser' ? state.browserPos : state.settingsPos)));
                        
                        Widget content = const SizedBox.shrink(); String title = ""; IconData icon = Icons.apps;
                        if (windowId == 'browser') { content = const BrowserApp(); title = 'Edge'; icon = Icons.language; }
                        if (windowId == 'explorer') { content = const FileExplorerApp(); title = 'This PC'; icon = Icons.folder; }
                        if (windowId == 'calculator') { content = const CalculatorApp(); title = 'Calculator'; icon = Icons.calculate; }
                        if (windowId == 'settings') { content = const SettingsApp(); title = 'Settings'; icon = Icons.settings; }

                        return AppWindow(
                          title: title, icon: icon, position: pos, size: size, isMinimized: isMinimized, isMaximized: isMaximized, useSafeArea: windowId != 'settings' && windowId != 'browser',
                          onClose: () => state.closeApp(windowId), onMinimize: () => state.minimizeApp(windowId), onMaximize: () => state.toggleMaximizeApp(windowId),
                          onDrag: (delta) { if (!isMobile) state.updateWindowPos(windowId, delta); },
                          onFocus: () { _closeOverlays(); state.focusWindow(windowId); }, content: content,
                        );
                      }).toList(),

                      if (_isStartMenuOpen) 
                        Positioned(bottom: taskbarHeight, left: 6, child: SizedBox(width: 290, height: screenHeight * 0.75, child: StartMenu(onOverlaysClosed: _closeOverlays, onPowerTapped: () { Navigator.of(context).pushReplacement(PageRouteBuilder(pageBuilder: (context, animation, secondaryAnimation) => const LockScreen(), transitionsBuilder: (context, animation, secondaryAnimation, child) { return FadeTransition(opacity: animation, child: child); })); }))),
                      
                      if (_isQuickSettingsOpen) 
                        Positioned(
                          bottom: taskbarHeight + 8, right: 8, width: quickSettingsWidth, 
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: overlayMaxHeight),
                            child: QuickSettings(
                              settingsState: _quickSettings, 
                              onToggle: _handleHardwareToggle, 
                              brightness: _brightness, onBrightnessChanged: _updateBrightness, 
                              volume: _volume, onVolumeChanged: _updateVolume, 
                              batteryLevel: _batteryLevel, batteryState: _batteryState,
                              onOpenSettings: () { state.openApp('settings'); _toggleOverlay('quick'); },
                              visibleTiles: state.visibleQuickSettings,
                              hiddenTiles: state.hiddenQuickSettings,
                              onToggleVisibility: state.toggleQuickSettingVisibility,
                            )
                          )
                        ),
                        
                      if (_isNotificationCenterOpen) 
                        Positioned(
                          bottom: taskbarHeight + 8, right: 8, width: notificationWidth, 
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: screenHeight * 0.88), 
                            child: NotificationCenterPanel(
                              notifications: _realNotifications, 
                              installedApps: state.installedApps, 
                              onClearAll: () {
                                platform.invokeMethod('clearAllNotifications');
                                setState(() => _realNotifications.clear());
                              },
                              onRemoveNotification: (event) {
                                platform.invokeMethod('dismissNotification', {'key': event['key']});
                                setState(() => _realNotifications.removeWhere((n) => n['key'] == event['key']));
                              },
                              onLaunchApp: (pkg) async {
                                _toggleOverlay('notification');
                                final success = await platform.invokeMethod('launchApp', {'package': pkg});
                                if (success != true) _showToast('App not found');
                              }
                            )
                          )
                        ),

                      Win11Taskbar(
                        isStartMenuOpen: _isStartMenuOpen, onStartToggled: () => _toggleOverlay('start'), onQuickSettingsToggled: () => _toggleOverlay('quick'), onNotificationCenterToggled: () => _toggleOverlay('notification'), onOverlaysClosed: _closeOverlays,
                        batteryLevel: _batteryLevel, batteryState: _batteryState, unreadNotifications: _unreadNotifications,    
                      ),
                      
                      _buildContextMenuOverlay(state),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}