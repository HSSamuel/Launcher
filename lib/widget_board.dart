import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../../launcher_state.dart';

class WidgetBoard extends StatefulWidget {
  const WidgetBoard({Key? key}) : super(key: key);

  @override
  State<WidgetBoard> createState() => _WidgetBoardState();
}

class _WidgetBoardState extends State<WidgetBoard> {
  String _weatherLocation = "Loading...";
  String _weatherTemp = "--";
  String _weatherDesc = "Fetching weather...";
  IconData _weatherIcon = Icons.cloud;

  String _stockSymbol1 = "AAPL";
  String _stockChange1 = "Loading...";
  String _stockSymbol2 = "GOOGL";
  String _stockChange2 = "Loading...";
  bool _stock1Up = true;
  bool _stock2Up = true;

  @override
  void initState() {
    super.initState();
    _fetchLiveWeatherData();
    _fetchLiveStockData();
  }

  Future<void> _fetchLiveWeatherData() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _weatherDesc = "Location disabled");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _weatherDesc = "Permission denied");
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      
      // CRITICAL FIX: Securely fetches the key injected at compile time
      const String apiKey = String.fromEnvironment('WEATHER_API_KEY', defaultValue: '');
      
      if (apiKey.isEmpty) {
        if (mounted) setState(() => _weatherDesc = "API Key Missing");
        return;
      }

      final url = 'https://api.openweathermap.org/data/2.5/weather?lat=${position.latitude}&lon=${position.longitude}&units=metric&appid=$apiKey';
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _weatherLocation = data['name'];
            _weatherTemp = "${data['main']['temp'].round()}°C";
            
            final desc = data['weather'][0]['description'];
            _weatherDesc = desc[0].toUpperCase() + desc.substring(1);
            
            final iconCode = data['weather'][0]['icon'];
            if (iconCode.contains('01')) _weatherIcon = Icons.wb_sunny;
            else if (iconCode.contains('02') || iconCode.contains('03') || iconCode.contains('04')) _weatherIcon = Icons.cloud;
            else if (iconCode.contains('09') || iconCode.contains('10')) _weatherIcon = Icons.grain;
            else if (iconCode.contains('11')) _weatherIcon = Icons.thunderstorm;
            else _weatherIcon = Icons.cloud;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _weatherDesc = "Offline");
    }
  }

  Future<void> _fetchLiveStockData() async {
    try {
      final headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
      };
      
      final response = await http.get(
        Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/AAPL?region=US&lang=en-US&includePrePost=false&interval=1d&useYfid=true&range=1d'),
        headers: headers
      );
      final response2 = await http.get(
        Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/GOOGL?region=US&lang=en-US&includePrePost=false&interval=1d&useYfid=true&range=1d'),
        headers: headers
      );
      
      if (response.statusCode == 200 && response2.statusCode == 200) {
        final data1 = jsonDecode(response.body);
        final data2 = jsonDecode(response2.body);
        
        final double prev1 = data1['chart']['result'][0]['meta']['chartPreviousClose'];
        final double cur1 = data1['chart']['result'][0]['meta']['regularMarketPrice'];
        final double diff1 = ((cur1 - prev1) / prev1) * 100;

        final double prev2 = data2['chart']['result'][0]['meta']['chartPreviousClose'];
        final double cur2 = data2['chart']['result'][0]['meta']['regularMarketPrice'];
        final double diff2 = ((cur2 - prev2) / prev2) * 100;

        if (mounted) {
          setState(() {
            _stockChange1 = "${diff1 >= 0 ? '+' : ''}${diff1.toStringAsFixed(2)}%";
            _stock1Up = diff1 >= 0;
            _stockChange2 = "${diff2 >= 0 ? '+' : ''}${diff2.toStringAsFixed(2)}%";
            _stock2Up = diff2 >= 0;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _stockChange1 = "Offline";
          _stockChange2 = "Offline";
        });
      }
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
                  StreamBuilder<DateTime>(
                    stream: TimeService.clockStream,
                    builder: (context, snapshot) {
                      final now = snapshot.data ?? DateTime.now();
                      int hour = now.hour;
                      final minute = now.minute.toString().padLeft(2, '0');
                      final period = hour >= 12 ? 'PM' : 'AM';
                      if (hour == 0) hour = 12;
                      else if (hour > 12) hour -= 12;
                      
                      final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
                      final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${hour.toString().padLeft(2, '0')}:$minute $period',
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black87, height: 1.0),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}',
                            style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500),
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
                          // 1. Live Weather Widget
                          _buildWidgetCard(
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
                                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(_weatherTemp, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
                              ],
                            ),
                          ),

                          // 2. Live Stocks Widget
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
                                        'Market Update',
                                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_stockSymbol1, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 13)),
                                    Text(_stockChange1, style: TextStyle(color: _stock1Up ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_stockSymbol2, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 13)),
                                    Text(_stockChange2, style: TextStyle(color: _stock2Up ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
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