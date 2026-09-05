import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../launcher_state.dart';
import 'settings_widgets.dart';
import '../../services/native_bridge.dart';

// ==========================================
// 1. NOTIFICATIONS SCREEN
// ==========================================
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _hasListenerPermission = true;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    try {
      final statuses = await NativeBridge.instance.getPermissionStatuses();
      if (mounted && statuses.containsKey('notificationListener')) {
        setState(() {
          _hasListenerPermission = statuses['notificationListener'] == true;
        });
      }
    } catch (_) {}
  }

  void _showAppExclusionDialog(BuildContext context, LauncherState state) {
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final apps = state.installedApps;
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
                        final isExcluded = state.excludedNotificationPkgs.contains(app.packageName);

                        return SwitchListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          secondary: SizedBox(
                            width: 28,
                            height: 28,
                            child: app.icon != null
                                ? Image.memory(app.icon!, fit: BoxFit.contain)
                                : const Icon(Icons.android, color: Colors.green, size: 24),
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
                          activeColor: state.currentAccentColor,
                          onChanged: (val) {
                            state.toggleAppNotificationExclusion(app.packageName!);
                            setDialogState(() {});
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Done', style: TextStyle(color: state.currentAccentColor, fontWeight: FontWeight.bold)),
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
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    final accent = state.currentAccentColor;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'System > Notifications'),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        physics: const BouncingScrollPhysics(),
        children: [
          // Native Warning if Android Permission is Revoked
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

          // Lock Screen & Privacy
          _buildSectionHeader('Lock Screen & Privacy', isDark),
          SettingsCard(
            title: 'Show on Lock Screen',
            subtitle: 'Display incoming message banners on the Windows lock screen',
            icon: Icons.lock_outline,
            trailing: Switch(
              value: state.notifShowOnLockScreen,
              activeColor: accent,
              onChanged: (val) => state.updateNotificationSetting('notifShowOnLockScreen', val),
            ),
          ),
          SettingsCard(
            title: 'Play notification sound',
            subtitle: 'Allow system alert tones for incoming notifications',
            icon: Icons.volume_up_outlined,
            trailing: Switch(
              value: state.notifPlaySound,
              activeColor: accent,
              onChanged: (val) => state.updateNotificationSetting('notifPlaySound', val),
            ),
          ),

          // Panel Actions
          _buildSectionHeader('Notification Panel Actions', isDark),
          SettingsCard(
            title: 'Clear when opening notification',
            subtitle: 'Automatically dismiss the item from tray once tapped',
            icon: Icons.playlist_remove_outlined,
            trailing: Switch(
              value: state.notifClearOnOpen,
              activeColor: accent,
              onChanged: (val) => state.updateNotificationSetting('notifClearOnOpen', val),
            ),
          ),
          SettingsCard(
            title: 'Close panel when opening notification',
            subtitle: 'Collapse the notification tray and switch directly to the app',
            icon: Icons.vertical_align_bottom_outlined,
            trailing: Switch(
              value: state.notifClosePanelOnOpen,
              activeColor: accent,
              onChanged: (val) => state.updateNotificationSetting('notifClosePanelOnOpen', val),
            ),
          ),

          // App Permissions
          _buildSectionHeader('App Permissions', isDark),
          SettingsCard(
            title: 'Excluded apps',
            subtitle: state.excludedNotificationPkgs.isEmpty
                ? 'All apps permitted to post notifications'
                : '${state.excludedNotificationPkgs.length} app(s) muted from panel',
            icon: Icons.notifications_off_outlined,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.excludedNotificationPkgs.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${state.excludedNotificationPkgs.length}',
                      style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ],
            ),
            onTap: () => _showAppExclusionDialog(context, state),
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
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    final valueColor = isDark ? Colors.white70 : Colors.black54;
    final trackColor = isDark ? Colors.white24 : Colors.grey.shade300;
    final accent = state.currentAccentColor;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'System > Recent apps'),
      body: ListView(
        padding: const EdgeInsets.all(12), physics: const BouncingScrollPhysics(),
        children: [
          SettingsCard(
            title: 'Recent apps', subtitle: 'Show recently opened applications in Start Menu', icon: Icons.filter_none,
            trailing: Switch(value: enableRecentApps, activeColor: accent, onChanged: (val) => setState(() => enableRecentApps = val)),
          ),
          SettingsCard(
            title: 'Max apps to show', subtitle: 'Number of items to log in recent apps', icon: Icons.linear_scale,
            trailing: Text(maxApps.toInt().toString(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor)),
          ),
          Slider(value: maxApps, min: 0, max: 50, divisions: 50, activeColor: accent, inactiveColor: trackColor, onChanged: (val) => setState(() => maxApps = val)),
          const SizedBox(height: 10),
          SettingsCard(
            title: 'Grid count horizontally', subtitle: 'Change this to increase or decrease icons count horizontally', icon: Icons.grid_4x4,
            trailing: Text(gridCount.toInt().toString(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor)),
          ),
          Slider(value: gridCount, min: 1, max: 7, divisions: 6, activeColor: accent, inactiveColor: trackColor, onChanged: (val) => setState(() => gridCount = val)),
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
  bool _isDeviceExpanded = true; 
  bool _isLauncherExpanded = true;
  
  String deviceName = "Loading...";
  String androidVersion = "...";
  String buildNumber = "...";
  String model = "...";
  String processor = "...";
  String screenRes = "...";
  String totalStorage = "...";
  String freeStorage = "...";
  
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
            tGB = stats['total']! / (1024 * 1024 * 1024);
            fGB = stats['free']! / (1024 * 1024 * 1024);
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
            
            if (tGB > 0) {
              totalStorage = "${tGB.toStringAsFixed(2)} GB";
              freeStorage = "${fGB.toStringAsFixed(2)} GB";
            }
          });
        }
      }
    } catch (_) {}
  }

  Widget _buildExpandableCard({required String title, required String subtitle, required IconData icon, required bool isExpanded, required VoidCallback onToggle, required Widget children, required bool isDark}) {
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade300;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.grey.shade700;
    final iconColor = isDark ? Colors.white70 : Colors.black54;

    return Container(
      margin: const EdgeInsets.only(bottom: 10), 
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6), border: Border.all(color: borderColor, width: 0.8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle, borderRadius: BorderRadius.circular(6),
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
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130, 
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: labelColor))
          ),
          Expanded(child: Text(value, style: TextStyle(fontSize: 12, color: valueColor))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    final size = MediaQuery.of(context).size;
    final ratio = MediaQuery.of(context).devicePixelRatio;
    screenRes = '${(size.width * ratio).toInt()} x ${(size.height * ratio).toInt()}';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'System > About'),
      body: ListView(
        padding: const EdgeInsets.all(12), physics: const BouncingScrollPhysics(),
        children: [
          // Windows 11 "This PC" Header
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              children: [
                Icon(Icons.computer, size: 48, color: state.currentAccentColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(deviceName, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
                      Text('Windows 11 Launcher', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54)),
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
              padding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
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
              padding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('Edition', 'Windows 11 Launcher', isDark),
                  _buildInfoRow('Version', launcherVersion, isDark),
                  _buildInfoRow('OS build', launcherBuild, isDark),
                  _buildInfoRow('Android core', 'v$androidVersion (API $buildNumber)', isDark),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          SettingsCard(title: 'Privacy Policy', subtitle: 'View the latest privacy policy.', icon: Icons.privacy_tip_outlined, onTap: () {}),
          SettingsCard(title: 'FAQ', subtitle: 'All frequently asked questions answered here.', icon: Icons.chat_bubble_outline, onTap: () {}),
          SettingsCard(title: 'Rate us on Google Play', subtitle: 'Your feedback matters to us', icon: Icons.star_border, onTap: () {}),
          SettingsCard(title: 'Share us', subtitle: 'Share Windows 11 Launcher easily with your loved ones', icon: Icons.share, onTap: () {}),
          const SizedBox(height: 12),
          SettingsCard(title: 'Reset launcher', subtitle: 'Tap to reset Windows 11 Launcher. Resetting will\nremove all modified settings.', icon: Icons.refresh, trailing: const SizedBox.shrink(), onTap: () {}),
          SettingsCard(title: 'Uninstall launcher', subtitle: 'Uninstall Windows 11 Launcher.', icon: Icons.delete_outline, trailing: const SizedBox.shrink(), onTap: () {}),
        ],
      ),
    );
  }
}

// ==========================================
// 4. DEVICE SUPPORT SCREEN
// ==========================================
class DeviceSupportScreen extends StatelessWidget {
  const DeviceSupportScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'System > Device Support'),
      body: ListView(
        padding: const EdgeInsets.all(12), physics: const BouncingScrollPhysics(),
        children: [
          SettingsCard(title: 'Request new features', subtitle: 'If you have some cool suggestions for new\nfeatures, use this to suggest.', icon: Icons.note_add_outlined, trailing: const SizedBox.shrink(), onTap: () {}),
          SettingsCard(title: 'Request assist', subtitle: 'Email us your problem and if we will try to fix that\nasap.', icon: Icons.support_agent, trailing: const SizedBox.shrink(), onTap: () {}),
          SettingsCard(title: 'Report a bug', subtitle: 'Use this if you want to report a bug.', icon: Icons.bug_report_outlined, trailing: const SizedBox.shrink(), onTap: () {}),
        ],
      ),
    );
  }
}