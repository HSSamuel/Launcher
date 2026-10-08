import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_widgets.dart';

class SettingsUsbScreen extends StatefulWidget {
  const SettingsUsbScreen({Key? key}) : super(key: key);

  @override
  State<SettingsUsbScreen> createState() => _SettingsUsbScreenState();
}

class _SettingsUsbScreenState extends State<SettingsUsbScreen> {
  bool autoplay = true;

  @override
  void initState() {
    super.initState();
    // FIX: Load persisted USB preference instead of falling back to default ephemeral state
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          autoplay = prefs.getBool('usb_autoplay') ?? true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Bluetooth & devices > USB'),
      body: ListView(
        padding: const EdgeInsets.all(12),
        physics: const BouncingScrollPhysics(),
        children: [
          SettingsCard(
            title: 'Use autoplay for all external device\nconnected',
            icon: Icons.usb,
            trailing: Switch(
              value: autoplay,
              activeColor: Colors.blueAccent,
              onChanged: (val) async {
                setState(() => autoplay = val);
                // FIX: Persist the configuration when toggled
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('usb_autoplay', val);
              },
            ),
          ),
        ],
      ),
    );
  }
}