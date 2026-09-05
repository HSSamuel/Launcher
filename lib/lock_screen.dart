import 'dart:typed_data';
import 'dart:ui';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:battery_plus/battery_plus.dart';

import 'ui/desktop/desktop_screen.dart';
import 'launcher_state.dart';
import 'services/native_bridge.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({Key? key}) : super(key: key);

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _isSigningIn = false;
  
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  Timer? _lockoutTimer;

  List<Map<String, dynamic>> _lockScreenNotifications = [];
  StreamSubscription? _notifSub;

  // Real-time hardware variables
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.discharging;
  bool _isWifiOn = false;
  StreamSubscription? _batterySub;
  StreamSubscription? _hwSub;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _initHardwareListeners();
  }
  
  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _notifSub?.cancel();
    _batterySub?.cancel();
    _hwSub?.cancel();
    super.dispose();
  }

  void _initHardwareListeners() async {
    try {
      final initialHw = await NativeBridge.instance.getHardwareState();
      if (mounted) setState(() => _isWifiOn = initialHw['Wi-Fi'] == true);

      _hwSub = NativeBridge.instance.hardwareStateStream.listen((event) {
        final data = Map<String, dynamic>.from(event);
        if (data.containsKey('Wi-Fi') && mounted) {
          setState(() => _isWifiOn = data['Wi-Fi'] == true);
        }
      });
    } catch (_) {}

    try {
      _batteryLevel = await Battery().batteryLevel;
      _batteryState = await Battery().batteryState;
      _batterySub = Battery().onBatteryStateChanged.listen((state) async {
        final lvl = await Battery().batteryLevel;
        if (mounted) {
          setState(() {
            _batteryState = state;
            _batteryLevel = lvl;
          });
        }
      });
    } catch (_) {}
  }

  void _initNotifications() async {
    try {
      final active = await NativeBridge.instance.getActiveNotifications();
      if (mounted) setState(() => _lockScreenNotifications = active);

      _notifSub = NativeBridge.instance.notificationStream.listen((event) {
        if (!mounted) return;
        final data = Map<String, dynamic>.from(event);
        setState(() {
          if (data['removed'] == true) {
            _lockScreenNotifications.removeWhere((n) => n['key'] == data['key']);
          } else {
            _lockScreenNotifications.removeWhere((n) => n['key'] == data['key']);
            _lockScreenNotifications.insert(0, data);
          }
        });
      });
    } catch (_) {}
  }

  String _hashPin(String pin) {
    final bytes = utf8.encode('Win11_Launcher_Salt_$pin');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  void _handleFailedAttempt() {
    _failedAttempts++;
    if (_failedAttempts >= 5) {
      setState(() {
        _lockoutUntil = DateTime.now().add(const Duration(seconds: 30));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Too many attempts. Locked out for 30 seconds.'), behavior: SnackBarBehavior.floating)
      );
      
      _lockoutTimer?.cancel();
      _lockoutTimer = Timer(const Duration(seconds: 30), () {
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

  Future<void> _login(String enteredPin) async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (_lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!)) {
      final secondsLeft = _lockoutUntil!.difference(DateTime.now()).inSeconds;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Too many attempts. Try again in $secondsLeft seconds.'), behavior: SnackBarBehavior.floating)
      );
      return;
    }

    final storage = const FlutterSecureStorage();
    final state = context.read<LauncherState>();

    if (!state.isPinSet) {
      if (enteredPin.length < 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN must be at least 4 digits'), behavior: SnackBarBehavior.floating)
        );
        return;
      }
      
      final hashedPin = _hashPin(enteredPin);
      await storage.write(key: 'device_pin_hash', value: hashedPin);
      await storage.delete(key: 'device_pin');
      
      await state.checkPinStatus();
      _proceedToDesktop();
      return;
    }

    String? storedHash = await storage.read(key: 'device_pin_hash');
    
    if (storedHash == null) {
      final oldPlaintextPin = await storage.read(key: 'device_pin');
      if (oldPlaintextPin != null) {
        if (enteredPin == oldPlaintextPin) {
          storedHash = _hashPin(enteredPin);
          await storage.write(key: 'device_pin_hash', value: storedHash);
          await storage.delete(key: 'device_pin');
          _failedAttempts = 0;
          _proceedToDesktop();
          return;
        } else {
          _handleFailedAttempt();
          return;
        }
      }
    }

    final enteredHash = _hashPin(enteredPin);
    if (enteredHash == storedHash) {
      _failedAttempts = 0;
      _proceedToDesktop();
    } else {
      _handleFailedAttempt();
    }
  }

  void _proceedToDesktop() {
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DesktopScreen()),
        );
      }
    });
  }

  void _handleSwipeUp() {
    final state = context.read<LauncherState>();
    if (!state.isPinSet) {
      _proceedToDesktop();
    } else if (!_isSigningIn) {
      setState(() => _isSigningIn = true);
    }
  }

  Widget _buildWallpaperFallback(Color accentColor, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withOpacity(0.85),
            isDark ? const Color(0xFF141414) : const Color(0xFFE0E5EC),
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryGauge() {
    bool isCharging = _batteryState == BatteryState.charging || _batteryState == BatteryState.full;
    double fillWidth = 14 * (_batteryLevel / 100).clamp(0.0, 1.0);
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCharging) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.bolt, size: 16, color: Colors.greenAccent)),
        Container(
          width: 18, height: 10,
          decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 1.2), borderRadius: BorderRadius.circular(2)),
          padding: const EdgeInsets.all(1),
          alignment: Alignment.centerLeft,
          child: Container(width: fillWidth, color: isCharging ? Colors.greenAccent : Colors.white),
        ),
        Container(width: 1.5, height: 4, decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final wallpaperUrl = state.actualWallpaperUrl;
    final userName = state.userName;
    final userImageBytes = state.userImageBytes;
    final accent = state.currentAccentColor;
    final isDark = state.isDarkMode;
    final isPinSet = state.isPinSet;

    return Scaffold(
      body: GestureDetector(
        onTap: () {
          if (!_isSigningIn) _handleSwipeUp();
        },
        onVerticalDragUpdate: (details) {
          if (details.primaryDelta! < -10 && !_isSigningIn) {
            _handleSwipeUp();
          }
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: wallpaperUrl.startsWith('assets/')
                  ? Image.asset(
                      wallpaperUrl, 
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _buildWallpaperFallback(accent, isDark),
                    )
                  : (wallpaperUrl.startsWith('http')
                      ? CachedNetworkImage(
                          imageUrl: wallpaperUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => _buildWallpaperFallback(accent, isDark),
                          errorWidget: (context, url, error) => _buildWallpaperFallback(accent, isDark),
                        )
                      : Image.file(
                          File(wallpaperUrl), 
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _buildWallpaperFallback(accent, isDark),
                        )),
            ),
            
            if (_isSigningIn)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                  child: Container(
                    color: Colors.black.withOpacity(0.2),
                  ),
                ),
              ),

            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _isSigningIn 
                  ? _SignInWidget(
                      userName: userName, 
                      userImageBytes: userImageBytes, 
                      isFirstTime: !isPinSet,
                      accentColor: accent,
                      onLogin: _login, 
                      onCancel: () => setState(() => _isSigningIn = false)
                    ) 
                  : _buildClockAndNotifications(),
              ),
            ),
            
            Positioned(
              bottom: 24,
              right: 24,
              child: Row(
                children: [
                  Icon(_isWifiOn ? Icons.wifi : Icons.wifi_off, color: Colors.white, size: 20),
                  const SizedBox(width: 16),
                  _buildBatteryGauge(),
                  const SizedBox(width: 6),
                  Text('$_batteryLevel%', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClockAndNotifications() {
    return Column(
      key: const ValueKey('clockView'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 80),
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
            
            final weekday = weekdays[now.weekday - 1];
            final month = months[now.month - 1];
            final day = now.day;

            return Column(
              children: [
                Text(
                  '$hour:$minute',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 72,
                    fontWeight: FontWeight.w500,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 2))],
                  ),
                ),
                Text(
                  '$weekday, $month $day',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2))],
                  ),
                ),
              ],
            );
          }
        ),
        
        const SizedBox(height: 40),
        
        if (_lockScreenNotifications.isNotEmpty)
          SizedBox(
            height: 250,
            width: 320,
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: _lockScreenNotifications.length > 4 ? 4 : _lockScreenNotifications.length,
              itemBuilder: (context, index) {
                final notif = _lockScreenNotifications[index];
                String title = notif['title'] ?? 'Notification';
                String text = notif['text'] ?? '';
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (text.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                text,
                                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ]
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
        const Spacer(),
      ],
    );
  }
}

class _SignInWidget extends StatefulWidget {
  final String userName;
  final Uint8List? userImageBytes;
  final bool isFirstTime;
  final Color accentColor;
  final Function(String) onLogin;
  final VoidCallback onCancel;

  const _SignInWidget({
    Key? key,
    required this.userName,
    this.userImageBytes,
    required this.isFirstTime,
    required this.accentColor,
    required this.onLogin,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<_SignInWidget> createState() => _SignInWidgetState();
}

class _SignInWidgetState extends State<_SignInWidget> {
  late TextEditingController _pinController;

  @override
  void initState() {
    super.initState();
    _pinController = TextEditingController();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('signInView'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(color: widget.accentColor, shape: BoxShape.circle),
          child: widget.userImageBytes != null
              ? ClipOval(child: Image.memory(widget.userImageBytes!, fit: BoxFit.cover))
              : const Icon(Icons.person, size: 60, color: Colors.white),
        ),
        const SizedBox(height: 24),
        Text(
          widget.userName,
          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (widget.isFirstTime)
          const Text('Create a new PIN', style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 16),
        
        SizedBox(
          width: 250,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'PIN',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.4),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.5), width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: widget.accentColor, width: 2),
                    ),
                  ),
                  onSubmitted: (_) => widget.onLogin(_pinController.text),
                ),
              ),
              const SizedBox(width: 8),
              
              InkWell(
                onTap: () => widget.onLogin(_pinController.text),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
                  ),
                  child: const Icon(Icons.arrow_forward, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}