import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // REQUIRED FOR NATIVE CHANNELS
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:notification_listener_service/notification_event.dart';
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
  bool _isNotificationCenterOpen = false; bool _isContextMenuOpen = false; Offset _contextMenuPos = Offset.zero;

  double _volume = 0.5; double _brightness = 0.5; int _batteryLevel = 100; BatteryState _batteryState = BatteryState.discharging;
  List<ServiceNotificationEvent> _realNotifications = []; int _unreadNotifications = 0; 
  final Map<String, bool> _quickSettings = { 'Airplane mode': false, 'Battery saver': false, 'Wi-Fi': false, 'Bluetooth': false, 'Flash': false, 'Data': false, 'Rotate': false, 'Location': false, 'Hotspot': false, 'VPN': false, 'Brightness': false, 'Accessibility': false };
  final double taskbarHeight = 48.0; 

  int _maxPointers = 0;

  // NATIVE COMMUNICATION CHANNEL
  static const platform = MethodChannel('win_launcher/native');

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
      bool isGranted = await NotificationListenerService.isPermissionGranted();
      if (!isGranted) await NotificationListenerService.requestPermission();
      NotificationListenerService.notificationsStream.listen((event) {
        if (mounted && event.packageName != null) {
          setState(() {
            if (_realNotifications.isNotEmpty) { final last = _realNotifications.first; if (last.title == event.title && last.content == event.content) return; }
            _realNotifications.insert(0, event); if (_realNotifications.length > 20) _realNotifications.removeLast(); 
            if (!_isNotificationCenterOpen) _unreadNotifications++;
          });
        }
      });
    } catch (_) {}
  }

  void _updateBrightness(double val) { setState(() => _brightness = val); if (!kIsWeb) ScreenBrightness().setScreenBrightness(val); }
  void _updateVolume(double val) { setState(() => _volume = val); if (!kIsWeb) VolumeController.instance.setVolume(val); }
  void _handleHardwareToggle(String key) async {
    if (key == 'Flash') {
      bool isActive = _quickSettings['Flash'] ?? false;
      try { if (isActive) { await TorchLight.disableTorch(); setState(() => _quickSettings['Flash'] = false); } else { await TorchLight.enableTorch(); setState(() => _quickSettings['Flash'] = true); } } catch (e) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Flashlight not available.'))); }
      return;
    }
    setState(() { _quickSettings[key] = !(_quickSettings[key] ?? false); });
  }

  Size _getResponsiveWindowSize(BuildContext context, double targetWidth, double targetHeight) {
    final screenSize = MediaQuery.of(context).size; final isMobile = screenSize.width < 600;
    if (isMobile) return Size(screenSize.width * 0.94, screenSize.height * 0.84);
    final maxWidth = screenSize.width * 0.90; final maxHeight = screenSize.height * 0.80; 
    return Size(targetWidth > maxWidth ? maxWidth : targetWidth, targetHeight > maxHeight ? maxHeight : targetHeight);
  }

  int _getGridCrossAxisCount(LauncherState state, bool isMobile) {
    return isMobile ? state.portraitGridX : state.landscapeGridX;
  }

  double _getIconScale(LauncherState state) {
    if (state.iconSize == 'Small') return 0.70;
    if (state.iconSize == 'Large') return 1.10;
    return 0.85; 
  }

  void _closeOverlays() { setState(() { _isStartMenuOpen = false; _isContextMenuOpen = false; _isWidgetBoardOpen = false; _isQuickSettingsOpen = false; _isNotificationCenterOpen = false; }); }
  
  void _toggleOverlay(String overlay) {
    setState(() {
      _isStartMenuOpen = overlay == 'start' ? !_isStartMenuOpen : false; _isQuickSettingsOpen = overlay == 'quick' ? !_isQuickSettingsOpen : false; _isWidgetBoardOpen = false; _isContextMenuOpen = false;
      if (overlay == 'notification') { _isNotificationCenterOpen = !_isNotificationCenterOpen; if (_isNotificationCenterOpen) _unreadNotifications = 0; } else { _isNotificationCenterOpen = false; }
    });
  }

  void _handleGestureAction(String action) async {
    if (action == 'None') return;
    
    // NEW: Map both 'Start Menu' AND 'Apps Menu' to open the app drawer
    if (action == 'Start Menu' || action == 'Apps Menu') _toggleOverlay('start');
    if (action == 'Notification Center') _toggleOverlay('notification');
    if (action == 'Quick Settings') _toggleOverlay('quick');
    if (action == 'Widget Board') setState(() { _closeOverlays(); _isWidgetBoardOpen = true; });
    
    // TRIGGERS THE NATIVE ANDROID NOTIFICATION SHADE
    if (action == 'Device Notification Bar') {
      try {
        await platform.invokeMethod('expandNotificationPanel');
      } catch (e) {
        debugPrint("Failed to expand native panel: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height; 
    final isMobile = screenWidth < 600;
    final overlayWidth = screenWidth > 340 ? 320.0 : screenWidth * 0.9;
    
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
          onScaleStart: (details) {
            _maxPointers = details.pointerCount;
          },
          onScaleUpdate: (details) {
            if (details.pointerCount > _maxPointers) {
              _maxPointers = details.pointerCount;
            }
          },
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
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onSecondaryTapDown: (details) => setState(() { _closeOverlays(); _isContextMenuOpen = true; _contextMenuPos = details.localPosition; }), 
                  onLongPressStart: (details) => setState(() { _closeOverlays(); _isContextMenuOpen = true; _contextMenuPos = details.localPosition; }),
                  onDoubleTap: () async {
                    if (state.doubleTapToSleep) {
                      _closeOverlays();
                      try {
                        // Triggers the physical screen lock via Kotlin!
                        await platform.invokeMethod('lockScreen');
                      } catch (_) {}
                      
                      // Also route to our visual lock screen inside the app
                      if (mounted) {
                        Navigator.of(context).pushReplacement(PageRouteBuilder(pageBuilder: (context, animation, secondaryAnimation) => const LockScreen(), transitionsBuilder: (context, animation, secondaryAnimation, child) { return FadeTransition(opacity: animation, child: child); }));
                      }
                    }
                  },
                  child: CachedNetworkImage(
                    imageUrl: state.actualWallpaperUrl, fit: BoxFit.cover,
                    placeholder: (context, url) => Container(color: const Color(0xFF191919)),
                    errorWidget: (_, __, ___) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.blue.shade900, const Color(0xFF191919)]))),
                  ),
                ),
              ),

              SafeArea(
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
                            // Adjusted aspect ratio slightly so 2 lines of text fit comfortably
                            childAspectRatio: 0.80, 
                            mainAxisSpacing: 16, crossAxisSpacing: 8,
                            children: [
                              Transform.scale(scale: _getIconScale(state), child: DesktopIcon(icon: Icons.delete_outline, label: 'Recycle Bin', iconColor: Colors.white70, onTap: () {})),
                              
                              // FIXED: Now uses the local image asset instead of the deleted vector class
                              Transform.scale(
                                scale: _getIconScale(state), 
                                child: DesktopIcon(
                                  customIcon: Image.asset(
                                    'assets/icons/folder.png', 
                                    width: 36, 
                                    height: 36,
                                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.folder, color: Colors.amber, size: 36),
                                  ),
                                  label: 'My Files', 
                                  onTap: () { _closeOverlays(); state.openApp('explorer'); }
                                )
                              ),
                              
                              Transform.scale(scale: _getIconScale(state), child: DesktopIcon(icon: Icons.calculate, label: 'Calculator', iconColor: Colors.grey, onTap: () { _closeOverlays(); state.openApp('calculator'); })),
                              Transform.scale(scale: _getIconScale(state), child: DesktopIcon(icon: Icons.language, label: 'Edge', iconColor: Colors.blue, onTap: () { _closeOverlays(); state.openApp('browser'); })),
                              Transform.scale(scale: _getIconScale(state), child: DesktopIcon(icon: Icons.settings, label: 'Settings', iconColor: Colors.blueGrey, onTap: () { _closeOverlays(); state.openApp('settings'); })),
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
                    
                    if (_isQuickSettingsOpen) Positioned(bottom: taskbarHeight + 8, right: 8, width: overlayWidth, child: QuickSettings(settingsState: _quickSettings, onToggle: _handleHardwareToggle, brightness: _brightness, onBrightnessChanged: _updateBrightness, volume: _volume, onVolumeChanged: _updateVolume, batteryLevel: _batteryLevel, onOpenSettings: () { state.openApp('settings'); _toggleOverlay('quick'); })),
                    if (_isNotificationCenterOpen) Positioned(bottom: taskbarHeight + 8, right: 8, width: overlayWidth, child: ConstrainedBox(constraints: BoxConstraints(maxHeight: screenHeight * 0.8), child: NotificationCenterPanel(notifications: _realNotifications, onClearAll: () => setState(() => _realNotifications.clear())))),

                    Win11Taskbar(
                      isStartMenuOpen: _isStartMenuOpen, onStartToggled: () => _toggleOverlay('start'), onQuickSettingsToggled: () => _toggleOverlay('quick'), onNotificationCenterToggled: () => _toggleOverlay('notification'), onOverlaysClosed: _closeOverlays,
                      batteryLevel: _batteryLevel, batteryState: _batteryState, unreadNotifications: _unreadNotifications,    
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}