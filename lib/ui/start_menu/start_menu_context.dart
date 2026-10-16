import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import '../../states/theme_state.dart';
import '../../states/apps_state.dart';
import '../../states/desktop_state.dart';
import '../../states/system_state.dart';
import '../../services/native_bridge.dart';
import '../../main.dart'; // CRITICAL FIX: Imported to access the global navigatorKey

class _MenuOption {
  final String id;
  final IconData icon;
  final String label;
  final Color? iconColor;

  _MenuOption(this.id, this.icon, this.label, {this.iconColor});
}

class StartMenuContext {
  static void showAccessibilityPrompt(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        title: Text(
          'Accessibility Service Required', 
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)
        ),
        content: SingleChildScrollView(
          child: Text(
            "Win11 PC Launcher uses the AccessibilityService API to enable core launcher functionalities without requiring root access. Specifically, this allows you to:\n\n"
            "• Open the system Power Menu\n"
            "• Expand the Notification Panel\n"
            "• Access Recent Apps / Task View\n\n"
            "Privacy Promise: This permission is used strictly for system navigation. We do not collect, monitor, store, or share any personal data, screen content, or keystrokes.\n\n"
            "To proceed:\n"
            "1. Tap 'Go to Settings'\n"
            "2. Select 'Downloaded Apps'\n"
            "3. Turn ON 'Win11 PC Launcher'", 
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13, height: 1.4)
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))
          ),
          TextButton(
            onPressed: () { 
              Navigator.pop(ctx); 
              NativeBridge.instance.openSettings('accessibility'); 
            }, 
            child: const Text('Go to Settings', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }

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
    Size size,
    bool isDark,
    VoidCallback onOverlaysClosed,
    VoidCallback onPowerTapped
  ) {
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final screenSize = MediaQuery.of(context).size;

    final safeY = math.max(0.0, position.dy - 170);
    final rightEdge = screenSize.width - (position.dx + size.width);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(screenSize.width, safeY, rightEdge, 0),
      color: bgColor, 
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6), 
        side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)
      ),
      items: <PopupMenuEntry<String>>[
        buildCompactMenuItem('change_launcher', Icons.home_outlined, 'Change Launcher', textColor),
        buildCompactMenuItem('sleep', Icons.bedtime_outlined, 'Sleep', textColor),
        buildCompactMenuItem('shutdown', Icons.power_settings_new, 'Shut down', textColor),
        buildCompactMenuItem('restart', Icons.restart_alt, 'Restart', textColor),
      ],
    ).then((value) async {
      if (value == null) return;
      onOverlaysClosed();
      
      switch (value) {
        case 'change_launcher':
          NativeBridge.instance.openSettings('home');
          break;
        case 'sleep':
          NativeBridge.instance.lockScreen(); 
          onPowerTapped();
          break;
        case 'shutdown':
          // Attempt to open Android System Power Dialog
          final success = await NativeBridge.instance.showPowerDialog(); 
          if (!success) { 
            // CRITICAL FIX: Use the guaranteed global navigator context instead of the volatile overlay context
            final safeContext = navigatorKey.currentContext;
            if (safeContext != null) {
              showAccessibilityPrompt(safeContext, isDark); 
            }
          }
          break;
        case 'restart':
          // CRITICAL FIX: Restart the launcher OS instead of triggering a system reboot intent
          NativeBridge.instance.restartApp();
          break;
      }
    });
  }

  static void showAppContextMenu(
    BuildContext context, 
    Offset position, 
    Size size,
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

    List<_MenuOption> options = [
      _MenuOption('open', Icons.open_in_new, 'Open'),
    ];

    if (insideCategory != null) {
      options.add(_MenuOption('remove_from_cat', Icons.folder_delete_outlined, 'Remove from Folder'));
    }

    if (isPinnedSection) {
      options.addAll([
        _MenuOption('unpin', Icons.push_pin_outlined, 'Unpin from Start'),
        _MenuOption('uninstall', Icons.delete_outline, 'Uninstall'),
      ]);
    } else {
      options.addAll([
        _MenuOption('pin_start', isPinnedToStart ? Icons.push_pin_outlined : Icons.push_pin, isPinnedToStart ? 'Unpin from Start' : 'Pin to Start'),
        _MenuOption('pin_desktop', isOnDesktop ? Icons.desktop_access_disabled : Icons.desktop_windows, isOnDesktop ? 'Remove from Desktop' : 'Add to Desktop'),
        _MenuOption('uninstall', Icons.delete_outline, 'Uninstall'),
      ]);
    }

    List<PopupMenuEntry<String>> menuItems = options.map<PopupMenuEntry<String>>((opt) => 
       buildCompactMenuItem(opt.id, opt.icon, opt.label, textColor, iconColor: opt.iconColor)
    ).toList();

    menuItems.addAll([
      const PopupMenuDivider(height: 1),
      buildCompactMenuItem('settings', Icons.settings_applications, 'App settings', textColor),
    ]);

    final screenSize = MediaQuery.of(context).size;
    final targetRect = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(targetRect, Offset.zero & screenSize),
      color: bgColor, 
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6), 
        side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)
      ),
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