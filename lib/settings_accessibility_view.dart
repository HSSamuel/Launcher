import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import 'settings_widgets.dart';

class SettingsAccessibilityView extends StatelessWidget {
  const SettingsAccessibilityView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColor = isDark ? Colors.white : Colors.black87;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text('Vision', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: headerColor)),
        ),
        SettingsCard(
          title: 'Text size',
          subtitle: 'Text size that appears throughout Windows and apps',
          icon: Icons.text_fields,
          onTap: () => AppSettings.openAppSettings(type: AppSettingsType.accessibility),
        ),
        SettingsCard(
          title: 'Visual effects',
          subtitle: 'Scroll bars, transparency, animations, notification timeout',
          icon: Icons.visibility_outlined,
          onTap: () => AppSettings.openAppSettings(type: AppSettingsType.display),
        ),
        SettingsCard(
          title: 'Color filters',
          subtitle: 'Color filters make photos and colors easier to see',
          icon: Icons.color_lens_outlined,
          onTap: () => AppSettings.openAppSettings(type: AppSettingsType.accessibility),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text('Hearing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: headerColor)),
        ),
        SettingsCard(
          title: 'Audio',
          subtitle: 'Mono audio, audio notification screen flash',
          icon: Icons.hearing,
          onTap: () => AppSettings.openAppSettings(type: AppSettingsType.sound),
        ),
        SettingsCard(
          title: 'Captions',
          subtitle: 'Caption styles',
          icon: Icons.closed_caption_outlined,
          onTap: () => AppSettings.openAppSettings(type: AppSettingsType.accessibility),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text('Interaction', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: headerColor)),
        ),
        SettingsCard(
          title: 'Speech',
          subtitle: 'Windows Speech Recognition, voice typing',
          icon: Icons.mic_none,
          onTap: () => AppSettings.openAppSettings(type: AppSettingsType.accessibility),
        ),
      ],
    );
  }
}