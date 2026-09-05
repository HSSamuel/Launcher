import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/file_item.dart';

class ExplorerContentView extends StatefulWidget {
  final bool isDark;
  final bool isMobile;
  final bool isAtHome;
  final String rootPath;
  final List<FileItem> files;
  final double totalGB;
  final double freeGB;
  final Set<String> selectedPaths;
  final bool isGridView;
  final bool isMultiSelectMode;
  
  final Function(String) onNavigate;
  final Function(String) onOpenFile;
  final Function(Set<String>) onSelectionChanged;
  final Function(bool) onMultiSelectToggled;
  final Function(Offset, String, String, VoidCallback?) onContextMenu;

  const ExplorerContentView({
    Key? key, required this.isDark, required this.isMobile, required this.isAtHome, required this.rootPath,
    required this.files, required this.totalGB, required this.freeGB, required this.selectedPaths,
    required this.isGridView, required this.isMultiSelectMode, required this.onNavigate, 
    required this.onOpenFile, required this.onSelectionChanged, required this.onMultiSelectToggled, required this.onContextMenu,
  }) : super(key: key);

  @override
  State<ExplorerContentView> createState() => _ExplorerContentViewState();
}

class _ExplorerContentViewState extends State<ExplorerContentView> {
  bool _isFoldersExpanded = true;
  bool _isDevicesExpanded = true;

  String _formatAuthenticDate(DateTime m) {
    final hour = m.hour % 12 == 0 ? 12 : m.hour % 12;
    final ampm = m.hour >= 12 ? 'PM' : 'AM';
    final min = m.minute.toString().padLeft(2, '0');
    return '${m.month.toString().padLeft(2, '0')}/${m.day.toString().padLeft(2, '0')}/${m.year} $hour:$min $ampm';
  }

  String _getSizeOrCount(FileItem item) {
    if (item.isDir) {
      return '${item.itemCount} items';
    } else {
      final sizeKB = item.size / 1024;
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

  Widget _buildFileIcon(BuildContext context, String path, {double size = 38}) {
    final ext = path.toLowerCase();
    if (ext.endsWith('.png') || ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.webp') || ext.endsWith('.gif')) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300, width: 0.5)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3.5), 
          child: Image.file(
            File(path), 
            width: size, 
            height: size, 
            cacheWidth: (size * MediaQuery.of(context).devicePixelRatio).round(),
            fit: BoxFit.cover, 
            errorBuilder: (_, __, ___) => Icon(Icons.image, color: Colors.blueAccent, size: size)
          )
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

  Widget _getWin11IconForType(String type, double size) {
    String assetName = type.toLowerCase();
    return Image.asset('assets/icons/$assetName.png', width: size, height: size, errorBuilder: (_, __, ___) => Icon(Icons.folder, size: size, color: Colors.amber));
  }

  Widget _buildFolderGridCard(String label, String path) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onNavigate(path),
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: [
            _getWin11IconForType(label, 36), const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: widget.isDark ? Colors.white : Colors.grey.shade800), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _buildThisPCHome() {
    double usedGB = widget.totalGB - widget.freeGB;
    double usagePercent = widget.totalGB > 0 ? usedGB / widget.totalGB : 0;
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final subTextColor = widget.isDark ? Colors.white70 : Colors.grey.shade700;
    final dividerColor = widget.isDark ? Colors.white12 : Colors.grey.shade200;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), physics: const BouncingScrollPhysics(),
      children: [
        Row(
          children: [
            InkWell(onTap: () => setState(() => _isFoldersExpanded = !_isFoldersExpanded), child: Icon(_isFoldersExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: textColor)), 
            const SizedBox(width: 4), Text('Folders (6)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: subTextColor)), const SizedBox(width: 12), 
            Expanded(child: Container(height: 1, color: dividerColor))
          ]
        ),
        if (_isFoldersExpanded) ...[
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: widget.isMobile ? 2 : 3, childAspectRatio: 2.8, mainAxisSpacing: 8, crossAxisSpacing: 8,
            children: [
              _buildFolderGridCard('Desktop', widget.rootPath), _buildFolderGridCard('Documents', '${widget.rootPath}/Documents'),
              _buildFolderGridCard('Downloads', '${widget.rootPath}/Download'), _buildFolderGridCard('Music', '${widget.rootPath}/Music'),
              _buildFolderGridCard('Pictures', '${widget.rootPath}/Pictures'), _buildFolderGridCard('Videos', '${widget.rootPath}/Movies'),
            ],
          ),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            InkWell(onTap: () => setState(() => _isDevicesExpanded = !_isDevicesExpanded), child: Icon(_isDevicesExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: textColor)), 
            const SizedBox(width: 4), Text('Devices and drives (1)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: subTextColor)), const SizedBox(width: 12), 
            Expanded(child: Container(height: 1, color: dividerColor))
          ]
        ),
        if (_isDevicesExpanded) ...[
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => widget.onNavigate(widget.rootPath),
              child: SizedBox(
                width: 280,
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.asset('assets/icons/drive.png', width: 42, height: 42, errorBuilder: (_, __, ___) => const Icon(Icons.storage, size: 42, color: Colors.grey)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Local Disk (C:)', style: TextStyle(fontSize: 13, color: widget.isDark ? Colors.white : const Color(0xFF333333))), const SizedBox(height: 4),
                            ClipRRect(borderRadius: BorderRadius.zero, child: LinearProgressIndicator(value: usagePercent, backgroundColor: const Color(0xFFC4C4C4), color: const Color(0xFF0078D4), minHeight: 14)), const SizedBox(height: 4),
                            Text('${widget.freeGB.toStringAsFixed(2)} GB free of ${widget.totalGB.toStringAsFixed(2)} GB', style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
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

  void _handleItemTap(FileItem item, bool isSelected) {
    if (widget.isMultiSelectMode) {
      final newSelection = Set<String>.from(widget.selectedPaths);
      if (isSelected) {
        newSelection.remove(item.path);
        widget.onSelectionChanged(newSelection);
        if (newSelection.isEmpty) widget.onMultiSelectToggled(false);
      } else {
        newSelection.add(item.path);
        widget.onSelectionChanged(newSelection);
      }
    } else {
      if (isSelected && widget.selectedPaths.length == 1) { 
        if (item.isDir) {
          widget.onNavigate(item.path); 
        } else {
          widget.onOpenFile(item.path);
        }
      } else { 
        widget.onSelectionChanged({item.path});
      }
    }
  }

  Widget _buildRealFileList() {
    if (widget.files.isEmpty) return const Center(child: Text("Empty Folder", style: TextStyle(color: Colors.grey)));

    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final subTextColor = widget.isDark ? Colors.white70 : Colors.grey.shade600;
    final hoverColor = widget.isDark ? Colors.white10 : const Color(0xFFE5E5E5);
    final borderColor = widget.isDark ? Colors.white30 : Colors.blueAccent.withOpacity(0.5);

    return GestureDetector(
      onTap: () { 
        widget.onSelectionChanged({});
        widget.onMultiSelectToggled(false);
      },
      onSecondaryTapDown: (details) => widget.onContextMenu(details.globalPosition, 'folder', '', null), 
      onLongPressStart: (details) => widget.onContextMenu(details.globalPosition, 'folder', '', null),
      child: widget.isGridView 
        ? GridView.builder(
            physics: const BouncingScrollPhysics(), padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 110, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.85),
            itemCount: widget.files.length,
            itemBuilder: (context, index) {
              final item = widget.files[index];
              final name = item.path.split('/').last;
              final isSelected = widget.selectedPaths.contains(item.path);

              return GestureDetector(
                onSecondaryTapDown: (details) { widget.onSelectionChanged(Set.from(widget.selectedPaths)..add(item.path)); widget.onContextMenu(details.globalPosition, 'folder', name, null); }, 
                onLongPressStart: (details) { widget.onMultiSelectToggled(true); widget.onSelectionChanged(Set.from(widget.selectedPaths)..add(item.path)); widget.onContextMenu(details.globalPosition, 'folder', name, null); },
                onTap: () => _handleItemTap(item, isSelected),
                child: Container(
                  decoration: BoxDecoration(color: isSelected ? hoverColor : Colors.transparent, borderRadius: BorderRadius.circular(4), border: Border.all(color: isSelected ? borderColor : Colors.transparent, width: 1.0)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      item.isDir ? _buildYellowFolder(size: 46) : _buildFileIcon(context, item.path, size: 46), const SizedBox(height: 8),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 4.0), child: Text(name, style: TextStyle(fontSize: 11, color: textColor), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              );
            },
          )
        : ListView.builder(
            physics: const BouncingScrollPhysics(), itemCount: widget.files.length, padding: const EdgeInsets.only(top: 8, bottom: 40, left: 8, right: 8),
            itemBuilder: (context, index) {
              final item = widget.files[index];
              final name = item.path.split('/').last;
              final isSelected = widget.selectedPaths.contains(item.path);
              
              final timeStr = _formatAuthenticDate(item.modified);
              final sizeStr = _getSizeOrCount(item);

              return GestureDetector(
                onSecondaryTapDown: (details) { widget.onSelectionChanged(Set.from(widget.selectedPaths)..add(item.path)); widget.onContextMenu(details.globalPosition, 'folder', name, null); }, 
                onLongPressStart: (details) { widget.onMultiSelectToggled(true); widget.onSelectionChanged(Set.from(widget.selectedPaths)..add(item.path)); widget.onContextMenu(details.globalPosition, 'folder', name, null); },
                onTap: () => _handleItemTap(item, isSelected),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: isSelected ? hoverColor : Colors.transparent, borderRadius: BorderRadius.circular(4), border: Border.all(color: isSelected ? borderColor : Colors.transparent, width: 1.0)),
                  child: Row(
                    children: [
                      item.isDir ? _buildYellowFolder(size: 46) : _buildFileIcon(context, item.path), const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor), overflow: TextOverflow.ellipsis), const SizedBox(height: 4),
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

  @override
  Widget build(BuildContext context) {
    return widget.isAtHome ? _buildThisPCHome() : _buildRealFileList();
  }
}