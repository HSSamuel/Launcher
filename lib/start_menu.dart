import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import 'launcher_state.dart';
import 'ui/settings/settings_accounts_view.dart';
import 'services/native_bridge.dart';

class StartMenu extends StatefulWidget {
  final VoidCallback onOverlaysClosed;
  final VoidCallback onPowerTapped;

  const StartMenu({
    Key? key,
    required this.onOverlaysClosed,
    required this.onPowerTapped,
  }) : super(key: key);

  @override
  State<StartMenu> createState() => _StartMenuState();
}

class _StartMenuState extends State<StartMenu> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  
  String _viewMode = 'Category'; 
  bool _isPinnedExpanded = false; 

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (_searchQuery != query) {
      setState(() { _searchQuery = query; });
    }
  }

  void _launchApp(String packageName, LauncherState state) {
    widget.onOverlaysClosed();
    state.launchNativeApp(packageName);
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(fontSize: 13)), duration: const Duration(seconds: 1)));
  }

  void _showAccessibilityPrompt(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        title: Text('Accessibility Required', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text("To open the Power Menu, Android requires Accessibility permissions.\n\n1. Tap 'Go to Settings'\n2. Select 'Downloaded Apps'\n3. Turn ON 'Windows 11 Launcher'", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
          TextButton(onPressed: () { Navigator.pop(ctx); NativeBridge.instance.openSettings('accessibility'); }, child: const Text('Go to Settings', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  void _showPowerMenu(BuildContext context, Offset position) {
    final isDark = context.read<LauncherState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(Rect.fromLTWH(position.dx, position.dy - 160, 0, 0), Offset.zero & MediaQuery.of(context).size),
      color: bgColor, elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'change_launcher', onTap: () { Future.delayed(const Duration(milliseconds: 100), () { widget.onOverlaysClosed(); NativeBridge.instance.openSettings('home'); }); }, child: Row(children: [Icon(Icons.home_outlined, size: 18, color: textColor), const SizedBox(width: 12), Text('Change Launcher', style: TextStyle(color: textColor, fontSize: 13))])),
        PopupMenuItem<String>(value: 'sleep', onTap: () { Future.delayed(const Duration(milliseconds: 100), () { widget.onOverlaysClosed(); NativeBridge.instance.lockScreen(); widget.onPowerTapped(); }); }, child: Row(children: [Icon(Icons.bedtime_outlined, size: 18, color: textColor), const SizedBox(width: 12), Text('Sleep', style: TextStyle(color: textColor, fontSize: 13))])),
        PopupMenuItem<String>(value: 'shutdown', onTap: () async { Future.delayed(const Duration(milliseconds: 100), () async { widget.onOverlaysClosed(); final success = await NativeBridge.instance.showPowerDialog(); if (!success && context.mounted) { _showAccessibilityPrompt(context, isDark); } }); }, child: Row(children: [Icon(Icons.power_settings_new, size: 18, color: textColor), const SizedBox(width: 12), Text('Shut down', style: TextStyle(color: textColor, fontSize: 13))])),
        PopupMenuItem<String>(value: 'restart', onTap: () async { Future.delayed(const Duration(milliseconds: 100), () async { widget.onOverlaysClosed(); final success = await NativeBridge.instance.showPowerDialog(); if (!success && context.mounted) { _showAccessibilityPrompt(context, isDark); } }); }, child: Row(children: [Icon(Icons.restart_alt, size: 18, color: textColor), const SizedBox(width: 12), Text('Restart', style: TextStyle(color: textColor, fontSize: 13))])),
      ],
    );
  }

  void _showAppContextMenu(BuildContext context, Offset position, AppInfo app, LauncherState state, {required bool isPinnedSection, String? insideCategory}) {
    final isDark = state.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final isPinnedToStart = state.pinnedStart.contains(app.packageName);
    final isOnDesktop = state.desktopItems.any((i) => i.type == 'app' && i.package == app.packageName);

    List<PopupMenuEntry<String>> menuItems = [
      PopupMenuItem<String>(value: 'open', onTap: () { Future.delayed(const Duration(milliseconds: 100), () { widget.onOverlaysClosed(); state.launchNativeApp(app.packageName!); }); }, child: Row(children: [Icon(Icons.open_in_new, size: 18, color: textColor), const SizedBox(width: 12), Text('Open', style: TextStyle(color: textColor, fontSize: 13))])),
    ];

    if (insideCategory != null && state.isCustomCategory(insideCategory)) {
      menuItems.add(
        PopupMenuItem<String>(
          value: 'remove_from_cat',
          onTap: () {
            state.removeAppFromCategory(insideCategory, app.packageName!);
            _showToast('Removed from $insideCategory');
          },
          child: Row(children: [Icon(Icons.folder_delete_outlined, size: 18, color: textColor), const SizedBox(width: 12), Text('Remove from Folder', style: TextStyle(color: textColor, fontSize: 13))]),
        ),
      );
    }

    if (isPinnedSection) {
      menuItems.addAll([
        PopupMenuItem<String>(value: 'unpin', onTap: () => state.togglePinToStart(app.packageName!), child: Row(children: [Icon(Icons.push_pin_outlined, size: 18, color: textColor), const SizedBox(width: 12), Text('Unpin from Start', style: TextStyle(color: textColor, fontSize: 13))])),
        PopupMenuItem<String>(value: 'uninstall', onTap: () { Future.delayed(const Duration(milliseconds: 100), () { widget.onOverlaysClosed(); NativeBridge.instance.uninstallApp(app.packageName!); }); }, child: Row(children: [Icon(Icons.delete_outline, size: 18, color: textColor), const SizedBox(width: 12), Text('Uninstall', style: TextStyle(color: textColor, fontSize: 13))])),
      ]);
    } else {
      menuItems.addAll([
        PopupMenuItem<String>(
          value: 'pin_start', 
          onTap: () { 
            if (!isPinnedToStart && state.pinnedStart.length >= 8) {
               _showToast('Maximum of 8 apps can be pinned.');
            } else {
               state.togglePinToStart(app.packageName!); 
               _showToast(isPinnedToStart ? 'Unpinned from Start' : 'Pinned to Start');
            }
          }, 
          child: Row(children: [Icon(isPinnedToStart ? Icons.push_pin_outlined : Icons.push_pin, size: 18, color: textColor), const SizedBox(width: 12), Text(isPinnedToStart ? 'Unpin from Start' : 'Pin to Start', style: TextStyle(color: textColor, fontSize: 13))])
        ),
        PopupMenuItem<String>(value: 'pin_desktop', onTap: () { if (isOnDesktop) { final item = state.desktopItems.firstWhere((i) => i.package == app.packageName); state.removeDesktopItem(item.id); } else { state.addDesktopApp(app, 0, 0, 0); } ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isOnDesktop ? 'Removed from Desktop' : 'Added to Desktop'), duration: const Duration(seconds: 1))); }, child: Row(children: [Icon(isOnDesktop ? Icons.desktop_access_disabled : Icons.desktop_windows, size: 18, color: textColor), const SizedBox(width: 12), Text(isOnDesktop ? 'Remove from Desktop' : 'Add to Desktop', style: TextStyle(color: textColor, fontSize: 13))])),
        PopupMenuItem<String>(value: 'uninstall', onTap: () { Future.delayed(const Duration(milliseconds: 100), () { widget.onOverlaysClosed(); NativeBridge.instance.uninstallApp(app.packageName!); }); }, child: Row(children: [Icon(Icons.delete_outline, size: 18, color: textColor), const SizedBox(width: 12), Text('Uninstall', style: TextStyle(color: textColor, fontSize: 13))])),
      ]);
    }

    menuItems.addAll([
      const PopupMenuDivider(),
      PopupMenuItem<String>(value: 'settings', onTap: () { Future.delayed(const Duration(milliseconds: 100), () { widget.onOverlaysClosed(); InstalledApps.openSettings(app.packageName!); }); }, child: Row(children: [Icon(Icons.settings_applications, size: 18, color: textColor), const SizedBox(width: 12), Text('App settings', style: TextStyle(color: textColor, fontSize: 13))])),
    ]);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(Rect.fromLTWH(position.dx, position.dy, 0, 0), Offset.zero & MediaQuery.of(context).size),
      color: bgColor, elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
      items: menuItems,
    );
  }

  Widget _buildAppIcon(AppInfo app, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 3, offset: const Offset(0, 1))
        ],
      ),
      child: ClipOval(
        child: app.icon != null 
            ? Transform.scale(scale: 1.15, child: Image.memory(app.icon!, fit: BoxFit.contain))
            : Transform.scale(scale: 0.60, child: const Icon(Icons.android, color: Colors.green)),
      ),
    );
  }

  Widget _buildAppGridItem(AppInfo app, LauncherState state, Color textColor, {required bool isPinnedSection, String? insideCategory}) {
    Offset tapPosition = Offset.zero;
    return Listener(
      onPointerDown: (details) => tapPosition = details.position,
      child: InkWell(
        onTap: () => _launchApp(app.packageName!, state),
        onLongPress: () => _showAppContextMenu(context, tapPosition, app, state, isPinnedSection: isPinnedSection, insideCategory: insideCategory),
        borderRadius: BorderRadius.circular(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAppIcon(app, 32), const SizedBox(height: 8),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 2.0), child: Text(app.name ?? '', style: TextStyle(color: textColor, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }

  Widget _buildAppListItem(AppInfo app, LauncherState state, Color textColor) {
    Offset tapPosition = Offset.zero;
    return Listener(
      onPointerDown: (details) => tapPosition = details.position,
      child: InkWell(
        onTap: () => _launchApp(app.packageName!, state),
        onLongPress: () => _showAppContextMenu(context, tapPosition, app, state, isPinnedSection: false),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              _buildAppIcon(app, 24), const SizedBox(width: 16),
              Expanded(child: Text(app.name ?? '', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500))),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateCategoryDialog(BuildContext context, LauncherState state) {
    final isDark = state.isDarkMode;
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text('New Category Folder', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Enter category name (e.g. Work, Games)',
            hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: state.currentAccentColor, width: 1.5)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                state.createCustomCategory(text);
                Navigator.pop(ctx);
                _showToast("Created '$text' folder");
              }
            }, 
            child: Text('Create', style: TextStyle(color: state.currentAccentColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showManageAppsInFolderDialog(BuildContext context, String categoryName, LauncherState state) {
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final currentCatPackages = List<String>.from(state.categoryMap[categoryName] ?? []);
    final Set<String> selected = currentCatPackages.toSet();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            title: Text('Add Apps to $categoryName', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 320,
              height: 380,
              child: ListView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: state.installedApps.length,
                itemBuilder: (context, index) {
                  final app = state.installedApps[index];
                  final isChecked = selected.contains(app.packageName);
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    secondary: _buildAppIcon(app, 22),
                    title: Text(app.name ?? '', style: TextStyle(color: textColor, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                    value: isChecked,
                    activeColor: state.currentAccentColor,
                    onChanged: (bool? val) {
                      setDialogState(() {
                        if (val == true) {
                          if (app.packageName != null) selected.add(app.packageName!);
                        } else {
                          selected.remove(app.packageName);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx), 
                child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
              ),
              TextButton(
                onPressed: () {
                  state.setCategoryApps(categoryName, selected.toList());
                  Navigator.pop(ctx);
                  _showToast('Updated $categoryName');
                }, 
                child: Text('Done', style: TextStyle(color: state.currentAccentColor, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showCategoryAppsDialog(String title, List<AppInfo> apps, LauncherState state, Color textColor, Color bgColor) {
    final isCustom = state.isCustomCategory(title);
    final isDark = state.isDarkMode; 

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Row(
          children: [
            Expanded(child: Text(title, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold))),
            if (isCustom)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                tooltip: 'Delete Folder',
                onPressed: () {
                  Navigator.pop(ctx);
                  state.deleteCustomCategory(title);
                  _showToast("Deleted '$title' folder");
                },
              )
          ],
        ),
        content: SizedBox(
          width: 280,
          child: apps.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                    child: Text('No apps in this folder yet.\nTap "+ Add Apps" below to select apps.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12, height: 1.4),
                    ),
                  ),
                )
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4, childAspectRatio: 0.80, mainAxisSpacing: 16, crossAxisSpacing: 8
                  ),
                  itemCount: apps.length,
                  itemBuilder: (ctx, idx) => _buildAppGridItem(apps[idx], state, textColor, isPinnedSection: false, insideCategory: title),
                ),
        ),
        actions: [
           if (isCustom)
             TextButton.icon(
               icon: Icon(Icons.add, size: 16, color: state.currentAccentColor),
               label: Text('Add Apps', style: TextStyle(color: state.currentAccentColor, fontWeight: FontWeight.bold)),
               onPressed: () {
                 Navigator.pop(ctx);
                 _showManageAppsInFolderDialog(context, title, state);
               },
             ),
           TextButton(
             onPressed: () => Navigator.pop(ctx), 
             child: Text('Close', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
           ),
        ],
      )
    );
  }

  Widget _buildCategoryPreviewBox(List<AppInfo> apps, Color iconBg, bool isDark) {
    final previewApps = apps.take(4).toList();
    
    Widget iconSlot(int index) {
      if (index < previewApps.length) {
        return _buildAppIcon(previewApps[index], 20);
      }
      return const SizedBox(width: 20, height: 20);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8), 
      decoration: BoxDecoration(
        color: iconBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12, width: 1),
      ),
      child: apps.isEmpty
          ? Center(
              child: Icon(Icons.create_new_folder_outlined, size: 28, color: isDark ? Colors.white38 : Colors.black26),
            )
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [iconSlot(0), const SizedBox(width: 6), iconSlot(1)],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [iconSlot(2), const SizedBox(width: 6), iconSlot(3)],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCategoryView(LauncherState state, Color textColor, Color cardBg, Color iconBg) {
    final categories = state.categorizedApps;

    return SizedBox(
      height: 245,
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), 
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, 
          childAspectRatio: 0.80,
          crossAxisSpacing: 16, 
          mainAxisSpacing: 16
        ),
        itemCount: categories.keys.length,
        itemBuilder: (ctx, idx) {
          final title = categories.keys.elementAt(idx);
          final catApps = categories[title]!;

          return InkWell(
            onTap: () => _showCategoryAppsDialog(title, catApps, state, textColor, cardBg),
            borderRadius: BorderRadius.circular(12),
            child: Column(
              children: [
                Expanded(
                  child: _buildCategoryPreviewBox(catApps, iconBg, state.isDarkMode),
                ),
                const SizedBox(height: 8),
                Text(
                  title, 
                  style: TextStyle(fontSize: 11.5, color: textColor, fontWeight: FontWeight.w500), 
                  textAlign: TextAlign.center, 
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;

    final bgColor = isDark ? const Color(0xFF242424).withOpacity(0.95) : const Color(0xFFF3F3F3).withOpacity(0.95);
    final textColor = isDark ? Colors.white : Colors.black87;
    final secText = isDark ? Colors.white70 : Colors.grey.shade600;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final searchBg = isDark ? const Color(0xFF333333) : Colors.white;
    final bottomBarBg = isDark ? const Color(0xFF1E1E1E).withOpacity(0.5) : const Color(0xFFE5E5E5).withOpacity(0.5);
    final categoryCardBg = isDark ? const Color(0xFF3A3A3A) : Colors.white;

    List<AppInfo> filteredApps = state.installedApps;
    if (_searchQuery.isNotEmpty) {
      filteredApps = state.installedApps.where((app) => (app.name ?? '').toLowerCase().contains(_searchQuery)).toList();
    }

    List<AppInfo> rawPinned = [];
    for (String pkg in state.pinnedStart) {
      try { rawPinned.add(state.installedApps.firstWhere((a) => a.packageName == pkg)); } catch (_) {}
    }
    List<AppInfo> pinnedApps = rawPinned.take(8).toList(); 

    return GestureDetector(
      onTap: () {}, 
      behavior: HitTestBehavior.opaque, 
      child: Container(
        decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor, width: 1),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 15, offset: Offset(0, 5))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: textColor, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true, hintText: 'Search for apps, settings...', hintStyle: TextStyle(color: secText, fontSize: 13), prefixIcon: Icon(Icons.search, color: secText, size: 18),
                    filled: true, fillColor: searchBg, contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: borderColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: borderColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: state.currentAccentColor)),
                  ),
                ),
              ),
            ),
            Flexible(
              child: _searchQuery.isNotEmpty
                  ? ListView.builder(
                      shrinkWrap: true, physics: const BouncingScrollPhysics(), itemCount: filteredApps.length,
                      itemBuilder: (context, index) {
                        final app = filteredApps[index];
                        Offset tapPosition = Offset.zero;
                        return Listener(
                          onPointerDown: (details) => tapPosition = details.position,
                          child: ListTile(
                            leading: _buildAppIcon(app, 24), title: Text(app.name ?? 'Unknown', style: TextStyle(color: textColor, fontSize: 13)),
                            onTap: () => _launchApp(app.packageName!, state),
                            onLongPress: () => _showAppContextMenu(context, tapPosition, app, state, isPinnedSection: false),
                          ),
                        );
                      },
                    )
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Pinned', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold)),
                                InkWell(
                                  onTap: () => setState(() => _isPinnedExpanded = !_isPinnedExpanded),
                                  child: Icon(_isPinnedExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: textColor),
                                )
                              ],
                            ),
                          ),
                          if (_isPinnedExpanded) ...[
                            const SizedBox(height: 12),
                            GridView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12.0), shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 0.85, crossAxisSpacing: 4, mainAxisSpacing: 12),
                              itemCount: pinnedApps.length,
                              itemBuilder: (context, index) => _buildAppGridItem(pinnedApps[index], state, textColor, isPinnedSection: true),
                            ),
                          ],
                          
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              children: [
                                Text('All Apps', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold)),
                                const Spacer(),
                                if (_viewMode == 'Category') ...[
                                  InkWell(
                                    onTap: () => _showCreateCategoryDialog(context, state),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      child: Row(
                                        children: [
                                          Icon(Icons.create_new_folder_outlined, size: 15, color: state.currentAccentColor),
                                          const SizedBox(width: 4),
                                          Text('New Folder', style: TextStyle(fontSize: 11.5, color: state.currentAccentColor, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _viewMode,
                                    icon: Icon(Icons.keyboard_arrow_down, size: 16, color: secText),
                                    style: TextStyle(fontSize: 12, color: secText, fontWeight: FontWeight.w500),
                                    isDense: true,
                                    dropdownColor: categoryCardBg,
                                    items: ['Category', 'Grid', 'List'].map((e) => DropdownMenuItem(value: e, child: Text('View: $e'))).toList(),
                                    onChanged: (val) => setState(() => _viewMode = val!),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (_viewMode == 'Category')
                             _buildCategoryView(state, textColor, bgColor, categoryCardBg)
                          else if (_viewMode == 'Grid')
                             GridView.builder(
                               padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0), shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                               gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 0.85, crossAxisSpacing: 4, mainAxisSpacing: 12),
                               itemCount: filteredApps.length,
                               itemBuilder: (context, index) => _buildAppGridItem(filteredApps[index], state, textColor, isPinnedSection: false),
                             )
                          else
                             ListView.builder(
                               shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                               itemCount: filteredApps.length,
                               itemBuilder: (context, index) => _buildAppListItem(filteredApps[index], state, textColor),
                             ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
            ),
            Container(
              height: 54,
              decoration: BoxDecoration(color: bottomBarBg, border: Border(top: BorderSide(color: borderColor)), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10))),
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () { final nav = Navigator.of(context); widget.onOverlaysClosed(); nav.push(MaterialPageRoute(builder: (_) => const YourInfoScreen())); },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Container(width: 32, height: 32, decoration: BoxDecoration(color: state.currentAccentColor, shape: BoxShape.circle), child: state.userImageBytes != null ? ClipOval(child: Image.memory(state.userImageBytes!, fit: BoxFit.cover)) : const Icon(Icons.person, size: 20, color: Colors.white)),
                            const SizedBox(width: 12),
                            Expanded(child: Text(state.userName, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Builder(builder: (ctx) => InkWell(onTap: () { final box = ctx.findRenderObject() as RenderBox; final offset = box.localToGlobal(Offset.zero); _showPowerMenu(context, offset); }, borderRadius: BorderRadius.circular(4), child: Padding(padding: const EdgeInsets.all(6.0), child: Icon(Icons.power_settings_new, color: textColor, size: 20)))),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}