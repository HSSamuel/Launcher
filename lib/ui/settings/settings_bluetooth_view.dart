import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import 'settings_widgets.dart';
import 'settings_usb_screen.dart';

import '../../services/native_bridge.dart';

class SettingsBluetoothView extends StatelessWidget {
  const SettingsBluetoothView({Key? key}) : super(key: key);

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
          // CRITICAL FIX: Safe delegation to NativeBridge routing to eliminate uncaught method exceptions
          onTap: () => NativeBridge.instance.openSettings('print_settings'),
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