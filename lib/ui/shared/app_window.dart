import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../launcher_state.dart';

class AppWindow extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget content;
  final Offset position;
  final Size size;
  final bool isMinimized;
  final bool isMaximized; 
  final bool useSafeArea; 
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize; 
  final Function(Offset delta) onDrag;
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
    this.useSafeArea = true, 
    required this.onClose, 
    required this.onMinimize, 
    required this.onMaximize, 
    required this.onDrag, 
    required this.onFocus,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isMinimized) return const SizedBox.shrink();

    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    
    final frameColor = isDark ? const Color(0xFF1F1F1F) : Colors.white;
    final borderColor = isDark ? Colors.white.withOpacity(0.15) : Colors.grey.shade300;
    final titleBarColor = isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE2E2E2);
    final contentBgColor = isDark ? const Color(0xFF191919) : Colors.white;
    final titleTextColor = isDark ? Colors.white : Colors.black87;
    final iconColor = isDark ? Colors.white70 : Colors.black54;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isMobile = screenWidth < 600;
    final showTitleBar = !isMobile; 

    final currentPosition = isMaximized ? Offset.zero : position;
    final currentSize = isMaximized ? Size(screenWidth, screenHeight - 48) : size;
    Widget windowContent = content;

    if (showTitleBar) {
      windowContent = MediaQuery.removePadding(context: context, removeTop: true, child: windowContent);
    } else if (useSafeArea) {
      windowContent = SafeArea(bottom: false, child: windowContent);
    } else {
      // FIX: Apply top padding for full-screen apps (like Edge) so they don't overlap the physical camera notch/status bar.
      windowContent = Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top), 
        child: windowContent
      );
    }

    return Positioned(
      left: currentPosition.dx, top: currentPosition.dy, width: currentSize.width, height: currentSize.height,
      child: Listener(
        onPointerDown: (_) => onFocus(),
        child: Container(
          decoration: BoxDecoration(
            color: isMaximized ? Colors.transparent : frameColor,
            borderRadius: isMaximized ? BorderRadius.zero : BorderRadius.circular(8),
            border: Border.all(color: isMaximized ? Colors.transparent : borderColor, width: isMaximized ? 0 : 1),
            boxShadow: isMaximized ? [] : [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.4 : 0.15), blurRadius: 24, offset: const Offset(0, 12))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (showTitleBar)
                GestureDetector(
                  onPanUpdate: (details) { onFocus(); if (!isMaximized) onDrag(details.delta); },
                  child: Container(
                    height: 36, color: titleBarColor, padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Icon(icon, size: 16, color: Colors.blueAccent), const SizedBox(width: 8),
                        Expanded(child: Text(title, style: TextStyle(color: titleTextColor, fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildControlButton(Icons.remove, onMinimize, iconColor),
                            _buildControlButton(isMaximized ? Icons.filter_none : Icons.crop_square, onMaximize, iconColor),
                            _buildControlButton(Icons.close, onClose, iconColor, isClose: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: Container(color: isMaximized ? Colors.transparent : contentBgColor, child: windowContent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onTap, Color color, {bool isClose = false}) {
    return InkWell(
      onTap: onTap, 
      hoverColor: isClose ? Colors.red : null,
      child: Container(width: 32, height: 36, alignment: Alignment.center, child: Icon(icon, size: 14, color: color))
    );
  }
}