import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/file_item.dart';
import '../../states/apps_state.dart';
import '../../states/desktop_state.dart';
import '../../states/system_state.dart';
import '../../states/theme_state.dart';
import '../../services/native_bridge.dart';
import '../../services/lazy_app_icon.dart';

class ExplorerContentView extends StatefulWidget {
  final bool isDark;
  final bool isMobile;
  final bool isAtHome;
  final bool isRecycleBin;
  final String rootPath;
  final List<FileItem> files;
  final double totalGB;
  final double freeGB;
  final Set<String> selectedPaths;
  final bool isMultiSelectMode;
  final List<Map<String, dynamic>> disks;
  
  final Function(String) onNavigate;
  final Function(String) onOpenFile;
  final Function(Set<String>) onSelectionChanged;
  final Function(bool) onMultiSelectToggled;
  final Function(Offset, String, String, VoidCallback?) onContextMenu;

  const ExplorerContentView({
    Key? key, required this.isDark, required this.isMobile, required this.isAtHome, this.isRecycleBin = false, required this.rootPath,
    required this.files, required this.totalGB, required this.freeGB, required this.selectedPaths,
    required this.isMultiSelectMode, required this.onNavigate, 
    required this.onOpenFile, required this.onSelectionChanged, required this.onMultiSelectToggled, 
    required this.onContextMenu, this.disks = const [],
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

  Widget _buildFolderIcon({required double size}) {
    final double reducedSize = size * 0.85; 
    return Image.asset(
      'assets/icons/custom_folder.png', 
      width: reducedSize, 
      height: reducedSize, 
      fit: BoxFit.contain, 
      errorBuilder: (_, __, ___) => Icon(Icons.folder, color: Colors.amber, size: reducedSize)
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

  Widget _buildFileIcon(BuildContext context, String path, bool previewFilesEnabled, {double size = 38}) {
    if (path.startsWith('virtual_app://')) {
      final pkg = path.replaceFirst('virtual_app://', '').split('/').first;
      final themeState = context.read<ThemeState>();
      if (themeState.cachedIconsPath != null) {
        final cacheFile = File('${themeState.cachedIconsPath}/$pkg.png');
        if (cacheFile.existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(4), 
            child: Image.file(
              cacheFile, 
              width: size, 
              height: size, 
              errorBuilder: (_, __, ___) => LazyAppIcon(packageName: pkg, size: size)
            )
          );
        }
      }
      return LazyAppIcon(packageName: pkg, size: size);
    }
    
    if (path.startsWith('virtual_system://')) {
      final id = path.replaceFirst('virtual_system://', '').split('/').first;
      String asset = 'folder';
      if (id == 'browser') asset = 'edge';
      else if (id == 'calculator') asset = 'calculator';
      else if (id == 'settings') asset = 'settings';
      else if (id == 'recycle_bin') asset = 'recycle';
      else if (id == 'this_pc') asset = 'folder';
      return Image.asset('assets/icons/$asset.png', width: size, height: size, errorBuilder: (_, __, ___) => Icon(Icons.apps, color: Colors.blueAccent, size: size));
    }

    if (path.startsWith('virtual_folder://')) {
      return _buildFolderIcon(size: size);
    }

    final ext = path.toLowerCase();
    
    if (ext.endsWith('.png') || ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.webp') || ext.endsWith('.gif') || ext.endsWith('.heic') || ext.endsWith('.bmp')) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300, width: 0.5)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3.5), 
          child: Image.file(
            File(path), 
            width: size, 
            height: size, 
            cacheWidth: 200, 
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
        onTap: () {
          if (context.read<DesktopState>().mouseSound) SystemSound.play(SystemSoundType.click);
          widget.onNavigate(path);
        },
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
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final subTextColor = widget.isDark ? Colors.white70 : Colors.grey.shade700;
    final dividerColor = widget.isDark ? Colors.white12 : Colors.grey.shade200;
    final totalDrivesCount = widget.disks.isNotEmpty ? widget.disks.length : 1;

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
              _buildFolderGridCard('Desktop', '${widget.rootPath}/Desktop'), 
              _buildFolderGridCard('Documents', 'Library:Documents'),
              _buildFolderGridCard('Downloads', '${widget.rootPath}/Download'), 
              _buildFolderGridCard('Music', 'Library:Music'),
              _buildFolderGridCard('Pictures', 'Library:Pictures'), 
              _buildFolderGridCard('Videos', 'Library:Videos'),
            ],
          ),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            InkWell(onTap: () => setState(() => _isDevicesExpanded = !_isDevicesExpanded), child: Icon(_isDevicesExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: textColor)), 
            const SizedBox(width: 4), Text('Devices and drives ($totalDrivesCount)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: subTextColor)), const SizedBox(width: 12), 
            Expanded(child: Container(height: 1, color: dividerColor))
          ]
        ),
        if (_isDevicesExpanded) ...[
          const SizedBox(height: 12),
          if (widget.disks.isNotEmpty)
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: widget.disks.map((disk) {
                final double totalGB = (disk['total'] as num).toDouble() / (1024 * 1024 * 1024);
                final double freeGB = (disk['free'] as num).toDouble() / (1024 * 1024 * 1024);
                final double usedGB = totalGB - freeGB;
                final double percent = totalGB > 0 ? (usedGB / totalGB).clamp(0.0, 1.0) : 0.0;
                final bool isRemovable = disk['isRemovable'] == true;
                final String label = disk['label'] ?? 'Disk';
                final String path = disk['path'] ?? widget.rootPath;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (context.read<DesktopState>().mouseSound) SystemSound.play(SystemSoundType.click);
                      widget.onNavigate(path);
                    },
                    child: SizedBox(
                      width: 280,
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Image.asset(
                              isRemovable ? 'assets/icons/sd_card.png' : 'assets/icons/drive.png',
                              width: 42, height: 42,
                              errorBuilder: (_, __, ___) => Icon(
                                isRemovable ? Icons.sd_storage : Icons.storage,
                                size: 42,
                                color: isRemovable ? Colors.teal : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label, style: TextStyle(fontSize: 13, color: widget.isDark ? Colors.white : const Color(0xFF333333))),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.zero,
                                    child: LinearProgressIndicator(
                                      value: percent,
                                      backgroundColor: const Color(0xFFC4C4C4),
                                      color: const Color(0xFF0078D4),
                                      minHeight: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${freeGB.toStringAsFixed(2)} GB free of ${totalGB.toStringAsFixed(2)} GB', style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            )
          else
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (context.read<DesktopState>().mouseSound) SystemSound.play(SystemSoundType.click);
                  widget.onNavigate(widget.rootPath);
                },
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
                              ClipRRect(borderRadius: BorderRadius.zero, child: LinearProgressIndicator(value: widget.totalGB > 0 ? ((widget.totalGB - widget.freeGB) / widget.totalGB).clamp(0.0, 1.0) : 0, backgroundColor: const Color(0xFFC4C4C4), color: const Color(0xFF0078D4), minHeight: 14)), const SizedBox(height: 4),
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
    final desktopState = context.read<DesktopState>();
    if (desktopState.mouseSound) SystemSound.play(SystemSoundType.click);
    
    if (widget.isMultiSelectMode) {
      if (desktopState.gestureHapticFeedback) {
        HapticFeedback.selectionClick();
      }
      
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
      if (item.path.startsWith('virtual_app://')) {
         final pkg = item.path.replaceFirst('virtual_app://', '').split('/').first;
         context.read<AppsState>().launchNativeApp(pkg, systemState: context.read<SystemState>());
      } else if (item.path.startsWith('virtual_system://')) {
         final id = item.path.replaceFirst('virtual_system://', '').split('/').first;
         context.read<AppsState>().openApp(id);
      } else if (item.path.startsWith('virtual_folder://')) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Virtual Desktop Folders must be opened from the Desktop Grid.')));
      } else {
         item.isDir ? widget.onNavigate(item.path) : widget.onOpenFile(item.path);
      }
    }
  }

  double _getIconSize(String viewType) {
    if (viewType == 'Extra Large Icons') return 72;
    if (viewType == 'Large Icons') return 56;
    if (viewType == 'Medium Icons') return 40;
    if (viewType == 'Small Icons') return 28;
    return 40; 
  }

  double _getCrossAxisExtent(String viewType) {
    if (viewType == 'Extra Large Icons') return 120;
    if (viewType == 'Large Icons') return 95;
    if (viewType == 'Medium Icons') return 80;
    if (viewType == 'Small Icons') return 65;
    return 80;
  }

  double _getMainAxisExtent(String viewType) {
    if (viewType == 'Extra Large Icons') return 130;
    if (viewType == 'Large Icons') return 115;
    if (viewType == 'Medium Icons') return 95;
    if (viewType == 'Small Icons') return 80;
    return 95;
  }

  Widget _buildRealFileList(AppsState appsState, DesktopState desktopState) {
    final showHidden = desktopState.showHiddenFiles;
    final List<FileItem> visibleFiles = widget.files.where((f) {
      final name = f.path.split('/').last;
      if (!showHidden && name.startsWith('.')) return false;
      return true;
    }).toList();

    if (visibleFiles.isEmpty) {
      if (widget.isRecycleBin) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/icons/recycle.png', 
                width: 56, 
                height: 56, 
                errorBuilder: (_, __, ___) => Icon(Icons.delete_outline, size: 56, color: widget.isDark ? Colors.white24 : Colors.black26),
              ),
              const SizedBox(height: 14),
              Text(
                "This folder is empty.", 
                style: TextStyle(
                  color: widget.isDark ? Colors.white54 : Colors.black54, 
                  fontSize: 13, 
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }

      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.security, size: 54, color: widget.isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 16),
            Text(
              "Protected by Android Scoped Storage", 
              style: TextStyle(
                color: widget.isDark ? Colors.white : Colors.black87, 
                fontSize: 14, 
                fontWeight: FontWeight.bold
              )
            ),
            const SizedBox(height: 8),
            Text(
              "Non-media documents (PDFs, DOCX, ZIPs)\nare secured by the OS and cannot be previewed here.", 
              textAlign: TextAlign.center,
              style: TextStyle(color: widget.isDark ? Colors.white54 : Colors.black54, height: 1.4, fontSize: 12)
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent, 
                foregroundColor: Colors.white, 
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))
              ),
              // Launches the unrestricted native Android File Picker
              onPressed: () => NativeBridge.instance.openSystemDocumentPicker(),
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text("Open in System Explorer", style: TextStyle(fontWeight: FontWeight.w600)),
            )
          ],
        )
      );
    }

    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final subTextColor = widget.isDark ? Colors.white70 : Colors.grey.shade600;
    final hoverColor = widget.isDark ? Colors.white10 : const Color(0xFFE5E5E5);
    final borderColor = widget.isDark ? Colors.white30 : Colors.blueAccent.withOpacity(0.5);

    double iconSize = _getIconSize(appsState.explorerViewType);
    bool isGrid = appsState.explorerViewType != 'List';
    final previewFiles = desktopState.previewFiles;

    return GestureDetector(
      onTap: () { 
        widget.onSelectionChanged({});
        widget.onMultiSelectToggled(false);
      },
      onSecondaryTapDown: (details) => widget.onContextMenu(details.globalPosition, 'folder', '', null), 
      onLongPressStart: (details) => widget.onContextMenu(details.globalPosition, 'folder', '', null),
      child: isGrid 
        ? GridView.builder(
            physics: const BouncingScrollPhysics(), padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _getCrossAxisExtent(appsState.explorerViewType), 
              mainAxisExtent: _getMainAxisExtent(appsState.explorerViewType),
              mainAxisSpacing: 12, 
              crossAxisSpacing: 12, 
            ),
            itemCount: visibleFiles.length,
            itemBuilder: (context, index) {
              final item = visibleFiles[index];
              final name = item.path.split('/').last;
              final isSelected = widget.selectedPaths.contains(item.path);

              return GestureDetector(
                onSecondaryTapDown: (details) { widget.onSelectionChanged(Set.from(widget.selectedPaths)..add(item.path)); widget.onContextMenu(details.globalPosition, item.isDir ? 'folder' : 'file', name, null); }, 
                onLongPressStart: (details) { 
                  if (desktopState.gestureHapticFeedback) {
                    HapticFeedback.lightImpact();
                  }
                  widget.onMultiSelectToggled(true); 
                  widget.onSelectionChanged(Set.from(widget.selectedPaths)..add(item.path)); 
                  widget.onContextMenu(details.globalPosition, item.isDir ? 'folder' : 'file', name, null); 
                },
                onTap: () => _handleItemTap(item, isSelected),
                child: Container(
                  decoration: BoxDecoration(color: isSelected ? hoverColor : Colors.transparent, borderRadius: BorderRadius.circular(4), border: Border.all(color: isSelected ? borderColor : Colors.transparent, width: 1.0)),
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      item.isDir ? _buildFolderIcon(size: iconSize) : _buildFileIcon(context, item.path, previewFiles, size: iconSize), 
                      const SizedBox(height: 6),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0), 
                          child: Text(name, style: TextStyle(fontSize: 11, color: textColor, height: 1.2), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis)
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          )
        : ListView.builder(
            physics: const BouncingScrollPhysics(), itemCount: visibleFiles.length, padding: const EdgeInsets.only(top: 8, bottom: 40, left: 8, right: 8),
            itemBuilder: (context, index) {
              final item = visibleFiles[index];
              final name = item.path.split('/').last;
              final isSelected = widget.selectedPaths.contains(item.path);
              
              final timeStr = _formatAuthenticDate(item.modified);
              final sizeStr = _getSizeOrCount(item);

              return GestureDetector(
                onSecondaryTapDown: (details) { widget.onSelectionChanged(Set.from(widget.selectedPaths)..add(item.path)); widget.onContextMenu(details.globalPosition, item.isDir ? 'folder' : 'file', name, null); }, 
                onLongPressStart: (details) { 
                  if (desktopState.gestureHapticFeedback) {
                    HapticFeedback.lightImpact();
                  }
                  widget.onMultiSelectToggled(true); 
                  widget.onSelectionChanged(Set.from(widget.selectedPaths)..add(item.path)); 
                  widget.onContextMenu(details.globalPosition, item.isDir ? 'folder' : 'file', name, null); 
                },
                onTap: () => _handleItemTap(item, isSelected),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: isSelected ? hoverColor : Colors.transparent, borderRadius: BorderRadius.circular(4), border: Border.all(color: isSelected ? borderColor : Colors.transparent, width: 1.0)),
                  child: Row(
                    children: [
                      item.isDir ? _buildFolderIcon(size: iconSize) : _buildFileIcon(context, item.path, previewFiles, size: iconSize), const SizedBox(width: 14),
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
    final appsState = context.watch<AppsState>();
    final desktopState = context.watch<DesktopState>();
    return widget.isAtHome ? _buildThisPCHome() : _buildRealFileList(appsState, desktopState);
  }
}