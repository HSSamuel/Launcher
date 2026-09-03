import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'launcher_state.dart';
import 'lock_screen.dart';

void main() {
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
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Windows 11 Launcher',
          themeMode: state.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData.light().copyWith(
            scaffoldBackgroundColor: const Color(0xFFF3F3F3),
            colorScheme: const ColorScheme.light(primary: Colors.blueAccent),
          ),
          darkTheme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF191919),
            colorScheme: const ColorScheme.dark(primary: Colors.blueAccent),
          ),
          home: const LockScreen(), 
        );
      },
    );
  }
}