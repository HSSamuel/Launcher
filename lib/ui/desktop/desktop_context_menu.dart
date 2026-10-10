import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:flutter/foundation.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/desktop_item_model.dart';
import '../../services/native_bridge.dart';
import '../../services/pro_gatekeeper.dart';
import '../../states/theme_state.dart';
import '../../states/desktop_state.dart';
import '../../states/apps_state.dart';
import '../../main.dart'; 

class DesktopContextMenu extends StatefulWidget {
  final bool isOpen;
  final Offset position;
  final String menuType;
  final String targetId;
  final String targetName;
  final VoidCallback? openAction;
  final VoidCallback onClose;
  final int currentDesktopPage;
  final PageController pageController;
  final Function(String) onEnterResizeMode;
  final Function(String) onEnterMoveMode;

  const DesktopContextMenu({
    Key? key,
    required this.isOpen,
    required this.position,
    required this.menuType,
    required this.targetId,
    required this.targetName,
    this.openAction,
    required this.onClose,
    required this.currentDesktopPage,
    required this.pageController,
    required this.onEnterResizeMode,
    required this.onEnterMoveMode,
  }) : super(key: key);

  @override
  State<DesktopContextMenu> createState() => _DesktopContextMenuState();
}

Future<void> _isolateZipCreation(Map<String, String> args) async {
  final source = args['source']!;
  final dest = args['dest']!;
  var encoder = ZipFileEncoder();
  encoder.create(dest);
  if (Directory(source).existsSync()) {
    encoder.addDirectory(Directory(source));
  } else {
    encoder.addFile(File(source));
  }
  encoder.close();
}

class _DesktopContextMenuState extends State<DesktopContextMenu> {
  String? _activeSubMenu;
  double _subMenuYOffset = 0;

  @override
  void didUpdateWidget(DesktopContextMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isOpen && widget.isOpen) {
      setState(() => _activeSubMenu = null);
    } else if (oldWidget.targetId != widget.targetId || oldWidget.menuType != widget.menuType) {
      setState(() => _activeSubMenu = null);
    }
  }

  void _showToastSafe(String message) {
    final safeContext = navigatorKey.currentContext;
    if (safeContext == null) return;
    ScaffoldMessenger.of(safeContext).clearSnackBars();
    ScaffoldMessenger.of(safeContext).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  void _showCreateShortcutDialog(BuildContext context, ThemeState themeState, DesktopState desktopState) {
    if (!ProGatekeeper.checkAccess(context, featureName: 'Custom Desktop Shortcuts')) return;

    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final nameController = TextEditingController();
    final targetController = TextEditingController();
    String selectedType = 'web';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            title: Text('Create Desktop Shortcut', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    dropdownColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
                    style: TextStyle(color: textColor, fontSize: 13),
                    decoration: const InputDecoration(labelText: 'Shortcut Type', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'web', child: Text('Website / Web Link')),
                      DropdownMenuItem(value: 'call', child: Text('Direct Phone Call / USSD')),
                      DropdownMenuItem(value: 'custom', child: Text('Custom Android Intent / Action')),
                    ],
                    onChanged: (val) {
                      setDialogState(() {
                        selectedType = val!;
                        if (val == 'web') targetController.text = 'https://';
                        else if (val == 'call') targetController.text = 'tel:';
                        else targetController.text = '';
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: textColor, fontSize: 13),
                    decoration: const InputDecoration(labelText: 'Shortcut Name (e.g. YouTube)', isDense: true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: targetController,
                    style: TextStyle(color: textColor, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: selectedType == 'web' ? 'Target URL' : selectedType == 'call' ? 'Phone Number / Code' : 'Action Intent URI',
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent, 
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))
                ),
                onPressed: () {
                  final name = nameController.text.trim();
                  final target = targetController.text.trim();
                  if (name.isNotEmpty && target.isNotEmpty) {
                    desktopState.addDesktopShortcut(
                      name: name,
                      targetPath: target,
                      shortcutType: selectedType,
                      targetPage: widget.currentDesktopPage,
                      col: 0,
                      row: 0,
                    );
                    Navigator.pop(ctx);
                    _showToastSafe('Shortcut "$name" created on Desktop');
                  }
                },
                child: const Text('Create'),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showRenameDialog(DesktopItemModel item, ThemeState themeState, DesktopState desktopState) {
    final safeContext = navigatorKey.currentContext;
    if (safeContext == null) return;
    
    final controller = TextEditingController(text: item.label);
    final isDark = themeState.isDarkMode;
    
    showDialog(
      context: safeContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text('Rename', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: themeState.foregroundAccentColor)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              Navigator.pop(ctx);
              if (newName.isNotEmpty && newName != item.label) {
                desktopState.renameDesktopItem(item.id, newName);
                _showToastSafe('Renamed successfully');
              }
            },
            child: Text('Save', style: TextStyle(color: themeState.foregroundAccentColor)),
          ),
        ],
      ),
    ).then((_) {
      Future.delayed(const Duration(milliseconds: 500), () => controller.dispose());
    });
  }

  Future<void> _createZipArchive(String extension) async {
    final safeContext = navigatorKey.currentContext;
    if (safeContext == null) return;

    final desktopState = context.read<DesktopState>();
    final matches = desktopState.desktopItems.where((i) => i.id == widget.targetId);
    if (matches.isEmpty || matches.first.path == null) {
      _showToastSafe('Invalid target for compression.');
      return;
    }

    final isDark = context.read<ThemeState>().isDarkMode;
    
    showDialog(
      context: safeContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        content: Row(
          children: [
            const CircularProgressIndicator(color: Colors.blueAccent),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                'Compressing ${widget.targetName}...\nThis might take a while depending on size.', 
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13)
              )
            ),
          ],
        ),
      ),
    );
    
    try {
      final sourcePath = matches.first.path!;
      
      String rootPath = '/storage/emulated/0';
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) rootPath = extDir.path.split('/Android')[0];
      } catch (_) {}

      final downloadDir = Directory('$rootPath/Download');
      if (!downloadDir.existsSync()) downloadDir.createSync(recursive: true);
      
      String safeName = widget.targetName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      if (safeName.isEmpty) safeName = 'Archive';
      
      String newZipPath = '${downloadDir.path}/$safeName$extension';
      int counter = 1;
      while (File(newZipPath).existsSync()) {
        newZipPath = '${downloadDir.path}/$safeName ($counter)$extension';
        counter++;
      }
      
      await compute(_isolateZipCreation, {
        'source': sourcePath, 
        'dest': newZipPath
      });

      if (safeContext.mounted) {
        Navigator.pop(safeContext); 
      }
      _showToastSafe('Successfully compressed to Download/${newZipPath.split('/').last}');
    } catch (e) {
      if (safeContext.mounted) {
        Navigator.pop(safeContext); 
      }
      _showToastSafe('Compression failed. Ensure storage permissions are granted.');
    }
  }

  void _showPropertiesDialog(ThemeState themeState) async {
    final safeContext = navigatorKey.currentContext;
    if (safeContext == null) return;

    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.grey.shade800;

    final desktopState = context.read<DesktopState>();
    final matches = desktopState.desktopItems.where((i) => i.id == widget.targetId);
    if (matches.isEmpty) return;
    final item = matches.first;

    int sizeBytes = 0;
    String location = 'Desktop > ${widget.targetName}';
    String typeLabel = item.type.toUpperCase();

    if (item.type == 'file' && item.path != null) {
       try {
         final stat = await File(item.path!).stat();
         sizeBytes = stat.size;
         location = item.path!;
       } catch (_) {}
    } else if (item.type == 'app') {
       typeLabel = 'Android Application';
    } else if (item.type == 'shortcut') {
       typeLabel = 'Desktop Script / Shortcut (${item.widgetType?.toUpperCase()})';
       location = item.path ?? 'Action';
    }

    final sizeStr = sizeBytes > 0 
        ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB' 
        : 'System Managed';

    showDialog(
      context: safeContext,
      builder: (context) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('${widget.targetName} Properties', style: TextStyle(fontSize: 15, color: textColor, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: $typeLabel', style: TextStyle(fontSize: 13, color: subTextColor)),
            const SizedBox(height: 8),
            Text('Target: $location', style: TextStyle(fontSize: 13, color: subTextColor)),
            const SizedBox(height: 8),
            Text('Size: $sizeStr', style: TextStyle(fontSize: 13, color: subTextColor)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('OK', style: TextStyle(color: themeState.foregroundAccentColor, fontWeight: FontWeight.bold)))],
      ),
    );
  }

  void _showAddWidgetDialog(ThemeState themeState, DesktopState desktopState) {
    final safeContext = navigatorKey.currentContext;
    if (safeContext == null) return;

    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white70 : Colors.black54;

    final availableWidgets = [
      {'type': 'clock', 'name': 'Digital Clock & Date', 'desc': 'Live updating clock with current day/date', 'icon': Icons.access_time},
      {'type': 'weather', 'name': 'Weather Card', 'desc': 'Displays local temperature and sky conditions', 'icon': Icons.wb_sunny_outlined},
      {'type': 'system_monitor', 'name': 'RAM Optimization', 'desc': 'Live system resources and memory cleaner', 'icon': Icons.memory},
      {'type': 'storage', 'name': 'Internal Storage', 'desc': 'Storage capacity bar and remaining free GB', 'icon': Icons.storage},
      {'type': 'calendar', 'name': 'Calendar Agenda', 'desc': 'Today\'s agenda and active event tracker', 'icon': Icons.calendar_month_outlined},
    ];

    showDialog(
      context: safeContext,
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
                  decoration: BoxDecoration(color: themeState.foregroundAccentColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(w['icon'] as IconData, color: themeState.foregroundAccentColor, size: 22),
                ),
                title: Text(w['name'] as String, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(w['desc'] as String, style: TextStyle(color: subColor, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  int targetCol = 0;
                  int targetRow = 1;
                  while (desktopState.desktopItems.any((i) => i.page == widget.currentDesktopPage && i.col == targetCol && i.row == targetRow)) {
                    targetRow++;
                    if (targetRow >= desktopState.portraitGridY - 1) {
                      targetRow = 0;
                      targetCol = (targetCol + 2) % desktopState.portraitGridX;
                    }
                  }

                  desktopState.addDesktopWidget(w['type'] as String, w['name'] as String, widget.currentDesktopPage, targetCol, targetRow, spanX: 2, spanY: 1);
                  _showToastSafe('Added ${w['name']} to Desktop');
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: subColor)))],
      ),
    );
  }

  // Tighter padding, thinner fonts, and smaller icons for a crisp desktop feel
  Widget _buildContextMenuItem(String title, IconData? icon, ThemeState themeState, {Color? iconColor, String? shortcut, bool hasSubMenu = false, String? subMenuKey, double subMenuY = 0, VoidCallback? onTap}) {
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final defaultIconColor = isDark ? Colors.white70 : Colors.black87;

    return InkWell(
      onTap: () {
        if (hasSubMenu) {
          setState(() { _activeSubMenu = subMenuKey; _subMenuYOffset = subMenuY; });
        } else {
          widget.onClose();
          if (onTap != null) onTap();
        }
      },
      hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5), // Reduced padding
        child: Row(
          children: [
            if (icon != null) Icon(icon, size: 15, color: iconColor ?? defaultIconColor), // Reduced icon
            if (icon != null) const SizedBox(width: 10),
            Expanded(
              child: Text(
                title, 
                // Removed letterSpacing, dropped weight to w400, reduced size
                style: TextStyle(fontSize: 12.5, color: textColor, fontWeight: FontWeight.w400)
              )
            ),
            if (shortcut != null) Text(shortcut, style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade600)),
            if (hasSubMenu) Icon(Icons.chevron_right, size: 15, color: isDark ? Colors.white54 : Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  Widget _buildSubMenuItem(String title, IconData? icon, ThemeState themeState, {bool isActive = false, bool isChecked = false, bool isDot = false, VoidCallback? onTap}) {
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;

    return InkWell(
      onTap: () {
        widget.onClose();
        if (onTap != null) onTap();
      },
      hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5), // Reduced padding
        child: Row(
          children: [
            if (icon != null || isActive || isDot || isChecked) ...[
              SizedBox(width: 16, child: isActive || isDot ? Icon(Icons.circle, size: 6, color: textColor) : (isChecked ? Icon(Icons.check, size: 14, color: textColor) : null)),
              const SizedBox(width: 8),
              if (icon != null) Icon(icon, size: 15, color: textColor),
              if (icon != null) const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                title, 
                style: TextStyle(fontSize: 12.5, color: textColor, fontWeight: FontWeight.w400)
              )
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextDivider(ThemeState themeState) => Container(height: 1, color: themeState.isDarkMode ? Colors.white24 : Colors.grey.shade300, margin: const EdgeInsets.symmetric(vertical: 4));

  Widget _buildBottomContextAction(IconData icon, String label, DesktopItemModel item, ThemeState themeState, AppsState appsState, DesktopState desktopState) {
    final isDark = themeState.isDarkMode;
    return InkWell(
      onTap: () {
        widget.onClose();
        if (label == 'Cut') { appsState.setClipboard(item.id, true); _showToastSafe('Cut to clipboard'); } 
        else if (label == 'Copy') { appsState.setClipboard(item.id, false); _showToastSafe('Copied to clipboard'); } 
        else if (label == 'Rename') _showRenameDialog(item, themeState, desktopState);
        else if (label == 'Delete') { desktopState.removeDesktopItem(item.id); _showToastSafe('Deleted item'); }
      },
      hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF0078D4)), 
            const SizedBox(height: 6),
            Text(
              label, 
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w500)
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicContextMenu(ThemeState themeState, DesktopState desktopState, AppsState appsState) {
    if (widget.menuType == 'desktop') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildContextMenuItem('View', Icons.grid_view, themeState, hasSubMenu: true, subMenuKey: 'view', subMenuY: 0),
          _buildContextMenuItem('Sort by', Icons.swap_vert, themeState, hasSubMenu: true, subMenuKey: 'sort', subMenuY: 28),
          _buildContextMenuItem('Page Transition', Icons.animation, themeState, hasSubMenu: true, subMenuKey: 'transition', subMenuY: 56),
          _buildContextMenuItem('Refresh', Icons.refresh, themeState, onTap: () => _showToastSafe('Desktop refreshed')),
          if (appsState.clipboardPath != null) ...[
            _buildContextDivider(themeState),
            _buildContextMenuItem('Paste', Icons.assignment_outlined, themeState, iconColor: Colors.blueAccent, onTap: () {
              final original = desktopState.desktopItems.firstWhere((i) => i.id == appsState.clipboardPath, orElse: () => DesktopItemModel(id: '', type: '', label: '', page: 0, col: 0, row: 0));
              if (original.id.isNotEmpty) {
                 if (appsState.isCut) { 
                    desktopState.moveItemToPage(original.id, widget.currentDesktopPage); 
                    appsState.clearClipboard(); 
                 } 
                 else {
                    desktopState.copyItemToPage(original.id, widget.currentDesktopPage);
                 }
                 _showToastSafe('Pasted to Desktop');
              }
            }),
          ],
          _buildContextDivider(themeState),
          _buildContextMenuItem('New Shortcut (Pro)', Icons.add_link, themeState, iconColor: Colors.blueAccent, onTap: () => _showCreateShortcutDialog(context, themeState, desktopState)),
          _buildContextMenuItem('Add Built-in Widget', Icons.widgets_outlined, themeState, iconColor: Colors.blueAccent, onTap: () => _showAddWidgetDialog(themeState, desktopState)),
          _buildContextMenuItem('Add Android Widget', Icons.android, themeState, iconColor: Colors.green, onTap: () {
            if (!ProGatekeeper.checkAccess(context, featureName: 'Android Widgets')) return;
            desktopState.addNativeWidget(widget.currentDesktopPage, 0, 0);
          }),
          _buildContextDivider(themeState),
          _buildContextMenuItem('New Desktop Page', Icons.add_to_photos_outlined, themeState, onTap: () {
            if (!ProGatekeeper.checkAccess(context, featureName: 'Multiple Workspaces')) return;
            desktopState.addDesktopPage();
            widget.pageController.animateToPage(desktopState.desktopPages - 1, duration: const Duration(milliseconds: 10), curve: Curves.easeOut);
            _showToastSafe('New workspace created');
          }),
          _buildContextMenuItem('Delete Desktop Page', Icons.remove_circle_outline, themeState, onTap: () {
            if (desktopState.desktopPages > 1) {
              desktopState.removeDesktopPage();
              _showToastSafe('Workspace deleted');
            } else {
              _showToastSafe('Cannot delete the last workspace');
            }
          }),
          _buildContextMenuItem(desktopState.dragIcons ? 'Lock Desktop Icons' : 'Unlock Desktop Icons', desktopState.dragIcons ? Icons.lock_outline : Icons.lock_open_outlined, themeState, onTap: () {
            desktopState.updateDesktopSetting('dragIcons', !desktopState.dragIcons);
            _showToastSafe(!desktopState.dragIcons ? 'Desktop icons locked' : 'Desktop icons unlocked');
          }),
          _buildContextDivider(themeState),
          _buildContextMenuItem('Next desktop background', Icons.wallpaper, themeState, onTap: () {
            if (!ProGatekeeper.checkAccess(context, featureName: 'Desktop Background Switcher')) return;

            themeState.nextWallpaper();
            _showToastSafe(themeState.infiniteWebWallpapers 
                ? 'Fetching new online wallpaper...' 
                : 'Switched wallpaper');
          }),
          _buildContextMenuItem('Personalize', Icons.brush_outlined, themeState, iconColor: const Color(0xFF0078D4), onTap: () => appsState.openApp('settings')),
        ],
      );
    }

    final matches = desktopState.desktopItems.where((i) => i.id == widget.targetId);
    if (matches.isEmpty) return const SizedBox.shrink();
    final item = matches.first;
    
    List<Widget> menuItems = [];

    if (item.type == 'app') {
      final isPinnedToStart = appsState.pinnedStart.contains(item.package);
      final hasCustomIcon = themeState.customAppIcons.containsKey(item.package);

      menuItems.addAll([
        _buildContextMenuItem('Open', Icons.open_in_new, themeState, onTap: widget.openAction),
        _buildContextMenuItem('App info', Icons.info_outline, themeState, onTap: () { if (item.package != null) InstalledApps.openSettings(item.package!); }),
        _buildContextMenuItem(isPinnedToStart ? 'Unpin from Start' : 'Pin to Start', isPinnedToStart ? Icons.push_pin_outlined : Icons.push_pin, themeState, onTap: () { if (item.package != null) { appsState.togglePinToStart(item.package!); _showToastSafe(isPinnedToStart ? 'Unpinned from Start' : 'Pinned to Start'); } }),
        _buildContextDivider(themeState),
        _buildContextMenuItem('Edit Icon', Icons.image_outlined, themeState, onTap: () async {
          final picker = ImagePicker();
          final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
          if (image != null && item.package != null) {
            final dir = await getApplicationDocumentsDirectory();
            final File newIcon = File('${dir.path}/custom_icon_${item.package}_${DateTime.now().millisecondsSinceEpoch}.png');
            await File(image.path).copy(newIcon.path);
            themeState.setCustomAppIcon(item.package!, newIcon.path);
            _showToastSafe('Custom icon applied');
          }
        }),
        if (hasCustomIcon)
          _buildContextMenuItem('Reset Default Icon', Icons.restore, themeState, onTap: () {
            themeState.removeCustomAppIcon(item.package!);
            _showToastSafe('Icon restored to default');
          }),
      ]);
    } else if (item.type == 'shortcut') {
      menuItems.addAll([
        _buildContextMenuItem('Run Shortcut', Icons.play_arrow, themeState, iconColor: Colors.blueAccent, onTap: widget.openAction),
        _buildContextMenuItem('Rename', Icons.edit, themeState, onTap: () => _showRenameDialog(item, themeState, desktopState)),
        _buildContextMenuItem('Properties', Icons.build_circle_outlined, themeState, onTap: () => _showPropertiesDialog(themeState)),
      ]);
    } else if (item.type == 'system') {
      menuItems.addAll([
        _buildContextMenuItem('Open', Icons.folder, themeState, iconColor: Colors.amber.shade400, onTap: widget.openAction),
        if (item.id == 'recycle_bin') _buildContextMenuItem('Empty Recycle Bin', Icons.delete_outline, themeState, onTap: () {
  NativeBridge.instance.playSound('recycle');
  _showToastSafe('Recycle Bin emptied');
}),
      ]);
    } else if (item.type == 'widget' || item.type == 'native_widget') {
      menuItems.addAll([
        _buildContextMenuItem('Move Widget', Icons.open_with, themeState, onTap: () => widget.onEnterMoveMode(item.id)),
        _buildContextMenuItem('Resize Widget', Icons.aspect_ratio, themeState, onTap: () => widget.onEnterResizeMode(item.id)),
      ]);
    } else if (item.type == 'desktop_folder') {
      menuItems.addAll([
        _buildContextMenuItem('Open Folder', Icons.folder_open, themeState, onTap: widget.openAction),
        _buildContextMenuItem('Rename Folder', Icons.edit, themeState, onTap: () => _showRenameDialog(item, themeState, desktopState)),
      ]);
    } else if (item.type == 'file') {
      menuItems.addAll([
        _buildContextMenuItem('Open', Icons.open_in_new, themeState, onTap: widget.openAction),
        _buildContextMenuItem('Share', Icons.share_outlined, themeState, onTap: () {
          if (item.path != null) NativeBridge.instance.shareFile(item.path!);
        }),
        _buildContextMenuItem('Compress to...', Icons.folder_zip_outlined, themeState, hasSubMenu: true, subMenuKey: 'compress', subMenuY: 56),
        _buildContextMenuItem('Properties', Icons.build_circle_outlined, themeState, onTap: () => _showPropertiesDialog(themeState)),
      ]);
    }

    menuItems.addAll([
      _buildContextDivider(themeState),
      _buildContextMenuItem('Move to next page', Icons.arrow_forward, themeState, onTap: () {
        int newPage = item.page + 1;
        if (newPage >= desktopState.desktopPages) {
          desktopState.addDesktopPage();
          widget.pageController.animateToPage(newPage, duration: const Duration(milliseconds: 10), curve: Curves.easeOut);
        } else {
          widget.pageController.animateToPage(newPage, duration: const Duration(milliseconds: 10), curve: Curves.easeOut);
        }
        desktopState.moveItemToPage(item.id, newPage); 
        _showToastSafe('Moved to next page');
      }),
      if (item.page > 0)
        _buildContextMenuItem('Move to previous page', Icons.arrow_back, themeState, onTap: () {
          desktopState.moveItemToPage(item.id, item.page - 1);
          widget.pageController.animateToPage(item.page - 1, duration: const Duration(milliseconds: 10), curve: Curves.easeOut);
          _showToastSafe('Moved to previous page');
        }),
      _buildContextMenuItem('Remove from Desktop', Icons.delete_sweep, themeState, onTap: () { 
        desktopState.removeDesktopItem(item.id); 
        if (item.type == 'native_widget' && item.appWidgetId != null) { NativeBridge.instance.removeWidget(item.appWidgetId!); } 
        _showToastSafe('Removed from Desktop'); 
      }),
    ]);
    
    if (item.type == 'app') {
       menuItems.add(_buildContextMenuItem('Uninstall', Icons.delete_outline, themeState, iconColor: Colors.redAccent, onTap: () { NativeBridge.instance.uninstallApp(item.package!); }));
    }

    if (item.type == 'file') {
       menuItems.addAll([
          _buildContextDivider(themeState),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBottomContextAction(Icons.content_cut, 'Cut', item, themeState, appsState, desktopState),
                _buildBottomContextAction(Icons.content_copy, 'Copy', item, themeState, appsState, desktopState),
                _buildBottomContextAction(Icons.drive_file_rename_outline, 'Rename', item, themeState, appsState, desktopState),
                _buildBottomContextAction(Icons.delete_outline, 'Delete', item, themeState, appsState, desktopState),
              ],
            ),
          ),
       ]);
    }

    return Column(mainAxisSize: MainAxisSize.min, children: menuItems);
  }

  Widget _buildSubMenuContent(ThemeState themeState, DesktopState desktopState) {
    if (_activeSubMenu == 'view') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSubMenuItem('Large icons', null, themeState, isActive: desktopState.desktopIconScale == 1.25, onTap: () => desktopState.updateDesktopSetting('desktopIconScale', 1.25)),
          _buildSubMenuItem('Medium icons', null, themeState, isActive: desktopState.desktopIconScale == 1.0, onTap: () => desktopState.updateDesktopSetting('desktopIconScale', 1.0)),
          _buildSubMenuItem('Small icons', null, themeState, isActive: desktopState.desktopIconScale == 0.75, onTap: () => desktopState.updateDesktopSetting('desktopIconScale', 0.75)),
        ],
      );
    } else if (_activeSubMenu == 'sort') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSubMenuItem('Name', null, themeState, isDot: true, onTap: () => _showToastSafe('Sorted by Name')),
          _buildSubMenuItem('Size', null, themeState, onTap: () => _showToastSafe('Sorted by Size')),
          _buildSubMenuItem('Item type', null, themeState, onTap: () => _showToastSafe('Sorted by Type')),
          _buildSubMenuItem('Date modified', null, themeState, onTap: () => _showToastSafe('Sorted by Date')),
        ],
      );
    } else if (_activeSubMenu == 'transition') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSubMenuItem('Classical', null, themeState, isActive: desktopState.pageTransition == 'Classical', onTap: () => desktopState.updateDesktopSetting('pageTransition', 'Classical')),
          _buildSubMenuItem('3D Cube', null, themeState, isActive: desktopState.pageTransition == '3D Cube', onTap: () => desktopState.updateDesktopSetting('pageTransition', '3D Cube')),
          _buildSubMenuItem('3D Page Flip', null, themeState, isActive: desktopState.pageTransition == '3D Page Flip', onTap: () => desktopState.updateDesktopSetting('pageTransition', '3D Page Flip')),
          _buildSubMenuItem('3D Card', null, themeState, isActive: desktopState.pageTransition == '3D Card', onTap: () => desktopState.updateDesktopSetting('pageTransition', '3D Card')),
          _buildSubMenuItem('Cube Carousel', null, themeState, isActive: desktopState.pageTransition == 'Cube Carousel', onTap: () => desktopState.updateDesktopSetting('pageTransition', 'Cube Carousel')),
          _buildSubMenuItem('3D Swipe', null, themeState, isActive: desktopState.pageTransition == '3D Swipe', onTap: () => desktopState.updateDesktopSetting('pageTransition', '3D Swipe')),
          _buildSubMenuItem('Random', null, themeState, isActive: desktopState.pageTransition == 'Random', onTap: () => desktopState.updateDesktopSetting('pageTransition', 'Random')),
        ],
      );
    } else if (_activeSubMenu == 'compress') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildContextMenuItem('ZIP File', null, themeState, onTap: () => _createZipArchive('.zip')),
          _buildContextMenuItem('7z File', null, themeState, onTap: () => _createZipArchive('.7z')),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen) return const SizedBox.shrink();

    final themeState = context.watch<ThemeState>();
    final desktopState = context.watch<DesktopState>();
    final appsState = context.watch<AppsState>();
    
    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B).withOpacity(0.95) : const Color(0xFFF3F3F3).withOpacity(0.95);
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;

    double menuWidth = 260; 
    double dx = widget.position.dx;
    double dy = widget.position.dy;
    final screenSize = MediaQuery.of(context).size;

    // Dynamic height calculation to ensure it strictly prevents the menu from falling off the bottom edge
    double menuHeight;
    if (widget.menuType == 'desktop') {
      menuHeight = appsState.clipboardPath != null ? 360 : 330;
    } else if (widget.menuType == 'file') {
      menuHeight = 280;
    } else if (widget.menuType == 'folder' || widget.menuType == 'desktop_folder') {
      menuHeight = 250;
    } else {
      menuHeight = 220;
    }

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
      child: _buildDynamicContextMenu(themeState, desktopState, appsState),
    );

    Widget? subMenu;
    if (_activeSubMenu != null) {
      double subMenuWidth = 220; 
      double subMenuX = dx + menuWidth - 4;
      if (subMenuX + subMenuWidth > screenSize.width) subMenuX = dx - subMenuWidth + 4;
      if (subMenuX < 8) subMenuX = 8;
      double subMenuY = dy + _subMenuYOffset;
      
      if (subMenuY + 280 > screenSize.height) subMenuY = math.max(8.0, screenSize.height - 290);
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
          child: _buildSubMenuContent(themeState, desktopState),
        ),
      );
    }

    return Stack(children: [Positioned(left: dx, top: dy, child: mainMenu), if (subMenu != null) subMenu]);
  }
}