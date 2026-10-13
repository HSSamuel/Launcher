import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import '../../states/theme_state.dart';
import '../../states/apps_state.dart';
import '../../states/desktop_state.dart';
import '../../states/system_state.dart';
import '../../services/native_bridge.dart';

class StartMenuContext {
  
  static PopupMenuItem<String> buildCompactMenuItem(String value, IconData icon, String label, Color textColor, {Color? iconColor}) {
    return PopupMenuItem<String>(
      value: value,
      height: 32, 
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor ?? textColor),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: textColor, fontSize: 13, height: 1.0)),
        ],
      ),
    );
  }

  static void showPowerMenu(
    BuildContext context, 
    Offset position, 
    bool isDark,
    VoidCallback onOverlaysClosed,
    VoidCallback onPowerTapped
  ) {
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    final safeY = math.max(0.0, position.dy - 100);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(Rect.fromLTWH(position.dx, safeY, 0, 0), Offset.zero & MediaQuery.of(context).size),
      color: bgColor, elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
      items: <PopupMenuEntry<String>>[
        buildCompactMenuItem('change_launcher', Icons.home_outlined, 'Change Launcher', textColor),
        buildCompactMenuItem('sleep', Icons.bedtime_outlined, 'Sleep', textColor),
      ],
    ).then((value) {
      if (value == null) return;
      onOverlaysClosed();
      
      if (value == 'change_launcher') {
        NativeBridge.instance.openSettings('home');
      } else if (value == 'sleep') {
        NativeBridge.instance.lockScreen(); 
        onPowerTapped();
      }
    });
  }

  static void showAppContextMenu(
    BuildContext context, 
    Offset position, 
    AppInfo app, 
    ThemeState themeState, 
    AppsState appsState, 
    DesktopState desktopState, 
    SystemState systemState,
    VoidCallback onOverlaysClosed,
    Function(String) showToast,
    int currentDesktopPage,
    {required bool isPinnedSection, String? insideCategory}
  ) {
    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final isPinnedToStart = appsState.pinnedStart.contains(app.packageName);
    final isOnDesktop = desktopState.desktopItems.any((i) => i.type == 'app' && i.package == app.packageName);

    List<PopupMenuEntry<String>> menuItems = [
      buildCompactMenuItem('open', Icons.open_in_new, 'Open', textColor),
    ];

    if (insideCategory != null) {
      menuItems.add(buildCompactMenuItem('remove_from_cat', Icons.folder_delete_outlined, 'Remove from Folder', textColor));
    }

    if (isPinnedSection) {
      menuItems.addAll([
        buildCompactMenuItem('unpin', Icons.push_pin_outlined, 'Unpin from Start', textColor),
        buildCompactMenuItem('uninstall', Icons.delete_outline, 'Uninstall', textColor),
      ]);
    } else {
      menuItems.addAll([
        buildCompactMenuItem('pin_start', isPinnedToStart ? Icons.push_pin_outlined : Icons.push_pin, isPinnedToStart ? 'Unpin from Start' : 'Pin to Start', textColor),
        buildCompactMenuItem('pin_desktop', isOnDesktop ? Icons.desktop_access_disabled : Icons.desktop_windows, isOnDesktop ? 'Remove from Desktop' : 'Add to Desktop', textColor),
        buildCompactMenuItem('uninstall', Icons.delete_outline, 'Uninstall', textColor),
      ]);
    }

    menuItems.addAll([
      const PopupMenuDivider(height: 1),
      buildCompactMenuItem('settings', Icons.settings_applications, 'App settings', textColor),
    ]);

    final safeY = math.min(position.dy, MediaQuery.of(context).size.height - 250);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(Rect.fromLTWH(position.dx, safeY, 0, 0), Offset.zero & MediaQuery.of(context).size),
      color: bgColor, elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
      items: menuItems,
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'open':
          onOverlaysClosed();
          appsState.launchNativeApp(app.packageName!, systemState: systemState);
          break;
        case 'remove_from_cat':
          appsState.removeAppFromCategory(insideCategory!, app.packageName!);
          showToast('Removed from $insideCategory');
          break;
        case 'unpin':
        case 'pin_start':
          if (value == 'pin_start' && !isPinnedToStart && appsState.pinnedStart.length >= 8) {
             showToast('Maximum of 8 apps can be pinned.');
          } else {
             appsState.togglePinToStart(app.packageName!); 
             showToast(isPinnedToStart ? 'Unpinned from Start' : 'Pinned to Start');
          }
          break;
        case 'uninstall':
          onOverlaysClosed();
          desktopState.keepOverlaysAliveNextPause = true;
          NativeBridge.instance.uninstallApp(app.packageName!);
          break;
        case 'pin_desktop':
          if (isOnDesktop) { 
            final item = desktopState.desktopItems.firstWhere((i) => i.package == app.packageName); 
            desktopState.removeDesktopItem(item.id); 
          } else { 
            desktopState.addDesktopApp(app.packageName!, app.name ?? 'App', currentDesktopPage, 0, 0); 
          } 
          showToast(isOnDesktop ? 'Removed from Desktop' : 'Added to Desktop');
          break;
        case 'settings':
          onOverlaysClosed();
          desktopState.keepOverlaysAliveNextPause = true;
          InstalledApps.openSettings(app.packageName!);
          break;
      }
    });
  }
}