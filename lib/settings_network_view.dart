import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import 'settings_widgets.dart';

class SettingsNetworkView extends StatelessWidget {
  const SettingsNetworkView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsCard(
          title: 'Wi-Fi',
          subtitle: 'Connect, manage known networks, metered\nnetwork',
          icon: Icons.wifi,
          trailing: const SizedBox.shrink(), // No chevron, matching your image
          // Routes directly to the Android Wi-Fi screen
          onTap: () => AppSettings.openAppSettings(type: AppSettingsType.wifi),
        ),
        
        // VPN has been removed per your instructions
        
        SettingsCard(
          title: 'Mobile hotspot',
          subtitle: 'Share your internet connection',
          icon: Icons.wifi_tethering,
          trailing: const SizedBox.shrink(),
          // Routes directly to the Android Personal Hotspot screen
          onTap: () => AppSettings.openAppSettings(type: AppSettingsType.hotspot),
        ),
        SettingsCard(
          title: 'Airplane mode',
          subtitle: 'Stop all wireless communication',
          icon: Icons.airplanemode_active,
          trailing: const SizedBox.shrink(),
          // 'wireless' maps to the Android "Hotspot & Connections" / "Wireless & Networks" root screen
          onTap: () => AppSettings.openAppSettings(type: AppSettingsType.wireless),
        ),
      ],
    );
  }
}