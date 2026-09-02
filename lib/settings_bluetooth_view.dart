import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_settings/app_settings.dart';
import 'settings_widgets.dart';
import 'settings_usb_screen.dart';

class SettingsBluetoothView extends StatelessWidget {
  const SettingsBluetoothView({Key? key}) : super(key: key);

  static const platform = MethodChannel('win_launcher/native');

  void _openPrintingSettings() async {
    try {
      await platform.invokeMethod('openSettings', {'type': 'print_settings'});
    } catch (e) {
      debugPrint("Failed to open print settings: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsCard(
          title: 'Bluetooth',
          subtitle: 'Bluetooth is turned off',
          icon: Icons.bluetooth,
          trailing: const SizedBox.shrink(),
          onTap: () => AppSettings.openAppSettings(type: AppSettingsType.bluetooth),
        ),
        SettingsCard(
          title: 'Printers & scanners',
          subtitle: 'Preferences, troubleshoot',
          icon: Icons.print_outlined,
          trailing: const SizedBox.shrink(),
          // FIXED: Routes directly to Android's native Printing service screen
          onTap: _openPrintingSettings,
        ),
        SettingsCard(
          title: 'USB',
          subtitle: 'Notifications, USB battery saver, mobile device preferences',
          icon: Icons.usb,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsUsbScreen())),
        ),
      ],
    );
  }
}