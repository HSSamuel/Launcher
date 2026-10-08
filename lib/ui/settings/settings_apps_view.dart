import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/desktop_state.dart';
import 'settings_widgets.dart';
import '../../services/native_bridge.dart';

class SettingsAppsView extends StatelessWidget {
  const SettingsAppsView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsCard(
          title: 'Apps & features',
          subtitle: 'Installed apps, system apps',
          icon: Icons.format_list_bulleted,
          // CRITICAL FIX: Try/Catch removal allows NativeBridge to safely handle fallback routing
          onTap: () => NativeBridge.instance.openSettings('manage_apps'),
        ),
        SettingsCard(
          title: 'Default apps',
          subtitle: 'Defaults for file and link types, other defaults',
          icon: Icons.app_shortcut,
          onTap: () => NativeBridge.instance.openSettings('default_apps'),
        ),
        SettingsCard(
          title: 'Optional features',
          subtitle: 'Extra functionality for your device',
          icon: Icons.add_box_outlined,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OptionalFeaturesScreen())),
        ),
      ],
    );
  }
}

class OptionalFeaturesScreen extends StatelessWidget {
  const OptionalFeaturesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final desktopState = context.watch<DesktopState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Apps > Optional features'),
      body: ListView(
        padding: const EdgeInsets.all(12),
        physics: const BouncingScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text('Installed features', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: headerColor)),
          ),
          SettingsCard(
            title: 'Developer Mode',
            subtitle: desktopState.devMode ? 'Developer mode is ON. Package names visible.' : 'Enable advanced testing and debugging features',
            icon: Icons.code,
            trailing: Switch(
              value: desktopState.devMode, 
              activeColor: Colors.blueAccent, 
              onChanged: (v) {
                 desktopState.updateDesktopSetting('devMode', v);
                 if (v) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Developer Mode Enabled. Package names now visible in Start Menu.')));
                    NativeBridge.instance.openSettings('settings');
                 }
              }
            ),
          ),
          SettingsCard(
            title: 'Windows Subsystem for Android™',
            subtitle: desktopState.windowsSubsystem ? 'WSA is running. Android apps are active.' : 'WSA is suspended. Android apps are hidden.',
            icon: Icons.android,
            trailing: Switch(
              value: desktopState.windowsSubsystem, 
              activeColor: Colors.blueAccent, 
              onChanged: (v) {
                 desktopState.updateDesktopSetting('windowsSubsystem', v);
                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(v ? 'WSA Started. Android apps restored to Start Menu.' : 'WSA Suspended. Android apps are now hidden.')));
              }
            ),
          ),
          SettingsCard(
            title: 'Experimental Web Engine',
            subtitle: desktopState.experimentalEngine ? 'Desktop User-Agent active for Edge' : 'Use the latest WebView rendering engine for Edge',
            icon: Icons.public,
            trailing: Switch(
              value: desktopState.experimentalEngine, 
              activeColor: Colors.blueAccent, 
              onChanged: (v) {
                 desktopState.updateDesktopSetting('experimentalEngine', v);
                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(v ? 'Edge will now render sites in Desktop Mode.' : 'Edge restored to Mobile rendering.')));
              }
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text('Device administration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: headerColor)),
          ),
          SettingsCard(
            title: 'Unknown app sources',
            subtitle: 'Allow installation of apps from unverified sources',
            icon: Icons.security,
            onTap: () {
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Navigate to "Install Unknown Apps" in the Security menu.')));
               NativeBridge.instance.openSettings('security');
            }
          ),
          SettingsCard(
            title: 'Device admin apps',
            subtitle: 'Manage applications with administrative privileges',
            icon: Icons.admin_panel_settings_outlined,
            onTap: () {
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Navigate to "Device Admin Apps" in the Security menu.')));
               NativeBridge.instance.openSettings('security');
            }
          ),
        ],
      ),
    );
  }
}