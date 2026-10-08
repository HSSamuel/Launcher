import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/theme_state.dart';
import '../../states/system_state.dart';
import '../../states/monetization_state.dart';
import '../ui/settings/settings_activation_screen.dart';

class ProGatekeeper {
  /// Checks if the user is Pro. If not, shows the upgrade dialog and returns false.
  static bool checkAccess(BuildContext context, {required String featureName}) {
    final systemState = context.read<SystemState>();
    final monetization = context.read<MonetizationState>();
    
    final isPro = systemState.isActivated || monetization.isPro;

    if (!isPro) {
      _showUpgradeDialog(context, featureName);
      return false;
    }
    return true;
  }

  static void _showUpgradeDialog(BuildContext context, String featureName) {
    final isDark = context.read<ThemeState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white70 : Colors.black54;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Row(
          children: [
            const Icon(Icons.workspace_premium, color: Colors.amber, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pro Feature', 
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)
              )
            ),
          ],
        ),
        content: Text(
          '$featureName is a premium feature.\n\nUpgrade to Win11 PC Launcher Pro to unlock advanced layouts, custom widgets, privacy vaults, and more.',
          style: TextStyle(color: subColor, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Maybe Later', style: TextStyle(color: subColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivationScreen()));
            },
            child: const Text('Upgrade to Pro', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}