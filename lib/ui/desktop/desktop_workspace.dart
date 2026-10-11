import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:installed_apps/app_info.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:path_provider/path_provider.dart';

import '../../models/desktop_item_model.dart';
import '../../states/theme_state.dart';
import '../../states/desktop_state.dart';
import '../../states/apps_state.dart';
import '../../states/system_state.dart';
import '../../services/native_bridge.dart';
import '../../services/lazy_app_icon.dart';
import '../shared/desktop_icon.dart';
import '../explorer/file_explorer_app.dart';

dynamic _isolateJsonDecode(String source) => jsonDecode(source);

class FastScrollPhysics extends PageScrollPhysics {
  const FastScrollPhysics({ScrollPhysics? parent}) : super(parent: parent);

  @override
  FastScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return FastScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => const SpringDescription(
        mass: 0.18,
        stiffness: 900.0,
        damping: 24.0,
      );
}

class DesktopWorkspace extends StatefulWidget {
  final double taskbarHeight;
  final double safeAreaTop;
  final int currentDesktopPage;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;
  final String? resizingWidgetId;
  final VoidCallback onExitResizeMode;
  final String? movingWidgetId;
  final VoidCallback onExitMoveMode;
  final Function(Offset pos, String type, String targetId, String targetName, VoidCallback? openAction) onContextMenu;
  final VoidCallback onCloseOverlays;
  final VoidCallback onDoubleTap;
  final GlobalKey<FileExplorerAppState>? explorerKey;

  const DesktopWorkspace({
    Key? key,
    required this.taskbarHeight,
    required this.safeAreaTop,
    required this.currentDesktopPage,
    required this.pageController,
    required this.onPageChanged,
    this.resizingWidgetId,
    required this.onExitResizeMode,
    this.movingWidgetId,
    required this.onExitMoveMode,
    required this.onContextMenu,
    required this.onCloseOverlays,
    required this.onDoubleTap,
    this.explorerKey,
  }) : super(key: key);

  @override
  State<DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends State<DesktopWorkspace> {
  DateTime _lastPageTurn = DateTime.now();

  String _activeRandomTransition = 'Classical';
  final List<String> _transitionTypes = [
    'Classical', '3D Cube', '3D Page Flip', '3D Card', 'Cube Carousel', '3D Swipe'
  ];

  Future<void> _launchSystemItem(DesktopItemModel item, AppsState appsState) async {
    if (item.id == 'recycle_bin') {
      String rootPath = '/storage/emulated/0';
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) rootPath = extDir.path.split('/Android')[0];
      } catch (_) {}
      
      final binPath = '$rootPath/.Win11RecycleBin';
      final rb = Directory(binPath);
      if (!rb.existsSync()) {
        try { 
          rb.createSync(recursive: true); 
          File('${rb.path}/.nomedia').createSync();
        } catch (_) {}
      }
      appsState.currentExplorerPath = rb.path;
      appsState.openApp('explorer');
      widget.explorerKey?.currentState?.navigateTo(rb.path);
    } else if (item.id == 'this_pc' || item.id == 'my_files') {
      appsState.currentExplorerPath = '/storage/emulated/0';
      appsState.openApp('explorer');
      widget.explorerKey?.currentState?.navigateTo('/storage/emulated/0');
    } else {
      appsState.openApp(item.id);
    }
  }

  void _executeShortcut(DesktopItemModel item, AppsState appsState) {
    if (item.path == null || item.path!.isEmpty) return;
    if (item.widgetType == 'web') {
      appsState.openApp('browser');
    } else {
      NativeBridge.instance.launchApp(item.path!);
    }
  }

  Widget _buildDesktopFolderIcon(DesktopItemModel item, AppsState appsState, ThemeState themeState) {
    final apps = item.folderApps?.map((pkg) => appsState.appMap[pkg]).whereType<AppInfo>().take(4).toList() ?? [];

    return FittedBox(
      fit: BoxFit.contain,
      child: Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.4), width: 1),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          spacing: 3,
          runSpacing: 3,
          children: apps.map((a) {
            if (a.packageName != null && themeState.customAppIcons.containsKey(a.packageName)) {
              return Image.file(
                File(themeState.customAppIcons[a.packageName]!),
                width: 13, height: 13, cacheWidth: 39, cacheHeight: 39, gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const Icon(Icons.android, size: 13, color: Colors.green),
              );
            }
            if (themeState.cachedIconsPath != null && a.packageName != null) {
              return Image.file(
                File('${themeState.cachedIconsPath}/${a.packageName}.png'),
                width: 13, height: 13, cacheWidth: 39, cacheHeight: 39, gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const Icon(Icons.android, size: 13, color: Colors.green),
              );
            }
            return a.packageName != null
                ? LazyAppIcon(packageName: a.packageName!, size: 13)
                : const Icon(Icons.android, size: 13, color: Colors.green);
          }).toList(),
        ),
      ),
    );
  }

  void _showRenameFolderDialog(BuildContext context, DesktopItemModel folderItem, DesktopState desktopState, ThemeState themeState) {
    final isDark = themeState.isDarkMode;
    final controller = TextEditingController(text: folderItem.label);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        title: Text('Rename Folder', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
          decoration: InputDecoration(
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: themeState.foregroundAccentColor, width: 1.5)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                desktopState.renameDesktopItem(folderItem.id, controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: Text('Save', style: TextStyle(color: themeState.foregroundAccentColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDesktopFolderDialog(BuildContext context, DesktopItemModel folderItem, AppsState appsState, DesktopState desktopState, ThemeState themeState) {
    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Folder',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (ctx, anim1, anim2) {
        return DragTarget<String>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (details) {
            final packageName = details.data;
            final app = appsState.appMap[packageName];
            Navigator.pop(ctx);

            desktopState.extractAppFromFolder(
              folderItem.id,
              packageName,
              app?.name ?? 'App',
              widget.currentDesktopPage,
              (pkg) => appsState.appMap[pkg]?.name ?? 'App',
            );

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${app?.name ?? "App"} moved to Desktop'), duration: const Duration(seconds: 1)),
            );
          },
          builder: (context, candidateData, rejectedData) {
            return Center(
              child: Material(
                color: Colors.transparent,
                child: DragTarget<String>(
                  onWillAcceptWithDetails: (_) => true,
                  onAcceptWithDetails: (_) {},
                  builder: (innerCtx, _, __) {
                    final apps = folderItem.folderApps?.map((pkg) => appsState.appMap[pkg]).whereType<AppInfo>().toList() ?? [];

                    return Container(
                      width: 320,
                      constraints: const BoxConstraints(maxHeight: 450),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                            child: Row(
                              children: [
                                Expanded(child: Text(folderItem.label, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold))),
                                IconButton(
                                  icon: Icon(Icons.edit, size: 18, color: themeState.foregroundAccentColor),
                                  tooltip: 'Rename Folder',
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _showRenameFolderDialog(context, folderItem, desktopState, themeState);
                                  },
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: apps.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    child: Text('Empty folder', textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
                                  )
                                : GridView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    shrinkWrap: true,
                                    physics: const BouncingScrollPhysics(),
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 4,
                                      childAspectRatio: 0.80,
                                      mainAxisSpacing: 16,
                                      crossAxisSpacing: 8,
                                    ),
                                    itemCount: apps.length,
                                    itemBuilder: (context, index) {
                                      final app = apps[index];

                                      Widget appIconWidget;
                                      if (app.packageName != null && themeState.customAppIcons.containsKey(app.packageName)) {
                                        appIconWidget = Image.file(
                                          File(themeState.customAppIcons[app.packageName]!),
                                          width: 32, height: 32, cacheWidth: 96, cacheHeight: 96, gaplessPlayback: true,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.android, size: 32, color: Colors.green),
                                        );
                                      } else if (themeState.cachedIconsPath != null && app.packageName != null) {
                                        appIconWidget = Image.file(
                                          File('${themeState.cachedIconsPath}/${app.packageName}.png'),
                                          width: 32, height: 32, cacheWidth: 96, cacheHeight: 96, gaplessPlayback: true,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.android, size: 32, color: Colors.green),
                                        );
                                      } else {
                                        appIconWidget = app.packageName != null
                                            ? LazyAppIcon(packageName: app.packageName!, size: 32)
                                            : const Icon(Icons.android, size: 32, color: Colors.green);
                                      }

                                      final itemContent = Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          appIconWidget,
                                          const SizedBox(height: 8),
                                          Text(app.name ?? '', style: TextStyle(color: textColor, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                                        ],
                                      );

                                      return LongPressDraggable<String>(
                                        data: app.packageName!,
                                        delay: const Duration(milliseconds: 140),
                                        feedback: Material(
                                          color: Colors.transparent,
                                          child: Opacity(
                                            opacity: 0.8,
                                            child: SizedBox(width: 80, child: itemContent),
                                          ),
                                        ),
                                        childWhenDragging: Opacity(opacity: 0.3, child: itemContent),
                                        child: InkWell(
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            appsState.launchNativeApp(app.packageName!, systemState: context.read<SystemState>());
                                          },
                                          child: itemContent,
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text('Close', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: anim1, curve: const Cubic(0.05, 0.7, 0.1, 1.0))),
            child: child,
          ),
        );
      },
    );
  }

  Widget _getDesktopIconWidget(DesktopItemModel item, AppsState appsState, ThemeState themeState, double iconScale) {
    Widget? iconChild;
    bool isSystem = item.type == 'system';
    bool leaveUncircled = false;

    if (item.type == 'folder') {
      iconChild = _buildDesktopFolderIcon(item, appsState, themeState);
      leaveUncircled = true;
    } else if (item.type == 'shortcut') {
      if (item.widgetType == 'call') {
        iconChild = const Icon(Icons.phone_forwarded, color: Colors.greenAccent, size: 28);
      } else if (item.widgetType == 'web') {
        iconChild = const Icon(Icons.language, color: Colors.blueAccent, size: 28);
      } else {
        iconChild = const Icon(Icons.terminal, color: Colors.amber, size: 28);
      }
      isSystem = true;
    } else if (isSystem) {
      String asset = 'folder';
      if (item.id == 'browser') { asset = 'edge'; leaveUncircled = true; }
      else if (item.id == 'calculator') { asset = 'calculator'; leaveUncircled = true; }
      else if (item.id == 'settings') { asset = 'settings'; leaveUncircled = true; }
      else if (item.id == 'recycle_bin') { asset = 'recycle'; leaveUncircled = true; }
      else if (item.id == 'this_pc' || item.id == 'my_files') { asset = 'folder'; leaveUncircled = true; }
      iconChild = Image.asset('assets/icons/$asset.png', fit: BoxFit.contain);
    } else if (item.type == 'app' && item.package != null) {
      if (themeState.customAppIcons.containsKey(item.package)) {
        iconChild = Image.file(
          File(themeState.customAppIcons[item.package]!),
          fit: BoxFit.contain, cacheWidth: 128, cacheHeight: 128, gaplessPlayback: true,
          errorBuilder: (_, __, ___) => LazyAppIcon(packageName: item.package!, size: 32.0 * iconScale),
        );
      } else if (themeState.cachedIconsPath != null) {
        iconChild = Image.file(
          File('${themeState.cachedIconsPath}/${item.package}.png'),
          fit: BoxFit.contain, cacheWidth: 128, cacheHeight: 128, gaplessPlayback: true,
          errorBuilder: (_, __, ___) => LazyAppIcon(packageName: item.package!, size: 32.0 * iconScale),
        );
      } else {
        iconChild = LazyAppIcon(
          packageName: item.package!,
          size: 32.0 * iconScale,
        );
      }
    } else if (item.type == 'file') {
      final pathStr = item.path ?? '';
      final name = pathStr.split('/').last;
      final hasExtension = name.contains('.');
      final ext = hasExtension ? name.split('.').last.toLowerCase() : '';
      
      if (!hasExtension) {
         iconChild = Image.asset('assets/icons/custom_folder.png', errorBuilder: (_, __, ___) => const Icon(Icons.folder, color: Colors.amber));
      } else {
         if (['png', 'jpg', 'jpeg', 'webp'].contains(ext)) {
            iconChild = ClipRRect(
               borderRadius: BorderRadius.circular(4),
               child: Image.file(File(pathStr), fit: BoxFit.cover, cacheWidth: 128)
            );
         } else if (ext == 'pdf') {
            iconChild = const Icon(Icons.picture_as_pdf, color: Colors.redAccent);
         } else if (['mp4', 'mkv'].contains(ext)) {
            iconChild = const Icon(Icons.video_file, color: Colors.purpleAccent);
         } else if (['mp3', 'wav'].contains(ext)) {
            iconChild = const Icon(Icons.audio_file, color: Colors.amber);
         } else if (['zip', 'rar', '7z'].contains(ext)) {
            iconChild = const Icon(Icons.folder_zip, color: Colors.orangeAccent);
         } else {
            iconChild = const Icon(Icons.insert_drive_file, color: Colors.blueGrey);
         }
      }
      isSystem = true;
    }

    iconChild ??= const Icon(Icons.apps, color: Colors.blueAccent);
    if (leaveUncircled) return iconChild;
    return isSystem ? Transform.scale(scale: 0.80, child: iconChild) : iconChild;
  }

  Widget _buildDesktopWidgetCard(DesktopItemModel item, ThemeState themeState, AppsState appsState) {
    final isDark = themeState.isDarkMode;
    final cardBg = isDark ? const Color(0xFF1E1E1E).withOpacity(0.9) : Colors.white.withOpacity(0.9);
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white70 : Colors.black54;

    // Retain the circular GPU Monitor untouched
    if (item.widgetType == 'system_monitor') {
      return Center(
        child: _LiveSystemMonitorWidget(
          textColor: textColor,
          subColor: subColor,
          accentColor: themeState.currentAccentColor,
          isDark: isDark,
        ),
      );
    }

    Widget content = const SizedBox.shrink();
    VoidCallback? onTap;

    switch (item.widgetType) {
      case 'clock':
        content = _LiveClockWidget(textColor: textColor, subColor: subColor);
        onTap = () => NativeBridge.instance.launchApp('content://com.android.calendar/time/');
        break;
      case 'weather':
        content = _LiveWeatherWidget(textColor: textColor, subColor: subColor);
        onTap = () => NativeBridge.instance.openWebSearch('weather forecast');
        break;
      case 'storage':
        content = _LiveStorageWidget(textColor: textColor, subColor: subColor, isDark: isDark);
        onTap = () {
          appsState.currentExplorerPath = '/storage/emulated/0';
          appsState.openApp('explorer');
        };
        break;
      case 'calendar':
        content = _LiveCalendarWidget(textColor: textColor, subColor: subColor);
        onTap = () => NativeBridge.instance.launchApp('content://com.android.calendar/time/');
        break;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), 
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );
  }

  Widget _buildStaticPageContent(
    BuildContext dragContext,
    int pageIndex,
    List<DesktopItemModel> pageItems,
    DesktopState desktopState,
    AppsState appsState,
    ThemeState themeState,
    SystemState systemState,
    double cellWidth,
    double cellHeight,
    int cols,
    int rows,
    double screenWidth,
  ) {
    return DragTarget<DesktopItemModel>(
      onWillAcceptWithDetails: (details) {
        final RenderBox box = dragContext.findRenderObject() as RenderBox;
        final Offset localPos = box.globalToLocal(details.offset);

        final itemWidth = cellWidth * details.data.spanX;
        final pointerX = localPos.dx + (itemWidth / 2);

        final now = DateTime.now();
        if (now.difference(_lastPageTurn).inMilliseconds > 500) {
          if (pointerX > screenWidth - 20) {
            if (pageIndex == desktopState.desktopPages - 1) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) desktopState.addDesktopPage();
              });
            }
            _lastPageTurn = now;
            widget.pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
          } else if (pointerX < 20 && pageIndex > 0) {
            _lastPageTurn = now;
            widget.pageController.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
          }
        }
        return true;
      },
      onAcceptWithDetails: (details) {
        final RenderBox box = dragContext.findRenderObject() as RenderBox;
        final Offset localPos = box.globalToLocal(details.offset);

        int droppedCol = (localPos.dx / cellWidth).round().clamp(0, math.max(0, cols - details.data.spanX));
        int droppedRow = (localPos.dy / cellHeight).round().clamp(0, math.max(0, rows - details.data.spanY));

        final targetItemIdx = pageItems.indexWhere((i) => i.col == droppedCol && i.row == droppedRow && i.id != details.data.id);

        if (targetItemIdx != -1 && details.data.type == 'app') {
          final targetItem = pageItems[targetItemIdx];
          if (targetItem.type == 'app' || targetItem.type == 'folder') {
            desktopState.mergeIntoFolder(targetItem.id, details.data.id);
            return;
          }
        }

        desktopState.updateItemPosition(details.data.id, pageIndex, droppedCol, droppedRow);
      },
      builder: (context, candidateData, rejectedData) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onCloseOverlays,
                onDoubleTap: widget.onDoubleTap,
                onSecondaryTapDown: (details) => widget.onContextMenu(details.globalPosition, 'desktop', '', '', null),
                onLongPressStart: (details) => widget.onContextMenu(details.globalPosition, 'desktop', '', '', null),
                child: Container(color: Colors.transparent),
              ),
            ),
            ...pageItems.map((item) {
              final isWidget = item.type == 'widget';
              final isNativeWidget = item.type == 'native_widget';
              final itemWidth = cellWidth * item.spanX;
              final itemHeight = cellHeight * item.spanY;
              final isMoving = widget.movingWidgetId == item.id;
              final isResizing = widget.resizingWidgetId == item.id;

              Widget content = const SizedBox.shrink();

              if (isNativeWidget && item.appWidgetId != null) {
                if (item.page != widget.currentDesktopPage) {
                  content = Container(
                    width: itemWidth,
                    height: itemHeight,
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                    child: const Center(child: Icon(Icons.widgets, color: Colors.white54)),
                  );
                } else {
                  content = GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onLongPressStart: (details) {
                      HapticFeedback.lightImpact();
                      widget.onContextMenu(
                        details.globalPosition,
                        'widget', item.id, item.label, null,
                      );
                    },
                    child: Stack(
                      children: [
                        SizedBox(
                          width: itemWidth, height: itemHeight,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: PlatformViewLink(
                              viewType: 'NativeWidget',
                              surfaceFactory: (BuildContext context, PlatformViewController controller) {
                                return AndroidViewSurface(
                                  controller: controller as AndroidViewController,
                                  gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
                                  hitTestBehavior: PlatformViewHitTestBehavior.opaque,
                                );
                              },
                              onCreatePlatformView: (PlatformViewCreationParams params) {
                                return PlatformViewsService.initSurfaceAndroidView(
                                  id: params.id, viewType: 'NativeWidget', layoutDirection: TextDirection.ltr,
                                  creationParams: {'appWidgetId': item.appWidgetId},
                                  creationParamsCodec: const StandardMessageCodec(),
                                  onFocus: () { params.onFocusChanged(true); },
                                )..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)..create();
                              },
                            ),
                          ),
                        ),
                        if (desktopState.dragIcons && !isResizing && !isMoving)
                          Positioned(
                            top: 0, left: 0, right: 0, height: 28,
                            child: Draggable<DesktopItemModel>(
                              data: item,
                              feedback: Material(
                                color: Colors.transparent,
                                child: Opacity(
                                  opacity: 0.8,
                                  child: Container(
                                    width: itemWidth, height: itemHeight,
                                    decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(10)),
                                    child: const Center(child: Icon(Icons.widgets, color: Colors.white)),
                                  ),
                                ),
                              ),
                              childWhenDragging: const SizedBox.shrink(),
                              child: Container(color: Colors.transparent),
                            ),
                          ),
                      ],
                    ),
                  );
                }
              } else if (isWidget) {
                content = GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapDown: (details) => widget.onContextMenu(details.globalPosition, 'widget', item.id, item.label, null),
                  onLongPressStart: (details) {
                    if (context.read<DesktopState>().gestureHapticFeedback) {
                      HapticFeedback.lightImpact();
                    }
                    widget.onContextMenu(
                      details.globalPosition,
                      'widget', item.id, item.label, null,
                    );
                  },
                  child: _buildDesktopWidgetCard(item, themeState, appsState),
                );
              } else {
                content = DesktopIcon(
                  itemData: item,
                  customIcon: _getDesktopIconWidget(item, appsState, themeState, desktopState.desktopIconScale),
                  label: item.label,
                  cellWidth: cellWidth,
                  onTap: () async {
                    widget.onCloseOverlays();
                    if (item.type == 'folder') {
                      _showDesktopFolderDialog(context, item, appsState, desktopState, themeState);
                    } else if (item.type == 'shortcut') {
                      _executeShortcut(item, appsState);
                    } else if (item.type == 'system') {
                      await _launchSystemItem(item, appsState); 
                    } else if (item.type == 'app' && item.package != null) {
                      appsState.launchNativeApp(item.package!, systemState: systemState);
                    } else if (item.type == 'file' && item.path != null) {
                      final isDir = Directory(item.path!).existsSync();
                      if (isDir) {
                         appsState.currentExplorerPath = item.path!;
                         appsState.openApp('explorer');
                         widget.explorerKey?.currentState?.navigateTo(item.path!);
                      } else {
                         NativeBridge.instance.openFile(item.path!);
                      }
                    }
                  },
                  onSecondaryTap: (globalPos) {
                    String cType = item.type;
                    if (item.type == 'folder') cType = 'desktop_folder';
                    if (item.type == 'shortcut') cType = 'shortcut';

                    widget.onContextMenu(
                      globalPos,
                      cType, item.id, item.label,
                      () async {
                        if (item.type == 'shortcut') {
                          _executeShortcut(item, appsState);
                        } else if (item.type == 'app' && item.package != null) {
                          appsState.launchNativeApp(item.package!, systemState: systemState);
                        } else if (item.type == 'system') {
                          await _launchSystemItem(item, appsState);
                        } else if (item.type == 'file' && item.path != null) {
                           final isDir = Directory(item.path!).existsSync();
                           if (isDir) appsState.requestExplorerNavigation(item.path!);
                           else NativeBridge.instance.openFile(item.path!);
                        } else if (item.type == 'folder') {
                           _showDesktopFolderDialog(context, item, appsState, desktopState, themeState);
                        }
                      },
                    );
                  },
                  onLongPress: (globalPos) {
                    String cType = item.type;
                    if (item.type == 'folder') cType = 'desktop_folder';
                    if (item.type == 'shortcut') cType = 'shortcut';

                    widget.onContextMenu(
                      globalPos,
                      cType, item.id, item.label,
                      () async {
                        if (item.type == 'shortcut') {
                          _executeShortcut(item, appsState);
                        } else if (item.type == 'app' && item.package != null) {
                          appsState.launchNativeApp(item.package!, systemState: systemState);
                        } else if (item.type == 'system') {
                          await _launchSystemItem(item, appsState);
                        } else if (item.type == 'file' && item.path != null) {
                           final isDir = Directory(item.path!).existsSync();
                           if (isDir) appsState.requestExplorerNavigation(item.path!);
                           else NativeBridge.instance.openFile(item.path!);
                        } else if (item.type == 'folder') {
                           _showDesktopFolderDialog(context, item, appsState, desktopState, themeState);
                        }
                      },
                    );
                  },
                );
              }

              if (isResizing) {
                double? dragDx;
                double? dragDy;

                return StatefulBuilder(
                  builder: (context, setLocalState) {
                    double addedWidth = dragDx ?? 0.0;
                    double addedHeight = dragDy ?? 0.0;

                    double finalWidth = (itemWidth + addedWidth).clamp(cellWidth, cellWidth * (cols - item.col));
                    double finalHeight = (itemHeight + addedHeight).clamp(cellHeight, cellHeight * (rows - item.row));

                    return Positioned(
                      left: item.col * cellWidth,
                      top: item.row * cellHeight,
                      width: itemWidth,
                      height: itemHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AbsorbPointer(
                            absorbing: true,
                            child: SizedBox(width: itemWidth, height: itemHeight, child: content),
                          ),
                          Positioned(
                            top: 0, left: 0, width: finalWidth, height: finalHeight,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.15),
                                border: Border.all(color: Colors.blueAccent, width: 2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          Positioned(
                            left: finalWidth - 48 + 8, top: finalHeight - 48 + 8,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanUpdate: (details) {
                                setLocalState(() {
                                  dragDx = (dragDx ?? 0.0) + details.delta.dx;
                                  dragDy = (dragDy ?? 0.0) + details.delta.dy;
                                });
                              },
                              onPanEnd: (_) {
                                int newSpanX = (finalWidth / cellWidth).round().clamp(1, cols - item.col);
                                int newSpanY = (finalHeight / cellHeight).round().clamp(1, rows - item.row);

                                if (newSpanX != item.spanX || newSpanY != item.spanY) {
                                  desktopState.resizeDesktopItem(item.id, newSpanX, newSpanY, cellWidth, cellHeight);
                                }
                                widget.onExitResizeMode();
                              },
                              onPanCancel: widget.onExitResizeMode,
                              child: Container(
                                width: 48, height: 48, color: Colors.transparent, alignment: Alignment.center,
                                child: Container(
                                  width: 32, height: 32, 
                                  decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]), 
                                  child: const Icon(Icons.open_in_full, size: 16, color: Colors.white)
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: finalWidth - 48 + 8, top: -8,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.onExitResizeMode,
                              child: Container(
                                width: 48, height: 48, color: Colors.transparent, alignment: Alignment.center,
                                child: Container(
                                  width: 28, height: 28, 
                                  decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]), 
                                  child: const Icon(Icons.check, size: 16, color: Colors.white)
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              } else if (isMoving) {
                return Positioned(
                  left: item.col * cellWidth,
                  top: item.row * cellHeight,
                  width: itemWidth,
                  height: itemHeight,
                  child: RepaintBoundary(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Draggable<DesktopItemModel>(
                          data: item,
                          onDragEnd: (_) => widget.onExitMoveMode(),
                          feedback: Material(
                            color: Colors.transparent,
                            child: Opacity(
                              opacity: 0.8,
                              child: Container(
                                width: itemWidth, height: itemHeight,
                                decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                                child: const Center(child: Icon(Icons.open_with, color: Colors.white, size: 32)),
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(opacity: 0.3, child: content),
                          child: Stack(
                            children: [
                              content,
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.blueAccent, width: 2),
                                  ),
                                  child: const Center(child: Icon(Icons.open_with, color: Colors.white, size: 32)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 4, right: 4,
                          child: GestureDetector(
                            onTap: widget.onExitMoveMode,
                            child: Container(
                              width: 28, height: 28,
                              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                              child: const Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else if (!desktopState.dragIcons) {
                return Positioned(
                  left: item.col * cellWidth,
                  top: item.row * cellHeight,
                  width: itemWidth,
                  height: itemHeight,
                  child: content,
                );
              } else {
                return Positioned(
                  left: item.col * cellWidth,
                  top: item.row * cellHeight,
                  width: itemWidth,
                  height: itemHeight,
                  child: Draggable<DesktopItemModel>(
                    data: item,
                    feedback: Material(
                      color: Colors.transparent,
                      child: Opacity(
                        opacity: 0.8,
                        child: isNativeWidget
                            ? Container(
                                width: itemWidth, height: itemHeight,
                                decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(10)),
                                child: const Center(child: Icon(Icons.widgets, color: Colors.white)),
                              )
                            : SizedBox(width: itemWidth, height: itemHeight, child: content),
                      ),
                    ),
                    childWhenDragging: Opacity(opacity: 0.3, child: content),
                    child: content,
                  ),
                );
              }
            }).toList(),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final desktopState = context.watch<DesktopState>();
    final appsState = context.watch<AppsState>();
    final systemState = context.read<SystemState>();

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    final double availableHeight = math.max(10.0, screenHeight - widget.taskbarHeight - widget.safeAreaTop - safeAreaBottom - 30);

    final int cols = (isPortrait ? desktopState.portraitGridX : desktopState.landscapeGridX).clamp(1, 20);
    final int rows = (isPortrait ? desktopState.portraitGridY : desktopState.landscapeGridY).clamp(1, 20);

    final double cellWidth = math.max(1.0, screenWidth / cols);
    final double cellHeight = math.max(1.0, availableHeight / rows);

    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned(
            top: widget.safeAreaTop + 8,
            left: 0,
            right: 0,
            height: availableHeight,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification) {
                  if (desktopState.pageTransition == 'Random') {
                    final page = widget.pageController.page;
                    if (page != null && page == page.roundToDouble()) {
                      final newTransition = _transitionTypes[math.Random().nextInt(_transitionTypes.length)];
                      if (_activeRandomTransition != newTransition) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _activeRandomTransition = newTransition);
                        });
                      }
                    }
                  }
                }
                return false;
              },
              child: PageView.builder(
                controller: widget.pageController,
                physics: (widget.resizingWidgetId != null || widget.movingWidgetId != null)
                    ? const NeverScrollableScrollPhysics()
                    : const FastScrollPhysics(parent: ClampingScrollPhysics()),
                itemCount: desktopState.desktopPages,
                onPageChanged: widget.onPageChanged,
                itemBuilder: (context, pageIndex) {
                  final pageItems = desktopState.desktopItems.where((i) => i.page == pageIndex).toList();
              
                  final staticPageTree = Builder(
                    builder: (dragContext) => _buildStaticPageContent(
                      dragContext,
                      pageIndex,
                      pageItems,
                      desktopState,
                      appsState,
                      themeState,
                      systemState,
                      cellWidth,
                      cellHeight,
                      cols,
                      rows,
                      screenWidth,
                    ),
                  );
              
                  final repaintedStaticTree = RepaintBoundary(child: staticPageTree);
              
                  return AnimatedBuilder(
                    animation: widget.pageController,
                    child: repaintedStaticTree,
                    builder: (context, child) {
                      double pageOffset = 0.0;
                      if (widget.pageController.hasClients && widget.pageController.position.haveDimensions) {
                        pageOffset = (widget.pageController.page ?? pageIndex.toDouble()) - pageIndex;
                      }
              
                      String effectiveTransition = desktopState.pageTransition;
                      if (effectiveTransition == 'Random') {
                        effectiveTransition = _activeRandomTransition;
                      }
              
                      Widget transformedChild = child!;
              
                      switch (effectiveTransition) {
                        case '3D Cube':
                          if (pageOffset.abs() <= 1.0) {
                            Alignment alignment = pageOffset > 0 ? Alignment.centerRight : Alignment.centerLeft;
                            transformedChild = Transform(
                              transform: Matrix4.identity()..setEntry(3, 2, 0.0015)..rotateY(-pageOffset * math.pi / 2),
                              alignment: alignment,
                              child: transformedChild,
                            );
                          } else { transformedChild = const SizedBox.shrink(); }
                          break;
                        case '3D Page Flip':
                          if (pageOffset.abs() <= 1.0) {
                            Alignment alignment = pageOffset > 0 ? Alignment.centerRight : Alignment.centerLeft;
                            transformedChild = Transform(
                              transform: Matrix4.identity()..setEntry(3, 2, 0.0015)..rotateY(-pageOffset * math.pi / 1.5),
                              alignment: alignment,
                              child: pageOffset.abs() > 0.5 ? const SizedBox.shrink() : transformedChild,
                            );
                          } else { transformedChild = const SizedBox.shrink(); }
                          break;
                        case '3D Card':
                          if (pageOffset.abs() <= 1.0) {
                            transformedChild = Transform(
                              transform: Matrix4.identity()..setEntry(3, 2, 0.0015)..rotateY(-pageOffset * math.pi / 3)..scale(1.0 - pageOffset.abs() * 0.15),
                              alignment: Alignment.center,
                              child: Opacity(opacity: (1.0 - pageOffset.abs()).clamp(0.0, 1.0), child: transformedChild),
                            );
                          }
                          break;
                        case 'Cube Carousel':
                          if (pageOffset.abs() <= 1.0) {
                            Alignment alignment = pageOffset > 0 ? Alignment.centerRight : Alignment.centerLeft;
                            transformedChild = Transform(
                              transform: Matrix4.identity()..setEntry(3, 2, 0.0015)..rotateY(-pageOffset * math.pi / 3)..scale(1.0 - pageOffset.abs() * 0.2),
                              alignment: alignment,
                              child: Opacity(opacity: (1.0 - pageOffset.abs()).clamp(0.0, 1.0), child: transformedChild),
                            );
                          }
                          break;
                        case '3D Swipe':
                          if (pageOffset.abs() <= 1.0) {
                            transformedChild = Transform(
                              transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(-pageOffset * math.pi / 6),
                              alignment: Alignment.center,
                              child: Opacity(opacity: (1.0 - pageOffset.abs()).clamp(0.0, 1.0), child: transformedChild),
                            );
                          }
                          break;
                        case 'Classical':
                        default:
                          break;
                      }
              
                      return transformedChild;
                    },
                  );
                },
              ),
            ),
          ),
          if (desktopState.desktopPages > 1)
            Positioned(
              bottom: widget.taskbarHeight + safeAreaBottom + 4,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(desktopState.desktopPages, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 6,
                    width: widget.currentDesktopPage == index ? 16 : 6,
                    decoration: BoxDecoration(
                      color: widget.currentDesktopPage == index ? Colors.white : Colors.white54,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 2)],
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

// --- BUILT-IN LIVE WIDGETS ---

class _LiveSystemMonitorWidget extends StatefulWidget {
  final Color textColor;
  final Color subColor;
  final Color accentColor;
  final bool isDark;

  const _LiveSystemMonitorWidget({
    Key? key, 
    required this.textColor, 
    required this.subColor, 
    required this.accentColor,
    required this.isDark,
  }) : super(key: key);

  @override
  State<_LiveSystemMonitorWidget> createState() => _LiveSystemMonitorWidgetState();
}

class _LiveSystemMonitorWidgetState extends State<_LiveSystemMonitorWidget> {
  bool _isOptimizing = false;
  double _ramPercent = 0.0;
  double _tempValue = 0.0;
  double _fanRpm = 0.0;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (mounted && !_isOptimizing) {
        try {
          final rawStats = await NativeBridge.instance.getSystemPerformanceStats();
          if (rawStats != null && mounted) {
            final ramPct = (rawStats['ram_percent'] as num?)?.toDouble() ?? 0.0;
            final temp = (rawStats['cpu_temp'] as num?)?.toDouble() ?? 0.0;
            
            setState(() {
              _ramPercent = ramPct;
              _tempValue = temp;
              _fanRpm = (1000.0 + (temp * 40.0)).clamp(0.0, 3200.0);
            });
          }
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _runOptimization() async {
    if (_isOptimizing) return;
    setState(() => _isOptimizing = true);
    
    final result = await NativeBridge.instance.optimizeSystem();
    final freedMb = result['freedMb'] ?? 0;
    final signaled = result['signaled'] ?? 0;
    
    await Future.delayed(const Duration(milliseconds: 300));
    
    if (mounted) {
      setState(() => _isOptimizing = false);
      ScaffoldMessenger.of(context).clearSnackBars();
      
      String message = freedMb > 0 
          ? 'Optimization complete. Signaled $signaled apps and freed $freedMb MB of RAM.'
          : 'System is already running optimally. Flushed memory cache.';
          
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: freedMb > 0 ? Colors.green.shade700 : Colors.blueGrey.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 200.0,
              height: 222.0, 
              child: Stack(
                clipBehavior: Clip.none, 
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    width: 200.0,
                    height: 200.0,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.isDark ? const Color(0xFF1E1E1E).withOpacity(0.92) : Colors.white.withOpacity(0.92),
                      border: Border.all(color: widget.isDark ? Colors.white24 : Colors.grey.shade200, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(widget.isDark ? 0.40 : 0.15),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 12.0, 
                    child: CustomPaint(
                      size: const Size(170.0, 170.0),
                      painter: _CircularGpuGaugePainter(
                        percent: _ramPercent / 100.0,
                        strokeWidth: 10.0,
                        trackColor: widget.isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 40.0, 
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          'GPU Optimization',
                          style: TextStyle(
                            fontSize: 14.0,
                            fontWeight: FontWeight.bold,
                            color: widget.textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_ramPercent.toInt()}%',
                          style: TextStyle(
                            fontSize: 52.0,
                            fontWeight: FontWeight.w900,
                            color: widget.textColor,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Temp', style: TextStyle(fontSize: 11.0, color: widget.subColor)),
                                Text('${_tempValue.toInt()}°C', style: TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold, color: widget.textColor)),
                              ],
                            ),
                            const SizedBox(width: 24),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Fan', style: TextStyle(fontSize: 11.0, color: widget.subColor)),
                                Text('${_fanRpm.toInt()} RPM', style: TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold, color: widget.textColor)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 0, 
                    child: SizedBox(
                      width: 150.0,
                      height: 44.0,
                      child: ElevatedButton(
                        onPressed: _isOptimizing ? null : _runOptimization,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4285F4), 
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22.0)),
                          elevation: 6,
                          shadowColor: const Color(0xFF4285F4).withOpacity(0.5),
                        ),
                        child: _isOptimizing
                            ? const SizedBox(width: 20.0, height: 20.0, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.rocket_launch, size: 17.0),
                                  const SizedBox(width: 8),
                                  const Text('Optimize', style: TextStyle(fontSize: 15.0, fontWeight: FontWeight.w700)),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CircularGpuGaugePainter extends CustomPainter {
  final double percent;
  final double strokeWidth;
  final Color trackColor;

  _CircularGpuGaugePainter({
    required this.percent,
    required this.strokeWidth,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    final paintTrack = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final paintProgress = Paint()
      ..shader = const SweepGradient(
        colors: [Colors.blueAccent, Colors.cyanAccent, Colors.greenAccent],
        stops: [0.0, 0.6, 1.0],
        transform: GradientRotation(math.pi), 
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi, 
      math.pi, 
      false,
      paintTrack,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi, 
      math.pi * percent.clamp(0.0, 1.0),
      false,
      paintProgress,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularGpuGaugePainter oldDelegate) {
    return oldDelegate.percent != percent ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.trackColor != trackColor;
  }
}

class _LiveClockWidget extends StatelessWidget {
  final Color textColor;
  final Color subColor;
  const _LiveClockWidget({required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime>(
      stream: TimeService.clockStream,
      builder: (context, snapshot) {
        final now = snapshot.data ?? DateTime.now();
        final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
        final timeStr = '$hour:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
        const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
        final dateStr = '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';

        return Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(timeStr, style: TextStyle(fontSize: 100, fontWeight: FontWeight.bold, color: textColor, height: 1.0)),
            const SizedBox(height: 16),
            Text(dateStr, style: TextStyle(fontSize: 36, color: subColor)),
          ],
        );
      },
    );
  }
}

class _LiveWeatherWidget extends StatefulWidget {
  final Color textColor;
  final Color subColor;
  const _LiveWeatherWidget({required this.textColor, required this.subColor});

  @override
  State<_LiveWeatherWidget> createState() => _LiveWeatherWidgetState();
}

class _LiveWeatherWidgetState extends State<_LiveWeatherWidget> {
  static String _temp = "--°";
  static String _desc = "Loading...";
  static String _loc = "Local Area";
  static IconData _icon = Icons.wb_sunny;
  static DateTime? _lastFetch;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    if (_lastFetch != null && DateTime.now().difference(_lastFetch!).inMinutes < 30) {
      return;
    }
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() { _desc = "Location Off"; });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() { _desc = "No Permission"; });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() { _desc = "Permission Denied"; });
        return;
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 5),
      );

      final url = 'https://api.open-meteo.com/v1/forecast?latitude=${pos.latitude}&longitude=${pos.longitude}&current=temperature_2m,weather_code';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = await compute(_isolateJsonDecode, response.body);
        final current = data['current'];
        final double tempVal = (current['temperature_2m'] as num).toDouble();
        final int code = (current['weather_code'] as num).toInt();

        String descText = 'Clear';
        IconData iconData = Icons.wb_sunny;
        if (code == 0) { descText = 'Clear'; iconData = Icons.wb_sunny; }
        else if (code >= 1 && code <= 3) { descText = 'Partly Cloudy'; iconData = Icons.cloud_queue; }
        else if (code == 45 || code == 48) { descText = 'Foggy'; iconData = Icons.foggy; }
        else if (code >= 51 && code <= 55) { descText = 'Drizzle'; iconData = Icons.grain; }
        else if (code >= 61 && code <= 65) { descText = 'Rainy'; iconData = Icons.water_drop; }
        else if (code >= 71 && code <= 75) { descText = 'Snowy'; iconData = Icons.ac_unit; }
        else if (code >= 95) { descText = 'Stormy'; iconData = Icons.thunderstorm; }

        String locText = "Local Area";
        try {
          final locRes = await http.get(Uri.parse(
            'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${pos.latitude}&longitude=${pos.longitude}&localityLanguage=en'
          )).timeout(const Duration(seconds: 5));
          if (locRes.statusCode == 200) {
            final locData = await compute(_isolateJsonDecode, locRes.body);
            locText = locData['city'] ?? locData['locality'] ?? 'Local Area';
          }
        } catch (_) {}

        _temp = "${tempVal.round()}°C";
        _desc = descText;
        _icon = iconData;
        _loc = locText;
        _lastFetch = DateTime.now();

        if (mounted) setState(() {});
      }
    } catch (_) {
      if (mounted && _temp == "--°") {
        setState(() { _desc = "Offline"; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(_icon, color: Colors.orange, size: 100),
        const SizedBox(width: 32),
        Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(_temp, style: TextStyle(fontSize: 84, fontWeight: FontWeight.bold, color: widget.textColor, height: 1.0)),
            const SizedBox(height: 12),
            Text('$_desc • $_loc', style: TextStyle(fontSize: 28, color: widget.subColor), textAlign: TextAlign.center),
          ],
        ),
      ],
    );
  }
}

class _LiveStorageWidget extends StatefulWidget {
  final Color textColor;
  final Color subColor;
  final bool isDark;
  const _LiveStorageWidget({required this.textColor, required this.subColor, required this.isDark});

  @override
  State<_LiveStorageWidget> createState() => _LiveStorageWidgetState();
}

class _LiveStorageWidgetState extends State<_LiveStorageWidget> {
  double _totalGB = 0;
  double _freeGB = 0;
  double _percent = 0;

  @override
  void initState() {
    super.initState();
    _loadStorage();
  }

  Future<void> _loadStorage() async {
    try {
      final stats = await NativeBridge.instance.getStorageStats();
      if (stats != null && mounted) {
        final total = stats['total'] ?? 0.0;
        final free = stats['free'] ?? 0.0;
        final tGB = total / (1024 * 1024 * 1024);
        final fGB = free / (1024 * 1024 * 1024);
        final uGB = tGB - fGB;
        setState(() {
          _totalGB = tGB;
          _freeGB = fGB;
          _percent = tGB > 0 ? (uGB / tGB).clamp(0.0, 1.0) : 0.0;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.storage, size: 54, color: Colors.blueAccent),
            const SizedBox(width: 16),
            Text(
              'Internal Storage',
              style: TextStyle(fontSize: 48, fontWeight: FontWeight.w700, color: widget.textColor),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: 380,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: LinearProgressIndicator(
              value: _percent,
              minHeight: 28,
              backgroundColor: widget.isDark ? Colors.white24 : Colors.grey.shade300,
              color: Colors.blueAccent,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _totalGB > 0
              ? '${_freeGB.toStringAsFixed(1)} GB free of ${_totalGB.toStringAsFixed(1)} GB'
              : 'Loading storage...',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w600,
            color: widget.subColor,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _LiveCalendarWidget extends StatefulWidget {
  final Color textColor;
  final Color subColor;
  const _LiveCalendarWidget({required this.textColor, required this.subColor});

  @override
  State<_LiveCalendarWidget> createState() => _LiveCalendarWidgetState();
}

class _LiveCalendarWidgetState extends State<_LiveCalendarWidget> {
  static String _upcomingEvent = "No upcoming events";
  static String _eventTimeStr = "Tap to open Calendar";
  static DateTime? _lastFetch;

  @override
  void initState() {
    super.initState();
    _fetchCalendar();
  }

  Future<void> _fetchCalendar() async {
    if (_lastFetch != null && DateTime.now().difference(_lastFetch!).inMinutes < 15) {
      return;
    }
    try {
      final calendarPlugin = DeviceCalendarPlugin();
      var permissionsGranted = await calendarPlugin.hasPermissions();
      if (permissionsGranted.isSuccess && !(permissionsGranted.data ?? false)) {
        permissionsGranted = await calendarPlugin.requestPermissions();
      }
      if (!permissionsGranted.isSuccess || !(permissionsGranted.data ?? false)) return;

      final calendarsResult = await calendarPlugin.retrieveCalendars();
      if (calendarsResult.isSuccess && calendarsResult.data != null) {
        late tz.Location safeLocation;
        try {
          safeLocation = tz.local;
        } catch (_) {
          safeLocation = tz.getLocation('UTC');
        }

        final now = DateTime.now();
        final startDate = tz.TZDateTime(safeLocation, now.year, now.month, now.day);
        final endDate = tz.TZDateTime(safeLocation, now.year, now.month, now.day, 23, 59, 59);

        final eventResults = await Future.wait(
          calendarsResult.data!.map(
            (cal) => calendarPlugin.retrieveEvents(
              cal.id,
              RetrieveEventsParams(startDate: startDate, endDate: endDate),
            ),
          ),
        );

        List<Map<String, dynamic>> rawEvents = [];
        for (var res in eventResults) {
          if (res.isSuccess && res.data != null) {
            for (var ev in res.data!) {
              if (ev.start == null) continue;
              final localStart = ev.start!.toLocal();
              final localEnd = ev.end?.toLocal() ?? localStart.add(const Duration(hours: 1));
              
              if (localEnd.isBefore(now)) continue;

              rawEvents.add({
                'title': ev.title ?? 'Event',
                'start': localStart,
                'isAllDay': ev.allDay ?? false,
              });
            }
          }
        }

        rawEvents.sort((a, b) => (a['start'] as DateTime).compareTo(b['start'] as DateTime));

        if (rawEvents.isNotEmpty) {
          final first = rawEvents.first;
          final DateTime start = first['start'];
          final bool isAllDay = first['isAllDay'] == true;
          
          String timeStr;
          if (isAllDay) {
            timeStr = 'All Day';
          } else if (start.isBefore(now)) {
            timeStr = 'Ongoing now';
          } else {
            int h = start.hour % 12 == 0 ? 12 : start.hour % 12;
            String ampm = start.hour >= 12 ? 'PM' : 'AM';
            String m = start.minute.toString().padLeft(2, '0');
            timeStr = 'At $h:$m $ampm';
          }

          _upcomingEvent = first['title'];
          _eventTimeStr = timeStr;
        } else {
          _upcomingEvent = "No upcoming events";
          _eventTimeStr = "Tap to open Calendar";
        }
        _lastFetch = DateTime.now();
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(0.18),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                months[now.month - 1].toUpperCase(),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${now.day}',
                style: TextStyle(
                  fontSize: 84,
                  fontWeight: FontWeight.w900,
                  color: widget.textColor,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 32),
        Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              _upcomingEvent,
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                color: widget.textColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _eventTimeStr,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: widget.subColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ],
    );
  }
}