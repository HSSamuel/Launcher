import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import 'desktop_state.dart';
import 'system_state.dart';
import '../ui/desktop/search_overlay.dart'; 
import '../services/lazy_app_icon.dart';

class AppsState extends ChangeNotifier {
  List<AppInfo> installedApps = [];
  Map<String, AppInfo> appMap = {};
  
  Map<String, List<AppInfo>> categorizedApps = {};
  Map<String, List<String>> categoryMap = {};
  
  Map<String, List<AppInfo>> precomputedAlphabetGroups = {};
  List<String> precomputedAlphabetKeys = [];

  bool isLoadingApps = true;

  List<String> windowStack = [];
  List<String> minimizedApps = [];
  List<String> maximizedApps = [];

  Offset? fileExplorerPos;
  Offset? calculatorPos;
  Offset? browserPos;
  Offset? settingsPos;

  String currentExplorerPath = '/storage/emulated/0';
  String? clipboardPath;
  String? highlightFileName;
  bool isCut = false;

  final StreamController<String> explorerNavigationStream = StreamController<String>.broadcast();

  List<String> pinnedQuickAccess = [];
  List<String> pinnedStart = [];
  List<String> recentApps = [];
  
  List<String> recentlyAddedApps = [];
  List<String> recentlyUpdatedApps = [];
  List<String> hiddenApps = [];
  List<String> lockedApps = [];

  Map<String, int> appNotificationCounts = {};
  Map<String, bool> iconCacheStatus = {};

  String explorerViewType = 'List';
  String explorerSortBy = 'Name';
  bool explorerSortAscending = true;

  Map<String, Future<bool> Function()> windowBackHandlers = {};
  Timer? _categorySaveDebouncer;

  static final _socialRegExp = RegExp(r'whatsapp|facebook|instagram|telegram|twitter|tiktok|linkedin', caseSensitive: false);
  static final _entertainmentRegExp = RegExp(r'youtube|music|spotify|netflix|video|player|games|xbox', caseSensitive: false);
  static final _productivityRegExp = RegExp(r'chrome|edge|browser|docs|drive|mail|gmail|teams|zoom|word', caseSensitive: false);
  static final _devToolsRegExp = RegExp(r'code|term|developer|studio|github', caseSensitive: false);
  static final _creativeRegExp = RegExp(r'draw|paint|canva|photo|camera|gallery', caseSensitive: false);
  static final _utilsRegExp = RegExp(r'settings|calc|clock|weather|file|manager|system', caseSensitive: false);

  AppsState() {
    _loadState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadRealAndroidApps();
    });
  }

  @override
  void dispose() {
    _categorySaveDebouncer?.cancel();
    explorerNavigationStream.close();
    super.dispose();
  }

  void addRecentlyAddedApp(String pkg, {bool isUpdate = false}) async {
    final entry = '$pkg|${DateTime.now().millisecondsSinceEpoch}';
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Purge the package from BOTH lists to guarantee mutual exclusivity
    recentlyAddedApps.removeWhere((e) => e.split('|')[0] == pkg);
    recentlyUpdatedApps.removeWhere((e) => e.split('|')[0] == pkg);
    
    // 2. Insert into the correct designated list
    if (isUpdate) {
      recentlyUpdatedApps.insert(0, entry);
      if (recentlyUpdatedApps.length > 6) {
        recentlyUpdatedApps = recentlyUpdatedApps.sublist(0, 6);
      }
    } else {
      recentlyAddedApps.insert(0, entry);
      if (recentlyAddedApps.length > 6) {
        recentlyAddedApps = recentlyAddedApps.sublist(0, 6);
      }
    }
    
    // 3. Persist the cleaned states to disk
    await prefs.setStringList('recentlyAddedApps', recentlyAddedApps);
    await prefs.setStringList('recentlyUpdatedApps', recentlyUpdatedApps);
    
    notifyListeners();
  }

  void requestExplorerNavigation(String path) {
    currentExplorerPath = path;
    explorerNavigationStream.add(path);
    openApp('explorer');
  }

  void triggerExplorerRefresh() {
    explorerNavigationStream.add(":refresh:");
  }

  void registerBackHandler(String appId, Future<bool> Function() handler) {
    windowBackHandlers[appId] = handler;
  }

  void unregisterBackHandler(String appId) {
    windowBackHandlers.remove(appId);
  }

  Future<void> injectAndSyncApp(String pkg, String label) async {
    if (kIsWeb) return;
    try {
      // Give the OS an extra second to finalize the APK extraction and manifest indexing
      await Future.delayed(const Duration(milliseconds: 2500));
      
      AppInfo? fetchedInfo;
      try {
        fetchedInfo = await InstalledApps.getAppInfo(pkg);
      } catch (_) {}

      if (fetchedInfo == null) {
        final allApps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: false);
        try {
          fetchedInfo = allApps.firstWhere((a) => a.packageName == pkg);
        } catch (_) {
          debugPrint("App not found in system index yet. Will sync on next background refresh.");
          return;
        }
      }

      installedApps.removeWhere((a) => a.packageName == pkg);
      installedApps.add(fetchedInfo);
      installedApps.sort((a, b) => (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase()));
      
      appMap[pkg] = fetchedInfo;
      
      // Pre-populate the LazyAppIcon memory cache to prevent the "Green Android" fallback
      if (fetchedInfo.icon != null) {
        LazyAppIcon.globalIconCache[pkg] = fetchedInfo.icon!;
        LazyAppIcon.failedFetches.remove(pkg);
      }
      
      await _updateCategorizedApps(); 
      notifyListeners(); 
    } catch (e) {
      debugPrint("Failed to sync injected app: $e");
    }
  }

  Future<void> checkIconCacheStatus(String windowId, String? cachedIconsPath) async {
    if (cachedIconsPath != null && !iconCacheStatus.containsKey(windowId)) {
      final cacheFile = File('$cachedIconsPath/$windowId.png');
      final exists = await cacheFile.exists();
      iconCacheStatus[windowId] = exists;
      notifyListeners();
    }
  }

  void updateNotificationCounts(List<Map<String, dynamic>> notifications) {
    Map<String, int> counts = {};
    for (var n in notifications) {
      final pkg = n['package'] as String?;
      if (pkg != null) {
        counts[pkg] = (counts[pkg] ?? 0) + 1;
      }
    }
    appNotificationCounts = counts;
    notifyListeners();
  }

  Future<void> updateExplorerView(String viewType) async {
    explorerViewType = viewType;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('explorerViewType', viewType);
  }

  Future<void> updateExplorerSort(String sortBy, bool ascending) async {
    explorerSortBy = sortBy;
    explorerSortAscending = ascending;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('explorerSortBy', sortBy);
    await prefs.setBool('explorerSortAscending', ascending);
  }

  Future<void> _saveCustomCategoriesNow() async {
    _categorySaveDebouncer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appCategoryMap', jsonEncode(categoryMap));
  }

  void _saveCustomCategoriesDebounced() {
    _categorySaveDebouncer?.cancel();
    _categorySaveDebouncer = Timer(const Duration(milliseconds: 400), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('appCategoryMap', jsonEncode(categoryMap));
    });
  }

  void _precomputeAlphabeticalIndex() {
    final Map<String, List<AppInfo>> groups = {};
    for (final app in installedApps) {
      if (hiddenApps.contains(app.packageName)) continue;
      final name = app.name?.trim() ?? '';
      String first = name.isNotEmpty ? name[0].toUpperCase() : '#';
      if (!RegExp(r'[A-Z]').hasMatch(first)) first = '#';

      if (!groups.containsKey(first)) {
        groups[first] = [];
      }
      groups[first]!.add(app);
    }

    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == '#') return 1;
        if (b == '#') return -1;
        return a.compareTo(b);
      });

    precomputedAlphabetGroups = groups;
    precomputedAlphabetKeys = keys;
  }

  Future<void> _updateCategorizedApps() async {
    if (categoryMap.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final String? catJson = prefs.getString('appCategoryMap');

      if (catJson != null && catJson.isNotEmpty) {
        try {
          categoryMap = (jsonDecode(catJson) as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as List).cast<String>()));
        } catch (_) {}
      }
    }

    if (categoryMap.isEmpty) {
      categoryMap = {
        'Productivity': [],
        'Developer Tools': [],
        'Utilities & Tools': [],
        'Creativity': [],
        'Social': [],
        'Entertainment': [],
        'Other': [],
      };
    }

    Set<String> alreadyCategorizedPkgs = {};
    for (var list in categoryMap.values) {
      alreadyCategorizedPkgs.addAll(list);
    }

    bool requiresSave = false;

    for (var app in installedApps) {
      if (app.packageName != null && !alreadyCategorizedPkgs.contains(app.packageName)) {
        String targetCategory = 'Other';
        final name = (app.name ?? '');
        final pkg = (app.packageName ?? '');

        if (_socialRegExp.hasMatch(pkg)) {
          targetCategory = 'Social';
        } else if (_entertainmentRegExp.hasMatch(pkg) || _entertainmentRegExp.hasMatch(name)) {
          targetCategory = 'Entertainment';
        } else if (_productivityRegExp.hasMatch(pkg)) {
          targetCategory = 'Productivity';
        } else if (_devToolsRegExp.hasMatch(pkg)) {
          targetCategory = 'Developer Tools';
        } else if (_creativeRegExp.hasMatch(pkg)) {
          targetCategory = 'Creativity';
        } else if (_utilsRegExp.hasMatch(pkg)) {
          targetCategory = 'Utilities & Tools';
        }

        if (!categoryMap.containsKey(targetCategory)) {
          if (!categoryMap.containsKey('Other')) categoryMap['Other'] = [];
          targetCategory = 'Other';
        }

        categoryMap[targetCategory]!.add(app.packageName!);
        requiresSave = true;
      }
    }

    if (requiresSave) {
      _saveCustomCategoriesDebounced();
    }

    final defaultCategories = {
      'Productivity',
      'Developer Tools',
      'Utilities & Tools',
      'Creativity',
      'Social',
      'Entertainment',
      'Other'
    };
    categoryMap.removeWhere((key, value) => value.isEmpty && defaultCategories.contains(key));

    Map<String, List<AppInfo>> resolved = {};
    categoryMap.forEach((catName, pkgList) {
      final List<AppInfo> matched = [];
      for (final p in pkgList) {
        if (!hiddenApps.contains(p) && appMap.containsKey(p)) {
          matched.add(appMap[p]!);
        }
      }
      resolved[catName] = matched;
    });

    categorizedApps = resolved;
    _precomputeAlphabeticalIndex();
    notifyListeners();
  }

  Future<void> createCustomCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty && !categoryMap.containsKey(trimmed)) {
      categoryMap[trimmed] = [];
      await _saveCustomCategoriesNow();
      await _updateCategorizedApps();
    }
  }

  Future<void> deleteCustomCategory(String name) async {
    if (categoryMap.containsKey(name)) {
      final orphanedApps = List<String>.from(categoryMap[name]!);
      categoryMap.remove(name);
      
      if (!categoryMap.containsKey('Other')) {
        categoryMap['Other'] = [];
      }
      categoryMap['Other']!.addAll(orphanedApps);

      await _saveCustomCategoriesNow();
      await _updateCategorizedApps();
    }
  }

  Future<void> setCategoryApps(String categoryName, List<String> packageNames) async {
    categoryMap.forEach((key, list) {
      if (key != categoryName) {
        list.removeWhere((pkg) => packageNames.contains(pkg));
      }
    });

    categoryMap[categoryName] = List<String>.from(packageNames);
    await _saveCustomCategoriesNow();
    await _updateCategorizedApps();
  }

  Future<void> removeAppFromCategory(String categoryName, String packageName) async {
    if (categoryMap.containsKey(categoryName)) {
      categoryMap[categoryName]!.remove(packageName);

      final defaultCategories = {
        'Productivity',
        'Developer Tools',
        'Utilities & Tools',
        'Creativity',
        'Social',
        'Entertainment'
      };
      if (defaultCategories.contains(categoryName)) {
        if (!categoryMap.containsKey('Other')) categoryMap['Other'] = [];
        categoryMap['Other']!.add(packageName);
      }

      await _saveCustomCategoriesNow();
      await _updateCategorizedApps();
    }
  }

  bool isCustomCategory(String categoryName) {
    final defaultCategories = {
      'Productivity',
      'Developer Tools',
      'Utilities & Tools',
      'Creativity',
      'Social',
      'Entertainment',
      'Other'
    };
    return !defaultCategories.contains(categoryName);
  }

  Future<void> batchUpdateAppVisibility({
    required Set<String> toLock, 
    required Set<String> toUnlock, 
    required Set<String> toHide, 
    required Set<String> toUnhide
  }) async {
    bool lockedChanged = false;
    bool hiddenChanged = false;
    
    for (var pkg in toLock) { if (!lockedApps.contains(pkg)) { lockedApps.add(pkg); lockedChanged = true; } }
    for (var pkg in toUnlock) { if (lockedApps.contains(pkg)) { lockedApps.remove(pkg); lockedChanged = true; } }
    
    for (var pkg in toHide) { 
      if (!hiddenApps.contains(pkg)) { 
        hiddenApps.add(pkg); 
        hiddenChanged = true; 
        pinnedStart.remove(pkg);
      } 
    }
    for (var pkg in toUnhide) { if (hiddenApps.contains(pkg)) { hiddenApps.remove(pkg); hiddenChanged = true; } }
    
    final prefs = await SharedPreferences.getInstance();
    if (lockedChanged) await prefs.setStringList('lockedApps', lockedApps);
    if (hiddenChanged) {
      await prefs.setStringList('hiddenApps', hiddenApps);
      await prefs.setStringList('pinnedStart', pinnedStart);
      await _updateCategorizedApps();
    }
    notifyListeners();
  }

  Future<void> refreshApps(DesktopState desktopState, {String? injectedPkg, String? injectedName}) async {
    if (kIsWeb) return;
    try {
      List<AppInfo> apps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: false);
      apps.removeWhere((app) => app.packageName == null);
      
      if (injectedPkg != null && injectedPkg.isNotEmpty) {
        if (!apps.any((a) => a.packageName == injectedPkg)) {
          try {
            AppInfo? newApp = await InstalledApps.getAppInfo(injectedPkg);
            if (newApp != null) {
              apps.add(newApp);
            }
          } catch (e) {
            debugPrint("Fallback injection failed: $e");
          }
        }
      }
      
      apps.sort((a, b) => (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase()));
      
      installedApps = apps;
      appMap = {for (var app in apps) if (app.packageName != null) app.packageName!: app};

      await _updateCategorizedApps();

      final validPackages = appMap.keys.toSet();
      bool prefsChanged = false;

      if (injectedPkg != null && injectedPkg.isNotEmpty) {
         validPackages.add(injectedPkg);
      }

      windowStack.removeWhere((pkg) => pkg.contains('.') && !validPackages.contains(pkg));
      minimizedApps.removeWhere((pkg) => pkg.contains('.') && !validPackages.contains(pkg));
      maximizedApps.removeWhere((pkg) => pkg.contains('.') && !validPackages.contains(pkg));
      windowBackHandlers.removeWhere((pkg, _) => pkg.contains('.') && !validPackages.contains(pkg));

      int initialPinnedLength = pinnedStart.length;
      pinnedStart.removeWhere((pkg) => !validPackages.contains(pkg));
      if (pinnedStart.length != initialPinnedLength) prefsChanged = true;

      int initialRecentLength = recentApps.length;
      recentApps.removeWhere((pkg) => !validPackages.contains(pkg));
      if (recentApps.length != initialRecentLength) prefsChanged = true;

      int initialLocked = lockedApps.length;
      lockedApps.removeWhere((pkg) => !validPackages.contains(pkg));
      if (lockedApps.length != initialLocked) prefsChanged = true;

      int initialHidden = hiddenApps.length;
      hiddenApps.removeWhere((pkg) => !validPackages.contains(pkg));
      if (hiddenApps.length != initialHidden) prefsChanged = true;
      
      int initialNewlyLength = recentlyAddedApps.length;
      int initialUpdatedLength = recentlyUpdatedApps.length;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      
      recentlyAddedApps.removeWhere((entry) {
        final parts = entry.split('|');
        final pkg = parts[0];
        final ts = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
        
        if (nowMs - ts >= 86400000) return true;
        if (nowMs - ts < 300000) return false;
        return !validPackages.contains(pkg);
      });
      if (recentlyAddedApps.length != initialNewlyLength) prefsChanged = true;

      recentlyUpdatedApps.removeWhere((entry) {
        final parts = entry.split('|');
        final pkg = parts[0];
        final ts = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
        
        if (nowMs - ts >= 86400000) return true;
        if (nowMs - ts < 300000) return false;
        return !validPackages.contains(pkg);
      });
      if (recentlyUpdatedApps.length != initialUpdatedLength) prefsChanged = true;

      appNotificationCounts.removeWhere((pkg, _) => !validPackages.contains(pkg));
      iconCacheStatus.removeWhere((pkg, _) => pkg.contains('.') && !validPackages.contains(pkg));

      categoryMap.forEach((_, list) {
        list.removeWhere((pkg) => !validPackages.contains(pkg));
      });

      desktopState.cleanUpOrphanedApps(validPackages);

      final prefs = await SharedPreferences.getInstance();
      if (prefsChanged) {
        await prefs.setStringList('pinnedStart', pinnedStart);
        await prefs.setStringList('recentApps', recentApps);
        await prefs.setStringList('lockedApps', lockedApps);
        await prefs.setStringList('hiddenApps', hiddenApps);
        await prefs.setStringList('recentlyAddedApps', recentlyAddedApps);
        await prefs.setStringList('recentlyUpdatedApps', recentlyUpdatedApps);
      }
      _saveCustomCategoriesDebounced();

      notifyListeners();
    } catch (e) {
      debugPrint("Error during refreshApps: $e");
    }
  }

  Future<void> loadRealAndroidApps() async {
    if (kIsWeb) {
      isLoadingApps = false;
      notifyListeners();
      return;
    }
    try {
      List<AppInfo> apps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: false);
      apps.removeWhere((app) => app.packageName == null);
      apps.sort((a, b) => (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase()));
      
      installedApps = apps;
      appMap = {for (var app in apps) if (app.packageName != null) app.packageName!: app};

      await _updateCategorizedApps();

      final prefs = await SharedPreferences.getInstance();
      bool hasInitializedPins = prefs.getBool('hasInitializedPins') ?? false;
      if (!hasInitializedPins && installedApps.isNotEmpty) {
        pinnedStart = installedApps.take(8).map((e) => e.packageName!).toList();
        await prefs.setStringList('pinnedStart', pinnedStart);
        await prefs.setBool('hasInitializedPins', true);
      }
      
      final allPackages = installedApps.map((e) => e.packageName!).toList();
      Future.microtask(() {
        LazyAppIcon.prewarmIcons(allPackages);
      });
      
      isLoadingApps = false;
      notifyListeners();
    } catch (_) {
      isLoadingApps = false;
      notifyListeners();
    }
  }

  void toggleAppHidden(String packageName) async {
    if (hiddenApps.contains(packageName)) {
      hiddenApps.remove(packageName);
    } else {
      hiddenApps.add(packageName);
      if (pinnedStart.contains(packageName)) togglePinToStart(packageName);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hiddenApps', hiddenApps);
    await _updateCategorizedApps();
  }

  void toggleAppLocked(String packageName) async {
    if (lockedApps.contains(packageName)) {
      lockedApps.remove(packageName);
    } else {
      lockedApps.add(packageName);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('lockedApps', lockedApps);
    notifyListeners();
  }

  Future<void> launchNativeApp(String packageName, {SystemState? systemState}) async {
    if (systemState != null && lockedApps.contains(packageName)) {
      bool auth = await systemState.authenticateUser('Authenticate to unlock app');
      if (!auth) return;
    }

    if (!kIsWeb) {
      InstalledApps.startApp(packageName);

      if (!hiddenApps.contains(packageName)) {
        recentApps.remove(packageName);
        recentApps.insert(0, packageName);

        final prefs = await SharedPreferences.getInstance();
        final int maxApps = prefs.getInt('maxRecentApps') ?? 20;

        if (recentApps.length > maxApps) {
          recentApps.removeLast();
        }

        if (!windowStack.contains(packageName)) {
          windowStack.add(packageName);
        } else {
          windowStack.remove(packageName);
          windowStack.add(packageName);
        }

        await prefs.setStringList('recentApps', recentApps);
      }
      notifyListeners();
    }
  }

  // CRITICAL FIX: Ensure 'this_pc' and 'recycle_bin' are correctly translated to 'explorer' 
  // uniformly across the app to prevent empty ghost windows from launching.
  void openApp(String appId) {
    String resolvedId = appId;
    if (appId == 'this_pc' || appId == 'my_files') {
      currentExplorerPath = '/storage/emulated/0';
      resolvedId = 'explorer';
    } else if (appId == 'recycle_bin') {
      resolvedId = 'explorer';
    }

    if (minimizedApps.contains(resolvedId)) minimizedApps.remove(resolvedId);
    if (!windowStack.contains(resolvedId)) windowStack.add(resolvedId);
    focusWindow(resolvedId);
  }

  void closeApp(String appId) {
    windowStack.remove(appId);
    minimizedApps.remove(appId);
    maximizedApps.remove(appId);

    if (appId == 'explorer') fileExplorerPos = null;
    if (appId == 'calculator') calculatorPos = null;
    if (appId == 'browser') browserPos = null;
    if (appId == 'settings') settingsPos = null;

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

  void updateWindowPos(String appId, Offset newPosOrDelta, {bool isAbsolute = false}) {
    if (isAbsolute) {
      if (appId == 'explorer') fileExplorerPos = newPosOrDelta;
      if (appId == 'calculator') calculatorPos = newPosOrDelta;
      if (appId == 'browser') browserPos = newPosOrDelta;
      if (appId == 'settings') settingsPos = newPosOrDelta;
    } else {
      if (appId == 'explorer' && fileExplorerPos != null) fileExplorerPos = fileExplorerPos! + newPosOrDelta;
      if (appId == 'calculator' && calculatorPos != null) calculatorPos = calculatorPos! + newPosOrDelta;
      if (appId == 'browser' && browserPos != null) browserPos = browserPos! + newPosOrDelta;
      if (appId == 'settings' && settingsPos != null) settingsPos = settingsPos! + newPosOrDelta;
    }
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

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    recentApps = prefs.getStringList('recentApps') ?? [];
    pinnedStart = prefs.getStringList('pinnedStart') ?? [];
    hiddenApps = prefs.getStringList('hiddenApps') ?? [];
    lockedApps = prefs.getStringList('lockedApps') ?? [];
    
    final rawRecentAdded = prefs.getStringList('recentlyAddedApps') ?? [];
    final rawRecentUpdated = prefs.getStringList('recentlyUpdatedApps') ?? [];
    final now = DateTime.now().millisecondsSinceEpoch;
    
    recentlyAddedApps = rawRecentAdded.where((entry) {
      final parts = entry.split('|');
      if (parts.length == 2) {
        final ts = int.tryParse(parts[1]) ?? 0;
        return (now - ts) < 86400000; 
      }
      return false;
    }).toList();
    if (rawRecentAdded.length != recentlyAddedApps.length) {
      prefs.setStringList('recentlyAddedApps', recentlyAddedApps);
    }

    recentlyUpdatedApps = rawRecentUpdated.where((entry) {
      final parts = entry.split('|');
      if (parts.length == 2) {
        final ts = int.tryParse(parts[1]) ?? 0;
        return (now - ts) < 86400000; 
      }
      return false;
    }).toList();
    if (rawRecentUpdated.length != recentlyUpdatedApps.length) {
      prefs.setStringList('recentlyUpdatedApps', recentlyUpdatedApps);
    }

    final String? catJson = prefs.getString('appCategoryMap');
    if (catJson != null && catJson.isNotEmpty) {
      try {
        categoryMap = (jsonDecode(catJson) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as List).cast<String>()));
      } catch (_) {}
    }

    if (pinnedStart.length > 8) pinnedStart = pinnedStart.sublist(0, 8);

    explorerViewType = prefs.getString('explorerViewType') ?? 'List';
    explorerSortBy = prefs.getString('explorerSortBy') ?? 'Name';
    explorerSortAscending = prefs.getBool('explorerSortAscending') ?? true;

    notifyListeners();
  }
}