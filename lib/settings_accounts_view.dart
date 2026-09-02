import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'launcher_state.dart';
import 'settings_widgets.dart';

class SettingsAccountsView extends StatelessWidget {
  const SettingsAccountsView({Key? key}) : super(key: key);

  static const platform = MethodChannel('win_launcher/native');

  void _openNativeSettings(String type) async {
    try {
      await platform.invokeMethod('openSettings', {'type': type});
    } catch (e) {
      debugPrint("Native routing failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsCard(
          title: 'Your info',
          subtitle: 'Accounts used by email, calender and contacts',
          icon: Icons.person_search_outlined,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const YourInfoScreen())),
        ),
        SettingsCard(
          title: 'Email & accounts',
          subtitle: 'Accounts used by email, calender and contacts',
          icon: Icons.mail_outline,
          onTap: () => _openNativeSettings('add_account'), // Native routing
        ),
      ],
    );
  }
}

class YourInfoScreen extends StatelessWidget {
  const YourInfoScreen({Key? key}) : super(key: key);

  void _editValue(BuildContext context, LauncherState state, bool isName) {
    TextEditingController controller = TextEditingController(text: isName ? state.userName : state.userEmail);
    final isDark = state.isDarkMode;
    final dialogBg = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(isName ? 'Edit Name' : 'Edit Email', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: textColor, fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent, width: 1.5)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
          TextButton(
            onPressed: () {
              if (isName) {
                state.updateUserName(controller.text);
              } else {
                state.updateUserEmail(controller.text);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade300;

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
              final XFile? image = await picker.pickImage(source: ImageSource.gallery);
              if (image != null) {
                final bytes = await image.readAsBytes();
                state.saveProfile(state.userName, bytes);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated!')));
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
              child: Text(state.userName, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            onTap: () => _editValue(context, state, true),
          ),
          SettingsCard(
            title: 'Email',
            subtitle: 'User email',
            icon: Icons.mail_outline,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)),
              child: Text(state.userEmail, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            onTap: () => _editValue(context, state, false),
          ),
        ],
      ),
    );
  }
}