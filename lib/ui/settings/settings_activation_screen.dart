import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../states/theme_state.dart';
import '../../states/system_state.dart';
import '../../states/monetization_state.dart';
import '../../services/native_bridge.dart';
import 'settings_widgets.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({Key? key}) : super(key: key);

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  // CRITICAL IMPLEMENTATION: Compile-time flag to hide custom licensing from Google Play
  static const bool isPlayStoreBuild = bool.fromEnvironment('PLAY_STORE_BUILD', defaultValue: false);

  final TextEditingController _keyController = TextEditingController();
  String _deviceId = '';
  bool _isLoadingDeviceId = true;
  bool _isVerifying = false;
  bool _isTransferring = false;

  @override
  void initState() {
    super.initState();
    _fetchDeviceId();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _fetchDeviceId() async {
    const storage = FlutterSecureStorage(); 
    String? id = await storage.read(key: 'unique_installation_id');

    if (id == null) {
      final random = math.Random.secure();
      final values = List<int>.generate(16, (i) => random.nextInt(256));
      id = base64UrlEncode(values).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').substring(0, 10).toUpperCase();
      await storage.write(key: 'unique_installation_id', value: id);
    }

    if (mounted) {
      setState(() {
        _deviceId = id!;
        _isLoadingDeviceId = false;
      });
    }
  }

  void _copyInstallationId() {
    if (_deviceId.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _deviceId));
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Installation ID copied to clipboard.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _verifyEnterpriseKey() async {
    final code = _keyController.text.trim().toUpperCase();
    if (code.isEmpty || _isVerifying) return;

    FocusScope.of(context).unfocus();
    setState(() => _isVerifying = true);

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final systemState = context.read<SystemState>();
    final success = await systemState.verifyAndActivate(code);

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (success) {
      _keyController.clear();
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Launcher activated successfully! All Pro features unlocked.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid product key. Ensure it matches your Installation ID.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showTransferDialog() {
    final themeState = context.read<ThemeState>();
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final accent = themeState.foregroundAccentColor;
    final TextEditingController oldKeyController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            title: Text('Transfer License', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Enter the Enterprise License Key from your old device. If valid, your license will be transferred to this Installation ID.', style: TextStyle(color: subTextColor, fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  controller: oldKeyController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 16,
                  style: TextStyle(color: textColor, fontSize: 13, letterSpacing: 1.2, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'OLD 16-CHARACTER KEY',
                    hintStyle: TextStyle(color: subTextColor.withOpacity(0.6), fontSize: 12, letterSpacing: 1.0),
                    isDense: true,
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade400)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accent, width: 1.5)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: TextStyle(color: subTextColor)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                onPressed: _isTransferring ? null : () async {
                  final oldKey = oldKeyController.text.trim().toUpperCase();
                  if (oldKey.isEmpty || oldKey.length != 16) return;

                  setDialogState(() => _isTransferring = true);
                  
                  try {
                    final response = await http.post(
                      Uri.parse('https://win11-license.onrender.com/reset-license'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({
                        'productKey': oldKey,
                        'newInstallationId': _deviceId,
                      }),
                    );

                    if (response.statusCode == 200) {
                      final data = jsonDecode(response.body);
                      final newKey = data['newProductKey'];
                      
                      if (ctx.mounted) Navigator.pop(ctx);
                      
                      // Automatically verify the new key
                      _keyController.text = newKey;
                      _verifyEnterpriseKey();
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('License transferred! Check your email for the new key record.'), backgroundColor: Colors.green),
                        );
                      }
                    } else {
                      final data = jsonDecode(response.body);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(data['message'] ?? data['error'] ?? 'Transfer failed.'), backgroundColor: Colors.redAccent),
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Network error. Could not reach license server.'), backgroundColor: Colors.redAccent),
                      );
                    }
                  } finally {
                    if (ctx.mounted) {
                      setDialogState(() => _isTransferring = false);
                    }
                  }
                },
                child: _isTransferring 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Transfer'),
              ),
            ],
          );
        }
      ),
    );
  }

  void _confirmDeactivation(BuildContext context, SystemState systemState, Color popBg, Color textColor, Color subTextColor) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: popBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(
          'Remove Product Key?',
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'This will remove your current product key and restore standard licensing limits.',
          style: TextStyle(color: subTextColor, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: subTextColor)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await systemState.deactivate();
              if (mounted) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Product key removed successfully.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final systemState = context.watch<SystemState>();
    final monetization = context.watch<MonetizationState>();

    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final cardBg = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade300;
    final accent = themeState.foregroundAccentColor;

    final isActivated = systemState.isActivated || monetization.isPro;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'System > Activation'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isActivated ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isActivated ? Colors.green : Colors.orange, width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  isActivated ? Icons.check_circle : Icons.info_outline,
                  color: isActivated ? Colors.green : Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isActivated ? 'Windows is activated' : 'Windows is not activated',
                        style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isActivated
                            ? 'You have full access to all premium personalization features.'
                            : 'Upgrade to Pro to unlock premium layouts and custom widgets.',
                        style: TextStyle(color: subTextColor, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (!isActivated && isPlayStoreBuild) ...[
            Text('Upgrade via Google Play', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              padding: const EdgeInsets.all(16),
              child: (!monetization.isStoreAvailable || monetization.products.isEmpty)
                  ? Text('Store currently unavailable. Check your network connection.', style: TextStyle(color: subTextColor, fontSize: 13))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(monetization.products.first.title, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(monetization.products.first.description, style: TextStyle(color: subTextColor, fontSize: 13)),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              monetization.products.first.price,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                            ),
                            monetization.isPurchasePending
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blueAccent,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    ),
                                    onPressed: monetization.buyProUpgrade,
                                    child: const Text('Upgrade Now'),
                                  ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: monetization.isPurchasePending ? null : monetization.restorePurchases,
                            child: const Text('Restore Purchases'),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
          ],

          if (isActivated) ...[
            Text('License Details', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Version: Win11 PC Launcher Pro', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    'Activation channel: ${systemState.isActivated ? "Enterprise License Key" : "Google Play Store"}',
                    style: TextStyle(color: subTextColor, fontSize: 12),
                  ),
                  if (systemState.isActivated && systemState.activationKey.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Product key: ${systemState.activationKey}',
                      style: TextStyle(color: subTextColor, fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (systemState.isActivated && !isPlayStoreBuild)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade400),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        icon: const Icon(Icons.vpn_key_off_outlined, size: 16, color: Colors.redAccent),
                        label: const Text('Remove Product Key', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                        onPressed: () => _confirmDeactivation(context, systemState, cardBg, textColor, subTextColor),
                      ),
                    ),
                ],
              ),
            ),
          ] else if (!isPlayStoreBuild) ...[
            Text('Enterprise License Activation', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Direct Payment Button integration
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade600,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Icon(Icons.payment, size: 20),
                      label: const Text('Purchase Enterprise Key Online', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      onPressed: () {
                        NativeBridge.instance.launchApp('https://flutterwave.com/pay/win11-pro-key');
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.perm_device_information, size: 18, color: accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Your Installation ID', style: TextStyle(color: subTextColor, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text(
                                _isLoadingDeviceId ? 'Retrieving ID...' : _deviceId,
                                style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          color: accent,
                          tooltip: 'Copy ID',
                          onPressed: _isLoadingDeviceId ? null : _copyInstallationId,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Provide your Installation ID at checkout to receive your custom 16-character key via email.',
                    style: TextStyle(color: subTextColor, fontSize: 11),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _keyController,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 16,
                          style: TextStyle(color: textColor, fontSize: 13, letterSpacing: 1.2, fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '16-CHARACTER KEY',
                            hintStyle: TextStyle(color: subTextColor.withOpacity(0.6), fontSize: 12, letterSpacing: 1.0),
                            isDense: true,
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade400)),
                            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accent, width: 1.5)),
                          ),
                          onSubmitted: (_) => _verifyEnterpriseKey(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        height: 34,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                            foregroundColor: textColor,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          onPressed: _isVerifying ? null : _verifyEnterpriseKey,
                          child: _isVerifying
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Next', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showTransferDialog,
                      child: const Text('Transfer existing license'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          if (!isActivated && !isPlayStoreBuild)
            Padding(
              padding: const EdgeInsets.only(top: 24.0),
              child: Text(
                'Note: Uninstalling the launcher or clearing its application data will reset this Installation ID and require a license transfer to restore your Pro status.',
                style: TextStyle(color: subTextColor, fontSize: 11, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}