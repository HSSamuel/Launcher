import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsUpdateView extends StatefulWidget {
  const SettingsUpdateView({Key? key}) : super(key: key);

  @override
  State<SettingsUpdateView> createState() => _SettingsUpdateViewState();
}

class _SettingsUpdateViewState extends State<SettingsUpdateView> {
  bool _isChecking = false;
  String _lastChecked = "Today";
  String _version = "...";

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
    
    // Simulate network delay for update check
    await Future.delayed(const Duration(seconds: 2));
    
    if (mounted) {
      setState(() {
        _isChecking = false;
        final now = DateTime.now();
        _lastChecked = "Today, ${now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour)}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}";
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Launcher is up to date!'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                    'Win11 Launcher Update',
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
                Text('Checking for updates...', style: TextStyle(color: textColor, fontSize: 13)),
              ],
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