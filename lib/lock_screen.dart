import 'dart:typed_data';
import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'desktop_screen.dart';
import 'launcher_state.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({Key? key}) : super(key: key);

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  bool _isSigningIn = false;
  String _currentTime = '';
  String _currentDate = '';
  Timer? _timer;
  final TextEditingController _pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateTime();
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    _pinController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateTime();
      _startTimer();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _stopTimer();
    }
  }

  void _startTimer() {
    _stopTimer();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _updateTime());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _updateTime() {
    final now = DateTime.now();
    int hour = now.hour;
    final minute = now.minute.toString().padLeft(2, '0');
    if (hour == 0) hour = 12;
    else if (hour > 12) hour -= 12;
    
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    
    final weekday = weekdays[now.weekday - 1];
    final month = months[now.month - 1];
    final day = now.day;

    if (mounted) {
      setState(() {
        _currentTime = '$hour:$minute';
        _currentDate = '$weekday, $month $day';
      });
    }
  }

  void _login() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const DesktopScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallpaperUrl = context.watch<LauncherState>().actualWallpaperUrl;
    final userName = context.watch<LauncherState>().userName;
    final userImageBytes = context.watch<LauncherState>().userImageBytes;

    return Scaffold(
      body: GestureDetector(
        onTap: () {
          if (!_isSigningIn) setState(() => _isSigningIn = true);
        },
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < 0 && !_isSigningIn) {
            setState(() => _isSigningIn = true);
          }
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: wallpaperUrl.startsWith('assets/')
                  ? Image.asset(wallpaperUrl, fit: BoxFit.cover)
                  : (wallpaperUrl.startsWith('http')
                      ? CachedNetworkImage(
                          imageUrl: wallpaperUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(color: const Color(0xFF191919)),
                        )
                      : Image.file(File(wallpaperUrl), fit: BoxFit.cover)),
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
                child: _isSigningIn ? _buildSignInView(userName, userImageBytes) : _buildClockView(),
              ),
            ),
            
            Positioned(
              bottom: 24,
              right: 24,
              child: Row(
                children: const [
                  Icon(Icons.wifi, color: Colors.white, size: 20),
                  SizedBox(width: 16),
                  Icon(Icons.battery_full, color: Colors.white, size: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClockView() {
    return Column(
      key: const ValueKey('clockView'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 100),
        Text(
          _currentTime,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 72,
            fontWeight: FontWeight.w500,
            shadows: [Shadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 2))],
          ),
        ),
        Text(
          _currentDate,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w400,
            shadows: [Shadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2))],
          ),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildSignInView(String userName, Uint8List? userImageBytes) {
    return Column(
      key: const ValueKey('signInView'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
          child: userImageBytes != null
              ? ClipOval(child: Image.memory(userImageBytes, fit: BoxFit.cover))
              : const Icon(Icons.person, size: 60, color: Colors.white),
        ),
        const SizedBox(height: 24),
        Text(
          userName,
          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        
        SizedBox(
          width: 250,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pinController,
                  obscureText: true,
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
                      borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                    ),
                  ),
                  onSubmitted: (_) => _login(),
                ),
              ),
              const SizedBox(width: 8),
              
              InkWell(
                onTap: _login,
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
          onPressed: () {
            setState(() {
              _isSigningIn = false;
              _pinController.clear();
            });
          },
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}