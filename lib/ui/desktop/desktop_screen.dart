import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:torch_light/torch_light.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:confetti/confetti.dart';

import '../../states/theme_state.dart';
import '../../states/system_state.dart';
import '../../states/desktop_state.dart';
import '../../states/apps_state.dart';
import '../../lock_screen.dart';
import 'taskbar.dart';
import '../start_menu/start_menu.dart';
import '../../quick_settings.dart';
import '../../notification_center.dart';
import '../explorer/file_explorer_app.dart';
import '../../services/native_bridge.dart';
import '../../services/backup_service.dart';
import '../../services/battery_mock.dart'; 
import '../../services/lazy_app_icon.dart'; 
import '../../services/pro_gatekeeper.dart'; 

import 'desktop_workspace.dart';
import 'window_manager.dart';
import 'desktop_context_menu.dart';
import 'search_overlay.dart'; 
import 'win11_toast.dart';
import 'desktop_services.dart';

class DesktopScreen extends StatefulWidget {
  const DesktopScreen({Key? key}) : super(key: key);
  @override
  State<DesktopScreen> createState() => _DesktopScreenState();
}

class _DesktopScreenState extends State<DesktopScreen> with WidgetsBindingObserver {
  final GlobalKey<FileExplorerAppState> _explorerKey = GlobalKey<FileExplorerAppState>();
  final PageController _pageController = PageController();
  
  late ConfettiController _confettiController;
  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();

  int _currentDesktopPage = 0;
  bool _isLocked = true;
  bool _isStartMenuOpen = false;
  bool _isWidgetBoardOpen = false;
  bool _isQuickSettingsOpen = false;
  bool _isNotificationCenterOpen = false;
  bool _isContextMenuOpen = false;

  bool get _isAnyOverlayOpen => 
      _isStartMenuOpen || _isQuickSettingsOpen || _isNotificationCenterOpen || _isWidgetBoardOpen || _isContextMenuOpen;

  Offset _contextMenuPos = Offset.zero;
  String _contextMenuType = 'desktop';
  String _contextTargetName = '';
  String _contextTargetId = '';
  VoidCallback? _contextOpenAction;

  String? _resizingWidgetId;
  String? _movingWidgetId;

  final ValueNotifier<double> _volume = ValueNotifier<double>(0.5);
  final ValueNotifier<double> _brightness = ValueNotifier<double>(0.5);
  final ValueNotifier<int> _batteryLevel = ValueNotifier<int>(100);
  final ValueNotifier<bool> _isCharging = ValueNotifier<bool>(false); 
  
  final ValueNotifier<List<Map<String, dynamic>>> _realNotifications = ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<int> _unreadNotifications = ValueNotifier<int>(0);

  final ValueNotifier<Map<String, bool>> _quickSettings = ValueNotifier<Map<String, bool>>({
    'Airplane mode': false, 'Battery saver': false, 'Wi-Fi': false, 'Bluetooth': false, 'Flash': false, 'Data': false, 'Rotate': false, 'Location': false, 'Hotspot': false, 'VPN': false, 'Brightness': false, 'Accessibility': false,
    'Play': false, 'Ring': true, 'ChatGPT': false, 'Storage': false, 'Dark Theme': false, 'Calculator': false, 'Song Search': false, 'DND': false, 'Screen Cast': false, 'Eye Care': false, 'Scan QR Code': false, 'Users & Account': false, 'Kids Mode': false,
    'Adaptive Brightness': false
  });
  
  final Set<String> _recentlyToggledHardware = {};

  int _activePointers = 0;
  int _maxPointers = 0;
  double _currentScale = 1.0; 

  StreamSubscription? _brightnessSub;
  StreamSubscription? _notifSub;
  StreamSubscription? _hwSub;
  StreamSubscription? _pkgSub;
  StreamSubscription? _fileSub;
  StreamSubscription? _usbSub;

  final List<Map<String, dynamic>> _activeToasts = [];

  String _lastWallpaperUrl = '';
  int _wallpaperTransitionType = 0;

  bool _isUserDraggingBrightness = false;
  bool _isUserDraggingVolume = false;
  DateTime _lastBrightnessNativeCall = DateTime.now();
  DateTime _lastVolumeNativeCall = DateTime.now();

  // CRITICAL FIX: Managed timers to prevent background lifecycle memory leaks & race conditions
  Timer? _hardwareSyncTimer;
  Timer? _physicalDesktopTimer;
  Timer? _backgroundTasksTimer;
  Timer? _calendarDelayTimer;
  Timer? _updateCheckTimer;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 4));
    WidgetsBinding.instance.addObserver(this); 
    
    if (!kIsWeb) {
      NativeBridge.instance.isDeviceLocked().then((isSystemLocked) {
        if (isSystemLocked && mounted) {
          setState(() => _isLocked = true);
        }
      });
      
      _initHardwareStreams(); 
      _initNotifications(); 
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<DesktopState>().applyOrientationLock();
        _runFirstLaunchSequence(); 
        
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) context.read<DesktopState>().syncPhysicalDesktop();
        });

        _calendarDelayTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) _runCalendarChecks();
        });

        _updateCheckTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            DesktopServices.checkAutomatedUpdate(
              realNotifications: _realNotifications,
              unreadNotifications: _unreadNotifications,
              activeToasts: _activeToasts,
              onToastAdded: () {
                if (mounted) setState(() {});
              },
            );
          }
        });
      });
    }
  }

  void _runCalendarChecks() async {
    var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
    if (permissionsGranted.isSuccess && !(permissionsGranted.data ?? false)) {
      permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
    }
    
    if (!permissionsGranted.isSuccess || !(permissionsGranted.data ?? false)) return;

    DesktopServices.checkForBirthdaysToday(
      calendarPlugin: _deviceCalendarPlugin,
      confettiController: _confettiController,
      realNotifications: _realNotifications,
      unreadNotifications: _unreadNotifications,
      activeToasts: _activeToasts,
      onToastAdded: () {
        if (mounted) setState(() {});
      },
    );

    DesktopServices.checkForUpcomingEvents(
      calendarPlugin: _deviceCalendarPlugin,
      realNotifications: _realNotifications,
      unreadNotifications: _unreadNotifications,
      activeToasts: _activeToasts,
      onToastAdded: () {
        if (mounted) setState(() {});
      },
      advanceNoticeMinutes: 30,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _confettiController.dispose();
    _cancelHardwareStreams();
    
    // Clean up lifecycle timers
    _hardwareSyncTimer?.cancel();
    _physicalDesktopTimer?.cancel();
    _backgroundTasksTimer?.cancel();
    _calendarDelayTimer?.cancel();
    _updateCheckTimer?.cancel();

    if (!kIsWeb) { try { VolumeController.instance.removeListener(); } catch (_) {} }
    _pageController.dispose(); _volume.dispose(); _brightness.dispose(); _batteryLevel.dispose(); _isCharging.dispose(); _realNotifications.dispose(); _unreadNotifications.dispose(); _quickSettings.dispose();
    super.dispose();
  }

  void _cancelHardwareStreams() {
    _brightnessSub?.cancel(); _brightnessSub = null;
    _hwSub?.cancel(); _hwSub = null;
    _pkgSub?.cancel(); _pkgSub = null;
    _fileSub?.cancel(); _fileSub = null;
    _usbSub?.cancel(); _usbSub = null;
    _notifSub?.cancel(); _notifSub = null;
  }

  void _lockDesktop() {
    if (mounted) {
      setState(() {
        _closeOverlays();
        _isLocked = true;
      });
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  Future<void> _runFirstLaunchSequence() async {
    final prefs = await SharedPreferences.getInstance();
    final hasPromptedHome = prefs.getBool('hasPromptedForDefault') ?? false;
    final hasPromptedNotif = prefs.getBool('hasPromptedForNotifAccess') ?? false;

    if (!hasPromptedHome) {
      await prefs.setBool('hasPromptedForDefault', true);
      if (mounted) {
        final isDark = context.read<ThemeState>().isDarkMode;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            title: Row(
              children: [const Icon(Icons.home_filled, color: Colors.blueAccent), const SizedBox(width: 12), Text('Set Default Launcher', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold))],
            ),
            content: Text('To get the complete Windows 11 experience, please set Win11 PC Launcher as your default home app on the next screen.', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13, height: 1.4)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Maybe Later', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
              TextButton(
                onPressed: () { 
                  Navigator.pop(ctx); 
                  NativeBridge.instance.openSettings('home'); 
                }, 
                child: const Text('Set as Default', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))
              ),
            ],
          )
        );
      }
    }

    if (!hasPromptedNotif) {
      await prefs.setBool('hasPromptedForNotifAccess', true);
      final perms = await NativeBridge.instance.getPermissionStatuses();
      
      if (perms['notification'] != true) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          NativeBridge.instance.openSettings('notification_access');
        }
      }
    }
  }

  void _fetchActualHardwareState() async {
    final initialState = await NativeBridge.instance.getHardwareState();
    if (mounted) {
      final updatedSettings = Map<String, bool>.from(_quickSettings.value);
      initialState.forEach((key, value) { 
        if (value is bool && !_recentlyToggledHardware.contains(key)) {
          updatedSettings[key] = value; 
        }
      });
      if (initialState.containsKey('sys_brightness') && initialState['sys_brightness'] is double) _brightness.value = initialState['sys_brightness'];
      
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
      context.read<DesktopState>().applyOrientationLock();

      NativeBridge.instance.checkAndClearScreenOffFlag().then((wasScreenOff) {
        NativeBridge.instance.isDeviceLocked().then((isSystemLocked) {
          final systemState = context.read<SystemState>();
          if (isSystemLocked || (wasScreenOff && systemState.isPinSet)) {
            _lockDesktop();
          }
        });
      });

      // CRITICAL FIX: Convert floating Delays to bound Timers
      _hardwareSyncTimer?.cancel();
      _hardwareSyncTimer = Timer(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        _fetchActualHardwareState(); 
        Future.delayed(const Duration(milliseconds: 500), _refreshNotifications);

        if (_hwSub == null) {
          _initHardwareStreams();
          _initNotifications();
        }
      });

      _physicalDesktopTimer?.cancel();
      _physicalDesktopTimer = Timer(const Duration(milliseconds: 3500), () {
        if (!mounted) return;
        context.read<DesktopState>().syncPhysicalDesktop();
      });

      _backgroundTasksTimer?.cancel();
      _backgroundTasksTimer = Timer(const Duration(seconds: 8), () {
        if (!mounted) return;
        BackupService.instance.checkAndRunWeeklyBackup();
        _runCalendarChecks();
      });
      
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      // Cancel active timers so they don't fire if the user is already gone
      _hardwareSyncTimer?.cancel();
      _physicalDesktopTimer?.cancel();
      _backgroundTasksTimer?.cancel();
      _calendarDelayTimer?.cancel();
      _updateCheckTimer?.cancel();

      final desktopState = context.read<DesktopState>();
      if (desktopState.keepOverlaysAliveNextPause) {
         desktopState.keepOverlaysAliveNextPause = false;
      } else {
         _closeOverlays();
      }
    }
  }

  void _initHardwareStreams() async {
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        final updated = Map<String, bool>.from(_quickSettings.value);
        for (var k in ['Data', 'Hotspot', 'Eye Care', 'Kids Mode']) {
          updated[k] = prefs.getBool('qs_$k') ?? false;
        }
        _quickSettings.value = updated;
      }
    });

    _fetchActualHardwareState();
    _hwSub = NativeBridge.instance.hardwareStateStream.listen((event) {
      if (!mounted) return;
      final data = Map<String, dynamic>.from(event);
      
      if (data['screen_off'] == true) {
        final systemState = context.read<SystemState>();
        NativeBridge.instance.isDeviceLocked().then((isSystemLocked) {
          if (isSystemLocked || systemState.isPinSet) {
            _lockDesktop();
          }
        });
        return; 
      }
      
      if (data.containsKey('battery_level') && data['battery_level'] is int) {
        _batteryLevel.value = data['battery_level'];
      }
      if (data.containsKey('battery_charging') && data['battery_charging'] is bool) {
        _isCharging.value = data['battery_charging'];
      }
      
      final updatedSettings = Map<String, bool>.from(_quickSettings.value);
      data.forEach((key, value) { 
        if (value is bool && !_recentlyToggledHardware.contains(key)) { 
          updatedSettings[key] = value; 
        } 
      });
      if (data.containsKey('sys_brightness') && data['sys_brightness'] is double && !_isUserDraggingBrightness) {
        _brightness.value = data['sys_brightness'];
      }
      
      _quickSettings.value = updatedSettings;
    });
    
    const EventChannel usbChannel = EventChannel('win_launcher/usb_events');
    _usbSub = usbChannel.receiveBroadcastStream().listen((event) async {
      if (!mounted) return;
      final data = Map<String, dynamic>.from(event);
      
      if (data['type'] == 'USB_ATTACHED') {
        final prefs = await SharedPreferences.getInstance();
        final autoPlayEnabled = prefs.getBool('usb_autoplay') ?? true;
        
        if (autoPlayEnabled) {
          final deviceName = data['deviceName'] ?? 'USB Drive';
          setState(() {
            _activeToasts.removeWhere((t) => t['title'] == 'Device Connected' && t['text'] == 'Tap to open $deviceName');

            final usbToast = {
              'key': 'usb_${DateTime.now().millisecondsSinceEpoch}',
              'package': 'system',
              'title': 'Device Connected',
              'text': 'Tap to open $deviceName',
              'postTime': DateTime.now().millisecondsSinceEpoch,
              'actions': [{'title': 'Open Folder', 'index': 1}],
              '_isFileToast': true,
              '_filePath': '/storage/emulated/0',
              '_toastId': 'usb_${DateTime.now().microsecondsSinceEpoch}',
            };
            if (_activeToasts.length >= 3) _activeToasts.removeAt(0);
            _activeToasts.add(usbToast);
          });
        }
      }
    });

    _pkgSub = NativeBridge.instance.packageEventStream.listen((event) {
      if (!mounted) return;

      final appsState = context.read<AppsState>();
      final desktopState = context.read<DesktopState>();

      String? installedPkg;
      String? installedLabel;

      if (event is Map) {
         final type = event['type'];
         if (type == 'APP_INSTALLED') {
        installedPkg = event['package'];
        installedLabel = event['label'];
        final bool isUpdate = event['isUpdate'] == true;
        
        if (installedPkg != null) {
           appsState.addRecentlyAddedApp(installedPkg, isUpdate: isUpdate);
           
           appsState.injectAndSyncApp(installedPkg, installedLabel ?? 'App').then((_) {
             if (!mounted) return;
             // DO NOT call LazyAppIcon.invalidateCache here, as we just pre-populated it!
             if (desktopState.createShortcut && !isUpdate) {
               desktopState.addDesktopApp(installedPkg!, installedLabel ?? 'App', _currentDesktopPage, 0, 0); 
             }
           });
        }
        
        setState(() {
            final installToast = {
              'key': 'install_$installedPkg',
              'package': installedPkg,
              'title': isUpdate ? 'App Updated' : 'New App Installed',
              'text': '${installedLabel ?? 'App'} is ready to use.',
              'postTime': DateTime.now().millisecondsSinceEpoch,
              'actions': [{'title': 'Open', 'index': 1}, {'title': 'Pin to Start', 'index': 2}],
              '_isAppInstall': true,
              '_installPkg': installedPkg,
              '_toastId': 'install_${DateTime.now().microsecondsSinceEpoch}',
            };
            
            _activeToasts.removeWhere((toast) => toast['_isAppInstall'] == true && toast['_installPkg'] == installedPkg);
            _activeToasts.add(installToast);
        });
     } else if (type == 'APP_REMOVED') {
            appsState.refreshApps(desktopState).then((_) {
               if (!mounted) return;
               final validPackages = appsState.appMap.keys.toSet();

               setState(() {
                 _activeToasts.removeWhere((toast) {
                   final pkg = toast['package'] as String?;
                   return pkg != null && pkg.contains('.') && !validPackages.contains(pkg);
                 });
               });

               final currentNotifs = List<Map<String, dynamic>>.from(_realNotifications.value);
               currentNotifs.removeWhere((n) {
                 final pkg = n['package'] as String?;
                 return pkg != null && pkg.contains('.') && !validPackages.contains(pkg);
               });
               _realNotifications.value = currentNotifs;
            });
         }
      }
    });

    _fileSub = NativeBridge.instance.fileEventStream.listen((event) {
        if (!mounted || event is! Map) return;
        final type = event['type'];
        if (type == 'FILE_DOWNLOADED') {
            final path = event['path'];
            final name = event['name'];
            
            setState(() {
                final fileToast = {
                  'key': 'file_$path',
                  'package': 'explorer',
                  'title': 'Download Complete',
                  'text': name,
                  'postTime': DateTime.now().millisecondsSinceEpoch,
                  'actions': [{'title': 'Open', 'index': 1}, {'title': 'Open Folder', 'index': 2}],
                  '_isFileToast': true,
                  '_filePath': path,
                  '_toastId': 'file_${DateTime.now().microsecondsSinceEpoch}',
                };
                _activeToasts.add(fileToast);
            });
        }
    });

    try {
      double v = await VolumeController.instance.getVolume();
      if (v.isNaN || v.isInfinite) v = 0.5;
      if (v > 1.0) v = v / 15.0; 
      _volume.value = v.clamp(0.0, 1.0);
      VolumeController.instance.addListener((vol) {
        if (mounted && !_isUserDraggingVolume) {
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
        if (mounted && !_isUserDraggingBrightness) {
          if (bValue.isNaN || bValue.isInfinite) bValue = 0.5;
          _brightness.value = bValue.clamp(0.0, 1.0);
        }
      });
    } catch (_) {}
  }

  void _initNotifications() async {
    try {
      _refreshNotifications();
      _realNotifications.addListener(() { 
        if (mounted) context.read<AppsState>().updateNotificationCounts(_realNotifications.value); 
      });
      
      _notifSub = NativeBridge.instance.notificationStream.listen((event) {
        if (!mounted) return;
        final data = Map<String, dynamic>.from(event);
        final currentNotifs = List<Map<String, dynamic>>.from(_realNotifications.value);
        
        if (data['removed'] == true) {
          currentNotifs.removeWhere((n) => n['key'] == data['key']);
          setState(() {
            _activeToasts.removeWhere((t) => t['key'] == data['key']);
          });
        } else {
          bool isTrayUpdate = currentNotifs.any((n) => n['key'] == data['key']);
          bool isToastActive = _activeToasts.any((t) => t['key'] == data['key']);

          currentNotifs.removeWhere((n) => n['key'] == data['key']);
          currentNotifs.insert(0, data);
          if (!_isNotificationCenterOpen) _unreadNotifications.value++;

          final lifecycleState = WidgetsBinding.instance.lifecycleState;
          final isForeground = lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
          
          final isOngoing = data['isOngoing'] == true;
          final isMedia = data['isMedia'] == true;

          bool blockToast = isOngoing || isMedia || (isTrayUpdate && !isToastActive);

          if (context.read<SystemState>().notifShowOnLockScreen && isForeground && !blockToast) {
             setState(() {
                String tTitle = data['title']?.toString().trim() ?? '';
                String tText = data['text']?.toString().trim() ?? '';
                String pkg = data['package']?.toString() ?? '';
                String appName = pkg.split('.').last.toLowerCase();
                
                bool isGenericSummary = tTitle.toLowerCase().contains(appName) || 
                                        tText.toLowerCase().contains('unread messages') || 
                                        tText.toLowerCase().contains('new messages');

                int existingIdx = _activeToasts.indexWhere((t) => t['package'] == pkg);
                
                if (existingIdx != -1) {
                    var existing = Map<String, dynamic>.from(_activeToasts[existingIdx]);
                    List<dynamic> tActions = data['actions'] ?? [];
                    
                    if (tActions.isNotEmpty) {
                        existing['actions'] = tActions;
                        existing['key'] = data['key']; 
                    }
                    
                    if (!isGenericSummary) {
                        existing['title'] = tTitle;
                        existing['text'] = tText;
                    }
                    
                    _activeToasts[existingIdx] = existing;
                } else {
                    if (_activeToasts.length >= 3) {
                      _activeToasts.removeAt(0);
                    }
                    data['_toastId'] = DateTime.now().microsecondsSinceEpoch.toString();
                    _activeToasts.add(Map<String, dynamic>.from(data));
                }
             });
          }
        }
        _realNotifications.value = currentNotifs;
      });
    } catch (_) {}
  }

  void _updateBrightness(double val) {
    if (val.isNaN || val.isInfinite) val = 0.5;
    final clamped = val.clamp(0.0, 1.0);
    _brightness.value = clamped;

    final now = DateTime.now();
    if (!kIsWeb && now.difference(_lastBrightnessNativeCall).inMilliseconds > 35) {
      _lastBrightnessNativeCall = now;
      NativeBridge.instance.setSystemBrightness(clamped);
    }
  }

  void _updateVolume(double val) {
    if (val.isNaN || val.isInfinite) val = 0.5;
    final clamped = val.clamp(0.0, 1.0);
    _volume.value = clamped;

    final now = DateTime.now();
    if (!kIsWeb && now.difference(_lastVolumeNativeCall).inMilliseconds > 35) {
      _lastVolumeNativeCall = now;
      VolumeController.instance.setVolume(clamped);
    }
  }

  void _handleHardwareToggle(String key) async {
    final appsState = context.read<AppsState>();
    final themeState = context.read<ThemeState>();
    bool currentVal = _quickSettings.value[key] ?? false;
    bool newVal = !currentVal;

    if (key == 'Calculator') { appsState.openApp('calculator'); return; }
    if (key == 'Storage') { NativeBridge.instance.toggleHardware('Storage', true); return; }
    if (key == 'ChatGPT') { final success = await NativeBridge.instance.launchApp('com.openai.chatgpt'); if (!success) _showToast('ChatGPT app not installed'); return; }
    if (key == 'Scan QR Code') { NativeBridge.instance.toggleHardware('Scan QR Code', true); return; }
    if (key == 'Song Search') { NativeBridge.instance.toggleHardware('Song Search', true); return; }
    if (key == 'Kids Mode') { NativeBridge.instance.toggleHardware('Kids Mode', true); return; }

    if (key == 'Play') {
      bool hasMedia = _realNotifications.value.any((n) {
        if (n['isMedia'] == true) return true;
        final pkg = (n['package'] ?? '').toString().toLowerCase();
        return pkg.contains('music') || pkg.contains('spotify') || pkg.contains('boomplayer') || pkg.contains('audiomack');
      });

      if (!hasMedia) {
        final musicApps = [
          'com.afmobi.boomplayer',                 
          'com.spotify.music',                     
          'com.google.android.apps.youtube.music', 
          'net.audiomack',                         
          'com.apple.android.music',               
          'com.transsnet.music',                   
        ];

        String? targetPkg;
        for (var pkg in musicApps) {
          if (appsState.installedApps.any((app) => app.packageName == pkg)) {
            targetPkg = pkg;
            break;
          }
        }

        if (targetPkg == null) {
          for (var app in appsState.installedApps) {
            final name = (app.name ?? '').toLowerCase();
            final pkg = (app.packageName ?? '').toLowerCase();
            if (name.contains('music') || name.contains('audio') || pkg.contains('music') || pkg.contains('audio')) {
              targetPkg = app.packageName;
              break;
            }
          }
        }

        if (targetPkg != null) {
          NativeBridge.instance.launchApp(targetPkg);
          _showToast('Launching Music Player...');
        } else {
          _showToast('No active media session or recognized music app found.');
        }
      } else {
        NativeBridge.instance.toggleHardware('Play', true);
      }
      return;
    }

    if (key == 'Flash') {
      try { if (currentVal) await TorchLight.disableTorch(); else await TorchLight.enableTorch(); } catch (e) { _showToast('Flashlight not available'); return; }
    } else if (key == 'Dark Theme') {
      if (newVal && !ProGatekeeper.checkAccess(context, featureName: 'Dark Theme')) return;
      themeState.setDarkMode(newVal);
    }

    _quickSettings.value = Map.from(_quickSettings.value)..[key] = newVal;
    
    if (['Data', 'Hotspot', 'Eye Care', 'Kids Mode'].contains(key)) {
       SharedPreferences.getInstance().then((prefs) => prefs.setBool('qs_$key', newVal));
    }
    
    _recentlyToggledHardware.add(key);
    NativeBridge.instance.toggleHardware(key, newVal);
    
    Future.delayed(const Duration(seconds: 4), () {
      _recentlyToggledHardware.remove(key);
    });
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
        if (_isNotificationCenterOpen) _unreadNotifications.value = 0;
      } else {
        _isNotificationCenterOpen = false;
      }
    });
  }

  void _showAccessibilityPrompt(String featureName, String explanation) {
    final isDark = context.read<ThemeState>().isDarkMode;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        title: Text('Accessibility Required', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text("To use $featureName, Android requires Accessibility permissions.\n\n$explanation\n\n1. Tap 'Go to Settings'\n2. Select 'Downloaded Apps'\n3. Turn ON 'Win11 PC Launcher'", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
          TextButton(onPressed: () { Navigator.pop(ctx); NativeBridge.instance.openSettings('accessibility'); }, child: const Text('Go to Settings', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  void _handleGestureAction(String action) async {
    if (action == 'None' || action.isEmpty) return;
    if (context.read<DesktopState>().gestureHapticFeedback) HapticFeedback.lightImpact();
    
    if (action.startsWith('app:')) { NativeBridge.instance.launchApp(action.substring(4)); return; }
    
    if (action == 'Start Menu' || action == 'All Apps') _toggleOverlay('start');
    else if (action == 'Notification Center') _toggleOverlay('notification');
    else if (action == 'Quick Settings') _toggleOverlay('quick');
    else if (action == 'Task View') {
      _closeOverlays();
      if (!ProGatekeeper.checkAccess(context, featureName: 'Recent Task View')) return;

      bool success = await NativeBridge.instance.toggleRecents();
      if (!success && mounted) {
        _showAccessibilityPrompt('Recent Apps', 'Win11 PC Launcher needs Accessibility Service to safely open your recent apps menu without root access.');
      }
    }
    else if (action == 'Widget Board') setState(() { _closeOverlays(); _isWidgetBoardOpen = true; });
    else if (action == 'Device Notification Bar') { try { await NativeBridge.instance.expandNotificationPanel(); } catch (e) { debugPrint("Failed to expand native panel: $e"); } }
    else if (action == 'Global Search') {
      _closeOverlays();
      showGeneralDialog(
        context: context, barrierDismissible: true, barrierLabel: 'Search', barrierColor: Colors.transparent, transitionDuration: const Duration(milliseconds: 10),
        pageBuilder: (context, anim1, anim2) {
          final screenWidth = MediaQuery.of(context).size.width;
          final screenHeight = MediaQuery.of(context).size.height;
          final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
          final safeAreaTop = MediaQuery.of(context).padding.top;
          
          final double assumedBottomOffset = math.max(64.0, keyboardHeight);
          final double maxAvailableHeight = screenHeight - assumedBottomOffset - safeAreaTop - 12.0;
          final double overlayHeight = math.min(520.0, math.max(250.0, maxAvailableHeight));

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 160),
                curve: const Cubic(0.05, 0.7, 0.1, 1.0),
                bottom: math.max(50.0 + MediaQuery.of(context).padding.bottom, MediaQuery.of(context).viewInsets.bottom + 2), 
                left: context.read<DesktopState>().taskbarAlignment == 'center' 
                    ? ((screenWidth - 315.0) / 2).clamp(0.0, screenWidth - 315.0) 
                    : 0.0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 315.0, maxHeight: overlayHeight),
                  child: AppSearchOverlay(
                    width: 315.0, 
                    installedApps: context.read<AppsState>().installedApps, 
                    isDark: context.read<ThemeState>().isDarkMode, 
                    accentColor: context.read<ThemeState>().currentAccentColor
                  )
                )
              )
            ],
          );
        },
        transitionBuilder: (context, anim1, anim2, child) {
          return SlideTransition(position: Tween(begin: const Offset(0, 0.05), end: const Offset(0, 0)).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOut)), child: FadeTransition(opacity: anim1, child: child));
        }
      );
    }
    else if (action == 'Lock Screen') {
      _closeOverlays();
      final bool locked = await NativeBridge.instance.lockScreen();
      if (locked && mounted) {
        _lockDesktop();
      } else if (mounted) {
        _showToast('Device Admin permission required to turn off screen');
      }
    }
    else if (action == 'Launch Assistant') {
      _closeOverlays();
      NativeBridge.instance.launchApp('com.google.android.googlequicksearchbox');
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(fontSize: 13)), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))));
  }

  Widget _buildWallpaperFallback(Color accentColor, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [accentColor.withOpacity(0.85), isDark ? const Color(0xFF141414) : const Color(0xFFE0E5EC)]),
      ),
    );
  }

  Widget _buildOverlayBlocker({required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque, 
      onTap: () {}, 
      onLongPress: () {}, 
      onLongPressStart: (_) {}, 
      onSecondaryTapDown: (_) {}, 
      child: child
    );
  }

  @override
  Widget build(BuildContext context) {
    // CRITICAL FIX: Replaced watch() with select() to prevent full-tree frame drops
    final safeAreaTop = MediaQuery.of(context).padding.top;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    final currentWallpaper = context.select<ThemeState, String>((state) => state.actualWallpaperUrl);
    final isDark = context.select<ThemeState, bool>((state) => state.isDarkMode);
    final accent = context.select<ThemeState, Color>((state) => state.currentAccentColor);

    final taskbarHeight = context.select<DesktopState, double>((state) => state.taskbarHeight);
    final taskbarAlignment = context.select<DesktopState, String>((state) => state.taskbarAlignment);

    const double startMenuWidth = 290.0;
    final bool isTaskbarCenter = taskbarAlignment == 'center';
    
    final double startMenuLeft = isTaskbarCenter 
        ? ((screenWidth - startMenuWidth) / 2).clamp(0.0, screenWidth - startMenuWidth) 
        : 0.0;
        
    final double currentTaskbarHeight = taskbarHeight;
    final double overlayBottomTarget = math.max(currentTaskbarHeight + safeAreaBottom, keyboardHeight);
        
    final double maxAvailableHeight = screenHeight - overlayBottomTarget - safeAreaTop - 12.0;
    final double maxOverlayHeight = math.min(520.0, math.max(250.0, maxAvailableHeight));

    if (_lastWallpaperUrl != currentWallpaper) {
      _lastWallpaperUrl = currentWallpaper;
      _wallpaperTransitionType = math.Random().nextInt(6);
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light, systemNavigationBarColor: Colors.transparent),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (_isLocked) return;
          if (_isStartMenuOpen || _isQuickSettingsOpen || _isNotificationCenterOpen || _isWidgetBoardOpen || _isContextMenuOpen) {
            _closeOverlays();
            return;
          }
          final appsState = context.read<AppsState>();
          if (appsState.windowStack.isNotEmpty) {
            final topApp = appsState.windowStack.last;
            if (appsState.windowBackHandlers.containsKey(topApp)) {
              bool handled = await appsState.windowBackHandlers[topApp]!();
              if (handled) return;
            }
            if (topApp == 'explorer') {
               bool wentBack = _explorerKey.currentState?.goBack() ?? false;
               if (wentBack) return; 
            }
            appsState.closeApp(topApp);
          }
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          body: SizedBox.expand(
            child: Listener(
              onPointerDown: (_) {
                _activePointers++;
                if (_activePointers == 1) _maxPointers = 1;
                else if (_activePointers > _maxPointers) _maxPointers = _activePointers;
              },
              onPointerUp: (_) { _activePointers--; },
              onPointerCancel: (_) { 
                 _activePointers--; 
                 if (_activePointers <= 0) {
                    _activePointers = 0;
                 }
              },
              child: GestureDetector(
                onTap: _closeOverlays,
                onScaleStart: _isAnyOverlayOpen ? null : (_) { _currentScale = 1.0; },
                onScaleUpdate: _isAnyOverlayOpen ? null : (details) { _currentScale = details.scale; },
                onScaleEnd: _isAnyOverlayOpen ? null : (details) {
                  final dx = details.velocity.pixelsPerSecond.dx;
                  final dy = details.velocity.pixelsPerSecond.dy;
                  final pointerSnapshot = _maxPointers;
                  
                  if (pointerSnapshot >= 2) {
                     if (_currentScale > 1.2) { _handleGestureAction(context.read<DesktopState>().gesturePinchOutAction); return; } 
                     else if (_currentScale < 0.8) { _handleGestureAction(context.read<DesktopState>().gesturePinchInAction); return; }
                  }
  
                  if (dx.abs() > 800 || dy.abs() > 800) {
                    if (dx.abs() > dy.abs()) {
                      if (dx > 800) { 
                        _handleGestureAction(context.read<DesktopState>().gestureRightAction); 
                      } else if (dx < -800) { 
                        _handleGestureAction(context.read<DesktopState>().gestureLeftAction); 
                      }
                    } else {
                      if (dy < -800) { _handleGestureAction(pointerSnapshot >= 2 ? context.read<DesktopState>().gestureTwoFingerUpAction : context.read<DesktopState>().gestureUpAction); } 
                      else if (dy > 800) { _handleGestureAction(pointerSnapshot >= 2 ? context.read<DesktopState>().gestureTwoFingerDownAction : context.read<DesktopState>().gestureDownAction); }
                    }
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: GestureDetector(
                          onDoubleTap: () => _handleGestureAction(context.read<DesktopState>().gestureDoubleTapAction),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 1200),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (Widget child, Animation<double> animation) {
                              switch (_wallpaperTransitionType) {
                                case 1: 
                                  return FadeTransition(opacity: animation, child: ScaleTransition(scale: Tween<double>(begin: 1.05, end: 1.0).animate(animation), child: child));
                                case 2: 
                                  return FadeTransition(opacity: animation, child: ScaleTransition(scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation), child: child));
                                case 3: 
                                  return FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation), child: child));
                                case 4: 
                                  return FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(-0.05, 0), end: Offset.zero).animate(animation), child: child));
                                case 5: 
                                  return FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(animation), child: child));
                                case 0:
                                default: 
                                  return FadeTransition(opacity: animation, child: child);
                              }
                            },
                            child: SizedBox.expand(
                              key: ValueKey<String>(currentWallpaper),
                              child: currentWallpaper == 'system'
                                  ? const SizedBox.expand()
                                  : (currentWallpaper.startsWith('assets/')
                                    ? Image.asset(currentWallpaper, fit: BoxFit.cover, errorBuilder: (c, e, s) => _buildWallpaperFallback(accent, isDark))
                                    : (currentWallpaper.startsWith('http')
                                        ? CachedNetworkImage(imageUrl: currentWallpaper, fit: BoxFit.cover, placeholder: (c, u) => _buildWallpaperFallback(accent, isDark), errorWidget: (c, u, e) => _buildWallpaperFallback(accent, isDark))
                                        : Image.file(
                                            File(currentWallpaper), 
                                            fit: BoxFit.cover, 
                                            cacheWidth: (screenWidth * MediaQuery.of(context).devicePixelRatio).toInt(), 
                                            errorBuilder: (c, e, s) => _buildWallpaperFallback(accent, isDark)
                                          ))),
                            ),
                          ),
                        ),
                      ),
                    ),
  
                    Offstage(
                      offstage: _isLocked,
                      child: DesktopWorkspace(
                        taskbarHeight: currentTaskbarHeight, 
                        safeAreaTop: safeAreaTop, 
                        currentDesktopPage: _currentDesktopPage, 
                        pageController: _pageController,
                        onPageChanged: (i) => setState(() => _currentDesktopPage = i),
                        resizingWidgetId: _resizingWidgetId, onExitResizeMode: () => setState(() => _resizingWidgetId = null),
                        movingWidgetId: _movingWidgetId, onExitMoveMode: () => setState(() => _movingWidgetId = null),
                        onCloseOverlays: _closeOverlays, 
                        onDoubleTap: () => _handleGestureAction(context.read<DesktopState>().gestureDoubleTapAction), 
                        explorerKey: _explorerKey, 
                        onContextMenu: (pos, type, targetId, targetName, openAction) { 
                          setState(() { 
                            _closeOverlays(); 
                            _isContextMenuOpen = true; 
                            _contextMenuPos = pos; 
                            _contextMenuType = type; 
                            _contextTargetId = targetId;
                            _contextTargetName = targetName; 
                            _contextOpenAction = openAction; 
                          }); 
                        },
                      ),
                    ),
  
                    Offstage(
                      offstage: _isLocked,
                      child: WindowManager(
                        taskbarHeight: currentTaskbarHeight,
                        safeAreaBottom: safeAreaBottom,
                        explorerKey: _explorerKey, 
                        onCloseOverlays: _closeOverlays
                      ),
                    ),

                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      bottom: (_isStartMenuOpen && !_isLocked) ? overlayBottomTarget + 2 : -(maxOverlayHeight + 150),
                      left: startMenuLeft, 
                      width: startMenuWidth,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: (_isStartMenuOpen && !_isLocked) ? 1.0 : 0.0,
                        child: IgnorePointer(
                          ignoring: !(_isStartMenuOpen && !_isLocked),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: startMenuWidth, maxHeight: maxOverlayHeight),
                            child: _buildOverlayBlocker(
                              child: Provider<bool?>.value(
                                value: _isStartMenuOpen && !_isLocked,
                                child: RepaintBoundary(
                                  child: StartMenu(currentDesktopPage: _currentDesktopPage, onOverlaysClosed: _closeOverlays, onPowerTapped: () { 
                                    _lockDesktop();
                                  }),
                                ),
                              )
                            ),
                          ),
                        ),
                      ),
                    ),

                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      bottom: (_isQuickSettingsOpen && !_isLocked) ? overlayBottomTarget + 2 : -(maxOverlayHeight + 150),
                      right: 3.0, 
                      width: 270.0,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: (_isQuickSettingsOpen && !_isLocked) ? 1.0 : 0.0,
                        child: IgnorePointer(
                          ignoring: !(_isQuickSettingsOpen && !_isLocked),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: maxOverlayHeight),
                            child: _buildOverlayBlocker(
                              child: Provider<bool?>.value(
                                value: _isQuickSettingsOpen && !_isLocked,
                                child: AnimatedBuilder(
                                  animation: Listenable.merge([_quickSettings, _brightness, _volume, _batteryLevel, _isCharging, _realNotifications]),
                                  builder: (context, child) {
                                    Map<String, dynamic>? activeMedia;
                                    try {
                                      activeMedia = _realNotifications.value.firstWhere((n) {
                                        if (n['isMedia'] == true) return true;
                                        final pkg = (n['package'] ?? '').toString().toLowerCase();
                                        if (pkg.contains('music') || pkg.contains('spotify') || pkg.contains('boomplayer') || pkg.contains('audiomack')) return true;
                                        final actions = n['actions'] as List?;
                                        if (actions != null && actions.any((a) {
                                          final t = (a['title'] ?? '').toString().toLowerCase();
                                          return t == 'play' || t == 'pause' || t == 'next' || t == 'previous';
                                        })) return true;
                                        return false;
                                      });
                                    } catch (_) {}
                                    
                                    return Consumer<SystemState>(
                                      builder: (context, systemState, _) => QuickSettings(
                                        activeMedia: activeMedia,
                                        settingsState: Map<String, bool>.from(_quickSettings.value)..['Dark Theme'] = isDark,
                                        onToggle: _handleHardwareToggle, 
                                        brightness: _brightness.value, 
                                        onBrightnessChanged: _updateBrightness,
                                        onBrightnessDragStart: () => _isUserDraggingBrightness = true,
                                        onBrightnessDragEnd: (finalVal) { _isUserDraggingBrightness = false; NativeBridge.instance.setSystemBrightness(finalVal); },
                                        volume: _volume.value, 
                                        onVolumeChanged: _updateVolume, 
                                        onVolumeDragStart: () => _isUserDraggingVolume = true,
                                        onVolumeDragEnd: (finalVal) { _isUserDraggingVolume = false; VolumeController.instance.setVolume(finalVal); },
                                        batteryLevel: _batteryLevel.value, 
                                        batteryState: _isCharging.value ? BatteryState.charging : BatteryState.discharging, 
                                        onOpenSettings: () { NativeBridge.instance.openSettings('system'); }, 
                                        visibleTiles: systemState.visibleQuickSettings,
                                        hiddenTiles: systemState.hiddenQuickSettings, 
                                        onToggleVisibility: systemState.toggleQuickSettingVisibility,
                                      ),
                                    );
                                  }
                                ),
                              )
                            ),
                          ),
                        ),
                      ),
                    ),

                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      bottom: (_isNotificationCenterOpen && !_isLocked) ? overlayBottomTarget + 2 : -(maxOverlayHeight + 150),
                      right: 3.0,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: (_isNotificationCenterOpen && !_isLocked) ? 1.0 : 0.0,
                        child: IgnorePointer(
                          ignoring: !(_isNotificationCenterOpen && !_isLocked),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: 300.0, maxHeight: maxOverlayHeight),
                            child: _buildOverlayBlocker(
                              child: Provider<bool?>.value(
                                value: _isNotificationCenterOpen && !_isLocked,
                                child: AnimatedBuilder(
                                  animation: _realNotifications,
                                  builder: (context, child) => NotificationCenterPanel(
                                    isOpen: _isNotificationCenterOpen,
                                    notifications: _realNotifications.value, 
                                    installedApps: context.read<AppsState>().installedApps, 
                                    onClosePanel: _closeOverlays,
                                    onClearAll: () { NativeBridge.instance.clearAllNotifications(); _realNotifications.value = []; },
                                    onRemoveNotification: (event) { NativeBridge.instance.dismissNotification(event['key']); final updated = List<Map<String, dynamic>>.from(_realNotifications.value); updated.removeWhere((n) => n['key'] == event['key']); _realNotifications.value = updated; },
                                    onLaunchApp: (pkg) async { final success = await NativeBridge.instance.launchApp(pkg); if (!success) _showToast('App not found'); },
                                  ),
                                ),
                              )
                            ),
                          ),
                        ),
                      ),
                    ),

                    if (_activeToasts.isNotEmpty && !_isLocked)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 160),
                        curve: const Cubic(0.05, 0.7, 0.1, 1.0),
                        bottom: overlayBottomTarget + 12, 
                        right: 4,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: _activeToasts.map<Widget>((toastData) {
                            return Win11ToastWidget(
                              key: ValueKey(toastData['_toastId'] ?? toastData['key']),
                              event: toastData,
                              onDismiss: () {
                                setState(() {
                                  _activeToasts.removeWhere((t) => t['key'] == toastData['key']);
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
  
                    Positioned(
                      bottom: safeAreaBottom, 
                      left: 0, 
                      right: 0, 
                      height: currentTaskbarHeight,
                      child: Offstage(
                        offstage: _isLocked,
                        child: _buildOverlayBlocker(
                          child: AnimatedBuilder(
                            animation: Listenable.merge([_batteryLevel, _isCharging, _unreadNotifications]),
                            builder: (context, child) => Win11Taskbar(
                              isStartMenuOpen: _isStartMenuOpen, 
                              onStartToggled: () => _toggleOverlay('start'), 
                              onQuickSettingsToggled: () => _toggleOverlay('quick'), 
                              onNotificationCenterToggled: () => _toggleOverlay('notification'),
                              onTaskViewToggled: () async {
                                _closeOverlays();
                                if (!ProGatekeeper.checkAccess(context, featureName: 'Recent Task View')) return;

                                bool success = await NativeBridge.instance.toggleRecents();
                                if (!success && mounted) {
                                  _showAccessibilityPrompt('Recent Apps', 'Win11 PC Launcher needs Accessibility Service to safely open your recent apps menu without root access.');
                                }
                              }, 
                              onOverlaysClosed: _closeOverlays, 
                              batteryLevel: _batteryLevel.value, 
                              batteryState: _isCharging.value ? BatteryState.charging : BatteryState.discharging, 
                              unreadNotifications: _unreadNotifications.value,
                            ),
                          ),
                        ),
                      ),
                    ),
  
                    if (_isContextMenuOpen && !_isLocked)
                      DesktopContextMenu(
                        isOpen: _isContextMenuOpen, 
                        position: _contextMenuPos, 
                        menuType: _contextMenuType, 
                        targetId: _contextTargetId,
                        targetName: _contextTargetName, 
                        openAction: _contextOpenAction, 
                        onClose: () => setState(() => _isContextMenuOpen = false), 
                        currentDesktopPage: _currentDesktopPage, 
                        pageController: _pageController, 
                        onEnterResizeMode: (id) => setState(() => _resizingWidgetId = id),
                        onEnterMoveMode: (id) => setState(() { _closeOverlays(); _movingWidgetId = id; })
                      ),
                    
                    Align(
                      alignment: Alignment.center,
                      child: ConfettiWidget(
                        confettiController: _confettiController,
                        blastDirectionality: BlastDirectionality.explosive,
                        shouldLoop: false,
                        maxBlastForce: 60,
                        minBlastForce: 10,
                        emissionFrequency: 0.08,
                        numberOfParticles: 40,
                        gravity: 0.2,
                        colors: const [Colors.red, Colors.blue, Colors.green, Colors.yellow, Colors.purple, Colors.orange],
                      ),
                    ),

                    if (_isLocked)
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: LockScreen(
                            onUnlocked: () {
                              setState(() {
                                _isLocked = false;
                              });
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}