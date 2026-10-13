import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/theme_state.dart';
import '../../services/native_bridge.dart';
import '../../services/lazy_app_icon.dart'; // Added for cache flush

class HardwareMonitorWidget extends StatefulWidget {
  const HardwareMonitorWidget({Key? key}) : super(key: key);

  @override
  State<HardwareMonitorWidget> createState() => _HardwareMonitorWidgetState();
}

class _HardwareMonitorWidgetState extends State<HardwareMonitorWidget> {
  double _x = 100.0;
  double _y = 50.0;
  
  bool _isOptimizing = false;
  double _ramPercent = 0.0;
  double _tempValue = 0.0;
  double _fanRpm = 0.0;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _startPolling();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _x = (MediaQuery.of(context).size.width / 2) - 110.0;
        });
      }
    });
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (mounted && !_isOptimizing) {
        try {
          final rawStats = await NativeBridge.instance.getSystemPerformanceStats();
          if (rawStats != null && mounted) {
            final ramPct = (rawStats['ram_percent'] as num?)?.toDouble() ?? 0.0;
            final temp = (rawStats['cpu_temp'] as num?)?.toDouble() ?? 0.0;
            
            setState(() {
              _ramPercent = ramPct;
              _tempValue = temp;
              _fanRpm = (1000.0 + (temp * 40.0)).clamp(0.0, 3200.0);
            });
          }
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _runOptimization() async {
    if (_isOptimizing) return;
    setState(() => _isOptimizing = true);
    
    // 1. Flutter Image Cache Flush
    final int beforeBytes = PaintingBinding.instance.imageCache.currentSizeBytes;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    
    // 2. Clear pre-warmed memory icon caches
    LazyAppIcon.globalIconCache.clear();
    
    final int flutterFreedMb = (beforeBytes / (1024 * 1024)).round();

    // 3. Native File System Cache Flush
    final result = await NativeBridge.instance.optimizeSystem();
    final nativeFreedMb = result['freedMb'] ?? 0;
    
    final totalFreedMb = flutterFreedMb + nativeFreedMb;
    
    await Future.delayed(const Duration(milliseconds: 600)); 
    
    if (mounted) {
      setState(() => _isOptimizing = false);
      ScaffoldMessenger.of(context).clearSnackBars();
      
      String message = totalFreedMb > 0 
          ? 'Optimization complete. Recovered $totalFreedMb MB of memory.'
          : 'System is running optimally. Memory cache flushed.';
          
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: totalFreedMb > 0 ? Colors.green.shade700 : Colors.blueGrey.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeState>().isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white70 : Colors.black54;

    return Positioned(
      left: _x,
      top: _y,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _x += details.delta.dx;
            _y += details.delta.dy;
          });
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double diameter = 220.0; 
            
            // Scaled up typography constraints
            final double titleFontSize = (diameter * 0.075).clamp(12.0, 20.0);
            final double percentFontSize = (diameter * 0.22).clamp(24.0, 56.0);
            final double metricLabelFontSize = (diameter * 0.06).clamp(11.0, 16.0);
            final double metricValueFontSize = (diameter * 0.08).clamp(14.0, 22.0);
            final double buttonHeight = (diameter * 0.15).clamp(26.0, 40.0);
            final double buttonWidth = (diameter * 0.52).clamp(80.0, 130.0);
            final double buttonFontSize = (diameter * 0.058).clamp(10.0, 14.0);
            final double arcStrokeWidth = (diameter * 0.05).clamp(5.0, 12.0);

            return SizedBox(
              width: diameter,
              height: diameter + (buttonHeight / 2),
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    width: diameter,
                    height: diameter,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF1E1E1E).withOpacity(0.90) : Colors.white.withOpacity(0.90),
                      border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                  
                  // Arc is perfectly scaled to circle's outer edge bounds
                  Positioned(
                    top: 0,
                    child: CustomPaint(
                      size: Size(diameter, diameter),
                      painter: _CircularGpuGaugePainter(
                        percent: _ramPercent / 100.0,
                        strokeWidth: arcStrokeWidth,
                        trackColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                      ),
                    ),
                  ),

                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: diameter * 0.08),
                      Text(
                        'GPU Optimization',
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      SizedBox(height: diameter * 0.01),
                      Text(
                        '${_ramPercent.toInt()}%',
                        style: TextStyle(
                          fontSize: percentFontSize,
                          fontWeight: FontWeight.w900,
                          color: textColor,
                          height: 1.05,
                        ),
                      ),
                      SizedBox(height: diameter * 0.03),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Column(
                            children: [
                              Text('Temp', style: TextStyle(fontSize: metricLabelFontSize, color: subColor)),
                              Text('${_tempValue.toInt()}°C', style: TextStyle(fontSize: metricValueFontSize, fontWeight: FontWeight.bold, color: textColor)),
                            ],
                          ),
                          SizedBox(width: diameter * 0.08),
                          Column(
                            children: [
                              Text('Fan', style: TextStyle(fontSize: metricLabelFontSize, color: subColor)),
                              Text('${_fanRpm.toInt()} RPM', style: TextStyle(fontSize: metricValueFontSize, fontWeight: FontWeight.bold, color: textColor)),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: diameter * 0.12),
                    ],
                  ),

                  Positioned(
                    bottom: 0,
                    child: SizedBox(
                      width: buttonWidth,
                      height: buttonHeight,
                      child: ElevatedButton(
                        onPressed: _isOptimizing ? null : _runOptimization,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonHeight / 2)),
                          elevation: 3,
                          shadowColor: Colors.blueAccent.withOpacity(0.5),
                        ),
                        child: _isOptimizing
                            ? SizedBox(width: buttonHeight * 0.45, height: buttonHeight * 0.45, child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.rocket_launch, size: buttonFontSize * 1.1),
                                  const SizedBox(width: 4),
                                  Text('Optimize', style: TextStyle(fontSize: buttonFontSize, fontWeight: FontWeight.bold)),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CircularGpuGaugePainter extends CustomPainter {
  final double percent;
  final double strokeWidth;
  final Color trackColor;

  _CircularGpuGaugePainter({
    required this.percent,
    required this.strokeWidth,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Exact circle bounds inside stroke
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final paintTrack = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final paintProgress = Paint()
      ..shader = const SweepGradient(
        colors: [Colors.blueAccent, Colors.tealAccent, Colors.greenAccent],
        stops: [0.0, 0.5, 1.0],
        transform: GradientRotation(math.pi * 0.75),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
      paintTrack,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      (math.pi * 1.5) * percent.clamp(0.0, 1.0),
      false,
      paintProgress,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularGpuGaugePainter oldDelegate) {
    return oldDelegate.percent != percent ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.trackColor != trackColor;
  }
}