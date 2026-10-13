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
    final themeState = context.read<ThemeState>();
    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF232323) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white70 : Colors.black54;
    final cardBg = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF6F8FA);
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final accent = themeState.foregroundAccentColor;

    showDialog(
      context: context,
      builder: (ctx) => Consumer<MonetizationState>(
        builder: (ctx, monetization, _) {
          final String localPrice = monetization.proPrice;
          final bool hasPrice = localPrice.isNotEmpty;
          final bool isWaitingForStore = !monetization.hasAttemptedLoad;

          return AlertDialog(
            backgroundColor: bgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: borderColor, width: 1),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.workspace_premium, color: Colors.amber, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Upgrade to Pro',
                    style: TextStyle(color: textColor, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$featureName requires a Win11 PC Launcher Pro license.',
                  style: TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  'Unlock unlimited customization, desktop gestures, custom icon packs, 3D animations, and privacy vaults.',
                  style: TextStyle(color: subColor, fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 16),

                // Dynamic Price Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasPrice ? accent.withOpacity(0.5) : borderColor, 
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'LIFETIME LICENSE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: Colors.blueAccent,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'One-time payment • No subscriptions',
                              style: TextStyle(color: subColor, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (hasPrice)
                        Text(
                          localPrice,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: textColor,
                          ),
                        )
                      else if (isWaitingForStore)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                          ),
                        )
                      else
  Text(
    'PRO',
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.0,
      color: accent,
    ),
  ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Maybe Later', style: TextStyle(color: subColor, fontSize: 13)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () {
                  final navigator = Navigator.of(ctx, rootNavigator: true);
                  navigator.pop();
                  navigator.push(
                    MaterialPageRoute(builder: (_) => const ActivationScreen()),
                  );
                },
                child: Text(
                  hasPrice ? 'Continue ($localPrice)' : 'Continue',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}