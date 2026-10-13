import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:installed_apps/app_info.dart';

import '../../states/apps_state.dart';
import '../../states/system_state.dart';
import '../../states/theme_state.dart';
import '../../services/native_bridge.dart';
import '../../services/pro_gatekeeper.dart';
import '../../services/lazy_app_icon.dart';
import 'settings_widgets.dart';

class SettingsPrivacySecurityView extends StatefulWidget {
  const SettingsPrivacySecurityView({Key? key}) : super(key: key);

  @override
  State<SettingsPrivacySecurityView> createState() => _SettingsPrivacySecurityViewState();
}

class _SettingsPrivacySecurityViewState extends State<SettingsPrivacySecurityView> with WidgetsBindingObserver {
  bool _storageGranted = false;
  bool _notificationGranted = false;
  bool _adminGranted = false;
  bool _writeSettingsGranted = false;
  bool _isSyncing = false;
  bool _isVaultDialogOpen = false;

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
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_isVaultDialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _isVaultDialogOpen = false;
      }
    }
  }

  Future<void> _syncNativePermissions() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final result = await NativeBridge.instance.getPermissionStatuses();
      if (mounted) {
        setState(() {
          _storageGranted = result['storage'] ?? false;
          _notificationGranted = result['notification'] ?? false;
          _adminGranted = result['admin'] ?? false;
          _writeSettingsGranted = result['write_settings'] ?? false;
        });
      }
    } catch (e) {
      debugPrint("Error syncing native permissions: $e");
    } finally {
      _isSyncing = false;
    }
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

  void _openWithDisclosure(String type, String title, String disclosure) async {
    final themeState = context.read<ThemeState>();
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        title: Text(title, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(disclosure, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              NativeBridge.instance.openSettings(type);
            },
            child: const Text('Agree & Continue', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))
          )
        ]
      )
    );
  }

  void _showAppSelectionDialog(BuildContext context, String title, AppsState appsState, ThemeState themeState, {required bool isLock}) {
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    final Set<String> localSelectedCache = isLock ? appsState.lockedApps.toSet() : appsState.hiddenApps.toSet();

    _isVaultDialogOpen = true;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(title, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 320,
          height: 400,
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: appsState.installedApps.length,
            itemBuilder: (context, index) {
              final app = appsState.installedApps[index];
              if (app.packageName == null) return const SizedBox.shrink();
              
              return StatefulBuilder(
                builder: (context, setTileState) {
                  final isChecked = localSelectedCache.contains(app.packageName);
                  return CheckboxListTile(
                    dense: true,
                    secondary: SizedBox(
                      width: 26,
                      height: 26,
                      child: _buildAppIcon(app, 26, themeState),
                    ),
                    title: Text(app.name ?? '', style: TextStyle(color: textColor, fontSize: 13), overflow: TextOverflow.ellipsis),
                    value: isChecked,
                    activeColor: themeState.currentAccentColor,
                    onChanged: (val) {
                      setTileState(() {
                        if (val == true) {
                          localSelectedCache.add(app.packageName!);
                        } else {
                          localSelectedCache.remove(app.packageName!);
                        }
                      });
                    },
                  );
                }
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final originalSet = isLock ? appsState.lockedApps.toSet() : appsState.hiddenApps.toSet();
              
              final itemsToAdd = localSelectedCache.difference(originalSet);
              final itemsToRemove = originalSet.difference(localSelectedCache);
              
              if (isLock) {
                appsState.batchUpdateAppVisibility(toLock: itemsToAdd, toUnlock: itemsToRemove, toHide: {}, toUnhide: {});
              } else {
                appsState.batchUpdateAppVisibility(toLock: {}, toUnlock: {}, toHide: itemsToAdd, toUnhide: itemsToRemove);
              }
              
              Navigator.pop(ctx);
            }, 
            child: Text('Done', style: TextStyle(color: themeState.currentAccentColor, fontWeight: FontWeight.bold))
          ),
        ],
      )
    ).then((_) {
      _isVaultDialogOpen = false;
    });
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
                      bottom: -2, right: -2,
                      child: Container(
                        decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(1.5),
                        child: Icon(isGranted ? Icons.check_circle : Icons.cancel, size: 13, color: isGranted ? Colors.green : Colors.redAccent),
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
                      Text(isGranted ? 'Permission enabled' : 'Permission disabled', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isGranted ? Colors.green : Colors.redAccent.shade200)),
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
    final systemState = context.watch<SystemState>();
    final appsState = context.watch<AppsState>();
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text('App Security & Vault', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
        ),
        SettingsCard(
          title: 'App Lock',
          subtitle: '${appsState.lockedApps.length} apps locked behind PIN authentication',
          icon: Icons.lock_person_outlined,
          onTap: () async {
             if (!ProGatekeeper.checkAccess(context, featureName: 'App Lock')) return;
             
             if (systemState.isPinSet) {
                bool auth = await systemState.authenticateUser('Enter PIN to manage App Lock');
                if (auth && context.mounted) _showAppSelectionDialog(context, 'App Lock', appsState, themeState, isLock: true);
             } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set a PIN on the Lock Screen first.')));
             }
          }
        ),
        SettingsCard(
          title: 'Hidden Apps Vault',
          subtitle: '${appsState.hiddenApps.length} apps hidden from Start Menu and Search',
          icon: Icons.visibility_off_outlined,
          onTap: () async {
             if (!ProGatekeeper.checkAccess(context, featureName: 'Hidden Apps Vault')) return;
             
             if (systemState.isPinSet) {
                bool auth = await systemState.authenticateUser('Enter PIN to open Vault');
                if (auth && context.mounted) _showAppSelectionDialog(context, 'Hidden Vault', appsState, themeState, isLock: false);
             } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set a PIN on the Lock Screen first.')));
             }
          }
        ),

        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text('Permissions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
        ),
        _buildPermissionCard(
          title: 'Storage',
          subtitle: 'Required to process wallpapers, manage files in file manager.',
          baseIcon: Icons.storage_outlined,
          isGranted: _storageGranted,
          onTap: () => NativeBridge.instance.openSettings('storage'),
        ),
        _buildPermissionCard(
          title: 'Admin',
          subtitle: 'Required to enable double tap to lock functionalities.',
          baseIcon: Icons.manage_accounts_outlined,
          isGranted: _adminGranted,
          onTap: () => _openWithDisclosure(
            'admin', 
            'Device Administration Required', 
            'Win11 PC Launcher needs Device Administration access to securely turn off the screen and lock your device when you trigger sleep gestures. This permission is used strictly for locking the screen.'
          ),
        ),
        _buildPermissionCard(
          title: 'Notification access',
          subtitle: 'Required to sync system tray notifications.',
          baseIcon: Icons.notifications_active_outlined,
          isGranted: _notificationGranted,
          onTap: () => _openWithDisclosure(
            'notification_access',
            'Notification Access Required',
            'To display incoming messages and alerts seamlessly in the desktop taskbar, the launcher requires permission to read your active notifications. This data remains entirely on your device.'
          ),
        ),
        _buildPermissionCard(
          title: 'Write Settings',
          subtitle: 'Required for toggling quick settings tiles.',
          baseIcon: Icons.build_outlined,
          isGranted: _writeSettingsGranted,
          onTap: () => NativeBridge.instance.openSettings('write_settings'),
        ),
      ],
    );
  }
}