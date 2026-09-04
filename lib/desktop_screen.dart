import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart'; 
import 'package:flutter/rendering.dart'; 
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:torch_light/torch_light.dart';

import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import 'launcher_state.dart';
import 'lock_screen.dart';
import 'taskbar.dart';
import 'desktop_icon.dart';
import 'app_window.dart';
import 'calculator_app.dart';
import 'browser_app.dart';
import 'settings_app.dart';
import 'file_explorer_app.dart';
import 'start_menu.dart';
import 'quick_settings.dart';
import 'notification_center.dart';

class DesktopScreen extends StatefulWidget {
  const DesktopScreen({Key? key}) : super(key: key);
  @override
  State<DesktopScreen> createState() => _DesktopScreenState();
}

class _DesktopScreenState extends State<DesktopScreen> {
  final GlobalKey<FileExplorerAppState> _explorerKey = GlobalKey<FileExplorerAppState>();
  final PageController _pageController = PageController();
  
  int _currentDesktopPage = 0;

  bool _isStartMenuOpen = false;
  bool _isWidgetBoardOpen = false;
  bool _isQuickSettingsOpen = false;
  bool _isNotificationCenterOpen = false;

  bool _isContextMenuOpen = false;
  Offset _contextMenuPos = Offset.zero;
  String _contextMenuType = 'desktop';

  String? _activeSubMenu;
  double _subMenuYOffset = 0;

  String _contextTargetName = '';
  VoidCallback? _contextOpenAction;

  // NEW: State variables mapping the live visual drag interactions during resize
  String? _resizingWidgetId;
  double _resizeAccumulatorX = 0;
  double _resizeAccumulatorY = 0;

  double _volume = 0.5;
  double _brightness = 0.5;
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.discharging;
  List<Map<String, dynamic>> _realNotifications = [];
  int _unreadNotifications = 0;

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
    if (!kIsWeb) {
      _initHardware();
      _initNotifications();
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      try { VolumeController.instance.removeListener(); } catch (_) {}
    }
    _pageController.dispose();
    super.dispose();
  }

  void _initHardware() async {
    try {
      _batteryLevel = await Battery().batteryLevel;
      _batteryState = await Battery().batteryState;
      Battery().onBatteryStateChanged.listen((state) async {
        if (!mounted) return;
        final level = await Battery().batteryLevel;
        setState(() {
          _batteryState = state;
          _batteryLevel = level;
        });
      });
    } catch (_) {}
    
    try {
      double v = await VolumeController.instance.getVolume();
      if (v.isNaN || v.isInfinite) v = 0.5;
      if (v > 1.0) v = v / 15.0; 
      _volume = v.clamp(0.0, 1.0);
      VolumeController.instance.addListener((vol) {
        if (mounted) {
           if (vol.isNaN || vol.isInfinite) vol = 0.5;
           setState(() => _volume = (vol > 1.0 ? vol / 15.0 : vol).clamp(0.0, 1.0));
        }
      });
    } catch (_) {}
    
    try {
      double b = await ScreenBrightness().current;
      if (b.isNaN || b.isInfinite) b = 0.5;
      _brightness = b.clamp(0.0, 1.0);
      ScreenBrightness().onCurrentBrightnessChanged.listen((bValue) {
        if (mounted) {
           if (bValue.isNaN || bValue.isInfinite) bValue = 0.5;
           setState(() => _brightness = bValue.clamp(0.0, 1.0));
        }
      });
    } catch (_) {}
  }

  void _initNotifications() async {
    try {
      final perms = await platform.invokeMapMethod<String, bool>('getPermissionStatuses');
      if (perms?['notification'] != true) {
        platform.invokeMethod('openSettings', {'type': 'notification_access'});
      }

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

  void _updateBrightness(double val) {
    if (val.isNaN || val.isInfinite) val = 0.5;
    setState(() => _brightness = val.clamp(0.0, 1.0));
    if (!kIsWeb) ScreenBrightness().setScreenBrightness(_brightness);
  }

  void _updateVolume(double val) {
    if (val.isNaN || val.isInfinite) val = 0.5;
    setState(() => _volume = val.clamp(0.0, 1.0));
    if (!kIsWeb) VolumeController.instance.setVolume(_volume);
  }

  void _handleHardwareToggle(String key) async {
    final state = context.read<LauncherState>();
    bool currentVal = _quickSettings[key] ?? false;
    bool newVal = !currentVal;

    if (key == 'Calculator') { state.openApp('calculator'); _toggleOverlay('quick'); return; }
    if (key == 'Storage') { state.currentExplorerPath = '/storage/emulated/0'; state.openApp('explorer'); _toggleOverlay('quick'); return; }
    if (key == 'ChatGPT') {
      _toggleOverlay('quick');
      final success = await platform.invokeMethod('launchApp', {'package': 'com.openai.chatgpt'});
      if (success != true) _showToast('ChatGPT app not installed');
      return;
    }
    if (key == 'Dark Theme') {
      state.setDarkMode(newVal);
      setState(() { _quickSettings[key] = state.isDarkMode; });
      platform.invokeMethod('toggleHardware', {'key': key, 'enable': state.isDarkMode});
      return;
    }

    if (['Bluetooth', 'Rotate', 'Adaptive Brightness', 'Ring', 'DND'].contains(key)) {
      setState(() { _quickSettings[key] = newVal; });
      platform.invokeMethod('toggleHardware', {'key': key, 'enable': newVal});
      return;
    }

    if (key == 'Flash') {
      try {
        if (currentVal) {
          await TorchLight.disableTorch();
          setState(() => _quickSettings['Flash'] = false);
        } else {
          await TorchLight.enableTorch();
          setState(() => _quickSettings['Flash'] = true);
        }
      } catch (e) {
        _showToast('Flashlight not available');
      }
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
      if (['Airplane mode', 'Location', 'Hotspot'].contains(key)) {
        await platform.invokeMethod('toggleHardware', {'key': key, 'enable': newVal});
      } else {
        await platform.invokeMethod('openSettings', {'type': settingsType});
      }
    } catch (_) {}
  }

  Size _getResponsiveWindowSize(BuildContext context, double targetWidth, double targetHeight) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;
    if (isMobile) return Size(screenSize.width * 0.94, screenSize.height * 0.84);
    final maxWidth = screenSize.width * 0.90;
    final maxHeight = screenSize.height * 0.80;
    return Size(targetWidth > maxWidth ? maxWidth : targetWidth, targetHeight > maxHeight ? maxHeight : targetHeight);
  }

  double _getIconScale(LauncherState state) {
    if (state.iconSize == 'Small') return 0.70;
    if (state.iconSize == 'Large') return 1.10;
    return 0.85;
  }

  void _closeOverlays() {
    setState(() {
      _isStartMenuOpen = false;
      _isContextMenuOpen = false;
      _activeSubMenu = null;
      _isWidgetBoardOpen = false;
      _isQuickSettingsOpen = false;
      _isNotificationCenterOpen = false;
      _resizingWidgetId = null;
    });
  }

  void _toggleOverlay(String overlay) {
    setState(() {
      _isStartMenuOpen = overlay == 'start' ? !_isStartMenuOpen : false;
      _isQuickSettingsOpen = overlay == 'quick' ? !_isQuickSettingsOpen : false;
      _isWidgetBoardOpen = false;
      _isContextMenuOpen = false;
      _activeSubMenu = null;
      _resizingWidgetId = null;

      if (overlay == 'notification') {
        _isNotificationCenterOpen = !_isNotificationCenterOpen;
        if (_isNotificationCenterOpen) {
          _unreadNotifications = 0;
          _fetchActiveNotifications();
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
    if (action == 'Device Notification Bar') {
      try {
        await platform.invokeMethod('expandNotificationPanel');
      } catch (e) {
        debugPrint("Failed to expand native panel: $e");
      }
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  void _showRenameDialog(DesktopItemModel item, LauncherState state) {
    final controller = TextEditingController(text: item.label);
    final isDark = state.isDarkMode;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text('Rename', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
          decoration: const InputDecoration(
            isDense: true,
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              Navigator.pop(ctx);
              if (newName.isNotEmpty && newName != item.label) {
                Future.delayed(const Duration(milliseconds: 150), () {
                  state.renameDesktopItem(item.id, newName);
                  _showToast('Renamed successfully');
                });
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
    ).then((_) {
      Future.delayed(const Duration(milliseconds: 500), () => controller.dispose());
    });
  }

  Widget _buildContextMenuItem(
    String title,
    IconData? icon,
    LauncherState state, {
    Color? iconColor,
    String? shortcut,
    bool hasSubMenu = false,
    String? subMenuKey,
    double subMenuY = 0,
    VoidCallback? onTap,
  }) {
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final defaultIconColor = isDark ? Colors.white : Colors.black87;
    final hoverColor = isDark ? Colors.white10 : Colors.black.withOpacity(0.05);
    final chevronColor = isDark ? Colors.white54 : Colors.grey.shade600;

    return InkWell(
      onTap: () {
        if (hasSubMenu) {
          setState(() {
            _activeSubMenu = subMenuKey;
            _subMenuYOffset = subMenuY;
          });
        } else {
          _closeOverlays();
          if (onTap != null) {
            Future.delayed(const Duration(milliseconds: 150), onTap);
          }
        }
      },
      hoverColor: hoverColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            if (icon != null) Icon(icon, size: 16, color: iconColor ?? defaultIconColor),
            if (icon != null) const SizedBox(width: 12),
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w400))),
            if (shortcut != null) Text(shortcut, style: TextStyle(fontSize: 12, color: chevronColor)),
            if (hasSubMenu) Icon(Icons.chevron_right, size: 16, color: chevronColor),
          ],
        ),
      ),
    );
  }

  Widget _buildSubMenuItem(
    String title,
    IconData? icon,
    LauncherState state, {
    bool isActive = false,
    bool isChecked = false,
    bool isDot = false,
    VoidCallback? onTap,
  }) {
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final iconColor = isDark ? Colors.white : Colors.black87;
    final hoverColor = isDark ? Colors.white10 : Colors.black.withOpacity(0.05);
    bool hasLeading = icon != null || isActive || isDot || isChecked;

    return InkWell(
      onTap: () {
        _closeOverlays();
        if (onTap != null) {
           Future.delayed(const Duration(milliseconds: 150), onTap);
        }
      },
      hoverColor: hoverColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (hasLeading) ...[
              SizedBox(
                width: 16,
                child: isActive || isDot
                    ? Icon(Icons.circle, size: 6, color: iconColor)
                    : (isChecked ? Icon(Icons.check, size: 14, color: iconColor) : null),
              ),
              const SizedBox(width: 8),
              if (icon != null) Icon(icon, size: 16, color: iconColor),
              if (icon != null) const SizedBox(width: 12),
            ],
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, color: textColor))),
          ],
        ),
      ),
    );
  }

  Widget _buildContextDivider(LauncherState state) => Container(
    height: 1,
    color: state.isDarkMode ? Colors.white24 : Colors.grey.shade300,
    margin: const EdgeInsets.symmetric(vertical: 4),
  );

  void _showAddWidgetDialog(LauncherState state) {
    final isDark = state.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white70 : Colors.black54;

    final availableWidgets = [
      {'type': 'clock', 'name': 'Digital Clock & Date', 'desc': 'Live updating clock with current day/date', 'icon': Icons.access_time},
      {'type': 'weather', 'name': 'Weather Card', 'desc': 'Displays local temperature and sky conditions', 'icon': Icons.wb_sunny_outlined},
      {'type': 'battery', 'name': 'Battery & Power', 'desc': 'Live battery level meter and charging state', 'icon': Icons.battery_charging_full},
      {'type': 'storage', 'name': 'Internal Storage', 'desc': 'Storage capacity bar and remaining free GB', 'icon': Icons.storage},
      {'type': 'calendar', 'name': 'Calendar Agenda', 'desc': 'Today\'s agenda and active event tracker', 'icon': Icons.calendar_month_outlined},
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text('Add Built-in Widget', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 320,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            itemCount: availableWidgets.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade200),
            itemBuilder: (context, index) {
              final w = availableWidgets[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(w['icon'] as IconData, color: Colors.blueAccent, size: 22),
                ),
                title: Text(w['name'] as String, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(w['desc'] as String, style: TextStyle(color: subColor, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  int targetCol = 0;
                  int targetRow = 1;
                  while (state.desktopItems.any((i) => i.page == _currentDesktopPage && i.col == targetCol && i.row == targetRow)) {
                    targetRow++;
                    if (targetRow >= state.portraitGridY - 1) {
                      targetRow = 0;
                      targetCol = (targetCol + 2) % state.portraitGridX;
                    }
                  }

                  state.addDesktopWidget(
                    w['type'] as String,
                    w['name'] as String,
                    _currentDesktopPage,
                    targetCol,
                    targetRow,
                    spanX: 2,
                    spanY: 1,
                  );
                  _showToast('Added ${w['name']} to Desktop');
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: subColor))),
        ],
      ),
    );
  }

  Widget _buildDynamicContextMenu(LauncherState state) {
    if (_contextMenuType == 'desktop') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildContextMenuItem('View', Icons.grid_view, state, hasSubMenu: true, subMenuKey: 'view', subMenuY: 0),
          _buildContextMenuItem('Sort by', Icons.swap_vert, state, hasSubMenu: true, subMenuKey: 'sort', subMenuY: 36),
          _buildContextMenuItem('Refresh', Icons.refresh, state, onTap: () => _showToast('Desktop refreshed')),
          if (state.clipboardPath != null) ...[
            _buildContextDivider(state),
            _buildContextMenuItem('Paste', Icons.assignment_outlined, state, iconColor: Colors.blueAccent, onTap: () {
              final original = state.desktopItems.firstWhere((i) => i.id == state.clipboardPath, orElse: () => DesktopItemModel(id: '', type: '', label: '', page: 0, col: 0, row: 0));
              if (original.id.isNotEmpty) {
                 if (state.isCut) {
                    state.updateItemPosition(original.id, _currentDesktopPage, 0, 0);
                    state.clearClipboard();
                 } else {
                    state.desktopItems.add(DesktopItemModel(
                       id: '${original.id}_copy_${DateTime.now().millisecondsSinceEpoch}',
                       type: original.type,
                       label: '${original.label} - Copy',
                       package: original.package,
                       path: original.path,
                       widgetType: original.widgetType,
                       appWidgetId: original.appWidgetId,
                       spanX: original.spanX,
                       spanY: original.spanY,
                       page: _currentDesktopPage,
                       col: 0,
                       row: 0,
                    ));
                 }
                 _showToast('Pasted to Desktop');
              }
            }),
          ],
          _buildContextDivider(state),
          _buildContextMenuItem('Add Built-in Widget', Icons.widgets_outlined, state, iconColor: Colors.blueAccent, onTap: () => _showAddWidgetDialog(state)),
          _buildContextMenuItem('Add Android Widget', Icons.android, state, iconColor: Colors.green, onTap: () {
            state.addNativeWidget(_currentDesktopPage, 0, 0);
          }),
          _buildContextDivider(state),
          _buildContextMenuItem('New Desktop Page', Icons.add_to_photos_outlined, state, onTap: () {
            state.addDesktopPage();
            _pageController.animateToPage(state.desktopPages - 1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
            _showToast('New workspace created');
          }),
          _buildContextMenuItem('Delete Desktop Page', Icons.remove_circle_outline, state, onTap: () {
            if (state.desktopPages > 1) {
              state.removeDesktopPage();
              _showToast('Workspace deleted');
            } else {
              _showToast('Cannot delete the last workspace');
            }
          }),
          _buildContextMenuItem(
            state.dragIcons ? 'Lock Desktop Icons' : 'Unlock Desktop Icons', 
            state.dragIcons ? Icons.lock_outline : Icons.lock_open_outlined, 
            state, 
            onTap: () {
              bool currentlyDraggable = state.dragIcons;
              state.updateDesktopSetting('dragIcons', !currentlyDraggable);
              _showToast(currentlyDraggable ? 'Desktop icons locked' : 'Desktop icons unlocked');
            }
          ),
          _buildContextDivider(state),
          _buildContextMenuItem('Next desktop background', Icons.wallpaper, state, onTap: () => state.nextWallpaper()),
          _buildContextMenuItem('Personalize', Icons.brush_outlined, state, iconColor: const Color(0xFF0078D4), onTap: () => state.openApp('settings')),
        ],
      );
    }

    final matches = state.desktopItems.where((i) => i.label == _contextTargetName);
    if (matches.isEmpty) return const SizedBox.shrink();
    final item = matches.first;

    List<Widget> menuItems = [];

    if (item.type == 'app') {
      final isPinnedToStart = state.pinnedStart.contains(item.package);
      menuItems.addAll([
        _buildContextMenuItem('Open', Icons.open_in_new, state, onTap: _contextOpenAction),
        _buildContextMenuItem('App info', Icons.info_outline, state, onTap: () {
          if (item.package != null) InstalledApps.openSettings(item.package!);
        }),
        _buildContextMenuItem(isPinnedToStart ? 'Unpin from Start' : 'Pin to Start', isPinnedToStart ? Icons.push_pin_outlined : Icons.push_pin, state, onTap: () {
          if (item.package != null) {
            state.togglePinToStart(item.package!);
            _showToast(isPinnedToStart ? 'Unpinned from Start' : 'Pinned to Start');
          }
        }),
        _buildContextMenuItem('Remove from Desktop', Icons.delete_sweep, state, onTap: () {
          state.removeDesktopItem(item.id);
          _showToast('Removed from Desktop');
        }),
        _buildContextDivider(state),
        _buildContextMenuItem('Uninstall', Icons.delete_outline, state, iconColor: Colors.redAccent, onTap: () {
          if (item.package != null) platform.invokeMethod('uninstallApp', {'package': item.package});
        }),
      ]);
    } else if (item.type == 'system') {
      menuItems.addAll([
        _buildContextMenuItem('Open', Icons.folder, state, iconColor: Colors.amber.shade400, onTap: _contextOpenAction),
        if (item.id == 'recycle_bin')
          _buildContextMenuItem('Empty Recycle Bin', Icons.delete_outline, state, onTap: () { _showToast('Recycle Bin emptied'); }),
        _buildContextMenuItem('Remove Shortcut', Icons.delete_sweep, state, onTap: () {
          state.removeDesktopItem(item.id);
          _showToast('Removed shortcut');
        }),
      ]);
    } else if (item.type == 'widget' || item.type == 'native_widget') {
      menuItems.addAll([
        // FIX: The Context Menu explicitly engages Resize Mode and clears old drag accumulators
        _buildContextMenuItem('Resize Widget', Icons.aspect_ratio, state, onTap: () {
          setState(() {
            _resizingWidgetId = item.id;
            _resizeAccumulatorX = 0;
            _resizeAccumulatorY = 0;
          });
        }),
        _buildContextMenuItem('Remove Widget', Icons.delete_sweep, state, iconColor: Colors.redAccent, onTap: () {
          state.removeDesktopItem(item.id);
          if (item.type == 'native_widget' && item.appWidgetId != null) {
            platform.invokeMethod('removeWidget', {'appWidgetId': item.appWidgetId});
          }
          _showToast('Widget removed');
        }),
      ]);
    } else if (item.type == 'file') {
      menuItems.addAll([
        _buildContextMenuItem('Open', Icons.open_in_new, state, onTap: _contextOpenAction),
        _buildContextMenuItem('Compress to...', Icons.folder_zip_outlined, state, hasSubMenu: true, subMenuKey: 'compress', subMenuY: 108),
        _buildContextMenuItem('Properties', Icons.build_circle_outlined, state, onTap: () => _showPropertiesDialog()),
        _buildContextDivider(state),
        _buildContextMenuItem('Remove from Desktop', Icons.delete_sweep, state, onTap: () {
          state.removeDesktopItem(item.id);
          _showToast('Removed from Desktop');
        }),
        _buildContextDivider(state),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomContextAction(Icons.content_cut, 'Cut', item, state),
              _buildBottomContextAction(Icons.content_copy, 'Copy', item, state),
              _buildBottomContextAction(Icons.drive_file_rename_outline, 'Rename', item, state),
              _buildBottomContextAction(Icons.delete_outline, 'Delete', item, state),
            ],
          ),
        ),
      ]);
    }

    return Column(mainAxisSize: MainAxisSize.min, children: menuItems);
  }

  Widget _buildBottomContextAction(IconData icon, String label, DesktopItemModel item, LauncherState state) {
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hoverColor = isDark ? Colors.white10 : Colors.black.withOpacity(0.05);

    return InkWell(
      onTap: () {
        _closeOverlays();
        Future.delayed(const Duration(milliseconds: 150), () {
          if (label == 'Cut') {
             state.setClipboard(item.id, true); 
             _showToast('Cut to clipboard'); 
          } else if (label == 'Copy') {
             state.setClipboard(item.id, false); 
             _showToast('Copied to clipboard'); 
          } else if (label == 'Rename') {
             _showRenameDialog(item, state);
          } else if (label == 'Delete') {
             state.removeDesktopItem(item.id);
             _showToast('Deleted item');
          }
        });
      },
      hoverColor: hoverColor,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF0078D4)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: textColor)),
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
          _buildContextMenuItem('Large icons', null, state, onTap: () => state.updateDesktopSetting('iconSize', 'Large')),
          _buildContextMenuItem('Medium icons', null, state, onTap: () => state.updateDesktopSetting('iconSize', 'Medium')),
          _buildContextMenuItem('Small icons', null, state, onTap: () => state.updateDesktopSetting('iconSize', 'Small')),
        ],
      );
    } else if (_activeSubMenu == 'sort') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildContextMenuItem('Name', null, state, onTap: () => _showToast('Sorted by Name')),
          _buildContextMenuItem('Size', null, state, onTap: () => _showToast('Sorted by Size')),
          _buildContextMenuItem('Item type', null, state, onTap: () => _showToast('Sorted by Type')),
          _buildContextMenuItem('Date modified', null, state, onTap: () => _showToast('Sorted by Date')),
        ],
      );
    } else if (_activeSubMenu == 'compress') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildContextMenuItem('ZIP File', null, state, onTap: () => _mockZipCreation('.zip')),
          _buildContextMenuItem('7z File', null, state, onTap: () => _mockZipCreation('.7z')),
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
    final isDark = context.read<LauncherState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.grey.shade800;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('$_contextTargetName Properties', style: TextStyle(fontSize: 15, color: textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: Shortcut / Widget', style: TextStyle(fontSize: 13, color: subTextColor)),
            const SizedBox(height: 8),
            Text('Location: Desktop > $_contextTargetName', style: TextStyle(fontSize: 13, color: subTextColor)),
            const SizedBox(height: 8),
            Text('Size: ${(12 + _contextTargetName.length * 0.5).toStringAsFixed(2)} MB', style: TextStyle(fontSize: 13, color: subTextColor)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Colors.blueAccent)))],
      ),
    );
  }

  Widget _buildContextMenuOverlay(LauncherState state) {
    if (!_isContextMenuOpen) return const SizedBox.shrink();

    final isDark = state.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B).withOpacity(0.95) : const Color(0xFFF3F3F3).withOpacity(0.95);
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;

    double menuWidth = 240;
    double menuHeight = _contextMenuType == 'folder' ? 360 : 380; 
    double dx = _contextMenuPos.dx;
    double dy = _contextMenuPos.dy;
    final screenSize = MediaQuery.of(context).size;

    if (dx + menuWidth > screenSize.width) dx = screenSize.width - menuWidth - 8;
    if (dx < 8) dx = 8;
    if (dy + menuHeight > screenSize.height) dy = screenSize.height - menuHeight - 8;
    if (dy < 8) dy = 8;

    Widget mainMenu = Container(
      width: menuWidth,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _buildDynamicContextMenu(state),
    );

    Widget? subMenu;
    if (_activeSubMenu != null) {
      double subMenuWidth = 190;
      double subMenuX = dx + menuWidth - 4;
      if (subMenuX + subMenuWidth > screenSize.width) subMenuX = dx - subMenuWidth + 4;
      if (subMenuX < 8) subMenuX = 8;
      double subMenuY = dy + _subMenuYOffset;
      if (subMenuY + 220 > screenSize.height) subMenuY = screenSize.height - 230;
      if (subMenuY < 8) subMenuY = 8;

      subMenu = Positioned(
        left: subMenuX,
        top: subMenuY,
        child: Container(
          width: subMenuWidth,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
          ),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _buildSubMenuContent(state),
        ),
      );
    }

    return Stack(children: [Positioned(left: dx, top: dy, child: mainMenu), if (subMenu != null) subMenu]);
  }

  Widget _getDesktopIconWidget(DesktopItemModel item, LauncherState state) {
    if (item.type == 'system') {
      String asset = 'folder';
      if (item.id == 'browser') asset = 'edge';
      if (item.id == 'calculator') asset = 'calculator';
      if (item.id == 'settings') asset = 'settings';
      if (item.id == 'recycle_bin') asset = 'recycle';
      return Image.asset('assets/icons/$asset.png', width: 36, height: 36, errorBuilder: (_, __, ___) => const Icon(Icons.apps, color: Colors.blue, size: 36));
    }
    
    if (item.type == 'app' && item.package != null) {
      try {
        final appInfo = state.installedApps.firstWhere((a) => a.packageName == item.package);
        if (appInfo.icon != null && appInfo.icon!.isNotEmpty) {
          return Image.memory(appInfo.icon!, width: 36, height: 36);
        }
      } catch (_) {}
      return const Icon(Icons.android, color: Colors.green, size: 36);
    }
    
    return const Icon(Icons.insert_drive_file, color: Colors.white, size: 36);
  }

  Widget _buildDesktopWidgetCard(DesktopItemModel item, LauncherState state, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E1E1E).withOpacity(0.85) : Colors.white.withOpacity(0.85);
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white70 : Colors.black54;

    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final timeStr = '$hour:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';

    Widget content = const SizedBox.shrink();

    switch (item.widgetType) {
      case 'clock':
        content = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(timeStr, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor, height: 1.0)),
            const SizedBox(height: 4),
            Text(dateStr, style: TextStyle(fontSize: 11, color: subColor)),
          ],
        );
        break;

      case 'weather':
        content = Row(
          children: [
            const Icon(Icons.wb_sunny, color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('32°C', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  Text('Sunny • Lagos', style: TextStyle(fontSize: 10, color: subColor), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        );
        break;

      case 'battery':
        bool isCharging = _batteryState == BatteryState.charging || _batteryState == BatteryState.full;
        content = Row(
          children: [
            Icon(isCharging ? Icons.battery_charging_full : Icons.battery_full, color: isCharging ? Colors.green : Colors.blueAccent, size: 28),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_batteryLevel%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                Text(isCharging ? 'Charging' : 'Discharging', style: TextStyle(fontSize: 10, color: subColor)),
              ],
            ),
          ],
        );
        break;

      case 'storage':
        content = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage, size: 16, color: Colors.blueAccent),
                const SizedBox(width: 6),
                Text('Internal Storage', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: const LinearProgressIndicator(value: 0.65, minHeight: 6, backgroundColor: Colors.grey, color: Colors.blueAccent),
            ),
            const SizedBox(height: 4),
            Text('45 GB free of 128 GB', style: TextStyle(fontSize: 9, color: subColor)),
          ],
        );
        break;

      case 'calendar':
        content = Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(months[now.month - 1].toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                  Text('${now.day}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No events today', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor), overflow: TextOverflow.ellipsis),
                  Text('Tap to open Calendar', style: TextStyle(fontSize: 9, color: subColor)),
                ],
              ),
            ),
          ],
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isMobile = screenWidth < 600;

    final quickSettingsWidth = screenWidth > 300 ? 270.0 : screenWidth * 0.9;
    final notificationWidth = screenWidth > 340 ? 320.0 : screenWidth * 0.94;
    final overlayMaxHeight = math.max(100.0, screenHeight * 0.85);
    
    final safeAreaTop = MediaQuery.of(context).padding.top;
    
    final int cols = (isMobile ? state.portraitGridX : state.landscapeGridX).clamp(1, 20);
    final int rows = (isMobile ? state.portraitGridY : state.landscapeGridY).clamp(1, 20);
    final double availableHeight = math.max(10.0, screenHeight - taskbarHeight - safeAreaTop - 30);
    final double cellWidth = math.max(1.0, screenWidth / cols);
    final double cellHeight = math.max(1.0, availableHeight / rows);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (didPop) return;
          if (_isStartMenuOpen || _isQuickSettingsOpen || _isNotificationCenterOpen || _isWidgetBoardOpen || _isContextMenuOpen) {
            _closeOverlays();
            return;
          }
          if (state.windowStack.isNotEmpty) {
            if (state.windowStack.last == 'explorer') {
               bool wentBack = _explorerKey.currentState?.goBack() ?? false;
               if (wentBack) return; 
            }
            state.closeApp(state.windowStack.last);
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: false,
          body: SizedBox.expand(
            child: GestureDetector(
              onTap: _closeOverlays,
              onSecondaryTapDown: (details) => setState(() {
                _closeOverlays();
                _isContextMenuOpen = true;
                _contextMenuPos = details.globalPosition;
                _contextMenuType = 'desktop';
              }),
              onLongPressStart: (details) => setState(() {
                _closeOverlays();
                _isContextMenuOpen = true;
                _contextMenuPos = details.globalPosition;
                _contextMenuType = 'desktop';
              }),
              onScaleStart: (details) { _maxPointers = details.pointerCount; },
              onScaleUpdate: (details) { if (details.pointerCount > _maxPointers) _maxPointers = details.pointerCount; },
              onScaleEnd: (details) {
                final dx = details.velocity.pixelsPerSecond.dx;
                final dy = details.velocity.pixelsPerSecond.dy;
                if (dx.abs() > 500 || dy.abs() > 500) {
                  if (dx.abs() > dy.abs()) {
                    if (dx > 500 && !_isQuickSettingsOpen && !_isNotificationCenterOpen) {
                      setState(() { _isWidgetBoardOpen = true; _isStartMenuOpen = false; });
                    } else if (dx < -500) {
                      if (_isWidgetBoardOpen) setState(() => _isWidgetBoardOpen = false);
                      else setState(() { _isNotificationCenterOpen = true; _isStartMenuOpen = false; });
                    }
                  } else {
                    if (dy < -500) {
                      _handleGestureAction(_maxPointers >= 2 ? state.gestureTwoFingerUpAction : state.gestureUpAction);
                    } else if (dy > 500) {
                      _handleGestureAction(_maxPointers >= 2 ? state.gestureTwoFingerDownAction : state.gestureDownAction);
                    }
                  }
                }
                _maxPointers = 0;
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onDoubleTap: () async {
                        if (state.doubleTapToSleep) {
                          _closeOverlays();
                          try { await platform.invokeMethod('lockScreen'); } catch (_) {}
                          if (mounted) {
                            Navigator.of(context).pushReplacement(
                              PageRouteBuilder(
                                pageBuilder: (context, animation, secondaryAnimation) => const LockScreen(),
                                transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                                    FadeTransition(opacity: animation, child: child),
                              ),
                            );
                          }
                        }
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        child: SizedBox.expand(
                          key: ValueKey<String>(state.actualWallpaperUrl),
                          child: state.actualWallpaperUrl.startsWith('assets/')
                              ? Image.asset(state.actualWallpaperUrl, fit: BoxFit.cover)
                              : (state.actualWallpaperUrl.startsWith('http')
                                  ? CachedNetworkImage(
                                      imageUrl: state.actualWallpaperUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(color: const Color(0xFF003D73)),
                                    )
                                  : Image.file(File(state.actualWallpaperUrl), fit: BoxFit.cover)),
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    top: safeAreaTop + 8,
                    left: 0,
                    right: 0,
                    height: availableHeight, 
                    child: PageView.builder(
                      controller: _pageController,
                      physics: const BouncingScrollPhysics(),
                      itemCount: state.desktopPages,
                      onPageChanged: (i) => setState(() => _currentDesktopPage = i),
                      itemBuilder: (context, pageIndex) {
                        final pageItems = state.desktopItems.where((i) => i.page == pageIndex).toList();

                        return Builder(
                          builder: (dragContext) {
                            return DragTarget<DesktopItemModel>(
                              onAcceptWithDetails: (details) {
                                final RenderBox box = dragContext.findRenderObject() as RenderBox;
                                final Offset localPos = box.globalToLocal(details.offset);
                                
                                int droppedCol = (localPos.dx / cellWidth).round().clamp(0, cols - details.data.spanX);
                                int droppedRow = (localPos.dy / cellHeight).round().clamp(0, rows - details.data.spanY);
                                
                                state.updateItemPosition(details.data.id, pageIndex, droppedCol, droppedRow);
                              },
                              builder: (context, candidateData, rejectedData) {
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned.fill(child: Container(color: Colors.transparent)),
                                    ...pageItems.map((item) {
                                      final isWidget = item.type == 'widget';
                                      final isNativeWidget = item.type == 'native_widget';
                                      final itemWidth = cellWidth * item.spanX;
                                      final itemHeight = cellHeight * item.spanY;

                                      Widget content = const SizedBox.shrink();
                                      
                                      if (isNativeWidget && item.appWidgetId != null) {
                                         content = SizedBox(
                                            width: itemWidth,
                                            height: itemHeight,
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(10),
                                              child: PlatformViewLink(
                                                viewType: 'NativeWidget',
                                                surfaceFactory: (BuildContext context, PlatformViewController controller) {
                                                  return AndroidViewSurface(
                                                    controller: controller as AndroidViewController,
                                                    gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
                                                    hitTestBehavior: PlatformViewHitTestBehavior.opaque,
                                                  );
                                                },
                                                onCreatePlatformView: (PlatformViewCreationParams params) {
                                                  return PlatformViewsService.initExpensiveAndroidView(
                                                    id: params.id,
                                                    viewType: 'NativeWidget',
                                                    layoutDirection: TextDirection.ltr,
                                                    creationParams: {'appWidgetId': item.appWidgetId},
                                                    creationParamsCodec: const StandardMessageCodec(),
                                                    onFocus: () {
                                                      params.onFocusChanged(true);
                                                    },
                                                  )
                                                    ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
                                                    ..create();
                                                },
                                              ),
                                            ),
                                         );
                                      } else if (isWidget) {
                                         content = _buildDesktopWidgetCard(item, state, state.isDarkMode);
                                      } else {
                                         content = Transform.scale(
                                              scale: _getIconScale(state),
                                              child: DesktopIcon(
                                                itemData: item,
                                                customIcon: _getDesktopIconWidget(item, state),
                                                label: item.label,
                                                onTap: () {
                                                  _closeOverlays();
                                                  if (item.type == 'system') {
                                                    if (item.id == 'recycle_bin') {
                                                      final rb = Directory('/storage/emulated/0/.RecycleBin');
                                                      if (!rb.existsSync()) { try { rb.createSync(); } catch (_) {} }
                                                      state.currentExplorerPath = rb.path;
                                                      state.openApp('explorer');
                                                    } else if (item.id == 'my_files') {
                                                      state.currentExplorerPath = '/storage/emulated/0';
                                                      state.openApp('explorer');
                                                    } else {
                                                      state.openApp(item.id);
                                                    }
                                                  } else if (item.type == 'app' && item.package != null) {
                                                    state.launchNativeApp(item.package!);
                                                  }
                                                },
                                                onSecondaryTap: () {
                                                  setState(() {
                                                    _closeOverlays();
                                                    _isContextMenuOpen = true;
                                                    _contextMenuPos = Offset((item.col * cellWidth) + 40, (item.row * cellHeight) + safeAreaTop + 40);
                                                    _contextMenuType = 'folder';
                                                    _contextTargetName = item.label;
                                                    _contextOpenAction = () {
                                                      if (item.type == 'app' && item.package != null) state.launchNativeApp(item.package!);
                                                      else if (item.type == 'system') state.openApp(item.id);
                                                    };
                                                  });
                                                },
                                                onLongPress: () {
                                                  setState(() {
                                                    _closeOverlays();
                                                    _isContextMenuOpen = true;
                                                    _contextMenuPos = Offset((item.col * cellWidth) + 40, (item.row * cellHeight) + safeAreaTop + 40);
                                                    _contextMenuType = 'folder';
                                                    _contextTargetName = item.label;
                                                    _contextOpenAction = () {
                                                      if (item.type == 'app' && item.package != null) state.launchNativeApp(item.package!);
                                                      else if (item.type == 'system') state.openApp(item.id);
                                                    };
                                                  });
                                                },
                                              ),
                                            );
                                      }

                                      Widget positionedChild = content;

                                      if (isWidget || isNativeWidget) {
                                         // FIX: The core Resize Overlay engine that wraps the widget when 'Resize' is tapped
                                         final isResizing = _resizingWidgetId == item.id;
                                         if (isResizing) {
                                            positionedChild = Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                AbsorbPointer(
                                                  absorbing: true,
                                                  child: SizedBox(width: itemWidth, height: itemHeight, child: content),
                                                ),
                                                Positioned.fill(
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.blueAccent.withOpacity(0.15),
                                                      border: Border.all(color: Colors.blueAccent, width: 2),
                                                      borderRadius: BorderRadius.circular(10),
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  right: -12,
                                                  bottom: -12,
                                                  child: GestureDetector(
                                                    onPanStart: (_) {
                                                      _resizeAccumulatorX = 0;
                                                      _resizeAccumulatorY = 0;
                                                    },
                                                    onPanUpdate: (dragDetails) {
                                                      _resizeAccumulatorX += dragDetails.delta.dx;
                                                      _resizeAccumulatorY += dragDetails.delta.dy;
                                                      
                                                      bool changed = false;
                                                      int newSpanX = item.spanX;
                                                      int newSpanY = item.spanY;

                                                      if (_resizeAccumulatorX > cellWidth * 0.5) {
                                                         newSpanX++;
                                                         _resizeAccumulatorX = 0;
                                                         changed = true;
                                                      } else if (_resizeAccumulatorX < -cellWidth * 0.5) {
                                                         newSpanX--;
                                                         _resizeAccumulatorX = 0;
                                                         changed = true;
                                                      }

                                                      if (_resizeAccumulatorY > cellHeight * 0.5) {
                                                         newSpanY++;
                                                         _resizeAccumulatorY = 0;
                                                         changed = true;
                                                      } else if (_resizeAccumulatorY < -cellHeight * 0.5) {
                                                         newSpanY--;
                                                         _resizeAccumulatorY = 0;
                                                         changed = true;
                                                      }
                                                      
                                                      if (changed) {
                                                         newSpanX = newSpanX.clamp(1, cols - item.col);
                                                         newSpanY = newSpanY.clamp(1, rows - item.row);
                                                         if (newSpanX != item.spanX || newSpanY != item.spanY) {
                                                            state.resizeDesktopItem(item.id, newSpanX, newSpanY, cellWidth, cellHeight);
                                                         }
                                                      }
                                                    },
                                                    child: Container(
                                                      width: 32,
                                                      height: 32,
                                                      decoration: const BoxDecoration(
                                                        color: Colors.blueAccent,
                                                        shape: BoxShape.circle,
                                                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                                      ),
                                                      child: const Icon(Icons.open_in_full, size: 16, color: Colors.white),
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  top: -12,
                                                  right: -12,
                                                  child: GestureDetector(
                                                    onTap: () {
                                                      setState(() { _resizingWidgetId = null; });
                                                    },
                                                    child: Container(
                                                      width: 28,
                                                      height: 28,
                                                      decoration: const BoxDecoration(
                                                        color: Colors.green,
                                                        shape: BoxShape.circle,
                                                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                                      ),
                                                      child: const Icon(Icons.check, size: 16, color: Colors.white),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                         } else if (!state.dragIcons) {
                                            positionedChild = GestureDetector(
                                              onSecondaryTapDown: (details) => setState(() {
                                                _closeOverlays();
                                                _isContextMenuOpen = true;
                                                _contextMenuPos = details.globalPosition;
                                                _contextMenuType = 'folder';
                                                _contextTargetName = item.label;
                                              }),
                                              onLongPressStart: (details) => setState(() {
                                                _closeOverlays();
                                                _isContextMenuOpen = true;
                                                _contextMenuPos = details.globalPosition;
                                                _contextMenuType = 'folder';
                                                _contextTargetName = item.label;
                                              }),
                                              child: content,
                                            );
                                         } else {
                                            positionedChild = GestureDetector(
                                              onSecondaryTapDown: (details) => setState(() {
                                                _closeOverlays();
                                                _isContextMenuOpen = true;
                                                _contextMenuPos = details.globalPosition;
                                                _contextMenuType = 'folder';
                                                _contextTargetName = item.label;
                                              }),
                                              onLongPressStart: (details) => setState(() {
                                                _closeOverlays();
                                                _isContextMenuOpen = true;
                                                _contextMenuPos = details.globalPosition;
                                                _contextMenuType = 'folder';
                                                _contextTargetName = item.label;
                                              }),
                                              child: Draggable<DesktopItemModel>(
                                                data: item,
                                                feedback: Material(
                                                  color: Colors.transparent,
                                                  child: Opacity(
                                                    opacity: 0.8,
                                                    child: isNativeWidget
                                                        ? Container(
                                                            width: itemWidth,
                                                            height: itemHeight,
                                                            decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(10)),
                                                            child: const Center(child: Icon(Icons.widgets, color: Colors.white)),
                                                          )
                                                        : SizedBox(width: itemWidth, height: itemHeight, child: content),
                                                  ),
                                                ),
                                                childWhenDragging: Opacity(opacity: 0.3, child: content),
                                                child: content,
                                              ),
                                            );
                                         }
                                      }

                                      return Positioned(
                                        left: item.col * cellWidth,
                                        top: item.row * cellHeight,
                                        width: itemWidth,
                                        height: itemHeight,
                                        child: positionedChild,
                                      );
                                    }).toList(),
                                  ]
                                );
                              },
                            );
                          }
                        );
                      },
                    ),
                  ),

                  if (state.desktopPages > 1)
                    Positioned(
                      bottom: taskbarHeight + 4,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(state.desktopPages, (index) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 6,
                            width: _currentDesktopPage == index ? 16 : 6,
                            decoration: BoxDecoration(
                              color: _currentDesktopPage == index ? Colors.white : Colors.white54,
                              borderRadius: BorderRadius.circular(3),
                              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 2)],
                            ),
                          );
                        }),
                      ),
                    ),

                  ...state.windowStack.where((id) => !id.contains('.')).map((windowId) {
                    final isMinimized = state.minimizedApps.contains(windowId);
                    final isMaximized = state.maximizedApps.contains(windowId) || (isMobile && windowId != 'calculator');

                    final size = (isMobile && windowId == 'calculator') 
                        ? Size(screenWidth * 0.90, 480) 
                        : (isMobile 
                            ? Size(screenWidth, math.max(0, screenHeight - taskbarHeight))
                            : _getResponsiveWindowSize(context, windowId == 'explorer' ? 580 : (windowId == 'calculator' ? 320 : 600), windowId == 'calculator' ? 480 : 420));
                            
                    final pos = (isMobile && windowId == 'calculator')
                        ? Offset((screenWidth - (screenWidth * 0.90)) / 2, math.max(0, screenHeight - 480 - taskbarHeight - 16))
                        : (isMobile 
                            ? Offset.zero
                            : (windowId == 'explorer' ? state.fileExplorerPos : (windowId == 'calculator' ? state.calculatorPos : (windowId == 'browser' ? state.browserPos : state.settingsPos))));

                    Widget content = const SizedBox.shrink();
                    String title = "";
                    IconData icon = Icons.apps;
                    
                    if (windowId == 'browser') { content = const BrowserApp(); title = 'Edge'; icon = Icons.language; }
                    if (windowId == 'explorer') { content = FileExplorerApp(key: _explorerKey); title = 'This PC'; icon = Icons.folder; }
                    if (windowId == 'calculator') { content = const CalculatorApp(); title = 'Calculator'; icon = Icons.calculate; }
                    if (windowId == 'settings') { content = const SettingsApp(); title = 'Settings'; icon = Icons.settings; }

                    return AppWindow(
                      title: title,
                      icon: icon,
                      position: pos,
                      size: size,
                      isMinimized: isMinimized,
                      isMaximized: isMaximized,
                      useSafeArea: windowId != 'settings' && windowId != 'browser',
                      onClose: () => state.closeApp(windowId),
                      onMinimize: () => state.minimizeApp(windowId),
                      onMaximize: () => state.toggleMaximizeApp(windowId),
                      onDrag: (delta) { if (!isMobile) state.updateWindowPos(windowId, delta); },
                      onFocus: () { _closeOverlays(); state.focusWindow(windowId); },
                      content: content,
                    );
                  }).toList(),

                  if (_isStartMenuOpen)
                    Positioned(
                      bottom: taskbarHeight,
                      left: 6,
                      child: SizedBox(
                        width: 290,
                        height: math.max(0, screenHeight * 0.75),
                        child: StartMenu(
                          onOverlaysClosed: _closeOverlays,
                          onPowerTapped: () {
                            Navigator.of(context).pushReplacement(
                              PageRouteBuilder(
                                pageBuilder: (context, animation, secondaryAnimation) => const LockScreen(),
                                transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                                    FadeTransition(opacity: animation, child: child),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  if (_isQuickSettingsOpen)
                    Positioned(
                      bottom: taskbarHeight + 8,
                      right: 8,
                      width: quickSettingsWidth,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: math.max(0, overlayMaxHeight)),
                        child: QuickSettings(
                          settingsState: _quickSettings,
                          onToggle: _handleHardwareToggle,
                          brightness: _brightness,
                          onBrightnessChanged: _updateBrightness,
                          volume: _volume,
                          onVolumeChanged: _updateVolume,
                          batteryLevel: _batteryLevel,
                          batteryState: _batteryState,
                          onOpenSettings: () {
                            state.openApp('settings');
                            _toggleOverlay('quick');
                          },
                          visibleTiles: state.visibleQuickSettings,
                          hiddenTiles: state.hiddenQuickSettings,
                          onToggleVisibility: state.toggleQuickSettingVisibility,
                        ),
                      ),
                    ),

                  if (_isNotificationCenterOpen)
                    Positioned(
                      bottom: taskbarHeight + 8,
                      right: 8,
                      width: notificationWidth,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: math.max(0, screenHeight * 0.88)),
                        child: NotificationCenterPanel(
                          notifications: _realNotifications,
                          installedApps: state.installedApps,
                          onClosePanel: _closeOverlays,
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
                          },
                        ),
                      ),
                    ),

                  Positioned(
                    bottom: 0, left: 0, right: 0, height: taskbarHeight,
                    child: Win11Taskbar(
                      isStartMenuOpen: _isStartMenuOpen,
                      onStartToggled: () => _toggleOverlay('start'),
                      onQuickSettingsToggled: () => _toggleOverlay('quick'),
                      onNotificationCenterToggled: () => _toggleOverlay('notification'),
                      onOverlaysClosed: _closeOverlays,
                      batteryLevel: _batteryLevel,
                      batteryState: _batteryState,
                      unreadNotifications: _unreadNotifications,
                    ),
                  ),

                  _buildContextMenuOverlay(state),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}