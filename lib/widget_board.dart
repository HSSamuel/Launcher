import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';

class WidgetBoard extends StatefulWidget {
  const WidgetBoard({Key? key}) : super(key: key);

  @override
  State<WidgetBoard> createState() => _WidgetBoardState();
}

// UPDATED: Added WidgetsBindingObserver to manage background states
class _WidgetBoardState extends State<WidgetBoard> with WidgetsBindingObserver {
  String _currentTime = '';
  String _currentDate = '';
  Timer? _timer;

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
    super.dispose();
  }

  // UPDATED: Pause timer when app is in the background
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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _updateTime() {
    final now = DateTime.now();
    int hour = now.hour;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    if (hour == 0) hour = 12;
    else if (hour > 12) hour -= 12;
    
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    
    if (mounted) {
      setState(() {
        _currentTime = '${hour.toString().padLeft(2, '0')}:$minute $period';
        _currentDate = '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
      });
    }
  }

  Widget _buildWidgetCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.9), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12.0, top: 12.0, bottom: 12.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F3F3).withOpacity(0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    _currentTime,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black87, height: 1.0),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentDate,
                    style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 24),
                  
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          // 1. Weather Widget
                          _buildWidgetCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(Icons.wb_sunny, color: Colors.orange, size: 18),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Partly Cloudy in Badagry, Lagos',
                                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Text('32°C', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
                              ],
                            ),
                          ),

                          // 2. Stocks Widget
                          _buildWidgetCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(Icons.trending_up, color: Colors.green, size: 18),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Market Update - Tech Stocks Rising',
                                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: const [
                                    Text('AAPL', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 13)),
                                    Text('+1.24%', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: const [
                                    Text('GOOGL', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 13)),
                                    Text('+0.89%', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          
                          // 3. Calendar Widget
                          _buildWidgetCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(Icons.event, color: Colors.blueAccent, size: 18),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Upcoming Events',
                                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Text('No meetings scheduled for today.', style: TextStyle(color: Colors.black54, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}