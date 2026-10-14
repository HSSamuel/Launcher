import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/desktop_state.dart';
import '../../states/theme_state.dart';
import '../../states/apps_state.dart';
import '../../states/cloud_drive_state.dart';
import '../../services/native_bridge.dart';
import '../shared/acrylic_container.dart';

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
    final desktopState = context.read<DesktopState>();
    final accent = themeState.currentAccentColor;
    final btnStyle = IconButton.styleFrom(padding: const EdgeInsets.all(2), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap);
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final inputBg = isDark ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    void playNavSound() {
      if (desktopState.mouseSound) {
        NativeBridge.instance.playSound('mouse');
      }
    }

    List<Widget> breadcrumbs = [];

    if (isViewingCloud) {
      breadcrumbs.add(Container(width: 12, height: 10, color: accent));
      breadcrumbs.add(const SizedBox(width: 4));
      breadcrumbs.add(InkWell(
        onTap: () { playNavSound(); onCloudNavigate?.call('root', 'Google Drive', true); },
        child: Text(cloudProvider == 'gdrive' ? 'GOOGLE DRIVE' : cloudProvider.toUpperCase(), style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600))
      ));
      
      for (var folder in cloudPathStack) {
        breadcrumbs.add(const SizedBox(width: 2));
        breadcrumbs.add(Icon(Icons.chevron_right, size: 14, color: textColor));
        breadcrumbs.add(const SizedBox(width: 2));
        breadcrumbs.add(InkWell(
          onTap: () { playNavSound(); onCloudNavigate?.call(folder['id']!, folder['name']!, true); }, 
          child: Text(folder['name']!, style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600))
        ));
      }
    } else {
      breadcrumbs.add(Container(width: 12, height: 10, color: accent));
      breadcrumbs.add(const SizedBox(width: 4));
      breadcrumbs.add(InkWell(onTap: () { playNavSound(); onGoHome(); }, child: Text('This PC', style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600))));
      breadcrumbs.add(const SizedBox(width: 2));
      breadcrumbs.add(Icon(Icons.chevron_right, size: 14, color: textColor));

      if (!isAtHome) {
        if (currentPath.contains('.Win11RecycleBin')) {
          breadcrumbs.add(const SizedBox(width: 2));
          breadcrumbs.add(InkWell(
            onTap: () { playNavSound(); onNavigate(currentPath); }, 
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
          breadcrumbs.add(InkWell(onTap: () { playNavSound(); onNavigate(basePath); }, child: Text(diskLabel, style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600))));
          breadcrumbs.add(const SizedBox(width: 2));
          breadcrumbs.add(Icon(Icons.chevron_right, size: 14, color: textColor));

          final relativeSubPath = currentPath.replaceFirst(basePath, '');
          final folders = relativeSubPath.split('/').where((e) => e.isNotEmpty).toList();
          String cumulativePath = basePath;

          for (var folder in folders) {
            cumulativePath += '/$folder';
            final targetPath = cumulativePath;
            breadcrumbs.add(const SizedBox(width: 2));
            breadcrumbs.add(InkWell(onTap: () { playNavSound(); onNavigate(targetPath); }, child: Text(folder, style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600))));
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
          IconButton(icon: Icon(Icons.arrow_back, size: 18, color: textColor), onPressed: pathHistory.isEmpty && !isViewingCloud ? null : () { playNavSound(); onGoBack(); }, style: btnStyle), const SizedBox(width: 2),
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

  void _playNavSound() {
    if (context.read<DesktopState>().mouseSound) {
      NativeBridge.instance.playSound('delete');
    }
  }

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
        onTap: () {
          _playNavSound();
          if (onTap != null) onTap();
          else onToggle();
        },
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
        onTap: () {
          _playNavSound();
          if (onTap != null) onTap();
        }, 
        hoverColor: hoverColor,
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
        onTap: () {
          _playNavSound();
          if (onTap != null) onTap();
        }, 
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
          child: Row(children: [const SizedBox(width: 16), Icon(icon, color: color, size: 16), const SizedBox(width: 8), Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: textColor), overflow: TextOverflow.ellipsis))])
        )
      ),
    );
  }

  Widget _buildCloudSidebarItem({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    final cloudState = context.watch<CloudDriveState>();
    final isConnected = cloudState.isGoogleDriveConnected;
    final textColor = widget.isDark ? Colors.white70 : Colors.grey.shade700;
    final selectedBg = widget.isDark ? Colors.white12 : Colors.blue.withOpacity(0.12);

    return Material(
      color: isSelected ? selectedBg : Colors.transparent,
      child: InkWell(
        onTap: () {
          _playNavSound();
          if (onTap != null) onTap();
        },
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Icon(icon, color: color, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            color: textColor,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isConnected && cloudState.currentUserEmail != null)
                          Text(
                            cloudState.currentUserEmail!,
                            style: const TextStyle(fontSize: 9.5, color: Colors.blueAccent),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (isConnected)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, size: 14, color: textColor),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      color: widget.isDark ? const Color(0xFF2B2B2B) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      onSelected: (val) async {
                        if (val == 'switch') {
                          await cloudState.switchGoogleAccount();
                        } else if (val == 'disconnect') {
                          await cloudState.disconnectDrive('gdrive');
                          widget.onGoHome();
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'switch',
                          height: 32,
                          child: Row(
                            children: [
                              Icon(Icons.switch_account, size: 16, color: Colors.blueAccent),
                              SizedBox(width: 8),
                              Text('Switch Account', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'disconnect',
                          height: 32,
                          child: Row(
                            children: [
                              Icon(Icons.logout, size: 16, color: Colors.redAccent),
                              SizedBox(width: 8),
                              Text('Sign Out', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (isSelected)
              Positioned(
                left: 0,
                top: 4,
                bottom: 4,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(3)),
                ),
              ),
          ],
        ),
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
                          onTap: () {
                            _playNavSound();
                            widget.onNavigate(path);
                          }, 
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
                          onTap: () {
                            _playNavSound();
                            widget.onNavigate(widget.rootPath);
                          }, 
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
          _buildCloudSidebarItem(
            context: context,
            label: 'Google Drive',
            icon: Icons.add_to_drive,
            color: Colors.green,
            isSelected: widget.isViewingCloud,
            onTap: widget.onGoogleDriveTap,
          ),
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