import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'settings_widgets.dart'; // Import our new shared widgets

// --- Notifications Screen ---
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool clearWhenOpening = false;
  bool closePanelWhenOpening = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'System > Notifications'),
      body: ListView(
        padding: const EdgeInsets.all(12), physics: const BouncingScrollPhysics(),
        children: [
          SettingsCard(title: 'Excluded apps', subtitle: 'Notifications from these apps are not included in panel', icon: Icons.flip_to_front, trailing: const SizedBox.shrink(), onTap: () {}),
          SettingsCard(
            title: 'Clear when opening notification', icon: Icons.clear_all,
            trailing: Switch(value: clearWhenOpening, activeColor: Colors.blueAccent, onChanged: (val) => setState(() => clearWhenOpening = val)),
          ),
          SettingsCard(
            title: 'Close panel when opening notification', icon: Icons.vertical_split,
            trailing: Switch(value: closePanelWhenOpening, activeColor: Colors.blueAccent, onChanged: (val) => setState(() => closePanelWhenOpening = val)),
          ),
        ],
      ),
    );
  }
}

// --- Recent Apps Screen ---
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'System > Recent apps'),
      body: ListView(
        padding: const EdgeInsets.all(12), physics: const BouncingScrollPhysics(),
        children: [
          SettingsCard(
            title: 'Recent apps', icon: Icons.filter_none,
            trailing: Switch(value: enableRecentApps, activeColor: Colors.blueAccent, onChanged: (val) => setState(() => enableRecentApps = val)),
          ),
          SettingsCard(
            title: 'Max apps to show', subtitle: 'Number of items to log in recent apps', icon: Icons.linear_scale,
            trailing: Text(maxApps.toInt().toString(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
          ),
          Slider(value: maxApps, min: 0, max: 50, divisions: 50, activeColor: Colors.blueAccent, inactiveColor: Colors.grey.shade300, onChanged: (val) => setState(() => maxApps = val)),
          const SizedBox(height: 10),
          SettingsCard(
            title: 'Grid count horizontally', subtitle: 'Change this to increase or decrease icons count horizontally', icon: Icons.grid_4x4,
            trailing: Text(gridCount.toInt().toString(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
          ),
          Slider(value: gridCount, min: 1, max: 7, divisions: 6, activeColor: Colors.blueAccent, inactiveColor: Colors.grey.shade300, onChanged: (val) => setState(() => gridCount = val)),
        ],
      ),
    );
  }
}

// --- About Screen (Dynamic Hardware Info) ---
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

        setState(() {
          deviceName = androidInfo.model;
          androidVersion = androidInfo.version.release;
          buildNumber = androidInfo.version.sdkInt.toString();
          model = androidInfo.model;
          processor = androidInfo.hardware;
          launcherVersion = packageInfo.version;
          launcherBuild = packageInfo.buildNumber;
        });
      }
    } catch (_) {}
  }

  Widget _buildExpandableCard({required String title, required String subtitle, required IconData icon, required bool isExpanded, required VoidCallback onToggle, required Widget children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10), 
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300, width: 0.8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle, borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), 
              child: Row(
                children: [
                  Icon(icon, size: 24, color: Colors.black54), const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                  Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 22, color: Colors.black87),
                ],
              ),
            ),
          ),
          if (isExpanded) children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, color: Colors.black54))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final ratio = MediaQuery.of(context).devicePixelRatio;
    screenRes = '${(size.width * ratio).toInt()} x ${(size.height * ratio).toInt()}';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'System > About'),
      body: ListView(
        padding: const EdgeInsets.all(12), physics: const BouncingScrollPhysics(),
        children: [
          _buildExpandableCard(
            title: 'Device specifications', subtitle: deviceName, icon: Icons.phone_android,
            isExpanded: _isDeviceExpanded, onToggle: () => setState(() => _isDeviceExpanded = !_isDeviceExpanded),
            children: Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('Device name : ', deviceName),
                  _buildInfoRow('Android version : ', androidVersion),
                  _buildInfoRow('Build number : ', buildNumber),
                  _buildInfoRow('Model : ', model),
                  _buildInfoRow('Processor : ', processor),
                  _buildInfoRow('Screen resolution : ', screenRes),
                ],
              ),
            ),
          ),
          _buildExpandableCard(
            title: 'Launcher specifications', subtitle: 'v$launcherVersion', icon: Icons.grid_view,
            isExpanded: _isLauncherExpanded, onToggle: () => setState(() => _isLauncherExpanded = !_isLauncherExpanded),
            children: Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('Build name : ', 'v$launcherVersion'),
                  _buildInfoRow('Build version : ', launcherBuild),
                ],
              ),
            ),
          ),
          SettingsCard(title: 'Privacy Policy', subtitle: 'View the latest privacy policy.', icon: Icons.privacy_tip_outlined, onTap: () {}),
          SettingsCard(title: 'FAQ', subtitle: 'All frequently asked questions answered here.', icon: Icons.chat_bubble_outline, onTap: () {}),
          SettingsCard(title: 'Rate us on Google Play', subtitle: 'Your feedback matters us', icon: Icons.star_border, onTap: () {}),
          SettingsCard(title: 'Share us', subtitle: 'Share Windows 11 Launcher easily with your loved ones', icon: Icons.share, onTap: () {}),
          SettingsCard(title: 'Reset launcher', subtitle: 'Tap to reset Windows 11 Launcher. Resetting will\nremove all modified settings.', icon: Icons.refresh, trailing: const SizedBox.shrink(), onTap: () {}),
          SettingsCard(title: 'Uninstall launcher', subtitle: 'Uninstall Windows 11 Launcher.', icon: Icons.delete_outline, trailing: const SizedBox.shrink(), onTap: () {}),
        ],
      ),
    );
  }
}

// --- Device Support Screen ---
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