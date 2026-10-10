import 'dart:io';
import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../../states/desktop_state.dart';
import '../../states/apps_state.dart';
import '../../states/theme_state.dart';
import '../../states/system_state.dart';
import '../../states/cloud_drive_state.dart';
import '../../services/pro_gatekeeper.dart';
import '../../models/file_item.dart';
import '../../models/cloud_file_model.dart';
import '../../models/desktop_item_model.dart';
import '../../services/native_bridge.dart';
import '../shared/acrylic_container.dart';
import 'explorer_content_view.dart';
import 'file_system_service.dart';

// --- BACKGROUND ISOLATE FUNCTIONS ---

List<FileItem> _isolateProcessFiles(Map<String, dynamic> args) {
  final List<FileItem> rawFiles = List<FileItem>.from(args['files']);
  final String query = args['query'] as String;
  final String sortBy = args['sortBy'] as String;
  final bool sortAscending = args['sortAscending'] as bool;
  final bool showHidden = args['showHidden'] as bool;

  List<FileItem> filtered = rawFiles.where((f) {
    final name = f.path.split('/').last;
    if (!showHidden && name.startsWith('.')) return false;
    if (query.isNotEmpty && !name.toLowerCase().contains(query)) return false;
    return true;
  }).toList();

  filtered.sort((a, b) {
    if (a.isDir && !b.isDir) return -1;
    if (!a.isDir && b.isDir) return 1;

    int result = 0;
    if (sortBy == 'Name') {
      result = a.path.split('/').last.toLowerCase().compareTo(b.path.split('/').last.toLowerCase());
    } else if (sortBy == 'Type') {
      result = a.path.split('.').last.toLowerCase().compareTo(b.path.split('.').last.toLowerCase());
    } else if (sortBy == 'Date modified') {
      result = a.modified.compareTo(b.modified);
    } else if (sortBy == 'Size') {
      result = a.size.compareTo(b.size);
    }
    return sortAscending ? result : -result;
  });

  return filtered;
}

Future<int> _calculateDirectorySize(String path) async {
  int total = 0;
  try {
    final dir = Directory(path);
    if (dir.existsSync()) {
      await for (var entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    }
  } catch (_) {}
  return total;
}

Future<int> _isolateCopyFiles(Map<String, dynamic> args) async {
  final List<String> files = List<String>.from(args['files']);
  final String targetDirPath = args['targetDirPath'];
  int copied = 0;
  for (var path in files) {
    try {
      final sourceFile = File(path);
      final fileName = path.split('/').last;
      final destPath = '$targetDirPath/$fileName';
      if (!File(destPath).existsSync()) {
        await sourceFile.copy(destPath);
        copied++;
      }
    } catch (_) {}
  }
  return copied;
}

Future<void> _isolateCleanRecycleBin(String binPath) async {
  try {
    final binDir = Directory(binPath);
    if (!binDir.existsSync()) return;

    final indexFile = File('${binDir.path}/.recycle_index.json');
    Map<String, dynamic> index = {};
    if (indexFile.existsSync()) {
      try { index = jsonDecode(indexFile.readAsStringSync()); } catch (_) {}
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    bool indexChanged = false;

    final elements = binDir.listSync();
    for (var entity in elements) {
      final name = entity.path.split('/').last;
      if (name == '.nomedia' || name == '.recycle_index.json') continue;
      
      final deletedAtMs = index[name] as int?;
      if (deletedAtMs != null && (nowMs - deletedAtMs) >= 7 * 24 * 60 * 60 * 1000) {
        try {
          entity.deleteSync(recursive: true);
          index.remove(name);
          indexChanged = true;
        } catch (_) {}
      } else if (deletedAtMs == null) {
        try {
          final stat = entity.statSync();
          if (DateTime.now().difference(stat.modified).inDays >= 7) {
            entity.deleteSync(recursive: true);
          }
        } catch (_) {}
      }
    }
    if (indexChanged) indexFile.writeAsStringSync(jsonEncode(index));
  } catch (_) {}
}

Future<void> _isolateEmptyRecycleBin(String binPath) async {
  try {
    final binDir = Directory(binPath);
    if (binDir.existsSync()) {
      for (var entity in binDir.listSync()) {
        try { entity.deleteSync(recursive: true); } catch (_) {}
      }
    }
  } catch (_) {}
}

Future<void> _fallbackCopyDir(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (var entity in source.list(recursive: false, followLinks: false)) {
    if (entity is Directory) {
      await _fallbackCopyDir(entity, Directory('${destination.path}/${entity.path.split('/').last}'));
    } else if (entity is File) {
      await entity.copy('${destination.path}/${entity.path.split('/').last}');
    }
  }
}

Future<List<String>> _isolateCopyToRecycleBin(Map<String, dynamic> args) async {
  final List<String> selectedPaths = List<String>.from(args['selectedPaths']);
  final String binPath = args['binPath'];
  final binDir = Directory(binPath);

  Map<String, dynamic> deletionIndex = {};
  final indexFile = File('${binDir.path}/.recycle_index.json');

  if (!binDir.existsSync()) {
    binDir.createSync(recursive: true);
    File('${binDir.path}/.nomedia').createSync(); 
  }
  if (indexFile.existsSync()) {
    try { deletionIndex = jsonDecode(indexFile.readAsStringSync()); } catch (_) {}
  }

  List<String> successfullyCopied = [];

  for (String path in selectedPaths) {
    try {
      final isDir = await FileSystemEntity.isDirectory(path);
      final entity = isDir ? Directory(path) : File(path);
      if (await entity.exists()) {
        final name = path.split('/').last;
        String dest = '${binDir.path}/$name';
        int counter = 1;
        
        while (File(dest).existsSync() || Directory(dest).existsSync()) {
          final extIdx = name.lastIndexOf('.');
          if (extIdx != -1) {
            final nameWithoutExt = name.substring(0, extIdx);
            final ext = name.substring(extIdx);
            dest = '${binDir.path}/$nameWithoutExt ($counter)$ext';
          } else {
            dest = '${binDir.path}/$name ($counter)';
          }
          counter++;
        }
        
        if (entity is File) {
          await entity.copy(dest);
        } else if (entity is Directory) {
          await _fallbackCopyDir(entity as Directory, Directory(dest));
        }
        
        deletionIndex[dest.split('/').last] = DateTime.now().millisecondsSinceEpoch;
        successfullyCopied.add(path); 
      }
    } catch (_) {}
  }

  indexFile.writeAsStringSync(jsonEncode(deletionIndex));
  return successfullyCopied;
}

Future<int> _isolateDeletePermanently(Map<String, dynamic> args) async {
  final List<String> selectedPaths = List<String>.from(args['selectedPaths']);
  final String binPath = args['binPath'];

  Map<String, dynamic> deletionIndex = {};
  final indexFile = File('$binPath/.recycle_index.json');

  if (indexFile.existsSync()) {
    try { deletionIndex = jsonDecode(indexFile.readAsStringSync()); } catch (_) {}
  }

  int deleted = 0;
  for (String path in selectedPaths) {
    try {
      final isDir = await FileSystemEntity.isDirectory(path);
      final entity = isDir ? Directory(path) : File(path);
      if (await entity.exists()) {
        await entity.delete(recursive: true);
        deletionIndex.remove(path.split('/').last);
        deleted++;
      }
    } catch (_) {}
  }
  indexFile.writeAsStringSync(jsonEncode(deletionIndex));
  return deleted;
}

// --- EXPLORER UI COMPONENTS ---

class ExplorerTitleBar extends StatelessWidget {
  final bool isDark;
  final VoidCallback onRestoreStatusBar;

  const ExplorerTitleBar({Key? key, required this.isDark, required this.onRestoreStatusBar}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final appsState = context.read<AppsState>();
    
    final bgColor = isDark ? const Color(0xFF191919) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accent = themeState.currentAccentColor;

    return Container(
      height: 36, color: bgColor,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Container(width: 14, height: 12, color: accent),
          const SizedBox(width: 8),
          Text('This PC', style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w400)),
          const Spacer(),
          InkWell(
            onTap: () { onRestoreStatusBar(); appsState.minimizeApp('explorer'); }, 
            child: SizedBox(width: 44, height: 36, child: Center(child: Icon(Icons.remove, size: 16, color: textColor)))
          ),
          InkWell(
            onTap: () => appsState.toggleMaximizeApp('explorer'), 
            child: SizedBox(width: 44, height: 36, child: Center(child: Icon(Icons.crop_square, size: 14, color: textColor)))
          ),
          InkWell(
            onTap: () { onRestoreStatusBar(); appsState.closeApp('explorer'); }, 
            hoverColor: Colors.red, 
            child: SizedBox(width: 44, height: 36, child: Center(child: Icon(Icons.close, size: 16, color: textColor)))
          ),
        ],
      ),
    );
  }
}

class ExplorerToolbar extends StatelessWidget {
  final bool isDark;
  final bool hasSelection;
  final bool isSingleSelection;
  final bool canPaste;
  final VoidCallback onNewFolder;
  final VoidCallback onCut;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  const ExplorerToolbar({
    Key? key, required this.isDark, required this.hasSelection, required this.isSingleSelection, 
    required this.canPaste, required this.onNewFolder, required this.onCut, required this.onCopy, 
    required this.onPaste, required this.onRename, required this.onDelete, required this.onShare,
  }) : super(key: key);

  Widget _toolBtn(IconData icon, bool isDark, {bool disabled = false, Color? color, VoidCallback? onTap}) {
    final defaultColor = color ?? (isDark ? Colors.white : Colors.black87);
    final disabledColor = isDark ? Colors.white24 : Colors.black26;
    return InkWell(
      onTap: disabled ? null : (onTap ?? () {}),
      borderRadius: BorderRadius.circular(4),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Icon(icon, size: 18, color: disabled ? disabledColor : defaultColor)),
    );
  }

  Widget _buildTextToolBtn(String text, IconData icon, bool isDark, Color activeColor, VoidCallback onTap) {
    final textColor = isDark ? Colors.white : Colors.black87;
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: activeColor), const SizedBox(width: 6),
            Text(text, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w400)), const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }

  Widget _divider(bool isDark) => Container(height: 16, width: 1, color: isDark ? Colors.white24 : Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 2));

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final appsState = context.watch<AppsState>();
    final activeColor = themeState.currentAccentColor;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor))),
      child: Row(
        children: [
          _buildTextToolBtn('New', Icons.add_circle_outline, isDark, activeColor, onNewFolder),
          _divider(isDark),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _toolBtn(Icons.content_cut, isDark, disabled: !isSingleSelection, color: activeColor, onTap: onCut),
                  _toolBtn(Icons.content_copy, isDark, disabled: !isSingleSelection, color: activeColor, onTap: onCopy),
                  _toolBtn(Icons.content_paste, isDark, disabled: !canPaste, color: activeColor, onTap: onPaste),
                  _toolBtn(Icons.drive_file_rename_outline, isDark, disabled: !isSingleSelection, color: activeColor, onTap: onRename),
                  _toolBtn(Icons.ios_share, isDark, disabled: !isSingleSelection, color: activeColor, onTap: onShare),
                  _toolBtn(Icons.delete_outline, isDark, disabled: !hasSelection, color: activeColor, onTap: onDelete),
                  _divider(isDark),
                ],
              ),
            ),
          ),
          
          Builder(
            builder: (btnContext) => InkWell(
              onTap: () {
                final RenderBox box = btnContext.findRenderObject() as RenderBox;
                final Offset pos = box.localToGlobal(Offset.zero);
                showMenu<String>(
                  context: context,
                  position: RelativeRect.fromLTRB(pos.dx, pos.dy + box.size.height, MediaQuery.of(context).size.width - pos.dx - box.size.width, 0),
                  color: Colors.transparent,
                  elevation: 0,
                  items: [
                    PopupMenuItem<String>(
                      enabled: false,
                      padding: EdgeInsets.zero,
                      child: Win11AcrylicContainer(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor, width: 1),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            {'label': 'Name', 'val': 'Name'},
                            {'label': 'Type', 'val': 'Type'},
                            {'label': 'Date modified', 'val': 'Date modified'},
                            {'label': 'Size', 'val': 'Size'},
                            const Divider(height: 1),
                            {'label': 'Ascending', 'val': 'Ascending'},
                            {'label': 'Descending', 'val': 'Descending'},
                          ].map((item) {
                            if (item is Divider) return item;
                            final map = item as Map<String, String>;
                            bool isDot = false;
                            if (map['val'] == 'Ascending') isDot = appsState.explorerSortAscending;
                            else if (map['val'] == 'Descending') isDot = !appsState.explorerSortAscending;
                            else isDot = appsState.explorerSortBy == map['val'];

                            return InkWell(
                              onTap: () => Navigator.pop(context, map['val']),
                              borderRadius: BorderRadius.circular(6),
                              hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    SizedBox(width: 16, child: isDot ? Icon(Icons.circle, size: 6, color: textColor) : null),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(map['label']!, style: TextStyle(color: textColor, fontSize: 12))),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ).then((val) {
                  if (val != null) {
                    if (val == 'Ascending') appsState.updateExplorerSort(appsState.explorerSortBy, true);
                    else if (val == 'Descending') appsState.updateExplorerSort(appsState.explorerSortBy, false);
                    else appsState.updateExplorerSort(val, appsState.explorerSortAscending);
                  }
                });
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Icon(Icons.swap_vert, size: 18, color: textColor)), 
            ),
          ),
          
          Builder(
            builder: (btnContext) => InkWell(
              onTap: () {
                final RenderBox box = btnContext.findRenderObject() as RenderBox;
                final Offset pos = box.localToGlobal(Offset.zero);
                showMenu<String>(
                  context: context,
                  position: RelativeRect.fromLTRB(pos.dx, pos.dy + box.size.height, MediaQuery.of(context).size.width - pos.dx - box.size.width, 0),
                  color: Colors.transparent,
                  elevation: 0,
                  items: [
                    PopupMenuItem<String>(
                      enabled: false,
                      padding: EdgeInsets.zero,
                      child: Win11AcrylicContainer(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor, width: 1),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            {'label': 'Extra Large Icons', 'icon': Icons.crop_square},
                            {'label': 'Large Icons', 'icon': Icons.crop_din},
                            {'label': 'Medium Icons', 'icon': Icons.crop_7_5},
                            {'label': 'Small Icons', 'icon': Icons.grid_view},
                            {'label': 'List', 'icon': Icons.format_list_bulleted},
                          ].map((item) {
                            final label = item['label'] as String;
                            final icon = item['icon'] as IconData;
                            final isDot = appsState.explorerViewType == label;

                            return InkWell(
                              onTap: () => Navigator.pop(context, label),
                              borderRadius: BorderRadius.circular(6),
                              hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    SizedBox(width: 16, child: isDot ? Icon(Icons.circle, size: 6, color: textColor) : null),
                                    const SizedBox(width: 8),
                                    Icon(icon, size: 16, color: textColor),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(label, style: TextStyle(color: textColor, fontSize: 12))),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ).then((val) {
                  if (val != null) appsState.updateExplorerView(val);
                });
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Icon(Icons.web_asset, size: 18, color: textColor)), 
            ),
          ),
          _divider(isDark),
          _toolBtn(Icons.more_horiz, isDark),
        ],
      ),
    );
  }
}

class ExplorerAddressBar extends StatelessWidget {
  final bool isDark;
  final bool isAtHome;
  final String currentPath;
  final String rootPath;
  final List<String> pathHistory;
  final TextEditingController searchController;
  final VoidCallback onGoBack;
  final VoidCallback onGoHome;
  final Function(String) onNavigate;
  final List<Map<String, dynamic>> disks;
  
  final bool isViewingCloud;
  final List<Map<String, String>> cloudPathStack;
  final String cloudProvider;
  final Function(String, String, bool)? onCloudNavigate;

  const ExplorerAddressBar({
    Key? key, required this.isDark, required this.isAtHome, required this.currentPath, required this.rootPath, 
    required this.pathHistory, required this.searchController, required this.onGoBack, required this.onGoHome, 
    required this.onNavigate, this.disks = const [],
    this.isViewingCloud = false, this.cloudPathStack = const [], this.cloudProvider = '', this.onCloudNavigate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final accent = themeState.currentAccentColor;
    final btnStyle = IconButton.styleFrom(padding: const EdgeInsets.all(2), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap);
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final inputBg = isDark ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    List<Widget> breadcrumbs = [];

    if (isViewingCloud) {
      breadcrumbs.add(Container(width: 12, height: 10, color: accent));
      breadcrumbs.add(const SizedBox(width: 4));
      breadcrumbs.add(InkWell(
        onTap: () => onCloudNavigate?.call('root', 'Google Drive', true),
        child: Text(cloudProvider == 'gdrive' ? 'GOOGLE DRIVE' : cloudProvider.toUpperCase(), style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600))
      ));
      
      for (var folder in cloudPathStack) {
        breadcrumbs.add(const SizedBox(width: 2));
        breadcrumbs.add(Icon(Icons.chevron_right, size: 14, color: textColor));
        breadcrumbs.add(const SizedBox(width: 2));
        breadcrumbs.add(InkWell(
          onTap: () => onCloudNavigate?.call(folder['id']!, folder['name']!, true), 
          child: Text(folder['name']!, style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600))
        ));
      }
    } else {
      breadcrumbs.add(Container(width: 12, height: 10, color: accent));
      breadcrumbs.add(const SizedBox(width: 4));
      breadcrumbs.add(InkWell(onTap: onGoHome, child: Text('This PC', style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600))));
      breadcrumbs.add(const SizedBox(width: 2));
      breadcrumbs.add(Icon(Icons.chevron_right, size: 14, color: textColor));

      if (!isAtHome) {
        if (currentPath.contains('.Win11RecycleBin')) {
          breadcrumbs.add(const SizedBox(width: 2));
          breadcrumbs.add(InkWell(
            onTap: () => onNavigate(currentPath), 
            child: Text('Recycle Bin', style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600))
          ));
          breadcrumbs.add(const SizedBox(width: 2));
          breadcrumbs.add(Icon(Icons.chevron_right, size: 14, color: textColor));
        } else {
          Map<String, dynamic>? activeDisk;
          for (var d in disks) {
            final dPath = d['path'] as String? ?? '';
            if (dPath.isNotEmpty && currentPath.startsWith(dPath)) {
              if (activeDisk == null || dPath.length > (activeDisk['path'] as String).length) {
                activeDisk = d;
              }
            }
          }

          final basePath = activeDisk != null ? (activeDisk['path'] as String) : rootPath;
          final diskLabel = activeDisk != null ? (activeDisk['label'] as String) : 'Local Disk (C:)';

          breadcrumbs.add(const SizedBox(width: 2));
          breadcrumbs.add(InkWell(onTap: () => onNavigate(basePath), child: Text(diskLabel, style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600))));
          breadcrumbs.add(const SizedBox(width: 2));
          breadcrumbs.add(Icon(Icons.chevron_right, size: 14, color: textColor));

          final relativeSubPath = currentPath.replaceFirst(basePath, '');
          final folders = relativeSubPath.split('/').where((e) => e.isNotEmpty).toList();
          String cumulativePath = basePath;

          for (var folder in folders) {
            cumulativePath += '/$folder';
            final targetPath = cumulativePath;
            breadcrumbs.add(const SizedBox(width: 2));
            breadcrumbs.add(InkWell(onTap: () => onNavigate(targetPath), child: Text(folder, style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600))));
            breadcrumbs.add(const SizedBox(width: 2));
            breadcrumbs.add(Icon(Icons.chevron_right, size: 14, color: textColor));
          }
        }
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200))),
      child: Row(
        children: [
          IconButton(icon: Icon(Icons.arrow_back, size: 18, color: textColor), onPressed: pathHistory.isEmpty && !isViewingCloud ? null : onGoBack, style: btnStyle), const SizedBox(width: 2),
          IconButton(icon: Icon(Icons.arrow_forward, size: 18, color: isDark ? Colors.white30 : Colors.black38), onPressed: null, style: btnStyle), const SizedBox(width: 4),
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
              decoration: BoxDecoration(
                border: Border.all(color: borderColor), 
                color: inputBg, 
                borderRadius: BorderRadius.circular(2)
              ),
              child: Row(
                children: [
                  Icon(Icons.search, size: 12, color: isDark ? Colors.white54 : Colors.black54), 
                  const SizedBox(width: 4), 
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      enabled: true,
                      textAlignVertical: TextAlignVertical.center,
                      style: TextStyle(fontSize: 11, color: textColor),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: isAtHome && !isViewingCloud ? 'Search This PC' : 'Search...',
                        hintStyle: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade600),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.only(bottom: 3), 
                      ),
                    ),
                  )
                ]
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ExplorerSidebar extends StatefulWidget {
  final double width;
  final bool isDark;
  final bool isAtHome;
  final String rootPath;
  final String currentPath;
  final String? currentLibraryCategory;
  final VoidCallback onGoHome;
  final Function(String) onNavigate;
  final List<Map<String, dynamic>> disks;
  final bool isViewingCloud;
  final VoidCallback? onGoogleDriveTap;

  const ExplorerSidebar({
    Key? key, required this.width, required this.isDark, required this.isAtHome, required this.rootPath, 
    required this.currentPath, this.currentLibraryCategory,
    required this.onGoHome, required this.onNavigate, this.disks = const [],
    this.isViewingCloud = false, this.onGoogleDriveTap,
  }) : super(key: key);

  @override
  State<ExplorerSidebar> createState() => _ExplorerSidebarState();
}

class _ExplorerSidebarState extends State<ExplorerSidebar> {
  bool _isQuickAccessExpanded = true;
  bool _isThisPCExpanded = true;

  bool _isSelected(String? category, String path) {
    if (widget.isViewingCloud) return false;
    if (widget.isAtHome && category == null && path == 'home') return true;
    if (widget.currentLibraryCategory != null && category != null) {
      return widget.currentLibraryCategory == category;
    }
    return widget.currentPath == path && !widget.isAtHome && widget.currentLibraryCategory == null;
  }

  Widget _buildSidebarHeader(IconData icon, String label, Color iconColor, bool isSelected, VoidCallback? onTap, bool isExpanded, VoidCallback onToggle) {
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final selectedBg = widget.isDark ? Colors.white12 : Colors.blue.withOpacity(0.12);
    
    return Material(
      color: isSelected ? selectedBg : Colors.transparent,
      child: InkWell(
        onTap: onTap ?? onToggle,
        child: Stack(
          children: [
            Row(
              children: [
                InkWell(onTap: onToggle, child: Padding(padding: const EdgeInsets.all(6.0), child: Icon(isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: textColor))),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      children: [
                        Icon(icon, size: 16, color: iconColor), const SizedBox(width: 6),
                        Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, color: textColor), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (isSelected)
              Positioned(
                left: 0, top: 4, bottom: 4,
                child: Container(width: 3, decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(3))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarAssetItem(String label, String assetName, bool isSelected, VoidCallback? onTap) {
    final hoverColor = widget.isDark ? Colors.white10 : Colors.lightBlue.withOpacity(0.08);
    final selectedBg = widget.isDark ? Colors.white12 : Colors.blue.withOpacity(0.12);
    final textColor = widget.isDark ? Colors.white70 : Colors.grey.shade700;
    
    return Material(
      color: isSelected ? selectedBg : Colors.transparent,
      child: InkWell(
        onTap: onTap, hoverColor: hoverColor,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
              child: Row(
                children: [
                  const SizedBox(width: 16), 
                  Image.asset('assets/icons/$assetName.png', width: 16, height: 16, errorBuilder: (_, __, ___) => const Icon(Icons.folder, size: 16, color: Colors.amber)),
                  const SizedBox(width: 8), 
                  Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: textColor, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal), overflow: TextOverflow.ellipsis))
                ]
              )
            ),
            if (isSelected)
              Positioned(
                left: 0, top: 4, bottom: 4,
                child: Container(width: 3, decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(3))),
              ),
          ],
        )
      ),
    );
  }

  Widget _buildSidebarItem(String label, IconData icon, Color color, VoidCallback? onTap) {
    final textColor = widget.isDark ? Colors.white70 : Colors.grey.shade700;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap, 
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
          child: Row(children: [const SizedBox(width: 16), Icon(icon, color: color, size: 16), const SizedBox(width: 8), Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: textColor), overflow: TextOverflow.ellipsis))])
        )
      ),
    );
  }

  Widget _buildCloudSidebarItem(String label, IconData icon, Color color, bool isSelected, VoidCallback? onTap) {
    final textColor = widget.isDark ? Colors.white70 : Colors.grey.shade700;
    final selectedBg = widget.isDark ? Colors.white12 : Colors.blue.withOpacity(0.12);
    return Material(
      color: isSelected ? selectedBg : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  const SizedBox(width: 16), 
                  Icon(icon, color: color, size: 16), 
                  const SizedBox(width: 8), 
                  Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: textColor, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal), overflow: TextOverflow.ellipsis))
                ]
              )
            ),
            if (isSelected)
              Positioned(left: 0, top: 4, bottom: 4, child: Container(width: 3, decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(3)))),
          ],
        )
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final appsState = context.watch<AppsState>();
    final bgColor = widget.isDark ? const Color(0xFF202020) : Colors.white;
    final borderColor = widget.isDark ? Colors.white12 : Colors.grey.shade200;
    final accent = themeState.currentAccentColor;

    return Container(
      width: widget.width,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: borderColor)), color: bgColor),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4), physics: const BouncingScrollPhysics(),
        children: [
          _buildSidebarHeader(Icons.star, 'Quick access', Colors.orange.shade400, false, null, _isQuickAccessExpanded, () => setState(() => _isQuickAccessExpanded = !_isQuickAccessExpanded)),
          if (_isQuickAccessExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Column(
                children: appsState.pinnedQuickAccess.map((name) {
                  return _buildSidebarItem(name, Icons.push_pin, widget.isDark ? Colors.white54 : Colors.grey.shade600, () {});
                }).toList(),
              ),
            ),
          _buildSidebarHeader(Icons.folder, 'This PC', accent, _isSelected(null, 'home'), widget.onGoHome, _isThisPCExpanded, () => setState(() => _isThisPCExpanded = !_isThisPCExpanded)),
          if (_isThisPCExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Column(
                children: [
                  _buildSidebarAssetItem('Desktop', 'desktop', _isSelected(null, '${widget.rootPath}/Desktop'), () => widget.onNavigate('${widget.rootPath}/Desktop')),
                  _buildSidebarAssetItem('Documents', 'documents', _isSelected('Documents', '${widget.rootPath}/Documents'), () => widget.onNavigate('Library:Documents')),
                  _buildSidebarAssetItem('Downloads', 'downloads', _isSelected(null, '${widget.rootPath}/Download'), () => widget.onNavigate('${widget.rootPath}/Download')),
                  _buildSidebarAssetItem('Music', 'music', _isSelected('Music', '${widget.rootPath}/Music'), () => widget.onNavigate('Library:Music')),
                  _buildSidebarAssetItem('Pictures', 'pictures', _isSelected('Pictures', '${widget.rootPath}/Pictures'), () => widget.onNavigate('Library:Pictures')),
                  _buildSidebarAssetItem('Videos', 'videos', _isSelected('Videos', '${widget.rootPath}/Movies'), () => widget.onNavigate('Library:Videos')),
                  
                  if (widget.disks.isNotEmpty)
                    ...widget.disks.map((disk) {
                      final bool isRemovable = disk['isRemovable'] == true;
                      final String label = disk['label'] ?? 'Disk';
                      final String path = disk['path'] ?? widget.rootPath;
                      final bool isSelected = _isSelected(null, path);

                      return Material(
                        color: isSelected ? (widget.isDark ? Colors.white12 : Colors.blue.withOpacity(0.12)) : Colors.transparent, 
                        child: InkWell(
                          onTap: () => widget.onNavigate(path), 
                          child: Stack(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
                                child: Row(
                                  children: [
                                    const SizedBox(width: 16), 
                                    Image.asset(
                                      isRemovable ? 'assets/icons/sd_card.png' : 'assets/icons/drive.png', 
                                      width: 16, height: 16, 
                                      errorBuilder: (_, __, ___) => Icon(
                                        isRemovable ? Icons.sd_storage : Icons.storage, 
                                        size: 16, 
                                        color: isRemovable ? Colors.teal : Colors.grey
                                      )
                                    ), 
                                    const SizedBox(width: 8), 
                                    Expanded(
                                      child: Text(
                                        label, 
                                        style: TextStyle(
                                          fontSize: 12, 
                                          color: widget.isDark ? Colors.white70 : Colors.grey.shade700,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal
                                        ), 
                                        overflow: TextOverflow.ellipsis
                                      )
                                    )
                                  ]
                                )
                              ),
                              if (isSelected)
                                Positioned(
                                  left: 0, top: 4, bottom: 4,
                                  child: Container(width: 3, decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(3))),
                                ),
                            ]
                          )
                        )
                      );
                    }).toList()
                  else ...[
                    Builder(builder: (context) {
                      final isSelected = _isSelected(null, widget.rootPath);
                      return Material(
                        color: isSelected ? (widget.isDark ? Colors.white12 : Colors.blue.withOpacity(0.12)) : Colors.transparent, 
                        child: InkWell(
                          onTap: () => widget.onNavigate(widget.rootPath), 
                          child: Stack(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
                                child: Row(
                                  children: [
                                    const SizedBox(width: 16), 
                                    Image.asset('assets/icons/drive.png', width: 16, height: 16, errorBuilder: (_, __, ___) => const Icon(Icons.storage, size: 16, color: Colors.grey)), 
                                    const SizedBox(width: 8), 
                                    Expanded(child: Text('Local Disk (C:)', style: TextStyle(fontSize: 12, color: widget.isDark ? Colors.white70 : Colors.grey.shade700, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal), overflow: TextOverflow.ellipsis))
                                  ]
                                )
                              ),
                              if (isSelected)
                                Positioned(
                                  left: 0, top: 4, bottom: 4,
                                  child: Container(width: 3, decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(3))),
                                ),
                            ]
                          )
                        )
                      );
                    })
                  ]
                ],
              ),
            ),
          
          const Padding(
            padding: EdgeInsets.only(top: 16, bottom: 4, left: 16),
            child: Align(alignment: Alignment.centerLeft, child: Text('Network Drives', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey))),
          ),
          _buildCloudSidebarItem('Google Drive', Icons.add_to_drive, Colors.green, widget.isViewingCloud, widget.onGoogleDriveTap),
        ],
      ),
    );
  }
}

class ExplorerStatusBar extends StatelessWidget {
  final bool isDark;
  final bool isAtHome;
  final int itemCount;
  final int selectedCount;
  final double sidebarWidthPercent;
  final ValueChanged<double> onWidthChanged;

  const ExplorerStatusBar({
    Key? key, required this.isDark, required this.isAtHome, required this.itemCount, required this.selectedCount, 
    required this.sidebarWidthPercent, required this.onWidthChanged,
  }) : super(key: key);

  void _showWidthAdjustmentDialog(BuildContext context, Color accent) {
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;
    double tempWidth = sidebarWidthPercent;

    showDialog(
      context: context, barrierColor: Colors.transparent, 
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Stack(
              children: [
                Positioned(
                  bottom: 60, right: 10,
                  child: Material(
                    elevation: 8, borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 250, padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: borderColor)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [Text('Select Quick Access width', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor)), InkWell(onTap: () => Navigator.pop(context), child: Icon(Icons.close, size: 16, color: textColor))],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.orange, size: 24),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(trackHeight: 4.0, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0)),
                                  child: Slider(
                                    value: tempWidth, min: 15, max: 50, activeColor: accent, inactiveColor: accent.withOpacity(0.2),
                                    onChanged: (val) { setDialogState(() => tempWidth = val); onWidthChanged(val); }
                                  ),
                                ),
                              ),
                              Text('${tempWidth.toInt()} %', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textColor)),
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

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final appsState = context.watch<AppsState>();
    final accent = themeState.currentAccentColor;
    final bgColor = isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3);
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final textColor = isDark ? Colors.white70 : Colors.grey.shade700;

    return Container(
      height: 28, padding: const EdgeInsets.symmetric(horizontal: 12), 
      decoration: BoxDecoration(color: bgColor, border: Border(top: BorderSide(color: borderColor, width: 0.8))),
      child: Row(
        children: [
          if (isAtHome) ...[
            Text('7 items', style: TextStyle(fontSize: 11, color: textColor)),
          ] else ...[
            Text('$itemCount items  |  ${selectedCount > 0 ? '$selectedCount items selected  |' : ''}', style: TextStyle(fontSize: 11, color: textColor)), 
            const Spacer(), 
            InkWell(onTap: () => _showWidthAdjustmentDialog(context, accent), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: Text('${sidebarWidthPercent.toInt()} %', style: TextStyle(fontSize: 11, color: textColor)))),
            const SizedBox(width: 8), 
            InkWell(onTap: () => appsState.updateExplorerView('List'), child: Padding(padding: const EdgeInsets.all(4.0), child: Icon(Icons.format_list_bulleted, size: 14, color: appsState.explorerViewType == 'List' ? accent : textColor))), 
            const SizedBox(width: 6), 
            InkWell(onTap: () => appsState.updateExplorerView('Medium Icons'), child: Padding(padding: const EdgeInsets.all(4.0), child: Icon(Icons.grid_view_sharp, size: 14, color: appsState.explorerViewType != 'List' ? accent : textColor)))
          ]
        ]
      ),
    );
  }
}

class SafeInputDialog extends StatefulWidget {
  final String title;
  final String initialText;
  final String hintText;
  final String actionText;
  final bool isDark;

  const SafeInputDialog({Key? key, required this.title, required this.initialText, required this.hintText, required this.actionText, required this.isDark}) : super(key: key);

  @override
  State<SafeInputDialog> createState() => _SafeInputDialogState();
}

class _SafeInputDialogState extends State<SafeInputDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final accent = themeState.currentAccentColor;
    final bgColor = widget.isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = widget.isDark ? Colors.white : Colors.black87;

    return AlertDialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Text(widget.title, style: TextStyle(fontSize: 15, color: textColor)),
      content: TextField(
        controller: _controller,
        style: TextStyle(color: textColor, fontSize: 13),
        decoration: InputDecoration(
          hintText: widget.hintText, hintStyle: TextStyle(color: widget.isDark ? Colors.white54 : Colors.black54),
          isDense: true, enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: widget.isDark ? Colors.white38 : Colors.black38)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accent)),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black87))),
        TextButton(onPressed: () => Navigator.pop(context, _controller.text), child: Text(widget.actionText, style: TextStyle(color: accent))),
      ],
    );
  }
}

class FileExplorerApp extends StatefulWidget {
  const FileExplorerApp({Key? key}) : super(key: key);

  @override
  State<FileExplorerApp> createState() => FileExplorerAppState();
}

class FileExplorerAppState extends State<FileExplorerApp> with WidgetsBindingObserver {
  final Map<String, List<FileItem>> _globalLibraryCache = {};
  final Map<String, DateTime> _globalLibrarySyncTime = {};

  AppsState? _appsState;
  DesktopState? _desktopState;
  late String _rootPath;
  late String _recycleBinPath;
  bool _isInitialized = false;

  final TextEditingController _searchController = TextEditingController();

  bool _hasPermission = false;
  bool _isAtHome = true;
  late Directory _currentDir;

  String? _currentLibraryCategory; 
  bool _isAggregatedView = true;
  bool _isLoadingLibrary = false;

  List<FileItem> _files = [];
  List<String> _pathHistory = []; 

  double _totalGB = 0.0;
  double _freeGB = 0.0;
  List<Map<String, dynamic>> _disks = [];

  Set<String> _selectedPaths = {};
  bool _isMultiSelectMode = false;

  bool _isContextMenuOpen = false;
  Offset _contextMenuPos = Offset.zero;
  String? _activeSubMenu;

  String _contextMenuType = 'desktop'; 
  String _contextTargetName = '';

  double _sidebarWidthPercent = 36.0;
  bool? _lastThemeDark;
  Timer? _searchDebounce;

  StreamSubscription<String>? _navSubscription;
  String? _activeHighlightName;

  List<FileItem> _processedFiles = [];
  bool _isProcessingFiles = true;
  String _lastQuery = '';
  String _lastSortBy = '';
  bool _lastSortAsc = true;
  bool _lastShowHidden = false;

  bool _isPromptingPermission = false;

  // Cloud VFS Logic Flags
  bool _isViewingCloud = false;

  @override
  void initState() {
    super.initState();
    _initExplorer();

    _navSubscription = context.read<AppsState>().explorerNavigationStream.stream.listen((path) {
      if (path == ":refresh:") {
        if (mounted) {
          if (_currentLibraryCategory != null) {
            _globalLibraryCache.remove(_currentLibraryCategory);
            _loadSmartLibrary(_currentLibraryCategory!);
          } else if (!_isAtHome) {
            _loadDirectory(_currentDir, isSilentRefresh: true);
          }
        }
        return;
      }
      
      if (mounted) _loadDirectorySafe(path);
    });
  }

  Future<void> _initExplorer() async {
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        _rootPath = extDir.path.split('/Android')[0];
        
        final binDir = Directory('$_rootPath/.Win11RecycleBin');
        if (!binDir.existsSync()) {
          binDir.createSync(recursive: true);
          File('${binDir.path}/.nomedia').createSync();
        }
        _recycleBinPath = binDir.path;
      } else {
        _rootPath = '/storage/emulated/0';
        _recycleBinPath = '$_rootPath/.Win11RecycleBin';
      }
    } catch (_) {
      _rootPath = '/storage/emulated/0';
      _recycleBinPath = '$_rootPath/.Win11RecycleBin';
    }

    String statePath = context.read<AppsState>().currentExplorerPath;
    if (statePath == '/storage/emulated/0' && _rootPath != '/storage/emulated/0') {
       statePath = _rootPath; 
       context.read<AppsState>().currentExplorerPath = _rootPath;
    }

    _currentDir = Directory(statePath);
    if (_currentDir.path != _rootPath) _isAtHome = false;

    _searchController.addListener(() {
      if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) _processFilesAsync();
      });
    });

    WidgetsBinding.instance.addObserver(this);

    if (mounted) {
      setState(() { _isInitialized = true; });
      _checkPermissionAndPrompt();
      _fetchStorageStats();
      _cleanRecycleBin(); 
    }
  }

  void _onStateChanged() {
    if (!mounted) return;
    final appsState = _appsState;
    final desktopState = _desktopState;
    if (appsState == null || desktopState == null) return;

    if (_lastSortBy != appsState.explorerSortBy || 
        _lastSortAsc != appsState.explorerSortAscending || 
        _lastShowHidden != desktopState.showHiddenFiles) {
      _processFilesAsync(force: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final newAppsState = context.read<AppsState>();
    final newDesktopState = context.read<DesktopState>();

    if (_appsState != newAppsState) {
      _appsState?.removeListener(_onStateChanged);
      _appsState = newAppsState;
      _appsState?.addListener(_onStateChanged);
      _appsState?.registerBackHandler('explorer', () async => goBack());
    }

    if (_desktopState != newDesktopState) {
      _desktopState?.removeListener(_onStateChanged);
      _desktopState = newDesktopState;
      _desktopState?.addListener(_onStateChanged);
    }

    final isDark = context.watch<ThemeState>().isDarkMode;
    if (_lastThemeDark != isDark) {
      _lastThemeDark = isDark;
      _updateStatusBar(isDark);
    }
  }

  @override
  void dispose() {
    _appsState?.removeListener(_onStateChanged);
    _desktopState?.removeListener(_onStateChanged);
    _appsState?.unregisterBackHandler('explorer');
    _searchDebounce?.cancel();
    _navSubscription?.cancel();
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _restoreTransparentStatusBar();

    _globalLibraryCache.clear();
    _globalLibrarySyncTime.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_lastThemeDark != null) {
        _updateStatusBar(_lastThemeDark!);
      }
      _checkPermissionAndPrompt();
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
    final disks = await NativeBridge.instance.getDisks();
    if (disks.isNotEmpty && mounted) {
      setState(() {
        _disks = disks;
        final primaryDisk = disks.firstWhere((d) => d['isPrimary'] == true, orElse: () => disks.first);
        _totalGB = (primaryDisk['total'] as num).toDouble() / (1024 * 1024 * 1024);
        _freeGB = (primaryDisk['free'] as num).toDouble() / (1024 * 1024 * 1024);
      });
    } else {
      final stats = await NativeBridge.instance.getStorageStats();
      if (stats != null && mounted) {
        setState(() {
          _totalGB = (stats['total'] ?? 0.0) / (1024 * 1024 * 1024);
          _freeGB = (stats['free'] ?? 0.0) / (1024 * 1024 * 1024);
        });
      }
    }
  }

  void navigateTo(String path) {
    _loadDirectorySafe(path);
  }

  void _blinkSelection(String targetPath) async {
    for (int i = 0; i < 3; i++) {
      if (!mounted) return;
      setState(() => _selectedPaths = {targetPath});
      await Future.delayed(const Duration(milliseconds: 250));
      
      if (!mounted) return;
      setState(() => _selectedPaths = {});
      await Future.delayed(const Duration(milliseconds: 250));
    }

    if (mounted) {
      setState(() {
        _selectedPaths = {targetPath};
      });
    }
  }

  Future<void> _cleanRecycleBin() async {
    await compute(_isolateCleanRecycleBin, _recycleBinPath);
  }

  Future<void> _emptyRecycleBin() async {
    HapticFeedback.lightImpact();
    await compute(_isolateEmptyRecycleBin, _recycleBinPath);
    _loadDirectory(_currentDir);
    _showToast('Recycle Bin emptied completely.');
  }

  Future<void> _checkPermissionAndPrompt() async {
    bool isGranted = false;
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 30) {
        isGranted = await Permission.manageExternalStorage.isGranted;
      } else {
        isGranted = await Permission.storage.isGranted;
      }
    } else {
      isGranted = true;
    }

    if (mounted) {
      setState(() => _hasPermission = isGranted);
      
      if (!isGranted) {
        _showPermissionRationaleDialog();
      } else {
        if (_currentLibraryCategory != null) {
          _fetchLibraryInBackground(_currentLibraryCategory!);
        } else if (!_isAtHome) {
          await _loadDirectory(_currentDir, isSilentRefresh: true);
        }
        _prewarmLibraries(); 
      }
    }
  }

  void _showPermissionRationaleDialog() {
    if (_isPromptingPermission) return;
    _isPromptingPermission = true;

    final isDark = context.read<ThemeState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Row(
          children: [
            const Icon(Icons.folder_special, color: Colors.blueAccent),
            const SizedBox(width: 12),
            Text('All Files Access Required', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'To provide a complete desktop experience, Win11 PC Launcher includes a built-in File Explorer ("This PC").\n\nThe launcher requires "All Files Access" to allow you to browse, manage, rename, and delete media and non-media documents (such as PDFs, Word files, and ZIP archives) across your device\'s internal storage.\n\nTap "Continue" to grant this permission in Android Settings.',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _isPromptingPermission = false;
              Navigator.pop(ctx);
            },
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              bool granted = await _requestStoragePermissionGracefully();
              _isPromptingPermission = false;
              if (granted && mounted) {
                _checkPermissionAndPrompt();
              }
            },
            child: const Text('Continue', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).then((_) {
      _isPromptingPermission = false;
    });
  }

  Future<bool> _requestStoragePermissionGracefully() async {
    bool isGranted = false;

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      
      if (androidInfo.version.sdkInt >= 30) {
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
        }
        isGranted = status.isGranted;
      } else {
        final status = await Permission.storage.request();
        isGranted = status.isGranted;
      }
    }

    if (isGranted) {
      if (mounted) setState(() => _hasPermission = true);
      return true;
    }
    return false;
  }

  void _prewarmLibraries() async {
    await Future.delayed(const Duration(seconds: 5));

    const categories = ['Pictures', 'Documents', 'Music', 'Videos'];
    for (final cat in categories) {
      if (!_globalLibraryCache.containsKey(cat)) {
        await _fetchLibraryInBackground(cat);
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  String? _detectLibraryCategory(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('/pictures') || lower.endsWith('/dcim') || lower == 'library:pictures' || lower == 'lib:pictures') return 'Pictures';
    if (lower.endsWith('/music') || lower == 'library:music' || lower == 'lib:music') return 'Music';
    if (lower.endsWith('/movies') || lower.endsWith('/videos') || lower == 'library:videos' || lower == 'lib:videos') return 'Videos';
    if (lower.endsWith('/documents') || lower == 'library:documents' || lower == 'lib:documents') return 'Documents';
    return null;
  }

  Future<void> _loadDirectorySafe(String path, {bool isBack = false}) async {
    if (!_hasPermission) {
      _showPermissionRationaleDialog();
      return;
    }

    if (!isBack) {
      _pathHistory.add(_isAtHome ? 'HOME' : (_currentLibraryCategory != null ? 'LIB:$_currentLibraryCategory' : _currentDir.path));
    }

    final detectedLib = _detectLibraryCategory(path);
    if (detectedLib != null && _isAggregatedView) {
      await _loadSmartLibrary(detectedLib);
      return;
    }

    setState(() {
      _currentLibraryCategory = null;
      _isProcessingFiles = true; 
      _isViewingCloud = false; 
    });

    final dir = Directory(path);
    if (!(await dir.exists())) {
      try { 
        await dir.create(recursive: true); 
      } catch (e) {
         setState(() => _isProcessingFiles = false);
         if (mounted) context.read<AppsState>().highlightFileName = null; // Clear stuck flag
         _showToast("Cannot access or create folder at this path."); 
         return;
      }
    }
    await _loadDirectory(dir);
  }

  Future<void> _processFilesAsync({bool force = false}) async {
     if (!mounted) return;
     final appsState = context.read<AppsState>();
     final desktopState = context.read<DesktopState>();
     
     final query = _searchController.text.toLowerCase();
     final sortBy = appsState.explorerSortBy;
     final sortAsc = appsState.explorerSortAscending;
     final showHidden = desktopState.showHiddenFiles;
     
     if (!force && query == _lastQuery && sortBy == _lastSortBy && sortAsc == _lastSortAsc && showHidden == _lastShowHidden) {
       return;
     }
     
     _lastQuery = query; _lastSortBy = sortBy; _lastSortAsc = sortAsc; _lastShowHidden = showHidden;
     
     if (mounted) setState(() => _isProcessingFiles = true);

     if (_isAtHome) {
         if (query.isEmpty) {
             if (mounted) setState(() {
                 _processedFiles = [];
                 _isProcessingFiles = false;
             });
             return;
         }
         try {
             final media = await NativeBridge.instance.searchMedia(query);
             List<FileItem> searchResults = [];
             if (media != null) {
                 for (var entry in media.entries) {
                     for (var item in entry.value) {
                         searchResults.add(FileItem(
                             path: item['path'],
                             isDir: false,
                             size: 0,
                             modified: DateTime.now(),
                         ));
                     }
                 }
             }
             if (mounted) {
                 setState(() {
                     _processedFiles = searchResults;
                     _isProcessingFiles = false;
                 });
             }
         } catch (_) {
             if (mounted) setState(() { _processedFiles = []; _isProcessingFiles = false; });
         }
         return;
     }
     
     try {
       final result = await compute(_isolateProcessFiles, {
         'files': _files,
         'query': query,
         'sortBy': sortBy,
         'sortAscending': sortAsc,
         'showHidden': showHidden,
       });
       
       if (mounted) {
         setState(() {
           _processedFiles = result;
           _isProcessingFiles = false;
         });
       }
     } catch (e) {
       debugPrint("Search indexing error: $e");
       if (mounted) {
         setState(() {
           _processedFiles = _files; 
           _isProcessingFiles = false;
         });
       }
     }
  }

  Future<void> _loadSmartLibrary(String category) async {
    final bool hasCache = _globalLibraryCache.containsKey(category);

    setState(() {
      _isAtHome = false;
      _isViewingCloud = false;
      _currentLibraryCategory = category;
      _currentDir = Directory('$_rootPath/$category');
      _selectedPaths.clear();
      _isMultiSelectMode = false;
      
      if (hasCache) {
        _files = _globalLibraryCache[category]!;
        _isLoadingLibrary = false;
      } else {
        _isLoadingLibrary = true;
        _files = [];
      }
    });

    if (hasCache) _processFilesAsync(force: true);

    final lastSync = _globalLibrarySyncTime[category];
    final isFresh = lastSync != null && DateTime.now().difference(lastSync).inMinutes < 5;

    if (!hasCache || !isFresh) {
       await _fetchLibraryInBackground(category);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final highlight = context.read<AppsState>().highlightFileName;
      if (highlight != null && highlight.isNotEmpty) {
         context.read<AppsState>().highlightFileName = null;
         setState(() => _activeHighlightName = highlight); 
         
         String targetPath = '$_rootPath/$category/$highlight';
         final matchIdx = _files.indexWhere((f) => f.path.split('/').last == highlight);
         if (matchIdx != -1) {
           targetPath = _files[matchIdx].path;
         }
         
         _blinkSelection(targetPath);
      }
    });
  }

  Future<void> _fetchLibraryInBackground(String category) async {
    try {
      final items = await compute(FileSystemService.scanAggregatedMediaIsolate, {
        'rootPath': _rootPath,
        'category': category,
      });

      _globalLibraryCache[category] = items;
      _globalLibrarySyncTime[category] = DateTime.now();

      if (mounted && _currentLibraryCategory == category) {
        setState(() {
          _files = items;
          _isLoadingLibrary = false;
          _selectedPaths.removeWhere((p) => !items.any((f) => f.path == p));
          if (_selectedPaths.isEmpty) _isMultiSelectMode = false;
        });
        _processFilesAsync(force: true);
      }
    } catch (e) {
      if (mounted && _currentLibraryCategory == category) {
        setState(() => _isLoadingLibrary = false);
      }
    }
  }

  Future<void> _loadDirectory(Directory dir, {bool isSilentRefresh = false}) async {
    if (!isSilentRefresh && mounted) {
      setState(() => _isProcessingFiles = true);
    }

    try {
      final items = await FileSystemService.getDirectoryContentsNative(dir.path);
      
      if (dir.path == '$_rootPath/Desktop' && _desktopState != null) {
        for (var item in _desktopState!.desktopItems) {
          if (item.type == 'app' && item.package != null) {
            items.add(FileItem(path: 'virtual_app://${item.package}/${item.label}', isDir: false, size: 0, modified: DateTime.now()));
          } else if (item.type == 'system') {
            items.add(FileItem(path: 'virtual_system://${item.id}/${item.label}', isDir: false, size: 0, modified: DateTime.now()));
          } else if (item.type == 'folder') {
            items.add(FileItem(path: 'virtual_folder://${item.id}/${item.label}', isDir: true, size: 0, modified: DateTime.now(), itemCount: item.folderApps?.length ?? 0));
          }
        }
      }

      if (mounted) {
        setState(() {
          _isAtHome = false;
          _currentDir = dir;
          _currentLibraryCategory = null;
          _files = items;
          
          if (!isSilentRefresh) {
            _selectedPaths.clear();
            _isMultiSelectMode = false;
            _isContextMenuOpen = false;
          } else {
            _selectedPaths.removeWhere((p) => !items.any((f) => f.path == p));
            if (_selectedPaths.isEmpty) _isMultiSelectMode = false;
          }
        });
        
        _processFilesAsync(force: true);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final highlight = context.read<AppsState>().highlightFileName;
          if (highlight != null && highlight.isNotEmpty) {
             context.read<AppsState>().highlightFileName = null;
             setState(() => _activeHighlightName = highlight);
             
             String targetPath = '${dir.path}/$highlight';
             final matchIdx = _files.indexWhere((f) => f.path.split('/').last == highlight);
             if (matchIdx != -1) {
               targetPath = _files[matchIdx].path;
             }

             _blinkSelection(targetPath);
          }
        });
      }
    } catch (e) {
      debugPrint("Error reading directory: $e");
      if (mounted) {
        setState(() => _isProcessingFiles = false);
        context.read<AppsState>().highlightFileName = null;
      }
    }
  }

  void _goHome({bool isBack = false}) {
    if (!isBack && !_isAtHome) {
      _pathHistory.add(_currentLibraryCategory != null ? 'LIB:$_currentLibraryCategory' : _currentDir.path);
    }

    context.read<AppsState>().highlightFileName = null; 
    _activeHighlightName = null; 
    _searchController.clear(); 

    setState(() {
      _isAtHome = true;
      _isViewingCloud = false; 
      _currentLibraryCategory = null;
      _currentDir = Directory(_rootPath);
      _selectedPaths.clear();
      _isMultiSelectMode = false;
      _isContextMenuOpen = false;
    });
  }

  bool goBack() {
    if (_isViewingCloud) {
      final cloudState = context.read<CloudDriveState>();
      if (cloudState.gDrivePathStack.isEmpty) {
        setState(() => _isViewingCloud = false);
      } else {
        cloudState.gDrivePathStack.removeLast();
        final targetId = cloudState.gDrivePathStack.isEmpty ? 'root' : cloudState.gDrivePathStack.last['id'];
        cloudState.openDrive('gdrive', folderId: targetId, isBack: true);
      }
      return true;
    }

    if (_pathHistory.isEmpty) return false;
    String prev = _pathHistory.removeLast();
    _activeHighlightName = null;

    if (prev == 'HOME') {
      _goHome(isBack: true);
    } else if (prev.startsWith('LIB:')) {
      _loadSmartLibrary(prev.substring(4));
    } else {
      _loadDirectorySafe(prev, isBack: true);
    }
    return true;
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(fontSize: 13)), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))));
  }

  Future<void> _consolidateLibraryFiles() async {
    if (_currentLibraryCategory == null || _files.isEmpty) return;

    final targetDirPath = '$_rootPath/$_currentLibraryCategory';
    final targetDir = Directory(targetDirPath);
    if (!targetDir.existsSync()) targetDir.createSync(recursive: true);

    final isDark = context.read<ThemeState>().isDarkMode;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        title: Text('Sync to $_currentLibraryCategory?', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'This will copy ${_files.length} ${_currentLibraryCategory!.toLowerCase()} files from scattered folders into "$targetDirPath".',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start Sync', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))),
        ],
      )
    );

    if (confirm != true) return;

    _showToast('Syncing files to $_currentLibraryCategory...');
    final Map<String, dynamic> args = {
       'files': _files.map((f) => f.path).toList(),
       'targetDirPath': targetDirPath,
    };

    final copied = await compute(_isolateCopyFiles, args);
    if (!mounted) return;

    _showToast('Synced $copied new files to $_currentLibraryCategory');
  }

  void _createNewFolder() async {
    final isDark = context.read<ThemeState>().isDarkMode;
    final String? folderName = await showDialog<String>(
      context: context, builder: (ctx) => SafeInputDialog(title: 'New Folder', initialText: 'New Folder', hintText: 'Folder name', actionText: 'Create', isDark: isDark),
    );

    if (folderName != null && folderName.trim().isNotEmpty) {
      try {
        final targetBase = _currentLibraryCategory != null ? '$_rootPath/$_currentLibraryCategory' : _currentDir.path;
        final newDir = Directory('$targetBase/${folderName.trim()}');
        if (!(await newDir.exists())) await newDir.create();
        
        if (!mounted) return;
        if (_currentLibraryCategory != null) {
          _globalLibraryCache.remove(_currentLibraryCategory);
          _loadSmartLibrary(_currentLibraryCategory!);
        } else {
          await _loadDirectory(_currentDir);
        }
        _showToast('Folder created');
      } catch (_) { 
        if (mounted) _showToast('Permission denied'); 
      }
    }
  }

  void _renameFile() async {
    if (_selectedPaths.isEmpty) return;
    if (_selectedPaths.any((p) => p.startsWith('virtual_'))) {
      _showToast('Shortcuts and Apps must be managed on the Desktop Grid.');
      return;
    }
    if (_selectedPaths.length != 1) return;
    final isDark = context.read<ThemeState>().isDarkMode;
    final entityPath = _selectedPaths.first;
    String oldName = entityPath.split('/').last;

    final String? newName = await showDialog<String>(
      context: context, builder: (ctx) => SafeInputDialog(title: 'Rename', initialText: oldName, hintText: 'New name', actionText: 'Rename', isDark: isDark),
    );

    if (newName != null && newName.trim().isNotEmpty && newName != oldName) {
      try {
        final isDir = await FileSystemEntity.isDirectory(entityPath);
        final entity = isDir ? Directory(entityPath) : File(entityPath);
        final parentDir = entity.parent.path;
        
        final String newFullPath = '$parentDir/${newName.trim()}';
        await entity.rename(newFullPath);
        
        for (int i = 0; i < _pathHistory.length; i++) {
           if (_pathHistory[i] == entityPath) {
               _pathHistory[i] = newFullPath;
           } else if (_pathHistory[i].startsWith('$entityPath/')) {
               _pathHistory[i] = _pathHistory[i].replaceFirst(entityPath, newFullPath);
           }
        }
        
        if (!mounted) return;
        if (_currentLibraryCategory != null) {
          _globalLibraryCache.remove(_currentLibraryCategory); 
          _loadSmartLibrary(_currentLibraryCategory!);
        } else {
          await _loadDirectory(_currentDir);
        }
        _showToast('Renamed to ${newName.trim()}');
      } catch (_) { 
        if (mounted) _showToast('Cannot rename protected file'); 
      }
    }
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedPaths.isEmpty) return;
    if (_selectedPaths.any((p) => p.startsWith('virtual_'))) {
      _showToast('Shortcuts and Apps must be managed on the Desktop Grid.');
      return;
    }

    final isDark = context.read<ThemeState>().isDarkMode;
    final bool isRecycleBin = _currentDir.path == _recycleBinPath;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(isRecycleBin ? 'Delete permanently?' : 'Move to Recycle Bin?', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          isRecycleBin 
             ? 'Permanently delete ${_selectedPaths.length} item(s)? This cannot be undone.'
             : 'Move ${_selectedPaths.length} item(s) to the Recycle Bin? (Auto-deleted after 7 days)', 
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13)
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(isRecycleBin ? 'Delete' : 'Move', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
        ],
      )
    );

    if (confirm != true) return;

    int movedOrDeleted = 0;

    if (isRecycleBin) {
      movedOrDeleted = await compute(_isolateDeletePermanently, {
        'selectedPaths': _selectedPaths.toList(),
        'binPath': _recycleBinPath,
      });
    } else {
      final copiedPaths = await compute(_isolateCopyToRecycleBin, {
        'selectedPaths': _selectedPaths.toList(),
        'binPath': _recycleBinPath,
      });

      for (String path in copiedPaths) {
        final success = await NativeBridge.instance.deleteFile(path);
        if (success) movedOrDeleted++;
      }
    }

    if (!mounted) return;

    if (_currentLibraryCategory != null) {
      _globalLibraryCache.remove(_currentLibraryCategory);
      _loadSmartLibrary(_currentLibraryCategory!);
    } else {
      await _loadDirectory(_currentDir);
    }
    _showToast(isRecycleBin ? 'Deleted items permanently' : 'Moved $movedOrDeleted items to Recycle Bin');
  }

  Future<void> _pasteFile() async {
    final appsState = context.read<AppsState>();
    if (appsState.clipboardPath != null) {
      try {
        final sourcePath = appsState.clipboardPath!;
        final isDir = await FileSystemEntity.isDirectory(sourcePath);
        final entity = isDir ? Directory(sourcePath) : File(sourcePath);
        final name = sourcePath.split('/').last;
        final targetBase = _currentLibraryCategory != null ? '$_rootPath/$_currentLibraryCategory' : _currentDir.path;
        final newPath = '$targetBase/$name';
        
        if (entity is File) {
          await entity.copy(newPath);
          if (appsState.isCut) await entity.delete();
        } else if (entity is Directory) {
          if (appsState.isCut) { 
            try {
              await entity.rename(newPath); 
            } catch (_) {
              await compute(FileSystemService.isolateCopyDirectory, {'source': entity.path, 'destination': newPath});
              await entity.delete(recursive: true);
            }
          } else { 
            await compute(FileSystemService.isolateCopyDirectory, {'source': entity.path, 'destination': newPath});
          }
        }
        
        if (!mounted) return;
        if (appsState.isCut) appsState.clearClipboard();
        
        if (_currentLibraryCategory != null) {
          _globalLibraryCache.remove(_currentLibraryCategory);
          _loadSmartLibrary(_currentLibraryCategory!);
        } else {
          await _loadDirectory(_currentDir);
        }
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

  Widget _buildContextMenuItem(String title, IconData? icon, ThemeState themeState, {Color? iconColor, bool hasSubMenu = false, VoidCallback? onTap}) {
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final defaultIconColor = isDark ? Colors.white : Colors.black87;
    return InkWell(
      onTap: () {
        if (onTap != null) onTap();
        if (!hasSubMenu) _closeOverlays();
      },
      hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            if (icon != null) Icon(icon, size: 16, color: iconColor ?? defaultIconColor), if (icon != null) const SizedBox(width: 12),
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, color: textColor))),
            if (hasSubMenu) Icon(_activeSubMenu == title.toLowerCase().replaceAll(' ', '_') ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: isDark ? Colors.white54 : Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  Widget _buildSubMenuItem(String title, IconData? icon, ThemeState themeState, {bool isDot = false, VoidCallback? onTap}) {
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    return InkWell(
      onTap: () { 
        if (onTap != null) onTap(); 
        _closeOverlays(); 
      },
      hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 16, child: isDot ? Icon(Icons.circle, size: 6, color: textColor) : null),
            const SizedBox(width: 8),
            if (icon != null) Icon(icon, size: 16, color: textColor),
            if (icon != null) const SizedBox(width: 10),
            Expanded(child: Text(title, style: TextStyle(fontSize: 12, color: textColor))),
          ],
        ),
      ),
    );
  }

  void _showPropertiesDialog() async {
    if (_selectedPaths.length != 1) return;
    try {
      final isDark = context.read<ThemeState>().isDarkMode;
      final pathStr = _selectedPaths.first;
      final isDir = await FileSystemEntity.isDirectory(pathStr);
      final entity = isDir ? Directory(pathStr) : File(pathStr);
      
      int sizeBytes = 0;
      if (isDir) {
        sizeBytes = await compute(_calculateDirectorySize, pathStr);
      } else {
        final stat = await entity.stat();
        sizeBytes = stat.size;
      }
      
      final stat = await entity.stat();
      final modified = stat.modified.toString().split('.')[0];
      final name = entity.path.split('/').last;

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
          title: Text('$name Properties', style: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black87)),
          content: Column(
            mainAxisSize: MainAxisSize.min, // <--- Added the comma here!
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Type: ${isDir ? 'File Folder' : 'File'}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)), const SizedBox(height: 8),
              Text('Location: ${entity.path}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)), const SizedBox(height: 8),
              Text('Size: ${(sizeBytes / 1024).toStringAsFixed(2)} KB', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)), const SizedBox(height: 8),
              Text('Modified: $modified', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Colors.blueAccent)))],
        )
      );
    } catch (_) { _showToast('Could not read properties'); }
  }

  Widget _buildContextMenuOverlay(ThemeState themeState, AppsState appsState) {
    if (!_isContextMenuOpen) return const SizedBox.shrink();

    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B).withOpacity(0.95) : const Color(0xFFF3F3F3).withOpacity(0.95);
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;

    double menuWidth = 240;
    double dx = _contextMenuPos.dx;
    double dy = _contextMenuPos.dy;

    final windowSize = MediaQuery.of(context).size;

    if (dx + menuWidth > windowSize.width) dx = windowSize.width - menuWidth - 8;
    if (dx < 8) dx = 8;

    double estimatedHeight = _contextMenuType == 'desktop' ? (_activeSubMenu != null ? 350 : 180) : 280;
    if (dy + estimatedHeight > windowSize.height) dy = windowSize.height - estimatedHeight - 8;
    if (dy < 8) dy = 8;

    return Stack(
      children: [
        Positioned(
          left: dx,
          top: dy,
          child: Container(
            width: menuWidth,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _contextMenuType == 'desktop'
                ? [
                    _buildContextMenuItem('View', Icons.grid_view, themeState, hasSubMenu: true, onTap: () {
                      setState(() => _activeSubMenu = _activeSubMenu == 'view' ? null : 'view');
                    }),
                    if (_activeSubMenu == 'view')
                      Container(
                        color: isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          children: [
                            _buildSubMenuItem('Large icons', Icons.crop_square, themeState, isDot: appsState.explorerViewType == 'Large Icons', onTap: () => appsState.updateExplorerView('Large Icons')),
                            _buildSubMenuItem('Medium icons', Icons.crop_7_5, themeState, isDot: appsState.explorerViewType == 'Medium Icons', onTap: () => appsState.updateExplorerView('Medium Icons')),
                            _buildSubMenuItem('Small icons', Icons.grid_view, themeState, isDot: appsState.explorerViewType == 'Small Icons', onTap: () => appsState.updateExplorerView('Small Icons')),
                            _buildSubMenuItem('List', Icons.format_list_bulleted, themeState, isDot: appsState.explorerViewType == 'List', onTap: () => appsState.updateExplorerView('List')),
                          ],
                        ),
                      ),
                    
                    _buildContextMenuItem('Sort by', Icons.swap_vert, themeState, hasSubMenu: true, onTap: () {
                      setState(() => _activeSubMenu = _activeSubMenu == 'sort' ? null : 'sort');
                    }),
                    if (_activeSubMenu == 'sort')
                      Container(
                        color: isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          children: [
                            _buildSubMenuItem('Name', null, themeState, isDot: appsState.explorerSortBy == 'Name', onTap: () => appsState.updateExplorerSort('Name', appsState.explorerSortAscending)),
                            _buildSubMenuItem('Type', null, themeState, isDot: appsState.explorerSortBy == 'Type', onTap: () => appsState.updateExplorerSort('Type', appsState.explorerSortAscending)),
                            _buildSubMenuItem('Date modified', null, themeState, isDot: appsState.explorerSortBy == 'Date modified', onTap: () => appsState.updateExplorerSort('Date modified', appsState.explorerSortAscending)),
                            _buildSubMenuItem('Size', null, themeState, isDot: appsState.explorerSortBy == 'Size', onTap: () => appsState.updateExplorerSort('Size', appsState.explorerSortAscending)),
                          ],
                        ),
                      ),
                    
                    _buildContextMenuItem('Refresh', Icons.refresh, themeState, onTap: () {
                      if (_currentLibraryCategory != null) {
                        _globalLibraryCache.remove(_currentLibraryCategory); 
                        _loadSmartLibrary(_currentLibraryCategory!);
                      } else {
                        _loadDirectory(_currentDir);
                      }
                      _showToast('Refreshed');
                    }),
                  ]
                : _contextMenuType == 'cloud_file' 
                  ? [
                      _buildContextMenuItem('Open', Icons.open_in_new, themeState, iconColor: Colors.blueAccent, onTap: () {
                      final cloudState = context.read<CloudDriveState>();
                      final targetId = _selectedPaths.isNotEmpty ? _selectedPaths.first : '';
                      final targetFile = cloudState.currentCloudFiles.firstWhere((f) => f.id == targetId, orElse: () => CloudFile(id: '', name: '', path: '', isFolder: false, size: 0, provider: ''));
                      
                      if (targetFile.isFolder) {
                        cloudState.openDrive(cloudState.activeProvider, folderId: targetFile.id, folderName: targetFile.name);
                      } else {
                        // NEW LOGIC: Download and open from Right-Click / Long-Press menu
                        _showToast('Fetching ${targetFile.name}...');
                        cloudState.downloadCloudFile(targetFile.id, targetFile.name).then((localPath) {
                          if (localPath != null && mounted) {
                            NativeBridge.instance.openFile(localPath);
                          } else if (mounted) {
                            _showToast('Failed to open ${targetFile.name}');
                          }
                        });
                      }
                    }),
                      _buildContextMenuItem('Delete', Icons.delete_outline, themeState, iconColor: Colors.redAccent, onTap: () async {
                        _showToast('Deleting $_contextTargetName...');
                        final cloudState = context.read<CloudDriveState>();
                        await cloudState.deleteFile(_selectedPaths.first);
                        _showToast('$_contextTargetName deleted');
                      }),
                      Container(height: 1, color: borderColor, margin: const EdgeInsets.symmetric(vertical: 4)),
                      _buildContextMenuItem('Properties', Icons.build_circle_outlined, themeState, onTap: () {
                        _showToast('$_contextTargetName properties');
                      }),
                    ]
                  : [
                      // Standard local file options
                      _buildContextMenuItem('Open', Icons.open_in_new, themeState, iconColor: Colors.blueAccent, onTap: () {
                      final cloudState = context.read<CloudDriveState>();
                      final targetId = _selectedPaths.isNotEmpty ? _selectedPaths.first : '';
                      final targetFile = cloudState.currentCloudFiles.firstWhere((f) => f.id == targetId, orElse: () => CloudFile(id: '', name: '', path: '', isFolder: false, size: 0, provider: ''));
                      
                      if (targetFile.isFolder) {
                        cloudState.openDrive(cloudState.activeProvider, folderId: targetFile.id, folderName: targetFile.name);
                      } else {
                        // NEW LOGIC: Download and open from Right-Click / Long-Press menu
                        _showToast('Fetching ${targetFile.name}...');
                        cloudState.downloadCloudFile(targetFile.id, targetFile.name).then((localPath) {
                          if (localPath != null && mounted) {
                            NativeBridge.instance.openFile(localPath);
                          } else if (mounted) {
                            _showToast('Failed to open ${targetFile.name}');
                          }
                        });
                      }
                    }),
                      _buildContextMenuItem('Share', Icons.share_outlined, themeState, onTap: () {
                        if (_selectedPaths.isNotEmpty) NativeBridge.instance.shareFile(_selectedPaths.first);
                      }),
                      _buildContextMenuItem('Properties', Icons.build_circle_outlined, themeState, onTap: () => _showPropertiesDialog()),
                      Container(height: 1, color: borderColor, margin: const EdgeInsets.symmetric(vertical: 4)),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            InkWell(
                              onTap: () { _closeOverlays(); appsState.setClipboard(_selectedPaths.first, true); _showToast('Cut'); }, 
                              child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.content_cut, size: 18, color: const Color(0xFF0078D4)), const SizedBox(height: 4), Text('Cut', style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87))])
                            ),
                            InkWell(
                              onTap: () { _closeOverlays(); appsState.setClipboard(_selectedPaths.first, false); _showToast('Copied'); }, 
                              child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.content_copy, size: 18, color: const Color(0xFF0078D4)), const SizedBox(height: 4), Text('Copy', style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87))])
                            ),
                            InkWell(
                              onTap: () { _closeOverlays(); _renameFile(); }, 
                              child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.drive_file_rename_outline, size: 18, color: const Color(0xFF0078D4)), const SizedBox(height: 4), Text('Rename', style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87))])
                            ),
                            InkWell(
                              onTap: () { _closeOverlays(); _deleteSelectedFiles(); }, 
                              child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.delete_outline, size: 18, color: const Color(0xFF0078D4)), const SizedBox(height: 4), Text('Delete', style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87))])
                            ),
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

  // --- CLOUD UI RENDERER (RESPONSIVE) ---

  Widget _getCloudFileIcon(CloudFile file, double size) {
    if (file.isFolder) {
      return Icon(Icons.folder, size: size, color: Colors.amber);
    }
    
    if (file.thumbnailLink != null && file.thumbnailLink!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          file.thumbnailLink!, 
          width: size, 
          height: size, 
          fit: BoxFit.cover, 
          errorBuilder: (_, __, ___) => _getFallbackCloudIcon(file.name, size)
        ),
      );
    }
    
    return _getFallbackCloudIcon(file.name, size);
  }

  Widget _getFallbackCloudIcon(String name, double size) {
    final nameLower = name.toLowerCase();
    if (nameLower.endsWith('.pdf')) return Icon(Icons.picture_as_pdf, size: size, color: Colors.redAccent);
    if (nameLower.endsWith('.mp4') || nameLower.endsWith('.mkv') || nameLower.endsWith('.avi')) return Icon(Icons.video_file, size: size, color: Colors.purpleAccent);
    if (nameLower.endsWith('.mp3') || nameLower.endsWith('.wav') || nameLower.endsWith('.ogg')) return Icon(Icons.audio_file, size: size, color: Colors.amber);
    if (nameLower.endsWith('.zip') || nameLower.endsWith('.rar') || nameLower.endsWith('.7z')) return Icon(Icons.folder_zip, size: size, color: Colors.orangeAccent);
    if (nameLower.endsWith('.doc') || nameLower.endsWith('.docx')) return Icon(Icons.description, size: size, color: Colors.blue);
    if (nameLower.endsWith('.xls') || nameLower.endsWith('.xlsx') || nameLower.endsWith('.csv')) return Icon(Icons.table_chart, size: size, color: Colors.green);
    if (nameLower.endsWith('.png') || nameLower.endsWith('.jpg') || nameLower.endsWith('.jpeg')) return Icon(Icons.image, size: size, color: Colors.blueAccent);
    
    return Icon(Icons.insert_drive_file, size: size, color: Colors.blueGrey);
  }

  Widget _buildCloudFileGrid(CloudDriveState cloudState, ThemeState themeState, AppsState appsState) {
    if (cloudState.isLoading) return const Center(child: CircularProgressIndicator(color: Colors.blueAccent));
    if (cloudState.currentCloudFiles.isEmpty) return Center(child: Text('This folder is empty.', style: TextStyle(color: themeState.isDarkMode ? Colors.white70 : Colors.black54)));

    final viewType = appsState.explorerViewType;
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;

    if (viewType == 'List') {
      return ListView.separated(
        padding: const EdgeInsets.all(8),
        physics: const BouncingScrollPhysics(),
        itemCount: cloudState.currentCloudFiles.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade200),
        itemBuilder: (itemContext, index) {
          final file = cloudState.currentCloudFiles[index];
          final sizeStr = file.isFolder ? '' : '${(file.size / 1024).toStringAsFixed(1)} KB';
          final dateStr = file.modifiedTime != null 
              ? "${file.modifiedTime!.year}-${file.modifiedTime!.month.toString().padLeft(2, '0')}-${file.modifiedTime!.day.toString().padLeft(2, '0')}" 
              : '';
              
          return GestureDetector(
            onSecondaryTapDown: (details) {
              final RenderBox box = context.findRenderObject() as RenderBox;
              setState(() { 
                _contextMenuPos = box.globalToLocal(details.globalPosition); 
                _contextMenuType = 'cloud_file'; 
                _contextTargetName = file.name; 
                _selectedPaths = {file.id}; // Temporarily use ID for selection
                _isContextMenuOpen = true; 
              });
            },
            onLongPressStart: (details) {
              final RenderBox box = context.findRenderObject() as RenderBox;
              setState(() { 
                _contextMenuPos = box.globalToLocal(details.globalPosition); 
                _contextMenuType = 'cloud_file'; 
                _contextTargetName = file.name; 
                _selectedPaths = {file.id};
                _isContextMenuOpen = true; 
              });
            },
            child: InkWell(
              onTap: () {
              if (file.isFolder) {
                cloudState.openDrive(cloudState.activeProvider, folderId: file.id, folderName: file.name);
              } else {
                // NEW LOGIC: Actually download and open the file
                _showToast('Fetching ${file.name}...');
                cloudState.downloadCloudFile(file.id, file.name).then((localPath) {
                  if (localPath != null && mounted) {
                    NativeBridge.instance.openFile(localPath);
                  } else if (mounted) {
                    _showToast('Failed to open ${file.name}');
                  }
                });
              }
            },
              hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    _getCloudFileIcon(file, 24),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: Text(file.name, style: TextStyle(color: textColor, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 2, child: Text(dateStr, style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 11))),
                    Expanded(flex: 1, child: Text(sizeStr, style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 11), textAlign: TextAlign.right)),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    double extent = 100;
    double iconSize = 48;
    double fontSize = 11;
    
    switch (viewType) {
      case 'Extra Large Icons': extent = 200; iconSize = 120; fontSize = 13; break;
      case 'Large Icons': extent = 140; iconSize = 80; fontSize = 12; break;
      case 'Small Icons': extent = 80; iconSize = 32; fontSize = 10; break;
      case 'Medium Icons': 
      default: extent = 100; iconSize = 48; fontSize = 11; break;
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: extent, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.85,
      ),
      itemCount: cloudState.currentCloudFiles.length,
      itemBuilder: (itemContext, index) {
        final file = cloudState.currentCloudFiles[index];
        return GestureDetector(
          onSecondaryTapDown: (details) {
            final RenderBox box = context.findRenderObject() as RenderBox;
            setState(() { 
              _contextMenuPos = box.globalToLocal(details.globalPosition); 
              _contextMenuType = 'cloud_file'; 
              _contextTargetName = file.name; 
              _selectedPaths = {file.id};
              _isContextMenuOpen = true; 
            });
          },
          onLongPressStart: (details) {
            final RenderBox box = context.findRenderObject() as RenderBox;
            setState(() { 
              _contextMenuPos = box.globalToLocal(details.globalPosition); 
              _contextMenuType = 'cloud_file'; 
              _contextTargetName = file.name; 
              _selectedPaths = {file.id};
              _isContextMenuOpen = true; 
            });
          },
          child: InkWell(
            onTap: () {
              if (file.isFolder) {
                cloudState.openDrive(cloudState.activeProvider, folderId: file.id, folderName: file.name);
              } else {
                // NEW LOGIC: Actually download and open the file
                _showToast('Fetching ${file.name}...');
                cloudState.downloadCloudFile(file.id, file.name).then((localPath) {
                  if (localPath != null && mounted) {
                    NativeBridge.instance.openFile(localPath);
                  } else if (mounted) {
                    _showToast('Failed to open ${file.name}');
                  }
                });
              }
            },
            borderRadius: BorderRadius.circular(6),
            hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _getCloudFileIcon(file, iconSize),
                const SizedBox(height: 8),
                Text(
                  file.name, 
                  style: TextStyle(fontSize: fontSize, color: textColor), 
                  maxLines: 2, 
                  overflow: TextOverflow.ellipsis, 
                  textAlign: TextAlign.center
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF191919) : Colors.white;

    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: bgColor, 
        body: const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
      );
    }

    final appsState = context.watch<AppsState>();
    final desktopState = context.watch<DesktopState>();
    final screenWidth = MediaQuery.of(context).size.width;
    final sidebarWidth = math.max(130.0, screenWidth * (_sidebarWidthPercent / 100));

    final bool isJumpingToHighlight = appsState.highlightFileName != null && appsState.highlightFileName!.isNotEmpty;

    if (_lastSortBy != appsState.explorerSortBy || _lastSortAsc != appsState.explorerSortAscending || _lastShowHidden != desktopState.showHiddenFiles) {
       Future.microtask(() => _processFilesAsync(force: true));
    }

    List<FileItem> sortedFiles = List.from(_processedFiles);

    final highlight = _activeHighlightName;
    if (highlight != null && highlight.isNotEmpty) {
       final highlightIdx = sortedFiles.indexWhere((f) => f.path.split('/').last == highlight);
       if (highlightIdx != -1) {
          final targetItem = sortedFiles.removeAt(highlightIdx);
          sortedFiles.insert(0, targetItem);
       }
    }

    final String displayAddress = _currentLibraryCategory != null 
        ? 'This PC > $_currentLibraryCategory' 
        : _currentDir.path;

    return Scaffold(
      backgroundColor: bgColor,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(statusBarColor: bgColor, statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark, statusBarBrightness: isDark ? Brightness.dark : Brightness.light),
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.goBack || event.logicalKey == LogicalKeyboardKey.escape)) {
              if (goBack()) return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: _closeOverlays,
            onSecondaryTapDown: (details) { 
              if (_isAtHome || _currentLibraryCategory != null) {
                final RenderBox box = context.findRenderObject() as RenderBox;
                setState(() { _contextMenuPos = box.globalToLocal(details.globalPosition); _contextMenuType = 'desktop'; _isContextMenuOpen = true; }); 
              }
            },
            onLongPressStart: (details) { 
              if (_isAtHome || _currentLibraryCategory != null) {
                final RenderBox box = context.findRenderObject() as RenderBox;
                setState(() { _contextMenuPos = box.globalToLocal(details.globalPosition); _contextMenuType = 'desktop'; _isContextMenuOpen = true; }); 
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
                        ExplorerToolbar(
                          isDark: isDark, 
                          hasSelection: _selectedPaths.isNotEmpty, 
                          isSingleSelection: _selectedPaths.length == 1,
                          canPaste: appsState.clipboardPath != null,
                          onNewFolder: _createNewFolder, 
                          onCut: () { appsState.setClipboard(_selectedPaths.first, true); _showToast('Cut to clipboard'); },
                          onCopy: () { appsState.setClipboard(_selectedPaths.first, false); _showToast('Copied to clipboard'); }, 
                          onPaste: _pasteFile, 
                          onRename: _renameFile, 
                          onDelete: _deleteSelectedFiles, 
                          onShare: () { if (_selectedPaths.isNotEmpty) NativeBridge.instance.shareFile(_selectedPaths.first); },
                        ),
                        
                        if (_currentDir.path == _recycleBinPath || _currentDir.path.contains('.Win11RecycleBin'))
                          Container(
                            height: 32, 
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            color: Colors.redAccent.withOpacity(0.08),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, color: Colors.redAccent, size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text('Items are permanently deleted after 7 days.', 
                                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 11.5),
                                    maxLines: 1, 
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: _emptyRecycleBin,
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.redAccent.withOpacity(0.15),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                    minimumSize: const Size(0, 24), 
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 13),
                                  label: const Text('Empty Bin', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                )
                              ],
                            ),
                          ),

                        if (_currentLibraryCategory != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 16.0, top: 4.0, bottom: 4.0),
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  backgroundColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                                ),
                                onPressed: _consolidateLibraryFiles,
                                icon: const Icon(Icons.sync, size: 14, color: Colors.blueAccent),
                                label: Text('Sync $_currentLibraryCategory to Folder', style: const TextStyle(fontSize: 11, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),

                        ExplorerAddressBar(
                          isDark: isDark, 
                          isAtHome: _isAtHome, 
                          currentPath: displayAddress, 
                          rootPath: _rootPath, 
                          pathHistory: _pathHistory, 
                          searchController: _searchController, 
                          onGoBack: goBack, 
                          onGoHome: _goHome, 
                          onNavigate: (p) => _loadDirectorySafe(p),
                          disks: _disks,
                          isViewingCloud: _isViewingCloud,
                          cloudPathStack: context.watch<CloudDriveState>().gDrivePathStack,
                          cloudProvider: context.watch<CloudDriveState>().activeProvider,
                          onCloudNavigate: (id, name, isBack) {
                            context.read<CloudDriveState>().openDrive(
                              context.read<CloudDriveState>().activeProvider, 
                              folderId: id, folderName: name, isBack: isBack
                            );
                          },
                        ),
                        
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ExplorerSidebar(
                                width: sidebarWidth, 
                                isDark: isDark, 
                                isAtHome: _isAtHome, 
                                rootPath: _rootPath, 
                                currentPath: _currentDir.path,
                                currentLibraryCategory: _currentLibraryCategory,
                                onGoHome: _goHome, 
                                onNavigate: (p) => _loadDirectorySafe(p),
                                disks: _disks,
                                isViewingCloud: _isViewingCloud,
                                
                                // CRITICAL FIX: Make handler async, await the connection, and then sync UI 
                                onGoogleDriveTap: () async {
                                  if (!ProGatekeeper.checkAccess(context, featureName: 'Cloud Drive Mounting')) return;
                                  
                                  setState(() => _isViewingCloud = true);
                                  
                                  final cloudState = context.read<CloudDriveState>();
                                  if (cloudState.isGoogleDriveConnected) {
                                    cloudState.openDrive('gdrive', folderId: 'root');
                                  } else {
                                    final success = await cloudState.connectGoogleDrive();
                                    if (success && mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Google Drive Synced Successfully'))
                                      );
                                    } else if (mounted) {
                                      // Revert to local files if auth failed or user cancelled
                                      setState(() => _isViewingCloud = false); 
                                    }
                                  }
                                },
                                // ==========================================
                              ),
                              Expanded(
                                child: _isLoadingLibrary || _isProcessingFiles || isJumpingToHighlight
                                  ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
                                  : _isViewingCloud 
                                      ? _buildCloudFileGrid(context.watch<CloudDriveState>(), themeState, appsState)
                                      : (_isAtHome && _searchController.text.isEmpty)
                                          ? ExplorerContentView(
                                              isDark: isDark, 
                                              isMobile: screenWidth < 500, 
                                              isAtHome: true, 
                                              rootPath: _rootPath, 
                                              files: sortedFiles,
                                              totalGB: _totalGB, 
                                              freeGB: _freeGB,
                                              selectedPaths: _selectedPaths, 
                                              isMultiSelectMode: _isMultiSelectMode, 
                                              disks: _disks,
                                              onNavigate: (p) => _loadDirectorySafe(p), 
                                              onOpenFile: NativeBridge.instance.openFile,
                                              onSelectionChanged: (paths) => setState(() => _selectedPaths = paths), 
                                              onMultiSelectToggled: (multi) => setState(() => _isMultiSelectMode = multi),
                                              onContextMenu: (pos, type, name, _) {
                                                final RenderBox box = context.findRenderObject() as RenderBox;
                                                setState(() { _contextMenuPos = box.globalToLocal(pos); _contextMenuType = type; _contextTargetName = name; _isContextMenuOpen = true; });
                                              },
                                            )
                                          : ExplorerContentView(
                                              isDark: isDark, 
                                              isMobile: screenWidth < 500, 
                                              isAtHome: false, 
                                              isRecycleBin: _currentDir.path == _recycleBinPath || _currentDir.path.contains('.Win11RecycleBin'),
                                              rootPath: _rootPath, 
                                              files: sortedFiles,
                                              totalGB: _totalGB, 
                                              freeGB: _freeGB,
                                              selectedPaths: _selectedPaths, 
                                              isMultiSelectMode: _isMultiSelectMode, 
                                              disks: _disks,
                                              onNavigate: (p) => _loadDirectorySafe(p), 
                                              onOpenFile: NativeBridge.instance.openFile,
                                              onSelectionChanged: (paths) => setState(() => _selectedPaths = paths), 
                                              onMultiSelectToggled: (multi) => setState(() => _isMultiSelectMode = multi),
                                              onContextMenu: (pos, type, name, _) {
                                                final RenderBox box = context.findRenderObject() as RenderBox;
                                                setState(() { _contextMenuPos = box.globalToLocal(pos); _contextMenuType = type; _contextTargetName = name; _isContextMenuOpen = true; });
                                              },
                                            ),
                              ),
                            ],
                          ),
                        ),
                        ExplorerStatusBar(
                          isDark: isDark, 
                          isAtHome: _isAtHome, 
                          itemCount: sortedFiles.length, 
                          selectedCount: _selectedPaths.length, 
                          sidebarWidthPercent: _sidebarWidthPercent,
                          onWidthChanged: (val) => setState(() => _sidebarWidthPercent = val), 
                        ),
                      ],
                    ),
                  ),
                ),
                _buildContextMenuOverlay(themeState, appsState),
              ],
            ),
          ),
        ),
      ),
    );
  }
}