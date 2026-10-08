import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:local_auth/local_auth.dart';

import '../main.dart'; 

class TimeService {
  static Stream<DateTime> get clockStream => Stream.periodic(
    const Duration(seconds: 1), 
    (_) => DateTime.now(),
  ).asBroadcastStream();
}

String _isolateDerivePinHash(Map<String, String> args) {
  final pin = args['pin']!;
  final salt = args['salt']!;
  
  final mac = Hmac(sha256, utf8.encode(pin));
  List<int> u = mac.convert(utf8.encode('$salt\x00\x00\x00\x01')).bytes;
  List<int> t = List<int>.from(u);
  
  for (int i = 1; i < 20000; i++) {
    u = mac.convert(u).bytes;
    for (int j = 0; j < t.length; j++) {
      t[j] ^= u[j];
    }
  }
  return base64Encode(t);
}

String _isolateDeriveLegacyPinHash9999(Map<String, String> args) {
  final pin = args['pin']!;
  final salt = args['salt']!;
  final initialBytes = utf8.encode('$salt$pin');
  Digest digest = sha256.convert(initialBytes);
  for (int i = 0; i < 9999; i++) {
    digest = sha256.convert(digest.bytes + initialBytes);
  }
  return digest.toString();
}

Future<String> derivePinHashAsync(String pin, String salt) async {
  return await compute(_isolateDerivePinHash, {'pin': pin, 'salt': salt});
}

class SystemState extends ChangeNotifier {
  String userName = "User";
  String userEmail = "user@outlook.com";
  Uint8List? userImageBytes;
  bool isPinSet = false;

  bool isActivated = false;
  String activationKey = '';

  final LocalAuthentication _localAuth = LocalAuthentication();

  List<String> visibleQuickSettings = [
    'Wi-Fi', 'Bluetooth', 'Airplane mode',
    'Flash', 'Rotate', 'Battery saver',
    'Data', 'Location', 'Hotspot',
    'Ring', 'Dark Theme', 'Storage',
  ];

  List<String> hiddenQuickSettings = [
    'Brightness', 'Accessibility', 'Play', 'ChatGPT',
    'Calculator', 'Song Search', 'DND', 'Screen Cast',
    'Eye Care', 'Scan QR Code', 'Users & Account', 'Kids Mode'
  ];

  bool notifShowOnLockScreen = true;
  bool notifPlaySound = true;
  bool notifClearOnOpen = false;
  bool notifClosePanelOnOpen = true;
  List<String> excludedNotificationPkgs = [];

  SystemState() {
    _loadProfile();
    checkPinStatus();
    _loadNotificationSettings();
    _loadQuickSettingsPreferences();
    _loadActivationState();
  }

  Future<bool> canUseBiometrics() async {
    if (kIsWeb) return false;
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics(String reason) async {
    if (kIsWeb) return false;
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
      );
    } catch (e) {
      debugPrint("Biometric error: $e");
      return false;
    }
  }

  Future<void> setNewPin(String pin) async {
    const storage = FlutterSecureStorage();
    final random = math.Random.secure();
    final salt = '${DateTime.now().millisecondsSinceEpoch}_${random.nextInt(10000)}';
    
    await storage.write(key: 'device_pin_salt', value: salt);
    final hashed = await derivePinHashAsync(pin, salt);
    await storage.write(key: 'device_pin_hash', value: hashed);
    
    await checkPinStatus();
  }

  Future<void> forceClearPin() async {
    const storage = FlutterSecureStorage();
    await storage.delete(key: 'device_pin_hash');
    await storage.delete(key: 'device_pin_salt');
    await storage.delete(key: 'device_pin');
    await storage.delete(key: 'lockout_until');
    await storage.delete(key: 'failed_attempts');
    isPinSet = false;
    notifyListeners();
  }

  Future<bool> verifyPin(String enteredPin) async {
    const storage = FlutterSecureStorage();
    final storedHash = await storage.read(key: 'device_pin_hash');
    final storedPlain = await storage.read(key: 'device_pin');
    final salt = await storage.read(key: 'device_pin_salt') ?? 'Win11_Launcher_Salt_';
    
    if (storedHash != null) {
      final derivedHash = await derivePinHashAsync(enteredPin, salt);
      if (storedHash == derivedHash) return true;

      final legacy9999Hash = await compute(_isolateDeriveLegacyPinHash9999, {'pin': enteredPin, 'salt': salt});
      if (storedHash == legacy9999Hash) {
        await storage.write(key: 'device_pin_hash', value: derivedHash);
        return true;
      }

      final rawHash = sha256.convert(utf8.encode('$salt$enteredPin')).toString();
      if (storedHash == rawHash) {
        await storage.write(key: 'device_pin_hash', value: derivedHash);
        return true;
      }
    }
    
    if (storedPlain != null && storedPlain == enteredPin) {
      final random = math.Random.secure();
      final newSalt = '${DateTime.now().millisecondsSinceEpoch}_${random.nextInt(10000)}';
      await storage.write(key: 'device_pin_salt', value: newSalt);
      final newHashed = await derivePinHashAsync(enteredPin, newSalt);
      await storage.write(key: 'device_pin_hash', value: newHashed);
      await storage.delete(key: 'device_pin');
      return true;
    }
    
    return false;
  }

  Future<bool> authenticateUser(String reason) async {
    if (!isPinSet) return true; 
    
    final context = navigatorKey.currentContext;
    if (context == null) return false;

    final controller = TextEditingController();
    bool isAuthorized = false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        title: Text(reason, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16)),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: 'Enter your PIN',
            hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
          ),
          onSubmitted: (_) async {
             isAuthorized = await verifyPin(controller.text);
             if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
          ),
          TextButton(
            onPressed: () async {
              isAuthorized = await verifyPin(controller.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Unlock', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (!isAuthorized && context.mounted) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
    }

    return isAuthorized;
  }

  Future<void> _loadActivationState() async {
    const storage = FlutterSecureStorage();
    final activatedStr = await storage.read(key: 'isLauncherActivated');
    isActivated = activatedStr == 'true';
    activationKey = await storage.read(key: 'launcherActivationKey') ?? '';
    notifyListeners();
  }

  Future<bool> verifyAndActivate(String code) async {
    final cleanCode = code.trim().toUpperCase();
    
    const storage = FlutterSecureStorage();
    // CRITICAL FIX: Fetch the exact Installation ID the user saw in the UI
    final String deviceId = await storage.read(key: 'unique_installation_id') ?? 'default_enterprise_salt';

    final String obfuscatedSecret = String.fromCharCodes([87, 105, 110, 49, 49, 80, 67, 76, 97, 117, 110, 99, 104, 101, 114, 83, 101, 99, 114, 101, 116]);
    final validEnterpriseHash = sha256.convert(utf8.encode('${deviceId}_$obfuscatedSecret')).toString().substring(0, 16).toUpperCase();
    
    if (cleanCode == validEnterpriseHash) {
      isActivated = true;
      activationKey = cleanCode;
      await storage.write(key: 'isLauncherActivated', value: 'true');
      await storage.write(key: 'launcherActivationKey', value: cleanCode);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> deactivate() async {
    const storage = FlutterSecureStorage();
    isActivated = false;
    activationKey = '';
    await storage.delete(key: 'isLauncherActivated');
    await storage.delete(key: 'launcherActivationKey');
    notifyListeners();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    userName = prefs.getString('userName') ?? "User";
    userEmail = prefs.getString('userEmail') ?? "user@outlook.com";
    
    String? path = prefs.getString('userImagePath');
    if (path != null && path.isNotEmpty) {
      try {
        final file = File(path);
        if (await file.exists()) {
          userImageBytes = await file.readAsBytes();
        }
      } catch (_) {}
    } else {
      String? b64 = prefs.getString('userImageB64');
      if (b64 != null && b64.isNotEmpty) {
        try { userImageBytes = base64Decode(b64); } catch (_) {}
      }
    }
    notifyListeners();
  }

  Future<void> saveProfile(String name, Uint8List? imageBytes) async {
    userName = name;
    userImageBytes = imageBytes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', name);
    if (imageBytes != null) {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/profile_pic.png');
      await file.writeAsBytes(imageBytes);
      await prefs.setString('userImagePath', file.path);
      await prefs.remove('userImageB64'); 
    }
    notifyListeners();
  }

  Future<void> updateUserName(String name) async {
    userName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', name);
    notifyListeners();
  }

  Future<void> updateUserEmail(String email) async {
    userEmail = email;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userEmail', email);
    notifyListeners();
  }

  Future<void> checkPinStatus() async {
    const storage = FlutterSecureStorage();
    String? hash = await storage.read(key: 'device_pin_hash');
    String? plain = await storage.read(key: 'device_pin');
    isPinSet = (hash != null && hash.isNotEmpty) || (plain != null && plain.isNotEmpty);
    notifyListeners();
  }

  Future<bool> verifyAndDisablePin(String enteredPin) async {
    const storage = FlutterSecureStorage();
    final storedHash = await storage.read(key: 'device_pin_hash');
    final storedPlain = await storage.read(key: 'device_pin');
    final salt = await storage.read(key: 'device_pin_salt') ?? 'Win11_Launcher_Salt_';
    
    final derivedHash = await derivePinHashAsync(enteredPin, salt);
    final legacy9999Hash = await compute(_isolateDeriveLegacyPinHash9999, {'pin': enteredPin, 'salt': salt});
    final rawHash = sha256.convert(utf8.encode('$salt$enteredPin')).toString();

    if ((storedHash != null && (storedHash == derivedHash || storedHash == legacy9999Hash || storedHash == rawHash)) ||
        (storedPlain != null && storedPlain == enteredPin)) {
      await storage.delete(key: 'device_pin_hash');
      await storage.delete(key: 'device_pin_salt');
      await storage.delete(key: 'device_pin');
      await storage.delete(key: 'lockout_until');
      await storage.delete(key: 'failed_attempts');
      isPinSet = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> _loadNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    notifShowOnLockScreen = prefs.getBool('notifShowOnLockScreen') ?? true;
    notifPlaySound = prefs.getBool('notifPlaySound') ?? true;
    notifClearOnOpen = prefs.getBool('notifClearOnOpen') ?? false;
    notifClosePanelOnOpen = prefs.getBool('notifClosePanelOnOpen') ?? true;
    excludedNotificationPkgs = prefs.getStringList('excludedNotificationPkgs') ?? [];
    notifyListeners();
  }

  void updateNotificationSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == 'notifShowOnLockScreen') notifShowOnLockScreen = value;
    if (key == 'notifPlaySound') notifPlaySound = value;
    if (key == 'notifClearOnOpen') notifClearOnOpen = value;
    if (key == 'notifClosePanelOnOpen') notifClosePanelOnOpen = value;
    await prefs.setBool(key, value);
    notifyListeners();
  }

  void toggleAppNotificationExclusion(String packageName) async {
    if (excludedNotificationPkgs.contains(packageName)) {
      excludedNotificationPkgs.remove(packageName);
    } else {
      excludedNotificationPkgs.add(packageName);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('excludedNotificationPkgs', excludedNotificationPkgs);
    notifyListeners();
  }

  Future<void> _loadQuickSettingsPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? savedVisible = prefs.getStringList('visibleQuickSettings');
    List<String>? savedHidden = prefs.getStringList('hiddenQuickSettings');

    if (savedVisible != null && savedVisible.isNotEmpty) visibleQuickSettings = savedVisible;
    if (savedHidden != null) hiddenQuickSettings = savedHidden;
    notifyListeners();
  }

  void toggleQuickSettingVisibility(String tileName) async {
    final prefs = await SharedPreferences.getInstance();
    if (visibleQuickSettings.contains(tileName)) {
      visibleQuickSettings.remove(tileName);
      if (!hiddenQuickSettings.contains(tileName)) hiddenQuickSettings.add(tileName);
    } else {
      hiddenQuickSettings.remove(tileName);
      if (!visibleQuickSettings.contains(tileName)) visibleQuickSettings.add(tileName);
    }
    await prefs.setStringList('visibleQuickSettings', visibleQuickSettings);
    await prefs.setStringList('hiddenQuickSettings', hiddenQuickSettings);
    notifyListeners();
  }
}