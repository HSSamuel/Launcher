import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:installed_apps/app_info.dart';

import '../../states/desktop_state.dart';
import '../../states/theme_state.dart';
import '../../states/apps_state.dart';
import '../../services/pro_gatekeeper.dart';
import '../../services/lazy_app_icon.dart';
import 'settings_personalization_screens.dart';

class SettingsGesturesView extends StatefulWidget {
  const SettingsGesturesView({Key? key}) : super(key: key);

  @override
  State<SettingsGesturesView> createState() => _SettingsGesturesViewState();
}

class _SettingsGesturesViewState extends State<SettingsGesturesView> {
  
  Widget _buildAppIcon(AppInfo app, double size, ThemeState themeState) {
    final pkg = app.packageName;
    if (pkg == null) return Icon(Icons.android, size: size, color: Colors.green);

    Widget fallback = LazyAppIcon(packageName: pkg, size: size);

    if (themeState.customAppIcons.containsKey(pkg)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.file(
          File(themeState.customAppIcons[pkg]!),
          width: size, height: size, fit: BoxFit.contain, gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallback,
        ),
      );
    }

    if (themeState.cachedIconsPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.file(
          File('${themeState.cachedIconsPath}/$pkg.png'),
          width: size, height: size, fit: BoxFit.contain, gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallback,
        ),
      );
    }

    return fallback;
  }

  String _formatActionDisplay(String action, AppsState appsState) {
    if (action.startsWith('app:')) {
      final pkg = action.substring(4);
      final match = appsState.installedApps.where((a) => a.packageName == pkg);
      if (match.isNotEmpty) return match.first.name ?? pkg;
      return 'App';
    }
    return action;
  }

  void _showAppPickerDialog(BuildContext context, DesktopState desktopState, ThemeState themeState, AppsState appsState, String gestureType) {
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    String searchQuery = '';
    Timer? debounceTimer;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredApps = appsState.installedApps.where((app) => 
              (app.name ?? '').toLowerCase().contains(searchQuery.toLowerCase())
          ).toList();

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            title: Text('Select Application', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 320,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search apps...',
                      hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13),
                      prefixIcon: Icon(Icons.search, size: 18, color: isDark ? Colors.white54 : Colors.black54),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    style: TextStyle(color: textColor, fontSize: 13),
                    onChanged: (val) {
                      debounceTimer?.cancel();
                      debounceTimer = Timer(const Duration(milliseconds: 250), () {
                        setDialogState(() => searchQuery = val);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: filteredApps.length,
                      itemBuilder: (context, index) {
                        final app = filteredApps[index];
                        if (app.packageName == null) return const SizedBox.shrink();
                        
                        return ListTile(
                          dense: true,
                          leading: SizedBox(
                            width: 28, 
                            height: 28,
                            child: _buildAppIcon(app, 28, themeState),
                          ),
                          title: Text(app.name ?? '', style: TextStyle(color: textColor, fontSize: 13), overflow: TextOverflow.ellipsis),
                          onTap: () {
                            desktopState.updateGesture(gestureType, 'app:${app.packageName}');
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
              ),
            ],
          );
        }
      ),
    ).whenComplete(() {
      debounceTimer?.cancel();
    });
  }

  void _showGestureActionDialog(BuildContext context, DesktopState desktopState, ThemeState themeState, AppsState appsState, String type) {
    final isDark = themeState.isDarkMode;
    
    String currentAction = 'None';
    String title = 'Gesture Action';
    
    if (type == 'DOUBLE_TAP') { currentAction = desktopState.gestureDoubleTapAction; title = 'Double Tap'; }
    else if (type == 'PINCH_IN') { currentAction = desktopState.gesturePinchInAction; title = 'Pinch In'; }
    else if (type == 'PINCH_OUT') { currentAction = desktopState.gesturePinchOutAction; title = 'Pinch Out'; }
    else if (type == 'UP') { currentAction = desktopState.gestureUpAction; title = '1-Finger UP'; }
    else if (type == 'DOWN') { currentAction = desktopState.gestureDownAction; title = '1-Finger DOWN'; }
    else if (type == '2_UP') { currentAction = desktopState.gestureTwoFingerUpAction; title = '2-Finger UP'; }
    else if (type == '2_DOWN') { currentAction = desktopState.gestureTwoFingerDownAction; title = '2-Finger DOWN'; }
    else if (type == 'LEFT') { currentAction = desktopState.gestureLeftAction; title = '1-Finger LEFT'; }
    else if (type == 'RIGHT') { currentAction = desktopState.gestureRightAction; title = '1-Finger RIGHT'; }

    final actions = [
      'None',
      'Start Menu',
      'Notification Center',
      'Quick Settings',
      'Widget Board',
      'Global Search',
      'Task View',
      'Lock Screen',
      'Device Notification Bar',
      'Launch Assistant',
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...actions.map((action) {
                  return ListTile(
                    dense: true,
                    title: Text(action, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13.5)),
                    trailing: currentAction == action ? const Icon(Icons.check, color: Colors.blueAccent, size: 18) : null,
                    onTap: () {
                      desktopState.updateGesture(type, action);
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
                const Divider(),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.apps, color: Colors.blueAccent, size: 20),
                  title: Text(
                    currentAction.startsWith('app:') ? 'App: ${_formatActionDisplay(currentAction, appsState)}' : 'Open Application...', 
                    style: const TextStyle(color: Colors.blueAccent, fontSize: 13.5, fontWeight: FontWeight.w600)
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.blueAccent),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showAppPickerDialog(context, desktopState, themeState, appsState, type);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGestureTile(String title, String subtitle, IconData icon, bool isDark, String currentAction, AppsState appsState, DesktopState desktopState, ThemeState themeState, String type) {
    final textColor = isDark ? Colors.white : Colors.black87;
    return Win11SettingsTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      isDark: isDark,
      isProLocked: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _formatActionDisplay(currentAction, appsState), 
              style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, size: 20, color: textColor),
        ]
      ),
      onTap: () {
        if (!ProGatekeeper.checkAccess(context, featureName: 'Desktop Gestures')) return;
        _showGestureActionDialog(context, desktopState, themeState, appsState, type);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktopState = context.watch<DesktopState>();
    final themeState = context.watch<ThemeState>();
    final appsState = context.watch<AppsState>();
    final isDark = themeState.isDarkMode;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Win11SettingsGroup(
            title: 'Preferences',
            isDark: isDark,
            children: [
              Win11SettingsTile(
                title: 'Haptic feedback',
                subtitle: 'Vibrate slightly when a gesture is triggered',
                icon: Icons.vibration,
                isDark: isDark,
                isProLocked: true,
                trailing: Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: desktopState.gestureHapticFeedback,
                    activeColor: themeState.currentAccentColor,
                    onChanged: (val) {
                      if (val && !ProGatekeeper.checkAccess(context, featureName: 'Desktop Gestures')) return;
                      desktopState.updateDesktopSetting('gestureHapticFeedback', val);
                    },
                  ),
                ),
              )
            ],
          ),
          Win11SettingsGroup(
            title: 'Tap Gestures',
            isDark: isDark,
            children: [
              _buildGestureTile('Double tap', 'Quickly tap the desktop wallpaper twice', Icons.touch_app, isDark, desktopState.gestureDoubleTapAction, appsState, desktopState, themeState, 'DOUBLE_TAP'),
            ],
          ),
          Win11SettingsGroup(
            title: 'Pinch Gestures',
            isDark: isDark,
            children: [
              _buildGestureTile('Pinch In', 'Pinch the desktop with two fingers', Icons.close_fullscreen, isDark, desktopState.gesturePinchInAction, appsState, desktopState, themeState, 'PINCH_IN'),
              _buildGestureTile('Pinch Out', 'Expand the desktop with two fingers', Icons.open_in_full, isDark, desktopState.gesturePinchOutAction, appsState, desktopState, themeState, 'PINCH_OUT'),
            ],
          ),
          Win11SettingsGroup(
            title: 'Swipe Gestures',
            isDark: isDark,
            children: [
              _buildGestureTile('1-Finger Swipe UP', 'Swipe up from desktop middle', Icons.swipe_up, isDark, desktopState.gestureUpAction, appsState, desktopState, themeState, 'UP'),
              _buildGestureTile('1-Finger Swipe DOWN', 'Swipe down from desktop middle', Icons.swipe_down, isDark, desktopState.gestureDownAction, appsState, desktopState, themeState, 'DOWN'),
              _buildGestureTile('1-Finger Swipe LEFT', 'Swipe left across the desktop', Icons.swipe_left, isDark, desktopState.gestureLeftAction, appsState, desktopState, themeState, 'LEFT'),
              _buildGestureTile('1-Finger Swipe RIGHT', 'Swipe right across the desktop', Icons.swipe_right, isDark, desktopState.gestureRightAction, appsState, desktopState, themeState, 'RIGHT'),
              _buildGestureTile('2-Finger Swipe UP', 'Swipe up using two fingers', Icons.swipe_up_alt, isDark, desktopState.gestureTwoFingerUpAction, appsState, desktopState, themeState, '2_UP'),
              _buildGestureTile('2-Finger Swipe DOWN', 'Swipe down using two fingers', Icons.swipe_down_alt, isDark, desktopState.gestureTwoFingerDownAction, appsState, desktopState, themeState, '2_DOWN'),
            ],
          ),
        ],
      ),
    );
  }
}