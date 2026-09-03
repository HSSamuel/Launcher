import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import 'launcher_state.dart';
import 'settings_accounts_view.dart';

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
  static const platform = MethodChannel('win_launcher/native');
  
  bool _isAllAppsGridView = false;

  List<AppInfo> _cachedApps = [];
  List<AppInfo> _filteredApps = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<LauncherState>();
    if (_cachedApps != state.installedApps) {
      _cachedApps = state.installedApps;
      _filterApps();
    }
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
      _searchQuery = query;
      _filterApps();
    }
  }

  void _filterApps() {
    if (_searchQuery.isEmpty) {
      setState(() => _filteredApps = _cachedApps);
    } else {
      setState(() {
        _filteredApps = _cachedApps
            .where((app) => (app.name ?? '').toLowerCase().contains(_searchQuery))
            .toList();
      });
    }
  }

  void _launchApp(String packageName, LauncherState state) {
    widget.onOverlaysClosed();
    state.launchNativeApp(packageName);
  }

  // FIX: Helper to prompt user to enable accessibility to access the native power menu
  void _showAccessibilityPrompt(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        title: Text('Accessibility Required', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          "To open the Power Menu, Android requires Accessibility permissions.\n\n1. Tap 'Go to Settings'\n2. Select 'Downloaded Apps'\n3. Turn ON 'Windows 11 Launcher'",
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              platform.invokeMethod('openSettings', {'type': 'accessibility'});
            },
            child: const Text('Go to Settings', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
          ),
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
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy - 120,
        position.dx + 50,
        position.dy,
      ),
      color: bgColor,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'sleep',
          onTap: () {
            widget.onOverlaysClosed();
            platform.invokeMethod('lockScreen'); // Trigger native lock
            widget.onPowerTapped(); // Transition Flutter UI to lock screen
          },
          child: Row(
            children: [
              Icon(Icons.bedtime_outlined, size: 18, color: textColor),
              const SizedBox(width: 12),
              Text('Sleep', style: TextStyle(color: textColor, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'shutdown',
          onTap: () async {
            widget.onOverlaysClosed();
            // FIX: Triggers the native Android Power Dialog (requires Accessibility)
            final success = await platform.invokeMethod('showPowerDialog');
            if (success != true && context.mounted) {
              _showAccessibilityPrompt(context, isDark);
            }
          },
          child: Row(
            children: [
              Icon(Icons.power_settings_new, size: 18, color: textColor),
              const SizedBox(width: 12),
              Text('Shut down', style: TextStyle(color: textColor, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'restart',
          onTap: () async {
            widget.onOverlaysClosed();
            // FIX: Triggers the native Android Power Dialog (requires Accessibility)
            final success = await platform.invokeMethod('showPowerDialog');
            if (success != true && context.mounted) {
              _showAccessibilityPrompt(context, isDark);
            }
          },
          child: Row(
            children: [
              Icon(Icons.restart_alt, size: 18, color: textColor),
              const SizedBox(width: 12),
              Text('Restart', style: TextStyle(color: textColor, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  void _showAppContextMenu(
    BuildContext context,
    Offset position,
    AppInfo app,
    LauncherState state, {
    required bool isPinnedSection,
  }) {
    final isDark = state.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final isPinnedToStart = state.pinnedStart.contains(app.packageName);
    final isOnDesktop = state.desktopApps.contains(app.packageName);

    List<PopupMenuEntry<String>> menuItems = [
      PopupMenuItem<String>(
        value: 'open',
        onTap: () {
          widget.onOverlaysClosed();
          state.launchNativeApp(app.packageName!);
        },
        child: Row(
          children: [
            Icon(Icons.open_in_new, size: 18, color: textColor),
            const SizedBox(width: 12),
            Text('Open', style: TextStyle(color: textColor, fontSize: 13)),
          ],
        ),
      ),
    ];

    if (isPinnedSection) {
      menuItems.addAll([
        PopupMenuItem<String>(
          value: 'unpin',
          onTap: () => state.togglePinToStart(app.packageName!),
          child: Row(
            children: [
              Icon(Icons.push_pin_outlined, size: 18, color: textColor),
              const SizedBox(width: 12),
              Text('Unpin from Start', style: TextStyle(color: textColor, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'uninstall',
          onTap: () {
            widget.onOverlaysClosed();
            platform.invokeMethod('uninstallApp', {'package': app.packageName});
          },
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: textColor),
              const SizedBox(width: 12),
              Text('Uninstall', style: TextStyle(color: textColor, fontSize: 13)),
            ],
          ),
        ),
      ]);
    } else {
      menuItems.addAll([
        PopupMenuItem<String>(
          value: 'pin_start',
          onTap: () => state.togglePinToStart(app.packageName!),
          child: Row(
            children: [
              Icon(isPinnedToStart ? Icons.push_pin_outlined : Icons.push_pin, size: 18, color: textColor),
              const SizedBox(width: 12),
              Text(isPinnedToStart ? 'Unpin from Start' : 'Pin to Start', style: TextStyle(color: textColor, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'pin_desktop',
          onTap: () {
            state.toggleDesktopApp(app.packageName!);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(isOnDesktop ? 'Removed from Desktop' : 'Added to Desktop'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          child: Row(
            children: [
              Icon(isOnDesktop ? Icons.desktop_access_disabled : Icons.desktop_windows, size: 18, color: textColor),
              const SizedBox(width: 12),
              Text(isOnDesktop ? 'Remove from Desktop' : 'Add to Desktop', style: TextStyle(color: textColor, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'uninstall',
          onTap: () {
            widget.onOverlaysClosed();
            platform.invokeMethod('uninstallApp', {'package': app.packageName});
          },
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: textColor),
              const SizedBox(width: 12),
              Text('Uninstall', style: TextStyle(color: textColor, fontSize: 13)),
            ],
          ),
        ),
      ]);
    }

    menuItems.addAll([
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'settings',
        onTap: () {
          widget.onOverlaysClosed();
          InstalledApps.openSettings(app.packageName!);
        },
        child: Row(
          children: [
            Icon(Icons.settings_applications, size: 18, color: textColor),
            const SizedBox(width: 12),
            Text('App settings', style: TextStyle(color: textColor, fontSize: 13)),
          ],
        ),
      ),
    ]);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 50,
        position.dy + 50,
      ),
      color: bgColor,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
      ),
      items: menuItems,
    );
  }

  Widget _buildAppIcon(AppInfo app, double size) {
    return app.icon != null
        ? Image.memory(app.icon!, width: size, height: size)
        : Icon(Icons.android, size: size, color: Colors.green);
  }

  Widget _buildAppGridItem(AppInfo app, LauncherState state, Color textColor, {required bool isPinnedSection}) {
    Offset tapPosition = Offset.zero;
    return Listener(
      onPointerDown: (details) => tapPosition = details.position,
      child: InkWell(
        onTap: () => _launchApp(app.packageName!, state),
        onLongPress: () => _showAppContextMenu(
          context,
          tapPosition,
          app,
          state,
          isPinnedSection: isPinnedSection,
        ),
        borderRadius: BorderRadius.circular(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAppIcon(app, 28),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Text(
                app.name ?? '',
                style: TextStyle(color: textColor, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
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
        onLongPress: () => _showAppContextMenu(
          context,
          tapPosition,
          app,
          state,
          isPinnedSection: false,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              _buildAppIcon(app, 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  app.name ?? '',
                  style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;

    final bgColor = isDark
        ? const Color(0xFF242424).withOpacity(0.95)
        : const Color(0xFFF3F3F3).withOpacity(0.95);
    final textColor = isDark ? Colors.white : Colors.black87;
    final secText = isDark ? Colors.white70 : Colors.grey.shade600;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final searchBg = isDark ? const Color(0xFF333333) : Colors.white;
    final bottomBarBg = isDark
        ? const Color(0xFF1E1E1E).withOpacity(0.5)
        : const Color(0xFFE5E5E5).withOpacity(0.5);

    List<AppInfo> pinnedApps = [];
    for (String pkg in state.pinnedStart) {
      try {
        pinnedApps.add(_filteredApps.firstWhere((a) => a.packageName == pkg));
      } catch (_) {}
    }

    List<AppInfo> recentAppInfos = [];
    for (String pkg in state.recentApps) {
      try {
        final app = state.installedApps.firstWhere((a) => a.packageName == pkg);
        recentAppInfos.add(app);
      } catch (_) {}
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 15, offset: Offset(0, 5))],
      ),
      child: Column(
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
                  isDense: true,
                  hintText: 'Search for apps, settings...',
                  hintStyle: TextStyle(color: secText, fontSize: 13),
                  prefixIcon: Icon(Icons.search, color: secText, size: 18),
                  filled: true,
                  fillColor: searchBg,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: Colors.blue.shade400),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _searchQuery.isNotEmpty
                ? ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: _filteredApps.length,
                    itemBuilder: (context, index) {
                      final app = _filteredApps[index];
                      Offset tapPosition = Offset.zero;
                      return Listener(
                        onPointerDown: (details) => tapPosition = details.position,
                        child: ListTile(
                          leading: _buildAppIcon(app, 24),
                          title: Text(app.name ?? 'Unknown', style: TextStyle(color: textColor, fontSize: 13)),
                          onTap: () => _launchApp(app.packageName!, state),
                          onLongPress: () => _showAppContextMenu(
                            context,
                            tapPosition,
                            app,
                            state,
                            isPinnedSection: false,
                          ),
                        ),
                      );
                    },
                  )
                : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Pinned',
                                style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            childAspectRatio: 0.85,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: pinnedApps.length,
                          itemBuilder: (context, index) {
                            return _buildAppGridItem(pinnedApps[index], state, textColor, isPinnedSection: true);
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('All', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold)),
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () => setState(() => _isAllAppsGridView = false),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Icon(Icons.format_list_bulleted, size: 16, color: !_isAllAppsGridView ? Colors.blue.shade400 : secText),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => setState(() => _isAllAppsGridView = true),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Icon(Icons.grid_view_sharp, size: 16, color: _isAllAppsGridView ? Colors.blue.shade400 : secText),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.only(left: 16.0, top: 12.0, bottom: 4.0),
                          child: Text('Recently used', style: TextStyle(color: secText, fontSize: 11)),
                        ),
                        if (recentAppInfos.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Text('No recent apps yet.', style: TextStyle(color: secText.withOpacity(0.5), fontSize: 12)),
                          )
                        else
                          _isAllAppsGridView
                              ? GridView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 4,
                                    childAspectRatio: 0.85,
                                    crossAxisSpacing: 4,
                                    mainAxisSpacing: 12,
                                  ),
                                  itemCount: recentAppInfos.length,
                                  itemBuilder: (context, index) => _buildAppGridItem(recentAppInfos[index], state, textColor, isPinnedSection: false),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: recentAppInfos.length,
                                  itemBuilder: (context, index) => _buildAppListItem(recentAppInfos[index], state, textColor),
                                ),

                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text('Installed apps', style: TextStyle(color: secText, fontSize: 11)),
                        ),
                        _isAllAppsGridView
                            ? GridView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  childAspectRatio: 0.85,
                                  crossAxisSpacing: 4,
                                  mainAxisSpacing: 12,
                                ),
                                itemCount: _filteredApps.length,
                                itemBuilder: (context, index) => _buildAppGridItem(_filteredApps[index], state, textColor, isPinnedSection: false),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _filteredApps.length,
                                itemBuilder: (context, index) => _buildAppListItem(_filteredApps[index], state, textColor),
                              ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
          ),
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: bottomBarBg,
              border: Border(top: BorderSide(color: borderColor)),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      widget.onOverlaysClosed();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const YourInfoScreen()));
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: state.userImageBytes != null
                                ? ClipOval(child: Image.memory(state.userImageBytes!, fit: BoxFit.cover))
                                : const Icon(Icons.person, size: 20, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              state.userName,
                              style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Builder(
                  builder: (ctx) => InkWell(
                    onTap: () {
                      final box = ctx.findRenderObject() as RenderBox;
                      final offset = box.localToGlobal(Offset.zero);
                      _showPowerMenu(context, offset);
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: Icon(Icons.power_settings_new, color: textColor, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}