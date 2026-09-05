import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:battery_plus/battery_plus.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:torch_light/torch_light.dart';

import '../../launcher_state.dart';
import '../../lock_screen.dart';
import '../../taskbar.dart';
import '../../start_menu.dart';
import '../../quick_settings.dart';
import '../../notification_center.dart';
import '../explorer/file_explorer_app.dart';
import '../../services/native_bridge.dart';

import 'desktop_workspace.dart';
import 'window_manager.dart';
import 'desktop_context_menu.dart';

class DesktopScreen extends StatefulWidget {
  const DesktopScreen({Key? key}) : super(key: key);
  @override
  State<DesktopScreen> createState() => _DesktopScreenState();
}

class _DesktopScreenState extends State<DesktopScreen> with WidgetsBindingObserver {
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
  String _contextTargetName = '';
  VoidCallback? _contextOpenAction;

  String? _resizingWidgetId;

  final ValueNotifier<double> _volume = ValueNotifier<double>(0.5);
  final ValueNotifier<double> _brightness = ValueNotifier<double>(0.5);
  final ValueNotifier<int> _batteryLevel = ValueNotifier<int>(100);
  final ValueNotifier<BatteryState> _batteryState = ValueNotifier<BatteryState>(BatteryState.discharging); 
  
  final ValueNotifier<List<Map<String, dynamic>>> _realNotifications = ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<int> _unreadNotifications = ValueNotifier<int>(0);

  final ValueNotifier<Map<String, bool>> _quickSettings = ValueNotifier<Map<String, bool>>({
    'Airplane mode': false, 'Battery saver': false, 'Wi-Fi': false, 'Bluetooth': false, 'Flash': false, 'Data': false, 'Rotate': false, 'Location': false, 'Hotspot': false, 'VPN': false, 'Brightness': false, 'Accessibility': false,
    'Play': false, 'Ring': true, 'ChatGPT': false, 'Storage': false, 'Dark Theme': false, 'Calculator': false, 'Song Search': false, 'DND': false, 'Screen Cast': false, 'Eye Care': false, 'Scan QR Code': false, 'Users & Account': false, 'Kids Mode': false,
    'Adaptive Brightness': false
  });
  
  final double taskbarHeight = 48.0;
  int _maxPointers = 0;

  StreamSubscription? _batterySub;
  StreamSubscription? _brightnessSub;
  StreamSubscription? _notifSub;
  StreamSubscription? _hwSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    if (!kIsWeb) {
      _initHardware(); 
      _initNotifications();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb) {
      try { VolumeController.instance.removeListener(); } catch (_) {}
    }
    
    _batterySub?.cancel();
    _brightnessSub?.cancel();
    _notifSub?.cancel();
    _hwSub?.cancel();

    _pageController.dispose();
    _volume.dispose();
    _brightness.dispose();
    _batteryLevel.dispose();
    _batteryState.dispose();
    _realNotifications.dispose();
    _unreadNotifications.dispose();
    _quickSettings.dispose();
    super.dispose();
  }

  void _fetchActualHardwareState() async {
    final initialState = await NativeBridge.instance.getHardwareState();
    if (mounted) {
      final updatedSettings = Map<String, bool>.from(_quickSettings.value);
      initialState.forEach((key, value) {
        if (value is bool) updatedSettings[key] = value;
      });
      if (initialState.containsKey('sys_brightness') && initialState['sys_brightness'] is double) {
         _brightness.value = initialState['sys_brightness'];
      }
      if (initialState.containsKey('Dark Theme')) {
        bool systemDark = initialState['Dark Theme'];
        final ls = context.read<LauncherState>();
        if (ls.isDarkMode != systemDark) ls.setDarkMode(systemDark);
      }
      _quickSettings.value = updatedSettings;
    }
  }

  void _refreshNotifications() async {
    try {
      final active = await NativeBridge.instance.getActiveNotifications();
      if (mounted) _realNotifications.value = active;
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<LauncherState>().refreshApps();
      _fetchActualHardwareState(); 
      _refreshNotifications();
    }
  }

  void _initHardware() async {
    _fetchActualHardwareState();

    _hwSub = NativeBridge.instance.hardwareStateStream.listen((event) {
      if (!mounted) return;
      final data = Map<String, dynamic>.from(event);
      final updatedSettings = Map<String, bool>.from(_quickSettings.value);
      
      data.forEach((key, value) {
        if (value is bool) updatedSettings[key] = value;
      });
      
      if (data.containsKey('sys_brightness') && data['sys_brightness'] is double) {
         _brightness.value = data['sys_brightness'];
      }
      if (data.containsKey('Dark Theme')) {
        bool systemDark = data['Dark Theme'];
        final ls = context.read<LauncherState>();
        if (ls.isDarkMode != systemDark) ls.setDarkMode(systemDark);
      }
      
      _quickSettings.value = updatedSettings;
    });

    try {
      _batteryLevel.value = await Battery().batteryLevel;
      _batteryState.value = await Battery().batteryState;
      _batterySub = Battery().onBatteryStateChanged.listen((state) async {
        if (!mounted) return;
        final level = await Battery().batteryLevel;
        _batteryState.value = state;
        _batteryLevel.value = level;
      });
    } catch (_) {}
    
    try {
      double v = await VolumeController.instance.getVolume();
      if (v.isNaN || v.isInfinite) v = 0.5;
      if (v > 1.0) v = v / 15.0; 
      _volume.value = v.clamp(0.0, 1.0);
      VolumeController.instance.addListener((vol) {
        if (mounted) {
           if (vol.isNaN || vol.isInfinite) vol = 0.5;
           _volume.value = (vol > 1.0 ? vol / 15.0 : vol).clamp(0.0, 1.0);
        }
      });
    } catch (_) {}
    
    try {
      double b = await ScreenBrightness().current;
      if (b.isNaN || b.isInfinite) b = 0.5;
      _brightness.value = b.clamp(0.0, 1.0);
      _brightnessSub = ScreenBrightness().onCurrentBrightnessChanged.listen((bValue) {
        if (mounted) {
           if (bValue.isNaN || bValue.isInfinite) bValue = 0.5;
           _brightness.value = bValue.clamp(0.0, 1.0);
        }
      });
    } catch (_) {}
  }

  void _initNotifications() async {
    try {
      final perms = await NativeBridge.instance.getPermissionStatuses();
      if (perms['notification'] != true) {
        NativeBridge.instance.openSettings('notification_access');
      }

      _refreshNotifications();

      _notifSub = NativeBridge.instance.notificationStream.listen((event) {
        if (!mounted) return;
        final data = Map<String, dynamic>.from(event);
        final currentNotifs = List<Map<String, dynamic>>.from(_realNotifications.value);
        if (data['removed'] == true) {
          currentNotifs.removeWhere((n) => n['key'] == data['key']);
        } else {
          currentNotifs.removeWhere((n) => n['key'] == data['key']);
          currentNotifs.insert(0, data);
          if (!_isNotificationCenterOpen) _unreadNotifications.value++;
        }
        _realNotifications.value = currentNotifs;
      });
    } catch (_) {}
  }

  void _updateBrightness(double val) {
    if (val.isNaN || val.isInfinite) val = 0.5;
    _brightness.value = val.clamp(0.0, 1.0);
    if (!kIsWeb) NativeBridge.instance.setSystemBrightness(_brightness.value);
  }

  void _updateVolume(double val) {
    if (val.isNaN || val.isInfinite) val = 0.5;
    _volume.value = val.clamp(0.0, 1.0);
    if (!kIsWeb) VolumeController.instance.setVolume(_volume.value);
  }

  void _handleHardwareToggle(String key) async {
    final state = context.read<LauncherState>();
    bool currentVal = _quickSettings.value[key] ?? false;
    bool newVal = !currentVal;

    if (key == 'Calculator') { state.openApp('calculator'); _toggleOverlay('quick'); return; }
    if (key == 'Storage') { NativeBridge.instance.toggleHardware('Storage', true); _toggleOverlay('quick'); return; }
    if (key == 'ChatGPT') {
      _toggleOverlay('quick');
      final success = await NativeBridge.instance.launchApp('com.openai.chatgpt');
      if (!success) _showToast('ChatGPT app not installed');
      return;
    }
    if (key == 'Scan QR Code') {
      _toggleOverlay('quick');
      NativeBridge.instance.toggleHardware('Scan QR Code', true);
      return;
    }
    if (key == 'Play') {
      _toggleOverlay('quick');
      NativeBridge.instance.toggleHardware('Play', true);
      return;
    }
    if (key == 'Song Search') {
      _toggleOverlay('quick');
      NativeBridge.instance.toggleHardware('Song Search', true);
      return;
    }
    if (key == 'Kids Mode') {
      _toggleOverlay('quick');
      NativeBridge.instance.toggleHardware('Kids Mode', true);
      return;
    }

    if (['Rotate', 'Brightness', 'Ring', 'DND', 'Flash', 'Dark Theme'].contains(key)) {
      if (key == 'Flash') {
        try {
          if (currentVal) await TorchLight.disableTorch();
          else await TorchLight.enableTorch();
        } catch (e) {
          _showToast('Flashlight not available');
          return;
        }
      } else if (key == 'Dark Theme') {
        state.setDarkMode(newVal);
      }
      
      _quickSettings.value = Map.from(_quickSettings.value)..[key] = newVal;
      NativeBridge.instance.toggleHardware(key, newVal);
      return;
    }

    _toggleOverlay('quick'); 
    NativeBridge.instance.toggleHardware(key, newVal);
  }

  void _closeOverlays() {
    setState(() {
      _isStartMenuOpen = false;
      _isContextMenuOpen = false;
      _isWidgetBoardOpen = false;
      _isQuickSettingsOpen = false;
      _isNotificationCenterOpen = false;
    });
  }

  void _toggleOverlay(String overlay) {
    setState(() {
      _isStartMenuOpen = overlay == 'start' ? !_isStartMenuOpen : false;
      _isQuickSettingsOpen = overlay == 'quick' ? !_isQuickSettingsOpen : false;
      _isWidgetBoardOpen = false;
      _isContextMenuOpen = false;

      if (overlay == 'notification') {
        _isNotificationCenterOpen = !_isNotificationCenterOpen;
        if (_isNotificationCenterOpen) {
          _unreadNotifications.value = 0;
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
        await NativeBridge.instance.expandNotificationPanel();
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

  Widget _buildWallpaperFallback(Color accentColor, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withOpacity(0.85),
            isDark ? const Color(0xFF141414) : const Color(0xFFE0E5EC),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final safeAreaTop = MediaQuery.of(context).padding.top;
    final accent = state.currentAccentColor;
    final isDark = state.isDarkMode;

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
                          NativeBridge.instance.lockScreen();
                          if (mounted) {
                            Navigator.of(context).pushReplacement(
                              PageRouteBuilder(
                                pageBuilder: (context, animation, secondaryAnimation) => const LockScreen(),
                                transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
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
                              ? Image.asset(
                                  state.actualWallpaperUrl,
                                  fit: BoxFit.cover,
                                  // Fallback: renders dynamic Fluent gradient if asset is missing
                                  errorBuilder: (context, error, stackTrace) => _buildWallpaperFallback(accent, isDark),
                                )
                              : (state.actualWallpaperUrl.startsWith('http')
                                  ? CachedNetworkImage(
                                      imageUrl: state.actualWallpaperUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => _buildWallpaperFallback(accent, isDark),
                                      errorWidget: (context, url, error) => _buildWallpaperFallback(accent, isDark),
                                    )
                                  : Image.file(
                                      File(state.actualWallpaperUrl),
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => _buildWallpaperFallback(accent, isDark),
                                    )),
                        ),
                      ),
                    ),
                  ),

                  DesktopWorkspace(
                    taskbarHeight: taskbarHeight,
                    safeAreaTop: safeAreaTop,
                    currentDesktopPage: _currentDesktopPage,
                    pageController: _pageController,
                    onPageChanged: (i) => setState(() => _currentDesktopPage = i),
                    resizingWidgetId: _resizingWidgetId,
                    onExitResizeMode: () => setState(() => _resizingWidgetId = null),
                    onCloseOverlays: _closeOverlays,
                    onContextMenu: (pos, type, targetName, openAction) {
                      setState(() {
                        _closeOverlays();
                        _isContextMenuOpen = true;
                        _contextMenuPos = pos;
                        _contextMenuType = type;
                        _contextTargetName = targetName;
                        _contextOpenAction = openAction;
                      });
                    },
                  ),

                  WindowManager(
                    taskbarHeight: taskbarHeight,
                    explorerKey: _explorerKey,
                    onCloseOverlays: _closeOverlays,
                  ),

                  if (_isStartMenuOpen)
                    Positioned(
                      bottom: taskbarHeight + 2, left: 6,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 290, maxHeight: MediaQuery.of(context).size.height * 0.85),
                        child: StartMenu(
                          onOverlaysClosed: _closeOverlays,
                          onPowerTapped: () {
                            Navigator.of(context).pushReplacement(
                              PageRouteBuilder(pageBuilder: (context, animation, secondaryAnimation) => const LockScreen(), transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child)),
                            );
                          },
                        ),
                      ),
                    ),

                  if (_isQuickSettingsOpen)
                    Positioned(
                      bottom: taskbarHeight + 2, right: 8, width: 270.0,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_quickSettings, _brightness, _volume, _batteryLevel, _batteryState]),
                        builder: (context, child) => QuickSettings(
                          settingsState: _quickSettings.value,
                          onToggle: _handleHardwareToggle,
                          brightness: _brightness.value,
                          onBrightnessChanged: _updateBrightness,
                          volume: _volume.value,
                          onVolumeChanged: _updateVolume,
                          batteryLevel: _batteryLevel.value,
                          batteryState: _batteryState.value, 
                          onOpenSettings: () { state.openApp('settings'); _toggleOverlay('quick'); },
                          visibleTiles: state.visibleQuickSettings,
                          hiddenTiles: state.hiddenQuickSettings,
                          onToggleVisibility: state.toggleQuickSettingVisibility,
                        ),
                      ),
                    ),

                  if (_isNotificationCenterOpen)
                    Positioned(
                      bottom: taskbarHeight + 2, right: 8,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 320.0,
                          maxHeight: MediaQuery.of(context).size.height - taskbarHeight - safeAreaTop - 20, 
                        ),
                        child: AnimatedBuilder(
                          animation: _realNotifications,
                          builder: (context, child) => NotificationCenterPanel(
                            notifications: _realNotifications.value,
                            installedApps: state.installedApps,
                            onClosePanel: _closeOverlays,
                            onClearAll: () { NativeBridge.instance.clearAllNotifications(); _realNotifications.value = []; },
                            onRemoveNotification: (event) {
                              NativeBridge.instance.dismissNotification(event['key']);
                              final updated = List<Map<String, dynamic>>.from(_realNotifications.value);
                              updated.removeWhere((n) => n['key'] == event['key']);
                              _realNotifications.value = updated;
                            },
                            onLaunchApp: (pkg) async {
                              _toggleOverlay('notification');
                              final success = await NativeBridge.instance.launchApp(pkg);
                              if (!success) _showToast('App not found');
                            },
                          ),
                        ),
                      ),
                    ),

                  Positioned(
                    bottom: 0, left: 0, right: 0, height: taskbarHeight,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_batteryLevel, _batteryState, _unreadNotifications]),
                      builder: (context, child) => Win11Taskbar(
                        isStartMenuOpen: _isStartMenuOpen,
                        onStartToggled: () => _toggleOverlay('start'),
                        onQuickSettingsToggled: () => _toggleOverlay('quick'),
                        onNotificationCenterToggled: () => _toggleOverlay('notification'),
                        onOverlaysClosed: _closeOverlays,
                        batteryLevel: _batteryLevel.value,
                        batteryState: _batteryState.value, 
                        unreadNotifications: _unreadNotifications.value,
                      ),
                    ),
                  ),

                  DesktopContextMenu(
                    isOpen: _isContextMenuOpen,
                    position: _contextMenuPos,
                    menuType: _contextMenuType,
                    targetName: _contextTargetName,
                    openAction: _contextOpenAction,
                    onClose: () => setState(() => _isContextMenuOpen = false),
                    currentDesktopPage: _currentDesktopPage,
                    pageController: _pageController,
                    onEnterResizeMode: (id) => setState(() => _resizingWidgetId = id),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}