import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';

import 'models/desktop_item_model.dart';
import 'models/win_theme.dart';
import 'services/native_bridge.dart';

class TimeService {
  static final Stream<DateTime> clockStream = Stream.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now(),
  ).asBroadcastStream();
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
  
  String actualWallpaperUrl = 'assets/wallpapers/theme_sunrise.jpg'; 
  bool isDarkMode = false; 
  String currentThemeName = 'Sunrise Glow';
  String taskbarAlignment = 'left';
  
  String? slideshowFolderPath;
  Color? customAccentColor;
  
  bool slideshowEnabled = false;
  int slideshowIntervalMinutes = 15;
  Timer? _slideshowTimer;

  bool showRecentlyAdded = true;
  bool showMostUsed = true;
  bool showRecommended = true;

  String iconSize = 'Small';
  String pageTransition = 'Classical';
  
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

  // --- Notification Settings Variables ---
  bool notifClearOnOpen = true;
  bool notifClosePanelOnOpen = true;
  bool notifShowOnLockScreen = true;
  bool notifPlaySound = false;
  List<String> excludedNotificationPkgs = [];

  bool isPinSet = false;

  final List<WinTheme> win11Themes = const [
    WinTheme(name: 'Windows Classic', wallpaperUrl: 'assets/wallpapers/theme_snow.jpg', isDark: false, accentColor: Color(0xFF0078D4)),
    WinTheme(name: 'Dark Mountains', wallpaperUrl: 'assets/wallpapers/theme_dark.jpg', isDark: true, accentColor: Color(0xFF4CC2FF)),
    WinTheme(name: 'Sunrise Glow', wallpaperUrl: 'assets/wallpapers/theme_sunrise.jpg', isDark: false, accentColor: Color(0xFFFF8C00)),
    WinTheme(name: 'Glacier Ice', wallpaperUrl: 'assets/wallpapers/theme_snow.jpg', isDark: false, accentColor: Color(0xFF00B4D8)),
    WinTheme(name: 'Golden Flora', wallpaperUrl: 'assets/wallpapers/theme_flora.jpg', isDark: false, accentColor: Color(0xFFE5A91E)),
    WinTheme(name: 'Blossom Pink', wallpaperUrl: 'assets/wallpapers/theme_pink.png', isDark: false, accentColor: Color(0xFFE91E63)),
    WinTheme(name: 'Monochrome Slate', wallpaperUrl: 'assets/wallpapers/theme_gray.jpg', isDark: true, accentColor: Color(0xFF8A99AD)),
    WinTheme(name: 'Emerald Contrast', wallpaperUrl: 'assets/wallpapers/theme_grey.jpg', isDark: true, accentColor: Color(0xFF00B294)),
  ];

  Color get currentAccentColor {
    if (!actualWallpaperUrl.startsWith('assets/') && customAccentColor != null) {
      return customAccentColor!;
    }
    final activeTheme = win11Themes.firstWhere(
      (t) => t.name == currentThemeName,
      orElse: () => win11Themes.first,
    );
    return activeTheme.accentColor;
  }

  List<AppInfo> installedApps = [];
  Map<String, List<AppInfo>> categorizedApps = {};
  Map<String, List<String>> categoryMap = {};
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
    'Brightness', 'Accessibility', 'Ring'
  ];

  List<String> hiddenQuickSettings = [
    'Play', 'ChatGPT', 'Storage',
    'Dark Theme', 'Calculator', 'Song Search',
    'DND', 'Screen Cast', 'Eye Care',
    'Scan QR Code', 'Users & Account', 'Kids Mode'
  ];

  LauncherState() {
    _loadState();
    checkPinStatus();
    Future.delayed(const Duration(seconds: 2), () {
      _loadRealAndroidApps();
    });
  }

  Future<void> checkPinStatus() async {
    final storage = const FlutterSecureStorage();
    final hash = await storage.read(key: 'device_pin_hash');
    isPinSet = hash != null;
    notifyListeners();
  }

  Future<bool> verifyAndDisablePin(String enteredPin) async {
    final storage = const FlutterSecureStorage();
    final storedHash = await storage.read(key: 'device_pin_hash');
    
    final bytes = utf8.encode('Win11_Launcher_Salt_$enteredPin');
    final enteredHash = sha256.convert(bytes).toString();
    
    if (storedHash == enteredHash) {
      await storage.delete(key: 'device_pin_hash');
      isPinSet = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  void _startSlideshowTimer() {
    _slideshowTimer?.cancel();
    if (slideshowEnabled) {
      _slideshowTimer = Timer.periodic(Duration(minutes: slideshowIntervalMinutes), (timer) {
        nextWallpaper();
      });
    }
  }

  Future<void> updateSlideshowSettings({bool? enabled, int? interval}) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled != null) {
      slideshowEnabled = enabled;
      await prefs.setBool('slideshowEnabled', enabled);
    }
    if (interval != null) {
      slideshowIntervalMinutes = interval;
      await prefs.setInt('slideshowIntervalMinutes', interval);
    }
    _startSlideshowTimer();
    notifyListeners();
  }

  // --- Notification Settings Methods ---
  Future<void> updateNotificationSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == 'notifClearOnOpen') notifClearOnOpen = value;
    if (key == 'notifClosePanelOnOpen') notifClosePanelOnOpen = value;
    if (key == 'notifShowOnLockScreen') notifShowOnLockScreen = value;
    if (key == 'notifPlaySound') notifPlaySound = value;
    
    if (value is bool) {
      await prefs.setBool(key, value);
    }
    notifyListeners();
  }

  Future<void> toggleAppNotificationExclusion(String packageName) async {
    if (excludedNotificationPkgs.contains(packageName)) {
      excludedNotificationPkgs.remove(packageName);
    } else {
      excludedNotificationPkgs.add(packageName);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('excludedNotificationPkgs', excludedNotificationPkgs);
    notifyListeners();
  }

  Future<void> _updateCategorizedApps() async {
    final prefs = await SharedPreferences.getInstance();
    final String? catJson = prefs.getString('appCategoryMap');

    if (catJson != null && catJson.isNotEmpty) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(catJson);
        categoryMap = decoded.map((k, v) => MapEntry(k, (v as List).cast<String>()));
      } catch (_) {}
    }

    if (categoryMap.isEmpty) {
      final Map<String, List<String>> defaultCategories = {
        'Productivity': [], 'Developer Tools': [], 'Utilities & Tools': [],
        'Creativity': [], 'Social': [], 'Entertainment': [], 'Other': [],
      };

      for (var app in installedApps) {
        final name = (app.name ?? '').toLowerCase();
        final pkg = (app.packageName ?? '').toLowerCase();
        if (pkg.contains('whatsapp') || pkg.contains('facebook') || pkg.contains('instagram') || pkg.contains('telegram') || pkg.contains('twitter') || pkg.contains('tiktok') || pkg.contains('linkedin')) {
          defaultCategories['Social']!.add(app.packageName!);
        } else if (pkg.contains('youtube') || pkg.contains('music') || pkg.contains('spotify') || pkg.contains('netflix') || name.contains('video') || name.contains('player') || pkg.contains('games') || pkg.contains('xbox')) {
          defaultCategories['Entertainment']!.add(app.packageName!);
        } else if (pkg.contains('chrome') || pkg.contains('edge') || pkg.contains('browser') || pkg.contains('docs') || pkg.contains('drive') || pkg.contains('mail') || pkg.contains('gmail') || pkg.contains('teams') || pkg.contains('zoom') || pkg.contains('word')) {
          defaultCategories['Productivity']!.add(app.packageName!);
        } else if (pkg.contains('code') || pkg.contains('term') || pkg.contains('developer') || pkg.contains('studio') || pkg.contains('github')) {
          defaultCategories['Developer Tools']!.add(app.packageName!);
        } else if (pkg.contains('draw') || pkg.contains('paint') || pkg.contains('canva') || pkg.contains('photo') || pkg.contains('camera') || pkg.contains('gallery')) {
          defaultCategories['Creativity']!.add(app.packageName!);
        } else if (pkg.contains('settings') || pkg.contains('calc') || pkg.contains('clock') || pkg.contains('weather') || pkg.contains('file') || pkg.contains('manager') || pkg.contains('system')) {
          defaultCategories['Utilities & Tools']!.add(app.packageName!);
        } else {
          defaultCategories['Other']!.add(app.packageName!);
        }
      }
      defaultCategories.removeWhere((key, value) => value.isEmpty);
      categoryMap = defaultCategories;
      await prefs.setString('appCategoryMap', jsonEncode(categoryMap));
    }

    Map<String, List<AppInfo>> resolved = {};
    categoryMap.forEach((catName, pkgList) {
      final apps = installedApps.where((a) => pkgList.contains(a.packageName)).toList();
      resolved[catName] = apps;
    });

    categorizedApps = resolved;
    notifyListeners();
  }

  Future<void> _saveCustomCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appCategoryMap', jsonEncode(categoryMap));
  }

  Future<void> createCustomCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty && !categoryMap.containsKey(trimmed)) {
      categoryMap[trimmed] = [];
      await _saveCustomCategories();
      await _updateCategorizedApps();
    }
  }

  Future<void> deleteCustomCategory(String name) async {
    if (categoryMap.containsKey(name)) {
      categoryMap.remove(name);
      await _saveCustomCategories();
      await _updateCategorizedApps();
    }
  }

  Future<void> setCategoryApps(String categoryName, List<String> packageNames) async {
    categoryMap[categoryName] = List<String>.from(packageNames);
    await _saveCustomCategories();
    await _updateCategorizedApps();
  }

  Future<void> removeAppFromCategory(String categoryName, String packageName) async {
    if (categoryMap.containsKey(categoryName)) {
      categoryMap[categoryName]!.remove(packageName);
      await _saveCustomCategories();
      await _updateCategorizedApps();
    }
  }

  bool isCustomCategory(String categoryName) {
    return true; 
  }

  Future<void> refreshApps() async {
    if (kIsWeb) return;
    try {
      List<AppInfo> apps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: true);
      apps.removeWhere((app) => app.name == 'Windows 11 Launcher' || (app.packageName != null && app.packageName!.contains('Windows 11 Luncher')));
      apps.sort((a, b) => (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase()));
      installedApps = apps;
      await _updateCategorizedApps();

      final validPackages = apps.map((a) => a.packageName).toSet();
      bool changed = false;

      int initialPinnedLength = pinnedStart.length;
      pinnedStart.removeWhere((pkg) => !validPackages.contains(pkg));
      if (pinnedStart.length != initialPinnedLength) changed = true;

      int initialRecentLength = recentApps.length;
      recentApps.removeWhere((pkg) => !validPackages.contains(pkg));
      if (recentApps.length != initialRecentLength) changed = true;

      int initialDesktopLength = desktopItems.length;
      desktopItems.removeWhere((item) => item.type == 'app' && !validPackages.contains(item.package));
      if (desktopItems.length != initialDesktopLength) {
        _saveDesktopItems();
      }

      if (changed) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('pinnedStart', pinnedStart);
        await prefs.setStringList('recentApps', recentApps);
      }

      notifyListeners();
    } catch (_) {}
  }

  List<int> _findFirstAvailableSlot(int page, int itemSpanX, int itemSpanY) {
    int maxCols = 15; 
    int maxRows = 15; 
    
    for (int c = 0; c < maxCols; c++) {
      for (int r = 0; r < maxRows; r++) {
        bool isOccupied = desktopItems.any((item) {
          if (item.page != page) return false;
          bool overlapX = c < item.col + item.spanX && c + itemSpanX > item.col;
          bool overlapY = r < item.row + item.spanY && r + itemSpanY > item.row;
          return overlapX && overlapY;
        });
        if (!isOccupied) {
          return [c, r];
        }
      }
    }
    return [0, 0];
  }

  void moveItemToPage(String id, int targetPage) {
    final index = desktopItems.indexWhere((i) => i.id == id);
    if (index != -1) {
      final item = desktopItems[index];
      final slot = _findFirstAvailableSlot(targetPage, item.spanX, item.spanY);
      item.page = targetPage;
      item.col = slot[0];
      item.row = slot[1];
      _saveDesktopItems();
      notifyListeners();
    }
  }

  void copyItemToPage(String originalId, int targetPage) {
    final original = desktopItems.firstWhere((i) => i.id == originalId, orElse: () => DesktopItemModel(id: '', type: '', label: '', page: 0, col: 0, row: 0));
    if (original.id.isNotEmpty) {
      final slot = _findFirstAvailableSlot(targetPage, original.spanX, original.spanY);
      desktopItems.add(DesktopItemModel(
        id: '${original.id}_copy_${DateTime.now().millisecondsSinceEpoch}', 
        type: original.type, 
        label: '${original.label} - Copy', 
        package: original.package, 
        path: original.path, 
        widgetType: original.widgetType, 
        appWidgetId: original.appWidgetId, 
        spanX: original.spanX, 
        spanY: original.spanY, 
        page: targetPage, 
        col: slot[0], 
        row: slot[1]
      ));
      _saveDesktopItems();
      notifyListeners();
    }
  }

  Future<void> addNativeWidget(int page, int col, int row) async {
    try {
      final data = await NativeBridge.instance.pickWidget();
      if (data != null) {
        final int appWidgetId = data['appWidgetId'];
        final String label = data['label'];
        final int minWidth = data['minWidth'];
        final int minHeight = data['minHeight'];
        
        int spanX = (minWidth / 80).ceil().clamp(1, 4);
        int spanY = (minHeight / 80).ceil().clamp(1, 4);
        
        bool occupied = desktopItems.any((i) => i.page == page && i.col == col && i.row == row);
        if (occupied) {
          final slot = _findFirstAvailableSlot(page, spanX, spanY);
          col = slot[0];
          row = slot[1];
        }

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

  void resizeDesktopItem(String id, int spanX, int spanY, double cellWidth, double cellHeight) {
    final index = desktopItems.indexWhere((i) => i.id == id);
    if (index != -1) {
      desktopItems[index].spanX = spanX;
      desktopItems[index].spanY = spanY;
      _saveDesktopItems();
      notifyListeners();
      
      if (desktopItems[index].type == 'native_widget' && desktopItems[index].appWidgetId != null) {
        NativeBridge.instance.updateWidgetSize(
           desktopItems[index].appWidgetId!,
           (spanX * cellWidth).toInt(),
           (spanY * cellHeight).toInt(),
        );
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
      bool occupied = desktopItems.any((i) => i.page == page && i.col == col && i.row == row);
      if (occupied) {
        final slot = _findFirstAvailableSlot(page, 1, 1);
        col = slot[0];
        row = slot[1];
      }
      
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
    int currentIndex = win11Themes.indexWhere((t) => t.name == currentThemeName);
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

  void togglePinToStart(String name) async {
    if (pinnedStart.contains(name)) {
      pinnedStart.remove(name);
    } else {
      if (pinnedStart.length >= 8) return; 
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
    
    String? imagePath = prefs.getString('userImagePath');
    if (imagePath != null) {
      final file = File(imagePath);
      if (file.existsSync()) {
        userImageBytes = await file.readAsBytes();
      }
    } else {
      String? base64Image = prefs.getString('userImage');
      if (base64Image != null) userImageBytes = base64Decode(base64Image);
    }

    final customColorInt = prefs.getInt('customAccentColor');
    if (customColorInt != null) {
      customAccentColor = Color(customColorInt);
    }

    actualWallpaperUrl = prefs.getString('wallpaper') ?? actualWallpaperUrl;
    
    if (actualWallpaperUrl.contains('theme_default.jpg') || actualWallpaperUrl.isEmpty) {
      actualWallpaperUrl = 'assets/wallpapers/theme_sunrise.jpg';
      await prefs.setString('wallpaper', actualWallpaperUrl);
    }

    isDarkMode = prefs.getBool('isDarkMode') ?? isDarkMode;
    currentThemeName = prefs.getString('currentThemeName') ?? 'Windows Classic';
    
    if (!win11Themes.any((t) => t.name == currentThemeName)) {
      currentThemeName = 'Windows Classic';
      await prefs.setString('currentThemeName', currentThemeName);
    }

    slideshowEnabled = prefs.getBool('slideshowEnabled') ?? false;
    slideshowIntervalMinutes = prefs.getInt('slideshowIntervalMinutes') ?? 15;
    _startSlideshowTimer();

    taskbarAlignment = prefs.getString('taskbarAlignment') ?? 'left';

    showRecentlyAdded = prefs.getBool('showRecentlyAdded') ?? true;
    showMostUsed = prefs.getBool('showMostUsed') ?? true;
    showRecommended = prefs.getBool('showRecommended') ?? true;

    iconSize = prefs.getString('iconSize') ?? 'Small';
    pageTransition = prefs.getString('pageTransition') ?? 'Classical';
    
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
    
    // Load Notifications State
    notifClearOnOpen = prefs.getBool('notifClearOnOpen') ?? true;
    notifClosePanelOnOpen = prefs.getBool('notifClosePanelOnOpen') ?? true;
    notifShowOnLockScreen = prefs.getBool('notifShowOnLockScreen') ?? true;
    notifPlaySound = prefs.getBool('notifPlaySound') ?? false;
    excludedNotificationPkgs = prefs.getStringList('excludedNotificationPkgs') ?? [];

    recentApps = prefs.getStringList('recentApps') ?? [];
    
    pinnedStart = prefs.getStringList('pinnedStart') ?? [];
    if (pinnedStart.length > 8) {
      pinnedStart = pinnedStart.sublist(0, 8);
    }
    
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
    if (bytes != null) {
      final directory = await getApplicationDocumentsDirectory();
      final imagePath = '${directory.path}/profile_pic.jpg';
      await File(imagePath).writeAsBytes(bytes);
      await prefs.setString('userImagePath', imagePath);
    }
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
    
    if (!url.startsWith('assets/')) {
      slideshowEnabled = false;
      _slideshowTimer?.cancel();
      await prefs.setBool('slideshowEnabled', false);

      try {
        final colorScheme = await ColorScheme.fromImageProvider(provider: FileImage(File(url)));
        Color extracted = colorScheme.primary;
        
        HSVColor hsv = HSVColor.fromColor(extracted);
        
        if (hsv.saturation < 0.15) {
           customAccentColor = isDarkMode ? const Color(0xFF7A7A7A) : const Color(0xFF5A5A5A);
        } else {
           if (hsv.saturation > 0.5) extracted = hsv.withSaturation(0.5).toColor();
           if (hsv.value > 0.8) extracted = hsv.withValue(0.8).toColor();
           customAccentColor = extracted;
        }
        
        await prefs.setInt('customAccentColor', customAccentColor!.value);
      } catch (_) {}
    } else {
      customAccentColor = null;
      await prefs.remove('customAccentColor');
    }

    await prefs.setString('wallpaper', url);
    notifyListeners();
  }

  Future<void> setDarkMode(bool dark) async {
    isDarkMode = dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', dark);
    notifyListeners();
  }

  Future<void> applyPresetTheme(WinTheme theme) async {
    currentThemeName = theme.name;
    isDarkMode = theme.isDark;
    customAccentColor = null; 
    actualWallpaperUrl = theme.wallpaperUrl;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currentThemeName', theme.name);
    await prefs.setBool('isDarkMode', theme.isDark);
    await prefs.setString('wallpaper', theme.wallpaperUrl);
    await prefs.remove('customAccentColor');
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
    if (key == 'pageTransition') { pageTransition = value; await prefs.setString(key, value); }
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
      await _updateCategorizedApps();

      final prefs = await SharedPreferences.getInstance();
      bool hasInitializedPins = prefs.getBool('hasInitializedPins') ?? false;
      if (!hasInitializedPins && installedApps.isNotEmpty) {
        pinnedStart = installedApps.take(8).map((e) => e.packageName!).toList();
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