import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../states/desktop_state.dart';
import '../../states/apps_state.dart';
import '../../states/theme_state.dart';
import '../../models/desktop_item_model.dart';
import '../../services/lazy_app_icon.dart';

class DesktopIcon extends StatefulWidget {
  final DesktopItemModel itemData;
  final IconData? icon;
  final Widget? customIcon; 
  final String label;
  final Color iconColor;
  final double cellWidth;
  final VoidCallback onTap;
  final Function(Offset globalPosition) onSecondaryTap;
  final Function(Offset globalPosition) onLongPress;

  const DesktopIcon({
    Key? key,
    required this.itemData,
    this.icon,
    this.customIcon,
    required this.label,
    this.iconColor = Colors.white,
    required this.cellWidth,
    required this.onTap,
    required this.onSecondaryTap,
    required this.onLongPress,
  }) : super(key: key);

  @override
  State<DesktopIcon> createState() => _DesktopIconState();
}

class _DesktopIconState extends State<DesktopIcon> {
  bool _isPressed = false;
  Offset _lastTapPosition = Offset.zero; // 1. Add this variable to track the pointer

  Widget _buildContent(int notifCount, double iconScale, double fontSize, bool hapticsEnabled, Widget? resolvedIcon) {
    final double coreSize = 32.0 * iconScale; 

    return UnconstrainedBox(
      clipBehavior: Clip.none,
      child: SizedBox(
        width: widget.cellWidth, 
        child: InkWell(
          onTap: widget.onTap,
          onTapDown: (details) {
            _lastTapPosition = details.globalPosition; // 2. Capture the exact tap location here
            setState(() => _isPressed = true);
            if (hapticsEnabled) {
              HapticFeedback.lightImpact();
            }
          },
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onSecondaryTapDown: (details) => widget.onSecondaryTap(details.globalPosition),
          
          // 3. Revert to the standard onLongPress, passing the captured position
          onLongPress: () => widget.onLongPress(_lastTapPosition),
          
          borderRadius: BorderRadius.circular(4),
          child: AnimatedScale(
            scale: _isPressed ? 0.92 : 1.0,
            duration: const Duration(milliseconds: 60),
            curve: Curves.easeOutCubic,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center, 
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: coreSize,
                    height: coreSize,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        resolvedIcon != null
                            ? SizedBox(width: coreSize, height: coreSize, child: Center(child: resolvedIcon))
                            : Icon(widget.icon, color: widget.iconColor, size: coreSize),
                        
                        if (notifCount > 0)
                          Positioned(
                            top: -6 * iconScale, 
                            right: -6 * iconScale,
                            child: Transform.scale(
                              scale: iconScale,
                              alignment: Alignment.center,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent, 
                                  shape: BoxShape.circle, 
                                  border: Border.all(color: Colors.white, width: 1.5)
                                ),
                                child: Text(
                                  notifCount > 9 ? '9+' : notifCount.toString(), 
                                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, height: 1.0)
                                ),
                              ),
                            ),
                          )
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: fontSize,
                      height: 1.15,
                      fontWeight: FontWeight.w500,
                      shadows: const [Shadow(color: Colors.black87, blurRadius: 4)],
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

  @override
  Widget build(BuildContext context) {
    final desktopState = context.watch<DesktopState>();
    final dragIcons = desktopState.dragIcons;
    final iconScale = desktopState.desktopIconScale;
    final fontSize = desktopState.desktopFontSize;
    final haptics = desktopState.gestureHapticFeedback;
    
    final notifCount = widget.itemData.type == 'app' && widget.itemData.package != null
        ? context.select<AppsState, int>((state) => state.appNotificationCounts[widget.itemData.package] ?? 0)
        : 0;
    
    Widget? finalIcon = widget.customIcon;
    if (finalIcon == null && widget.itemData.type == 'app' && widget.itemData.package != null) {
      final themeState = context.read<ThemeState>();
      
      if (themeState.cachedIconsPath != null) {
        final cacheFile = File('${themeState.cachedIconsPath}/${widget.itemData.package}.png');
        
        finalIcon = Image.file(
          cacheFile, 
          fit: BoxFit.contain, 
          gaplessPlayback: true,
          cacheWidth: (32.0 * iconScale * 2.5).toInt().clamp(64, 256),
          cacheHeight: (32.0 * iconScale * 2.5).toInt().clamp(64, 256),
          errorBuilder: (_, __, ___) => LazyAppIcon(packageName: widget.itemData.package!, size: 32.0 * iconScale),
        );
      } else {
         finalIcon = LazyAppIcon(
           packageName: widget.itemData.package!,
           size: 32.0 * iconScale,
         );
      }
    }
    
    if (!dragIcons) {
      return RepaintBoundary(child: _buildContent(notifCount, iconScale, fontSize, haptics, finalIcon));
    }

    return RepaintBoundary(
      child: Draggable<DesktopItemModel>(
        data: widget.itemData,
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.8,
            child: _buildContent(notifCount, iconScale, fontSize, false, finalIcon),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: _buildContent(notifCount, iconScale, fontSize, false, finalIcon)),
        child: _buildContent(notifCount, iconScale, fontSize, haptics, finalIcon),
      ),
    );
  }
}