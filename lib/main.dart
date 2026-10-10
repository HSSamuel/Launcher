// main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:dynamic_color/dynamic_color.dart';

import 'states/theme_state.dart';
import 'states/system_state.dart';
import 'states/desktop_state.dart';
import 'states/apps_state.dart';
import 'states/monetization_state.dart';
import 'states/cloud_drive_state.dart'; // NEW
import 'ui/desktop/desktop_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones(); 

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeState()),
        ChangeNotifierProvider(create: (_) => SystemState()),
        ChangeNotifierProvider(create: (_) => DesktopState()),
        ChangeNotifierProvider(create: (_) => AppsState()),
        ChangeNotifierProvider(create: (_) => MonetizationState()),
        ChangeNotifierProvider(create: (_) => CloudDriveState()), // NEW
      ],
      child: const Win11LauncherApp(),
    ),
  );
}

class Win11LauncherApp extends StatefulWidget {
  const Win11LauncherApp({Key? key}) : super(key: key);

  @override
  State<Win11LauncherApp> createState() => _Win11LauncherAppState();
}

class _Win11LauncherAppState extends State<Win11LauncherApp> with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    debugPrint("System Memory Pressure Warning: Flushed ImageCache");
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            context.read<ThemeState>().setSystemDynamicColors(
              lightDynamic?.primary, 
              darkDynamic?.primary
            );
          }
        });

        return Consumer<ThemeState>(
          builder: (context, themeState, child) {
            final seedColor = themeState.currentAccentColor;

            return MaterialApp(
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,
              title: 'Win11 PC Launcher',
              themeMode: themeState.isDarkMode ? ThemeMode.dark : ThemeMode.light,
              theme: ThemeData(
                useMaterial3: true,
                colorSchemeSeed: seedColor,
                scaffoldBackgroundColor: const Color(0xFFF3F3F3),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                colorSchemeSeed: seedColor,
                brightness: Brightness.dark,
                scaffoldBackgroundColor: const Color(0xFF191919),
              ),
              home: const DesktopScreen(), 
            );
          },
        );
      }
    );
  }
}