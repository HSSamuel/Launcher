import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:provider/provider.dart';
import 'launcher_state.dart';

class Win11Taskbar extends StatelessWidget {
  final bool isStartMenuOpen;
  final VoidCallback onStartToggled;
  final VoidCallback onQuickSettingsToggled;
  final VoidCallback onNotificationCenterToggled;
  final VoidCallback onOverlaysClosed;
  final int batteryLevel;
  final BatteryState batteryState;
  final int unreadNotifications;

  const Win11Taskbar({
    Key? key, required this.isStartMenuOpen, required this.onStartToggled, required this.onQuickSettingsToggled, required this.onNotificationCenterToggled, required this.onOverlaysClosed, this.batteryLevel = 100, this.batteryState = BatteryState.discharging, this.unreadNotifications = 0,
  }) : super(key: key);

  void _handleTaskbarIconClick(String appId, LauncherState state) {
    onOverlaysClosed();
    if (!state.windowStack.contains(appId)) return state.openApp(appId);
    if (state.minimizedApps.contains(appId)) { state.minimizedApps.remove(appId); state.focusWindow(appId); return; }
    if (state.windowStack.last != appId) return state.focusWindow(appId);
    state.minimizeApp(appId);
  }

  Widget _buildTaskbarIcon(Widget icon, bool isOpen, bool isActive, VoidCallback onTap, bool isDarkMode) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: isActive ? (isDarkMode ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08)) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            icon,
            if (isOpen) Positioned(bottom: 2, child: Container(width: isActive ? 14 : 6, height: 3, decoration: BoxDecoration(color: isActive ? Colors.blueAccent : Colors.grey.shade400, borderRadius: BorderRadius.circular(1.5)))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeStr = "${now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour)}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}";
    final dateStr = "${now.month}/${now.day}/${now.year}";
    
    final state = context.watch<LauncherState>();
    final isExplorerOpen = state.windowStack.contains('explorer');
    final isBrowserOpen = state.windowStack.contains('browser');
    final isCalculatorOpen = state.windowStack.contains('calculator');
    final isSettingsOpen = state.windowStack.contains('settings');
    final activeAppId = state.windowStack.isNotEmpty && !state.minimizedApps.contains(state.windowStack.last) ? state.windowStack.last : '';
    final isCentered = state.taskbarAlignment == 'center';
    
    // DYNAMIC THEME COLORS
    final taskbarColor = state.isDarkMode ? Colors.black.withOpacity(0.65) : Colors.white.withOpacity(0.85);
    final iconColor = state.isDarkMode ? Colors.white : Colors.black87;

    final appIconsRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTaskbarIcon(const Icon(Icons.window, color: Colors.blueAccent, size: 20), isStartMenuOpen, isStartMenuOpen, onStartToggled, state.isDarkMode),
          _buildTaskbarIcon(Icon(Icons.search, color: iconColor, size: 20), false, false, () {}, state.isDarkMode),
          if (isExplorerOpen) _buildTaskbarIcon(const Icon(Icons.folder, color: Colors.amber, size: 20), true, activeAppId == 'explorer', () => _handleTaskbarIconClick('explorer', state), state.isDarkMode),
          if (isBrowserOpen) _buildTaskbarIcon(const Icon(Icons.language, color: Colors.blue, size: 20), true, activeAppId == 'browser', () => _handleTaskbarIconClick('browser', state), state.isDarkMode),
          if (isCalculatorOpen) _buildTaskbarIcon(const Icon(Icons.calculate, color: Colors.grey, size: 20), true, activeAppId == 'calculator', () => _handleTaskbarIconClick('calculator', state), state.isDarkMode),
          if (isSettingsOpen) _buildTaskbarIcon(const Icon(Icons.settings, color: Colors.blueGrey, size: 20), true, activeAppId == 'settings', () => _handleTaskbarIconClick('settings', state), state.isDarkMode),
        ],
      ),
    );

    return Positioned(
      bottom: 0, left: 0, right: 0, height: 48,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            color: taskbarColor,
            padding: const EdgeInsets.symmetric(horizontal: 4), 
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!isCentered) Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(right: 140), child: appIconsRow)) else Center(child: appIconsRow),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(onTap: () {}, borderRadius: BorderRadius.circular(4), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8), child: Icon(Icons.keyboard_arrow_up, color: iconColor, size: 16))),
                      InkWell(
                        onTap: onQuickSettingsToggled, borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4),
                          child: Row(children: [Icon(Icons.wifi, color: iconColor, size: 14), const SizedBox(width: 4), Icon(Icons.volume_up, color: iconColor, size: 14), const SizedBox(width: 4), Icon(batteryState == BatteryState.charging ? Icons.battery_charging_full : Icons.battery_full, color: iconColor, size: 14)]),
                        ),
                      ),
                      InkWell(
                        onTap: onNotificationCenterToggled, borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4),
                          child: Row(
                            children: [
                              Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(timeStr, style: TextStyle(color: iconColor, fontSize: 10)), Text(dateStr, style: TextStyle(color: iconColor, fontSize: 10))]), const SizedBox(width: 6), 
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Icon(Icons.notifications_none, color: iconColor, size: 16),
                                  if (unreadNotifications > 0) Positioned(right: -2, top: -2, child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle), child: Text(unreadNotifications > 9 ? '9+' : unreadNotifications.toString(), style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold)))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}