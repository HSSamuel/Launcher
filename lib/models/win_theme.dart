import 'package:flutter/material.dart';

class WinTheme {
  final String name;
  final String wallpaperUrl;
  final bool isDark;
  final Color accentColor;

  const WinTheme({
    required this.name,
    required this.wallpaperUrl,
    required this.isDark,
    required this.accentColor,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WinTheme && other.name == name;
  }

  @override
  int get hashCode => name.hashCode;
}