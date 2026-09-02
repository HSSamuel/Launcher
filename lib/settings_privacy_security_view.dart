import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsPrivacySecurityView extends StatefulWidget {
  const SettingsPrivacySecurityView({Key? key}) : super(key: key);

  @override
  State<SettingsPrivacySecurityView> createState() => _SettingsPrivacySecurityViewState();
}

class _SettingsPrivacySecurityViewState extends State<SettingsPrivacySecurityView> with WidgetsBindingObserver {
  static const platform = MethodChannel('win_launcher/native');

  bool _storageGranted = false;
  bool _notificationGranted = false;
  bool _accessibilityGranted = false;
  bool _adminGranted = false;
  bool _writeSettingsGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncNativePermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncNativePermissions();
    }
  }

  Future<void> _syncNativePermissions() async {
    try {
      final Map<dynamic, dynamic>? result = await platform.invokeMethod('getPermissionStatuses');
      if (result != null && mounted) {
        setState(() {
          _storageGranted = result['storage'] ?? false;
          _notificationGranted = result['notification'] ?? false;
          _accessibilityGranted = result['accessibility'] ?? false;
          _adminGranted = result['admin'] ?? false;
          _writeSettingsGranted = result['write_settings'] ?? false;
        });
      }
    } catch (e) {
      debugPrint("Error syncing native permissions: $e");
    }
  }

  void _openNativeSetting(String type) async {
    try {
      await platform.invokeMethod('openSettings', {'type': type});
    } catch (e) {
      debugPrint("Failed to open setting: $e");
    }
  }

  Widget _buildPermissionCard({
    required String title,
    required String subtitle,
    required IconData baseIcon,
    required bool isGranted,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade300;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.grey.shade600;
    final iconColor = isDark ? Colors.white70 : Colors.black87;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6), border: Border.all(color: borderColor, width: 0.8)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(baseIcon, size: 26, color: iconColor),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(1.5),
                        child: Icon(
                          isGranted ? Icons.check_circle : Icons.cancel,
                          size: 13,
                          color: isGranted ? Colors.green : Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(fontSize: 11, color: subTextColor)),
                      const SizedBox(height: 4),
                      Text(
                        isGranted ? 'Permission enabled' : 'Permission disabled',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isGranted ? Colors.green : Colors.redAccent.shade200,
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildPermissionCard(
          title: 'Storage',
          subtitle: 'Storage permission is required to process wallpapers,\nmanage files in file manager.',
          baseIcon: Icons.storage_outlined,
          isGranted: _storageGranted,
          onTap: () => _openNativeSetting('storage'),
        ),
        _buildPermissionCard(
          title: 'Accessibility',
          subtitle: 'Accessibility permission is required to toggle desktop\nfunctionality',
          baseIcon: Icons.accessibility_new,
          isGranted: _accessibilityGranted,
          onTap: () => _openNativeSetting('accessibility'),
        ),
        _buildPermissionCard(
          title: 'Admin',
          subtitle: 'Admin permission is required to enable lock, double tap to\nlock functionalities',
          baseIcon: Icons.manage_accounts_outlined,
          isGranted: _adminGranted,
          onTap: () => _openNativeSetting('admin'),
        ),
        _buildPermissionCard(
          title: 'Notification access',
          subtitle: 'Notification access is required to get the notifications and\ndisplay it in side panel.',
          baseIcon: Icons.notifications_active_outlined,
          isGranted: _notificationGranted,
          onTap: () => _openNativeSetting('notification_access'),
        ),
        _buildPermissionCard(
          title: 'Write Settings',
          subtitle: 'Write Settings is required for toggling shortcut tiles,\nchange system settings.',
          baseIcon: Icons.build_outlined,
          isGranted: _writeSettingsGranted,
          onTap: () => _openNativeSetting('write_settings'),
        ),
      ],
    );
  }
}