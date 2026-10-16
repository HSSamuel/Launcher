import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:installed_apps/app_info.dart';
import 'package:path_provider/path_provider.dart';
import 'package:app_settings/app_settings.dart'; 

import '../../states/system_state.dart';
import '../../states/theme_state.dart';
import '../../states/apps_state.dart';
import '../../services/lazy_app_icon.dart';
import 'settings_widgets.dart';
import '../../services/native_bridge.dart';
import '../../services/pro_gatekeeper.dart'; 
import 'settings_personalization_screens.dart'; 
import 'settings_activation_screen.dart';
import 'settings_backup_screen.dart';

class SupportConfig {
  static const String supportPhone = "2348084737049";
  static const String supportEmail = "smkmayomisamuel@gmail.com";
}

// ==========================================
// 0. SYSTEM VIEW SCREEN (Main Menu Tab)
// ==========================================
class SystemViewScreen extends StatelessWidget {
  final BuildContext innerContext;
  const SystemViewScreen({Key? key, required this.innerContext}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          SettingsCard(title: 'Default Launcher', subtitle: 'Set this application as your primary home screen', icon: Icons.home_filled, trailing: const SizedBox.shrink(), onTap: () => NativeBridge.instance.openSettings('home')),
          SettingsCard(title: 'Display', subtitle: 'Monitors, brightness, night light, display profile', icon: Icons.desktop_windows_outlined, trailing: const SizedBox.shrink(), onTap: () => AppSettings.openAppSettings(type: AppSettingsType.display)),
          
          SettingsCard(
            title: 'Sound', 
            subtitle: 'Volume levels, output, input, sound device', 
            icon: Icons.volume_up_outlined, 
            onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const SoundSettingsScreen()))
          ),
          
          SettingsCard(title: 'Notifications', subtitle: 'Alerts from apps and system', icon: Icons.notifications_none, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
          SettingsCard(title: 'Recent apps', subtitle: 'Most used apps and games', icon: Icons.filter_none, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const RecentAppsScreen()))),
          SettingsCard(title: 'Power & battery', subtitle: 'Sleep, battery usage, battery saver', icon: Icons.power_settings_new, trailing: const SizedBox.shrink(), onTap: () => AppSettings.openAppSettings(type: AppSettingsType.batteryOptimization)),
          SettingsCard(title: 'Backup & Restore', subtitle: 'Save or load your launcher layout and preferences', icon: Icons.save_alt, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const BackupRestoreScreen()))),
          SettingsCard(title: 'Activation', subtitle: 'Activation state, in app purchases, product key', icon: Icons.check_circle_outline, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const ActivationScreen()))),
          SettingsCard(title: 'About', subtitle: 'Device specifications, rename PC, Launcher specification', icon: Icons.info_outline, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const AboutScreen()))),
          SettingsCard(title: 'Device Support', subtitle: 'Report a bug, request new features and more', icon: Icons.devices, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const DeviceSupportScreen()))),
        ],
      ),
    );
  }
}

// ==========================================
// 1. NOTIFICATIONS SCREEN
// ==========================================
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> with WidgetsBindingObserver {
  bool _hasListenerPermission = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    try {
      final statuses = await NativeBridge.instance.getPermissionStatuses();
      if (mounted && statuses.containsKey('notification')) {
        setState(() {
          _hasListenerPermission = statuses['notification'] == true;
        });
      }
    } catch (_) {}
  }

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

  void _showAppExclusionDialog(BuildContext context, SystemState systemState, AppsState appsState, ThemeState themeState) {
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final apps = appsState.installedApps;
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            title: Text(
              'Exclude App Notifications',
              style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: 320,
              height: 400,
              child: apps.isEmpty
                  ? Center(
                      child: Text(
                        'No apps found',
                        style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: apps.length,
                      itemBuilder: (context, index) {
                        final app = apps[index];
                        final isExcluded = systemState.excludedNotificationPkgs.contains(app.packageName);

                        return SwitchListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          secondary: SizedBox(
                            width: 28,
                            height: 28,
                            child: _buildAppIcon(app, 28, themeState),
                          ),
                          title: Text(
                            app.name ?? 'App',
                            style: TextStyle(color: textColor, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            isExcluded ? 'Blocked in tray' : 'Allowed',
                            style: TextStyle(
                              color: isExcluded ? Colors.redAccent : (isDark ? Colors.white54 : Colors.black54),
                              fontSize: 11,
                            ),
                          ),
                          value: !isExcluded,
                          activeColor: themeState.currentAccentColor,
                          onChanged: (val) {
                            systemState.toggleAppNotificationExclusion(app.packageName!);
                            setDialogState(() {});
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Done', style: TextStyle(color: themeState.currentAccentColor, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, top: 18.0, bottom: 6.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white70 : Colors.black87,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final systemState = context.watch<SystemState>();
    final appsState = context.watch<AppsState>();
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final accent = themeState.currentAccentColor;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'System > Notifications'),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        physics: const BouncingScrollPhysics(),
        children: [
          if (!_hasListenerPermission)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade700, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Notification access required',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Allow the launcher to read notifications so they sync with the taskbar panel.',
                          style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white70 : Colors.black87),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await NativeBridge.instance.openSettings('notification_listener');
                      _checkPermission();
                    },
                    child: Text('Enable', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

          _buildSectionHeader('Lock Screen & Privacy', isDark),
          SettingsCard(
            title: 'Show on Lock Screen',
            subtitle: 'Display incoming message banners on the Windows lock screen',
            icon: Icons.lock_outline,
            trailing: Switch(
              value: systemState.notifShowOnLockScreen,
              activeColor: accent,
              onChanged: (val) => systemState.updateNotificationSetting('notifShowOnLockScreen', val),
            ),
          ),
          SettingsCard(
            title: 'Play notification sound',
            subtitle: 'Allow system alert tones for incoming notifications',
            icon: Icons.volume_up_outlined,
            trailing: Switch(
              value: systemState.notifPlaySound,
              activeColor: accent,
              onChanged: (val) => systemState.updateNotificationSetting('notifPlaySound', val),
            ),
          ),

          _buildSectionHeader('Notification Panel Actions', isDark),
          SettingsCard(
            title: 'Clear when opening notification',
            subtitle: 'Automatically dismiss the item from tray once tapped',
            icon: Icons.playlist_remove_outlined,
            trailing: Switch(
              value: systemState.notifClearOnOpen,
              activeColor: accent,
              onChanged: (val) => systemState.updateNotificationSetting('notifClearOnOpen', val),
            ),
          ),
          SettingsCard(
            title: 'Close panel when opening notification',
            subtitle: 'Collapse the notification tray and switch directly to the app',
            icon: Icons.vertical_align_bottom_outlined,
            trailing: Switch(
              value: systemState.notifClosePanelOnOpen,
              activeColor: accent,
              onChanged: (val) => systemState.updateNotificationSetting('notifClosePanelOnOpen', val),
            ),
          ),

          _buildSectionHeader('App Permissions', isDark),
          SettingsCard(
            title: 'Excluded apps',
            subtitle: systemState.excludedNotificationPkgs.isEmpty
                ? 'All apps permitted to post notifications'
                : '${systemState.excludedNotificationPkgs.length} app(s) muted from panel',
            icon: Icons.notifications_off_outlined,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (systemState.excludedNotificationPkgs.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${systemState.excludedNotificationPkgs.length}',
                      style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ],
            ),
            onTap: () => _showAppExclusionDialog(context, systemState, appsState, themeState),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 2. RECENT APPS SCREEN
// ==========================================
class RecentAppsScreen extends StatefulWidget {
  const RecentAppsScreen({Key? key}) : super(key: key);
  @override
  State<RecentAppsScreen> createState() => _RecentAppsScreenState();
}

class _RecentAppsScreenState extends State<RecentAppsScreen> {
  bool enableRecentApps = true;
  double maxApps = 20;
  double gridCount = 5;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      enableRecentApps = prefs.getBool('enableRecentApps') ?? true;
      maxApps = (prefs.getInt('maxRecentApps') ?? 20).toDouble();
      gridCount = (prefs.getInt('recentAppsGridCount') ?? 5).toDouble();
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is int) await prefs.setInt(key, value);
  }

  Widget _buildConfigCard({required String title, required String subtitle, required IconData icon, required Widget trailing, Widget? bottom}) {
    final isDark = context.read<ThemeState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade300;
    final iconColor = isDark ? Colors.white70 : Colors.black54;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.grey.shade600;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 0.8),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 24, color: iconColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: titleColor)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(fontSize: 11, color: subColor)),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
          ),
          if (bottom != null) bottom,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final valueColor = isDark ? Colors.white70 : Colors.black54;
    final trackColor = isDark ? Colors.white24 : Colors.grey.shade300;
    final accent = themeState.currentAccentColor;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'System > Recent apps'),
      body: ListView(
        padding: const EdgeInsets.all(16), 
        physics: const BouncingScrollPhysics(),
        children: [
          _buildConfigCard(
            title: 'Recent apps', 
            subtitle: 'Show recently opened applications in Start\nMenu', 
            icon: Icons.filter_none,
            trailing: Switch(
              value: enableRecentApps, 
              activeColor: accent, 
              onChanged: (val) {
                setState(() => enableRecentApps = val);
                _saveSetting('enableRecentApps', val);
              }
            ),
          ),
          
          _buildConfigCard(
            title: 'Max apps to show', 
            subtitle: 'Number of items to log in recent apps', 
            icon: Icons.linear_scale,
            trailing: Text(maxApps.toInt().toString(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor)),
            bottom: Padding(
              padding: const EdgeInsets.only(bottom: 8.0, left: 8.0, right: 8.0),
              child: Slider(
                value: maxApps, 
                min: 0, 
                max: 50, 
                divisions: 50, 
                activeColor: accent, 
                inactiveColor: trackColor, 
                onChanged: (val) {
                  setState(() => maxApps = val);
                },
                onChangeEnd: (val) {
                  _saveSetting('maxRecentApps', val.toInt());
                }
              ),
            ),
          ),
          
          _buildConfigCard(
            title: 'Grid count horizontally', 
            subtitle: 'Change this to increase or decrease icons count\nhorizontally', 
            icon: Icons.grid_4x4,
            trailing: Text(gridCount.toInt().toString(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor)),
            bottom: Padding(
              padding: const EdgeInsets.only(bottom: 8.0, left: 8.0, right: 8.0),
              child: Slider(
                value: gridCount, 
                min: 1, 
                max: 7, 
                divisions: 6, 
                activeColor: accent, 
                inactiveColor: trackColor, 
                onChanged: (val) {
                  setState(() => gridCount = val);
                },
                onChangeEnd: (val) {
                  _saveSetting('recentAppsGridCount', val.toInt());
                }
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 3. ABOUT SCREEN
// ==========================================
class AboutScreen extends StatefulWidget {
  const AboutScreen({Key? key}) : super(key: key);
  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  bool _isDeviceExpanded = false; 
  bool _isLauncherExpanded = false;
  
  String deviceName = "Loading...";
  String androidVersion = "...";
  String buildNumber = "...";
  String model = "...";
  String processor = "...";
  String screenRes = "...";
  String totalStorage = "...";
  String freeStorage = "...";
  String packageName = "com.samuel.winlauncher";
  
  String launcherVersion = "...";
  String launcherBuild = "...";

  @override
  void initState() {
    super.initState();
    _fetchAuthenticSystemInfo();
  }

  Future<void> _fetchAuthenticSystemInfo() async {
    try {
      if (!kIsWeb) {
        DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        PackageInfo packageInfo = await PackageInfo.fromPlatform();

        double tGB = 0;
        double fGB = 0;
        try {
          final stats = await NativeBridge.instance.getStorageStats();
          if (stats != null) {
            tGB = (stats['total'] ?? 0.0) / (1024 * 1024 * 1024);
            fGB = (stats['free'] ?? 0.0) / (1024 * 1024 * 1024);
          }
        } catch (_) {}

        if (mounted) {
          setState(() {
            deviceName = androidInfo.model;
            androidVersion = androidInfo.version.release;
            buildNumber = androidInfo.version.sdkInt.toString();
            model = androidInfo.model;
            processor = androidInfo.hardware;
            launcherVersion = packageInfo.version;
            launcherBuild = packageInfo.buildNumber;
            packageName = packageInfo.packageName;
            
            if (tGB > 0) {
              totalStorage = "${tGB.toStringAsFixed(2)} GB";
              freeStorage = "${fGB.toStringAsFixed(2)} GB";
            }
          });
        }
      }
    } catch (_) {}
  }

  void _showResetDialog(BuildContext context, ThemeState themeState) {
    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Reset Launcher?', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'This will permanently delete your custom settings, layouts, and data. The app will restart.',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              
              final storage = const FlutterSecureStorage();
              await storage.deleteAll();
              
              try {
                final dir = await getApplicationDocumentsDirectory();
                final files = dir.listSync();
                for (var file in files) {
                  if (file is File && (file.path.contains('custom_wall_') || file.path.contains('custom_start_') || file.path.contains('profile_pic'))) {
                    file.deleteSync();
                  }
                }
              } catch (_) {}
              
              // CRITICAL FIX: Restart the JVM completely rather than merely popping the UI stack
              NativeBridge.instance.restartApp();
            }, 
            child: const Text('Reset', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
          ),
        ],
      )
    );
  }

  void _showUninstallDialog(BuildContext context, ThemeState themeState) async {
    // CRITICAL FIX: Intercept Uninstallation if Device Admin is strictly active
    final statuses = await NativeBridge.instance.getPermissionStatuses();
    final isAdminActive = statuses['admin'] == true;
    
    if (!context.mounted) return;

    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Uninstall Launcher?', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'Are you sure you want to uninstall Win11 PC Launcher from your device?\n\nNote: If this is currently set as your Default Home App, Android will block the uninstallation. Please tap "Clear Defaults" first.'
          '${isAdminActive ? '\n\nIMPORTANT: Device Administration is currently ACTIVE. Android strictly prevents uninstalling Admin applications. You MUST deactivate it below before uninstalling.' : ''}',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
        ),
        actions: [
          if (isAdminActive)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                NativeBridge.instance.openSettings('admin');
              }, 
              child: const Text('Deactivate Admin', style: TextStyle(color: Colors.orangeAccent))
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              NativeBridge.instance.openSettings('home');
            }, 
            child: Text('Clear Defaults', style: TextStyle(color: isDark ? Colors.blueAccent : Colors.blue))
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              NativeBridge.instance.uninstallApp(packageName);
            }, 
            child: const Text('Uninstall', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
          ),
        ],
      )
    );
  }

  Widget _buildExpandableCard({required String title, required String subtitle, required IconData icon, required bool isExpanded, required VoidCallback onToggle, required Widget children, required bool isDark}) {
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade300;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.grey.shade700;
    final iconColor = isDark ? Colors.white70 : Colors.black54;

    return Container(
      margin: const EdgeInsets.only(bottom: 10), 
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: borderColor, width: 0.8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle, borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), 
              child: Row(
                children: [
                  Icon(icon, size: 24, color: iconColor), const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: TextStyle(fontSize: 11, color: subTextColor)),
                      ],
                    ),
                  ),
                  Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 22, color: textColor),
                ],
              ),
            ),
          ),
          if (isExpanded) children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    final labelColor = isDark ? Colors.white : Colors.black87;
    final valueColor = isDark ? Colors.white54 : Colors.black54;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140, 
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: labelColor))
          ),
          Expanded(child: Text(value, style: TextStyle(fontSize: 12, color: valueColor))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    final size = MediaQuery.of(context).size;
    final ratio = MediaQuery.of(context).devicePixelRatio;
    screenRes = '${(size.width * ratio).toInt()} x ${(size.height * ratio).toInt()}';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'System > About'),
      body: ListView(
        padding: const EdgeInsets.all(16), physics: const BouncingScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 24, left: 4),
            child: Row(
              children: [
                Icon(Icons.computer, size: 54, color: themeState.currentAccentColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(deviceName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                      const SizedBox(height: 2),
                      Text('Win11 PC Launcher', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          _buildExpandableCard(
            title: 'Device specifications', subtitle: model, icon: Icons.phone_android,
            isExpanded: _isDeviceExpanded, onToggle: () => setState(() => _isDeviceExpanded = !_isDeviceExpanded),
            isDark: isDark,
            children: Padding(
              padding: const EdgeInsets.fromLTRB(56, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('Device name', deviceName, isDark),
                  _buildInfoRow('Processor', processor, isDark),
                  _buildInfoRow('Screen resolution', screenRes, isDark),
                  _buildInfoRow('Total Storage', totalStorage, isDark),
                  _buildInfoRow('Free Storage', freeStorage, isDark),
                ],
              ),
            ),
          ),
          _buildExpandableCard(
            title: 'Windows specifications', subtitle: 'Launcher OS details', icon: Icons.grid_view,
            isExpanded: _isLauncherExpanded, onToggle: () => setState(() => _isLauncherExpanded = !_isLauncherExpanded),
            isDark: isDark,
            children: Padding(
              padding: const EdgeInsets.fromLTRB(56, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('Edition', 'Win11 PC Launcher', isDark),
                  _buildInfoRow('Version', launcherVersion, isDark),
                  _buildInfoRow('OS build', launcherBuild, isDark),
                  _buildInfoRow('Android core', 'v$androidVersion (API $buildNumber)', isDark),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          SettingsCard(
            title: 'Privacy Policy', 
            subtitle: 'View the latest privacy policy.', 
            icon: Icons.privacy_tip_outlined, 
            onTap: () {
               NativeBridge.instance.launchApp('https://sites.google.com/view/win11-launcher-privacy/home');
            }
          ),
          SettingsCard(
            title: 'FAQ', 
            subtitle: 'All frequently asked questions answered here.', 
            icon: Icons.chat_bubble_outline, 
            onTap: () {
               Navigator.push(context, MaterialPageRoute(builder: (_) => const FAQScreen()));
            }
          ),
          SettingsCard(
            title: 'Rate us on Google Play', 
            subtitle: 'Your feedback matters to us', 
            icon: Icons.star_border, 
            onTap: () async {
               bool launched = await NativeBridge.instance.launchApp('market://details?id=$packageName');
               if (!launched) {
                  NativeBridge.instance.launchApp('https://play.google.com/store/apps/details?id=$packageName');
               }
            }
          ),
          SettingsCard(
            title: 'Share us', 
            subtitle: 'Share Win11 PC Launcher easily with your loved ones', 
            icon: Icons.share, 
            onTap: () {
               NativeBridge.instance.shareText('Check out this amazing Win11 PC Launcher for Android! Get it here: https://play.google.com/store/apps/details?id=$packageName');
            }
          ),
          const SizedBox(height: 12),
          SettingsCard(
            title: 'Reset launcher', 
            subtitle: 'Tap to reset Win11 PC Launcher. Resetting will\nremove all modified settings.', 
            icon: Icons.refresh, 
            trailing: const SizedBox.shrink(), 
            onTap: () => _showResetDialog(context, themeState)
          ),
          SettingsCard(
            title: 'Uninstall launcher', 
            subtitle: 'Uninstall Win11 PC Launcher.', 
            icon: Icons.delete_outline, 
            trailing: const SizedBox.shrink(), 
            onTap: () => _showUninstallDialog(context, themeState)
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 3.1 FAQ SCREEN 
// ==========================================
class FAQScreen extends StatefulWidget {
  const FAQScreen({Key? key}) : super(key: key);

  @override
  State<FAQScreen> createState() => _FAQScreenState();
}

class _FAQScreenState extends State<FAQScreen> {
  final List<bool> _expanded = List.generate(5, (_) => false);

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;

    final faqs = [
      {'q': 'How do I add a widget to the desktop?', 'a': 'Long-press any empty space on the desktop to open the Context Menu, then select "Add Built-in Widget" or "Add Android Widget".'},
      {'q': 'Why can\'t I uninstall system apps?', 'a': 'Android OS strictly prohibits third-party launchers from deleting core system applications.'},
      {'q': 'How do I change the desktop background?', 'a': 'Go to Settings > Personalization > Background to select a theme, start a slideshow, or pick a custom image from your gallery.'},
      {'q': 'Why does the Power Menu prompt for Accessibility?', 'a': 'To physically lock the screen or open the system power dialog without requiring Root access, Android strictly requires the Accessibility Service to act on your behalf.'},
      {'q': 'How do I resize a widget?', 'a': 'Right-click or Long-press the widget and select "Resize Widget". A bounding box with a grab handle will appear. Drag the handle to resize, and tap the checkmark when done.'}
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'System > FAQ'),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        itemCount: faqs.length,
        itemBuilder: (context, index) {
          return ExpandableSettingsCard(
            title: faqs[index]['q']!,
            icon: Icons.help_outline,
            isExpanded: _expanded[index], 
            onToggle: () {
              setState(() {
                _expanded[index] = !_expanded[index];
              });
            },
            children: Padding(
              padding: const EdgeInsets.only(left: 56, right: 16, bottom: 16),
              child: Text(
                faqs[index]['a']!,
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13, height: 1.4),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// 4. DEVICE SUPPORT SCREEN
// ==========================================
class DeviceSupportScreen extends StatelessWidget {
  const DeviceSupportScreen({Key? key}) : super(key: key);

  void _launchWhatsApp(BuildContext context) async {
    final String url = "https://wa.me/${SupportConfig.supportPhone}?text=${Uri.encodeComponent('Hello, I need some assistance with the Win11 PC Launcher.')}";
    final success = await NativeBridge.instance.launchApp(url);
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp. Please check your browser or installed apps.'))
      );
    }
  }

  void _launchEmail(String subject) {
    final String url = "mailto:${SupportConfig.supportEmail}?subject=${Uri.encodeComponent(subject)}";
    NativeBridge.instance.launchApp(url);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white54 : Colors.black54;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'System > Device Support'),
      body: ListView(
        padding: const EdgeInsets.all(12), physics: const BouncingScrollPhysics(),
        children: [
          SettingsCard(
            title: 'Request new features', 
            subtitle: 'Have a cool suggestion? Send us an email with your ideas.', 
            icon: Icons.note_add_outlined, 
            trailing: Icon(Icons.email_outlined, size: 20, color: iconColor), 
            onTap: () => _launchEmail('Feature Request: Win11 PC Launcher')
          ),
          SettingsCard(
            title: 'Request assist', 
            subtitle: 'Chat with us directly on WhatsApp for immediate support.', 
            icon: Icons.support_agent, 
            trailing: Icon(Icons.chat_outlined, size: 20, color: Colors.green.shade400), 
            onTap: () => _launchWhatsApp(context)
          ),
          SettingsCard(
            title: 'Report a bug', 
            subtitle: 'Found an issue? Email us the details and we will fix it ASAP.', 
            icon: Icons.bug_report_outlined, 
            trailing: Icon(Icons.email_outlined, size: 20, color: iconColor), 
            onTap: () => _launchEmail('Bug Report: Win11 PC Launcher')
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 5. SOUND SETTINGS SCREEN
// ==========================================
class SoundSettingsScreen extends StatelessWidget {
  const SoundSettingsScreen({Key? key}) : super(key: key);

  void _showBootAnimationDialog(BuildContext context, ThemeState themeState) {
    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accent = themeState.currentAccentColor;
    final options = ['None', 'Windows 98 Retro', 'Windows XP Bliss', 'Windows 7 Aero'];

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: bgColor,
          title: Text('Boot Animation', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) => InkWell(
              onTap: () {
                themeState.setBootAnimation(opt);
                Navigator.pop(ctx);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(child: Text(opt, style: TextStyle(color: textColor, fontSize: 14))),
                    if (themeState.bootAnimation == opt) Icon(Icons.check, color: accent, size: 18),
                  ],
                ),
              ),
            )).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)))
          ]
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'System > Sound'),
      body: ListView(
        padding: const EdgeInsets.all(16), physics: const BouncingScrollPhysics(),
        children: [
          Win11SettingsGroup(
            title: 'System Audio',
            isDark: isDark,
            children: [
              Win11SettingsTile(
                title: 'Android Sound Settings',
                subtitle: 'Volume levels, output, input, sound device',
                icon: Icons.volume_up_outlined,
                isDark: isDark,
                trailing: Icon(Icons.open_in_new, size: 20, color: textColor),
                onTap: () => NativeBridge.instance.openSettings('sound'),
              ),
            ],
          ),
          Win11SettingsGroup(
            title: 'Retro & Effects (Pro)',
            isDark: isDark,
            children: [
              Win11SettingsTile(
                title: 'Launcher Sounds',
                subtitle: 'Play classic startup and system error chimes',
                icon: Icons.speaker_group_outlined,
                isDark: isDark,
                isProLocked: true,
                trailing: Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: themeState.enableSystemSounds,
                    activeColor: themeState.currentAccentColor,
                    onChanged: (val) {
                      if (val && !ProGatekeeper.checkAccess(context, featureName: 'Retro System Sounds')) return;
                      themeState.setSystemSounds(val);
                    },
                  ),
                ),
              ),
              Win11SettingsTile(
                title: 'Boot Animation',
                subtitle: themeState.bootAnimation == 'None' ? 'Disabled' : themeState.bootAnimation,
                icon: Icons.power_settings_new,
                isDark: isDark,
                isProLocked: true,
                trailing: Icon(Icons.chevron_right, size: 20, color: textColor),
                onTap: () {
                  if (!ProGatekeeper.checkAccess(context, featureName: 'Retro Boot Animations')) return;
                  _showBootAnimationDialog(context, themeState);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}