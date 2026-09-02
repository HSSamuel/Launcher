import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FileExplorerApp extends StatefulWidget {
  const FileExplorerApp({Key? key}) : super(key: key);

  @override
  State<FileExplorerApp> createState() => _FileExplorerAppState();
}

class _FileExplorerAppState extends State<FileExplorerApp> with WidgetsBindingObserver {
  static const platform = MethodChannel('win_launcher/native');
  
  bool _hasPermission = false;
  bool _isAtHome = true;
  Directory _currentDir = Directory('/storage/emulated/0');
  List<FileSystemEntity> _files = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermission();
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
        });
      }
    } catch (e) {
      debugPrint("Error reading directory: $e");
    }
  }

  void _goHome() {
    setState(() => _isAtHome = true);
  }

  // --- NEW: AUTHENTIC ASSET IMAGE RENDERER ---
  Widget _getWin11IconForType(String type, double size) {
    String assetPath = '';
    switch (type) {
      case 'Desktop': assetPath = 'assets/icons/desktop.png'; break;
      case 'Documents': assetPath = 'assets/icons/documents.png'; break;
      case 'Downloads': assetPath = 'assets/icons/downloads.png'; break;
      case 'Music': assetPath = 'assets/icons/music.png'; break;
      case 'Pictures': assetPath = 'assets/icons/pictures.png'; break;
      case 'Videos': assetPath = 'assets/icons/videos.png'; break;
      case 'Drive': assetPath = 'assets/icons/drive.png'; break;
      default: assetPath = 'assets/icons/folder.png'; break;
    }

    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      // Fallback just in case the file is missing so your app never crashes
      errorBuilder: (context, error, stackTrace) => Icon(
        type == 'Drive' ? Icons.storage : Icons.folder, 
        color: type == 'Drive' ? Colors.grey : Colors.amber, 
        size: size
      ),
    );
  }

  // --- UI BUILDING BLOCKS ---

  Widget _buildToolbar() {
    final btnStyle = IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36), splashFactory: InkRipple.splashFactory);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: () {}, icon: const Icon(Icons.add_circle_outline, size: 16, color: Colors.black54), label: const Text('New', style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w400)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 36)),
            ),
            const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.black54),
            const SizedBox(width: 8),
            Container(height: 18, width: 1, color: Colors.grey.shade300),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.content_cut, size: 18, color: Colors.black54), onPressed: () {}, style: btnStyle),
            IconButton(icon: const Icon(Icons.copy, size: 18, color: Colors.black54), onPressed: () {}, style: btnStyle),
            IconButton(icon: const Icon(Icons.paste, size: 18, color: Colors.black38), onPressed: () {}, style: btnStyle),
            IconButton(icon: const Icon(Icons.drive_file_rename_outline, size: 18, color: Colors.black54), onPressed: () {}, style: btnStyle),
            IconButton(icon: const Icon(Icons.share_outlined, size: 18, color: Colors.black54), onPressed: () {}, style: btnStyle),
            IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.black54), onPressed: () {}, style: btnStyle),
            Container(height: 18, width: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 8)),
            IconButton(icon: const Icon(Icons.swap_vert, size: 18, color: Colors.black54), onPressed: () {}, style: btnStyle),
            IconButton(icon: const Icon(Icons.view_list_outlined, size: 18, color: Colors.black54), onPressed: () {}, style: btnStyle),
            IconButton(icon: const Icon(Icons.more_horiz, size: 18, color: Colors.black54), onPressed: () {}, style: btnStyle),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressBar() {
    final btnStyle = IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(32, 32));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back, size: 18, color: Colors.black87), onPressed: _isAtHome ? null : _goHome, style: btnStyle),
          IconButton(icon: const Icon(Icons.arrow_forward, size: 18, color: Colors.black38), onPressed: null, style: btnStyle),
          IconButton(icon: const Icon(Icons.arrow_upward, size: 18, color: Colors.black87), onPressed: _isAtHome || _currentDir.path == '/storage/emulated/0' ? null : () => _loadDirectory(_currentDir.parent), style: btnStyle),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), color: Colors.white),
              child: Row(
                children: [
                  Container(width: 14, height: 14, color: Colors.cyan), 
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(child: Text(_isAtHome ? 'This PC' : _currentDir.path.replaceFirst('/storage/emulated/0', 'This PC > Local Disk (C:)').replaceAll('/', ' > '), style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), color: Colors.white),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 14, color: Colors.black54),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_isAtHome ? 'Search This PC' : 'Search', style: TextStyle(fontSize: 12, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(double width) {
    return Container(
      width: width,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade200)), color: Colors.white),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        physics: const BouncingScrollPhysics(),
        children: [
          _buildSidebarHeader(Icons.star, 'Quick access', Colors.amber),
          _buildSidebarHeader(Icons.computer, 'This PC', Colors.cyan, isSelected: _isAtHome, onTap: _goHome),
          Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: Column(
              children: [
                _buildSidebarItem('Desktop'),
                _buildSidebarItem('Documents'),
                _buildSidebarItem('Downloads'),
                _buildSidebarItem('Music'),
                _buildSidebarItem('Pictures'),
                _buildSidebarItem('Videos'),
                _buildSidebarItem('Drive', labelOverride: 'Local Disk (C:)', onTap: () {
                  if (_hasPermission) _loadDirectory(Directory('/storage/emulated/0'));
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(IconData icon, String label, Color iconColor, {bool isSelected = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected ? Colors.blue.withOpacity(0.08) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.black87),
            const SizedBox(width: 4),
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(String type, {String? labelOverride, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            const SizedBox(width: 18), 
            _getWin11IconForType(type, 16),
            const SizedBox(width: 8),
            Expanded(child: Text(labelOverride ?? type, style: TextStyle(fontSize: 12, color: Colors.grey.shade700), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.black87),
        const SizedBox(width: 4),
        Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: Colors.grey.shade200)),
      ],
    );
  }

  Widget _buildThisPCHome(bool isMobile) {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      children: [
        _buildSectionHeader('Folders (6)'),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: isMobile ? 2 : 3,
          childAspectRatio: 3.0, mainAxisSpacing: 8, crossAxisSpacing: 8,
          children: [
            _buildFolderGridItem('Desktop'),
            _buildFolderGridItem('Documents'),
            _buildFolderGridItem('Downloads'),
            _buildFolderGridItem('Music'),
            _buildFolderGridItem('Pictures'),
            _buildFolderGridItem('Videos'),
          ],
        ),
        const SizedBox(height: 32),
        _buildSectionHeader('Devices and drives (1)'),
        const SizedBox(height: 16),
        InkWell(
          onTap: () {
            if (!_hasPermission) {
              platform.invokeMethod('openSettings', {'type': 'storage'});
            } else {
              _loadDirectory(Directory('/storage/emulated/0'));
            }
          },
          child: SizedBox(
            width: 280,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _getWin11IconForType('Drive', 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Local Disk (C:)', style: TextStyle(fontSize: 13, color: Colors.black87)),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: 0.6, backgroundColor: Colors.grey.shade300, color: Colors.blueAccent.shade700, minHeight: 14),
                      const SizedBox(height: 6),
                      Text('99.78 GB free of 228.01 GB', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFolderGridItem(String type) {
    return Row(
      children: [
        _getWin11IconForType(type, 36),
        const SizedBox(width: 12),
        Expanded(child: Text(type, style: TextStyle(fontSize: 12, color: Colors.grey.shade800), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildRealFileList() {
    if (_files.isEmpty) return const Center(child: Text("Empty Folder", style: TextStyle(color: Colors.grey)));
    return Material(
      color: Colors.transparent,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: _files.length,
        itemBuilder: (context, index) {
          final item = _files[index];
          final isDir = item is Directory;
          return ListTile(
            dense: true,
            leading: isDir 
              ? _getWin11IconForType('Folder', 24) 
              : const Icon(Icons.insert_drive_file_outlined, color: Colors.blueGrey, size: 24),
            title: Text(item.path.split('/').last, style: const TextStyle(fontSize: 12, color: Colors.black87), overflow: TextOverflow.ellipsis),
            onTap: () { if (isDir) _loadDirectory(item as Directory); },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 500;
    final sidebarWidth = isMobile ? 130.0 : 180.0;

    return Container(
      color: Colors.white,
      child: Column(
        children: [
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
        ],
      ),
    );
  }
}