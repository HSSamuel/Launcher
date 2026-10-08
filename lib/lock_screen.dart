import 'dart:typed_data';
import 'dart:ui';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:torch_light/torch_light.dart';

import 'ui/desktop/desktop_screen.dart';
import 'states/desktop_state.dart';
import 'states/theme_state.dart';
import 'states/system_state.dart';
import 'services/native_bridge.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback? onUnlocked;

  const LockScreen({Key? key, this.onUnlocked}) : super(key: key);

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with TickerProviderStateMixin {
  bool _isSigningIn = false;
  
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  Timer? _lockoutTimer;

  int _batteryLevel = 100;
  bool _isCharging = false;
  bool _isWifiOn = false;
  bool _isFlashlightOn = false;
  
  StreamSubscription? _hwSub;

  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  final ValueNotifier<double> _dragOffsetNotifier = ValueNotifier<double>(0.0);
  late AnimationController _snapController;
  late Animation<double> _snapAnimation;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    _initHardwareListeners();
    _initLockoutState();
    
    _bounceController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 1000)
    )..repeat(reverse: true);
    
    _bounceAnimation = Tween<double>(begin: 0, end: -10).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut)
    );

    _snapController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 160)
    );
    _snapAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _snapController, curve: const Cubic(0.05, 0.7, 0.1, 1.0))
    );
    _snapController.addListener(() {
      _dragOffsetNotifier.value = _snapAnimation.value;
    });
  }
  
  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _lockoutTimer?.cancel();
    _hwSub?.cancel();
    _bounceController.dispose(); 
    _snapController.dispose();
    _dragOffsetNotifier.dispose();
    super.dispose();
  }

  void _initLockoutState() async {
    const storage = FlutterSecureStorage();
    final failedAttemptsStr = await storage.read(key: 'failed_attempts');
    _failedAttempts = int.tryParse(failedAttemptsStr ?? '0') ?? 0;

    final lockoutStr = await storage.read(key: 'lockout_until');
    if (lockoutStr != null) {
      final lockoutDate = DateTime.tryParse(lockoutStr);
      if (lockoutDate != null && lockoutDate.isAfter(DateTime.now())) {
        if (mounted) {
          setState(() {
            _lockoutUntil = lockoutDate;
            if (_failedAttempts < 5) _failedAttempts = 5; 
          });
        }
        final diff = lockoutDate.difference(DateTime.now());
        _lockoutTimer = Timer(diff, () async {
          await storage.delete(key: 'lockout_until');
          await storage.delete(key: 'failed_attempts');
          if (mounted) {
            setState(() {
              _failedAttempts = 0;
              _lockoutUntil = null;
            });
          }
        });
      } else {
        await storage.delete(key: 'lockout_until');
        await storage.delete(key: 'failed_attempts');
        _failedAttempts = 0;
      }
    }
  }

  void _initHardwareListeners() async {
    try {
      _hwSub = NativeBridge.instance.hardwareStateStream.listen((event) {
        final data = Map<String, dynamic>.from(event);
        if (mounted) {
          setState(() {
            if (data.containsKey('Wi-Fi')) _isWifiOn = data['Wi-Fi'] == true;
            if (data.containsKey('battery_level')) _batteryLevel = data['battery_level'];
            if (data.containsKey('battery_charging')) _isCharging = data['battery_charging'];
          });
        }
      });
    } catch (_) {}
  }

  Future<void> _toggleFlashlight(bool turnOn) async {
    if (_isFlashlightOn == turnOn) return; 
    try {
      if (turnOn) {
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }
      setState(() => _isFlashlightOn = turnOn);
      HapticFeedback.lightImpact(); 
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flashlight not available', style: TextStyle(color: Colors.white)), behavior: SnackBarBehavior.floating)
      );
    }
  }

  void _handleFailedAttempt() async {
    _failedAttempts++;
    await const FlutterSecureStorage().write(key: 'failed_attempts', value: _failedAttempts.toString());

    if (_failedAttempts >= 5) {
      final lockoutDate = DateTime.now().add(const Duration(seconds: 30));
      setState(() => _lockoutUntil = lockoutDate);
      
      const FlutterSecureStorage().write(key: 'lockout_until', value: lockoutDate.toIso8601String());
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Too many attempts. Locked out for 30 seconds.'), behavior: SnackBarBehavior.floating)
      );
      
      _lockoutTimer?.cancel();
      _lockoutTimer = Timer(const Duration(seconds: 30), () async {
        await const FlutterSecureStorage().delete(key: 'lockout_until');
        await const FlutterSecureStorage().delete(key: 'failed_attempts');
        if (mounted) {
          setState(() {
            _failedAttempts = 0;
            _lockoutUntil = null;
          });
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect PIN'), behavior: SnackBarBehavior.floating)
      );
    }
  }

  Future<void> _login({String? enteredPin, bool biometricBypass = false}) async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (biometricBypass) {
      _failedAttempts = 0;
      await const FlutterSecureStorage().delete(key: 'failed_attempts');
      await const FlutterSecureStorage().delete(key: 'lockout_until');
      _proceedToDesktop();
      return;
    }

    if (_lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!)) {
      final secondsLeft = _lockoutUntil!.difference(DateTime.now()).inSeconds;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Too many attempts. Try again in $secondsLeft seconds.'), behavior: SnackBarBehavior.floating)
      );
      return;
    }

    final systemState = context.read<SystemState>();
    
    bool hasPin = systemState.isPinSet;
    if (!hasPin) {
      final storage = const FlutterSecureStorage();
      final hash = await storage.read(key: 'device_pin_hash');
      if (hash != null) hasPin = true;
    }

    if (!hasPin) {
      _proceedToDesktop();
      return;
    }

    if (enteredPin == null) {
      return;
    }

    final isValid = await systemState.verifyPin(enteredPin);

    if (isValid) {
      _failedAttempts = 0;
      await const FlutterSecureStorage().delete(key: 'failed_attempts');
      await const FlutterSecureStorage().delete(key: 'lockout_until');
      _proceedToDesktop();
    } else {
      _handleFailedAttempt();
    }
  }

  void _proceedToDesktop() async {
    bool unlocked = await NativeBridge.instance.dismissSystemLock();
    if (!unlocked) {
      if (mounted) setState(() => _isSigningIn = false);
      return;
    }

    if (!mounted) return;
    context.read<DesktopState>().applySystemUI();

    if (widget.onUnlocked != null) {
      widget.onUnlocked!();
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const DesktopScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    }
  }

  void _handleSwipeUp() async {
    final systemState = context.read<SystemState>();
    
    bool hasPin = systemState.isPinSet;
    if (!hasPin) {
      final storage = const FlutterSecureStorage();
      final hash = await storage.read(key: 'device_pin_hash');
      if (hash != null) hasPin = true;
    }

    if (!hasPin) {
      _proceedToDesktop();
    } else if (!_isSigningIn) {
      setState(() {
        _isSigningIn = true;
        _bounceController.stop(); 
      });
    }
  }

  void _animateSwipeUp() {
    if (_isSigningIn) return;
    final screenHeight = MediaQuery.of(context).size.height;
    
    _snapAnimation = Tween<double>(begin: _dragOffsetNotifier.value, end: -screenHeight).animate(
      CurvedAnimation(parent: _snapController, curve: const Cubic(0.05, 0.7, 0.1, 1.0))
    );
    
    _snapController.forward(from: 0).then((_) {
      _handleSwipeUp();
      _dragOffsetNotifier.value = 0.0;
    });
  }

  Widget _buildBatteryGauge() {
    double fillWidth = 14 * (_batteryLevel / 100).clamp(0.0, 1.0);
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isCharging) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.bolt, size: 16, color: Colors.greenAccent)),
        Container(
          width: 18, height: 10,
          decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 1.2), borderRadius: BorderRadius.circular(2)),
          padding: const EdgeInsets.all(1),
          alignment: Alignment.centerLeft,
          child: Container(width: fillWidth, color: _isCharging ? Colors.greenAccent : Colors.white),
        ),
        Container(width: 1.5, height: 4, decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.horizontal(right: Radius.circular(2)))),
      ],
    );
  }

  Widget _buildClockProfileWidget(ThemeState themeState, String userName, Uint8List? userImageBytes) {
    return SafeArea(
      child: Column(
        key: const ValueKey('clockView'),
        children: [
          const Spacer(flex: 1), 
          Column(
            children: [
              Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  color: themeState.currentAccentColor, 
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 4))],
                ),
                child: userImageBytes != null
                    ? ClipOval(child: Image.memory(userImageBytes, fit: BoxFit.cover, cacheWidth: 240))
                    : Icon(Icons.person, size: 54, color: themeState.textOnAccentColor),
              ),
              const SizedBox(height: 14),
              Text(
                userName, 
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600, shadows: [Shadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2))])
              ),
            ],
          ),
          const SizedBox(height: 24), 
          StreamBuilder<DateTime>(
            stream: TimeService.clockStream,
            builder: (context, snapshot) {
              final now = snapshot.data ?? DateTime.now();
              int hour = now.hour;
              final minute = now.minute.toString().padLeft(2, '0');
              if (hour == 0) hour = 12;
              else if (hour > 12) hour -= 12;
              
              const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
              const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
              
              return Column(
                children: [
                  Text('$hour:$minute', style: const TextStyle(color: Colors.white, fontSize: 72, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2))])),
                  Text('${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2))])),
                ],
              );
            }
          ),
          const Spacer(flex: 2), 
          AnimatedBuilder(
            animation: _bounceAnimation,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _bounceAnimation.value),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.keyboard_double_arrow_up, color: Colors.white, size: 24, shadows: [Shadow(color: Colors.black45, blurRadius: 4)]),
                    SizedBox(height: 4),
                    Text('Swipe up to unlock', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black45, blurRadius: 4)])),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 72), 
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final systemState = context.watch<SystemState>();

    final userName = systemState.userName;
    final userImageBytes = systemState.userImageBytes;
    final accent = themeState.currentAccentColor;
    final isPinSet = systemState.isPinSet;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () {
          if (!_isSigningIn) _animateSwipeUp();
        },
        onVerticalDragUpdate: (details) {
          if (_isSigningIn) return;
          double next = _dragOffsetNotifier.value + (details.primaryDelta ?? 0);
          if (next > 0) next = 0;
          _dragOffsetNotifier.value = next;
        },
        onVerticalDragEnd: (details) {
          if (_isSigningIn) return;
          if (_dragOffsetNotifier.value < -120 || (details.primaryVelocity ?? 0) < -300) {
            _animateSwipeUp();
          } else {
            _snapAnimation = Tween<double>(begin: _dragOffsetNotifier.value, end: 0.0).animate(
              CurvedAnimation(parent: _snapController, curve: const Cubic(0.05, 0.7, 0.1, 1.0))
            );
            _snapController.forward(from: 0);
          }
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: _isSigningIn 
                ? BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                    child: Container(color: Colors.black.withOpacity(0.5)),
                  )
                : Container(color: Colors.black.withOpacity(0.15)),
            ),

            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                switchInCurve: const Cubic(0.05, 0.7, 0.1, 1.0),
                switchOutCurve: Curves.easeIn,
                child: _isSigningIn 
                  ? _SignInWidget(
                      userName: userName, 
                      userImageBytes: userImageBytes, 
                      isPinSet: isPinSet,
                      accentColor: accent,
                      textOnAccentColor: themeState.textOnAccentColor,
                      onLogin: _login, 
                      onCancel: () {
                        setState(() {
                          _isSigningIn = false;
                          _dragOffsetNotifier.value = 0.0;
                          _bounceController.repeat(reverse: true); 
                        });
                      },
                    ) 
                  : ValueListenableBuilder<double>(
                      valueListenable: _dragOffsetNotifier,
                      builder: (context, dragOffset, _) {
                        return Transform.translate(
                          offset: Offset(0, dragOffset),
                          child: _buildClockProfileWidget(themeState, userName, userImageBytes),
                        );
                      },
                    ),
              ),
            ),
            
            Positioned(
              bottom: 24,
              left: 24,
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity > 100) {
                    _toggleFlashlight(!_isFlashlightOn); 
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isFlashlightOn ? Colors.white : Colors.black.withOpacity(0.35),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(_isFlashlightOn ? 1.0 : 0.4), width: 1.5),
                  ),
                  child: Icon(
                    _isFlashlightOn ? Icons.flashlight_on : Icons.flashlight_off,
                    color: _isFlashlightOn ? Colors.black : Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: 24,
              right: 24,
              child: Row(
                children: [
                  Icon(_isWifiOn ? Icons.wifi : Icons.wifi_off, color: Colors.white, size: 18),
                  const SizedBox(width: 14),
                  _buildBatteryGauge(),
                  const SizedBox(width: 6),
                  Text('$_batteryLevel%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignInWidget extends StatefulWidget {
  final String userName;
  final Uint8List? userImageBytes;
  final bool isPinSet;
  final Color accentColor;
  final Color textOnAccentColor;
  final Function({String? enteredPin, bool biometricBypass}) onLogin;
  final VoidCallback onCancel;

  const _SignInWidget({
    Key? key, required this.userName, this.userImageBytes, required this.isPinSet, required this.accentColor, required this.textOnAccentColor, required this.onLogin, required this.onCancel,
  }) : super(key: key);

  @override
  State<_SignInWidget> createState() => _SignInWidgetState();
}

class _SignInWidgetState extends State<_SignInWidget> {
  String _enteredPin = '';
  bool _canUseBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final systemState = context.read<SystemState>();
    final canUse = await systemState.canUseBiometrics();
    if (mounted) setState(() => _canUseBiometrics = canUse);
  }

  void _handleBiometricUnlock() async {
    final systemState = context.read<SystemState>();
    final success = await systemState.authenticateWithBiometrics('Authenticate to unlock Win11 PC Launcher');
    if (success) {
      widget.onLogin(biometricBypass: true);
    }
  }

  void _handleForgotPin() async {
    final systemState = context.read<SystemState>();
    final success = await systemState.authenticateWithBiometrics('Verify your device credentials to reset your launcher PIN');
    if (success) {
      await systemState.forceClearPin();
      widget.onLogin(biometricBypass: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN successfully removed.')));
      }
    }
  }

  void _handleNumpad(String digit) {
    HapticFeedback.lightImpact();
    if (_enteredPin.length < 4) {
      setState(() {
        _enteredPin += digit;
      });
      if (_enteredPin.length == 4) {
        widget.onLogin(enteredPin: _enteredPin);
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && _enteredPin.length == 4) {
            setState(() { _enteredPin = ''; });
          }
        });
      }
    }
  }

  void _handleBackspace() {
    HapticFeedback.lightImpact();
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  Widget _numButton(String digit) {
    return InkWell(
      onTap: () => _handleNumpad(digit),
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 60, height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.1)),
        child: Text(digit, style: const TextStyle(color: Colors.white, fontSize: 24)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('signInView'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 110, height: 110,
          decoration: BoxDecoration(color: widget.accentColor, shape: BoxShape.circle),
          child: widget.userImageBytes != null
              ? ClipOval(child: Image.memory(widget.userImageBytes!, fit: BoxFit.cover, cacheWidth: 220))
              : Icon(Icons.person, size: 54, color: widget.textOnAccentColor),
        ),
        const SizedBox(height: 20),
        Text(widget.userName, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600)),
        
        const SizedBox(height: 54),
        
        if (!widget.isPinSet) ...[
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              elevation: 0,
            ),
            onPressed: () => widget.onLogin(enteredPin: ''),
            child: const Text('Sign in', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Icon(
                index < _enteredPin.length ? Icons.circle : Icons.circle_outlined,
                color: Colors.white,
                size: 14,
              ),
            )),
          ),
          
          const SizedBox(height: 64),
          
          Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [_numButton('1'), const SizedBox(width: 24), _numButton('2'), const SizedBox(width: 24), _numButton('3')]),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [_numButton('4'), const SizedBox(width: 24), _numButton('5'), const SizedBox(width: 24), _numButton('6')]),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [_numButton('7'), const SizedBox(width: 24), _numButton('8'), const SizedBox(width: 24), _numButton('9')]),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center, 
                children: [
                  _canUseBiometrics 
                    ? InkWell(
                        onTap: _handleBiometricUnlock,
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          width: 60, height: 60, alignment: Alignment.center, 
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blueAccent.withOpacity(0.15)),
                          child: const Icon(Icons.fingerprint, color: Colors.blueAccent, size: 28)
                        ),
                      )
                    : const SizedBox(width: 60), 
                  const SizedBox(width: 24), 
                  _numButton('0'), 
                  const SizedBox(width: 24), 
                  InkWell(
                    onTap: _handleBackspace,
                    borderRadius: BorderRadius.circular(30),
                    child: Container(width: 60, height: 60, alignment: Alignment.center, child: const Icon(Icons.backspace_outlined, color: Colors.white, size: 22)),
                  )
                ]
              ),
            ],
          ),
        ],
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: widget.onCancel, 
              child: const Text('Cancel', style: TextStyle(color: Colors.white70))
            ),
            if (widget.isPinSet && _canUseBiometrics) ...[
              Container(height: 14, width: 1.5, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 16)),
              TextButton(
                onPressed: _handleForgotPin, 
                child: const Text('Forgot PIN?', style: TextStyle(color: Colors.white70))
              ),
            ]
          ],
        ),
      ],
    );
  }
}