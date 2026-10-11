import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../states/theme_state.dart';

enum WindowSnap { none, left, right }

class AppWindow extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget content;
  final Offset position;
  final Size size;
  final bool isMinimized;
  final bool isMaximized; 
  final bool isFocused;
  final bool useSafeArea; 
  final double taskbarHeight;
  final double safeAreaBottom;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize; 
  final ValueChanged<Offset> onPositionChanged;
  final VoidCallback onFocus;

  const AppWindow({
    Key? key, 
    required this.title, 
    required this.icon, 
    required this.content, 
    required this.position, 
    required this.size, 
    required this.isMinimized, 
    required this.isMaximized, 
    required this.isFocused,
    this.useSafeArea = true, 
    required this.taskbarHeight,
    required this.safeAreaBottom,
    required this.onClose, 
    required this.onMinimize, 
    required this.onMaximize, 
    required this.onPositionChanged, 
    required this.onFocus,
  }) : super(key: key);

  @override
  State<AppWindow> createState() => _AppWindowState();
}

class _AppWindowState extends State<AppWindow> {
  late final ValueNotifier<Offset> _positionNotifier;
  bool _isDragging = false;
  
  WindowSnap _currentSnap = WindowSnap.none;
  Offset? _lastPointerPos;
  Orientation? _lastOrientation;

  @override
  void initState() {
    super.initState();
    _positionNotifier = ValueNotifier<Offset>(widget.position);
  }

  @override
  void didUpdateWidget(covariant AppWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      _positionNotifier.value = widget.position;
    }
    if (!oldWidget.isMaximized && widget.isMaximized) {
      _currentSnap = WindowSnap.none;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentOrientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != null && _lastOrientation != currentOrientation) {
      if (_currentSnap != WindowSnap.none) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _currentSnap = WindowSnap.none);
        });
      }
    }
    _lastOrientation = currentOrientation;
  }

  @override
  void dispose() {
    _positionNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    
    final frameColor = isDark ? const Color(0xFF1F1F1F) : Colors.white;
    final borderColor = isDark ? Colors.white.withOpacity(0.15) : Colors.grey.shade300;
    final titleBarColor = isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE2E2E2);
    final contentBgColor = isDark ? const Color(0xFF191919) : Colors.white;
    final titleTextColor = isDark ? Colors.white : Colors.black87;
    final iconColor = isDark ? Colors.white70 : Colors.black54;

    final rawSize = MediaQuery.of(context).size;
    final screenWidth = rawSize.width;
    final screenHeight = rawSize.height;
    
    final safeAreaTop = MediaQuery.of(context).padding.top;
    const showTitleBar = true; 
    final double maximizedTop = showTitleBar ? safeAreaTop : 0.0;
    
    final double maximizedHeight = screenHeight - widget.taskbarHeight - widget.safeAreaBottom - (showTitleBar ? safeAreaTop : 0.0);

    Size currentSize;
    if (widget.isMaximized) {
      currentSize = Size(screenWidth, maximizedHeight);
    } else if (_currentSnap == WindowSnap.left || _currentSnap == WindowSnap.right) {
      currentSize = Size(screenWidth / 2, maximizedHeight);
    } else {
      currentSize = widget.size;
    }

    Widget windowContent = Provider<bool?>.value(
      value: widget.isFocused,
      child: Material(
        type: MaterialType.transparency,
        child: widget.content,
      ),
    );

    if (showTitleBar) {
      windowContent = MediaQuery.removePadding(context: context, removeTop: true, child: windowContent);
    } else if (widget.useSafeArea) {
      windowContent = SafeArea(bottom: false, child: windowContent);
    } else {
      windowContent = Padding(
        padding: EdgeInsets.only(top: safeAreaTop), 
        child: windowContent
      );
    }

    return ValueListenableBuilder<Offset>(
      valueListenable: _positionNotifier,
      builder: (context, dynamicPos, child) {
        
        Offset activePosition;
        if (widget.isMaximized) {
          activePosition = Offset(0, maximizedTop);
        } else if (_currentSnap == WindowSnap.left) {
          activePosition = Offset(0, maximizedTop);
        } else if (_currentSnap == WindowSnap.right) {
          activePosition = Offset(screenWidth / 2, maximizedTop);
        } else {
          activePosition = dynamicPos;
        }

        return Positioned(
          left: activePosition.dx, 
          top: activePosition.dy, 
          width: currentSize.width, 
          height: currentSize.height,
          child: Offstage(
            offstage: widget.isMinimized,
            child: RepaintBoundary(
              child: Listener(
                onPointerDown: (_) => widget.onFocus(),
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.isMaximized ? Colors.transparent : frameColor,
                    borderRadius: (widget.isMaximized || _currentSnap != WindowSnap.none) ? BorderRadius.zero : BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.isMaximized ? Colors.transparent : borderColor, 
                      width: widget.isMaximized ? 0 : 1
                    ),
                    boxShadow: (widget.isMaximized || _currentSnap != WindowSnap.none)
                        ? [] 
                        : [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.35 : 0.12), blurRadius: _isDragging ? 4 : 16, offset: Offset(0, _isDragging ? 2 : 8))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      if (showTitleBar)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) {
                            setState(() => _isDragging = true);
                            widget.onFocus();
  
                            if (_currentSnap != WindowSnap.none || widget.isMaximized) {
                              if (widget.isMaximized) widget.onMaximize();
                              
                              double relativeX = details.localPosition.dx / currentSize.width;
                              setState(() => _currentSnap = WindowSnap.none);
  
                              double newX = details.globalPosition.dx - (widget.size.width * relativeX);
                              double newY = details.globalPosition.dy - (showTitleBar ? safeAreaTop : 0) - 18; 
                              
                              _positionNotifier.value = Offset(newX, newY);
                            }
                          },
                          onPanUpdate: (details) {
                            _lastPointerPos = details.globalPosition;
                            if (!widget.isMaximized && _currentSnap == WindowSnap.none) {
                              Offset newPos = _positionNotifier.value + details.delta;
                              
                              final maxX = screenWidth - 50;
                              final maxY = screenHeight - widget.taskbarHeight - 50;
                              
                              if (newPos.dy < 0) newPos = Offset(newPos.dx, 0);
                              if (newPos.dy > maxY) newPos = Offset(newPos.dx, maxY);
                              if (newPos.dx < -currentSize.width + 50) newPos = Offset(-currentSize.width + 50, newPos.dy);
                              if (newPos.dx > maxX) newPos = Offset(maxX, newPos.dy);
  
                              _positionNotifier.value = newPos;
                            }
                          },
                          onPanEnd: (details) {
                            setState(() => _isDragging = false);
                            
                            if (!widget.isMaximized && _lastPointerPos != null) {
                              final px = _lastPointerPos!.dx;
                              final py = _lastPointerPos!.dy;
  
                              if (py <= safeAreaTop + 5) {
                                widget.onMaximize();
                              } else if (px <= 5) {
                                setState(() => _currentSnap = WindowSnap.left);
                                widget.onPositionChanged(Offset(0, maximizedTop));
                              } else if (px >= screenWidth - 5) {
                                setState(() => _currentSnap = WindowSnap.right);
                                widget.onPositionChanged(Offset(screenWidth / 2, maximizedTop));
                              } else {
                                widget.onPositionChanged(_positionNotifier.value);
                              }
                            }
                            _lastPointerPos = null;
                          },
                          onPanCancel: () {
                            setState(() => _isDragging = false);
                            _lastPointerPos = null;
                          },
                          onDoubleTap: () {
                            HapticFeedback.lightImpact();
                            widget.onMaximize();
                          }, 
                          child: Container(
                            height: 36, 
                            color: titleBarColor, 
                            padding: const EdgeInsets.only(left: 10),
                            child: Row(
                              children: [
                                Icon(widget.icon, size: 16, color: Colors.blueAccent), 
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.title, 
                                    style: TextStyle(color: titleTextColor, fontSize: 12, fontWeight: FontWeight.w500), 
                                    overflow: TextOverflow.ellipsis
                                  )
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildControlButton(Icons.remove, widget.onMinimize, iconColor),
                                    _buildControlButton(widget.isMaximized ? Icons.filter_none : Icons.crop_square, widget.onMaximize, iconColor),
                                    _buildControlButton(Icons.close, widget.onClose, iconColor, isClose: true),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: Container(
                          color: widget.isMaximized ? Colors.transparent : contentBgColor, 
                          child: windowContent
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onTap, Color color, {bool isClose = false}) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      }, 
      hoverColor: isClose ? Colors.red : Colors.grey.withOpacity(0.3),
      child: Container(
        width: 44, 
        height: 36, 
        alignment: Alignment.center, 
        child: Icon(icon, size: 15, color: color)
      ),
    );
  }
}