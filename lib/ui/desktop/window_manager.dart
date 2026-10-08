import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/apps_state.dart';
import '../shared/app_window.dart';
import '../shared/calculator_app.dart';
import '../shared/browser_app.dart';
import '../settings/settings_app.dart';
import '../explorer/file_explorer_app.dart';

class WindowManager extends StatelessWidget {
  final double taskbarHeight;
  final double safeAreaBottom;
  final GlobalKey<FileExplorerAppState> explorerKey;
  final VoidCallback onCloseOverlays;

  const WindowManager({
    Key? key,
    required this.taskbarHeight,
    required this.safeAreaBottom,
    required this.explorerKey,
    required this.onCloseOverlays,
  }) : super(key: key);

  Size _getResponsiveWindowSize(BuildContext context, String windowId) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width <= 600; 
    
    if (isMobile) return Size(screenSize.width * 0.85, screenSize.height * 0.70);
    
    if (windowId == 'calculator') {
      return const Size(320, 480);
    }
    
    final double targetWidth = math.min(900.0, screenSize.width * 0.75);
    final double targetHeight = math.min(650.0, screenSize.height * 0.75);
    
    return Size(targetWidth, targetHeight);
  }

  Offset _calculateCenter(double screenWidth, double winWidth, double taskbarTopY, double winHeight, bool isCalculator) {
    double centerX = (screenWidth - winWidth) / 2;
    double centerY = (taskbarTopY - winHeight) / 2;
    if (isCalculator) {
      return Offset(centerX, math.max(0.0, taskbarTopY - winHeight - 8));
    }
    return Offset(math.max(0.0, centerX), math.max(0.0, centerY));
  }

  @override
  Widget build(BuildContext context) {
    final appsState = context.watch<AppsState>();
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isMobile = screenWidth <= 600;
    
    final double taskbarTopY = screenHeight - taskbarHeight - safeAreaBottom;

    return Stack(
      children: appsState.windowStack.where((id) => !id.contains('.')).map((windowId) {
        final isMinimized = appsState.minimizedApps.contains(windowId);
        
        bool isMaximized;
        if (windowId == 'calculator') {
          isMaximized = false; 
        } else if (isMobile) {
          isMaximized = !appsState.maximizedApps.contains(windowId);
        } else {
          isMaximized = appsState.maximizedApps.contains(windowId);
        }

        final size = _getResponsiveWindowSize(context, windowId);
                
        Offset pos;
        if (windowId == 'explorer') pos = appsState.fileExplorerPos ?? _calculateCenter(screenWidth, size.width, taskbarTopY, size.height, false);
        else if (windowId == 'browser') pos = appsState.browserPos ?? _calculateCenter(screenWidth, size.width, taskbarTopY, size.height, false);
        else if (windowId == 'calculator') pos = appsState.calculatorPos ?? _calculateCenter(screenWidth, size.width, taskbarTopY, size.height, true);
        else pos = appsState.settingsPos ?? _calculateCenter(screenWidth, size.width, taskbarTopY, size.height, false);

        double maxDy = taskbarTopY - size.height;
        if (pos.dy > maxDy) {
          pos = Offset(pos.dx, math.max(0.0, maxDy));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            appsState.updateWindowPos(windowId, pos, isAbsolute: true);
          });
        }

        Widget content = const SizedBox.shrink();
        String title = "";
        IconData icon = Icons.apps;
        
        if (windowId == 'browser') { content = const BrowserApp(); title = 'Edge'; icon = Icons.language; }
        if (windowId == 'explorer') { content = FileExplorerApp(key: explorerKey); title = 'This PC'; icon = Icons.folder; }
        if (windowId == 'calculator') { content = const CalculatorApp(); title = 'Calculator'; icon = Icons.calculate; }
        if (windowId == 'settings') { content = const SettingsApp(); title = 'Settings'; icon = Icons.settings; }

        return AppWindow(
          key: ValueKey('window_$windowId'),
          title: title,
          icon: icon,
          position: pos,
          size: size,
          isMinimized: isMinimized,
          isMaximized: isMaximized,
          isFocused: appsState.windowStack.last == windowId,
          useSafeArea: windowId != 'settings' && windowId != 'browser',
          taskbarHeight: taskbarHeight,
          safeAreaBottom: safeAreaBottom,
          onClose: () => appsState.closeApp(windowId),
          onMinimize: () => appsState.minimizeApp(windowId),
          onMaximize: () => appsState.toggleMaximizeApp(windowId),
          onPositionChanged: (newPos) {
            appsState.updateWindowPos(windowId, newPos, isAbsolute: true);
          },
          onFocus: () { 
            onCloseOverlays(); 
            appsState.focusWindow(windowId); 
          },
          content: content,
        );
      }).toList(),
    );
  }
}