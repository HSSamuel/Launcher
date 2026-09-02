import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_settings/app_settings.dart';
import 'settings_widgets.dart';

class SettingsAppsView extends StatelessWidget {
  const SettingsAppsView({Key? key}) : super(key: key);

  static const platform = MethodChannel('win_launcher/native');

  void _openNativeSettings(String type) async {
    try {
      // Calls the Kotlin code we wrote
      await platform.invokeMethod('openSettings', {'type': type});
    } catch (e) {
      debugPrint("Native routing failed, falling back to AppSettings: $e");
      AppSettings.openAppSettings(type: AppSettingsType.settings);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsCard(
          title: 'Apps & features',
          subtitle: 'Installed apps, system apps',
          icon: Icons.format_list_bulleted,
          onTap: () => _openNativeSettings('manage_apps'),
        ),
        SettingsCard(
          title: 'Default apps',
          subtitle: 'Defaults for file and link types, other defaults',
          icon: Icons.app_shortcut,
          onTap: () => _openNativeSettings('default_apps'),
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

// --- "Pro-Level" Optional Features Screen ---
class OptionalFeaturesScreen extends StatefulWidget {
  const OptionalFeaturesScreen({Key? key}) : super(key: key);
  @override
  State<OptionalFeaturesScreen> createState() => _OptionalFeaturesScreenState();
}

class _OptionalFeaturesScreenState extends State<OptionalFeaturesScreen> {
  bool devMode = false;
  bool windowsSubsystem = true;
  bool experimentalEngine = false;

  @override
  Widget build(BuildContext context) {
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
            subtitle: 'Enable advanced testing and debugging features',
            icon: Icons.code,
            trailing: Switch(value: devMode, activeColor: Colors.blueAccent, onChanged: (v) => setState(() => devMode = v)),
          ),
          SettingsCard(
            title: 'Windows Subsystem for Android™',
            subtitle: 'Run native Android apps seamlessly alongside Windows apps',
            icon: Icons.android,
            trailing: Switch(value: windowsSubsystem, activeColor: Colors.blueAccent, onChanged: (v) => setState(() => windowsSubsystem = v)),
          ),
          SettingsCard(
            title: 'Experimental Web Engine',
            subtitle: 'Use the latest WebView rendering engine for Edge',
            icon: Icons.public,
            trailing: Switch(value: experimentalEngine, activeColor: Colors.blueAccent, onChanged: (v) => setState(() => experimentalEngine = v)),
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
            // FIXED: Routed to security settings instead of manageUnknownAppSources
            onTap: () => AppSettings.openAppSettings(type: AppSettingsType.security),
          ),
          SettingsCard(
            title: 'Device admin apps',
            subtitle: 'Manage applications with administrative privileges',
            icon: Icons.admin_panel_settings_outlined,
            onTap: () => AppSettings.openAppSettings(type: AppSettingsType.security),
          ),
        ],
      ),
    );
  }
}