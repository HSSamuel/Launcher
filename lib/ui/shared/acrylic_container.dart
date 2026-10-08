import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/theme_state.dart';

class Win11AcrylicContainer extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  const Win11AcrylicContainer({
    Key? key,
    required this.child,
    this.borderRadius,
    this.border,
    this.padding,
    this.margin,
    this.width,
    this.height,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final accent = themeState.currentAccentColor;

    bool isFocused = true;
    try {
      isFocused = Provider.of<bool?>(context, listen: true) ?? true;
    } catch (_) {}

    final radius = borderRadius ?? BorderRadius.circular(10);
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;
    final effectiveBorder = border ?? Border.all(color: borderColor, width: 1);

    final baseBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
    final panelBg = Color.alphaBlend(accent.withOpacity(0.08), baseBg)
        .withOpacity(themeState.activePanelOpacity);

    final sigma = isFocused ? themeState.activeBlurSigma : 0.0;

    if (sigma <= 0.0) {
      return Container(
        width: width,
        height: height,
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: panelBg,
          borderRadius: radius,
          border: effectiveBorder,
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: child,
      );
    }

    // PERFORMANCE FIX: Stack decoupled backdrop filter behind the child
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            // Static blurred backdrop (GPU blurs wallpaper once)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: Container(
                  decoration: BoxDecoration(
                    color: panelBg,
                    borderRadius: radius,
                    border: effectiveBorder,
                  ),
                ),
              ),
            ),
            // Scrollable / interactive content renders ON TOP of the blur
            Container(
              padding: padding,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}