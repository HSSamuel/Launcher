import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:app_settings/app_settings.dart';

import '../../launcher_state.dart';
import 'settings_widgets.dart';
import 'settings_system_screens.dart';
import 'settings_bluetooth_view.dart';
import 'settings_network_view.dart';
import 'settings_personalization_screens.dart';
import 'settings_gestures_view.dart';
import 'settings_apps_view.dart';
import 'settings_accounts_view.dart'; 
import 'settings_time_language_view.dart'; 
import 'settings_accessibility_view.dart'; 
import 'settings_privacy_security_view.dart'; 
import 'settings_update_view.dart'; 

class SettingsApp extends StatefulWidget {
  const SettingsApp({Key? key}) : super(key: key);
  @override
  State<SettingsApp> createState() => _SettingsAppState();
}

class _SettingsAppState extends State<SettingsApp> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0; 

  final List<Map<String, dynamic>> _categories = [
    {'title': 'System', 'icon': Icons.laptop, 'color': Colors.blue},
    {'title': 'Bluetooth & devices', 'icon': Icons.bluetooth, 'color': Colors.blueAccent},
    {'title': 'Network & Internet', 'icon': Icons.wifi, 'color': Colors.blue.shade700},
    {'title': 'Personalization', 'icon': Icons.brush, 'color': Colors.orange.shade400},
    {'title': 'Gestures', 'icon': Icons.touch_app, 'color': Colors.lightBlue},
    {'title': 'Apps', 'icon': Icons.grid_view, 'color': Colors.grey.shade600},
    {'title': 'Accounts', 'icon': Icons.person, 'color': Colors.teal.shade400},
    {'title': 'Time & language', 'icon': Icons.language, 'color': Colors.blue},
    {'title': 'Accessibility', 'icon': Icons.accessibility_new, 'color': Colors.lightBlueAccent.shade400},
    {'title': 'Privacy & security', 'icon': Icons.security, 'color': Colors.grey.shade700},
    {'title': 'Launcher Update', 'icon': Icons.sync, 'color': Colors.lightBlueAccent},
  ];

  Widget _buildSystemView() {
    return Column(
      children: [
        SettingsCard(title: 'Display', subtitle: 'Monitors, brightness, night light, display profile', icon: Icons.desktop_windows_outlined, trailing: const SizedBox.shrink(), onTap: () => AppSettings.openAppSettings(type: AppSettingsType.display)),
        SettingsCard(title: 'Sound', subtitle: 'Volume levels, output, input, sound device', icon: Icons.volume_up_outlined, trailing: const SizedBox.shrink(), onTap: () => AppSettings.openAppSettings(type: AppSettingsType.sound)),
        SettingsCard(title: 'Notifications', subtitle: 'Alerts from apps and system', icon: Icons.notifications_none, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
        SettingsCard(title: 'Recent apps', subtitle: 'Most used apps and games', icon: Icons.filter_none, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecentAppsScreen()))),
        SettingsCard(title: 'Power & battery', subtitle: 'Sleep, battery usage, battery saver', icon: Icons.power_settings_new, trailing: const SizedBox.shrink(), onTap: () => AppSettings.openAppSettings(type: AppSettingsType.batteryOptimization)),
        SettingsCard(title: 'Activation', subtitle: 'Activation state, in app purchases, product key', icon: Icons.check_circle_outline, onTap: () {}),
        SettingsCard(title: 'About', subtitle: 'Device specifications, rename PC, Launcher specification', icon: Icons.info_outline, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()))),
        SettingsCard(title: 'Device Support', subtitle: 'Report a bug, request new features and more', icon: Icons.devices, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceSupportScreen()))),
      ],
    );
  }

  Widget _buildPersonalizationView(bool isCompact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(title: 'Background', subtitle: 'Background image, folder, slideshow', icon: Icons.image_outlined, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackgroundScreen()))),
        SettingsCard(title: 'Themes', subtitle: 'Install, create, manage', icon: Icons.color_lens_outlined, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemesScreen()))),
        SettingsCard(title: 'Start', subtitle: 'Recent apps and items, folders', icon: Icons.apps_outage, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StartSettingsScreen()))),
        SettingsCard(title: 'Search', subtitle: 'Manage search types, indexing', icon: Icons.search, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()))),
        SettingsCard(title: 'Taskbar', subtitle: 'Taskbar behaviours, system pin', icon: Icons.border_bottom, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskbarScreen()))),
        SettingsCard(title: 'Desktop', subtitle: 'Icon size, double tap to sleep', icon: Icons.desktop_windows_outlined, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DesktopSettingsScreen()))),
        SettingsCard(title: 'File manager', subtitle: 'Manage files, view styles', icon: Icons.snippet_folder_outlined, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FileManagerScreen()))),
      ],
    );
  }

  Widget _buildActiveContent(bool isCompact) {
    switch (_selectedIndex) {
      case 0: return _buildSystemView();
      case 1: return const SettingsBluetoothView(); 
      case 2: return const SettingsNetworkView(); 
      case 3: return _buildPersonalizationView(isCompact);
      case 4: return const SettingsGesturesView(); 
      case 5: return const SettingsAppsView(); 
      case 6: return const SettingsAccountsView();
      case 7: return const SettingsTimeLanguageView(); 
      case 8: return const SettingsAccessibilityView();
      case 9: return const SettingsPrivacySecurityView(); 
      case 10: return const SettingsUpdateView(); 
      default: return _buildSystemView();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    
    final backgroundColor = isDark ? const Color(0xFF191919) : const Color(0xFFF3F3F3);
    final drawerBg = isDark ? const Color(0xFF202020) : const Color(0xFFF9F9F9);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final searchBg = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade400;
    final selectedTileColor = isDark ? Colors.white10 : const Color(0xFFE2E2E2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        return Scaffold(
          key: _scaffoldKey, backgroundColor: backgroundColor, 
          appBar: AppBar(
            systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark, 
            backgroundColor: backgroundColor, surfaceTintColor: Colors.transparent, elevation: 0,
            leading: IconButton(icon: Icon(Icons.menu, color: textColor, size: 26), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
            title: Text(_categories[_selectedIndex]['title'], style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          drawer: Drawer(
            width: isCompact ? constraints.maxWidth * 0.75 : 320, backgroundColor: drawerBg, 
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
                  child: Row(
                    children: [
                      Container(
                        width: 56, height: 56, decoration: BoxDecoration(color: Colors.blueAccent.shade100, shape: BoxShape.circle),
                        child: state.userImageBytes != null ? ClipOval(child: Image.memory(state.userImageBytes!, fit: BoxFit.cover)) : const Icon(Icons.person, size: 32, color: Colors.white),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(state.userName.toUpperCase(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            // UPDATED: Now dynamically reads from LauncherState
                            Text(state.userEmail, style: TextStyle(fontSize: 12, color: subTextColor), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: TextField(
                    style: TextStyle(fontSize: 13, color: textColor),
                    decoration: InputDecoration(
                      isDense: true, hintText: 'Find a setting', hintStyle: TextStyle(fontSize: 13, color: subTextColor), filled: true, fillColor: searchBg, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.blueAccent)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.zero, physics: const BouncingScrollPhysics(), itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final isSelected = _selectedIndex == index;
                      return InkWell(
                        onTap: () { setState(() => _selectedIndex = index); Navigator.pop(context); },
                        child: Container(
                          decoration: BoxDecoration(color: isSelected ? selectedTileColor : Colors.transparent, border: Border(left: BorderSide(color: isSelected ? Colors.blueAccent : Colors.transparent, width: 4))),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          child: Row(
                            children: [
                              Icon(category['icon'], size: 20, color: category['color']), const SizedBox(width: 16),
                              Expanded(child: Text(category['title'], style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, color: textColor), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          body: SingleChildScrollView(physics: const BouncingScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: _buildActiveContent(isCompact)),
        );
      },
    );
  }
}