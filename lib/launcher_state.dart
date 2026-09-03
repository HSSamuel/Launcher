import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

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
}

class LauncherState extends ChangeNotifier {
  List<String> windowStack = [];
  List<String> minimizedApps = [];
  List<String> maximizedApps = [];
  Offset fileExplorerPos = const Offset(10, 15);
  Offset calculatorPos = const Offset(15, 20);
  Offset browserPos = const Offset(10, 15);
  Offset settingsPos = const Offset(10, 15);

  String userName = 'HUNSA S. S.';
  String userEmail = 'smkmayomisamuel@gmail.com';
  Uint8List? userImageBytes;
  String actualWallpaperUrl = 'https://images.pexels.com/photos/1624496/pexels-photo-1624496.jpeg?auto=compress&cs=tinysrgb&w=2000';

  bool isDarkMode = true;
  String currentThemeName = 'Dark theme';
  String taskbarAlignment = 'left';
  String? slideshowFolderPath;

  bool showRecentlyAdded = true;
  bool showMostUsed = true;
  bool showRecommended = true;

  String iconSize = 'Small';
  int portraitGridX = 6;
  int portraitGridY = 10;
  int landscapeGridX = 7;
  int landscapeGridY = 5;
  bool doubleTapToSleep = true;
  bool dragIcons = true;
  bool hideStatusBar = false;
  bool hideNavBar = false;
  bool createShortcut = true;

  bool devMode = false;
  bool windowsSubsystem = true;
  bool experimentalEngine = false;
  bool showHiddenFiles = false;
  bool previewFiles = false;
  bool mouseSound = false;

  String gestureUpAction = 'None';
  String gestureDownAction = 'None';
  String gestureTwoFingerUpAction = 'Start Menu';
  String gestureTwoFingerDownAction = 'Device Notification Bar';

  final List<WinTheme> win11Themes = const [
    WinTheme(name: 'Windows 11 (Light)', wallpaperUrl: 'https://images.pexels.com/photos/1743165/pexels-photo-1743165.jpeg?auto=compress&cs=tinysrgb&w=2000', isDark: false, accentColor: Color(0xFF0067C0)),
    WinTheme(name: 'Windows 11 (Dark)', wallpaperUrl: 'https://images.pexels.com/photos/1624496/pexels-photo-1624496.jpeg?auto=compress&cs=tinysrgb&w=2000', isDark: true, accentColor: Color(0xFF4CC2FF)),
    WinTheme(name: 'Glow', wallpaperUrl: 'https://images.pexels.com/photos/2088203/pexels-photo-2088203.jpeg?auto=compress&cs=tinysrgb&w=2000', isDark: true, accentColor: Color(0xFF9E64FF)),
    WinTheme(name: 'Captured Motion', wallpaperUrl: 'https://images.pexels.com/photos/289569/pexels-photo-289569.jpeg?auto=compress&cs=tinysrgb&w=2000', isDark: true, accentColor: Color(0xFFFF4343)),
    WinTheme(name: 'Sunrise', wallpaperUrl: 'https://images.pexels.com/photos/1287145/pexels-photo-1287145.jpeg?auto=compress&cs=tinysrgb&w=2000', isDark: false, accentColor: Color(0xFFFF8C00)),
    WinTheme(name: 'Flow', wallpaperUrl: 'https://images.pexels.com/photos/1323550/pexels-photo-1323550.jpeg?auto=compress&cs=tinysrgb&w=2000', isDark: false, accentColor: Color(0xFF00A2ED)),
  ];

  List<AppInfo> installedApps = [];
  bool isLoadingApps = true;

  String currentExplorerPath = '/storage/emulated/0';
  String? clipboardPath;
  bool isCut = false;

  List<String> pinnedQuickAccess = [];
  List<String> pinnedStart = [];
  List<String> recentApps = [];
  List<String> desktopApps = [];

  List<String> visibleQuickSettings = [
    'Airplane mode', 'Battery saver', 'Wi-Fi',
    'Bluetooth', 'Flash', 'Data',
    'Rotate', 'Location', 'Hotspot',
    'VPN', 'Brightness', 'Accessibility'
  ];

  List<String> hiddenQuickSettings = [
    'Play', 'Ring', 'ChatGPT', 'Storage',
    'Dark Theme', 'Calculator', 'Song Search',
    'DND', 'Screen Cast', 'Eye Care',
    'Scan QR Code', 'PC Connection', 'Kids Mode'
  ];

  LauncherState() {
    _loadState();
    _loadRealAndroidApps();
  }

  void toggleQuickSettingVisibility(String item) async {
    if (visibleQuickSettings.contains(item)) {
      visibleQuickSettings.remove(item);
      hiddenQuickSettings.add(item);
    } else {
      hiddenQuickSettings.remove(item);
      visibleQuickSettings.add(item);
    }
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('visibleQuickSettings', visibleQuickSettings);
    await prefs.setStringList('hiddenQuickSettings', hiddenQuickSettings);
  }

  void nextWallpaper() {
    int currentIndex = win11Themes.indexWhere((t) => t.wallpaperUrl == actualWallpaperUrl);
    if (currentIndex == -1) currentIndex = 0;
    int nextIndex = (currentIndex + 1) % win11Themes.length;
    applyPresetTheme(win11Themes[nextIndex]);
  }

  void pinToQuickAccess(String name) {
    if (!pinnedQuickAccess.contains(name)) {
      pinnedQuickAccess.add(name);
      notifyListeners();
    }
  }

  // RESTORED: Explicitly pins items without toggling (used by Desktop/Folders)
  void pinToStart(String name) async {
    if (!pinnedStart.contains(name)) {
      pinnedStart.add(name);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('pinnedStart', pinnedStart);
      notifyListeners();
    }
  }

  void togglePinToStart(String name) async {
    if (pinnedStart.contains(name)) {
      pinnedStart.remove(name);
    } else {
      pinnedStart.add(name);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pinnedStart', pinnedStart);
    notifyListeners();
  }

  void toggleDesktopApp(String name) async {
    if (desktopApps.contains(name)) {
      desktopApps.remove(name);
    } else {
      desktopApps.add(name);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('desktopApps', desktopApps);
    notifyListeners();
  }

  void setClipboard(String path, bool cut) {
    clipboardPath = path;
    isCut = cut;
    notifyListeners();
  }

  void clearClipboard() {
    clipboardPath = null;
    isCut = false;
    notifyListeners();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    userName = prefs.getString('userName') ?? 'HUNSA S. S.';
    userEmail = prefs.getString('userEmail') ?? 'smkmayomisamuel@gmail.com';
    String? base64Image = prefs.getString('userImage');
    if (base64Image != null) userImageBytes = base64Decode(base64Image);

    actualWallpaperUrl = prefs.getString('wallpaper') ?? actualWallpaperUrl;
    isDarkMode = prefs.getBool('isDarkMode') ?? true;
    currentThemeName = prefs.getString('currentThemeName') ?? 'Dark theme';
    taskbarAlignment = prefs.getString('taskbarAlignment') ?? 'left';
    slideshowFolderPath = prefs.getString('slideshowFolderPath');

    showRecentlyAdded = prefs.getBool('showRecentlyAdded') ?? true;
    showMostUsed = prefs.getBool('showMostUsed') ?? true;
    showRecommended = prefs.getBool('showRecommended') ?? true;

    iconSize = prefs.getString('iconSize') ?? 'Small';
    portraitGridX = prefs.getInt('portraitGridX') ?? 6;
    portraitGridY = prefs.getInt('portraitGridY') ?? 10;
    landscapeGridX = prefs.getInt('landscapeGridX') ?? 7;
    landscapeGridY = prefs.getInt('landscapeGridY') ?? 5;
    doubleTapToSleep = prefs.getBool('doubleTapToSleep') ?? true;
    dragIcons = prefs.getBool('dragIcons') ?? true;
    hideStatusBar = prefs.getBool('hideStatusBar') ?? false;
    hideNavBar = prefs.getBool('hideNavBar') ?? false;
    createShortcut = prefs.getBool('createShortcut') ?? true;

    devMode = prefs.getBool('devMode') ?? false;
    windowsSubsystem = prefs.getBool('windowsSubsystem') ?? true;
    experimentalEngine = prefs.getBool('experimentalEngine') ?? false;
    showHiddenFiles = prefs.getBool('showHiddenFiles') ?? false;
    previewFiles = prefs.getBool('previewFiles') ?? false;
    mouseSound = prefs.getBool('mouseSound') ?? false;

    gestureUpAction = prefs.getString('gestureUpAction') ?? 'None';
    gestureDownAction = prefs.getString('gestureDownAction') ?? 'None';
    gestureTwoFingerUpAction = prefs.getString('gestureTwoFingerUpAction') ?? 'Start Menu';
    gestureTwoFingerDownAction = prefs.getString('gestureTwoFingerDownAction') ?? 'Device Notification Bar';

    visibleQuickSettings = prefs.getStringList('visibleQuickSettings') ?? visibleQuickSettings;
    hiddenQuickSettings = prefs.getStringList('hiddenQuickSettings') ?? hiddenQuickSettings;

    recentApps = prefs.getStringList('recentApps') ?? [];
    desktopApps = prefs.getStringList('desktopApps') ?? [];
    pinnedStart = prefs.getStringList('pinnedStart') ?? [];

    notifyListeners();
  }

  Future<void> saveProfile(String name, Uint8List? bytes) async {
    userName = name;
    userImageBytes = bytes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', name);
    if (bytes != null) await prefs.setString('userImage', base64Encode(bytes));
    notifyListeners();
  }

  Future<void> updateUserName(String name) async {
    userName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', name);
    notifyListeners();
  }

  Future<void> updateUserEmail(String email) async {
    userEmail = email;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userEmail', email);
    notifyListeners();
  }

  Future<void> changeWallpaper(String url) async {
    actualWallpaperUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wallpaper', url);
    notifyListeners();
  }

  Future<void> setDarkMode(bool dark) async {
    isDarkMode = dark;
    currentThemeName = dark ? 'Dark theme' : 'Light theme';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', dark);
    await prefs.setString('currentThemeName', currentThemeName);
    notifyListeners();
  }

  Future<void> applyPresetTheme(WinTheme theme) async {
    currentThemeName = theme.name;
    isDarkMode = theme.isDark;
    actualWallpaperUrl = theme.wallpaperUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currentThemeName', theme.name);
    await prefs.setBool('isDarkMode', theme.isDark);
    await prefs.setString('wallpaper', theme.wallpaperUrl);
    notifyListeners();
  }

  Future<void> setTaskbarAlignment(String alignment) async {
    taskbarAlignment = alignment;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('taskbarAlignment', alignment);
    notifyListeners();
  }

  Future<void> setSlideshowFolder(String path) async {
    slideshowFolderPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('slideshowFolderPath', path);
    notifyListeners();
  }

  Future<void> setStartMenuOptions({bool? recentlyAdded, bool? mostUsed, bool? recommended}) async {
    final prefs = await SharedPreferences.getInstance();
    if (recentlyAdded != null) {
      showRecentlyAdded = recentlyAdded;
      await prefs.setBool('showRecentlyAdded', recentlyAdded);
    }
    if (mostUsed != null) {
      showMostUsed = mostUsed;
      await prefs.setBool('showMostUsed', mostUsed);
    }
    if (recommended != null) {
      showRecommended = recommended;
      await prefs.setBool('showRecommended', recommended);
    }
    notifyListeners();
  }

  Future<void> updateDesktopSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == 'iconSize') { iconSize = value; await prefs.setString(key, value); }
    if (key == 'portraitGridX') { portraitGridX = value; await prefs.setInt(key, value); }
    if (key == 'portraitGridY') { portraitGridY = value; await prefs.setInt(key, value); }
    if (key == 'landscapeGridX') { landscapeGridX = value; await prefs.setInt(key, value); }
    if (key == 'landscapeGridY') { landscapeGridY = value; await prefs.setInt(key, value); }
    if (key == 'doubleTapToSleep') { doubleTapToSleep = value; await prefs.setBool(key, value); }
    if (key == 'dragIcons') { dragIcons = value; await prefs.setBool(key, value); }
    if (key == 'hideStatusBar') { hideStatusBar = value; await prefs.setBool(key, value); }
    if (key == 'hideNavBar') { hideNavBar = value; await prefs.setBool(key, value); }
    if (key == 'createShortcut') { createShortcut = value; await prefs.setBool(key, value); }

    if (key == 'devMode') { devMode = value; await prefs.setBool(key, value); }
    if (key == 'windowsSubsystem') { windowsSubsystem = value; await prefs.setBool(key, value); }
    if (key == 'experimentalEngine') { experimentalEngine = value; await prefs.setBool(key, value); }
    if (key == 'showHiddenFiles') { showHiddenFiles = value; await prefs.setBool(key, value); }
    if (key == 'previewFiles') { previewFiles = value; await prefs.setBool(key, value); }
    if (key == 'mouseSound') { mouseSound = value; await prefs.setBool(key, value); }

    notifyListeners();
  }

  Future<void> updateGesture(String type, String action) async {
    final prefs = await SharedPreferences.getInstance();
    String key = '';
    if (type == 'UP') { gestureUpAction = action; key = 'gestureUpAction'; }
    else if (type == 'DOWN') { gestureDownAction = action; key = 'gestureDownAction'; }
    else if (type == '2_UP') { gestureTwoFingerUpAction = action; key = 'gestureTwoFingerUpAction'; }
    else if (type == '2_DOWN') { gestureTwoFingerDownAction = action; key = 'gestureTwoFingerDownAction'; }
    await prefs.setString(key, action);
    notifyListeners();
  }

  Future<void> _loadRealAndroidApps() async {
    if (kIsWeb) { isLoadingApps = false; notifyListeners(); return; }
    try {
      List<AppInfo> apps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: true);
      apps.removeWhere((app) => app.name == 'Win11 Simulator' || (app.packageName != null && app.packageName!.contains('win_launcher')));
      apps.sort((a, b) => (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase()));
      installedApps = apps;

      final prefs = await SharedPreferences.getInstance();
      bool hasInitializedPins = prefs.getBool('hasInitializedPins') ?? false;
      if (!hasInitializedPins && installedApps.isNotEmpty) {
        pinnedStart = installedApps.take(16).map((e) => e.packageName!).toList();
        await prefs.setStringList('pinnedStart', pinnedStart);
        await prefs.setBool('hasInitializedPins', true);
      }

    } catch (_) {} finally {
      isLoadingApps = false;
      notifyListeners();
    }
  }

  Future<void> launchNativeApp(String packageName) async {
    if (!kIsWeb) {
      InstalledApps.startApp(packageName);

      recentApps.remove(packageName);
      recentApps.insert(0, packageName);
      if (recentApps.length > 6) recentApps.removeLast();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('recentApps', recentApps);
      notifyListeners();
    }
  }

  void openApp(String appId) {
    if (minimizedApps.contains(appId)) minimizedApps.remove(appId);
    if (!windowStack.contains(appId)) windowStack.add(appId);
    focusWindow(appId);
  }

  void closeApp(String appId) {
    windowStack.remove(appId);
    minimizedApps.remove(appId);
    maximizedApps.remove(appId);
    notifyListeners();
  }

  void minimizeApp(String appId) {
    if (!minimizedApps.contains(appId)) minimizedApps.add(appId);
    notifyListeners();
  }

  void toggleMaximizeApp(String appId) {
    maximizedApps.contains(appId) ? maximizedApps.remove(appId) : maximizedApps.add(appId);
    focusWindow(appId);
  }

  void focusWindow(String appId) {
    windowStack.remove(appId);
    windowStack.add(appId);
    notifyListeners();
  }

  void updateWindowPos(String appId, Offset delta) {
    if (appId == 'explorer') fileExplorerPos += delta;
    if (appId == 'calculator') calculatorPos += delta;
    if (appId == 'browser') browserPos += delta;
    if (appId == 'settings') settingsPos += delta;
    notifyListeners();
  }
}