import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../launcher_state.dart';
import '../shared/app_window.dart';
import '../shared/calculator_app.dart';
import '../shared/browser_app.dart';
import '../settings/settings_app.dart';
import '../explorer/file_explorer_app.dart';

class WindowManager extends StatelessWidget {
  final double taskbarHeight;
  final GlobalKey<FileExplorerAppState> explorerKey;
  final VoidCallback onCloseOverlays;

  const WindowManager({
    Key? key,
    required this.taskbarHeight,
    required this.explorerKey,
    required this.onCloseOverlays,
  }) : super(key: key);

  Size _getResponsiveWindowSize(BuildContext context, double targetWidth, double targetHeight) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;
    if (isMobile) return Size(screenSize.width * 0.94, screenSize.height * 0.84);
    final maxWidth = screenSize.width * 0.90;
    final maxHeight = screenSize.height * 0.80;
    return Size(targetWidth > maxWidth ? maxWidth : targetWidth, targetHeight > maxHeight ? maxHeight : targetHeight);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isMobile = screenWidth < 600;

    return Stack(
      children: state.windowStack.where((id) => !id.contains('.')).map((windowId) {
        final isMinimized = state.minimizedApps.contains(windowId);
        final isMaximized = state.maximizedApps.contains(windowId) || (isMobile && windowId != 'calculator');

        final size = (isMobile && windowId == 'calculator') 
            ? Size(screenWidth * 0.90, 480) 
            : (isMobile 
                ? Size(screenWidth, math.max(0, screenHeight - taskbarHeight))
                : _getResponsiveWindowSize(context, windowId == 'explorer' ? 580 : (windowId == 'calculator' ? 320 : 600), windowId == 'calculator' ? 480 : 420));
                
        final pos = (isMobile && windowId == 'calculator')
            ? Offset((screenWidth - (screenWidth * 0.90)) / 2, math.max(0, screenHeight - 480 - taskbarHeight - 16))
            : (isMobile 
                ? Offset.zero
                : (windowId == 'explorer' ? state.fileExplorerPos : (windowId == 'calculator' ? state.calculatorPos : (windowId == 'browser' ? state.browserPos : state.settingsPos))));

        Widget content = const SizedBox.shrink();
        String title = "";
        IconData icon = Icons.apps;
        
        if (windowId == 'browser') { content = const BrowserApp(); title = 'Edge'; icon = Icons.language; }
        if (windowId == 'explorer') { content = FileExplorerApp(key: explorerKey); title = 'This PC'; icon = Icons.folder; }
        if (windowId == 'calculator') { content = const CalculatorApp(); title = 'Calculator'; icon = Icons.calculate; }
        if (windowId == 'settings') { content = const SettingsApp(); title = 'Settings'; icon = Icons.settings; }

        return AppWindow(
          title: title,
          icon: icon,
          position: pos,
          size: size,
          isMinimized: isMinimized,
          isMaximized: isMaximized,
          useSafeArea: windowId != 'settings' && windowId != 'browser',
          onClose: () => state.closeApp(windowId),
          onMinimize: () => state.minimizeApp(windowId),
          onMaximize: () => state.toggleMaximizeApp(windowId),
          onDrag: (delta) { if (!isMobile) state.updateWindowPos(windowId, delta); },
          onFocus: () { onCloseOverlays(); state.focusWindow(windowId); },
          content: content,
        );
      }).toList(),
    );
  }
}