import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../models/desktop_item_model.dart';
import '../../launcher_state.dart';
import '../shared/desktop_icon.dart';

class DesktopWorkspace extends StatefulWidget {
  final double taskbarHeight;
  final double safeAreaTop;
  final int currentDesktopPage;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;
  final String? resizingWidgetId;
  final VoidCallback onExitResizeMode;
  final Function(Offset pos, String type, String targetName, VoidCallback? openAction) onContextMenu;
  final VoidCallback onCloseOverlays;

  const DesktopWorkspace({
    Key? key,
    required this.taskbarHeight,
    required this.safeAreaTop,
    required this.currentDesktopPage,
    required this.pageController,
    required this.onPageChanged,
    this.resizingWidgetId,
    required this.onExitResizeMode,
    required this.onContextMenu,
    required this.onCloseOverlays,
  }) : super(key: key);

  @override
  State<DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends State<DesktopWorkspace> {
  DateTime _lastPageTurn = DateTime.now();

  double _getIconScale(LauncherState state) {
    if (state.iconSize == 'Small') return 0.70;
    if (state.iconSize == 'Large') return 1.10;
    return 0.85;
  }

  // CRITICAL FIX: Safely excludes the requested 5 desktop icons from the circular plate mask
  Widget _getDesktopIconWidget(DesktopItemModel item, LauncherState state) {
    Widget iconChild;
    bool isSystem = item.type == 'system';
    bool leaveUncircled = false;
    
    if (isSystem) {
      String asset = 'folder';
      if (item.id == 'browser') { asset = 'edge'; leaveUncircled = true; }
      else if (item.id == 'calculator') { asset = 'calculator'; leaveUncircled = true; }
      else if (item.id == 'settings') { asset = 'settings'; leaveUncircled = true; }
      else if (item.id == 'recycle_bin') { asset = 'recycle'; leaveUncircled = true; }
      else if (item.id == 'my_files') { asset = 'folder'; leaveUncircled = true; } 
      
      iconChild = Image.asset('assets/icons/$asset.png', fit: BoxFit.contain);
    } else if (item.type == 'app' && item.package != null) {
      try {
        final appInfo = state.installedApps.firstWhere((a) => a.packageName == item.package);
        if (appInfo.icon != null && appInfo.icon!.isNotEmpty) {
          iconChild = Image.memory(appInfo.icon!, fit: BoxFit.contain);
        } else {
          iconChild = const Icon(Icons.android, color: Colors.green);
          isSystem = true; 
        }
      } catch (_) {
        iconChild = const Icon(Icons.android, color: Colors.green);
        isSystem = true;
      }
    } else {
      iconChild = const Icon(Icons.insert_drive_file, color: Colors.blueGrey);
      isSystem = true;
    }

    if (leaveUncircled) {
      return SizedBox(
        width: 36,
        height: 36,
        child: iconChild,
      );
    }

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white, 
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4, offset: const Offset(0, 2))
        ],
      ),
      child: ClipOval(
        child: isSystem
            ? Transform.scale(scale: 0.60, child: iconChild) 
            : Transform.scale(scale: 1.15, child: iconChild), 
      ),
    );
  }

  Widget _buildDesktopWidgetCard(DesktopItemModel item, LauncherState state, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E1E1E).withOpacity(0.85) : Colors.white.withOpacity(0.85);
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white70 : Colors.black54;

    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final timeStr = '$hour:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';

    Widget content = const SizedBox.shrink();

    switch (item.widgetType) {
      case 'clock':
        content = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(timeStr, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor, height: 1.0)),
            const SizedBox(height: 4),
            Text(dateStr, style: TextStyle(fontSize: 11, color: subColor)),
          ],
        );
        break;

      case 'weather':
        content = Row(
          children: [
            const Icon(Icons.wb_sunny, color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('32°C', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  Text('Sunny • Lagos', style: TextStyle(fontSize: 10, color: subColor), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        );
        break;

      case 'battery':
        content = Row(
          children: [
            const Icon(Icons.battery_full, color: Colors.blueAccent, size: 28),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('100%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                Text('Discharging', style: TextStyle(fontSize: 10, color: subColor)),
              ],
            ),
          ],
        );
        break;

      case 'storage':
        content = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage, size: 16, color: Colors.blueAccent),
                const SizedBox(width: 6),
                Text('Internal Storage', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: const LinearProgressIndicator(value: 0.65, minHeight: 6, backgroundColor: Colors.grey, color: Colors.blueAccent),
            ),
            const SizedBox(height: 4),
            Text('45 GB free of 128 GB', style: TextStyle(fontSize: 9, color: subColor)),
          ],
        );
        break;

      case 'calendar':
        content = Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(months[now.month - 1].toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                  Text('${now.day}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No events today', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor), overflow: TextOverflow.ellipsis),
                  Text('Tap to open Calendar', style: TextStyle(fontSize: 9, color: subColor)),
                ],
              ),
            ),
          ],
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isMobile = screenWidth < 600;

    final int cols = (isMobile ? state.portraitGridX : state.landscapeGridX).clamp(1, 20);
    final int rows = (isMobile ? state.portraitGridY : state.landscapeGridY).clamp(1, 20);
    final double availableHeight = math.max(10.0, screenHeight - widget.taskbarHeight - widget.safeAreaTop - 30);
    final double cellWidth = math.max(1.0, screenWidth / cols);
    final double cellHeight = math.max(1.0, availableHeight / rows);

    return Stack(
      children: [
        Positioned(
          top: widget.safeAreaTop + 8,
          left: 0,
          right: 0,
          height: availableHeight, 
          child: PageView.builder(
            controller: widget.pageController,
            physics: const BouncingScrollPhysics(),
            itemCount: state.desktopPages,
            onPageChanged: widget.onPageChanged,
            itemBuilder: (context, pageIndex) {
              final pageItems = state.desktopItems.where((i) => i.page == pageIndex).toList();

              return AnimatedBuilder(
                animation: widget.pageController,
                builder: (context, child) {
                  double pageOffset = 0.0;
                  if (widget.pageController.hasClients && widget.pageController.position.haveDimensions) {
                    pageOffset = (widget.pageController.page ?? pageIndex.toDouble()) - pageIndex;
                  }

                  Widget transformedChild = child!;

                  switch (state.pageTransition) {
                    case 'Crossfade':
                      transformedChild = Opacity(
                        opacity: (1.0 - pageOffset.abs()).clamp(0.0, 1.0),
                        child: transformedChild,
                      );
                      break;
                    case 'Zoom':
                      double scale = 1.0 - (pageOffset.abs() * 0.3).clamp(0.0, 1.0);
                      transformedChild = Transform.scale(
                        scale: scale,
                        child: Opacity(
                          opacity: (1.0 - pageOffset.abs()).clamp(0.0, 1.0),
                          child: transformedChild,
                        ),
                      );
                      break;
                    case 'Windmill':
                      transformedChild = Transform(
                        transform: Matrix4.rotationZ(pageOffset * -math.pi / 4),
                        alignment: Alignment.bottomCenter,
                        child: Opacity(
                          opacity: (1.0 - pageOffset.abs()).clamp(0.0, 1.0),
                          child: transformedChild,
                        ),
                      );
                      break;
                    case 'Cube':
                      if (pageOffset.abs() <= 1.0) {
                        Alignment alignment = pageOffset > 0 ? Alignment.centerRight : Alignment.centerLeft;
                        transformedChild = Transform(
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001) 
                            ..rotateY(-pageOffset * math.pi / 2),
                          alignment: alignment,
                          child: transformedChild,
                        );
                      } else {
                        transformedChild = const SizedBox.shrink();
                      }
                      break;
                    case 'Classical':
                    default:
                      break;
                  }

                  return transformedChild;
                },
                child: Builder(
                  builder: (dragContext) {
                    return DragTarget<DesktopItemModel>(
                      onWillAcceptWithDetails: (details) {
                        final RenderBox box = dragContext.findRenderObject() as RenderBox;
                        final Offset localPos = box.globalToLocal(details.offset);
                        
                        final now = DateTime.now();
                        if (now.difference(_lastPageTurn).inMilliseconds > 1000) {
                          if (localPos.dx > screenWidth - 75) {
                            if (pageIndex == state.desktopPages - 1) {
                               WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) state.addDesktopPage();
                               });
                            }
                            _lastPageTurn = now;
                            widget.pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                          }
                          else if (localPos.dx < 75 && pageIndex > 0) {
                            _lastPageTurn = now;
                            widget.pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                          }
                        }
                        return true;
                      },
                      onAcceptWithDetails: (details) {
                        final RenderBox box = dragContext.findRenderObject() as RenderBox;
                        final Offset localPos = box.globalToLocal(details.offset);
                        
                        int droppedCol = (localPos.dx / cellWidth).round().clamp(0, cols - details.data.spanX);
                        int droppedRow = (localPos.dy / cellHeight).round().clamp(0, rows - details.data.spanY);
                        
                        state.updateItemPosition(details.data.id, pageIndex, droppedCol, droppedRow);
                      },
                      builder: (context, candidateData, rejectedData) {
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(child: Container(color: Colors.transparent)),
                            ...pageItems.map((item) {
                              final isWidget = item.type == 'widget';
                              final isNativeWidget = item.type == 'native_widget';
                              final itemWidth = cellWidth * item.spanX;
                              final itemHeight = cellHeight * item.spanY;

                              Widget content = const SizedBox.shrink();
                              
                              if (isNativeWidget && item.appWidgetId != null) {
                                 content = SizedBox(
                                    width: itemWidth,
                                    height: itemHeight,
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
                                          return PlatformViewsService.initExpensiveAndroidView(
                                            id: params.id,
                                            viewType: 'NativeWidget',
                                            layoutDirection: TextDirection.ltr,
                                            creationParams: {'appWidgetId': item.appWidgetId},
                                            creationParamsCodec: const StandardMessageCodec(),
                                            onFocus: () {
                                              params.onFocusChanged(true);
                                            },
                                          )
                                            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
                                            ..create();
                                        },
                                      ),
                                    ),
                                 );
                              } else if (isWidget) {
                                 content = _buildDesktopWidgetCard(item, state, state.isDarkMode);
                              } else {
                                 content = Transform.scale(
                                      scale: _getIconScale(state),
                                      child: DesktopIcon(
                                        itemData: item,
                                        customIcon: _getDesktopIconWidget(item, state),
                                        label: item.label,
                                        onTap: () {
                                          widget.onCloseOverlays();
                                          if (item.type == 'system') {
                                            if (item.id == 'recycle_bin') {
                                              final rb = Directory('/storage/emulated/0/.RecycleBin');
                                              if (!rb.existsSync()) { try { rb.createSync(); } catch (_) {} }
                                              state.currentExplorerPath = rb.path;
                                              state.openApp('explorer');
                                            } else if (item.id == 'my_files') {
                                              state.currentExplorerPath = '/storage/emulated/0';
                                              state.openApp('explorer');
                                            } else {
                                              state.openApp(item.id);
                                            }
                                          } else if (item.type == 'app' && item.package != null) {
                                            state.launchNativeApp(item.package!);
                                          }
                                        },
                                        onSecondaryTap: () {
                                          widget.onContextMenu(
                                            Offset((item.col * cellWidth) + 40, (item.row * cellHeight) + widget.safeAreaTop + 40),
                                            'folder',
                                            item.label,
                                            () {
                                              if (item.type == 'app' && item.package != null) state.launchNativeApp(item.package!);
                                              else if (item.type == 'system') state.openApp(item.id);
                                            }
                                          );
                                        },
                                        onLongPress: () {
                                          widget.onContextMenu(
                                            Offset((item.col * cellWidth) + 40, (item.row * cellHeight) + widget.safeAreaTop + 40),
                                            'folder',
                                            item.label,
                                            () {
                                              if (item.type == 'app' && item.package != null) state.launchNativeApp(item.package!);
                                              else if (item.type == 'system') state.openApp(item.id);
                                            }
                                          );
                                        },
                                      ),
                                    );
                              }

                              Widget positionedChild = content;

                              if (isWidget || isNativeWidget) {
                                 final isResizing = widget.resizingWidgetId == item.id;
                                 if (isResizing) {
                                    double resizeAccX = 0;
                                    double resizeAccY = 0;
                                    positionedChild = Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        AbsorbPointer(
                                          absorbing: true,
                                          child: SizedBox(width: itemWidth, height: itemHeight, child: content),
                                        ),
                                        Positioned.fill(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.blueAccent.withOpacity(0.15),
                                              border: Border.all(color: Colors.blueAccent, width: 2),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          right: -12,
                                          bottom: -12,
                                          child: GestureDetector(
                                            onPanStart: (_) {
                                              resizeAccX = 0;
                                              resizeAccY = 0;
                                            },
                                            onPanUpdate: (dragDetails) {
                                              resizeAccX += dragDetails.delta.dx;
                                              resizeAccY += dragDetails.delta.dy;
                                              
                                              bool changed = false;
                                              int newSpanX = item.spanX;
                                              int newSpanY = item.spanY;

                                              if (resizeAccX > cellWidth * 0.5) {
                                                 newSpanX++; resizeAccX = 0; changed = true;
                                              } else if (resizeAccX < -cellWidth * 0.5) {
                                                 newSpanX--; resizeAccX = 0; changed = true;
                                              }

                                              if (resizeAccY > cellHeight * 0.5) {
                                                 newSpanY++; resizeAccY = 0; changed = true;
                                              } else if (resizeAccY < -cellHeight * 0.5) {
                                                 newSpanY--; resizeAccY = 0; changed = true;
                                              }
                                              
                                              if (changed) {
                                                 newSpanX = newSpanX.clamp(1, cols - item.col);
                                                 newSpanY = newSpanY.clamp(1, rows - item.row);
                                                 if (newSpanX != item.spanX || newSpanY != item.spanY) {
                                                    state.resizeDesktopItem(item.id, newSpanX, newSpanY, cellWidth, cellHeight);
                                                 }
                                              }
                                            },
                                            child: Container(
                                              width: 32, height: 32,
                                              decoration: const BoxDecoration(
                                                color: Colors.blueAccent, shape: BoxShape.circle,
                                                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                              ),
                                              child: const Icon(Icons.open_in_full, size: 16, color: Colors.white),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: -12, right: -12,
                                          child: GestureDetector(
                                            onTap: widget.onExitResizeMode,
                                            child: Container(
                                              width: 28, height: 28,
                                              decoration: const BoxDecoration(
                                                color: Colors.green, shape: BoxShape.circle,
                                                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                              ),
                                              child: const Icon(Icons.check, size: 16, color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                 } else if (!state.dragIcons) {
                                    positionedChild = GestureDetector(
                                      onSecondaryTapDown: (details) => widget.onContextMenu(details.globalPosition, 'folder', item.label, null),
                                      onLongPressStart: (details) => widget.onContextMenu(details.globalPosition, 'folder', item.label, null),
                                      child: content,
                                    );
                                 } else {
                                    positionedChild = GestureDetector(
                                      onSecondaryTapDown: (details) => widget.onContextMenu(details.globalPosition, 'folder', item.label, null),
                                      onLongPressStart: (details) => widget.onContextMenu(details.globalPosition, 'folder', item.label, null),
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
                              }

                              return Positioned(
                                left: item.col * cellWidth, top: item.row * cellHeight,
                                width: itemWidth, height: itemHeight,
                                child: positionedChild,
                              );
                            }).toList(),
                          ]
                        );
                      },
                    );
                  }
                ),
              );
            },
          ),
        ),

        if (state.desktopPages > 1)
          Positioned(
            bottom: widget.taskbarHeight + 4,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(state.desktopPages, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
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
    );
  }
}