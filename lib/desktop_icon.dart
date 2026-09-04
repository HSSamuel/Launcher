import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'launcher_state.dart';

class DesktopIcon extends StatelessWidget {
  final DesktopItemModel itemData;
  final IconData? icon;
  final Widget? customIcon; 
  final String label;
  final Color iconColor;
  final VoidCallback onTap;
  final VoidCallback onSecondaryTap;
  final VoidCallback onLongPress;

  const DesktopIcon({
    Key? key,
    required this.itemData,
    this.icon,
    this.customIcon,
    required this.label,
    this.iconColor = Colors.white,
    required this.onTap,
    required this.onSecondaryTap,
    required this.onLongPress,
  }) : super(key: key);

  // FIX: Created a builder method so Draggable gets unique widget instances 
  // instead of reusing the exact same element simultaneously
  Widget _buildContent() {
    return InkWell(
      onTap: onTap,
      onSecondaryTapDown: (_) => onSecondaryTap(),
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.contain,
                child: customIcon != null
                    ? SizedBox(width: 40, height: 40, child: Center(child: customIcon!))
                    : Icon(icon, color: iconColor, size: 40),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                height: 1.15,
                fontWeight: FontWeight.w500,
                shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<LauncherState>();
    
    if (!state.dragIcons) return _buildContent();

    return Draggable<DesktopItemModel>(
      data: itemData,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.8,
          child: SizedBox(
            width: 70, height: 80,
            child: _buildContent(),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _buildContent()),
      child: _buildContent(),
    );
  }
}