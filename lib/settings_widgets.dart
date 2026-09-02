import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'launcher_state.dart';

class SettingsCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SettingsCard({
    Key? key, required this.title, this.subtitle, this.icon, this.trailing, this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<LauncherState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade300;
    final iconColor = isDark ? Colors.white70 : Colors.black54;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.grey.shade600;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6), border: Border.all(color: borderColor, width: 0.8)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap, borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 24, color: iconColor), const SizedBox(width: 16)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: titleColor)),
                      if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: TextStyle(fontSize: 11, color: subColor))]
                    ],
                  ),
                ),
                trailing ?? Icon(Icons.chevron_right, size: 22, color: titleColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ExpandableSettingsCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget children;

  const ExpandableSettingsCard({
    Key? key, required this.title, this.subtitle, this.icon, required this.isExpanded, required this.onToggle, required this.children,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<LauncherState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade300;
    final iconColor = isDark ? Colors.white70 : Colors.black54;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.grey.shade600;

    return Container(
      margin: const EdgeInsets.only(bottom: 10), 
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6), border: Border.all(color: borderColor, width: 0.8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle, borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), 
              child: Row(
                children: [
                  if (icon != null) ...[Icon(icon, size: 24, color: iconColor), const SizedBox(width: 16)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: titleColor)),
                        if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: TextStyle(fontSize: 11, color: subColor))]
                      ],
                    ),
                  ),
                  Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 22, color: titleColor),
                ],
              ),
            ),
          ),
          if (isExpanded) Padding(padding: const EdgeInsets.only(bottom: 8.0), child: children),
        ],
      ),
    );
  }
}

class SubScreenAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const SubScreenAppBar({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<LauncherState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF191919) : const Color(0xFFF3F3F3);
    final textColor = isDark ? Colors.white : Colors.black54;
    final iconColor = isDark ? Colors.white : Colors.black87;

    return AppBar(
      systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark, 
      backgroundColor: bgColor, surfaceTintColor: Colors.transparent, elevation: 0,
      leading: IconButton(icon: Icon(Icons.arrow_back, color: iconColor), onPressed: () => Navigator.pop(context)),
      title: Text(title, style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600)), titleSpacing: 0,
    );
  }
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}