import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../launcher_state.dart';
import '../../models/file_item.dart';
import '../../services/native_bridge.dart';
import 'explorer_components.dart';
import 'explorer_content_view.dart';

class FileExplorerApp extends StatefulWidget {
  const FileExplorerApp({Key? key}) : super(key: key);

  @override
  State<FileExplorerApp> createState() => FileExplorerAppState();
}

class FileExplorerAppState extends State<FileExplorerApp> with WidgetsBindingObserver {
  final String _rootPath = '/storage/emulated/0';

  bool _hasPermission = false;
  bool _isAtHome = true;
  late Directory _currentDir;
  
  List<FileItem> _files = [];
  List<String> _pathHistory = []; 

  // CRITICAL FIX: Safe defaults with fallback loading states instead of fake data
  double _totalGB = 0.0;
  double _freeGB = 0.0;

  Set<String> _selectedPaths = {};
  bool _isMultiSelectMode = false;
  
  bool _isContextMenuOpen = false;
  Offset _contextMenuPos = Offset.zero;
  String? _activeSubMenu;
  double _subMenuYOffset = 0;
  
  String _contextMenuType = 'desktop'; 
  String _contextTargetName = '';

  double _sidebarWidthPercent = 36.0;
  bool _isGridView = false;
  
  bool? _lastThemeDark;

  @override
  void initState() {
    super.initState();
    _currentDir = Directory(context.read<LauncherState>().currentExplorerPath);
    if (_currentDir.path != _rootPath) _isAtHome = false;
    
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
    _fetchStorageStats();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isDark = context.watch<LauncherState>().isDarkMode;
    if (_lastThemeDark != isDark) {
      _lastThemeDark = isDark;
      _updateStatusBar(isDark);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restoreTransparentStatusBar();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_lastThemeDark != null) {
        _updateStatusBar(_lastThemeDark!);
      }
      _checkPermission();
      _fetchStorageStats();
    }
  }

  void _updateStatusBar(bool isDark) {
    NativeBridge.instance.setStatusBarColor(isDark ? '#191919' : '#FFFFFF', !isDark);
  }

  void _restoreTransparentStatusBar() {
    NativeBridge.instance.setStatusBarColor('#00000000', false);
  }

  Future<void> _fetchStorageStats() async {
    final stats = await NativeBridge.instance.getStorageStats();
    if (stats != null && mounted) {
      setState(() {
        _totalGB = stats['total']! / (1024 * 1024 * 1024);
        _freeGB = stats['free']! / (1024 * 1024 * 1024);
      });
    }
  }

  Future<void> _checkPermission() async {
    final result = await NativeBridge.instance.getPermissionStatuses();
    if (mounted) {
      setState(() => _hasPermission = result['storage'] ?? false);
      if (_hasPermission && !_isAtHome) await _loadDirectorySafe(_currentDir.path);
    }
  }

  Future<void> _loadDirectorySafe(String path, {bool isBack = false}) async {
    if (!_hasPermission) {
      NativeBridge.instance.openSettings('storage');
      return;
    }
    
    if (!isBack) {
      if (_isAtHome) {
        _pathHistory.add('HOME');
      } else {
        _pathHistory.add(_currentDir.path);
      }
    }

    final dir = Directory(path);
    if (!(await dir.exists())) {
      try { await dir.create(recursive: true); } catch (_) {}
    }
    await _loadDirectory(dir);
  }

  // CRITICAL FIX: Replaced sequential processing with Future.wait for concurrent OS-level I/O operations
  static Future<List<FileItem>> _processDirectoryInBackground(String dirPath) async {
    final dir = Directory(dirPath);
    final entities = await dir.list().toList();
    
    final items = await Future.wait(entities.map((e) async {
      try {
        final stat = await e.stat();
        int count = 0;
        bool isDir = e is Directory;
        if (isDir) {
          try { count = e.listSync().length; } catch (_) {}
        }
        return FileItem(path: e.path, isDir: isDir, size: stat.size, modified: stat.modified, itemCount: count);
      } catch (_) {
        return null; 
      }
    }));
    
    final validItems = items.whereType<FileItem>().toList();
    
    validItems.sort((a, b) {
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
    
    return validItems;
  }

  Future<void> _loadDirectory(Directory dir) async {
    try {
      final items = await compute(_processDirectoryInBackground, dir.path);
      if (mounted) {
        setState(() {
          _isAtHome = false;
          _currentDir = dir;
          _files = items;
          _selectedPaths.clear();
          _isMultiSelectMode = false;
          _isContextMenuOpen = false;
        });
      }
    } catch (e) {
      debugPrint("Error reading directory: $e");
    }
  }

  void _goHome({bool isBack = false}) {
    if (!isBack && !_isAtHome) {
      _pathHistory.add(_currentDir.path);
    }
    setState(() {
      _isAtHome = true;
      _selectedPaths.clear();
      _isMultiSelectMode = false;
      _isContextMenuOpen = false;
    });
  }

  bool goBack() {
    if (_pathHistory.isEmpty) return false;
    String prevPath = _pathHistory.removeLast();
    if (prevPath == 'HOME') {
      _goHome(isBack: true);
    } else {
      _loadDirectorySafe(prevPath, isBack: true);
    }
    return true;
  }
  
  void _showToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(fontSize: 13)), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))));
  }

  void _createNewFolder() async {
    final isDark = context.read<LauncherState>().isDarkMode;
    final String? folderName = await showDialog<String>(
      context: context, builder: (ctx) => SafeInputDialog(title: 'New Folder', initialText: 'New Folder', hintText: 'Folder name', actionText: 'Create', isDark: isDark),
    );

    if (folderName != null && folderName.trim().isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 150), () async {
        try {
          final newDir = Directory('${_currentDir.path}/${folderName.trim()}');
          if (!(await newDir.exists())) await newDir.create();
          await _loadDirectory(_currentDir);
          _showToast('Folder created');
        } catch (_) { _showToast('Permission denied'); }
      });
    }
  }

  void _renameFile() async {
    if (_selectedPaths.length != 1) return;
    final isDark = context.read<LauncherState>().isDarkMode;
    final entityPath = _selectedPaths.first;
    String oldName = entityPath.split('/').last;

    final String? newName = await showDialog<String>(
      context: context, builder: (ctx) => SafeInputDialog(title: 'Rename', initialText: oldName, hintText: 'New name', actionText: 'Rename', isDark: isDark),
    );

    if (newName != null && newName.trim().isNotEmpty && newName != oldName) {
      Future.delayed(const Duration(milliseconds: 150), () async {
        try {
          final isDir = await FileSystemEntity.isDirectory(entityPath);
          final entity = isDir ? Directory(entityPath) : File(entityPath);
          await entity.rename('${_currentDir.path}/${newName.trim()}');
          await _loadDirectory(_currentDir);
          _showToast('Renamed to ${newName.trim()}');
        } catch (_) { _showToast('Cannot rename OS protected folders'); }
      });
    }
  }

  Future<void> _deleteSelectedFiles() async {
    try {
      for (String path in _selectedPaths) {
        final isDir = await FileSystemEntity.isDirectory(path);
        final entity = isDir ? Directory(path) : File(path);
        if (await entity.exists()) await entity.delete(recursive: true);
      }
      await _loadDirectory(_currentDir);
      _showToast('Deleted ${_selectedPaths.length} items');
    } catch (_) { _showToast('Error deleting files'); }
  }

  // CRITICAL FIX: Custom recursive directory algorithm added for robust deep copying
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (var entity in source.list(recursive: false)) {
      if (entity is Directory) {
        var newDirectory = Directory('${destination.path}/${entity.path.split('/').last}');
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        await entity.copy('${destination.path}/${entity.path.split('/').last}');
      }
    }
  }

  Future<void> _pasteFile() async {
    final state = context.read<LauncherState>();
    if (state.clipboardPath != null) {
      try {
        final sourcePath = state.clipboardPath!;
        final isDir = await FileSystemEntity.isDirectory(sourcePath);
        final entity = isDir ? Directory(sourcePath) : File(sourcePath);
        final name = sourcePath.split('/').last;
        final newPath = '${_currentDir.path}/$name';
        
        if (entity is File) {
          await entity.copy(newPath);
          if (state.isCut) await entity.delete();
        } else if (entity is Directory) {
          if (state.isCut) { 
            await entity.rename(newPath); 
          } else { 
            await _copyDirectory(entity, Directory(newPath)); 
          }
        }
        
        if (state.isCut) state.clearClipboard();
        await _loadDirectory(_currentDir);
        _showToast('Paste successful');
      } catch (_) { _showToast('Error pasting file'); }
    }
  }

  void _closeOverlays() {
    setState(() {
      _isContextMenuOpen = false;
      _activeSubMenu = null;
    });
  }

  Widget _buildContextMenuItem(String title, IconData? icon, LauncherState state, {Color? iconColor, bool hasSubMenu = false, String? subMenuKey, double subMenuY = 0, VoidCallback? onTap}) {
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final defaultIconColor = isDark ? Colors.white : Colors.black87;
    return InkWell(
      onTap: () {
        if (hasSubMenu) { setState(() { _activeSubMenu = subMenuKey; _subMenuYOffset = subMenuY; }); } 
        else { _closeOverlays(); if (onTap != null) onTap(); }
      },
      hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            if (icon != null) Icon(icon, size: 16, color: iconColor ?? defaultIconColor), if (icon != null) const SizedBox(width: 12),
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, color: textColor))),
            if (hasSubMenu) Icon(Icons.chevron_right, size: 16, color: isDark ? Colors.white54 : Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  Widget _buildSubMenuItem(String title, IconData? icon, LauncherState state, {bool isActive = false, bool isChecked = false, bool isDot = false, VoidCallback? onTap}) {
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    return InkWell(
      onTap: () { if (onTap != null) onTap(); _closeOverlays(); },
      hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (icon != null || isActive || isDot || isChecked) ...[
              SizedBox(width: 16, child: isActive || isDot ? Icon(Icons.circle, size: 6, color: textColor) : (isChecked ? Icon(Icons.check, size: 14, color: textColor) : null)), const SizedBox(width: 8),
              if (icon != null) Icon(icon, size: 16, color: textColor), if (icon != null) const SizedBox(width: 12),
            ],
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, color: textColor))),
          ],
        ),
      ),
    );
  }

  void _showPropertiesDialog() async {
    if (_selectedPaths.length != 1) return;
    try {
      final isDark = context.read<LauncherState>().isDarkMode;
      final entity = File(_selectedPaths.first);
      final stat = await entity.stat();
      final size = stat.size;
      final modified = stat.modified.toString().split('.')[0];
      final name = entity.path.split('/').last;

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
          title: Text('$name Properties', style: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black87)),
          content: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Location: ${entity.path}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)), const SizedBox(height: 8),
              Text('Size: ${(size / 1024).toStringAsFixed(2)} KB', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)), const SizedBox(height: 8),
              Text('Modified: $modified', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Colors.blueAccent)))],
        )
      );
    } catch (_) { _showToast('Could not read properties'); }
  }

  Widget _buildContextMenuOverlay(LauncherState state) {
    if (!_isContextMenuOpen) return const SizedBox.shrink();

    final isDark = state.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B).withOpacity(0.95) : const Color(0xFFF3F3F3).withOpacity(0.95);
    double menuWidth = 240, menuHeight = _contextMenuType == 'folder' ? 320 : 200, dx = _contextMenuPos.dx, dy = _contextMenuPos.dy;
    final screenSize = MediaQuery.of(context).size;
    
    if (dx + menuWidth > screenSize.width) dx = screenSize.width - menuWidth - 8;
    if (dx < 8) dx = 8;
    if (dy + menuHeight > screenSize.height) dy = screenSize.height - menuHeight - 8;
    if (dy < 8) dy = 8;

    Widget mainMenu = Container(
      width: menuWidth,
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300, width: 1), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))]),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _contextMenuType == 'desktop'
          ? [
              _buildContextMenuItem('View', Icons.grid_view, state, hasSubMenu: true, subMenuKey: 'view', subMenuY: 0),
              _buildContextMenuItem('Sort by', Icons.swap_vert, state, hasSubMenu: true, subMenuKey: 'sort', subMenuY: 36),
              _buildContextMenuItem('Refresh', Icons.refresh, state, onTap: () => _showToast('Refreshed')),
            ]
          : [
              _buildContextMenuItem('Open', Icons.open_in_new, state, iconColor: Colors.blueAccent, onTap: () {
                if (_selectedPaths.isNotEmpty) NativeBridge.instance.openFile(_selectedPaths.first);
              }),
              _buildContextMenuItem('Properties', Icons.build_circle_outlined, state, onTap: () => _showPropertiesDialog()),
              Container(height: 1, color: isDark ? Colors.white24 : Colors.grey.shade300, margin: const EdgeInsets.symmetric(vertical: 4)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    InkWell(onTap: () { _closeOverlays(); state.setClipboard(_selectedPaths.first, true); _showToast('Cut'); }, child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.content_cut, size: 18, color: const Color(0xFF0078D4)), const SizedBox(height: 4), Text('Cut', style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87))])),
                    InkWell(onTap: () { _closeOverlays(); state.setClipboard(_selectedPaths.first, false); _showToast('Copied'); }, child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.content_copy, size: 18, color: const Color(0xFF0078D4)), const SizedBox(height: 4), Text('Copy', style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87))])),
                    InkWell(onTap: () { _closeOverlays(); _renameFile(); }, child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.drive_file_rename_outline, size: 18, color: const Color(0xFF0078D4)), const SizedBox(height: 4), Text('Rename', style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87))])),
                    InkWell(onTap: () { _closeOverlays(); _deleteSelectedFiles(); }, child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.delete_outline, size: 18, color: const Color(0xFF0078D4)), const SizedBox(height: 4), Text('Delete', style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87))])),
                  ],
                ),
              ),
            ],
      ),
    );

    Widget? subMenu;
    if (_activeSubMenu != null) {
      double subMenuWidth = 190, subMenuX = dx + menuWidth - 4, subMenuY = dy + _subMenuYOffset;
      if (subMenuX + subMenuWidth > screenSize.width) subMenuX = dx - subMenuWidth + 4;
      if (subMenuY + 220 > screenSize.height) subMenuY = screenSize.height - 230;
      subMenu = Positioned(
        left: subMenuX, top: subMenuY,
        child: Container(
          width: subMenuWidth,
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300, width: 1), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))]),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _activeSubMenu == 'view'
              ? [_buildSubMenuItem('Large icons', Icons.crop_square, state), _buildSubMenuItem('List', Icons.format_list_bulleted, state)]
              : [_buildSubMenuItem('Name', null, state, isDot: true), _buildSubMenuItem('Size', null, state)],
          ),
        ),
      );
    }
    return Stack(children: [Positioned(left: dx, top: dy, child: mainMenu), if (subMenu != null) subMenu]);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final sidebarWidth = math.max(130.0, screenWidth * (_sidebarWidthPercent / 100));
    final bgColor = isDark ? const Color(0xFF191919) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(statusBarColor: bgColor, statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark, statusBarBrightness: isDark ? Brightness.dark : Brightness.light),
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.goBack || event.logicalKey == LogicalKeyboardKey.escape)) {
              if (!_isAtHome && _pathHistory.isNotEmpty) { goBack(); return KeyEventResult.handled; }
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: _closeOverlays,
            onSecondaryTapDown: (details) { if (_isAtHome) setState(() { _contextMenuPos = details.globalPosition; _contextMenuType = 'desktop'; _isContextMenuOpen = true; }); },
            onLongPressStart: (details) { if (_isAtHome) setState(() { _contextMenuPos = details.globalPosition; _contextMenuType = 'desktop'; _isContextMenuOpen = true; }); },
            child: Stack(
              children: [
                Container(
                  color: bgColor,
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        ExplorerTitleBar(isDark: isDark, onRestoreStatusBar: _restoreTransparentStatusBar),
                        ExplorerToolbar(
                          isDark: isDark, hasSelection: _selectedPaths.isNotEmpty, isSingleSelection: _selectedPaths.length == 1,
                          canPaste: state.clipboardPath != null, onNewFolder: _createNewFolder, onCut: () { state.setClipboard(_selectedPaths.first, true); _showToast('Cut to clipboard'); },
                          onCopy: () { state.setClipboard(_selectedPaths.first, false); _showToast('Copied to clipboard'); }, onPaste: _pasteFile, onRename: _renameFile, onDelete: _deleteSelectedFiles, onShare: () { if (_selectedPaths.isNotEmpty) NativeBridge.instance.shareFile(_selectedPaths.first); },
                        ),
                        ExplorerAddressBar(
                          isDark: isDark, isAtHome: _isAtHome, currentPath: _currentDir.path, rootPath: _rootPath, pathHistory: _pathHistory, onGoBack: goBack, onGoHome: _goHome, onNavigate: _loadDirectorySafe,
                        ),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ExplorerSidebar(width: sidebarWidth, isDark: isDark, isAtHome: _isAtHome, rootPath: _rootPath, onGoHome: _goHome, onNavigate: _loadDirectorySafe),
                              Expanded(
                                child: ExplorerContentView(
                                  isDark: isDark, isMobile: screenWidth < 500, isAtHome: _isAtHome, rootPath: _rootPath, files: _files, totalGB: _totalGB, freeGB: _freeGB,
                                  selectedPaths: _selectedPaths, isGridView: _isGridView, isMultiSelectMode: _isMultiSelectMode, onNavigate: _loadDirectorySafe, onOpenFile: NativeBridge.instance.openFile,
                                  onSelectionChanged: (paths) => setState(() => _selectedPaths = paths), onMultiSelectToggled: (multi) => setState(() => _isMultiSelectMode = multi),
                                  onContextMenu: (pos, type, name, _) => setState(() { _contextMenuPos = pos; _contextMenuType = type; _contextTargetName = name; _isContextMenuOpen = true; }),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ExplorerStatusBar(
                          isDark: isDark, isAtHome: _isAtHome, itemCount: _files.length, selectedCount: _selectedPaths.length, sidebarWidthPercent: _sidebarWidthPercent,
                          isGridView: _isGridView, onWidthChanged: (val) => setState(() => _sidebarWidthPercent = val), onViewChanged: (val) => setState(() => _isGridView = val),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildContextMenuOverlay(state),
              ],
            ),
          ),
        ),
      ),
    );
  }
}