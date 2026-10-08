import 'dart:async';
import 'dart:io';
import 'dart:math' as math; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:win11_pc_launcher/services/battery_mock.dart';

import '../../states/theme_state.dart';
import '../../states/apps_state.dart';
import '../../states/desktop_state.dart';
import '../../states/system_state.dart';
import '../../services/native_bridge.dart';
import '../../services/lazy_app_icon.dart';
import 'search_overlay.dart';

class Win11Taskbar extends StatefulWidget {
  final bool isStartMenuOpen;
  final VoidCallback onStartToggled;
  final VoidCallback onQuickSettingsToggled;
  final VoidCallback onNotificationCenterToggled;
  final VoidCallback onTaskViewToggled;
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
    required this.onTaskViewToggled,
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
    int h = time.hour; 
    int m = time.minute;
    String ampm = h >= 12 ? 'PM' : 'AM';
    h = h % 12; 
    if (h == 0) h = 12;
    return '$h:${m.toString().padLeft(2, '0')} $ampm';
  }

  String _formatDate(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _triggerHaptic() {
    if (context.read<DesktopState>().gestureHapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  void _openSearchOverlay(BuildContext context, AppsState appsState, ThemeState themeState, DesktopState desktopState) {
    final screenWidth = MediaQuery.of(context).size.width;
    const double searchWidth = 315.0;
    final bool isCenter = desktopState.taskbarAlignment == 'center';
    
    final double searchLeft = isCenter 
        ? ((screenWidth - searchWidth) / 2).clamp(0.0, screenWidth - searchWidth) 
        : 0.0;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Search',
      barrierColor: Colors.transparent, 
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (context, anim1, anim2) {
        final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
        final safeAreaBottom = MediaQuery.of(context).padding.bottom;
        final double overlayBottomTarget = math.max(desktopState.taskbarHeight + safeAreaBottom, keyboardHeight);

        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 160),
              curve: const Cubic(0.05, 0.7, 0.1, 1.0),
              bottom: overlayBottomTarget + 2.0, 
              left: searchLeft, 
              child: AppSearchOverlay(
                width: searchWidth,
                installedApps: appsState.installedApps, 
                isDark: themeState.isDarkMode, 
                accentColor: themeState.currentAccentColor 
              ),
            )
          ],
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween(begin: const Offset(0, 0.05), end: const Offset(0, 0)).animate(
            CurvedAnimation(parent: anim1, curve: Curves.easeOut)
          ),
          child: FadeTransition(opacity: anim1, child: child),
        );
      }
    );
  }

  Widget _buildTaskbarButton({
    required bool isActive,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    required Widget child,
    required double buttonSize,
    double spacing = 0.0, 
    bool indicator = false,
    bool isApp = false,
    bool isActiveApp = false,
  }) {
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final accent = themeState.currentAccentColor;
    
    Color indicatorColor = accent;
    if (isDark && accent.computeLuminance() < 0.05) indicatorColor = Colors.white70;
    if (!isDark && accent.computeLuminance() > 0.95) indicatorColor = Colors.black87;

    return InkWell(
      onTap: () {
        _triggerHaptic();
        onTap();
      },
      onTapDown: (_) => _triggerHaptic(),
      onLongPress: onLongPress ?? () {},
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: buttonSize, 
        height: buttonSize,
        margin: EdgeInsets.symmetric(horizontal: spacing / 2),
        decoration: BoxDecoration(
          color: isActive ? accent.withOpacity(isDark ? 0.35 : 0.20) : Colors.transparent,
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
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  width: isApp ? (isActiveApp ? (buttonSize * 0.4) : (buttonSize * 0.17)) : (buttonSize * 0.3),
                  height: 3,
                  decoration: BoxDecoration(
                    color: isApp
                        ? (isActiveApp ? indicatorColor : (isDark ? Colors.white54 : Colors.black45))
                        : indicatorColor,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _getRawAppIcon(String windowId, AppsState appsState, bool isDark, ThemeState themeState, double iconSize) {
    if (windowId.contains('.')) {
      if (themeState.cachedIconsPath != null) {
         if (!appsState.iconCacheStatus.containsKey(windowId)) {
           appsState.checkIconCacheStatus(windowId, themeState.cachedIconsPath);
         }
         
         if (appsState.iconCacheStatus[windowId] == true) {
           return Image.file(
             File('${themeState.cachedIconsPath}/$windowId.png'), 
             width: iconSize, height: iconSize, gaplessPlayback: true,
             errorBuilder: (_, __, ___) => LazyAppIcon(packageName: windowId, size: iconSize)
           );
         }
      }
      
      return LazyAppIcon(packageName: windowId, size: iconSize);
    }
    
    switch (windowId) {
      case 'browser': return Image.asset('assets/icons/edge.png', width: iconSize, height: iconSize);
      case 'explorer': return Image.asset('assets/icons/folder.png', width: iconSize, height: iconSize);
      case 'calculator': return Image.asset('assets/icons/calculator.png', width: iconSize, height: iconSize);
      case 'settings': return Image.asset('assets/icons/settings.png', width: iconSize, height: iconSize);
      default: return Icon(Icons.apps, size: iconSize, color: isDark ? Colors.white : Colors.black87);
    }
  }

  Widget _buildBatteryGauge(int level, bool isCharging, Color color) {
    double fillWidth = 12 * (level / 100).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCharging) 
          Padding(
            padding: const EdgeInsets.only(right: 2), 
            child: Icon(Icons.bolt, size: 12, color: Colors.green.shade500)
          ),
        Container(
          width: 16, 
          height: 9,
          decoration: BoxDecoration(border: Border.all(color: color, width: 1.2), borderRadius: BorderRadius.circular(2)),
          padding: const EdgeInsets.all(1),
          alignment: Alignment.centerLeft,
          child: Container(width: fillWidth, color: isCharging ? Colors.green.shade500 : color),
        ),
        Container(
          width: 1.5, 
          height: 3, 
          decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)))
        ),
      ],
    );
  }

  Widget _buildSystemTray(AppsState appsState, Color iconColor, bool isDark) {
    final bool isCharging = widget.batteryState == BatteryState.charging || widget.batteryState == BatteryState.full;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Quick Settings\nBattery: ${widget.batteryLevel}% ${isCharging ? '(Charging)' : ''}',
          child: InkWell(
            onTap: () {
              _triggerHaptic();
              widget.onQuickSettingsToggled();
            },
            onLongPress: () {},
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0), 
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scaleX: 1.3, scaleY: 0.9,
                    child: Icon(Icons.keyboard_arrow_up, size: 18, color: iconColor, shadows: [Shadow(color: iconColor, blurRadius: 0.5, offset: const Offset(0.2, 0.2))]),
                  ),
                  const SizedBox(width: 4),
                  _buildBatteryGauge(widget.batteryLevel, isCharging, iconColor),
                ]
              )
            ),
          ),
        ),

        InkWell(
          onTap: () {
            _triggerHaptic();
            widget.onNotificationCenterToggled();
          },
          onLongPress: () {},
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
                    Text(_formatTime(now), style: TextStyle(fontSize: 11, color: iconColor, fontWeight: FontWeight.bold)),
                    Text(_formatDate(now), style: TextStyle(fontSize: 10, color: iconColor, fontWeight: FontWeight.w600)),
                  ],
                );
              }
            ),
          ),
        ),
        
        InkWell(
          onTap: () {
             _triggerHaptic();
             for (var app in appsState.windowStack) { 
               appsState.minimizeApp(app); 
             }
             widget.onOverlaysClosed();
          },
          onLongPress: () {},
          child: Container(
            width: 6, 
            height: double.infinity, 
            margin: const EdgeInsets.only(left: 2),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final appsState = context.watch<AppsState>();
    final desktopState = context.watch<DesktopState>();

    final isDark = themeState.isDarkMode;
    final accent = themeState.currentAccentColor;
    
    final baseColor = isDark ? const Color(0xFF141414) : const Color(0xFFF3F3F3);
    
    final taskbarColor = Color.alphaBlend(accent.withOpacity(isDark ? 0.25 : 0.18), baseColor).withOpacity(1.0);
    final iconColor = isDark ? Colors.white : Colors.black87;

    final double scale = desktopState.taskbarIconScale.clamp(0.6, 1.8);
    final double maxButtonBound = math.max(24.0, desktopState.taskbarHeight - 4.0);
    final double buttonSize = (32.0 * scale).clamp(24.0, maxButtonBound);
    final double iconSize = (24.0 * scale).clamp(16.0, buttonSize - 6.0);
    final double iconSpacing = desktopState.taskbarIconSpacing;

    return RepaintBoundary(
      child: Container(
        height: double.infinity, 
        decoration: BoxDecoration(
          color: taskbarColor,
          border: Border(top: BorderSide(color: accent.withOpacity(isDark ? 0.6 : 0.4), width: 1.5)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.1), blurRadius: 4, offset: const Offset(0, -1))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: desktopState.taskbarAlignment == 'center' ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  const SizedBox(width: 4),
                  
                  _buildTaskbarButton(
                    buttonSize: buttonSize,
                    spacing: iconSpacing,
                    isActive: widget.isStartMenuOpen,
                    onTap: widget.onStartToggled,
                    child: desktopState.customStartIconPath != null && File(desktopState.customStartIconPath!).existsSync()
                        ? Image.file(
                            File(desktopState.customStartIconPath!), 
                            width: iconSize, 
                            height: iconSize, 
                            errorBuilder: (c, e, s) => Icon(Icons.window, color: themeState.foregroundAccentColor, size: iconSize)
                          )
                        : Image.asset(
                            'assets/icons/start.png', 
                            width: iconSize, 
                            height: iconSize, 
                            errorBuilder: (c, e, s) => Icon(Icons.window, color: themeState.foregroundAccentColor, size: iconSize)
                          ),
                    indicator: widget.isStartMenuOpen,
                  ),
                  
                  _buildTaskbarButton(
                    buttonSize: buttonSize,
                    spacing: iconSpacing,
                    isActive: false,
                    onTap: () { 
                      widget.onOverlaysClosed(); 
                      _openSearchOverlay(context, appsState, themeState, desktopState); 
                    },
                    child: Image.asset(
                      'assets/icons/search.png', 
                      width: iconSize * 0.9, 
                      height: iconSize * 0.9, 
                      errorBuilder: (c, e, s) => Icon(Icons.search, size: iconSize * 0.9, color: iconColor)
                    ),
                  ),
                  
                  _buildTaskbarButton(
                    buttonSize: buttonSize,
                    spacing: iconSpacing,
                    isActive: false,
                    onTap: () {
                      widget.onOverlaysClosed();
                      widget.onTaskViewToggled();
                    },
                    child: Image.asset(
                      'assets/icons/task_view.png', 
                      width: iconSize * 0.9, 
                      height: iconSize * 0.9, 
                      errorBuilder: (c, e, s) => Icon(Icons.filter_none, size: iconSize * 0.8, color: iconColor)
                    ),
                  ),
                  
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: appsState.windowStack.map((appId) {
                          bool isActive = appsState.windowStack.last == appId && !appsState.minimizedApps.contains(appId);
                          final int notifCount = appsState.appNotificationCounts[appId] ?? 0;

                          return _buildTaskbarButton(
                            buttonSize: buttonSize,
                            spacing: iconSpacing,
                            isActive: isActive,
                            onTap: () { 
                              if (appId.contains('.')) {
                                NativeBridge.instance.launchApp(appId);
                              } else {
                                appsState.openApp(appId);
                              }
                            },
                            onLongPress: () {
                              appsState.closeApp(appId);
                            }, 
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                _getRawAppIcon(appId, appsState, isDark, themeState, iconSize),
                                if (notifCount > 0)
                                  Positioned(
                                    top: -4, right: -6,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle, border: Border.all(color: Colors.transparent, width: 0)),
                                      child: Text(notifCount > 9 ? '9+' : notifCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold, height: 1.0)),
                                    ),
                                  ),
                              ]
                            ),
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
              child: _buildSystemTray(appsState, iconColor, isDark),
            ),
          ],
        ),
      ),
    );
  }
}