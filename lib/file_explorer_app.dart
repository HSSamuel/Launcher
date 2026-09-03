import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'launcher_state.dart';

class FileItem {
  final FileSystemEntity entity;
  final FileStat stat;
  final int itemCount;
  FileItem(this.entity, this.stat, {this.itemCount = 0});
}

class FileExplorerApp extends StatefulWidget {
  const FileExplorerApp({Key? key}) : super(key: key);

  @override
  State<FileExplorerApp> createState() => FileExplorerAppState();
}

class FileExplorerAppState extends State<FileExplorerApp> with WidgetsBindingObserver {
  static const platform = MethodChannel('win_launcher/native');

  bool _hasPermission = false;
  bool _isAtHome = true;
  late Directory _currentDir;
  
  List<FileItem> _files = [];
  List<String> _pathHistory = []; 

  double _totalGB = 228.01;
  double _freeGB = 95.96;

  Set<String> _selectedPaths = {};
  bool _isMultiSelectMode = false;
  
  bool _isContextMenuOpen = false;
  Offset _contextMenuPos = Offset.zero;
  String? _activeSubMenu;
  double _subMenuYOffset = 0;
  
  // FIXED: Declared the missing context menu variables here at the top!
  String _contextMenuType = 'desktop'; 
  String _contextTargetName = '';
  VoidCallback? _contextOpenAction;

  bool _isQuickAccessExpanded = true;
  bool _isThisPCExpanded = true;
  bool _isFoldersExpanded = true;
  bool _isDevicesExpanded = true;

  double _sidebarWidthPercent = 36.0;
  bool _isGridView = false;
  
  bool? _lastThemeDark;

  @override
  void initState() {
    super.initState();
    _currentDir = Directory(context.read<LauncherState>().currentExplorerPath);
    if (_currentDir.path != '/storage/emulated/0') _isAtHome = false;
    
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
    final color = isDark ? '#191919' : '#FFFFFF';
    try {
      platform.invokeMethod('setStatusBarColor', {'color': color, 'darkIcons': !isDark});
    } catch (_) {}
  }

  void _restoreTransparentStatusBar() {
    try {
      platform.invokeMethod('setStatusBarColor', {'color': '#00000000', 'darkIcons': false});
    } catch (_) {}
  }

  Future<void> _fetchStorageStats() async {
    try {
      final Map<dynamic, dynamic>? stats = await platform.invokeMethod('getStorageStats');
      if (stats != null && mounted) {
        setState(() {
          _totalGB = stats['total'] / (1024 * 1024 * 1024);
          _freeGB = stats['free'] / (1024 * 1024 * 1024);
        });
      }
    } catch (_) {}
  }

  Future<void> _checkPermission() async {
    try {
      final Map<dynamic, dynamic>? result = await platform.invokeMethod('getPermissionStatuses');
      if (result != null && mounted) {
        setState(() => _hasPermission = result['storage'] ?? false);
        if (_hasPermission && !_isAtHome) await _loadDirectory(_currentDir);
      }
    } catch (_) {}
  }

  Future<void> _loadDirectorySafe(String path, {bool isBack = false}) async {
    if (!_hasPermission) {
      platform.invokeMethod('openSettings', {'type': 'storage'});
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

  Future<void> _loadDirectory(Directory dir) async {
    try {
      final entities = await dir.list().toList();
      List<FileItem> items = [];
      
      for (var e in entities) {
        final stat = await e.stat();
        int count = 0;
        if (e is Directory) {
          try { count = e.listSync().length; } catch (_) {}
        }
        items.add(FileItem(e, stat, itemCount: count));
      }
      
      items.sort((a, b) {
        if (a.entity is Directory && b.entity is! Directory) return -1;
        if (a.entity is! Directory && b.entity is Directory) return 1;
        return a.entity.path.toLowerCase().compareTo(b.entity.path.toLowerCase());
      });
      
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(fontSize: 13)), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)))
    );
  }

  void _createNewFolder() {
    final isDark = context.read<LauncherState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    TextEditingController controller = TextEditingController(text: 'New Folder');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('New Folder', style: TextStyle(fontSize: 15, color: textColor)),
        content: TextField(
          controller: controller, 
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: 'Folder name', 
            hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white38 : Colors.black38)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
          )
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87))),
          TextButton(
            onPressed: () async {
              try {
                final newDir = Directory('${_currentDir.path}/${controller.text}');
                if (!(await newDir.exists())) await newDir.create();
                await _loadDirectory(_currentDir);
                _showToast('Folder created');
              } catch (_) { _showToast('Permission denied'); }
              if (mounted) Navigator.pop(context);
            }, 
            child: const Text('Create', style: TextStyle(color: Colors.blueAccent))
          ),
        ],
      )
    );
  }

  void _renameFile() {
    if (_selectedPaths.length != 1) return;
    
    final isDark = context.read<LauncherState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    final entityPath = _selectedPaths.first;
    String oldName = entityPath.split('/').last;
    TextEditingController controller = TextEditingController(text: oldName);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Rename', style: TextStyle(fontSize: 15, color: textColor)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white38 : Colors.black38)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
          )
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87))),
          TextButton(
            onPressed: () async {
              try {
                final entity = File(entityPath);
                await entity.rename('${entity.parent.path}/${controller.text}');
                await _loadDirectory(_currentDir);
                _showToast('Renamed to ${controller.text}');
              } catch (_) { _showToast('Error renaming file'); }
              if (mounted) Navigator.pop(context);
            }, 
            child: const Text('Rename', style: TextStyle(color: Colors.blueAccent))
          ),
        ],
      )
    );
  }

  Future<void> _deleteSelectedFiles() async {
    try {
      for (String path in _selectedPaths) {
        final isDir = await FileSystemEntity.isDirectory(path);
        final entity = isDir ? Directory(path) : File(path);
        if (await entity.exists()) {
          await entity.delete(recursive: true);
        }
      }
      await _loadDirectory(_currentDir);
      _showToast('Deleted ${_selectedPaths.length} items');
    } catch (_) { _showToast('Error deleting files'); }
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
          if (state.isCut) { await entity.rename(newPath); } 
          else { await Directory(newPath).create(); }
        }
        
        if (state.isCut) state.clearClipboard();
        await _loadDirectory(_currentDir);
        _showToast('Paste successful');
      } catch (_) { _showToast('Error pasting file'); }
    }
  }

  Future<void> _compressFile(String path, String ext) async {
    try {
      final entity = File(path);
      final name = entity.path.split('/').last;
      final newPath = '${entity.parent.path}/$name$ext';
      await File(newPath).create();
      await _loadDirectory(_currentDir);
      _showToast('Successfully compressed to $name$ext');
    } catch (_) { _showToast('Error creating archive'); }
  }

  void _showPropertiesDialog() async {
    if (_selectedPaths.length != 1) {
       _showSystemPropertiesDialog();
       return;
    }

    try {
      final isDark = context.read<LauncherState>().isDarkMode;
      final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
      final textColor = isDark ? Colors.white : Colors.black87;
      final subTextColor = isDark ? Colors.white70 : Colors.black54;

      final entity = File(_selectedPaths.first);
      final stat = await entity.stat();
      final size = stat.size;
      final modified = stat.modified.toString().split('.')[0];
      final name = entity.path.split('/').last;

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: bgColor,
          title: Text('$name Properties', style: TextStyle(fontSize: 15, color: textColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Location: ${entity.path}', style: TextStyle(fontSize: 12, color: subTextColor)),
              const SizedBox(height: 8),
              Text('Size: ${(size / 1024).toStringAsFixed(2)} KB', style: TextStyle(fontSize: 12, color: subTextColor)),
              const SizedBox(height: 8),
              Text('Modified: $modified', style: TextStyle(fontSize: 12, color: subTextColor)),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Colors.blueAccent)))],
        )
      );
    } catch (_) { _showToast('Could not read properties'); }
  }

  void _showSystemPropertiesDialog() {
    final isDark = context.read<LauncherState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.grey.shade800;
    final targetName = _activeSubMenu ?? 'System App / Shortcut';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Properties', style: TextStyle(fontSize: 15, color: textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: $targetName', style: TextStyle(fontSize: 13, color: subTextColor)),
            const SizedBox(height: 8),
            Text('Location: Desktop', style: TextStyle(fontSize: 13, color: subTextColor)),
            const SizedBox(height: 8),
            Text('Size: ${(12 + targetName.length * 0.5).toStringAsFixed(2)} MB', style: TextStyle(fontSize: 13, color: subTextColor)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Colors.blueAccent)))],
      ),
    );
  }

  void _mockZipCreation(String extension) {
    if (_selectedPaths.isEmpty) return;
    try {
      final name = _selectedPaths.first.split('/').last;
      final newZipPath = '/storage/emulated/0/$name$extension';
      File(newZipPath).createSync();
      _showToast('Successfully compressed to $name$extension');
    } catch (_) {
      _showToast('Storage permission required to compress.');
    }
  }

  String _formatAuthenticDate(FileStat stat) {
    final m = stat.modified;
    final hour = m.hour % 12 == 0 ? 12 : m.hour % 12;
    final ampm = m.hour >= 12 ? 'PM' : 'AM';
    final min = m.minute.toString().padLeft(2, '0');
    return '${m.month.toString().padLeft(2, '0')}/${m.day.toString().padLeft(2, '0')}/${m.year} $hour:$min $ampm';
  }

  String _getSizeOrCount(FileItem item) {
    if (item.entity is Directory) {
      return '${item.itemCount} items';
    } else {
      final sizeKB = item.stat.size / 1024;
      if (sizeKB > 1024) {
        return '${(sizeKB / 1024).toStringAsFixed(2)} MB';
      }
      return '${sizeKB.toStringAsFixed(2)} KB';
    }
  }

  Widget _buildYellowFolder({double size = 48}) {
    return Container(
      width: size, height: size * 0.82,
      decoration: BoxDecoration(color: const Color(0xFFFFC83B), borderRadius: BorderRadius.circular(3), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1))]),
      child: Stack(
        children: [
          Positioned(top: 0, left: 0, child: Container(width: size * 0.42, height: size * 0.22, decoration: const BoxDecoration(color: Color(0xFFE5A91E), borderRadius: BorderRadius.only(topLeft: Radius.circular(3), topRight: Radius.circular(3))))),
          Positioned(top: size * 0.18, left: 0, right: 0, bottom: 0, child: Container(decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFD452), Color(0xFFFFBF24)]), borderRadius: BorderRadius.circular(3)))),
        ],
      ),
    );
  }

  Widget _buildPdfIcon({double size = 46}) {
    return Container(
      width: size, height: size * 1.15,
      decoration: BoxDecoration(color: const Color(0xFFE51A1A), borderRadius: BorderRadius.circular(3), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))]),
      alignment: Alignment.center,
      child: const Text('PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
    );
  }

  Widget _buildFileIcon(String path, {double size = 38}) {
    final ext = path.toLowerCase();
    
    if (ext.endsWith('.png') || ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.webp') || ext.endsWith('.gif')) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300, width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3.5),
          child: Image.file(File(path), width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.image, color: Colors.blueAccent, size: size)),
        ),
      );
    }
    
    if (ext.endsWith('.pdf')) return _buildPdfIcon(size: size);
    if (ext.endsWith('.zip') || ext.endsWith('.7z') || ext.endsWith('.rar')) return Icon(Icons.folder_zip, color: Colors.orangeAccent, size: size);
    if (ext.endsWith('.mp3') || ext.endsWith('.wav') || ext.endsWith('.m4a') || ext.endsWith('.aac') || ext.endsWith('.ogg')) return Icon(Icons.audio_file, color: Colors.amber, size: size);
    if (ext.endsWith('.mp4') || ext.endsWith('.mkv') || ext.endsWith('.avi') || ext.endsWith('.mov')) return Icon(Icons.video_file, color: Colors.purpleAccent, size: size);
    if (ext.endsWith('.doc') || ext.endsWith('.docx') || ext.endsWith('.txt') || ext.endsWith('.csv')) return Icon(Icons.description, color: Colors.blue, size: size);
    if (ext.endsWith('.xls') || ext.endsWith('.xlsx')) return Icon(Icons.table_chart, color: Colors.green, size: size);
    if (ext.endsWith('.ppt') || ext.endsWith('.pptx')) return Icon(Icons.slideshow, color: Colors.deepOrange, size: size);
    if (ext.endsWith('.apk')) return Icon(Icons.android, color: Colors.green, size: size);
    
    return Icon(Icons.insert_drive_file_outlined, color: Colors.blueGrey, size: size);
  }

  Widget _buildTitleBar(BuildContext context, bool isDark) {
    final state = context.read<LauncherState>();
    final bgColor = isDark ? const Color(0xFF191919) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      height: 36, color: bgColor,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Container(width: 14, height: 12, color: Colors.cyan),
          const SizedBox(width: 8),
          Text('This PC', style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w400)),
          const Spacer(),
          InkWell(
            onTap: () { 
              _restoreTransparentStatusBar(); 
              state.minimizeApp('explorer'); 
            }, 
            child: SizedBox(width: 44, height: 36, child: Center(child: Icon(Icons.remove, size: 16, color: textColor)))
          ),
          InkWell(
            onTap: () => state.toggleMaximizeApp('explorer'), 
            child: SizedBox(width: 44, height: 36, child: Center(child: Icon(Icons.crop_square, size: 14, color: textColor)))
          ),
          InkWell(
            onTap: () { 
              _restoreTransparentStatusBar(); 
              state.closeApp('explorer'); 
            }, 
            hoverColor: Colors.red, 
            child: SizedBox(width: 44, height: 36, child: Center(child: Icon(Icons.close, size: 16, color: textColor)))
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(String title, IconData? icon, bool isDark, {bool isActive = false}) {
    final textColor = isDark ? Colors.white : Colors.black87;
    return PopupMenuItem<String>(
      value: title, height: 32, padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(width: 16, child: isActive ? Icon(Icons.circle, size: 5, color: textColor) : null),
          if (icon != null) Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(fontSize: 12, color: textColor))),
          if (title == 'Show') Icon(Icons.chevron_right, size: 16, color: textColor)
        ],
      ),
    );
  }

  Widget _toolBtn(IconData icon, bool isDark, {bool disabled = false, Color? color, VoidCallback? onTap}) {
    final defaultColor = color ?? (isDark ? Colors.white : Colors.black87);
    final disabledColor = isDark ? Colors.white24 : Colors.black26;
    
    return InkWell(
      onTap: disabled ? null : (onTap ?? () {}),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Icon(icon, size: 16, color: disabled ? disabledColor : defaultColor),
      ),
    );
  }

  Widget _menuBtn(IconData icon, bool isDark) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Icon(icon, size: 16, color: isDark ? Colors.white : Colors.black87));
  }

  Widget _divider(bool isDark) => Container(height: 14, width: 1, color: isDark ? Colors.white24 : Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 2));

  Widget _buildToolbar(bool isDark) {
    final state = context.watch<LauncherState>();
    final isSelected = _selectedPaths.isNotEmpty;
    final isSingleSelected = _selectedPaths.length == 1;
    final canPaste = state.clipboardPath != null;
    final activeColor = const Color(0xFF0078D4);
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black87;
    final popupBg = isDark ? const Color(0xFF2B2B2B) : Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor))),
      child: Row(
        children: [
          InkWell(
            onTap: _createNewFolder, borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF0078D4)), const SizedBox(width: 4),
                  Text('New', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w400)), const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down, size: 14, color: isDark ? Colors.white54 : Colors.black54),
                ],
              ),
            ),
          ),
          _divider(isDark),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _toolBtn(Icons.content_cut, isDark, disabled: !isSingleSelected, color: activeColor, onTap: () { state.setClipboard(_selectedPaths.first, true); _showToast('Cut to clipboard'); }),
                  _toolBtn(Icons.content_copy, isDark, disabled: !isSingleSelected, color: activeColor, onTap: () { state.setClipboard(_selectedPaths.first, false); _showToast('Copied to clipboard'); }),
                  _toolBtn(Icons.assignment_outlined, isDark, disabled: !canPaste, color: activeColor, onTap: _pasteFile),
                  _toolBtn(Icons.drive_file_rename_outline, isDark, disabled: !isSingleSelected, color: activeColor, onTap: _renameFile),
                  _toolBtn(Icons.share_outlined, isDark, disabled: !isSingleSelected, color: activeColor, onTap: () => _showToast('Opening Share menu...')),
                  _toolBtn(Icons.delete_outline, isDark, disabled: !isSelected, color: activeColor, onTap: _deleteSelectedFiles),
                  _divider(isDark),
                ],
              ),
            ),
          ),
          _toolBtn(Icons.swap_vert, isDark),
          PopupMenuButton<String>(
            tooltip: '', offset: const Offset(0, 24), color: popupBg, elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            itemBuilder: (context) => [ _buildPopupItem('Extra Large Icons', Icons.crop_square, isDark), _buildPopupItem('Large Icons', Icons.crop_din, isDark), _buildPopupItem('Medium Icons', Icons.crop_7_5, isDark), _buildPopupItem('Small Icons', Icons.grid_view, isDark), _buildPopupItem('List', Icons.format_list_bulleted, isDark, isActive: true), const PopupMenuDivider(), _buildPopupItem('Show', null, isDark) ],
            child: _menuBtn(Icons.web_asset, isDark), 
          ),
          _divider(isDark),
          PopupMenuButton<String>(
            tooltip: '', offset: const Offset(0, 24), color: popupBg, elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            itemBuilder: (context) => [ _buildPopupItem('Pin to Quick Access', Icons.push_pin_outlined, isDark), const PopupMenuDivider(), _buildPopupItem('Select all', Icons.select_all, isDark), _buildPopupItem('Select none', Icons.grid_off_outlined, isDark), _buildPopupItem('Invert selection', Icons.flip_to_back_outlined, isDark), const PopupMenuDivider(), _buildPopupItem('Properties', Icons.description_outlined, isDark) ],
            child: _menuBtn(Icons.more_horiz, isDark), 
          ),
        ],
      ),
    );
  }

  Widget _buildAddressBar(bool isDark) {
    final btnStyle = IconButton.styleFrom(padding: const EdgeInsets.all(2), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap);
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final inputBg = isDark ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    List<Widget> breadcrumbs = [
      Container(width: 12, height: 10, color: Colors.cyan), 
      const SizedBox(width: 4),
      InkWell(
        onTap: _goHome,
        child: Text('This PC', style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600)),
      ), 
      const SizedBox(width: 2),
      Icon(Icons.chevron_right, size: 14, color: textColor),
    ];

    if (!_isAtHome) {
      final folders = _currentDir.path.replaceFirst('/storage/emulated/0', '').split('/').where((e) => e.isNotEmpty).toList();
      String cumulativePath = '/storage/emulated/0';
      
      for (var folder in folders) {
        cumulativePath += '/$folder';
        final targetPath = cumulativePath;
        
        breadcrumbs.add(const SizedBox(width: 2));
        breadcrumbs.add(InkWell(
          onTap: () => _loadDirectorySafe(targetPath),
          child: Text(folder, style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600)),
        ));
        breadcrumbs.add(const SizedBox(width: 2));
        breadcrumbs.add(Icon(Icons.chevron_right, size: 14, color: textColor));
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200))),
      child: Row(
        children: [
          IconButton(icon: Icon(Icons.arrow_back, size: 18, color: textColor), onPressed: _pathHistory.isEmpty ? null : goBack, style: btnStyle), 
          const SizedBox(width: 2),
          IconButton(icon: Icon(Icons.arrow_forward, size: 18, color: isDark ? Colors.white30 : Colors.black38), onPressed: null, style: btnStyle), 
          const SizedBox(width: 4),
          Expanded(
            flex: 7,
            child: Container(
              height: 26, padding: const EdgeInsets.symmetric(horizontal: 4), 
              decoration: BoxDecoration(border: Border.all(color: borderColor), color: inputBg, borderRadius: BorderRadius.circular(2)),
              child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: breadcrumbs)),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 3,
            child: Container(
              height: 26, padding: const EdgeInsets.symmetric(horizontal: 4), 
              decoration: BoxDecoration(border: Border.all(color: borderColor), color: inputBg, borderRadius: BorderRadius.circular(2)),
              child: Row(children: [Icon(Icons.search, size: 12, color: isDark ? Colors.white54 : Colors.black54), const SizedBox(width: 4), Expanded(child: Text('Search...', style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade600), overflow: TextOverflow.ellipsis))]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarAssetItem(String label, String assetName, bool isDark, {VoidCallback? onTap}) {
    final hoverColor = isDark ? Colors.white10 : Colors.lightBlue.withOpacity(0.08);
    final textColor = isDark ? Colors.white70 : Colors.grey.shade700;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap, 
        hoverColor: hoverColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
          child: Row(
            children: [
              const SizedBox(width: 16), 
              Image.asset('assets/icons/$assetName.png', width: 16, height: 16, errorBuilder: (context, error, stackTrace) => const Icon(Icons.folder, size: 16, color: Colors.amber)),
              const SizedBox(width: 8), 
              Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: textColor), overflow: TextOverflow.ellipsis))
            ]
          )
        )
      ),
    );
  }

  Widget _buildSidebarHeader(IconData icon, String label, Color iconColor, bool isDark, {bool isSelected = false, VoidCallback? onTap, bool isExpanded = true, VoidCallback? onToggle}) {
    final textColor = isDark ? Colors.white : Colors.black87;
    return Material(
      color: isSelected ? (isDark ? Colors.white12 : Colors.lightBlue.withOpacity(0.08)) : Colors.transparent,
      child: Row(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: Icon(isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: textColor),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onTap ?? onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: iconColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(String label, IconData icon, Color color, bool isDark, {VoidCallback? onTap}) {
    final textColor = isDark ? Colors.white70 : Colors.grey.shade700;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap, 
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
          child: Row(
            children: [
              const SizedBox(width: 16), 
              Icon(icon, color: color, size: 16), 
              const SizedBox(width: 8), 
              Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: textColor), overflow: TextOverflow.ellipsis))
            ]
          )
        )
      ),
    );
  }

  Widget _buildSidebar(double width, bool isDark) {
    final state = context.watch<LauncherState>();
    final bgColor = isDark ? const Color(0xFF202020) : Colors.white;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade200;

    return Container(
      width: width,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: borderColor)), color: bgColor),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4), 
        physics: const BouncingScrollPhysics(),
        children: [
          _buildSidebarHeader(
            Icons.star, 'Quick access', Colors.orange.shade400, isDark,
            isExpanded: _isQuickAccessExpanded,
            onToggle: () => setState(() => _isQuickAccessExpanded = !_isQuickAccessExpanded),
          ),
          if (_isQuickAccessExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Column(
                children: state.pinnedQuickAccess.map((name) {
                  return _buildSidebarItem(name, Icons.push_pin, isDark ? Colors.white54 : Colors.grey.shade600, isDark, onTap: () => _showToast('Opening $name...'));
                }).toList(),
              ),
            ),
          
          _buildSidebarHeader(
            Icons.folder, 'This PC', Colors.cyan, isDark, isSelected: _isAtHome, onTap: _goHome,
            isExpanded: _isThisPCExpanded,
            onToggle: () => setState(() => _isThisPCExpanded = !_isThisPCExpanded),
          ),
          if (_isThisPCExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Column(
                children: [
                  _buildSidebarAssetItem('Desktop', 'desktop', isDark, onTap: () => _loadDirectorySafe('/storage/emulated/0')),
                  _buildSidebarAssetItem('Documents', 'documents', isDark, onTap: () => _loadDirectorySafe('/storage/emulated/0/Documents')),
                  _buildSidebarAssetItem('Downloads', 'downloads', isDark, onTap: () => _loadDirectorySafe('/storage/emulated/0/Download')),
                  _buildSidebarAssetItem('Music', 'music', isDark, onTap: () => _loadDirectorySafe('/storage/emulated/0/Music')),
                  _buildSidebarAssetItem('Pictures', 'pictures', isDark, onTap: () => _loadDirectorySafe('/storage/emulated/0/Pictures')),
                  _buildSidebarAssetItem('Videos', 'videos', isDark, onTap: () => _loadDirectorySafe('/storage/emulated/0/Movies')),
                  Material(
                    color: Colors.transparent, 
                    child: InkWell(
                      onTap: () => _loadDirectorySafe('/storage/emulated/0'), 
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
                        child: Row(
                          children: [
                            const SizedBox(width: 16), 
                            Image.asset('assets/icons/drive.png', width: 16, height: 16, errorBuilder: (context, error, stackTrace) => const Icon(Icons.storage, size: 16, color: Colors.grey)), 
                            const SizedBox(width: 8), 
                            Expanded(child: Text('Local Disk (C:)', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700), overflow: TextOverflow.ellipsis))
                          ]
                        )
                      )
                    )
                  )
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThisPCHome(bool isMobile, bool isDark) {
    double usedGB = _totalGB - _freeGB;
    double usagePercent = _totalGB > 0 ? usedGB / _totalGB : 0;
    
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.grey.shade700;
    final dividerColor = isDark ? Colors.white12 : Colors.grey.shade200;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      physics: const BouncingScrollPhysics(),
      children: [
        Row(
          children: [
            InkWell(
              onTap: () => setState(() => _isFoldersExpanded = !_isFoldersExpanded),
              child: Icon(_isFoldersExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: textColor),
            ), 
            const SizedBox(width: 4), 
            Text('Folders (6)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: subTextColor)), 
            const SizedBox(width: 12), 
            Expanded(child: Container(height: 1, color: dividerColor))
          ]
        ),
        if (_isFoldersExpanded) ...[
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: isMobile ? 2 : 3, childAspectRatio: 2.8, mainAxisSpacing: 8, crossAxisSpacing: 8,
            children: [
              _buildFolderGridCard('Desktop', '/storage/emulated/0', isDark), 
              _buildFolderGridCard('Documents', '/storage/emulated/0/Documents', isDark),
              _buildFolderGridCard('Downloads', '/storage/emulated/0/Download', isDark), 
              _buildFolderGridCard('Music', '/storage/emulated/0/Music', isDark),
              _buildFolderGridCard('Pictures', '/storage/emulated/0/Pictures', isDark), 
              _buildFolderGridCard('Videos', '/storage/emulated/0/Movies', isDark),
            ],
          ),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            InkWell(
              onTap: () => setState(() => _isDevicesExpanded = !_isDevicesExpanded),
              child: Icon(_isDevicesExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: textColor),
            ), 
            const SizedBox(width: 4), 
            Text('Devices and drives (1)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: subTextColor)), 
            const SizedBox(width: 12), 
            Expanded(child: Container(height: 1, color: dividerColor))
          ]
        ),
        if (_isDevicesExpanded) ...[
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _loadDirectorySafe('/storage/emulated/0'),
              child: SizedBox(
                width: 280,
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.asset('assets/icons/drive.png', width: 42, height: 42, errorBuilder: (context, error, stackTrace) => const Icon(Icons.storage, size: 42, color: Colors.grey)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Local Disk (C:)', style: TextStyle(fontSize: 13, color: isDark ? Colors.white : const Color(0xFF333333))), 
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.zero,
                              child: LinearProgressIndicator(value: usagePercent, backgroundColor: const Color(0xFFC4C4C4), color: const Color(0xFF0078D4), minHeight: 14),
                            ), 
                            const SizedBox(height: 4),
                            Text('${_freeGB.toStringAsFixed(2)} GB free of ${_totalGB.toStringAsFixed(2)} GB', style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _getWin11IconForType(String type, double size) {
    String assetName = type.toLowerCase();
    
    return Image.asset(
      'assets/icons/$assetName.png',
      width: size,
      height: size,
      errorBuilder: (context, error, stackTrace) => Icon(Icons.folder, size: size, color: Colors.amber),
    );
  }

  Widget _buildFolderGridCard(String label, String path, bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _loadDirectorySafe(path),
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: [
            _getWin11IconForType(label, 36), 
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.grey.shade800), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
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
    final hoverColor = isDark ? Colors.white10 : Colors.black.withOpacity(0.05);
    final chevronColor = isDark ? Colors.white54 : Colors.grey.shade600;

    return InkWell(
      onTap: () {
        if (hasSubMenu) { 
          setState(() { 
            _activeSubMenu = subMenuKey; 
            _subMenuYOffset = subMenuY; 
          }); 
        } else { 
          _closeOverlays(); 
          if (onTap != null) onTap(); 
        }
      },
      hoverColor: hoverColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            if (icon != null) Icon(icon, size: 16, color: iconColor ?? defaultIconColor),
            if (icon != null) const SizedBox(width: 12),
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, color: textColor))),
            if (hasSubMenu) Icon(Icons.chevron_right, size: 16, color: chevronColor),
          ],
        ),
      ),
    );
  }

  Widget _buildSubMenuItem(String title, IconData? icon, LauncherState state, {bool isActive = false, bool isChecked = false, bool isDot = false, VoidCallback? onTap}) {
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final iconColor = isDark ? Colors.white : Colors.black87;
    final hoverColor = isDark ? Colors.white10 : Colors.black.withOpacity(0.05);
    bool hasLeading = icon != null || isActive || isDot || isChecked;

    return InkWell(
      onTap: () {
        if (onTap != null) onTap();
        _closeOverlays();
      },
      hoverColor: hoverColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (hasLeading) ...[
              SizedBox(
                width: 16,
                child: isActive || isDot
                    ? Icon(Icons.circle, size: 6, color: iconColor)
                    : (isChecked ? Icon(Icons.check, size: 14, color: iconColor) : null),
              ),
              const SizedBox(width: 8),
              if (icon != null) Icon(icon, size: 16, color: iconColor),
              if (icon != null) const SizedBox(width: 12),
            ],
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, color: textColor))),
          ],
        ),
      ),
    );
  }

  Widget _buildContextDivider(LauncherState state) => Container(
    height: 1,
    color: state.isDarkMode ? Colors.white24 : Colors.grey.shade300,
    margin: const EdgeInsets.symmetric(vertical: 4),
  );

  Widget _buildDesktopContextMenu(LauncherState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildContextMenuItem('View', Icons.grid_view, state, hasSubMenu: true, subMenuKey: 'view', subMenuY: 0),
        _buildContextMenuItem('Sort by', Icons.swap_vert, state, hasSubMenu: true, subMenuKey: 'sort', subMenuY: 36),
        _buildContextMenuItem('Refresh', Icons.refresh, state, onTap: () => _showToast('Desktop refreshed')),
        _buildContextDivider(state),
        _buildContextMenuItem('New', Icons.add_circle_outline, state, onTap: () => _showToast('Create new...')),
        _buildContextDivider(state),
        _buildContextMenuItem('Next desktop background', Icons.wallpaper, state, onTap: () => state.nextWallpaper()),
        _buildContextMenuItem('Display settings', Icons.monitor, state, onTap: () => state.openApp('settings')),
        _buildContextMenuItem('Personalize', Icons.brush_outlined, state, iconColor: const Color(0xFF0078D4), onTap: () => state.openApp('settings')),
      ],
    );
  }

  Widget _buildFolderContextMenu(LauncherState state) {
    if (_selectedPaths.isEmpty) return const SizedBox.shrink();
    final name = _selectedPaths.first.split('/').last;
    final isDir = true; 

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildContextMenuItem(
          'Open', 
          isDir ? Icons.folder : Icons.open_in_new, 
          state,
          iconColor: isDir ? Colors.amber.shade400 : Colors.blueAccent, 
          onTap: () { 
            if (isDir) {
              _loadDirectory(Directory(_selectedPaths.first)); 
            } else {
              platform.invokeMethod('openFile', {'path': _selectedPaths.first});
            }
          }
        ),
        _buildContextMenuItem(
          'Pin to Quick access', 
          Icons.push_pin_outlined, 
          state,
          iconColor: const Color(0xFF0078D4), 
          onTap: () { 
            state.pinToQuickAccess(name); 
            _showToast('Pinned $name to Quick access'); 
          }
        ),
        _buildContextMenuItem(
          'Pin to Start', 
          Icons.push_pin, 
          state,
          iconColor: const Color(0xFF0078D4), 
          onTap: () { 
            state.pinToStart(name); 
            _showToast('Pinned $name to Start'); 
          }
        ),
        _buildContextMenuItem(
          'Compress to...', 
          Icons.folder_zip_outlined, 
          state,
          hasSubMenu: true, 
          subMenuKey: 'compress', 
          subMenuY: 108
        ),
        _buildContextMenuItem(
          'Properties', 
          Icons.build_circle_outlined, 
          state,
          onTap: () => _showPropertiesDialog()
        ),
        _buildContextDivider(state),
        _buildContextMenuItem(
          'Show more options', 
          Icons.layers_outlined, 
          state,
          hasSubMenu: true, 
          subMenuKey: 'more_options', 
          subMenuY: 160
        ),
        _buildContextDivider(state),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomContextAction(Icons.content_cut, 'Cut', state),
              _buildBottomContextAction(Icons.content_copy, 'Copy', state),
              _buildBottomContextAction(Icons.drive_file_rename_outline, 'Rename', state),
              _buildBottomContextAction(Icons.delete_outline, 'Delete', state),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomContextAction(IconData icon, String label, LauncherState state) {
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hoverColor = isDark ? Colors.white10 : Colors.black.withOpacity(0.05);

    return InkWell(
      onTap: () {
        _closeOverlays();
        if (label == 'Cut') {
           state.setClipboard(_selectedPaths.first, true); 
           _showToast('Cut to clipboard'); 
        } else if (label == 'Copy') {
           state.setClipboard(_selectedPaths.first, false); 
           _showToast('Copied to clipboard'); 
        } else if (label == 'Rename') {
           _renameFile(); 
        } else if (label == 'Delete') {
           _deleteSelectedFiles(); 
        }
      },
      hoverColor: hoverColor,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF0078D4)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: textColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildSubMenuContent(LauncherState state) {
    if (_activeSubMenu == 'view') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSubMenuItem('Large icons', Icons.crop_square, state, isActive: state.iconSize == 'Large', onTap: () => state.updateDesktopSetting('iconSize', 'Large')),
          _buildSubMenuItem('Medium icons', Icons.crop_7_5, state, isActive: state.iconSize == 'Medium', onTap: () => state.updateDesktopSetting('iconSize', 'Medium')),
          _buildSubMenuItem('Small icons', Icons.apps, state, isActive: state.iconSize == 'Small', onTap: () => state.updateDesktopSetting('iconSize', 'Small')),
          _buildContextDivider(state),
          _buildSubMenuItem('Auto arrange icons', Icons.bolt, state, isChecked: true, onTap: () => _showToast('Auto arrange toggled')),
          _buildSubMenuItem('Align icons to grid', Icons.grid_4x4, state, isChecked: true, onTap: () => _showToast('Grid alignment toggled')),
          _buildSubMenuItem('Show desktop icons', Icons.desktop_windows, state, isChecked: true, onTap: () => _showToast('Desktop icons toggled')),
        ],
      );
    } else if (_activeSubMenu == 'sort') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSubMenuItem('Name', null, state, isDot: true, onTap: () => _showToast('Sorted by Name')),
          _buildSubMenuItem('Size', null, state, onTap: () => _showToast('Sorted by Size')),
          _buildSubMenuItem('Item type', null, state, onTap: () => _showToast('Sorted by Type')),
          _buildSubMenuItem('Date modified', null, state, onTap: () => _showToast('Sorted by Date')),
        ],
      );
    } else if (_activeSubMenu == 'compress') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildContextMenuItem('ZIP File', null, state, onTap: () => _mockZipCreation('.zip')),
          _buildContextMenuItem('7z File', null, state, onTap: () => _mockZipCreation('.7z')),
        ],
      );
    } else if (_activeSubMenu == 'more_options') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildContextMenuItem('Send to', null, state, hasSubMenu: true, subMenuKey: 'send_to'),
          _buildContextDivider(state),
          _buildContextMenuItem(
            'Cut', 
            null, 
            state,
            onTap: () { 
              state.setClipboard(_selectedPaths.first, true); 
              _showToast('Cut to clipboard'); 
            }
          ),
          _buildContextMenuItem(
            'Copy', 
            null, 
            state,
            onTap: () { 
              state.setClipboard(_selectedPaths.first, false); 
              _showToast('Copied to clipboard'); 
            }
          ),
          _buildContextDivider(state),
          _buildContextMenuItem('Delete', null, state, onTap: () => _deleteSelectedFiles()),
          _buildContextMenuItem('Rename', null, state, onTap: () => _renameFile()),
          _buildContextDivider(state),
          _buildContextMenuItem('Properties', null, state, onTap: () => _showPropertiesDialog()),
        ],
      );
    } else if (_activeSubMenu == 'send_to') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildContextMenuItem('Bluetooth device', Icons.bluetooth, state, onTap: () => _showToast('Searching for devices...')),
          _buildContextMenuItem('Documents', Icons.article_outlined, state, onTap: () => _showToast('Sent to Documents')),
          _buildContextMenuItem('Desktop', Icons.desktop_windows, state, onTap: () => _showToast('Sent to Desktop')),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildContextMenuOverlay(LauncherState state) {
    if (!_isContextMenuOpen) return const SizedBox.shrink();

    final isDark = state.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B).withOpacity(0.95) : const Color(0xFFF3F3F3).withOpacity(0.95);
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;

    double menuWidth = 240; 
    double menuHeight = 320; 
    double dx = _contextMenuPos.dx; 
    double dy = _contextMenuPos.dy;
    final screenSize = MediaQuery.of(context).size;
    
    if (dx + menuWidth > screenSize.width) dx = screenSize.width - menuWidth - 8;
    if (dx < 8) dx = 8;
    if (dy + menuHeight > screenSize.height) dy = screenSize.height - menuHeight - 8;
    if (dy < 8) dy = 8;

    Widget mainMenu = Container(
      width: menuWidth,
      decoration: BoxDecoration(
        color: bgColor, 
        borderRadius: BorderRadius.circular(8), 
        border: Border.all(color: borderColor, width: 1), 
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))]
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _contextMenuType == 'desktop' ? _buildDesktopContextMenu(state) : _buildFolderContextMenu(state),
    );

    Widget? subMenu;
    if (_activeSubMenu != null) {
      double subMenuWidth = 190; 
      double subMenuX = dx + menuWidth - 4; 
      
      if (subMenuX + subMenuWidth > screenSize.width) subMenuX = dx - subMenuWidth + 4;
      if (subMenuX < 8) subMenuX = 8; 
      
      double subMenuY = dy + _subMenuYOffset;
      if (subMenuY + 220 > screenSize.height) subMenuY = screenSize.height - 230; 
      if (subMenuY < 8) subMenuY = 8;

      subMenu = Positioned(
        left: subMenuX, 
        top: subMenuY,
        child: Container(
          width: subMenuWidth,
          decoration: BoxDecoration(
            color: bgColor, 
            borderRadius: BorderRadius.circular(8), 
            border: Border.all(color: borderColor, width: 1), 
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))]
          ),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _buildSubMenuContent(state),
        ),
      );
    }

    return Stack(
      children: [
        Positioned(left: dx, top: dy, child: mainMenu), 
        if (subMenu != null) subMenu
      ]
    );
  }

  Widget _buildRealFileList(bool isDark) {
    if (_files.isEmpty) return const Center(child: Text("Empty Folder", style: TextStyle(color: Colors.grey)));

    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.grey.shade600;
    final hoverColor = isDark ? Colors.white10 : const Color(0xFFE5E5E5);
    final borderColor = isDark ? Colors.white30 : Colors.blueAccent.withOpacity(0.5);

    return GestureDetector(
      onTap: () { 
        setState(() { 
          _selectedPaths.clear();
          _isMultiSelectMode = false;
        }); 
        _closeOverlays(); 
      },
      onSecondaryTapDown: (details) => setState(() { 
        _contextMenuPos = details.globalPosition; 
        _contextMenuType = 'folder';
        _isContextMenuOpen = true; 
      }), 
      onLongPressStart: (details) => setState(() { 
        _contextMenuPos = details.globalPosition; 
        _contextMenuType = 'folder';
        _isContextMenuOpen = true; 
      }),
      child: _isGridView 
        ? GridView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 110,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: _files.length,
            itemBuilder: (context, index) {
              final item = _files[index];
              final isDir = item.entity is Directory;
              final name = item.entity.path.split('/').last;
              
              final isSelected = _selectedPaths.contains(item.entity.path);

              return GestureDetector(
                onSecondaryTapDown: (details) => setState(() { _selectedPaths.add(item.entity.path); _contextMenuPos = details.globalPosition; _contextMenuType = 'folder'; _isContextMenuOpen = true; }), 
                onLongPressStart: (details) => setState(() { _isMultiSelectMode = true; _selectedPaths.add(item.entity.path); _contextMenuPos = details.globalPosition; _contextMenuType = 'folder'; _isContextMenuOpen = true; }),
                onTap: () async {
                  if (_isMultiSelectMode) {
                    setState(() {
                      if (isSelected) {
                        _selectedPaths.remove(item.entity.path);
                        if (_selectedPaths.isEmpty) _isMultiSelectMode = false;
                      } else {
                        _selectedPaths.add(item.entity.path);
                      }
                    });
                  } else {
                    if (isSelected && _selectedPaths.length == 1) { 
                      if (isDir) {
                        await _loadDirectorySafe(item.entity.path); 
                      } else {
                        platform.invokeMethod('openFile', {'path': item.entity.path});
                      }
                    } else { 
                      setState(() { _selectedPaths = {item.entity.path}; });
                    }
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? hoverColor : Colors.transparent, 
                    borderRadius: BorderRadius.circular(4), 
                    border: Border.all(color: isSelected ? borderColor : Colors.transparent, width: 1.0)
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      isDir ? _buildYellowFolder(size: 46) : _buildFileIcon(item.entity.path, size: 46),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Text(
                          name, 
                          style: TextStyle(fontSize: 11, color: textColor), 
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          )
        : ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: _files.length,
            padding: const EdgeInsets.only(top: 8, bottom: 40, left: 8, right: 8),
            itemBuilder: (context, index) {
              final item = _files[index];
              final isDir = item.entity is Directory;
              final name = item.entity.path.split('/').last;
              
              final isSelected = _selectedPaths.contains(item.entity.path);
              
              final timeStr = _formatAuthenticDate(item.stat);
              final sizeStr = _getSizeOrCount(item);

              return GestureDetector(
                onSecondaryTapDown: (details) => setState(() { _selectedPaths.add(item.entity.path); _contextMenuPos = details.globalPosition; _contextMenuType = 'folder'; _isContextMenuOpen = true; }), 
                onLongPressStart: (details) => setState(() { _isMultiSelectMode = true; _selectedPaths.add(item.entity.path); _contextMenuPos = details.globalPosition; _contextMenuType = 'folder'; _isContextMenuOpen = true; }),
                onTap: () async {
                  if (_isMultiSelectMode) {
                    setState(() {
                      if (isSelected) {
                        _selectedPaths.remove(item.entity.path);
                        if (_selectedPaths.isEmpty) _isMultiSelectMode = false;
                      } else {
                        _selectedPaths.add(item.entity.path);
                      }
                    });
                  } else {
                    if (isSelected && _selectedPaths.length == 1) { 
                      if (isDir) {
                        await _loadDirectorySafe(item.entity.path); 
                      } else {
                        platform.invokeMethod('openFile', {'path': item.entity.path});
                      }
                    } else { 
                      setState(() { _selectedPaths = {item.entity.path}; });
                    }
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? hoverColor : Colors.transparent, 
                    borderRadius: BorderRadius.circular(4), 
                    border: Border.all(color: isSelected ? borderColor : Colors.transparent, width: 1.0)
                  ),
                  child: Row(
                    children: [
                      isDir ? _buildYellowFolder(size: 46) : _buildFileIcon(item.entity.path),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text('$timeStr   |   $sizeStr', style: TextStyle(fontSize: 11, color: subTextColor)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }

  void _showWidthAdjustmentDialog(bool isDark) {
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;

    showDialog(
      context: context,
      barrierColor: Colors.transparent, 
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Stack(
              children: [
                Positioned(
                  bottom: 60,
                  right: 10,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 250,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor)
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Select Quick Access width', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor)),
                              InkWell(onTap: () => Navigator.pop(context), child: Icon(Icons.close, size: 16, color: textColor))
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.orange, size: 24),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 4.0,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                  ),
                                  child: Slider(
                                    value: _sidebarWidthPercent,
                                    min: 15,
                                    max: 50,
                                    activeColor: const Color(0xFF0078D4),
                                    inactiveColor: Colors.blue.shade100,
                                    onChanged: (val) {
                                      setDialogState(() => _sidebarWidthPercent = val);
                                      setState(() => _sidebarWidthPercent = val);
                                    }
                                  ),
                                ),
                              ),
                              Text('${_sidebarWidthPercent.toInt()} %', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textColor)),
                            ]
                          )
                        ]
                      )
                    )
                  )
                )
              ]
            );
          }
        );
      }
    );
  }

  Widget _buildBottomStatusBar(bool isDark) {
    final bgColor = isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3);
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final textColor = isDark ? Colors.white70 : Colors.grey.shade700;

    return Container(
      height: 28, 
      padding: const EdgeInsets.symmetric(horizontal: 12), 
      decoration: BoxDecoration(
        color: bgColor, 
        border: Border(top: BorderSide(color: borderColor, width: 0.8))
      ),
      child: Row(
        children: [
          if (_isAtHome) ...[
            Text('7 items', style: TextStyle(fontSize: 11, color: textColor)),
          ] else ...[
            Text(
              '${_files.length} items  |  ${_selectedPaths.isNotEmpty ? '${_selectedPaths.length} items selected  |' : ''}', 
              style: TextStyle(fontSize: 11, color: textColor)
            ), 
            const Spacer(), 
            InkWell(
              onTap: () => _showWidthAdjustmentDialog(isDark),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text('${_sidebarWidthPercent.toInt()} %', style: TextStyle(fontSize: 11, color: textColor)),
              ),
            ),
            const SizedBox(width: 8), 
            InkWell(
              onTap: () => setState(() => _isGridView = false),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Icon(Icons.format_list_bulleted, size: 14, color: !_isGridView ? Colors.blue.shade700 : textColor),
              )
            ), 
            const SizedBox(width: 6), 
            InkWell(
              onTap: () => setState(() => _isGridView = true),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Icon(Icons.grid_view_sharp, size: 14, color: _isGridView ? Colors.blue.shade700 : textColor),
              )
            )
          ]
        ]
      ),
    );
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
        value: SystemUiOverlayStyle(
          statusBarColor: bgColor, 
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark, 
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light
        ),
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.goBack || event.logicalKey == LogicalKeyboardKey.escape)) {
              if (!_isAtHome && _pathHistory.isNotEmpty) {
                goBack();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: () {
              _closeOverlays();
            },
            onSecondaryTapDown: (details) {
               if (_isAtHome) {
                  setState(() {
                    _contextMenuPos = details.globalPosition;
                    _contextMenuType = 'desktop';
                    _isContextMenuOpen = true;
                  });
               }
            },
            onLongPressStart: (details) {
               if (_isAtHome) {
                  setState(() {
                    _contextMenuPos = details.globalPosition;
                    _contextMenuType = 'desktop';
                    _isContextMenuOpen = true;
                  });
               }
            },
            child: Stack(
              children: [
                Container(
                  color: bgColor,
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        _buildTitleBar(context, isDark),
                        _buildToolbar(isDark),
                        _buildAddressBar(isDark),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSidebar(sidebarWidth, isDark),
                              Expanded(child: _isAtHome ? _buildThisPCHome(screenWidth < 500, isDark) : _buildRealFileList(isDark)),
                            ],
                          ),
                        ),
                        _buildBottomStatusBar(isDark),
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