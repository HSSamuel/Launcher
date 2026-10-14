import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../models/desktop_item_model.dart';
import '../services/native_bridge.dart';

class DesktopState extends ChangeNotifier with WidgetsBindingObserver {
  int desktopPages = 1;
  List<DesktopItemModel> desktopItems = [];

  String taskbarAlignment = 'left';
  String taskbarColorStyle = 'default';
  bool showRecentlyAdded = true;
  bool showMostUsed = true;
  bool showRecommended = true;

  double desktopIconScale = 1.0; 
  double desktopFontSize = 11.0; 
  
  double taskbarHeight = 48.0;
  double taskbarIconScale = 1.0;
  double taskbarIconSpacing = 4.0;
  
  String? customStartIconPath;
  
  String pageTransition = 'Classical';
  int portraitGridX = 5; 
  int portraitGridY = 8;
  int landscapeGridX = 8;
  int landscapeGridY = 5;
  bool allowLandscape = false;
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

  bool gestureHapticFeedback = true;
  String gestureDoubleTapAction = 'Lock Screen';
  String gesturePinchInAction = 'None';
  String gesturePinchOutAction = 'None';
  String gestureUpAction = 'None';
  String gestureDownAction = 'None';
  String gestureLeftAction = 'None';
  String gestureRightAction = 'None';
  String gestureTwoFingerUpAction = 'Start Menu';
  String gestureTwoFingerDownAction = 'Device Notification Bar';

  bool searchShowTopApps = true;
  bool searchCatApps = true;
  bool searchCatDocs = true;
  bool searchCatPhotos = true;
  bool searchCatAudio = true;
  bool searchCatVideos = true;
  bool searchCatSettings = true;
  bool searchShowNews = true; 

  bool taskbarItemSearch = true;
  bool taskbarItemTaskView = true;
  bool taskbarItemWidget = true;
  bool taskbarOverInternet = true;
  bool taskbarOverSound = true;
  bool taskbarOverBattery = true;
  bool taskbarOverDate = true;
  bool hideNetworkIcons = false;
  
  bool showTaskbarSystemMonitor = false;

  bool keepOverlaysAliveNextPause = false;
  bool isRecycleBinFull = false;

  Timer? _saveDebouncer;

  DesktopState() { 
    WidgetsBinding.instance.addObserver(this);
    _loadState(); 
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveDebouncer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (_saveDebouncer?.isActive ?? false) {
        _saveDebouncer?.cancel();
        _forceSaveDesktopItems();
      }
    }
  }

  void applyOrientationLock() {
    if (allowLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  Future<void> setAllowLandscape(bool allow) async {
    allowLandscape = allow;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('allowLandscape', allow);
    applyOrientationLock();
    notifyListeners();
  }

  void applySystemUI() {
    if (hideStatusBar && hideNavBar) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else if (hideStatusBar) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.bottom]);
    } else if (hideNavBar) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.top]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> checkRecycleBinStatus() async {
    String rootPath = '/storage/emulated/0';
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) rootPath = extDir.path.split('/Android')[0];
    } catch (_) {}
    
    final binDir = Directory('$rootPath/.Win11RecycleBin');
    bool hasFiles = false;
    
    // Check existence asynchronously
    if (await binDir.exists()) {
      try {
        // Use async 'list()' instead of 'listSync()' to prevent frame drops
        await for (var entity in binDir.list(followLinks: false)) {
          final name = entity.path.split('/').last;
          if (name != '.nomedia' && name != '.recycle_index.json') {
            hasFiles = true;
            break; // Stop searching as soon as we find one valid deleted file
          }
        }
      } catch (_) {}
    }
    
    if (isRecycleBinFull != hasFiles) {
      isRecycleBinFull = hasFiles;
      notifyListeners();
    }
  }

  Future<void> _forceSaveDesktopItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('desktopItems', jsonEncode(desktopItems.map((i) => i.toJson()).toList()));
  }

  void _saveDesktopItems() {
    _saveDebouncer?.cancel();
    _saveDebouncer = Timer(const Duration(milliseconds: 500), () {
      _forceSaveDesktopItems();
    });
  }

  Future<void> syncPhysicalDesktop() async {
    String rootPath = '/storage/emulated/0';
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) rootPath = extDir.path.split('/Android')[0];
    } catch (_) {}

    final desktopDirPath = '$rootPath/Desktop';
    final dir = Directory(desktopDirPath);
    
    if (!(await dir.exists())) {
      try { await dir.create(recursive: true); } catch (_) {}
      return;
    }

    final fileList = await dir.list().toList();
    final files = fileList.where((e) {
      final name = e.path.split('/').last;
      return !name.startsWith('.') && name != 'desktop.ini';
    }).toList();

    bool changed = false;
    final currentPaths = desktopItems.where((i) => i.type == 'file' && i.path != null).map((i) => i.path!).toSet();
    final physicalPaths = files.map((f) => f.path).toSet();

    for (var f in files) {
      if (!currentPaths.contains(f.path)) {
        final slot = _findFirstAvailableSlot(0, 1, 1);
        int page = 0, col = 0, row = 0;
        
        if (slot[0] != -1) {
          col = slot[0]; row = slot[1];
        } else {
          final safeSlot = _findSafeSlotAndPage(0, 1, 1);
          page = safeSlot[0]; col = safeSlot[1]; row = safeSlot[2];
        }
        
        desktopItems.add(DesktopItemModel(
          id: 'file_${f.path.hashCode}',
          type: 'file',
          label: f.path.split('/').last,
          path: f.path,
          page: page,
          col: col,
          row: row,
        ));
        changed = true;
      }
    }

    final itemsToRemove = desktopItems.where((item) {
      if (item.type == 'file' && item.path != null && item.path!.startsWith(desktopDirPath)) {
        return !physicalPaths.contains(item.path);
      }
      return false;
    }).toList();

    for (var item in itemsToRemove) {
      desktopItems.remove(item);
      changed = true;
    }

    if (changed) {
      await _forceSaveDesktopItems();
      notifyListeners();
    }
  }

  void _initializeDefaultDesktop() {
    desktopItems = [
      DesktopItemModel(id: 'recycle_bin', type: 'system', label: 'Recycle Bin', page: 0, col: 0, row: 0),
      DesktopItemModel(id: 'this_pc', type: 'system', label: 'This PC', page: 0, col: 1, row: 0),
      DesktopItemModel(id: 'calculator', type: 'system', label: 'Calculator', page: 0, col: 2, row: 0),
      DesktopItemModel(id: 'browser', type: 'system', label: 'Edge', page: 0, col: 3, row: 0),
      DesktopItemModel(id: 'settings', type: 'system', label: 'Settings', page: 0, col: 4, row: 0),
    ];
    _saveDesktopItems();
  }

  bool _isSlotOccupied(int page, int col, int row, int spanX, int spanY) {
    return desktopItems.any((item) {
      if (item.page != page) return false;
      return col < item.col + item.spanX && 
             col + spanX > item.col && 
             row < item.row + item.spanY && 
             row + spanY > item.row;
    });
  }

  List<int> _findFirstAvailableSlot(int page, int itemSpanX, int itemSpanY) {
    int maxCols = math.max(landscapeGridX, portraitGridX);
    int maxRows = math.max(landscapeGridY, portraitGridY);

    for (int c = 0; c <= maxCols - itemSpanX; c++) {
      for (int r = 0; r <= maxRows - itemSpanY; r++) {
        if (!_isSlotOccupied(page, c, r, itemSpanX, itemSpanY)) {
          return [c, r];
        }
      }
    }
    return [-1, -1]; 
  }

  List<int> _findSafeSlotAndPage(int startPage, int spanX, int spanY) {
    int page = startPage;
    while (true) {
      final slot = _findFirstAvailableSlot(page, spanX, spanY);
      if (slot[0] != -1) {
        return [page, slot[0], slot[1]];
      }
      page++;
      if (page >= desktopPages) {
        desktopPages = page + 1;
        SharedPreferences.getInstance().then((prefs) => prefs.setInt('desktopPages', desktopPages));
        notifyListeners();
      }
    }
  }

  void mergeIntoFolder(String targetId, String draggedId) {
    final targetIdx = desktopItems.indexWhere((i) => i.id == targetId);
    final draggedIdx = desktopItems.indexWhere((i) => i.id == draggedId);
    if (targetIdx == -1 || draggedIdx == -1) return;

    final target = desktopItems[targetIdx];
    final dragged = desktopItems[draggedIdx];

    if (target.type == 'app' && dragged.type == 'app') {
      desktopItems[targetIdx] = DesktopItemModel(
        id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
        type: 'folder',
        label: 'Desktop Folder',
        page: target.page,
        col: target.col,
        row: target.row,
        folderApps: [target.package!, dragged.package!],
      );
      desktopItems.removeAt(draggedIdx);
    } else if (target.type == 'folder' && dragged.type == 'app') {
      if (target.folderApps == null) target.folderApps = [];
      if (!target.folderApps!.contains(dragged.package!)) {
        target.folderApps = [...target.folderApps!, dragged.package!];
      }
      desktopItems.removeAt(draggedIdx);
    }
    _saveDesktopItems();
    notifyListeners();
  }

  void extractAppFromFolder(String folderId, String packageName, String appLabel, int targetPage, String Function(String) getAppName) {
    final folderIdx = desktopItems.indexWhere((i) => i.id == folderId);
    if (folderIdx == -1) return;
    
    final folder = desktopItems[folderIdx];
    folder.folderApps?.remove(packageName);
    
    int page = targetPage;
    int c = folder.col;
    int r = folder.row + 1;
    
    int maxRows = math.max(landscapeGridY, portraitGridY);
    if (r >= maxRows) { r = folder.row - 1; if (r < 0) r = 0; }

    if (_isSlotOccupied(page, c, r, 1, 1)) {
      final loc = _findSafeSlotAndPage(page, 1, 1);
      page = loc[0]; c = loc[1]; r = loc[2];
    }
    desktopItems.add(DesktopItemModel(id: packageName, type: 'app', label: appLabel, package: packageName, page: page, col: c, row: r));
    
    if (folder.folderApps == null || folder.folderApps!.isEmpty) {
      desktopItems.removeWhere((i) => i.id == folderId);
    } else if (folder.folderApps!.length == 1) {
      String lastPkg = folder.folderApps!.first;
      String label = getAppName(lastPkg);
      int fPage = folder.page;
      int fCol = folder.col;
      int fRow = folder.row;
      
      desktopItems.removeWhere((i) => i.id == folderId);
      desktopItems.add(DesktopItemModel(id: lastPkg, type: 'app', label: label, package: lastPkg, page: fPage, col: fCol, row: fRow));
    }
    _saveDesktopItems();
    notifyListeners();
  }

  void removeFromFolder(String folderId, String packageName) {
    final folderIdx = desktopItems.indexWhere((i) => i.id == folderId);
    if (folderIdx != -1) {
      desktopItems[folderIdx].folderApps?.remove(packageName);
      if (desktopItems[folderIdx].folderApps?.isEmpty ?? true) {
        desktopItems.removeAt(folderIdx);
      }
      _saveDesktopItems();
      notifyListeners();
    }
  }

  void cleanUpOrphanedApps(Set<String> validPackages) {
    int initialLength = desktopItems.length;
    bool folderContentsChanged = false;

    desktopItems.removeWhere((item) => item.type == 'app' && !validPackages.contains(item.package));
    
    for (var item in desktopItems.where((i) => i.type == 'folder')) {
      final beforeCount = item.folderApps?.length ?? 0;
      item.folderApps?.removeWhere((pkg) => !validPackages.contains(pkg));
      if ((item.folderApps?.length ?? 0) != beforeCount) {
        folderContentsChanged = true;
      }
    }

    desktopItems.removeWhere((item) => item.type == 'folder' && (item.folderApps == null || item.folderApps!.isEmpty));

    if (desktopItems.length != initialLength || folderContentsChanged) {
      _saveDesktopItems();
      notifyListeners();
    }
  }

  void moveItemToPage(String id, int targetPage) {
    final index = desktopItems.indexWhere((i) => i.id == id);
    if (index != -1) {
      final loc = _findSafeSlotAndPage(targetPage, desktopItems[index].spanX, desktopItems[index].spanY);
      desktopItems[index].page = loc[0];
      desktopItems[index].col = loc[1];
      desktopItems[index].row = loc[2];
      _saveDesktopItems();
      notifyListeners();
    }
  }

  void copyItemToPage(String originalId, int targetPage) {
    final original = desktopItems.firstWhere((i) => i.id == originalId, orElse: () => DesktopItemModel(id: '', type: '', label: '', page: 0, col: 0, row: 0));
    if (original.id.isNotEmpty) {
      final loc = _findSafeSlotAndPage(targetPage, original.spanX, original.spanY);
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
        page: loc[0], 
        col: loc[1], 
        row: loc[2]
      ));
      _saveDesktopItems();
      notifyListeners();
    }
  }

  Future<void> addNativeWidget(int targetPage, int col, int row) async {
    try {
      final data = await NativeBridge.instance.pickWidget();
      if (data != null) {
        int spanX = (data['minWidth'] / 80).ceil().clamp(1, 4);
        int spanY = (data['minHeight'] / 80).ceil().clamp(1, 4);
        int page = targetPage;
        
        if (_isSlotOccupied(page, col, row, spanX, spanY)) {
          final loc = _findSafeSlotAndPage(page, spanX, spanY);
          page = loc[0]; col = loc[1]; row = loc[2];
        }
        
        desktopItems.add(DesktopItemModel(
          id: 'native_widget_${data['appWidgetId']}', 
          type: 'native_widget', 
          label: data['label'], 
          appWidgetId: data['appWidgetId'], 
          spanX: spanX, 
          spanY: spanY, 
          page: page, 
          col: col, 
          row: row
        ));
        _saveDesktopItems();
        notifyListeners();
      }
    } catch (_) {}
  }

  void resizeDesktopItem(String id, int spanX, int spanY, double cellWidth, double cellHeight) {
    final index = desktopItems.indexWhere((i) => i.id == id);
    if (index != -1) {
      desktopItems[index].spanX = spanX;
      desktopItems[index].spanY = spanY;
      _saveDesktopItems();
      notifyListeners();
      if (desktopItems[index].type == 'native_widget' && desktopItems[index].appWidgetId != null) {
        NativeBridge.instance.updateWidgetSize(desktopItems[index].appWidgetId!, (spanX * cellWidth).toInt(), (spanY * cellHeight).toInt());
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
      int targetPage = desktopPages - 1;
      
      var itemsToMove = desktopItems.where((i) => i.page > targetPage).toList();
      
      for (var item in itemsToMove) {
        final slot = _findFirstAvailableSlot(targetPage, item.spanX, item.spanY);
        if (slot[0] != -1) {
          item.page = targetPage;
          item.col = slot[0];
          item.row = slot[1];
        } else {
          item.page = 0;
          item.col = 0;
          item.row = 0;
        }
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
      final colIdx = desktopItems.indexWhere((i) => i.page == page && i.col == col && i.row == row && i.id != id);
      if (colIdx != -1) {
        desktopItems[colIdx].col = desktopItems[index].col;
        desktopItems[colIdx].row = desktopItems[index].row;
        desktopItems[colIdx].page = desktopItems[index].page;
      }
      desktopItems[index].page = page; desktopItems[index].col = col; desktopItems[index].row = row;
      _saveDesktopItems();
      notifyListeners();
    }
  }

  Future<void> removeDesktopItem(String id) async {
    final index = desktopItems.indexWhere((i) => i.id == id);
    if (index != -1) {
      desktopItems.removeAt(index);
      _saveDesktopItems();
      notifyListeners();
    }
  }

  Future<void> renameDesktopItem(String id, String newName) async {
    final index = desktopItems.indexWhere((i) => i.id == id);
    if (index != -1) {
      final item = desktopItems[index];
      if (item.type == 'file' && item.path != null && item.path!.contains('/Desktop')) {
         try {
           final oldPath = item.path!;
           final parentDir = oldPath.substring(0, oldPath.lastIndexOf('/'));
           final newPath = '$parentDir/$newName';
           final isDir = await Directory(oldPath).exists();
           if (isDir) {
             await Directory(oldPath).rename(newPath);
           } else {
             await File(oldPath).rename(newPath);
           }
           desktopItems[index] = item.copyWith(label: newName, path: newPath);
         } catch (_) {
           desktopItems[index].label = newName; 
         }
      } else {
        desktopItems[index].label = newName; 
      }
      _saveDesktopItems();
      notifyListeners();
    }
  }

  void addDesktopApp(String packageName, String name, int targetPage, int col, int row) {
    if (!desktopItems.any((i) => i.id == packageName)) {
      int page = targetPage;
      if (_isSlotOccupied(page, col, row, 1, 1)) {
        final loc = _findSafeSlotAndPage(page, 1, 1);
        page = loc[0]; col = loc[1]; row = loc[2];
      }
      desktopItems.add(DesktopItemModel(id: packageName, type: 'app', label: name, package: packageName, page: page, col: col, row: row));
      _saveDesktopItems();
      notifyListeners();
    }
  }

  void addDesktopShortcut({
    required String name,
    required String targetPath,
    required String shortcutType,
    required int targetPage,
    required int col,
    required int row,
  }) {
    int page = targetPage;
    if (_isSlotOccupied(page, col, row, 1, 1)) {
      final loc = _findSafeSlotAndPage(page, 1, 1);
      page = loc[0]; col = loc[1]; row = loc[2];
    }

    final newId = 'shortcut_${DateTime.now().millisecondsSinceEpoch}';
    desktopItems.add(DesktopItemModel(
      id: newId,
      type: 'shortcut',
      label: name,
      path: targetPath,
      widgetType: shortcutType,
      spanX: 1,
      spanY: 1,
      page: page,
      col: col,
      row: row,
    ));
    _saveDesktopItems();
    notifyListeners();
  }

  void addDesktopWidget(String widgetType, String label, int targetPage, int col, int row, {int spanX = 2, int spanY = 1}) {
    int page = targetPage;
    if (_isSlotOccupied(page, col, row, spanX, spanY)) {
      final loc = _findSafeSlotAndPage(page, spanX, spanY);
      page = loc[0]; col = loc[1]; row = loc[2];
    }
    
    desktopItems.add(DesktopItemModel(id: 'widget_${widgetType}_${DateTime.now().millisecondsSinceEpoch}', type: 'widget', label: label, widgetType: widgetType, spanX: spanX, spanY: spanY, page: page, col: col, row: row));
    _saveDesktopItems();
    notifyListeners();
  }

  Future<void> updateDesktopSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == 'desktopIconScale') { desktopIconScale = value; await prefs.setDouble(key, value); }
    if (key == 'desktopFontSize') { desktopFontSize = value; await prefs.setDouble(key, value); }
    if (key == 'pageTransition') { pageTransition = value; await prefs.setString(key, value); }
    if (key == 'portraitGridX') { portraitGridX = value; await prefs.setInt(key, value); }
    if (key == 'portraitGridY') { portraitGridY = value; await prefs.setInt(key, value); }
    if (key == 'landscapeGridX') { landscapeGridX = value; await prefs.setInt(key, value); }
    if (key == 'landscapeGridY') { landscapeGridY = value; await prefs.setInt(key, value); }
    if (key == 'allowLandscape') { allowLandscape = value; await prefs.setBool(key, value); applyOrientationLock(); }
    if (key == 'dragIcons') { dragIcons = value; await prefs.setBool(key, value); }
    if (key == 'hideStatusBar') { hideStatusBar = value; await prefs.setBool(key, value); applySystemUI(); }
    if (key == 'hideNavBar') { hideNavBar = value; await prefs.setBool(key, value); applySystemUI(); }
    if (key == 'createShortcut') { createShortcut = value; await prefs.setBool(key, value); }
    if (key == 'devMode') { devMode = value; await prefs.setBool(key, value); }
    if (key == 'windowsSubsystem') { windowsSubsystem = value; await prefs.setBool(key, value); }
    if (key == 'experimentalEngine') { experimentalEngine = value; await prefs.setBool(key, value); }
    if (key == 'showHiddenFiles') { showHiddenFiles = value; await prefs.setBool(key, value); }
    if (key == 'previewFiles') { previewFiles = value; await prefs.setBool(key, value); }
    if (key == 'mouseSound') { mouseSound = value; await prefs.setBool(key, value); }
    if (key == 'gestureHapticFeedback') { gestureHapticFeedback = value; await prefs.setBool(key, value); }
    if (key == 'showTaskbarSystemMonitor') { showTaskbarSystemMonitor = value; await prefs.setBool(key, value); }
    notifyListeners();
  }

  Future<void> updateGesture(String type, String action) async {
    final prefs = await SharedPreferences.getInstance();
    if (type == 'DOUBLE_TAP') { gestureDoubleTapAction = action; await prefs.setString('gestureDoubleTapAction', action); }
    else if (type == 'PINCH_IN') { gesturePinchInAction = action; await prefs.setString('gesturePinchInAction', action); }
    else if (type == 'PINCH_OUT') { gesturePinchOutAction = action; await prefs.setString('gesturePinchOutAction', action); }
    else if (type == 'UP') { gestureUpAction = action; await prefs.setString('gestureUpAction', action); }
    else if (type == 'DOWN') { gestureDownAction = action; await prefs.setString('gestureDownAction', action); }
    else if (type == 'LEFT') { gestureLeftAction = action; await prefs.setString('gestureLeftAction', action); }
    else if (type == 'RIGHT') { gestureRightAction = action; await prefs.setString('gestureRightAction', action); }
    else if (type == '2_UP') { gestureTwoFingerUpAction = action; await prefs.setString('gestureTwoFingerUpAction', action); }
    else if (type == '2_DOWN') { gestureTwoFingerDownAction = action; await prefs.setString('gestureTwoFingerDownAction', action); }
    notifyListeners();
  }

  Future<void> updateSearchSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == 'showTopApps') searchShowTopApps = value;
    if (key == 'showNews') searchShowNews = value;
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

  Future<void> setTaskbarDimensions({double? height, double? iconScale, double? iconSpacing}) async {
    final prefs = await SharedPreferences.getInstance();
    if (height != null) {
      taskbarHeight = height;
      await prefs.setDouble('taskbarHeight', height);
    }
    if (iconScale != null) {
      taskbarIconScale = iconScale;
      await prefs.setDouble('taskbarIconScale', iconScale);
    }
    if (iconSpacing != null) {
      taskbarIconSpacing = iconSpacing;
      await prefs.setDouble('taskbarIconSpacing', iconSpacing);
    }
    notifyListeners();
  }

  Future<void> setStartMenuOptions({bool? recentlyAdded, bool? mostUsed, bool? recommended}) async {
    final prefs = await SharedPreferences.getInstance();
    if (recentlyAdded != null) { showRecentlyAdded = recentlyAdded; await prefs.setBool('showRecentlyAdded', recentlyAdded); }
    if (mostUsed != null) { showMostUsed = mostUsed; await prefs.setBool('showMostUsed', mostUsed); }
    if (recommended != null) { showRecommended = recommended; await prefs.setBool('showRecommended', recommended); }
    notifyListeners();
  }

  Future<void> setTaskbarAlignment(String alignment) async {
    taskbarAlignment = alignment;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('taskbarAlignment', alignment);
    notifyListeners();
  }
  
  Future<void> setTaskbarColorStyle(String style) async {
    taskbarColorStyle = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('taskbarColorStyle', style);
    notifyListeners();
  }

  Future<void> setCustomStartIcon(String? path) async {
    customStartIconPath = path;
    final prefs = await SharedPreferences.getInstance();
    if (path != null) {
      await prefs.setString('customStartIconPath', path);
    } else {
      await prefs.remove('customStartIconPath');
    }
    notifyListeners();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    taskbarAlignment = prefs.getString('taskbarAlignment') ?? 'left';
    taskbarColorStyle = prefs.getString('taskbarColorStyle') ?? 'default'; 
    showRecentlyAdded = prefs.getBool('showRecentlyAdded') ?? true;
    showMostUsed = prefs.getBool('showMostUsed') ?? true;
    showRecommended = prefs.getBool('showRecommended') ?? true;

    desktopIconScale = prefs.getDouble('desktopIconScale') ?? 1.0;
    desktopFontSize = prefs.getDouble('desktopFontSize') ?? 11.0;
    
    taskbarHeight = prefs.getDouble('taskbarHeight') ?? 48.0;
    taskbarIconScale = prefs.getDouble('taskbarIconScale') ?? 1.0;
    taskbarIconSpacing = prefs.getDouble('taskbarIconSpacing') ?? 4.0;
    
    customStartIconPath = prefs.getString('customStartIconPath');

    pageTransition = prefs.getString('pageTransition') ?? 'Classical';
    portraitGridX = prefs.getInt('portraitGridX') ?? 5;
    portraitGridY = prefs.getInt('portraitGridY') ?? 8;
    landscapeGridX = prefs.getInt('landscapeGridX') ?? 8;
    landscapeGridY = prefs.getInt('landscapeGridY') ?? 5;
    allowLandscape = prefs.getBool('allowLandscape') ?? false;
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

    gestureHapticFeedback = prefs.getBool('gestureHapticFeedback') ?? true;
    gestureDoubleTapAction = prefs.getString('gestureDoubleTapAction') ?? (prefs.getBool('doubleTapToSleep') == false ? 'None' : 'Lock Screen');
    gesturePinchInAction = prefs.getString('gesturePinchInAction') ?? 'None';
    gesturePinchOutAction = prefs.getString('gesturePinchOutAction') ?? 'None';
    gestureUpAction = prefs.getString('gestureUpAction') ?? 'None';
    gestureDownAction = prefs.getString('gestureDownAction') ?? 'None';
    gestureLeftAction = prefs.getString('gestureLeftAction') ?? 'None';
    gestureRightAction = prefs.getString('gestureRightAction') ?? 'None';
    gestureTwoFingerUpAction = prefs.getString('gestureTwoFingerUpAction') ?? 'Start Menu';
    gestureTwoFingerDownAction = prefs.getString('gestureTwoFingerDownAction') ?? 'Device Notification Bar';

    searchShowTopApps = prefs.getBool('search_showTopApps') ?? true;
    searchShowNews = prefs.getBool('search_showNews') ?? true;
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
    
    showTaskbarSystemMonitor = prefs.getBool('showTaskbarSystemMonitor') ?? false;

    desktopPages = prefs.getInt('desktopPages') ?? 1;

    final String? itemsJson = prefs.getString('desktopItems');
    if (itemsJson != null && itemsJson.isNotEmpty) {
      try {
        desktopItems = (jsonDecode(itemsJson) as List).map((e) => DesktopItemModel.fromJson(e)).toList();
        
        bool needsSave = false;
        for (int i = 0; i < desktopItems.length; i++) {
           if (desktopItems[i].id == 'my_files') {
              desktopItems[i] = desktopItems[i].copyWith(id: 'this_pc', label: 'This PC');
              needsSave = true;
           }
        }
        if (needsSave) _saveDesktopItems();

      } catch (_) { _initializeDefaultDesktop(); }
    } else {
      _initializeDefaultDesktop();
    }
    
    applySystemUI();
    applyOrientationLock();
    checkRecycleBinStatus();
    notifyListeners();
  }
}