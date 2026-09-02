import 'package:flutter/material.dart';

class DesktopIcon extends StatelessWidget {
  final IconData? icon;
  final Widget? customIcon; 
  final String label;
  final Color iconColor;
  final VoidCallback onTap;

  const DesktopIcon({
    Key? key,
    this.icon,
    this.customIcon,
    required this.label,
    this.iconColor = Colors.white,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // FIXED: Expanded + FittedBox ensures the icon gracefully shrinks 
            // if the desktop grid is too small, completely preventing overflows!
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
}