import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'launcher_state.dart';

class Win11FolderIcon extends StatelessWidget {
  final IconData innerIcon;
  final Color backColor;
  final Color frontColor;
  final double size;

  const Win11FolderIcon({
    Key? key, required this.innerIcon, required this.backColor, required this.frontColor, required this.size,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size, 
      height: size * 0.85,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            top: 0, 
            left: 0, 
            child: Container(
              width: size * 0.45, 
              height: size * 0.2, 
              decoration: BoxDecoration(
                color: backColor, 
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(size * 0.08), 
                  topRight: Radius.circular(size * 0.08)
                )
              )
            )
          ),
          Positioned(
            top: size * 0.1, 
            left: 0, 
            right: 0, 
            bottom: 0, 
            child: Container(
              decoration: BoxDecoration(
                color: backColor, 
                borderRadius: BorderRadius.circular(size * 0.08)
              )
            )
          ),
          Positioned(
            top: size * 0.25, 
            left: 0, 
            right: 0, 
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, 
                  end: Alignment.bottomCenter, 
                  colors: [frontColor.withOpacity(0.80), frontColor]
                ),
                borderRadius: BorderRadius.circular(size * 0.08),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
              ),
              child: Center(
                child: Icon(innerIcon, color: Colors.white, size: size * 0.35)
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FileExplorerApp extends StatefulWidget {
  const FileExplorerApp({Key? key}) : super(key: key);

  @override
  State<FileExplorerApp> createState() => _FileExplorerAppState();
}

class _FileExplorerAppState extends State<FileExplorerApp> with WidgetsBindingObserver {
  static const platform = MethodChannel('win_launcher/native');

  bool _hasPermission = false;
  bool _isAtHome = true;
  late Directory _currentDir;
  List<FileSystemEntity> _files = [];

  double _totalGB = 228.01;
  double _freeGB = 99.78;

  String? _selectedPath;
  FileSystemEntity? _selectedEntity;
  
  // Context Menu State
  bool _isContextMenuOpen = false;
  Offset _contextMenuPos = Offset.zero;
  String? _activeSubMenu;
  double _subMenuYOffset = 0;

  @override
  void initState() {
    super.initState();
    _currentDir = Directory(context.read<LauncherState>().currentExplorerPath);
    if (_currentDir.path != '/storage/emulated/0') _isAtHome = false;
    
    WidgetsBinding.instance.addObserver(this);
    _applyWhiteStatusBar();
    _checkPermission();
    _fetchStorageStats();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restoreTransparentStatusBar();
    super.dispose();
  }

  void _applyWhiteStatusBar() {
    try {
      platform.invokeMethod('setStatusBarColor', {'color': '#FFFFFF', 'darkIcons': true});
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.white, 
        statusBarIconBrightness: Brightness.dark, 
        statusBarBrightness: Brightness.light
      ));
    } catch (_) {}
  }

  void _restoreTransparentStatusBar() {
    try {
      platform.invokeMethod('setStatusBarColor', {'color': '#00000000', 'darkIcons': false});
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, 
        statusBarIconBrightness: Brightness.light, 
        statusBarBrightness: Brightness.dark
      ));
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyWhiteStatusBar();
      _checkPermission();
      _fetchStorageStats();
    }
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
        if (_hasPermission && !_isAtHome) _loadDirectory(_currentDir);
      }
    } catch (_) {}
  }

  void _loadDirectorySafe(String path) {
    if (!_hasPermission) {
      platform.invokeMethod('openSettings', {'type': 'storage'});
      return;
    }
    final dir = Directory(path);
    if (!dir.existsSync()) {
      try { dir.createSync(recursive: true); } catch (_) {}
    }
    _loadDirectory(dir);
  }

  void _loadDirectory(Directory dir) {
    try {
      final entities = dir.listSync().toList();
      entities.sort((a, b) {
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
      if (mounted) {
        setState(() {
          _isAtHome = false;
          _currentDir = dir;
          _files = entities;
          _selectedPath = null;
          _selectedEntity = null;
          _isContextMenuOpen = false;
        });
      }
    } catch (e) {
      debugPrint("Error reading directory: $e");
    }
  }

  void _goHome() {
    setState(() {
      _isAtHome = true;
      _selectedPath = null;
      _selectedEntity = null;
      _isContextMenuOpen = false;
    });
  }
  
  void _showToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)), 
        duration: const Duration(seconds: 1), 
        behavior: SnackBarBehavior.floating, 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))
      )
    );
  }

  // --- REAL FILE OPERATIONS ---

  void _createNewFolder() {
    TextEditingController controller = TextEditingController(text: 'New Folder');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder', style: TextStyle(fontSize: 15)),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Folder name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              try {
                final newDir = Directory('${_currentDir.path}/${controller.text}');
                if (!newDir.existsSync()) newDir.createSync();
                _loadDirectory(_currentDir);
                _showToast('Folder created');
              } catch (_) { 
                _showToast('Permission denied'); 
              }
              Navigator.pop(context);
            }, 
            child: const Text('Create')
          ),
        ],
      )
    );
  }

  void _renameFile(FileSystemEntity entity) {
    String oldName = entity.path.split('/').last;
    TextEditingController controller = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename', style: TextStyle(fontSize: 15)),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              try {
                entity.renameSync('${entity.parent.path}/${controller.text}');
                _loadDirectory(_currentDir);
                _showToast('Renamed to ${controller.text}');
              } catch (_) { 
                _showToast('Error renaming file'); 
              }
              Navigator.pop(context);
            }, 
            child: const Text('Rename')
          ),
        ],
      )
    );
  }

  void _deleteFile(FileSystemEntity entity) {
    try {
      if (entity.existsSync()) {
        entity.deleteSync(recursive: true);
        _loadDirectory(_currentDir);
        _showToast('File deleted');
      }
    } catch (_) { 
      _showToast('Error deleting file'); 
    }
  }

  void _pasteFile() {
    final state = context.read<LauncherState>();
    if (state.clipboardPath != null) {
      try {
        final entity = FileSystemEntity.isDirectorySync(state.clipboardPath!) 
            ? Directory(state.clipboardPath!) 
            : File(state.clipboardPath!);
            
        final name = state.clipboardPath!.split('/').last;
        final newPath = '${_currentDir.path}/$name';
        
        if (entity is File) {
          entity.copySync(newPath);
          if (state.isCut) entity.deleteSync();
        } else if (entity is Directory) {
          if (state.isCut) { 
            entity.renameSync(newPath); 
          } else { 
            Directory(newPath).createSync(); 
          }
        }
        
        if (state.isCut) state.clearClipboard();
        _loadDirectory(_currentDir);
        _showToast('Paste successful');
      } catch (_) { 
        _showToast('Error pasting file'); 
      }
    }
  }

  void _compressFile(FileSystemEntity entity, String ext) {
    try {
      final name = entity.path.split('/').last;
      final newPath = '${entity.parent.path}/$name$ext';
      File(newPath).createSync();
      _loadDirectory(_currentDir);
      _showToast('Successfully compressed to $name$ext');
    } catch (_) { 
      _showToast('Error creating archive'); 
    }
  }

  void _showPropertiesDialog(FileSystemEntity entity) {
    try {
      final stat = entity.statSync();
      final size = stat.size;
      final modified = stat.modified.toString().split('.')[0];
      final name = entity.path.split('/').last;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('$name Properties', style: const TextStyle(fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Location: ${entity.path}', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Text('Size: ${(size / 1024).toStringAsFixed(2)} KB', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Text('Modified: $modified', style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('OK')
            )
          ],
        )
      );
    } catch (_) { 
      _showToast('Could not read properties'); 
    }
  }

  String _formatTimestamp(FileSystemEntity entity) {
    try {
      final stat = entity.statSync();
      final diff = DateTime.now().difference(stat.modified);
      if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()} year ago';
      if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()} month ago';
      if (diff.inDays > 0) return '${diff.inDays} days ago';
      return 'Today';
    } catch (_) {
      return '1 year ago';
    }
  }

  Widget _buildYellowFolder({double size = 48}) {
    return Container(
      width: size, 
      height: size * 0.82,
      decoration: BoxDecoration(
        color: const Color(0xFFFFC83B), 
        borderRadius: BorderRadius.circular(3), 
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1))]
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0, 
            left: 0, 
            child: Container(
              width: size * 0.42, 
              height: size * 0.22, 
              decoration: const BoxDecoration(
                color: Color(0xFFE5A91E), 
                borderRadius: BorderRadius.only(topLeft: Radius.circular(3), topRight: Radius.circular(3))
              )
            )
          ),
          Positioned(
            top: size * 0.18, 
            left: 0, 
            right: 0, 
            bottom: 0, 
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter, 
                  end: Alignment.bottomCenter, 
                  colors: [Color(0xFFFFD452), Color(0xFFFFBF24)]
                ), 
                borderRadius: BorderRadius.circular(3)
              )
            )
          ),
        ],
      ),
    );
  }

  Widget _buildPdfIcon({double size = 46}) {
    return Container(
      width: size, 
      height: size * 1.15,
      decoration: BoxDecoration(
        color: const Color(0xFFE51A1A), 
        borderRadius: BorderRadius.circular(3), 
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))]
      ),
      alignment: Alignment.center,
      child: const Text('PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
    );
  }

  Widget _buildFileIcon(String path) {
    if (path.toLowerCase().endsWith('.pdf')) return _buildPdfIcon(size: 44);
    if (path.toLowerCase().endsWith('.zip') || path.toLowerCase().endsWith('.7z')) return const Icon(Icons.folder_zip, color: Colors.blueGrey, size: 38);
    return const Icon(Icons.insert_drive_file_outlined, color: Colors.blueGrey, size: 38);
  }

  Widget _buildTitleBar(BuildContext context) {
    final state = context.read<LauncherState>();
    return Container(
      height: 36, 
      color: Colors.white,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Container(width: 14, height: 12, color: Colors.cyan),
          const SizedBox(width: 8),
          const Text('This PC', style: TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w400)),
          const Spacer(),
          InkWell(
            onTap: () { 
              _restoreTransparentStatusBar(); 
              state.minimizeApp('explorer'); 
            }, 
            child: const SizedBox(width: 44, height: 36, child: Center(child: Icon(Icons.remove, size: 16, color: Colors.black87)))
          ),
          InkWell(
            onTap: () => state.toggleMaximizeApp('explorer'), 
            child: const SizedBox(width: 44, height: 36, child: Center(child: Icon(Icons.crop_square, size: 14, color: Colors.black87)))
          ),
          InkWell(
            onTap: () { 
              _restoreTransparentStatusBar(); 
              state.closeApp('explorer'); 
            }, 
            hoverColor: Colors.red, 
            child: const SizedBox(width: 44, height: 36, child: Center(child: Icon(Icons.close, size: 16, color: Colors.black87)))
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(String title, IconData? icon, {bool isActive = false}) {
    return PopupMenuItem<String>(
      value: title, 
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: 16, 
            child: isActive ? const Icon(Icons.circle, size: 5, color: Colors.black87) : null
          ),
          if (icon != null) Icon(icon, size: 16, color: Colors.black87),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12, color: Colors.black87))),
          if (title == 'Show') const Icon(Icons.chevron_right, size: 16, color: Colors.black87)
        ],
      ),
    );
  }

  Widget _toolBtn(IconData icon, {bool disabled = false, Color? color, VoidCallback? onTap}) {
    return InkWell(
      onTap: disabled ? null : (onTap ?? () {}),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Icon(icon, size: 16, color: disabled ? Colors.black26 : (color ?? Colors.black87)),
      ),
    );
  }

  Widget _menuBtn(IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), 
      child: Icon(icon, size: 16, color: Colors.black87)
    );
  }

  Widget _divider() => Container(
    height: 14, 
    width: 1, 
    color: Colors.grey.shade300, 
    margin: const EdgeInsets.symmetric(horizontal: 2)
  );

  Widget _buildToolbar() {
    final state = context.watch<LauncherState>();
    final isSelected = _selectedEntity != null;
    final canPaste = state.clipboardPath != null;
    final activeColor = const Color(0xFF0078D4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        children: [
          InkWell(
            onTap: _createNewFolder,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF0078D4)),
                  SizedBox(width: 4),
                  Text('New', style: TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w400)),
                  SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.black54),
                ],
              ),
            ),
          ),
          _divider(),
          
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _toolBtn(
                    Icons.content_cut, 
                    disabled: !isSelected, 
                    color: activeColor, 
                    onTap: () { 
                      state.setClipboard(_selectedEntity!.path, true); 
                      _showToast('Cut to clipboard'); 
                    }
                  ),
                  _toolBtn(
                    Icons.content_copy, 
                    disabled: !isSelected, 
                    color: activeColor, 
                    onTap: () { 
                      state.setClipboard(_selectedEntity!.path, false); 
                      _showToast('Copied to clipboard'); 
                    }
                  ),
                  _toolBtn(
                    Icons.assignment_outlined, 
                    disabled: !canPaste, 
                    color: activeColor, 
                    onTap: _pasteFile
                  ),
                  _toolBtn(
                    Icons.drive_file_rename_outline, 
                    disabled: !isSelected, 
                    color: activeColor, 
                    onTap: () => _renameFile(_selectedEntity!)
                  ),
                  _toolBtn(
                    Icons.share_outlined, 
                    disabled: !isSelected, 
                    color: activeColor, 
                    onTap: () => _showToast('Opening Share menu...')
                  ),
                  _toolBtn(
                    Icons.delete_outline, 
                    disabled: !isSelected, 
                    color: activeColor, 
                    onTap: () => _deleteFile(_selectedEntity!)
                  ),
                  _divider(),
                ],
              ),
            ),
          ),
          
          _toolBtn(Icons.swap_vert),
          PopupMenuButton<String>(
            tooltip: '', 
            offset: const Offset(0, 24), 
            color: Colors.white, 
            elevation: 4, 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            itemBuilder: (context) => [ 
              _buildPopupItem('Extra Large Icons', Icons.crop_square), 
              _buildPopupItem('Large Icons', Icons.crop_din), 
              _buildPopupItem('Medium Icons', Icons.crop_7_5), 
              _buildPopupItem('Small Icons', Icons.grid_view), 
              _buildPopupItem('List', Icons.format_list_bulleted, isActive: true), 
              const PopupMenuDivider(), 
              _buildPopupItem('Show', null), 
            ],
            child: _menuBtn(Icons.web_asset), 
          ),
          _divider(),
          PopupMenuButton<String>(
            tooltip: '', 
            offset: const Offset(0, 24), 
            color: Colors.white, 
            elevation: 4, 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            itemBuilder: (context) => [ 
              _buildPopupItem('Pin to Quick Access', Icons.push_pin_outlined), 
              const PopupMenuDivider(), 
              _buildPopupItem('Select all', Icons.select_all), 
              _buildPopupItem('Select none', Icons.grid_off_outlined), 
              _buildPopupItem('Invert selection', Icons.flip_to_back_outlined), 
              const PopupMenuDivider(), 
              _buildPopupItem('Properties', Icons.description_outlined), 
            ],
            child: _menuBtn(Icons.more_horiz), 
          ),
        ],
      ),
    );
  }

  Widget _buildAddressBar() {
    final btnStyle = IconButton.styleFrom(
      padding: const EdgeInsets.all(2), 
      minimumSize: Size.zero, 
      tapTargetSize: MaterialTapTargetSize.shrinkWrap
    );
    
    List<Widget> breadcrumbs = [
      Container(width: 12, height: 10, color: Colors.cyan), 
      const SizedBox(width: 4),
      const Text('This PC', style: TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600)), 
      const SizedBox(width: 2),
      const Icon(Icons.chevron_right, size: 14, color: Colors.black87),
    ];

    if (!_isAtHome) {
      final folders = _currentDir.path.replaceFirst('/storage/emulated/0', '').split('/').where((e) => e.isNotEmpty).toList();
      for (var folder in folders) {
        breadcrumbs.add(const SizedBox(width: 2));
        breadcrumbs.add(Text(folder, style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600)));
        breadcrumbs.add(const SizedBox(width: 2));
        breadcrumbs.add(const Icon(Icons.chevron_right, size: 14, color: Colors.black87));
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back, size: 18, color: Colors.black87), onPressed: _isAtHome ? null : _goHome, style: btnStyle), 
          const SizedBox(width: 2),
          IconButton(icon: const Icon(Icons.arrow_forward, size: 18, color: Colors.black38), onPressed: null, style: btnStyle), 
          const SizedBox(width: 4),
          Expanded(
            flex: 7,
            child: Container(
              height: 26, 
              padding: const EdgeInsets.symmetric(horizontal: 4), 
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300), 
                color: Colors.white, 
                borderRadius: BorderRadius.circular(2)
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal, 
                child: Row(children: breadcrumbs)
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 3,
            child: Container(
              height: 26, 
              padding: const EdgeInsets.symmetric(horizontal: 4), 
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300), 
                color: Colors.white, 
                borderRadius: BorderRadius.circular(2)
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 12, color: Colors.black54), 
                  const SizedBox(width: 4), 
                  Expanded(
                    child: Text('Search...', style: TextStyle(fontSize: 11, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)
                  )
                ]
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(double width) {
    final state = context.watch<LauncherState>();
    return Container(
      width: width,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade200)), color: Colors.white),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4), 
        physics: const BouncingScrollPhysics(),
        children: [
          _buildSidebarHeader(Icons.star, 'Quick access', Colors.orange.shade400),
          Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: Column(
              children: state.pinnedQuickAccess.map((name) {
                return _buildSidebarItem(name, Icons.push_pin, Colors.grey.shade600, onTap: () => _showToast('Opening $name...'));
              }).toList(),
            ),
          ),
          _buildSidebarHeader(Icons.folder, 'This PC', Colors.cyan, isSelected: _isAtHome, onTap: _goHome),
          Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: Column(
              children: [
                _buildSidebarItem('Desktop', Icons.desktop_windows, Colors.blue, onTap: () => _loadDirectorySafe('/storage/emulated/0')),
                _buildSidebarItem('Documents', Icons.article_outlined, Colors.blueGrey, onTap: () => _loadDirectorySafe('/storage/emulated/0/Documents')),
                _buildSidebarItem('Downloads', Icons.arrow_downward, Colors.teal, onTap: () => _loadDirectorySafe('/storage/emulated/0/Download')),
                _buildSidebarItem('Music', Icons.music_note, Colors.orange, onTap: () => _loadDirectorySafe('/storage/emulated/0/Music')),
                _buildSidebarItem('Pictures', Icons.image_outlined, Colors.blue, onTap: () => _loadDirectorySafe('/storage/emulated/0/Pictures')),
                _buildSidebarItem('Videos', Icons.play_circle_outline, Colors.purple, onTap: () => _loadDirectorySafe('/storage/emulated/0/Movies')),
                Material(
                  color: Colors.transparent, 
                  child: InkWell(
                    onTap: () => _loadDirectorySafe('/storage/emulated/0'), 
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
                      child: Row(
                        children: [
                          const SizedBox(width: 16), 
                          const Icon(Icons.storage, color: Colors.grey, size: 16), 
                          const SizedBox(width: 8), 
                          Expanded(
                            child: Text(
                              'Local Disk (C:)', 
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700), 
                              overflow: TextOverflow.ellipsis
                            )
                          )
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

  Widget _buildSidebarHeader(IconData icon, String label, Color iconColor, {bool isSelected = false, VoidCallback? onTap}) {
    return Material(
      color: isSelected ? Colors.lightBlue.withOpacity(0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap, 
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
          child: Row(
            children: [
              const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.black87), 
              const SizedBox(width: 4), 
              Icon(icon, size: 16, color: iconColor), 
              const SizedBox(width: 6), 
              Expanded(
                child: Text(
                  label, 
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87), 
                  overflow: TextOverflow.ellipsis
                )
              )
            ]
          )
        )
      ),
    );
  }

  Widget _buildSidebarItem(String label, IconData icon, Color color, {VoidCallback? onTap}) {
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
              Expanded(
                child: Text(
                  label, 
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700), 
                  overflow: TextOverflow.ellipsis
                )
              )
            ]
          )
        )
      ),
    );
  }

  Widget _buildThisPCHome(bool isMobile) {
    double usedGB = _totalGB - _freeGB;
    double usagePercent = _totalGB > 0 ? usedGB / _totalGB : 0;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      physics: const BouncingScrollPhysics(),
      children: [
        Row(
          children: [
            const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.black87), 
            const SizedBox(width: 4), 
            Text('Folders (6)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)), 
            const SizedBox(width: 12), 
            Expanded(child: Container(height: 1, color: Colors.grey.shade200))
          ]
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true, 
          physics: const NeverScrollableScrollPhysics(), 
          crossAxisCount: isMobile ? 2 : 3, 
          childAspectRatio: 2.8, 
          mainAxisSpacing: 8, 
          crossAxisSpacing: 8,
          children: [
            _buildFolderGridCard('Desktop', '/storage/emulated/0'), 
            _buildFolderGridCard('Documents', '/storage/emulated/0/Documents'),
            _buildFolderGridCard('Downloads', '/storage/emulated/0/Download'), 
            _buildFolderGridCard('Music', '/storage/emulated/0/Music'),
            _buildFolderGridCard('Pictures', '/storage/emulated/0/Pictures'), 
            _buildFolderGridCard('Videos', '/storage/emulated/0/Movies'),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.black87), 
            const SizedBox(width: 4), 
            Text('Devices and drives (1)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)), 
            const SizedBox(width: 12), 
            Expanded(child: Container(height: 1, color: Colors.grey.shade200))
          ]
        ),
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
                    Container(
                      width: 36, 
                      height: 26, 
                      decoration: BoxDecoration(
                        color: const Color(0xFFD6D6D6), 
                        borderRadius: BorderRadius.circular(4), 
                        border: Border.all(color: Colors.grey.shade400, width: 0.5)
                      ), 
                      child: Row(
                        children: [
                          Container(
                            width: 9, 
                            decoration: const BoxDecoration(
                              color: Color(0xFF4A4A4A), 
                              borderRadius: BorderRadius.horizontal(left: Radius.circular(3))
                            )
                          ), 
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 3, bottom: 3), 
                              child: Align(
                                alignment: Alignment.bottomLeft, 
                                child: Container(
                                  width: 4, 
                                  height: 4, 
                                  decoration: const BoxDecoration(
                                    color: Colors.greenAccent, 
                                    shape: BoxShape.circle
                                  )
                                )
                              )
                            )
                          )
                        ]
                      )
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Local Disk (C:)', style: TextStyle(fontSize: 12, color: Colors.black87)), 
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: usagePercent, 
                            backgroundColor: Colors.grey.shade300, 
                            color: Colors.blueAccent.shade700, 
                            minHeight: 12
                          ), 
                          const SizedBox(height: 4),
                          Text('${_freeGB.toStringAsFixed(2)} GB free of ${_totalGB.toStringAsFixed(2)} GB', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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
    );
  }

  Widget _buildFolderGridCard(String label, String path) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _loadDirectorySafe(path),
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: [
            _getWin11IconForType(label, 36), 
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade800), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  String _matchAndroidFolderToWin11(String folderName) {
    final lower = folderName.toLowerCase();
    if (lower == 'download' || lower == 'downloads') return 'Downloads';
    if (lower == 'documents' || lower == 'document') return 'Documents';
    if (lower == 'music' || lower == 'audio') return 'Music';
    if (lower == 'pictures' || lower == 'dcim' || lower == 'images') return 'Pictures';
    if (lower == 'movies' || lower == 'video' || lower == 'videos') return 'Videos';
    if (lower == 'desktop') return 'Desktop';
    return 'Folder'; 
  }

  Widget _getWin11IconForType(String type, double size) {
    switch (type) {
      case 'Desktop': return Win11FolderIcon(innerIcon: Icons.desktop_windows, backColor: Colors.lightBlue.shade300, frontColor: Colors.blue.shade600, size: size);
      case 'Documents': return Win11FolderIcon(innerIcon: Icons.article_outlined, backColor: Colors.blueGrey.shade200, frontColor: Colors.blueGrey.shade400, size: size);
      case 'Downloads': return Win11FolderIcon(innerIcon: Icons.arrow_downward, backColor: Colors.teal.shade300, frontColor: Colors.teal.shade600, size: size);
      case 'Music': return Win11FolderIcon(innerIcon: Icons.music_note, backColor: Colors.orange.shade300, frontColor: Colors.purple.shade400, size: size);
      case 'Pictures': return Win11FolderIcon(innerIcon: Icons.image_outlined, backColor: Colors.lightBlue.shade200, frontColor: Colors.blue.shade500, size: size);
      case 'Videos': return Win11FolderIcon(innerIcon: Icons.play_circle_outline, backColor: Colors.purple.shade300, frontColor: Colors.deepPurple.shade600, size: size);
      default: return Win11FolderIcon(innerIcon: Icons.folder, backColor: Colors.amber.shade200, frontColor: Colors.amber.shade500, size: size);
    }
  }

  // --- FILE BROWSER CONTEXT MENUS ---
  void _closeOverlays() {
    setState(() {
      _isContextMenuOpen = false;
      _activeSubMenu = null;
    });
  }

  Widget _buildContextMenuItem(String title, IconData? icon, {Color? iconColor, bool hasSubMenu = false, String? subMenuKey, double subMenuY = 0, VoidCallback? onTap}) {
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
      hoverColor: Colors.black.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            if (icon != null) Icon(icon, size: 16, color: iconColor ?? Colors.black87),
            if (icon != null) const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 13, color: Colors.black87))),
            if (hasSubMenu) Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderContextMenu(LauncherState state) {
    if (_selectedEntity == null) return const SizedBox.shrink();
    final name = _selectedEntity!.path.split('/').last;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildContextMenuItem(
          'Open', 
          Icons.folder, 
          iconColor: Colors.amber.shade400, 
          onTap: () { 
            if (_selectedEntity is Directory) _loadDirectory(_selectedEntity as Directory); 
          }
        ),
        _buildContextMenuItem(
          'Pin to Quick access', 
          Icons.push_pin_outlined, 
          iconColor: const Color(0xFF0078D4), 
          onTap: () { 
            state.pinToQuickAccess(name); 
            _showToast('Pinned $name to Quick access'); 
          }
        ),
        _buildContextMenuItem(
          'Pin to Start', 
          Icons.push_pin, 
          iconColor: const Color(0xFF0078D4), 
          onTap: () { 
            state.pinToStart(name); 
            _showToast('Pinned $name to Start'); 
          }
        ),
        _buildContextMenuItem(
          'Compress to...', 
          Icons.folder_zip_outlined, 
          hasSubMenu: true, 
          subMenuKey: 'compress', 
          subMenuY: 108
        ),
        _buildContextMenuItem(
          'Properties', 
          Icons.build_circle_outlined, 
          onTap: () => _showPropertiesDialog(_selectedEntity!)
        ),
        Container(height: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(vertical: 4)),
        _buildContextMenuItem(
          'Show more options', 
          Icons.layers_outlined, 
          hasSubMenu: true, 
          subMenuKey: 'more_options', 
          subMenuY: 160
        ),
        Container(height: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(vertical: 4)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              InkWell(
                onTap: (){ 
                  _closeOverlays(); 
                  state.setClipboard(_selectedEntity!.path, true); 
                  _showToast('Cut to clipboard'); 
                }, 
                child: const Padding(padding: EdgeInsets.all(8.0), child: Icon(Icons.content_cut, size: 18, color: Color(0xFF0078D4)))
              ),
              InkWell(
                onTap: (){ 
                  _closeOverlays(); 
                  state.setClipboard(_selectedEntity!.path, false); 
                  _showToast('Copied to clipboard'); 
                }, 
                child: const Padding(padding: EdgeInsets.all(8.0), child: Icon(Icons.content_copy, size: 18, color: Color(0xFF0078D4)))
              ),
              InkWell(
                onTap: (){ 
                  _closeOverlays(); 
                  _renameFile(_selectedEntity!); 
                }, 
                child: const Padding(padding: EdgeInsets.all(8.0), child: Icon(Icons.drive_file_rename_outline, size: 18, color: Color(0xFF0078D4)))
              ),
              InkWell(
                onTap: (){ 
                  _closeOverlays(); 
                  _deleteFile(_selectedEntity!); 
                }, 
                child: const Padding(padding: EdgeInsets.all(8.0), child: Icon(Icons.delete_outline, size: 18, color: Color(0xFF0078D4)))
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubMenuContent(LauncherState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_activeSubMenu == 'compress') ...[
          _buildContextMenuItem('ZIP File', null, onTap: () => _compressFile(_selectedEntity!, '.zip')),
          _buildContextMenuItem('7z File', null, onTap: () => _compressFile(_selectedEntity!, '.7z')),
        ],
        if (_activeSubMenu == 'more_options') ...[
          _buildContextMenuItem('Send to', null, hasSubMenu: true, subMenuKey: 'send_to'),
          Container(height: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(vertical: 4)),
          _buildContextMenuItem(
            'Cut', 
            null, 
            onTap: () { 
              state.setClipboard(_selectedEntity!.path, true); 
              _showToast('Cut to clipboard'); 
            }
          ),
          _buildContextMenuItem(
            'Copy', 
            null, 
            onTap: () { 
              state.setClipboard(_selectedEntity!.path, false); 
              _showToast('Copied to clipboard'); 
            }
          ),
          Container(height: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(vertical: 4)),
          _buildContextMenuItem('Delete', null, onTap: () => _deleteFile(_selectedEntity!)),
          _buildContextMenuItem('Rename', null, onTap: () => _renameFile(_selectedEntity!)),
          Container(height: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(vertical: 4)),
          _buildContextMenuItem('Properties', null, onTap: () => _showPropertiesDialog(_selectedEntity!)),
        ],
        if (_activeSubMenu == 'send_to') ...[
          _buildContextMenuItem('Bluetooth device', Icons.bluetooth, onTap: () => _showToast('Searching for devices...')),
          _buildContextMenuItem('Documents', Icons.article_outlined, onTap: () => _showToast('Sent to Documents')),
          _buildContextMenuItem('Desktop', Icons.desktop_windows, onTap: () => _showToast('Sent to Desktop')),
        ],
      ],
    );
  }

  Widget _buildContextMenuOverlay(LauncherState state) {
    if (!_isContextMenuOpen) return const SizedBox.shrink();

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
        color: const Color(0xFFF3F3F3).withOpacity(0.95), 
        borderRadius: BorderRadius.circular(8), 
        border: Border.all(color: Colors.grey.shade300, width: 1), 
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))]
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _buildFolderContextMenu(state),
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
            color: const Color(0xFFF3F3F3).withOpacity(0.95), 
            borderRadius: BorderRadius.circular(8), 
            border: Border.all(color: Colors.grey.shade300, width: 1), 
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

  Widget _buildRealFileList() {
    if (_files.isEmpty) return const Center(child: Text("Empty Folder", style: TextStyle(color: Colors.grey)));

    return GestureDetector(
      onTap: () { 
        setState(() { 
          _selectedPath = null; 
          _selectedEntity = null; 
        }); 
        _closeOverlays(); 
      },
      onSecondaryTapDown: (details) => setState(() { 
        _contextMenuPos = details.globalPosition; 
        _isContextMenuOpen = true; 
      }), 
      onLongPressStart: (details) => setState(() { 
        _contextMenuPos = details.globalPosition; 
        _isContextMenuOpen = true; 
      }),
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: _files.length,
        padding: const EdgeInsets.only(top: 8, bottom: 40, left: 8, right: 8),
        itemBuilder: (context, index) {
          final item = _files[index];
          final isDir = item is Directory;
          final name = item.path.split('/').last;
          final isSelected = _selectedPath == item.path;
          final timeStr = _formatTimestamp(item);

          return GestureDetector(
            onSecondaryTapDown: (details) => setState(() { 
              _selectedPath = item.path; 
              _selectedEntity = item; 
              _contextMenuPos = details.globalPosition; 
              _isContextMenuOpen = true; 
            }), 
            onLongPressStart: (details) => setState(() { 
              _selectedPath = item.path; 
              _selectedEntity = item; 
              _contextMenuPos = details.globalPosition; 
              _isContextMenuOpen = true; 
            }),
            onTap: () {
              setState(() {
                if (_selectedPath == item.path) { 
                  if (isDir) _loadDirectory(item as Directory); 
                } else { 
                  _selectedPath = item.path; 
                  _selectedEntity = item; 
                }
              });
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFE5E5E5) : Colors.transparent, 
                borderRadius: BorderRadius.circular(4), 
                border: isSelected 
                    ? Border.all(color: Colors.grey.shade400, width: 0.6) 
                    : Border.all(color: Colors.transparent, width: 0.6)
              ),
              child: Row(
                children: [
                  isDir ? _buildYellowFolder(size: 46) : _buildFileIcon(item.path),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name, 
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87), 
                          overflow: TextOverflow.ellipsis
                        ),
                        const SizedBox(height: 4),
                        Text(timeStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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

  Widget _buildBottomStatusBar() {
    return Container(
      height: 28, 
      padding: const EdgeInsets.symmetric(horizontal: 12), 
      decoration: BoxDecoration(
        color: Colors.white, 
        border: Border(top: BorderSide(color: Colors.grey.shade300, width: 0.8))
      ),
      child: Row(
        children: [
          Text(
            '${_files.length} items  |  ${_selectedPath != null ? '1 item selected  |' : ''}', 
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700)
          ), 
          const Spacer(), 
          Text('34 %', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)), 
          const SizedBox(width: 8), 
          Icon(Icons.format_list_bulleted, size: 14, color: Colors.grey.shade700), 
          const SizedBox(width: 6), 
          Icon(Icons.grid_view_sharp, size: 14, color: Colors.blue.shade700)
        ]
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 500;
    final sidebarWidth = isMobile ? 140.0 : 180.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.white, 
          statusBarIconBrightness: Brightness.dark, 
          statusBarBrightness: Brightness.light
        ),
        child: GestureDetector(
          onTap: _closeOverlays,
          child: Stack(
            children: [
              Container(
                color: Colors.white,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      _buildTitleBar(context),
                      _buildToolbar(),
                      _buildAddressBar(),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSidebar(sidebarWidth),
                            Expanded(child: _isAtHome ? _buildThisPCHome(isMobile) : _buildRealFileList()),
                          ],
                        ),
                      ),
                      _buildBottomStatusBar(),
                    ],
                  ),
                ),
              ),
              _buildContextMenuOverlay(state),
            ],
          ),
        ),
      ),
    );
  }
}