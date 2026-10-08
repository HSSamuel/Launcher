import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/theme_state.dart';
import '../../states/system_state.dart';
import 'settings_widgets.dart';

class SignInOptionsScreen extends StatefulWidget {
  const SignInOptionsScreen({Key? key}) : super(key: key);

  @override
  State<SignInOptionsScreen> createState() => _SignInOptionsScreenState();
}

class _SignInOptionsScreenState extends State<SignInOptionsScreen> {
  bool _hasPin = false;

  @override
  void initState() {
    super.initState();
    _checkPinStatus();
  }

  Future<void> _checkPinStatus() async {
    final systemState = context.read<SystemState>();
    setState(() {
      _hasPin = systemState.isPinSet;
    });
  }

  void _showPinSetupDialog({bool isRemoval = false}) async {
    final systemState = context.read<SystemState>();
    final canUseBiometrics = await systemState.canUseBiometrics();
    if (!mounted) return;

    final isDark = context.read<ThemeState>().isDarkMode;
    final controller = TextEditingController();
    String errorMessage = '';
    
    bool isConfirming = false;
    String firstPin = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            title: Text(
              isRemoval ? 'Remove PIN' : 'Set up a PIN', 
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRemoval 
                      ? 'Enter your current PIN to remove it.' 
                      : (isConfirming ? 'Re-enter your PIN to confirm.' : 'Create a 4-digit PIN to secure your launcher.'),
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 18, letterSpacing: 8),
                  decoration: InputDecoration(
                    counterText: '',
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.read<ThemeState>().foregroundAccentColor)),
                  ),
                ),
                if (errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(errorMessage, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ]
              ],
            ),
            actions: [
              if (isRemoval && canUseBiometrics)
                TextButton(
                  onPressed: () async {
                  final success = await systemState.authenticateWithBiometrics('Verify your identity to remove your PIN');
                  if (success) {
                    await systemState.forceClearPin();
                    if (ctx.mounted) Navigator.pop(ctx);
                    
                    if (mounted) {
                      _checkPinStatus();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN successfully removed.')));
                    }
                  }
                },
                  child: const Text('Forgot PIN?', style: TextStyle(color: Colors.blueAccent)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
              ),
              TextButton(
                onPressed: () async {
                  final input = controller.text;

                  if (isRemoval) {
                    if (input.length == 4) {
                      final success = await systemState.verifyAndDisablePin(input);
                      if (success) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (!mounted) return;
                        _checkPinStatus();
                      } else {
                        setDialogState(() => errorMessage = 'Incorrect PIN. Please try again.');
                      }
                    } else {
                      setDialogState(() => errorMessage = 'PIN must be 4 digits');
                    }
                  } else {
                    if (input.length == 4) {
                      if (!isConfirming) {
                        setDialogState(() {
                          firstPin = input;
                          isConfirming = true;
                          controller.clear();
                          errorMessage = '';
                        });
                      } else {
                        if (input == firstPin) {
                          await systemState.setNewPin(input);
                          
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (!mounted) return; // CRITICAL FIX
                          _checkPinStatus();
                        } else {
                          setDialogState(() {
                            isConfirming = false;
                            firstPin = '';
                            controller.clear();
                            errorMessage = 'PINs did not match. Please start over.';
                          });
                        }
                      }
                    } else {
                      setDialogState(() => errorMessage = 'PIN must be 4 digits');
                    }
                  }
                },
                child: Text('Confirm', style: TextStyle(color: context.read<ThemeState>().foregroundAccentColor, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final systemState = context.watch<SystemState>();
    final hasPin = systemState.isPinSet;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Accounts > Sign-in options'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        children: [
          SettingsCard(
            title: 'Windows Hello PIN',
            subtitle: hasPin ? 'Your PIN is actively securing this device' : 'Set up a PIN to sign in securely',
            icon: Icons.pin_outlined,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasPin)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _showPinSetupDialog(isRemoval: true),
                    child: const Text('Remove', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                if (hasPin) const SizedBox(width: 4),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.read<ThemeState>().foregroundAccentColor,
                    foregroundColor: context.read<ThemeState>().textOnAccentColor,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onPressed: () => _showPinSetupDialog(isRemoval: false),
                  child: Text(hasPin ? 'Change' : 'Set up', style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}