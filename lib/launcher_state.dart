import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

class DesktopItemModel {
  final String id;
  final String type; // 'system', 'app', 'file', 'widget', 'native_widget'
  String label;      
  final String? package;
  final String? path;
  final String? widgetType; 
  final int? appWidgetId;
  int spanX;
  int spanY;
  int page;
  int col;
  int row;

  DesktopItemModel({
    required this.id,
    required this.type,
    required this.label,
    this.package,
    this.path,
    this.widgetType,
    this.appWidgetId,
    this.spanX = 1,
    this.spanY = 1,
    required this.page,
    required this.col,
    required this.row,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'label': label,
    'package': package,
    'path': path,
    'widgetType': widgetType,
    'appWidgetId': appWidgetId,
    'spanX': spanX,
    'spanY': spanY,
    'page': page,
    'col': col,
    'row': row,
  };

  factory DesktopItemModel.fromJson(Map<String, dynamic> json) {
    return DesktopItemModel(
      id: json['id'],
      type: json['type'],
      label: json['label'],
      package: json['package'],
      path: json['path'],
      widgetType: json['widgetType'],
      appWidgetId: json['appWidgetId'],
      spanX: json['spanX'] ?? (json['type'] == 'widget' || json['type'] == 'native_widget' ? 2 : 1),
      spanY: json['spanY'] ?? 1,
      page: json['page'] ?? 0,
      col: json['col'] ?? 0,
      row: json['row'] ?? 0,
    );
  }
}

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

  String userName = 'Windows User';
  String userEmail = 'Local Account';
  Uint8List? userImageBytes;
  
  String actualWallpaperUrl = 'assets/wallpapers/theme_dark.jpg';

  bool isDarkMode = true;
  String currentThemeName = 'Dark Mountains';
  String taskbarAlignment = 'left';
  String? slideshowFolderPath;

  bool showRecentlyAdded = true;
  bool showMostUsed = true;
  bool showRecommended = true;

  String iconSize = 'Small';
  int portraitGridX = 5; 
  int portraitGridY = 8;
  int landscapeGridX = 8;
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

  bool searchShowTopApps = true;
  bool searchCatApps = true;
  bool searchCatDocs = true;
  bool searchCatPhotos = true;
  bool searchCatAudio = true;
  bool searchCatVideos = true;
  bool searchCatSettings = true;

  bool taskbarItemSearch = true;
  bool taskbarItemTaskView = true;
  bool taskbarItemWidget = true;
  bool taskbarOverInternet = true;
  bool taskbarOverSound = true;
  bool taskbarOverBattery = true;
  bool taskbarOverDate = true;
  bool hideNetworkIcons = false;

  final List<WinTheme> win11Themes = const [
    WinTheme(name: 'Dark Mountains', wallpaperUrl: 'assets/wallpapers/theme_dark.jpg', isDark: true, accentColor: Color(0xFF4CC2FF)),
    WinTheme(name: 'Sunrise Horizon', wallpaperUrl: 'assets/wallpapers/theme_sunrise.jpg', isDark: false, accentColor: Color(0xFFFF8C00)),
    WinTheme(name: 'Snowy Peaks', wallpaperUrl: 'assets/wallpapers/theme_snow.jpg', isDark: false, accentColor: Color(0xFF00A2ED)),
    WinTheme(name: 'Yellow Flora', wallpaperUrl: 'assets/wallpapers/theme_flora.jpg', isDark: false, accentColor: Color(0xFFFFD700)),
    WinTheme(name: 'Pink Sky', wallpaperUrl: 'assets/wallpapers/theme_pink.png', isDark: false, accentColor: Color(0xFFE91E63)),
    WinTheme(name: 'Gray Minimal', wallpaperUrl: 'assets/wallpapers/theme_gray.jpg', isDark: true, accentColor: Color(0xFF9E9E9E)),
    WinTheme(name: 'Grey Contrast', wallpaperUrl: 'assets/wallpapers/theme_grey.jpg', isDark: true, accentColor: Color(0xFF607D8B)),
  ];

  List<AppInfo> installedApps = [];
  bool isLoadingApps = true;

  String currentExplorerPath = '/storage/emulated/0';
  String? clipboardPath;
  bool isCut = false;

  List<String> pinnedQuickAccess = [];
  List<String> pinnedStart = [];
  List<String> recentApps = [];
  
  int desktopPages = 1;
  List<DesktopItemModel> desktopItems = [];

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
    Future.delayed(const Duration(seconds: 2), () {
      _loadRealAndroidApps();
    });
  }
  
  Future<void> addNativeWidget(int page, int col, int row) async {
    try {
      final result = await const MethodChannel('win_launcher/native').invokeMethod('pickWidget');
      if (result != null) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(result);
        final int appWidgetId = data['appWidgetId'];
        final String label = data['label'];
        final int minWidth = data['minWidth'];
        final int minHeight = data['minHeight'];
        
        int spanX = (minWidth / 80).ceil().clamp(1, 4);
        int spanY = (minHeight / 80).ceil().clamp(1, 4);

        desktopItems.add(DesktopItemModel(
          id: 'native_widget_$appWidgetId',
          type: 'native_widget',
          label: label,
          appWidgetId: appWidgetId,
          spanX: spanX,
          spanY: spanY,
          page: page,
          col: col,
          row: row,
        ));
        _saveDesktopItems();
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error picking native widget: $e");
    }
  }

  // NEW: Executes real-time widget resizing by updating the grid state and firing the MethodChannel
  void resizeDesktopItem(String id, int spanX, int spanY, double cellWidth, double cellHeight) {
    final index = desktopItems.indexWhere((i) => i.id == id);
    if (index != -1) {
      desktopItems[index].spanX = spanX;
      desktopItems[index].spanY = spanY;
      _saveDesktopItems();
      notifyListeners();
      
      if (desktopItems[index].type == 'native_widget' && desktopItems[index].appWidgetId != null) {
        const MethodChannel('win_launcher/native').invokeMethod('updateWidgetSize', {
           'appWidgetId': desktopItems[index].appWidgetId,
           'width': (spanX * cellWidth).toInt(),
           'height': (spanY * cellHeight).toInt(),
        });
      }
    }
  }

  void addDesktopPage() async {
    desktopPages++;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('desktopPages', desktopPages);
  }

  void removeDesktopPage() async {
    if (desktopPages > 1) {
      desktopPages--;
      for (var item in desktopItems.where((i) => i.page >= desktopPages)) {
        item.page = desktopPages - 1;
      }
      _saveDesktopItems();
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('desktopPages', desktopPages);
    }
  }

  void updateItemPosition(String id, int page, int col, int row) {
    final index = desktopItems.indexWhere((i) => i.id == id);
    if (index != -1) {
      final collisionIndex = desktopItems.indexWhere((i) => i.page == page && i.col == col && i.row == row && i.id != id);
      if (collisionIndex != -1) {
        desktopItems[collisionIndex].col = desktopItems[index].col;
        desktopItems[collisionIndex].row = desktopItems[index].row;
        desktopItems[collisionIndex].page = desktopItems[index].page;
      }
      
      desktopItems[index].page = page;
      desktopItems[index].col = col;
      desktopItems[index].row = row;
      _saveDesktopItems();
      notifyListeners();
    }
  }

  void renameDesktopItem(String id, String newName) {
    final index = desktopItems.indexWhere((i) => i.id == id);
    if (index != -1) {
      desktopItems[index].label = newName;
      _saveDesktopItems();
      notifyListeners();
    }
  }

  void addDesktopApp(AppInfo app, int page, int col, int row) {
    if (!desktopItems.any((i) => i.id == app.packageName)) {
      desktopItems.add(DesktopItemModel(
        id: app.packageName ?? DateTime.now().toString(),
        type: 'app',
        label: app.name ?? 'App',
        package: app.packageName,
        page: page,
        col: col,
        row: row,
      ));
      _saveDesktopItems();
      notifyListeners();
    }
  }

  void addDesktopWidget(String widgetType, String label, int page, int col, int row, {int spanX = 2, int spanY = 1}) {
    desktopItems.add(DesktopItemModel(
      id: 'widget_${widgetType}_${DateTime.now().millisecondsSinceEpoch}',
      type: 'widget',
      label: label,
      widgetType: widgetType,
      spanX: spanX,
      spanY: spanY,
      page: page,
      col: col,
      row: row,
    ));
    _saveDesktopItems();
    notifyListeners();
  }

  void removeDesktopItem(String id) {
    desktopItems.removeWhere((i) => i.id == id);
    _saveDesktopItems();
    notifyListeners();
  }

  Future<void> _saveDesktopItems() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = jsonEncode(desktopItems.map((i) => i.toJson()).toList());
    await prefs.setString('desktopItems', jsonString);
  }

  void _initializeDefaultDesktop() {
    desktopItems = [
      DesktopItemModel(id: 'recycle_bin', type: 'system', label: 'Recycle Bin', page: 0, col: 0, row: 0),
      DesktopItemModel(id: 'my_files', type: 'system', label: 'My Files', page: 0, col: 1, row: 0),
      DesktopItemModel(id: 'calculator', type: 'system', label: 'Calculator', page: 0, col: 2, row: 0),
      DesktopItemModel(id: 'browser', type: 'system', label: 'Edge', page: 0, col: 3, row: 0),
      DesktopItemModel(id: 'settings', type: 'system', label: 'Settings', page: 0, col: 4, row: 0),
    ];
    _saveDesktopItems();
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
    
    userName = prefs.getString('userName') ?? 'Windows User';
    userEmail = prefs.getString('userEmail') ?? 'Local Account';
    
    String? base64Image = prefs.getString('userImage');
    if (base64Image != null) userImageBytes = base64Decode(base64Image);

    actualWallpaperUrl = prefs.getString('wallpaper') ?? actualWallpaperUrl;
    isDarkMode = prefs.getBool('isDarkMode') ?? isDarkMode;
    currentThemeName = prefs.getString('currentThemeName') ?? currentThemeName;
    taskbarAlignment = prefs.getString('taskbarAlignment') ?? 'left';
    slideshowFolderPath = prefs.getString('slideshowFolderPath');

    showRecentlyAdded = prefs.getBool('showRecentlyAdded') ?? true;
    showMostUsed = prefs.getBool('showMostUsed') ?? true;
    showRecommended = prefs.getBool('showRecommended') ?? true;

    iconSize = prefs.getString('iconSize') ?? 'Small';
    portraitGridX = prefs.getInt('portraitGridX') ?? 5;
    portraitGridY = prefs.getInt('portraitGridY') ?? 8;
    landscapeGridX = prefs.getInt('landscapeGridX') ?? 8;
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

    searchShowTopApps = prefs.getBool('search_showTopApps') ?? true;
    searchCatApps = prefs.getBool('search_catApps') ?? true;
    searchCatDocs = prefs.getBool('search_catDocs') ?? true;
    searchCatPhotos = prefs.getBool('search_catPhotos') ?? true;
    searchCatAudio = prefs.getBool('search_catAudio') ?? true;
    searchCatVideos = prefs.getBool('search_catVideos') ?? true;
    searchCatSettings = prefs.getBool('search_catSettings') ?? true;

    taskbarItemSearch = prefs.getBool('taskbar_itemSearch') ?? true;
    taskbarItemTaskView = prefs.getBool('taskbar_itemTaskView') ?? true;
    taskbarItemWidget = prefs.getBool('taskbar_itemWidget') ?? true;
    taskbarOverInternet = prefs.getBool('taskbar_overInternet') ?? true;
    taskbarOverSound = prefs.getBool('taskbar_overSound') ?? true;
    taskbarOverBattery = prefs.getBool('taskbar_overBattery') ?? true;
    taskbarOverDate = prefs.getBool('taskbar_overDate') ?? true;
    hideNetworkIcons = prefs.getBool('taskbar_hideNetworkIcons') ?? false;

    visibleQuickSettings = prefs.getStringList('visibleQuickSettings') ?? visibleQuickSettings;
    hiddenQuickSettings = prefs.getStringList('hiddenQuickSettings') ?? hiddenQuickSettings;

    recentApps = prefs.getStringList('recentApps') ?? [];
    pinnedStart = prefs.getStringList('pinnedStart') ?? [];
    desktopPages = prefs.getInt('desktopPages') ?? 1;

    final String? itemsJson = prefs.getString('desktopItems');
    if (itemsJson != null && itemsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(itemsJson);
        desktopItems = decoded.map((e) => DesktopItemModel.fromJson(e)).toList();
      } catch (_) {
        _initializeDefaultDesktop();
      }
    } else {
      _initializeDefaultDesktop();
    }

    notifyListeners();
  }

  Future<void> updateSearchSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == 'showTopApps') searchShowTopApps = value;
    if (key == 'catApps') searchCatApps = value;
    if (key == 'catDocs') searchCatDocs = value;
    if (key == 'catPhotos') searchCatPhotos = value;
    if (key == 'catAudio') searchCatAudio = value;
    if (key == 'catVideos') searchCatVideos = value;
    if (key == 'catSettings') searchCatSettings = value;
    await prefs.setBool('search_$key', value);
    notifyListeners();
  }

  Future<void> updateTaskbarSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == 'itemSearch') taskbarItemSearch = value;
    if (key == 'itemTaskView') taskbarItemTaskView = value;
    if (key == 'itemWidget') taskbarItemWidget = value;
    if (key == 'overInternet') taskbarOverInternet = value;
    if (key == 'overSound') taskbarOverSound = value;
    if (key == 'overBattery') taskbarOverBattery = value;
    if (key == 'overDate') taskbarOverDate = value;
    if (key == 'hideNetworkIcons') hideNetworkIcons = value;
    await prefs.setBool('taskbar_$key', value);
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
    currentThemeName = dark ? 'Dark Mountains' : 'Sunrise Horizon';
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
      apps.removeWhere((app) => app.name == 'Windows 11 Launcher' || (app.packageName != null && app.packageName!.contains('Windows 11 Luncher')));
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

      if (!windowStack.contains(packageName)) {
        windowStack.add(packageName);
      } else {
        windowStack.remove(packageName);
        windowStack.add(packageName); 
      }

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