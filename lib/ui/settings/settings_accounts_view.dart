import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../../states/theme_state.dart';
import '../../states/system_state.dart';
import 'settings_widgets.dart';
import '../../services/native_bridge.dart';
import 'settings_sign_in_options.dart';

class SettingsAccountsView extends StatelessWidget {
  const SettingsAccountsView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final systemState = context.watch<SystemState>();

    return Column(
      children: [
        SettingsCard(
          title: 'Your info',
          subtitle: 'Accounts used by email, calendar and contacts',
          icon: Icons.person_search_outlined,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const YourInfoScreen())),
        ),
        SettingsCard(
          title: 'Sign-in options',
          subtitle: systemState.isPinSet ? 'PIN (Windows Hello) is enabled' : 'Set up a PIN to sign in securely',
          icon: Icons.lock_outline,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignInOptionsScreen())),
        ),
        SettingsCard(
          title: 'Email & accounts',
          subtitle: 'Accounts used by email, calendar and contacts',
          icon: Icons.mail_outline,
          onTap: () => NativeBridge.instance.openSettings('add_account'), 
        ),
      ],
    );
  }
}

class _EditInfoDialog extends StatefulWidget {
  final String initialText;
  final String title;
  final bool isDark;

  const _EditInfoDialog({
    Key? key,
    required this.initialText,
    required this.title,
    required this.isDark,
  }) : super(key: key);

  @override
  State<_EditInfoDialog> createState() => _EditInfoDialogState();
}

class _EditInfoDialogState extends State<_EditInfoDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dialogBg = widget.isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = widget.isDark ? Colors.white : Colors.black87;

    return AlertDialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Text(widget.title, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
      content: TextField(
        controller: _controller,
        style: TextStyle(color: textColor, fontSize: 13),
        decoration: const InputDecoration(
          isDense: true,
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent, width: 1.5)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), 
          child: Text('Cancel', style: TextStyle(color: widget.isDark ? Colors.white54 : Colors.black54))
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class YourInfoScreen extends StatelessWidget {
  const YourInfoScreen({Key? key}) : super(key: key);

  void _editValue(BuildContext context, bool isName) async {
    final systemState = context.read<SystemState>();
    final themeState = context.read<ThemeState>();
    final initialText = isName ? systemState.userName : systemState.userEmail;
    
    final String? newText = await showDialog<String>(
      context: context,
      builder: (ctx) => _EditInfoDialog(
        initialText: initialText,
        title: isName ? 'Edit Name' : 'Edit Email',
        isDark: themeState.isDarkMode,
      ),
    );

    if (!context.mounted) return;

    if (newText != null && newText.trim().isNotEmpty && newText != initialText) {
      if (isName) {
        systemState.updateUserName(newText.trim());
      } else {
        systemState.updateUserEmail(newText.trim());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final systemState = context.watch<SystemState>();
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white.withOpacity(0.10) : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Accounts > Your info'),
      body: ListView(
        padding: const EdgeInsets.all(12),
        physics: const BouncingScrollPhysics(),
        children: [
          SettingsCard(
            title: 'Picture',
            subtitle: 'Select user account picture',
            icon: Icons.image_outlined,
            trailing: const SizedBox.shrink(),
            onTap: () async {
              final picker = ImagePicker();
              final XFile? image = await picker.pickImage(
                source: ImageSource.gallery,
                maxWidth: 256,
                maxHeight: 256,
                imageQuality: 70,
              );
              if (image != null) {
                final bytes = await image.readAsBytes();
                systemState.saveProfile(systemState.userName, bytes);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated!')));
                }
              }
            },
          ),
          SettingsCard(
            title: 'Name',
            subtitle: 'User name',
            icon: Icons.badge_outlined,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)),
              child: Text(systemState.userName, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            onTap: () => _editValue(context, true),
          ),
          SettingsCard(
            title: 'Email',
            subtitle: 'User email',
            icon: Icons.mail_outline,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)),
              child: Text(systemState.userEmail, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            onTap: () => _editValue(context, false),
          ),
        ],
      ),
    );
  }
}