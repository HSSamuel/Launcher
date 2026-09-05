import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:installed_apps/installed_apps.dart';

import '../../models/desktop_item_model.dart';
import '../../services/native_bridge.dart';
import '../../launcher_state.dart';

class DesktopContextMenu extends StatefulWidget {
  final bool isOpen;
  final Offset position;
  final String menuType;
  final String targetName;
  final VoidCallback? openAction;
  final VoidCallback onClose;
  final int currentDesktopPage;
  final PageController pageController;
  final Function(String) onEnterResizeMode;

  const DesktopContextMenu({
    Key? key,
    required this.isOpen,
    required this.position,
    required this.menuType,
    required this.targetName,
    this.openAction,
    required this.onClose,
    required this.currentDesktopPage,
    required this.pageController,
    required this.onEnterResizeMode,
  }) : super(key: key);

  @override
  State<DesktopContextMenu> createState() => _DesktopContextMenuState();
}

class _DesktopContextMenuState extends State<DesktopContextMenu> {
  String? _activeSubMenu;
  double _subMenuYOffset = 0;

  @override
  void didUpdateWidget(DesktopContextMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isOpen && widget.isOpen) {
      setState(() => _activeSubMenu = null);
    } else if (oldWidget.targetName != widget.targetName || oldWidget.menuType != widget.menuType) {
      setState(() => _activeSubMenu = null);
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  void _showRenameDialog(DesktopItemModel item, LauncherState state) {
    final controller = TextEditingController(text: item.label);
    final isDark = state.isDarkMode;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text('Rename', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
          decoration: const InputDecoration(
            isDense: true,
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              Navigator.pop(ctx);
              if (newName.isNotEmpty && newName != item.label) {
                Future.delayed(const Duration(milliseconds: 150), () {
                  state.renameDesktopItem(item.id, newName);
                  _showToast('Renamed successfully');
                });
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
    ).then((_) {
      Future.delayed(const Duration(milliseconds: 500), () => controller.dispose());
    });
  }

  void _mockZipCreation(String extension) {
    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (!downloadDir.existsSync()) {
        downloadDir.createSync(recursive: true);
      }
      final newZipPath = '${downloadDir.path}/${widget.targetName}$extension';
      File(newZipPath).createSync();
      _showToast('Successfully compressed to Download/${widget.targetName}$extension');
    } catch (_) {
      _showToast('Storage permission required to compress.');
    }
  }

  void _showPropertiesDialog(LauncherState state) {
    final isDark = state.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.grey.shade800;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('${widget.targetName} Properties', style: TextStyle(fontSize: 15, color: textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: Shortcut / Widget', style: TextStyle(fontSize: 13, color: subTextColor)),
            const SizedBox(height: 8),
            Text('Location: Desktop > ${widget.targetName}', style: TextStyle(fontSize: 13, color: subTextColor)),
            const SizedBox(height: 8),
            Text('Size: ${(12 + widget.targetName.length * 0.5).toStringAsFixed(2)} MB', style: TextStyle(fontSize: 13, color: subTextColor)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Colors.blueAccent)))],
      ),
    );
  }

  void _showAddWidgetDialog(LauncherState state) {
    final isDark = state.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white70 : Colors.black54;

    final availableWidgets = [
      {'type': 'clock', 'name': 'Digital Clock & Date', 'desc': 'Live updating clock with current day/date', 'icon': Icons.access_time},
      {'type': 'weather', 'name': 'Weather Card', 'desc': 'Displays local temperature and sky conditions', 'icon': Icons.wb_sunny_outlined},
      {'type': 'battery', 'name': 'Battery & Power', 'desc': 'Live battery level meter and charging state', 'icon': Icons.battery_charging_full},
      {'type': 'storage', 'name': 'Internal Storage', 'desc': 'Storage capacity bar and remaining free GB', 'icon': Icons.storage},
      {'type': 'calendar', 'name': 'Calendar Agenda', 'desc': 'Today\'s agenda and active event tracker', 'icon': Icons.calendar_month_outlined},
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text('Add Built-in Widget', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 320,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            itemCount: availableWidgets.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade200),
            itemBuilder: (context, index) {
              final w = availableWidgets[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(w['icon'] as IconData, color: Colors.blueAccent, size: 22),
                ),
                title: Text(w['name'] as String, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(w['desc'] as String, style: TextStyle(color: subColor, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  int targetCol = 0;
                  int targetRow = 1;
                  while (state.desktopItems.any((i) => i.page == widget.currentDesktopPage && i.col == targetCol && i.row == targetRow)) {
                    targetRow++;
                    if (targetRow >= state.portraitGridY - 1) {
                      targetRow = 0;
                      targetCol = (targetCol + 2) % state.portraitGridX;
                    }
                  }

                  state.addDesktopWidget(w['type'] as String, w['name'] as String, widget.currentDesktopPage, targetCol, targetRow, spanX: 2, spanY: 1);
                  _showToast('Added ${w['name']} to Desktop');
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: subColor)))],
      ),
    );
  }

  Widget _buildContextMenuItem(String title, IconData? icon, LauncherState state, {Color? iconColor, String? shortcut, bool hasSubMenu = false, String? subMenuKey, double subMenuY = 0, VoidCallback? onTap}) {
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final defaultIconColor = isDark ? Colors.white : Colors.black87;

    return InkWell(
      onTap: () {
        if (hasSubMenu) {
          setState(() { _activeSubMenu = subMenuKey; _subMenuYOffset = subMenuY; });
        } else {
          widget.onClose();
          if (onTap != null) Future.delayed(const Duration(milliseconds: 150), onTap);
        }
      },
      hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
      child: Padding(
        // CRITICAL FIX: Reduced vertical padding from 8 to 4 to tighten line spacing
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(
          children: [
            if (icon != null) Icon(icon, size: 16, color: iconColor ?? defaultIconColor),
            if (icon != null) const SizedBox(width: 12),
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w400))),
            if (shortcut != null) Text(shortcut, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey.shade600)),
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
      onTap: () {
        widget.onClose();
        if (onTap != null) Future.delayed(const Duration(milliseconds: 150), onTap);
      },
      hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
      child: Padding(
        // CRITICAL FIX: Reduced vertical padding from 8 to 4 inside submenus as well
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            if (icon != null || isActive || isDot || isChecked) ...[
              SizedBox(width: 16, child: isActive || isDot ? Icon(Icons.circle, size: 6, color: textColor) : (isChecked ? Icon(Icons.check, size: 14, color: textColor) : null)),
              const SizedBox(width: 8),
              if (icon != null) Icon(icon, size: 16, color: textColor),
              if (icon != null) const SizedBox(width: 12),
            ],
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, color: textColor))),
          ],
        ),
      ),
    );
  }

  // CRITICAL FIX: Reduced divider margin to keep the menu extremely compact
  Widget _buildContextDivider(LauncherState state) => Container(height: 1, color: state.isDarkMode ? Colors.white24 : Colors.grey.shade300, margin: const EdgeInsets.symmetric(vertical: 2));

  Widget _buildBottomContextAction(IconData icon, String label, DesktopItemModel item, LauncherState state) {
    final isDark = state.isDarkMode;
    return InkWell(
      onTap: () {
        widget.onClose();
        Future.delayed(const Duration(milliseconds: 150), () {
          if (label == 'Cut') { state.setClipboard(item.id, true); _showToast('Cut to clipboard'); } 
          else if (label == 'Copy') { state.setClipboard(item.id, false); _showToast('Copied to clipboard'); } 
          else if (label == 'Rename') _showRenameDialog(item, state);
          else if (label == 'Delete') { state.removeDesktopItem(item.id); _showToast('Deleted item'); }
        });
      },
      hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF0078D4)), const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicContextMenu(LauncherState state) {
    if (widget.menuType == 'desktop') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // CRITICAL FIX: Recalibrated subMenuY Offsets due to the thinner menu items
          _buildContextMenuItem('View', Icons.grid_view, state, hasSubMenu: true, subMenuKey: 'view', subMenuY: 0),
          _buildContextMenuItem('Sort by', Icons.swap_vert, state, hasSubMenu: true, subMenuKey: 'sort', subMenuY: 28),
          _buildContextMenuItem('Page Transition', Icons.animation, state, hasSubMenu: true, subMenuKey: 'transition', subMenuY: 56),
          _buildContextMenuItem('Refresh', Icons.refresh, state, onTap: () => _showToast('Desktop refreshed')),
          if (state.clipboardPath != null) ...[
            _buildContextDivider(state),
            _buildContextMenuItem('Paste', Icons.assignment_outlined, state, iconColor: Colors.blueAccent, onTap: () {
              final original = state.desktopItems.firstWhere((i) => i.id == state.clipboardPath, orElse: () => DesktopItemModel(id: '', type: '', label: '', page: 0, col: 0, row: 0));
              if (original.id.isNotEmpty) {
                 if (state.isCut) { 
                    state.moveItemToPage(original.id, widget.currentDesktopPage); 
                    state.clearClipboard(); 
                 } 
                 else {
                    state.copyItemToPage(original.id, widget.currentDesktopPage);
                 }
                 _showToast('Pasted to Desktop');
              }
            }),
          ],
          _buildContextDivider(state),
          _buildContextMenuItem('Add Built-in Widget', Icons.widgets_outlined, state, iconColor: Colors.blueAccent, onTap: () => _showAddWidgetDialog(state)),
          _buildContextMenuItem('Add Android Widget', Icons.android, state, iconColor: Colors.green, onTap: () => state.addNativeWidget(widget.currentDesktopPage, 0, 0)),
          _buildContextDivider(state),
          _buildContextMenuItem('New Desktop Page', Icons.add_to_photos_outlined, state, onTap: () { state.addDesktopPage(); widget.pageController.animateToPage(state.desktopPages - 1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); _showToast('New workspace created'); }),
          _buildContextMenuItem('Delete Desktop Page', Icons.remove_circle_outline, state, onTap: () { if (state.desktopPages > 1) { state.removeDesktopPage(); _showToast('Workspace deleted'); } else { _showToast('Cannot delete the last workspace'); } }),
          _buildContextMenuItem(state.dragIcons ? 'Lock Desktop Icons' : 'Unlock Desktop Icons', state.dragIcons ? Icons.lock_outline : Icons.lock_open_outlined, state, onTap: () { state.updateDesktopSetting('dragIcons', !state.dragIcons); _showToast(!state.dragIcons ? 'Desktop icons locked' : 'Desktop icons unlocked'); }),
          _buildContextDivider(state),
          _buildContextMenuItem('Next desktop background', Icons.wallpaper, state, onTap: () => state.nextWallpaper()),
          _buildContextMenuItem('Personalize', Icons.brush_outlined, state, iconColor: const Color(0xFF0078D4), onTap: () => state.openApp('settings')),
        ],
      );
    }

    final matches = state.desktopItems.where((i) => i.label == widget.targetName);
    if (matches.isEmpty) return const SizedBox.shrink();
    final item = matches.first;
    
    List<Widget> menuItems = [];

    if (item.type == 'app') {
      final isPinnedToStart = state.pinnedStart.contains(item.package);
      menuItems.addAll([
        _buildContextMenuItem('Open', Icons.open_in_new, state, onTap: widget.openAction),
        _buildContextMenuItem('App info', Icons.info_outline, state, onTap: () { if (item.package != null) InstalledApps.openSettings(item.package!); }),
        _buildContextMenuItem(isPinnedToStart ? 'Unpin from Start' : 'Pin to Start', isPinnedToStart ? Icons.push_pin_outlined : Icons.push_pin, state, onTap: () { if (item.package != null) { state.togglePinToStart(item.package!); _showToast(isPinnedToStart ? 'Unpinned from Start' : 'Pinned to Start'); } }),
      ]);
    } else if (item.type == 'system') {
      menuItems.addAll([
        _buildContextMenuItem('Open', Icons.folder, state, iconColor: Colors.amber.shade400, onTap: widget.openAction),
        if (item.id == 'recycle_bin') _buildContextMenuItem('Empty Recycle Bin', Icons.delete_outline, state, onTap: () => _showToast('Recycle Bin emptied')),
      ]);
    } else if (item.type == 'widget' || item.type == 'native_widget') {
      menuItems.addAll([
        _buildContextMenuItem('Resize Widget', Icons.aspect_ratio, state, onTap: () => widget.onEnterResizeMode(item.id)),
      ]);
    } else if (item.type == 'file') {
      menuItems.addAll([
        _buildContextMenuItem('Open', Icons.open_in_new, state, onTap: widget.openAction),
        // Recalibrated offset
        _buildContextMenuItem('Compress to...', Icons.folder_zip_outlined, state, hasSubMenu: true, subMenuKey: 'compress', subMenuY: 28),
        _buildContextMenuItem('Properties', Icons.build_circle_outlined, state, onTap: () => _showPropertiesDialog(state)),
      ]);
    }

    menuItems.addAll([
      _buildContextDivider(state),
      _buildContextMenuItem('Move to next page', Icons.arrow_forward, state, onTap: () {
        int newPage = item.page + 1;
        if (newPage >= state.desktopPages) {
          state.addDesktopPage();
          widget.pageController.animateToPage(newPage, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        }
        state.moveItemToPage(item.id, newPage); 
        _showToast('Moved to next page');
      }),
      if (item.page > 0)
        _buildContextMenuItem('Move to previous page', Icons.arrow_back, state, onTap: () {
          state.moveItemToPage(item.id, item.page - 1);
          widget.pageController.animateToPage(item.page - 1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
          _showToast('Moved to previous page');
        }),
      _buildContextMenuItem('Remove from Desktop', Icons.delete_sweep, state, onTap: () { 
        state.removeDesktopItem(item.id); 
        if (item.type == 'native_widget' && item.appWidgetId != null) { NativeBridge.instance.removeWidget(item.appWidgetId!); } 
        _showToast('Removed from Desktop'); 
      }),
    ]);
    
    if (item.type == 'app') {
       menuItems.add(_buildContextMenuItem('Uninstall', Icons.delete_outline, state, iconColor: Colors.redAccent, onTap: () { Future.delayed(const Duration(milliseconds: 100), () { widget.onClose(); NativeBridge.instance.uninstallApp(item.package!); }); }));
    }

    if (item.type == 'file') {
       menuItems.addAll([
          _buildContextDivider(state),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBottomContextAction(Icons.content_cut, 'Cut', item, state),
                _buildBottomContextAction(Icons.content_copy, 'Copy', item, state),
                _buildBottomContextAction(Icons.drive_file_rename_outline, 'Rename', item, state),
                _buildBottomContextAction(Icons.delete_outline, 'Delete', item, state),
              ],
            ),
          ),
       ]);
    }

    return Column(mainAxisSize: MainAxisSize.min, children: menuItems);
  }

  Widget _buildSubMenuContent(LauncherState state) {
    if (_activeSubMenu == 'view') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSubMenuItem('Large icons', null, state, isActive: state.iconSize == 'Large', onTap: () => state.updateDesktopSetting('iconSize', 'Large')),
          _buildSubMenuItem('Medium icons', null, state, isActive: state.iconSize == 'Medium', onTap: () => state.updateDesktopSetting('iconSize', 'Medium')),
          _buildSubMenuItem('Small icons', null, state, isActive: state.iconSize == 'Small', onTap: () => state.updateDesktopSetting('iconSize', 'Small')),
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
    } else if (_activeSubMenu == 'transition') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSubMenuItem('Classical', null, state, isActive: state.pageTransition == 'Classical', onTap: () => state.updateDesktopSetting('pageTransition', 'Classical')),
          _buildSubMenuItem('Cube', null, state, isActive: state.pageTransition == 'Cube', onTap: () => state.updateDesktopSetting('pageTransition', 'Cube')),
          _buildSubMenuItem('Windmill', null, state, isActive: state.pageTransition == 'Windmill', onTap: () => state.updateDesktopSetting('pageTransition', 'Windmill')),
          _buildSubMenuItem('Zoom', null, state, isActive: state.pageTransition == 'Zoom', onTap: () => state.updateDesktopSetting('pageTransition', 'Zoom')),
          _buildSubMenuItem('Crossfade', null, state, isActive: state.pageTransition == 'Crossfade', onTap: () => state.updateDesktopSetting('pageTransition', 'Crossfade')),
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
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen) return const SizedBox.shrink();

    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B).withOpacity(0.95) : const Color(0xFFF3F3F3).withOpacity(0.95);
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;

    double menuWidth = 240;
    double menuHeight = widget.menuType == 'folder' ? 360 : 420; 
    double dx = widget.position.dx;
    double dy = widget.position.dy;
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
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _buildDynamicContextMenu(state),
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
        left: subMenuX, top: subMenuY,
        child: Container(
          width: subMenuWidth,
          decoration: BoxDecoration(
            color: bgColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: borderColor, width: 1),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
          ),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _buildSubMenuContent(state),
        ),
      );
    }

    return Stack(children: [Positioned(left: dx, top: dy, child: mainMenu), if (subMenu != null) subMenu]);
  }
}