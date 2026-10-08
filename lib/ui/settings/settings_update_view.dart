import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:new_version_plus/new_version_plus.dart';
import 'package:provider/provider.dart';

import '../../states/theme_state.dart';
import '../../services/native_bridge.dart'; 

class SettingsUpdateView extends StatefulWidget {
  const SettingsUpdateView({Key? key}) : super(key: key);

  @override
  State<SettingsUpdateView> createState() => _SettingsUpdateViewState();
}

class _SettingsUpdateViewState extends State<SettingsUpdateView> {
  bool _isChecking = false;
  String _lastChecked = "Today";
  String _version = "...";
  
  bool _updateAvailable = false;
  String _newVersion = "";
  String _releaseNotes = "";
  String _appStoreLink = "";

  @override
  void initState() {
    super.initState();
    _fetchVersion();
  }

  Future<void> _fetchVersion() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = packageInfo.version);
    } catch (_) {}
  }

  void _checkForUpdates() async {
    setState(() => _isChecking = true);
    
    try {
      final newVersionPlus = NewVersionPlus(
        androidId: 'com.samuel.winlauncher',
      );
      
      final status = await newVersionPlus.getVersionStatus();
      
      if (status != null && status.canUpdate) {
        if (mounted) {
          setState(() {
            _updateAvailable = true;
            _newVersion = status.storeVersion;
            _releaseNotes = status.releaseNotes ?? "General improvements and optimizations.";
            _appStoreLink = status.appStoreLink;
          });
        }
      } else {
         if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Launcher is up to date!'), behavior: SnackBarBehavior.floating),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reach Google Play. Check your connection.'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
          final now = DateTime.now();
          _lastChecked = "Today, ${now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour)}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}";
        });
      }
    }
  }

  void _downloadUpdate() {
    if (_appStoreLink.isNotEmpty) {
      NativeBridge.instance.launchApp(_appStoreLink);
    } else {
      NativeBridge.instance.launchApp('market://details?id=com.samuel.winlauncher');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync, size: 36, color: Colors.blueAccent.shade400),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Win11 PC Launcher Update',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Current version: v$_version',
                    style: TextStyle(fontSize: 12, color: subTextColor),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          
          if (_isChecking)
            Row(
              children: [
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                ),
                const SizedBox(width: 16),
                Text('Checking Google Play...', style: TextStyle(color: textColor, fontSize: 13)),
              ],
            )
          else if (_updateAvailable)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.3))
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.new_releases, color: Colors.blueAccent, size: 20),
                      const SizedBox(width: 12),
                      Text('Update Available: v$_newVersion', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(_releaseNotes, style: TextStyle(color: textColor, fontSize: 13, height: 1.4), maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _downloadUpdate,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Download Update', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  )
                ],
              ),
            )
          else
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('You\'re up to date', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Last checked: $_lastChecked', style: TextStyle(color: subTextColor, fontSize: 11)),
                  ],
                ),
              ],
            ),
            
          const SizedBox(height: 24),
          if (!_updateAvailable)
            ElevatedButton(
              onPressed: _isChecking ? null : _checkForUpdates,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Check for updates', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          
          const SizedBox(height: 32),
          Text('Advanced options', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.history, color: subTextColor),
            title: Text('Update history', style: TextStyle(color: textColor, fontSize: 13)),
            trailing: Icon(Icons.chevron_right, color: subTextColor),
            onTap: () {},
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.code, color: subTextColor),
            title: Text('Join beta program', style: TextStyle(color: textColor, fontSize: 13)),
            trailing: Icon(Icons.chevron_right, color: subTextColor),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}