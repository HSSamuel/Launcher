import 'dart:async';
import 'dart:io';
import 'dart:convert'; 
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/win_theme.dart';
import '../services/native_bridge.dart';

class ThemeState extends ChangeNotifier with WidgetsBindingObserver {
  String actualWallpaperUrl = 'assets/wallpapers/theme_sunrise.jpg'; 
  bool isDarkMode = false; 
  bool syncWithSystemTheme = false;
  String currentThemeName = 'Sunrise Glow';
  Color? customAccentColor;
  
  bool syncAccentWithOS = false;
  Color? osAccentColor;
  
  Color? _systemLightDynamic;
  Color? _systemDarkDynamic;
  
  bool slideshowEnabled = false;
  int slideshowIntervalMinutes = 15;
  Timer? _slideshowTimer;

  bool infiniteWebWallpapers = false;

  String? currentIconPackPackage;
  String? cachedIconsPath;
  bool isProcessingIconPack = false;

  Map<String, String> customAppIcons = {};

  bool transparencyEffects = true;
  bool isLegacyDevice = false;

  double get activeBlurSigma {
    if (!transparencyEffects) return 0.0;
    return isLegacyDevice ? 7.0 : 20.0;
  }

  double get activePanelOpacity {
    if (!transparencyEffects) return isDarkMode ? 0.96 : 0.98;
    return isLegacyDevice ? (isDarkMode ? 0.88 : 0.92) : (isDarkMode ? 0.70 : 0.85);
  }

  final List<WinTheme> win11Themes = const [
    WinTheme(name: 'Windows Classic', wallpaperUrl: 'assets/wallpapers/theme_snow.jpg', isDark: false, accentColor: Color(0xFF0078D4)),
    WinTheme(name: 'Glacier Ice', wallpaperUrl: 'assets/wallpapers/theme_snow.jpg', isDark: false, accentColor: Color(0xFF00B4D8)),
    WinTheme(name: 'Vivid Blue', wallpaperUrl: 'assets/wallpapers/theme_sunrise.jpg', isDark: false, accentColor: Color(0xFF005A9E)),
    WinTheme(name: 'Dark Ribbons', wallpaperUrl: 'assets/wallpapers/theme_dark.jpg', isDark: true, accentColor: Color(0xFF4CC2FF)),
    WinTheme(name: 'Neon Orb', wallpaperUrl: 'assets/wallpapers/theme_flora.jpg', isDark: true, accentColor: Color(0xFFD32F2F)),
    WinTheme(name: 'Blossom Pink', wallpaperUrl: 'assets/wallpapers/theme_pink.jpg', isDark: false, accentColor: Color(0xFFE91E63)),
    WinTheme(name: 'Blossom Pink', wallpaperUrl: 'assets/wallpapers/theme_pink.png', isDark: false, accentColor: Color(0xFFE91E63)),
    WinTheme(name: 'Monochrome Slate', wallpaperUrl: 'assets/wallpapers/theme_gray.jpg', isDark: false, accentColor: Color(0xFF607D8B)),
    WinTheme(name: 'Minimal Grey', wallpaperUrl: 'assets/wallpapers/theme_grey.jpg', isDark: false, accentColor: Color(0xFF78909C)),
    WinTheme(name: 'Vibrant Abstract', wallpaperUrl: 'assets/wallpapers/road.jpg', isDark: true, accentColor: Color(0xFFE91E63)),
    WinTheme(name: 'Frozen Stream', wallpaperUrl: 'assets/wallpapers/stream.jpg', isDark: false, accentColor: Color(0xFF388E3C)),
    WinTheme(name: 'Fiery Ribbons', wallpaperUrl: 'assets/wallpapers/green.jpg', isDark: true, accentColor: Color(0xFFD84315)),
  ];

  Color get currentAccentColor {
    if (customAccentColor != null) return customAccentColor!;
    if (syncAccentWithOS && osAccentColor != null) return osAccentColor!;
    return win11Themes.firstWhere((t) => t.name == currentThemeName, orElse: () => win11Themes.first).accentColor;
  }

  Color get foregroundAccentColor {
    final c = currentAccentColor;
    if (!isDarkMode && c.computeLuminance() > 0.8) return Colors.black87;
    if (isDarkMode && c.computeLuminance() < 0.1) return Colors.white70;
    return c;
  }

  Color get textOnAccentColor {
    return currentAccentColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
  }

  ThemeState() { 
    WidgetsBinding.instance.addObserver(this);
    _loadState(); 
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _slideshowTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (syncWithSystemTheme) {
      final isSysDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
      if (isDarkMode != isSysDark) {
        isDarkMode = isSysDark;
        _applySystemOrExtractedColor();
        notifyListeners();
      }
    }
  }

  Future<void> initDeviceCapabilities() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        isLegacyDevice = androidInfo.version.sdkInt < 29;
      } catch (_) {}
    }
  }

  void setSystemDynamicColors(Color? lightPrimary, Color? darkPrimary) {
    if (_systemLightDynamic == lightPrimary && _systemDarkDynamic == darkPrimary) return;
    _systemLightDynamic = lightPrimary;
    _systemDarkDynamic = darkPrimary;
    
    if (syncAccentWithOS) {
      _applySystemOrExtractedColor();
    }
  }

  Future<void> _applySystemOrExtractedColor() async {
    final matchedThemes = win11Themes.where((t) => t.wallpaperUrl == actualWallpaperUrl);
    if (matchedThemes.isNotEmpty) {
      osAccentColor = matchedThemes.first.accentColor;
      notifyListeners();
      return;
    }

    if (actualWallpaperUrl == 'system') {
      if (isDarkMode && _systemDarkDynamic != null) {
        osAccentColor = _systemDarkDynamic;
        notifyListeners();
        return;
      } else if (!isDarkMode && _systemLightDynamic != null) {
        osAccentColor = _systemLightDynamic;
        notifyListeners();
        return;
      }
    }
    
    await extractAccentFromWallpaper(actualWallpaperUrl);
  }

  Future<void> extractAccentFromWallpaper(String url) async {
    await Future.delayed(const Duration(milliseconds: 150));
    try {
      ImageProvider provider;
      if (url.startsWith('http')) {
        provider = CachedNetworkImageProvider(url);
      } else if (url.startsWith('assets/')) {
        provider = AssetImage(url);
      } else if (url != 'system' && File(url).existsSync()) {
        provider = FileImage(File(url));
      } else {
        return;
      }
      
      final colorProvider = ResizeImage(provider, width: 112);
      final colorScheme = await ColorScheme.fromImageProvider(
        provider: colorProvider,
        brightness: isDarkMode ? Brightness.dark : Brightness.light,
      );
      
      Color extracted = colorScheme.primary;
      HSVColor hsv = HSVColor.fromColor(extracted);
      
      if (hsv.saturation < 0.18) {
        if (isDarkMode) {
          extracted = hsv.withValue(0.75).toColor();
        } else {
          extracted = hsv.withValue(0.35).toColor();
        }
      } else {
        if (isDarkMode && hsv.value < 0.4) {
          extracted = hsv.withValue(0.7).toColor();
        } else if (!isDarkMode && hsv.value > 0.9) {
          extracted = hsv.withValue(0.8).toColor();
        }
      }
      
      osAccentColor = extracted;
      notifyListeners();
    } catch (e) {
      debugPrint("Material You extraction failed: $e");
    }
  }

  Future<void> setSyncAccentWithOS(bool sync) async {
    syncAccentWithOS = sync;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('syncAccentWithOS', sync);
    
    if (sync) {
      customAccentColor = null;
      await prefs.remove('customAccentColor');
      await _applySystemOrExtractedColor();
    } else {
      notifyListeners();
    }
  }

  Future<void> setTransparencyEffects(bool enabled) async {
    transparencyEffects = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('transparencyEffects', enabled);
    notifyListeners();
  }

  Future<void> setManualAccentColor(Color color) async {
    customAccentColor = color;
    syncAccentWithOS = false; 
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('customAccentColor', color.value);
    await prefs.setBool('syncAccentWithOS', false);
    notifyListeners();
  }

  Future<void> clearManualAccentColor() async {
    customAccentColor = null;
    syncAccentWithOS = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('customAccentColor');
    await prefs.setBool('syncAccentWithOS', false);
    
    if (!actualWallpaperUrl.startsWith('assets/') && actualWallpaperUrl != 'system') {
       await changeWallpaper(actualWallpaperUrl);
    } else {
       notifyListeners();
    }
  }

  Future<void> setCustomAppIcon(String packageName, String imagePath) async {
    customAppIcons[packageName] = imagePath;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customAppIconsMap', jsonEncode(customAppIcons));
    notifyListeners();
  }

  Future<void> removeCustomAppIcon(String packageName) async {
    if (customAppIcons.containsKey(packageName)) {
      customAppIcons.remove(packageName);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('customAppIconsMap', jsonEncode(customAppIcons));
      notifyListeners();
    }
  }

  Future<void> setIconPack(String? packageName) async {
    isProcessingIconPack = true;
    notifyListeners();

    final path = await NativeBridge.instance.applyIconPack(packageName);
    
    currentIconPackPackage = packageName;
    cachedIconsPath = path;
    isProcessingIconPack = false;

    final prefs = await SharedPreferences.getInstance();
    if (packageName != null) prefs.setString('currentIconPack', packageName);
    else prefs.remove('currentIconPack');
    
    if (path != null) prefs.setString('cachedIconsPath', path);
    else prefs.remove('cachedIconsPath');

    notifyListeners();
  }

  Future<void> setInfiniteWebWallpapers(bool enabled) async {
    infiniteWebWallpapers = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('infiniteWebWallpapers', enabled);
    notifyListeners();
  }

  void _startSlideshowTimer() {
    _slideshowTimer?.cancel();
    if (slideshowEnabled) {
      _slideshowTimer = Timer.periodic(Duration(minutes: slideshowIntervalMinutes), (_) => nextWallpaper());
    }
  }

  Future<void> updateSlideshowSettings({bool? enabled, int? interval}) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled != null) { slideshowEnabled = enabled; await prefs.setBool('slideshowEnabled', enabled); }
    if (interval != null) { slideshowIntervalMinutes = interval; await prefs.setInt('slideshowIntervalMinutes', interval); }
    _startSlideshowTimer();
    notifyListeners();
  }

  void nextWallpaper() async {
    if (infiniteWebWallpapers) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final seed = math.Random().nextInt(10000);
      final url = 'https://picsum.photos/1920/1080?random=${timestamp}_$seed';
      await changeWallpaper(url);
      return;
    }

    int currentIndex = win11Themes.indexWhere((t) => t.wallpaperUrl == actualWallpaperUrl && t.name == currentThemeName);
    
    if (currentIndex == -1) {
      currentIndex = win11Themes.indexWhere((t) => t.wallpaperUrl == actualWallpaperUrl);
    }
    if (currentIndex == -1) {
      currentIndex = win11Themes.indexWhere((t) => t.name == currentThemeName);
    }
    if (currentIndex == -1) {
      currentIndex = 0;
    }

    int nextIndex = (currentIndex + 1) % win11Themes.length;
    
    if (win11Themes[nextIndex].wallpaperUrl == 'system') {
      nextIndex = (nextIndex + 1) % win11Themes.length;
    }

    await applyPresetTheme(win11Themes[nextIndex], allowDarkMode: false);
  }

  Future<void> changeWallpaper(String url) async {
    actualWallpaperUrl = url;
    final prefs = await SharedPreferences.getInstance();
    
    bool isCustom = !url.startsWith('assets/') && url != 'system' && !url.startsWith('http');
    bool isWeb = url.startsWith('http');

    if (isCustom) {
      slideshowEnabled = false;
      infiniteWebWallpapers = false;
      _slideshowTimer?.cancel();
      await prefs.setBool('slideshowEnabled', false);
      await prefs.setBool('infiniteWebWallpapers', false);
    } else if (!isWeb) {
      customAccentColor = null;
      await prefs.remove('customAccentColor');
      try {
         final matchingTheme = win11Themes.firstWhere((t) => t.wallpaperUrl == url);
         currentThemeName = matchingTheme.name;
         await prefs.setString('currentThemeName', matchingTheme.name);
      } catch (_) {}
    }
    
    await prefs.setString('wallpaper', url);

    if (syncAccentWithOS) {
      await _applySystemOrExtractedColor();
    } else {
      notifyListeners();
    }
  }

  Future<void> setDarkMode(bool dark, {bool syncWithSystem = false}) async {
    isDarkMode = dark;
    syncWithSystemTheme = syncWithSystem;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', dark);
    await prefs.setBool('syncWithSystemTheme', syncWithSystem);
    
    if (syncAccentWithOS) {
      await _applySystemOrExtractedColor();
    } else {
      notifyListeners();
    }
  }

  Future<void> applyPresetTheme(WinTheme theme, {bool allowDarkMode = true}) async {
    currentThemeName = theme.name;
    actualWallpaperUrl = theme.wallpaperUrl;
    customAccentColor = null; 
    syncAccentWithOS = false; 
    infiniteWebWallpapers = false;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currentThemeName', theme.name);
    await prefs.setString('wallpaper', theme.wallpaperUrl);
    await prefs.remove('customAccentColor');
    await prefs.setBool('syncAccentWithOS', false);
    await prefs.setBool('infiniteWebWallpapers', false);

    if (allowDarkMode) {
      isDarkMode = theme.isDark;
      await prefs.setBool('isDarkMode', theme.isDark);
    }

    notifyListeners();
  }

  Future<void> _loadState() async {
    await initDeviceCapabilities();

    final prefs = await SharedPreferences.getInstance();
    transparencyEffects = prefs.getBool('transparencyEffects') ?? true;
    syncAccentWithOS = prefs.getBool('syncAccentWithOS') ?? false;
    infiniteWebWallpapers = prefs.getBool('infiniteWebWallpapers') ?? false;

    final customColorInt = prefs.getInt('customAccentColor');
    if (customColorInt != null) customAccentColor = Color(customColorInt);

    final customIconsJson = prefs.getString('customAppIconsMap');
    if (customIconsJson != null) {
      try {
        customAppIcons = Map<String, String>.from(jsonDecode(customIconsJson));
      } catch (_) {}
    }

    actualWallpaperUrl = prefs.getString('wallpaper') ?? actualWallpaperUrl;
    if (actualWallpaperUrl.contains('theme_default.jpg') || actualWallpaperUrl.isEmpty) {
      actualWallpaperUrl = 'assets/wallpapers/theme_sunrise.jpg';
      await prefs.setString('wallpaper', actualWallpaperUrl);
    }

    isDarkMode = prefs.getBool('isDarkMode') ?? isDarkMode;
    syncWithSystemTheme = prefs.getBool('syncWithSystemTheme') ?? false;
    
    if (syncWithSystemTheme) {
      isDarkMode = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    }
    
    currentThemeName = prefs.getString('currentThemeName') ?? 'Windows Classic';
    
    if (!win11Themes.any((t) => t.name == currentThemeName)) {
      currentThemeName = 'Windows Classic';
      await prefs.setString('currentThemeName', currentThemeName);
    }

    cachedIconsPath = prefs.getString('cachedIconsPath');
    currentIconPackPackage = prefs.getString('currentIconPack');

    if (cachedIconsPath != null && !Directory(cachedIconsPath!).existsSync()) {
      cachedIconsPath = null;
      currentIconPackPackage = null;
      await prefs.remove('cachedIconsPath');
      await prefs.remove('currentIconPack');
    }

    slideshowEnabled = prefs.getBool('slideshowEnabled') ?? false;
    slideshowIntervalMinutes = prefs.getInt('slideshowIntervalMinutes') ?? 15;
    _startSlideshowTimer();

    if (syncAccentWithOS) {
      _applySystemOrExtractedColor();
    }

    // PERFORMANCE FIX: Generate native WebP icon cache in background on fresh installs
    if (cachedIconsPath == null && !kIsWeb && Platform.isAndroid) {
      Future.delayed(const Duration(seconds: 2), () {
        setIconPack(null);
      });
    }

    notifyListeners();
  }
}