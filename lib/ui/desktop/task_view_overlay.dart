import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/apps_state.dart';
import '../../states/theme_state.dart';
import '../../states/system_state.dart';
import '../../services/lazy_app_icon.dart';

class TaskViewOverlay extends StatelessWidget {
  final VoidCallback onClose;

  const TaskViewOverlay({Key? key, required this.onClose}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appsState = context.watch<AppsState>();
    final themeState = context.watch<ThemeState>();
    final systemState = context.read<SystemState>();
    
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    final recentApps = appsState.recentApps
        .where((pkg) => appsState.appMap.containsKey(pkg) && !appsState.hiddenApps.contains(pkg))
        .map((pkg) => appsState.appMap[pkg]!)
        .toList();

    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black.withOpacity(0.4),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 40, bottom: 20),
                  child: Text('Task View', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black54, blurRadius: 8)])),
                ),
                Expanded(
                  child: recentApps.isEmpty
                    ? Center(child: Text("No recent apps", style: TextStyle(color: Colors.white70, fontSize: 16)))
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        physics: const BouncingScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          childAspectRatio: 1.1,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: recentApps.length,
                        itemBuilder: (context, index) {
                          final app = recentApps[index];
                          return GestureDetector(
                            onTap: () {
                              onClose();
                              appsState.launchNativeApp(app.packageName!, systemState: systemState);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF2B2B2B).withOpacity(0.8) : Colors.white.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? Colors.white24 : Colors.white, width: 1.5),
                                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        app.packageName != null && themeState.cachedIconsPath != null && File('${themeState.cachedIconsPath}/${app.packageName}.png').existsSync()
                                            ? Image.file(File('${themeState.cachedIconsPath}/${app.packageName}.png'), width: 48, height: 48)
                                            : LazyAppIcon(packageName: app.packageName!, size: 48),
                                        const SizedBox(height: 12),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                          child: Text(app.name ?? '', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Positioned(
                                    top: 4, right: 4,
                                    child: IconButton(
                                      icon: Icon(Icons.close, size: 18, color: textColor.withOpacity(0.6)),
                                      onPressed: () {
                                        appsState.recentApps.remove(app.packageName);
                                        appsState.notifyListeners();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                ),
                const SizedBox(height: 100), 
              ],
            ),
          ),
        ),
      ),
    );
  }
}