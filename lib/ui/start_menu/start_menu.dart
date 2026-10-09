import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:installed_apps/app_info.dart';

import '../../states/theme_state.dart';
import '../../states/apps_state.dart';
import '../../states/desktop_state.dart';
import '../../states/system_state.dart';
import '../settings/settings_accounts_view.dart';
import 'start_menu_context.dart';
import '../shared/acrylic_container.dart';
import '../../services/lazy_app_icon.dart';

class StartMenu extends StatefulWidget {
  final VoidCallback onOverlaysClosed;
  final VoidCallback onPowerTapped;
  final int currentDesktopPage;

  const StartMenu({
    Key? key,
    required this.onOverlaysClosed,
    required this.onPowerTapped,
    required this.currentDesktopPage,
  }) : super(key: key);

  @override
  State<StartMenu> createState() => _StartMenuState();
}

class _StartMenuState extends State<StartMenu> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  String _searchQuery = '';
  
  Timer? _searchDebounce;

  String _viewMode = 'Category';
  bool _isPinnedExpanded = false;
  bool _showAlphabetGrid = false;

  // Memoized cache for the A-Z list to avoid O(N) calculations in build()
  List<Map<String, dynamic>> _cachedFlattenedList = [];
  Map<String, double> _cachedLetterOffsets = {};
  int _lastAppCount = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    if (_searchQuery != query) {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        setState(() {
          _searchQuery = query;
          _showAlphabetGrid = false;
        });
      });
    }
  }

  void _launchApp(String packageName, AppsState appsState, SystemState systemState) {
    appsState.launchNativeApp(packageName, systemState: systemState);
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(fontSize: 13)), duration: const Duration(seconds: 1)),
    );
  }

  Widget _buildAppIcon(AppInfo app, double size, ThemeState themeState, AppsState appsState, {int notifCount = 0}) {
    Widget iconWidget;
    int safeCacheWidth = (size * 2).toInt().clamp(48, 144);

    Widget fallbackIcon = app.packageName != null
        ? LazyAppIcon(packageName: app.packageName!, size: size)
        : const Icon(Icons.android, color: Colors.green);

    if (app.packageName != null && themeState.customAppIcons.containsKey(app.packageName)) {
      iconWidget = Image.file(
        File(themeState.customAppIcons[app.packageName]!),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        cacheWidth: safeCacheWidth,
        cacheHeight: safeCacheWidth,
        errorBuilder: (_, __, ___) => fallbackIcon,
      );
    } else if (themeState.cachedIconsPath != null && app.packageName != null) {
      iconWidget = Image.file(
        File('${themeState.cachedIconsPath}/${app.packageName}.png'),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        cacheWidth: safeCacheWidth,
        cacheHeight: safeCacheWidth,
        errorBuilder: (_, __, ___) => fallbackIcon,
      );
    } else {
      iconWidget = fallbackIcon;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: iconWidget,
        ),
        if (notifCount > 0)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                notifCount > 9 ? '9+' : notifCount.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, height: 1.0),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAppGridItem(
    AppInfo app,
    ThemeState themeState,
    AppsState appsState,
    DesktopState desktopState,
    SystemState systemState,
    Color textColor, {
    required bool isPinnedSection,
    String? insideCategory,
  }) {
    final int notifCount = appsState.appNotificationCounts[app.packageName] ?? 0;
    final double scale = desktopState.desktopIconScale.clamp(0.6, 1.8);
    final double iconSize = 32.0 * scale; 
    final double fontSize = desktopState.desktopFontSize;

    return RepaintBoundary(
      child: Builder(
        builder: (ctx) => InkWell(
          onTap: () => _launchApp(app.packageName!, appsState, systemState),
          onLongPress: () {
            if (!ctx.mounted) return;
            final RenderBox box = ctx.findRenderObject() as RenderBox;
            final Offset pos = box.localToGlobal(Offset.zero);
            StartMenuContext.showAppContextMenu(
              ctx,
              pos,
              app,
              themeState,
              appsState,
              desktopState,
              systemState,
              widget.onOverlaysClosed,
              _showToast,
              widget.currentDesktopPage,
              isPinnedSection: isPinnedSection,
              insideCategory: insideCategory,
            );
          },
          borderRadius: BorderRadius.circular(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildAppIcon(app, iconSize, themeState, appsState, notifCount: notifCount),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: Text(
                  app.name ?? '', 
                  style: TextStyle(color: textColor, fontSize: fontSize, height: 1.15), 
                  maxLines: 2, 
                  overflow: TextOverflow.ellipsis, 
                  textAlign: TextAlign.center
                ),
              ),
              if (desktopState.devMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: Text(
                    app.packageName?.split('.').last ?? '',
                    style: const TextStyle(color: Colors.blueAccent, fontSize: 8),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppListItem(
    AppInfo app,
    ThemeState themeState,
    AppsState appsState,
    DesktopState desktopState,
    SystemState systemState,
    Color textColor,
  ) {
    final int notifCount = appsState.appNotificationCounts[app.packageName] ?? 0;
    final double scale = desktopState.desktopIconScale.clamp(0.6, 1.8);
    final double baseSize = 32.0 * scale;
    final double itemHeight = math.max(48.0, 52.0 * scale);
    final double fontSize = desktopState.desktopFontSize;

    return RepaintBoundary(
      child: SizedBox(
        height: itemHeight, 
        child: Builder(
          builder: (ctx) => InkWell(
            onTap: () => _launchApp(app.packageName!, appsState, systemState),
            onLongPress: () {
              if (!ctx.mounted) return;
              final RenderBox box = ctx.findRenderObject() as RenderBox;
              final Offset pos = box.localToGlobal(Offset.zero);
              StartMenuContext.showAppContextMenu(
                ctx,
                pos,
                app,
                themeState,
                appsState,
                desktopState,
                systemState,
                widget.onOverlaysClosed,
                _showToast,
                widget.currentDesktopPage,
                isPinnedSection: false,
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                children: [
                  _buildAppIcon(app, baseSize, themeState, appsState, notifCount: notifCount),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(app.name ?? '', style: TextStyle(color: textColor, fontSize: fontSize, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (desktopState.devMode)
                          Text(app.packageName ?? '', style: const TextStyle(color: Colors.blueAccent, fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextHeader(String text, Color textColor, double fontSize) {
    return Container(
      height: 32,
      margin: const EdgeInsets.only(top: 8, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      alignment: Alignment.bottomLeft,
      child: Text(text, style: TextStyle(color: textColor, fontSize: fontSize, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildLetterHeader(String letter, Color textColor, Color accentColor) {
    return Container(
      height: 42,
      margin: const EdgeInsets.only(top: 8, bottom: 2),
      child: InkWell(
        onTap: () => setState(() => _showAlphabetGrid = true),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(4)),
                alignment: Alignment.center,
                child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlphabetGrid(Color textColor, Color bgColor, ThemeState themeState, List<String> activeLetters, bool isDark, Map<String, double> letterOffsets) {
    final List<String> alphabets = List.generate(26, (index) => String.fromCharCode(index + 65))..add('#');

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: GridView.builder(
          physics: const ClampingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: alphabets.length,
          itemBuilder: (context, index) {
            final letter = alphabets[index];
            final isActive = activeLetters.contains(letter);

            return InkWell(
              onTap: isActive
                  ? () {
                      setState(() => _showAlphabetGrid = false);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final offset = letterOffsets[letter];
                        if (offset != null && _listScrollController.hasClients) {
                          _listScrollController.animateTo(
                            offset,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      });
                    }
                  : null,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                decoration: BoxDecoration(
                  color: isActive ? themeState.currentAccentColor : (isDark ? Colors.white10 : Colors.black12),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isActive ? themeState.textOnAccentColor : textColor.withOpacity(0.3),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showCreateCategoryDialog(BuildContext context, ThemeState themeState, AppsState appsState) async {
    final isDark = themeState.isDarkMode;
    final accent = themeState.foregroundAccentColor;

    final String? folderName = await showDialog<String>(
      context: context,
      builder: (ctx) => _NewCategoryDialog(
        isDark: isDark,
        accentColor: accent,
      ),
    );

    if (folderName != null && folderName.trim().isNotEmpty) {
      appsState.createCustomCategory(folderName.trim());
      if (mounted) {
        _showToast("Created '${folderName.trim()}' folder");
      }
    }
  }

  void _showManageAppsInFolderDialog(BuildContext context, String categoryName, ThemeState themeState, AppsState appsState, DesktopState desktopState) {
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final currentCatPackages = List<String>.from(appsState.categoryMap[categoryName] ?? []);
    final Set<String> selected = currentCatPackages.toSet();

    final visibleApps = appsState.installedApps.where((app) {
      if (appsState.hiddenApps.contains(app.packageName)) return false;
      if (!desktopState.windowsSubsystem) return false;
      return true;
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            title: Text('Add Apps to $categoryName', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 260,
              height: 340,
              child: ListView.builder(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                itemCount: visibleApps.length,
                itemBuilder: (context, index) {
                  final app = visibleApps[index];
                  final isChecked = selected.contains(app.packageName);

                  String subtitleStr = '';
                  if (!isChecked) {
                    for (var entry in appsState.categoryMap.entries) {
                      if (entry.value.contains(app.packageName) && entry.key != categoryName) {
                        subtitleStr = 'Moves from ${entry.key}';
                        break;
                      }
                    }
                  }

                  return CheckboxListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    secondary: _buildAppIcon(app, 22, themeState, appsState),
                    title: Text(app.name ?? '', style: TextStyle(color: textColor, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: subtitleStr.isNotEmpty ? Text(subtitleStr, style: TextStyle(color: themeState.foregroundAccentColor, fontSize: 10)) : null,
                    value: isChecked,
                    activeColor: themeState.foregroundAccentColor,
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
                  appsState.setCategoryApps(categoryName, selected.toList());
                  Navigator.pop(ctx);
                  _showToast('Updated $categoryName');
                },
                child: Text('Done', style: TextStyle(color: themeState.foregroundAccentColor, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCategoryAppsDialog(
    String title,
    List<AppInfo> initialApps,
    ThemeState themeState,
    AppsState appsState,
    DesktopState desktopState,
    SystemState systemState,
    Color textColor,
    Color bgColor,
  ) {
    final isDark = themeState.isDarkMode;
    final solidBgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;

    showDialog(
      context: context,
      builder: (dialogCtx) => Consumer<AppsState>(
        builder: (context, currentAppsState, _) {
          final apps = currentAppsState.categorizedApps[title] ?? [];
          final isCustom = currentAppsState.isCustomCategory(title);

          return AlertDialog(
            backgroundColor: solidBgColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Row(
              children: [
                Expanded(
                  child: Text(title, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (isCustom)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    tooltip: 'Delete Folder',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      currentAppsState.deleteCustomCategory(title);
                      _showToast("Deleted '$title' folder");
                    },
                  ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260, maxHeight: 500),
              child: apps.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(
                        child: Text(
                          'No apps in this folder yet.\nTap "Manage Apps" below to select apps.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12, height: 1.4),
                        ),
                      ),
                    )
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 0.75,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: apps.length,
                      itemBuilder: (ctx, idx) => _buildAppGridItem(
                        apps[idx],
                        themeState,
                        currentAppsState,
                        desktopState,
                        systemState,
                        textColor,
                        isPinnedSection: false,
                        insideCategory: title,
                      ),
                    ),
            ),
            actions: [
              TextButton.icon(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                icon: Icon(Icons.settings_applications, size: 16, color: themeState.foregroundAccentColor),
                label: Text('Manage', style: TextStyle(color: themeState.foregroundAccentColor, fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _showManageAppsInFolderDialog(context, title, themeState, currentAppsState, desktopState);
                },
              ),
              TextButton(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('Close', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCategoryPreviewBox(List<AppInfo> apps, Color iconBg, ThemeState themeState, AppsState appsState, DesktopState desktopState) {
    final previewApps = apps.take(4).toList();
    final double scale = desktopState.desktopIconScale.clamp(0.6, 1.8);
    final double catIconSize = 32.0 * scale; 

    Widget iconSlot(int index) {
      if (index < previewApps.length) {
        return _buildAppIcon(previewApps[index], catIconSize, themeState, appsState);
      }
      return SizedBox(width: catIconSize, height: catIconSize);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: themeState.isDarkMode ? Colors.white10 : Colors.black12, width: 1),
      ),
      child: apps.isEmpty
          ? Center(
              child: Icon(Icons.create_new_folder_outlined, size: 28, color: themeState.isDarkMode ? Colors.white38 : Colors.black26),
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

  Widget _buildCategoryView(
    ThemeState themeState,
    AppsState appsState,
    DesktopState desktopState,
    SystemState systemState,
    Color textColor,
    Color cardBg,
    Color iconBg,
  ) {
    final categories = appsState.categorizedApps;
    final double fontSize = desktopState.desktopFontSize;

    return Expanded(
      child: RepaintBoundary(
        child: GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          physics: const ClampingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.80,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: categories.keys.length,
          itemBuilder: (ctx, idx) {
            final title = categories.keys.elementAt(idx);
            final catApps = categories[title]!;

            return RepaintBoundary(
              child: InkWell(
                onTap: () => _showCategoryAppsDialog(title, catApps, themeState, appsState, desktopState, systemState, textColor, cardBg),
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  children: [
                    Expanded(
                      child: _buildCategoryPreviewBox(catApps, iconBg, themeState, appsState, desktopState),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: TextStyle(fontSize: fontSize, color: textColor, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final appsState = context.watch<AppsState>();
    final desktopState = context.watch<DesktopState>();
    final systemState = context.watch<SystemState>();

    List<AppInfo> currentSearchApps = [];
    if (_searchQuery.isNotEmpty) {
      currentSearchApps = appsState.installedApps.where((app) {
        if (appsState.hiddenApps.contains(app.packageName)) return false;
        if (!desktopState.windowsSubsystem) return false;
        return (app.name ?? '').toLowerCase().contains(_searchQuery);
      }).toList();
    }

    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secText = isDark ? Colors.white70 : Colors.grey.shade600;
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;
    final searchBg = isDark ? const Color(0xFF333333).withOpacity(0.6) : Colors.white.withOpacity(0.6);
    final bottomBarBg = isDark ? const Color(0xFF1E1E1E).withOpacity(0.4) : const Color(0xFFE5E5E5).withOpacity(0.4);
    final categoryCardBg = isDark ? const Color(0xFF3A3A3A).withOpacity(0.7) : Colors.white.withOpacity(0.7);

    final List<AppInfo> pinnedApps = [];
    for (final pkg in appsState.pinnedStart) {
      if (pinnedApps.length >= 8) break;
      if (!appsState.hiddenApps.contains(pkg) && desktopState.windowsSubsystem && appsState.appMap.containsKey(pkg)) {
        pinnedApps.add(appsState.appMap[pkg]!);
      }
    }
    
    final List<AppInfo> recentAddedApps = [];
    for (final entry in appsState.recentlyAddedApps) {
      if (recentAddedApps.length >= 6) break;
      final pkg = entry.split('|')[0];
      if (!appsState.hiddenApps.contains(pkg) && appsState.appMap.containsKey(pkg)) {
        recentAddedApps.add(appsState.appMap[pkg]!);
      }
    }
    
    final List<AppInfo> recentUpdatedApps = [];
    for (final entry in appsState.recentlyUpdatedApps) {
      if (recentUpdatedApps.length >= 6) break;
      final pkg = entry.split('|')[0];
      if (!appsState.hiddenApps.contains(pkg) && appsState.appMap.containsKey(pkg)) {
        recentUpdatedApps.add(appsState.appMap[pkg]!);
      }
    }

    final sortedKeys = appsState.precomputedAlphabetKeys;
    final groupedApps = appsState.precomputedAlphabetGroups;

    final double scale = desktopState.desktopIconScale.clamp(0.6, 1.8);
    final double itemHeight = math.max(48.0, 52.0 * scale); 
    final double fontSize = desktopState.desktopFontSize;

    if ((_viewMode == 'List' || _showAlphabetGrid) && (_lastAppCount != appsState.installedApps.length || _cachedFlattenedList.isEmpty)) {
      _lastAppCount = appsState.installedApps.length;
      _cachedFlattenedList = [];
      _cachedLetterOffsets = {};
      double currentOffset = 0.0;

      if (desktopState.showRecentlyAdded) {
        if (recentAddedApps.isNotEmpty) {
          _cachedFlattenedList.add({'type': 'header', 'text': 'Recently added'});
          currentOffset += 32.0; 
          for (var app in recentAddedApps) {
            _cachedFlattenedList.add({'type': 'app', 'data': app});
            currentOffset += itemHeight;
          }
        }
        if (recentUpdatedApps.isNotEmpty) {
          _cachedFlattenedList.add({'type': 'header', 'text': 'Recently updated'});
          currentOffset += 32.0; 
          for (var app in recentUpdatedApps) {
            _cachedFlattenedList.add({'type': 'app', 'data': app});
            currentOffset += itemHeight;
          }
        }
      }

      for (var letter in sortedKeys) {
        final group = groupedApps[letter] ?? [];
        if (group.isNotEmpty) {
          _cachedLetterOffsets[letter] = currentOffset;
          _cachedFlattenedList.add({'type': 'letter', 'text': letter});
          currentOffset += 52.0; 
          
          for (var app in group) {
            _cachedFlattenedList.add({'type': 'app', 'data': app});
            currentOffset += itemHeight;
          }
        }
      }
      _cachedFlattenedList.add({'type': 'footer', 'height': 8.0});
    }

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () {},
        behavior: HitTestBehavior.opaque,
        child: Win11AcrylicContainer(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 1),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    textAlignVertical: TextAlignVertical.center,
                    style: TextStyle(color: textColor, fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search for apps, settings...',
                      hintStyle: TextStyle(color: secText, fontSize: 13),
                      prefixIcon: Icon(Icons.search, color: secText, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty 
                          ? IconButton(
                              icon: Icon(Icons.close, size: 16, color: textColor.withOpacity(0.7)),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                                FocusScope.of(context).unfocus();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: searchBg,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: borderColor)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: borderColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: themeState.foregroundAccentColor)),
                    ),
                  ),
                ),
              ),
              
              Expanded(
                child: _searchQuery.isNotEmpty
                    ? RepaintBoundary(
                        child: ListView.builder(
                          physics: const ClampingScrollPhysics(),
                          itemCount: currentSearchApps.length,
                          itemBuilder: (context, index) {
                            final app = currentSearchApps[index];
                            return RepaintBoundary(
                              child: Builder(
                                builder: (ctx) => Material(
                                  type: MaterialType.transparency,
                                  child: ListTile(
                                    leading: _buildAppIcon(app, 32 * scale, themeState, appsState),
                                    title: Text(app.name ?? 'Unknown', style: TextStyle(color: textColor, fontSize: fontSize)),
                                    onTap: () => _launchApp(app.packageName!, appsState, systemState),
                                    onLongPress: () {
                                      if (!ctx.mounted) return;
                                      final RenderBox box = ctx.findRenderObject() as RenderBox;
                                      final Offset pos = box.localToGlobal(Offset.zero);
                                      StartMenuContext.showAppContextMenu(
                                        ctx,
                                        pos,
                                        app,
                                        themeState,
                                        appsState,
                                        desktopState,
                                        systemState,
                                        widget.onOverlaysClosed,
                                        _showToast,
                                        widget.currentDesktopPage,
                                        isPinnedSection: false,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.max, 
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Pinned',
                                    style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                InkWell(
                                  onTap: () => setState(() => _isPinnedExpanded = !_isPinnedExpanded),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Icon(_isPinnedExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: textColor),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_isPinnedExpanded) ...[
                            const SizedBox(height: 8),
                            RepaintBoundary(
                              child: GridView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  childAspectRatio: 0.75, 
                                  crossAxisSpacing: 4,
                                  mainAxisSpacing: 8,
                                ),
                                itemCount: pinnedApps.length,
                                itemBuilder: (context, index) => _buildAppGridItem(
                                  pinnedApps[index],
                                  themeState,
                                  appsState,
                                  desktopState,
                                  systemState,
                                  textColor,
                                  isPinnedSection: true,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'All Apps',
                                    style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                if (_viewMode == 'Category') ...[
                                  InkWell(
                                    onTap: () => _showCreateCategoryDialog(context, themeState, appsState),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.create_new_folder_outlined, size: 14, color: themeState.foregroundAccentColor),
                                          const SizedBox(width: 3),
                                          Text(
                                            'New Folder',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: themeState.foregroundAccentColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
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
                                                children: ['Category', 'Grid', 'List'].map((mode) {
                                                  return InkWell(
                                                    onTap: () => Navigator.pop(context, mode),
                                                    borderRadius: BorderRadius.circular(6),
                                                    hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.max,
                                                        children: [
                                                          Expanded(child: Text('View: $mode', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w500))),
                                                          if (_viewMode == mode) Icon(Icons.check, size: 16, color: textColor),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ).then((val) async {
                                        if (val != null) {
                                          await Future.delayed(const Duration(milliseconds: 150));
                                          if (!mounted) return;
                                          setState(() {
                                            _viewMode = val;
                                            _showAlphabetGrid = false;
                                          });
                                        }
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'View: $_viewMode',
                                            style: TextStyle(fontSize: 11.5, color: secText, fontWeight: FontWeight.w500),
                                          ),
                                          const SizedBox(width: 2),
                                          Icon(Icons.keyboard_arrow_down, size: 14, color: secText),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_showAlphabetGrid)
                            _buildAlphabetGrid(textColor, Colors.transparent, themeState, sortedKeys, isDark, _cachedLetterOffsets)
                          else if (_viewMode == 'Category')
                            _buildCategoryView(themeState, appsState, desktopState, systemState, textColor, Colors.transparent, categoryCardBg)
                          else if (_viewMode == 'Grid')
                            Expanded(
                              child: RepaintBoundary(
                                child: GridView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                  physics: const ClampingScrollPhysics(),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 4,
                                    childAspectRatio: 0.75, 
                                    crossAxisSpacing: 4,
                                    mainAxisSpacing: 8,
                                  ),
                                  itemCount: appsState.installedApps.length,
                                  itemBuilder: (context, index) => _buildAppGridItem(
                                    appsState.installedApps[index],
                                    themeState,
                                    appsState,
                                    desktopState,
                                    systemState,
                                    textColor,
                                    isPinnedSection: false,
                                  ),
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: appsState.isLoadingApps 
                                ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
                                : RepaintBoundary(
                                    child: ListView.builder(
                                      controller: _listScrollController,
                                      physics: const ClampingScrollPhysics(),
                                      itemCount: _cachedFlattenedList.length,
                                      itemBuilder: (context, index) {
                                        final item = _cachedFlattenedList[index];
                                        
                                        if (item['type'] == 'header') {
                                          return _buildTextHeader(item['text'], textColor, fontSize);
                                        } else if (item['type'] == 'letter') {
                                          return _buildLetterHeader(item['text'], textColor, themeState.currentAccentColor);
                                        } else if (item['type'] == 'app') {
                                          return _buildAppListItem(
                                            item['data'], 
                                            themeState, 
                                            appsState, 
                                            desktopState, 
                                            systemState, 
                                            textColor
                                          );
                                        } else if (item['type'] == 'footer') {
                                          return SizedBox(height: item['height']);
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                  ),
                            ),
                        ],
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
                          final nav = Navigator.of(context);
                          widget.onOverlaysClosed();
                          nav.push(MaterialPageRoute(builder: (_) => const YourInfoScreen()));
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(color: themeState.currentAccentColor, shape: BoxShape.circle),
                                child: systemState.userImageBytes != null
                                    ? ClipOval(child: Image.memory(systemState.userImageBytes!, fit: BoxFit.cover))
                                    : Icon(Icons.person, size: 20, color: themeState.textOnAccentColor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  systemState.userName,
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
                          StartMenuContext.showPowerMenu(ctx, offset, isDark, widget.onOverlaysClosed, widget.onPowerTapped);
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewCategoryDialog extends StatefulWidget {
  final bool isDark;
  final Color accentColor;

  const _NewCategoryDialog({
    Key? key,
    required this.isDark,
    required this.accentColor,
  }) : super(key: key);

  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.isDark ? const Color(0xFF2B2B2B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Text(
        'New Folder',
        style: TextStyle(
          color: widget.isDark ? Colors.white : Colors.black87,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 260,
        child: TextField(
          controller: _controller,
          autofocus: true,
          style: TextStyle(
            color: widget.isDark ? Colors.white : Colors.black87,
            fontSize: 13,
          ),
          decoration: InputDecoration(
            hintText: 'Enter category name (e.g. Work, Games)',
            hintStyle: TextStyle(
              color: widget.isDark ? Colors.white54 : Colors.black54,
              fontSize: 12,
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: widget.accentColor, width: 1.5),
            ),
          ),
          onSubmitted: (val) {
            final text = val.trim();
            if (text.isNotEmpty) {
              Navigator.pop(context, text);
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: widget.isDark ? Colors.white54 : Colors.black54),
          ),
        ),
        TextButton(
          onPressed: () {
            final text = _controller.text.trim();
            if (text.isNotEmpty) {
              Navigator.pop(context, text);
            }
          },
          child: Text(
            'Create',
            style: TextStyle(
              color: widget.accentColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}