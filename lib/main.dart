import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// CRITICAL FIX: Safe global initialization to prevent StateErrors when repeatedly opening the widget
import 'package:timezone/data/latest.dart' as tz_data;

import 'launcher_state.dart';
import 'lock_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones(); // Ensure TimeZones are injected immediately on startup

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => LauncherState())],
      child: const Win11LauncherApp(),
    ),
  );
}

class Win11LauncherApp extends StatelessWidget {
  const Win11LauncherApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<LauncherState>(
      builder: (context, state, child) {
        // Fetch the active theme's predefined accent color
        final activeTheme = state.win11Themes.firstWhere(
          (t) => t.name == state.currentThemeName, 
          orElse: () => state.win11Themes.first
        );
        final seedColor = activeTheme.accentColor;

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Windows 11 Launcher',
          themeMode: state.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          
          // Dynamic Colors Implementation using seedColor
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
          home: const LockScreen(), 
        );
      },
    );
  }
}