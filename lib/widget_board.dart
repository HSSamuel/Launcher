import 'dart:ui';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'states/system_state.dart';
import 'states/theme_state.dart';

class WidgetBoard extends StatefulWidget {
  const WidgetBoard({Key? key}) : super(key: key);

  @override
  State<WidgetBoard> createState() => _WidgetBoardState();
}

class _WidgetBoardState extends State<WidgetBoard> {
  // Static cache variables persist across opens to prevent rate limiting
  static String _weatherLocation = "Loading...";
  static String _weatherTemp = "--";
  static String _weatherDesc = "Fetching weather...";
  static IconData _weatherIcon = Icons.cloud;
  static DateTime? _lastWeatherFetch;

  String _stockSymbol1 = "AAPL";
  String _stockChange1 = "Loading...";
  String _stockSymbol2 = "GOOGL";
  String _stockChange2 = "Loading...";
  bool _stock1Up = true;
  bool _stock2Up = true;

  List<String> _upcomingMeetings = [];
  bool _isLoadingMeetings = true;

  @override
  void initState() {
    super.initState();
    _fetchLiveWeatherData();
    _fetchLiveStockData();
    _fetchLiveCalendarEvents();
  }

  Future<void> _fetchLiveCalendarEvents() async {
    try {
      final calendarPlugin = DeviceCalendarPlugin();
      final permissionsGranted = await calendarPlugin.hasPermissions();

      if (permissionsGranted.isSuccess && (permissionsGranted.data ?? false)) {
        final calendarsResult = await calendarPlugin.retrieveCalendars();
        if (calendarsResult.isSuccess && calendarsResult.data != null) {
          late tz.Location safeLocation;
          try { 
            safeLocation = tz.local; 
          } catch (_) { 
            safeLocation = tz.getLocation('UTC'); 
          }
          
          final now = DateTime.now();
          final startDate = tz.TZDateTime(safeLocation, now.year, now.month, now.day);
          final endDate = tz.TZDateTime(safeLocation, now.year, now.month, now.day, 23, 59, 59);

          final eventResults = await Future.wait(
            calendarsResult.data!.map(
              (cal) => calendarPlugin.retrieveEvents(
                cal.id,
                RetrieveEventsParams(startDate: startDate, endDate: endDate),
              ),
            ),
          );

          List<Map<String, dynamic>> rawEvents = [];
          for (var res in eventResults) {
            if (res.isSuccess && res.data != null) {
              for (var ev in res.data!) {
                if (ev.start == null) continue;
                final localStart = ev.start!.toLocal();
                final localEnd = ev.end?.toLocal() ?? localStart.add(const Duration(hours: 1));
                
                if (localEnd.isBefore(now)) continue; 

                final title = (ev.title ?? '').trim();
                final lower = title.toLowerCase();
                if (lower.contains('birthday') || lower.contains('bday') || lower.contains("b'day")) {
                  continue;
                }
                
                rawEvents.add({
                  'title': title,
                  'start': localStart,
                  'location': ev.location,
                  'isAllDay': ev.allDay ?? false,
                });
              }
            }
          }

          rawEvents.sort((a, b) => (a['start'] as DateTime).compareTo(b['start'] as DateTime));
          
          List<String> meetings = [];
          for (var ev in rawEvents.take(3)) {
            final start = ev['start'] as DateTime;
            final isAllDay = ev['isAllDay'] == true;
            
            String timeStr;
            if (isAllDay) {
              timeStr = 'All Day';
            } else if (start.isBefore(now)) {
              timeStr = 'Ongoing now';
            } else {
              int h = start.hour % 12 == 0 ? 12 : start.hour % 12;
              String ampm = start.hour >= 12 ? 'PM' : 'AM';
              String m = start.minute.toString().padLeft(2, '0');
              timeStr = 'at $h:$m $ampm';
            }
            meetings.add('${ev['title']} $timeStr');
          }

          if (mounted) {
            setState(() {
              _upcomingMeetings = meetings;
              _isLoadingMeetings = false;
            });
          }
          return;
        }
      } else {
        if (mounted) {
          setState(() {
            _upcomingMeetings = ["Calendar permission required"];
            _isLoadingMeetings = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingMeetings = false;
        });
      }
    }
  }

  Future<void> _fetchLiveWeatherData() async {
    // 30-minute cooldown cache to protect against BigDataCloud & Open-Meteo rate limits
    if (_lastWeatherFetch != null && DateTime.now().difference(_lastWeatherFetch!).inMinutes < 30) {
      if (mounted) setState(() {});
      return;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted && _weatherDesc == "Fetching weather...") {
          setState(() => _weatherDesc = "Location disabled");
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          if (mounted && _weatherDesc == "Fetching weather...") {
            setState(() { 
              _weatherDesc = "Location permission needed";
              _weatherTemp = "--";
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted && _weatherDesc == "Fetching weather...") {
          setState(() { 
            _weatherDesc = "Location permission needed";
            _weatherTemp = "--";
          });
        }
        return;
      }

      // Enforced timeout to prevent thread hangs on weak GPS reception
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 6),
      );
      
      final url = 'https://api.open-meteo.com/v1/forecast?latitude=${pos.latitude}&longitude=${pos.longitude}&current=temperature_2m,weather_code';
      
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final current = data['current'];
        final double temp = (current['temperature_2m'] as num).toDouble();
        final int code = (current['weather_code'] as num).toInt();
        
        String desc = 'Clear';
        IconData icon = Icons.wb_sunny;
        
        if (code == 0) { desc = 'Clear sky'; icon = Icons.wb_sunny; }
        else if (code >= 1 && code <= 3) { desc = 'Partly cloudy'; icon = Icons.cloud_queue; }
        else if (code == 45 || code == 48) { desc = 'Fog'; icon = Icons.foggy; }
        else if (code >= 51 && code <= 55) { desc = 'Drizzle'; icon = Icons.grain; }
        else if (code >= 61 && code <= 65) { desc = 'Rain'; icon = Icons.water_drop; }
        else if (code >= 71 && code <= 75) { desc = 'Snow'; icon = Icons.ac_unit; }
        else if (code >= 95) { desc = 'Thunderstorm'; icon = Icons.thunderstorm; }

        String loc = _weatherLocation != "Loading..." && _weatherLocation != "Local Area"
            ? _weatherLocation 
            : 'Local Area';

        try {
          final locRes = await http.get(Uri.parse(
            'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${pos.latitude}&longitude=${pos.longitude}&localityLanguage=en'
          )).timeout(const Duration(seconds: 6));
          if (locRes.statusCode == 200) {
            final locData = jsonDecode(locRes.body);
            loc = locData['city'] ?? locData['locality'] ?? loc;
          }
        } catch (_) {}

        _weatherTemp = "${temp.round()}°C";
        _weatherDesc = desc;
        _weatherIcon = icon;
        _weatherLocation = loc;
        _lastWeatherFetch = DateTime.now();

        if (mounted) setState(() {});
      }
    } catch (e) {
      if (mounted && _weatherDesc == "Fetching weather...") {
        setState(() => _weatherDesc = "Offline");
      }
    }
  }

  Future<void> _fetchLiveStockData() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedStock1 = prefs.getString('cached_stock_1');
    final cachedStock2 = prefs.getString('cached_stock_2');
    final lastFetch = prefs.getInt('last_stock_fetch') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (cachedStock1 != null && cachedStock2 != null) {
      if (mounted) {
        setState(() {
          _stockChange1 = cachedStock1;
          _stockChange2 = cachedStock2;
          _stock1Up = !cachedStock1.startsWith('-');
          _stock2Up = !cachedStock2.startsWith('-');
        });
      }
      if (now - lastFetch < 3600000) return; 
    }

    try {
      final headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'Accept': 'application/json',
      };
      
      Future<http.Response> fetchWithRetry(String url) async {
        int attempts = 0;
        while (attempts < 3) {
          if (!mounted) return http.Response('{}', 499);
          try {
            final response = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 8));
            if (response.statusCode == 200) return response;
            if (response.statusCode == 429) {
              attempts++;
              if (attempts < 3) {
                await Future.delayed(Duration(seconds: math.pow(2, attempts + 1).toInt() + math.Random().nextInt(2)));
              }
              continue;
            }
          } catch (_) {}
          attempts++;
          if (attempts < 3) await Future.delayed(Duration(seconds: 2 * attempts));
        }
        return http.Response('{}', 403);
      }

      final responses = await Future.wait([
        fetchWithRetry('https://query2.finance.yahoo.com/v8/finance/chart/AAPL?region=US&lang=en-US&includePrePost=false&interval=1d&useYfid=true&range=1d'),
        fetchWithRetry('https://query2.finance.yahoo.com/v8/finance/chart/GOOGL?region=US&lang=en-US&includePrePost=false&interval=1d&useYfid=true&range=1d')
      ]);

      final response = responses[0];
      final response2 = responses[1];
      
      if (response.statusCode == 200 && response2.statusCode == 200) {
        final data1 = jsonDecode(response.body);
        final data2 = jsonDecode(response2.body);
        
        final result1 = data1['chart']?['result'] as List?;
        final result2 = data2['chart']?['result'] as List?;

        if (result1 != null && result1.isNotEmpty && result2 != null && result2.isNotEmpty) {
          final meta1 = result1[0]['meta'];
          final meta2 = result2[0]['meta'];

          if (meta1 != null && meta2 != null) {
            final double prev1 = (meta1['chartPreviousClose'] as num?)?.toDouble() ?? 0.0;
            final double cur1 = (meta1['regularMarketPrice'] as num?)?.toDouble() ?? 0.0;
            final double diff1 = prev1 != 0 ? ((cur1 - prev1) / prev1) * 100 : 0.0;

            final double prev2 = (meta2['chartPreviousClose'] as num?)?.toDouble() ?? 0.0;
            final double cur2 = (meta2['regularMarketPrice'] as num?)?.toDouble() ?? 0.0;
            final double diff2 = prev2 != 0 ? ((cur2 - prev2) / prev2) * 100 : 0.0;

            if (mounted) {
              setState(() {
                _stockChange1 = "${diff1 >= 0 ? '+' : ''}${diff1.toStringAsFixed(2)}%";
                _stock1Up = diff1 >= 0;
                _stockChange2 = "${diff2 >= 0 ? '+' : ''}${diff2.toStringAsFixed(2)}%";
                _stock2Up = diff2 >= 0;
              });
            }
            await prefs.setString('cached_stock_1', _stockChange1);
            await prefs.setString('cached_stock_2', _stockChange2);
            await prefs.setInt('last_stock_fetch', now);
          }
        }
      } else {
        throw Exception('API returned non-200 status');
      }
    } catch (_) {
      if (mounted && cachedStock1 == null) {
        setState(() {
          _stockChange1 = "Unavailable";
          _stockChange2 = "Unavailable";
        });
      }
    }
  }

  Widget _buildWidgetCard({required Widget child, required bool isDark}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.5) : Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white12 : Colors.white.withOpacity(0.9), width: 1.5),
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
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white70 : Colors.black54;

    return Padding(
      padding: const EdgeInsets.only(left: 12.0, top: 12.0, bottom: 12.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E).withOpacity(0.98) : const Color(0xFFF3F3F3).withOpacity(0.98),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  StreamBuilder<DateTime>(
                    stream: TimeService.clockStream,
                    builder: (context, snapshot) {
                      final now = snapshot.data ?? DateTime.now();
                      int hour = now.hour;
                      final minute = now.minute.toString().padLeft(2, '0');
                      final period = hour >= 12 ? 'PM' : 'AM';
                      if (hour == 0) hour = 12;
                      else if (hour > 12) hour -= 12;
                      
                      const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
                      const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${hour.toString().padLeft(2, '0')}:$minute $period',
                            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textColor, height: 1.0),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}',
                            style: TextStyle(fontSize: 13, color: subColor, fontWeight: FontWeight.w500),
                          ),
                        ]
                      );
                    }
                  ),
                  const SizedBox(height: 24),
                  
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          _buildWidgetCard(
                            isDark: isDark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(_weatherIcon, color: Colors.orange, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '$_weatherDesc in $_weatherLocation',
                                        style: TextStyle(fontWeight: FontWeight.w600, color: textColor, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(_weatherTemp, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
                              ],
                            ),
                          ),

                          _buildWidgetCard(
                            isDark: isDark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.trending_up, color: Colors.green, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Market Update',
                                        style: TextStyle(fontWeight: FontWeight.w600, color: textColor, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_stockSymbol1, style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 13)),
                                    Text(_stockChange1, style: TextStyle(color: _stock1Up ? Colors.green : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_stockSymbol2, style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 13)),
                                    Text(_stockChange2, style: TextStyle(color: _stock2Up ? Colors.green : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          
                          _buildWidgetCard(
                            isDark: isDark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.event, color: Colors.blueAccent, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Upcoming Events',
                                        style: TextStyle(fontWeight: FontWeight.w600, color: textColor, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (_isLoadingMeetings)
                                  const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                else if (_upcomingMeetings.isEmpty)
                                  Text('No meetings scheduled for today.', style: TextStyle(color: subColor, fontSize: 12))
                                else
                                  ..._upcomingMeetings.map((m) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.circle, size: 6, color: themeState.foregroundAccentColor),
                                        const SizedBox(width: 6),
                                        Expanded(child: Text(m, style: TextStyle(color: textColor, fontSize: 12))),
                                      ],
                                    ),
                                  )).toList()
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