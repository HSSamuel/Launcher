import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'launcher_state.dart';
import 'settings_widgets.dart';

class SettingsGesturesView extends StatefulWidget {
  const SettingsGesturesView({Key? key}) : super(key: key);

  @override
  State<SettingsGesturesView> createState() => _SettingsGesturesViewState();
}

class _SettingsGesturesViewState extends State<SettingsGesturesView> {
  bool isDesktopGesturesExpanded = false;

  void _showGestureActionDialog(BuildContext context, LauncherState state, String type) {
    final isDark = state.isDarkMode;
    
    String currentAction = 'None';
    String title = 'Gesture Action';
    if (type == 'UP') { currentAction = state.gestureUpAction; title = '1-Finger UP'; }
    else if (type == 'DOWN') { currentAction = state.gestureDownAction; title = '1-Finger DOWN'; }
    else if (type == '2_UP') { currentAction = state.gestureTwoFingerUpAction; title = '2-Finger UP'; }
    else if (type == '2_DOWN') { currentAction = state.gestureTwoFingerDownAction; title = '2-Finger DOWN'; }

    // NEW: 'Apps Menu' added to the selectable list
    final actions = ['None', 'Start Menu', 'Apps Menu', 'Notification Center', 'Quick Settings', 'Widget Board', 'Device Notification Bar'];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: actions.map((action) {
            return ListTile(
              title: Text(action, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
              trailing: currentAction == action ? const Icon(Icons.check, color: Colors.blueAccent) : null,
              onTap: () {
                state.updateGesture(type, action);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildInnerGestureOption(String title, String subtitle, IconData icon, bool isDark, String currentAction, VoidCallback onTap) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.grey.shade600;
    final iconColor = isDark ? Colors.white70 : Colors.black54;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: subTextColor)),
                ],
              ),
            ),
            Text(currentAction, style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 22, color: textColor),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;

    return Column(
      children: [
        ExpandableSettingsCard(
          title: 'Desktop gestures',
          subtitle: 'Select gestures for desktop',
          icon: Icons.touch_app,
          isExpanded: isDesktopGesturesExpanded,
          onToggle: () => setState(() => isDesktopGesturesExpanded = !isDesktopGesturesExpanded),
          children: Column(
            children: [
              Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
              _buildInnerGestureOption('Desktop gesture UP', 'Gesture while swiping down to up', Icons.swipe_up, isDark, state.gestureUpAction, () => _showGestureActionDialog(context, state, 'UP')),
              _buildInnerGestureOption('Desktop gesture DOWN', 'Gesture while swiping up to down', Icons.swipe_down, isDark, state.gestureDownAction, () => _showGestureActionDialog(context, state, 'DOWN')),
              Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
              _buildInnerGestureOption('Desktop 2-finger UP', 'Apps / Start Menu', Icons.swipe_up_alt, isDark, state.gestureTwoFingerUpAction, () => _showGestureActionDialog(context, state, '2_UP')),
              _buildInnerGestureOption('Desktop 2-finger DOWN', 'Phone edge notification', Icons.swipe_down_alt, isDark, state.gestureTwoFingerDownAction, () => _showGestureActionDialog(context, state, '2_DOWN')),
            ],
          ),
        ),
      ],
    );
  }
}