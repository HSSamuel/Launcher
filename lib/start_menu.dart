import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'launcher_state.dart';

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
  bool _showAllPinned = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _launchApp(String packageName) {
    widget.onOverlaysClosed();
    InstalledApps.startApp(packageName);
  }

  void _showPowerMenu(BuildContext context, Offset position) {
    final isDark = context.read<LauncherState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy - 120, position.dx + 50, position.dy),
      color: bgColor,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
      items: [
        PopupMenuItem(
          onTap: () { widget.onOverlaysClosed(); widget.onPowerTapped(); },
          child: Row(children: [Icon(Icons.bedtime_outlined, size: 18, color: textColor), const SizedBox(width: 12), Text('Sleep', style: TextStyle(color: textColor, fontSize: 13))]),
        ),
        PopupMenuItem(
          onTap: () { widget.onOverlaysClosed(); widget.onPowerTapped(); },
          child: Row(children: [Icon(Icons.power_settings_new, size: 18, color: textColor), const SizedBox(width: 12), Text('Shut down', style: TextStyle(color: textColor, fontSize: 13))]),
        ),
        PopupMenuItem(
          onTap: () { widget.onOverlaysClosed(); widget.onPowerTapped(); },
          child: Row(children: [Icon(Icons.restart_alt, size: 18, color: textColor), const SizedBox(width: 12), Text('Restart', style: TextStyle(color: textColor, fontSize: 13))]),
        ),
      ],
    );
  }

  Widget _buildAppIcon(AppInfo app, double size) {
    return app.icon != null 
        ? Image.memory(app.icon!, width: size, height: size) 
        : Icon(Icons.android, size: size, color: Colors.green);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;

    // Windows 11 precise colors
    final bgColor = isDark ? const Color(0xFF242424).withOpacity(0.95) : const Color(0xFFF3F3F3).withOpacity(0.95);
    final textColor = isDark ? Colors.white : Colors.black87;
    final secText = isDark ? Colors.white70 : Colors.grey.shade600;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final searchBg = isDark ? const Color(0xFF333333) : Colors.white;
    final bottomBarBg = isDark ? const Color(0xFF1E1E1E).withOpacity(0.5) : const Color(0xFFE5E5E5).withOpacity(0.5);

    // Filter apps based on search
    List<AppInfo> displayApps = state.installedApps;
    if (_searchQuery.isNotEmpty) {
      displayApps = displayApps.where((app) => (app.name ?? '').toLowerCase().contains(_searchQuery)).toList();
    }

    // Split apps to mimic "Pinned" and "All" (Using the first 8-12 apps as Pinned for realism)
    int pinnedCount = _showAllPinned ? 24 : 8;
    List<AppInfo> pinnedApps = displayApps.take(pinnedCount).toList();
    List<AppInfo> allApps = displayApps.skip(pinnedCount).toList();

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
          // 1. Search Bar
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: borderColor)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: borderColor)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.blue.shade400)),
                ),
              ),
            ),
          ),

          // 2. Scrollable Content Area
          Expanded(
            child: _searchQuery.isNotEmpty
                ? ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: displayApps.length,
                    itemBuilder: (context, index) {
                      final app = displayApps[index];
                      return ListTile(
                        leading: _buildAppIcon(app, 32),
                        title: Text(app.name ?? 'Unknown', style: TextStyle(color: textColor, fontSize: 13)),
                        onTap: () => _launchApp(app.packageName!),
                      );
                    },
                  )
                : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- PINNED SECTION ---
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Pinned', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold)),
                              InkWell(
                                onTap: () => setState(() => _showAllPinned = !_showAllPinned),
                                child: Row(
                                  children: [
                                    Text(_showAllPinned ? 'Show less' : 'All apps', style: TextStyle(color: secText, fontSize: 11)),
                                    Icon(_showAllPinned ? Icons.keyboard_arrow_up : Icons.chevron_right, size: 14, color: secText),
                                  ],
                                ),
                              )
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
                            final app = pinnedApps[index];
                            return InkWell(
                              onTap: () => _launchApp(app.packageName!),
                              borderRadius: BorderRadius.circular(6),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildAppIcon(app, 36),
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
                            );
                          },
                        ),

                        const SizedBox(height: 16),

                        // --- ALL APPS SECTION ---
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('All', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold)),
                              Row(
                                children: [
                                  Text('View: List', style: TextStyle(color: secText, fontSize: 11)),
                                  Icon(Icons.keyboard_arrow_down, size: 14, color: secText),
                                ],
                              )
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 16.0, top: 12.0, bottom: 4.0),
                          child: Text('Most used', style: TextStyle(color: secText, fontSize: 11)),
                        ),
                        
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: allApps.length > 5 ? 5 : allApps.length, // Show just a few to mimic the "Most used" list
                          itemBuilder: (context, index) {
                            final app = allApps[index];
                            return InkWell(
                              onTap: () => _launchApp(app.packageName!),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                child: Row(
                                  children: [
                                    _buildAppIcon(app, 32),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(app.name ?? '', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
          ),

          // 3. Bottom User Profile & Power Bar
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
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.blue.shade200,
                  child: const Icon(Icons.person, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text(
                  'HUNSA S. S.',
                  style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
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