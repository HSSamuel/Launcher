import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import 'settings_widgets.dart';

import '../../services/native_bridge.dart';

class SettingsTimeLanguageView extends StatelessWidget {
  const SettingsTimeLanguageView({Key? key}) : super(key: key);

  void _openNativeSettings(String type) async {
    try {
      await NativeBridge.instance.openSettings(type);
    } catch (e) {
      debugPrint("Native routing failed: $e");
      AppSettings.openAppSettings(type: AppSettingsType.settings);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsCard(
          title: 'Date & time',
          subtitle: 'Time zones, automatic clock settings, calendar display',
          icon: Icons.access_time,
          onTap: () => AppSettings.openAppSettings(type: AppSettingsType.date),
        ),
        SettingsCard(
          title: 'Language & region',
          subtitle: 'Windows display language, preferred languages, regional format',
          icon: Icons.language,
          onTap: () => _openNativeSettings('locale'), 
        ),
        SettingsCard(
          title: 'Typing',
          subtitle: 'Touch keyboard, text suggestions, preferences',
          icon: Icons.keyboard_outlined,
          onTap: () => _openNativeSettings('keyboard'), 
        ),
      ],
    );
  }
}