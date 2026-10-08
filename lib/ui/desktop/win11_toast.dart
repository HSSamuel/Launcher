import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/theme_state.dart';
import '../../states/apps_state.dart';
import '../../services/native_bridge.dart';
import '../../services/lazy_app_icon.dart';

class Win11ToastWidget extends StatefulWidget {
  final Map<String, dynamic> event;
  final VoidCallback onDismiss;

  const Win11ToastWidget({
    Key? key,
    required this.event,
    required this.onDismiss,
  }) : super(key: key);

  @override
  State<Win11ToastWidget> createState() => _Win11ToastWidgetState();
}

class _Win11ToastWidgetState extends State<Win11ToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnim;
  Timer? _autoDismissTimer;
  bool _isReplying = false;
  final TextEditingController _replyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _slideAnim = Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _animController.forward();
    _startTimer();
  }

  void _startTimer() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(const Duration(seconds: 7), () {
      if (!_isReplying && mounted) _close();
    });
  }

  void _close() async {
    if (!mounted) return;
    await _animController.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _animController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  void _executeAction(int? actionIndex) async {
    final appsState = context.read<AppsState>();

    if (widget.event['_isUpdateToast'] == true) {
      NativeBridge.instance.launchApp(widget.event['_updateUrl'] ?? 'market://details?id=com.samuel.winlauncher');
    } else if (widget.event['_isBirthdayToast'] == true) {
      NativeBridge.instance.launchApp('content://com.android.calendar/time/');
    } else if (widget.event['_isCalendarReminder'] == true) {
      final epoch = widget.event['_eventStartEpoch'] ?? DateTime.now().millisecondsSinceEpoch;
      NativeBridge.instance.launchApp('content://com.android.calendar/time/$epoch');
    } else if (widget.event['_isAppInstall'] == true) {
      final pkg = widget.event['_installPkg'] ?? widget.event['package'];
      if (actionIndex == 1) {
        appsState.launchNativeApp(pkg);
      } else if (actionIndex == 2) {
        appsState.togglePinToStart(pkg);
      }
    } else if (widget.event['_isFileToast'] == true) {
      final path = widget.event['_filePath'];
      if (actionIndex == 1) {
        NativeBridge.instance.openFile(path);
      } else if (actionIndex == 2) {
        final file = File(path);
        appsState.requestExplorerNavigation(file.parent.path);
        appsState.highlightFileName = file.path.split('/').last;
      }
    } else {
      await NativeBridge.instance.triggerNotificationAction(
        widget.event['key'], 
        actionIndex ?? -1, 
        replyText: _replyController.text.trim(),
      );
    }
    _close();
  }

  Widget _buildAppIcon(
    String packageName, 
    double size, 
    ThemeState themeState, 
    AppsState appsState, 
    {Widget? fallback}
  ) {
    Widget fallbackWidget = fallback ?? Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: themeState.currentAccentColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.android, color: themeState.currentAccentColor, size: size * 0.6),
    );

    if (packageName.isEmpty || packageName == 'system') {
      return fallbackWidget;
    }

    // 1. Custom Icon Pack Override
    if (themeState.customAppIcons.containsKey(packageName)) {
      final file = File(themeState.customAppIcons[packageName]!);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.22),
          child: Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => fallbackWidget,
          ),
        );
      }
    }

    // 2. In-Memory AppsState Cache (Bypasses hanging IPC calls for newly installed apps)
    final appInfo = appsState.appMap[packageName];
    if (appInfo?.icon != null && appInfo!.icon!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.memory(
          appInfo.icon!,
          width: size,
          height: size,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallbackWidget,
        ),
      );
    }

    // 3. Disk Cache
    if (themeState.cachedIconsPath != null) {
      final iconFile = File('${themeState.cachedIconsPath}/$packageName.png');
      if (iconFile.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.22),
          child: Image.file(
            iconFile,
            width: size,
            height: size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => LazyAppIcon(
              packageName: packageName,
              size: size,
              fallbackIcon: fallbackWidget,
            ),
          ),
        );
      }
    }

    // 4. Lazy Fetch Fallback
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: LazyAppIcon(
        packageName: packageName,
        size: size,
        fallbackIcon: fallbackWidget,
      ),
    );
  }

  Widget _buildLeadingWidget(
    bool isDark,
    ThemeState themeState,
    AppsState appsState,
    bool isAppInstall,
    bool isUpdate,
    bool isBday,
    bool isCalReminder,
    bool isFile,
    String pkg,
  ) {
    if (isAppInstall) {
      final installPkg = widget.event['_installPkg'] ?? pkg;
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.white12 : Colors.black12, width: 0.8),
        ),
        alignment: Alignment.center,
        child: _buildAppIcon(
          installPkg,
          36,
          themeState,
          appsState,
          fallback: Icon(Icons.apps, color: themeState.foregroundAccentColor, size: 28),
        ),
      );
    }

    if (isUpdate || isBday || isCalReminder || isFile) {
      IconData iconData = Icons.notifications;
      if (isUpdate) iconData = Icons.system_update;
      if (isBday) iconData = Icons.celebration;
      if (isCalReminder) iconData = Icons.event;
      if (isFile) iconData = Icons.insert_drive_file;

      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: themeState.currentAccentColor,
          shape: BoxShape.circle,
        ),
        child: Icon(iconData, color: themeState.textOnAccentColor, size: 26),
      );
    }

    final String? largeIconPath = widget.event['largeIcon'] as String?;
    if (largeIconPath != null && largeIconPath.isNotEmpty) {
      final file = File(largeIconPath);
      if (file.existsSync()) {
        return ClipOval(
          child: Image.file(
            file,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            cacheWidth: 144,
            cacheHeight: 144,
            errorBuilder: (_, __, ___) => _buildAppIconContainer(pkg, isDark, themeState, appsState),
          ),
        );
      }
    }

    return _buildAppIconContainer(pkg, isDark, themeState, appsState);
  }

  Widget _buildAppIconContainer(String pkg, bool isDark, ThemeState themeState, AppsState appsState) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12, width: 0.8),
      ),
      alignment: Alignment.center,
      child: _buildAppIcon(
        pkg,
        36,
        themeState,
        appsState,
        fallback: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: themeState.currentAccentColor,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.person, color: themeState.textOnAccentColor, size: 26),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final appsState = context.watch<AppsState>();
    final isDark = themeState.isDarkMode;

    final primaryText = isDark ? Colors.white : Colors.black87;
    final secText = isDark ? Colors.white70 : Colors.grey.shade700;
    final cardBg = isDark ? const Color(0xFF222222) : const Color(0xFFF9F9F9);
    final borderCol = isDark ? Colors.white24 : Colors.grey.shade300;
    
    final screenWidth = MediaQuery.of(context).size.width;
    final toastWidth = math.min(290.0, screenWidth * 0.85);

    bool isUpdate = widget.event['_isUpdateToast'] == true;
    bool isBday = widget.event['_isBirthdayToast'] == true;
    bool isAppInstall = widget.event['_isAppInstall'] == true;
    bool isFile = widget.event['_isFileToast'] == true;
    bool isCalReminder = widget.event['_isCalendarReminder'] == true;

    String pkg = widget.event['package'] ?? 'system';
    String appName = pkg;
    
    if (isUpdate) {
      appName = "System Update";
    } else if (isBday) {
      appName = "Calendar Event";
    } else if (isCalReminder) {
      appName = "Calendar Reminder";
    } else if (isFile) {
      appName = "File Manager";
    } else if (isAppInstall) {
      appName = "Package Installer";
    } else {
      final appInfo = appsState.appMap[pkg];
      if (appInfo?.name != null && appInfo!.name!.trim().isNotEmpty) {
        appName = appInfo.name!.trim();
      } else {
        if (appName.contains('.')) appName = appName.split('.').last;
        if (appName.toLowerCase() == 'gm') {
          appName = "Gmail";
        } else if (appName.toLowerCase().contains('telegram')) {
          appName = "Telegram";
        } else if (appName.toLowerCase().contains('whatsapp')) {
          appName = "WhatsApp";
        } else if (appName.isNotEmpty) {
          appName = appName[0].toUpperCase() + appName.substring(1);
        }
      }
    }

    Widget appIcon;
    if (isUpdate || isBday || isFile || isCalReminder || isAppInstall) {
      IconData base = Icons.notifications;
      if (isUpdate) base = Icons.system_update;
      if (isBday) base = Icons.cake;
      if (isFile) base = Icons.download_done;
      if (isCalReminder) base = Icons.event_available;
      if (isAppInstall) base = Icons.check_circle;

      appIcon = Icon(base, color: themeState.foregroundAccentColor, size: 16);
    } else {
      appIcon = _buildAppIcon(pkg, 16, themeState, appsState);
    }

    String title = widget.event['title']?.toString().trim() ?? "";
    String content = widget.event['text']?.toString().trim() ?? "";
    
    if (title.isNotEmpty && content.startsWith('$title:')) {
      content = content.substring(title.length + 1).trim();
    }
    
    List<dynamic> rawActions = widget.event['actions'] ?? [];
    Map<String, dynamic>? replyAction;
    List<Map<String, dynamic>> otherActions = [];

    for (var rawAction in rawActions) {
      if (rawAction is Map) {
        final action = Map<String, dynamic>.from(rawAction);
        String aTitle = action['title']?.toString().toLowerCase() ?? '';
        if (aTitle.contains('reply')) {
          replyAction = action;
        } else {
          otherActions.add(action);
        }
      }
    }

    return SlideTransition(
      position: _slideAnim,
      child: Dismissible(
        key: ValueKey('dismiss_${widget.event['_toastId'] ?? widget.event['key']}'),
        direction: DismissDirection.startToEnd,
        onDismissed: (direction) {
          _autoDismissTimer?.cancel();
          widget.onDismiss();
        },
        child: Container(
          width: toastWidth, 
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderCol),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 6))],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _executeAction(-1),
              onHover: (isHovering) {
                if (isHovering) {
                  _autoDismissTimer?.cancel();
                } else if (!_isReplying) {
                  _startTimer();
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        appIcon,
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            appName, 
                            style: TextStyle(fontSize: 12, color: primaryText, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: _close,
                          child: Icon(Icons.close, size: 16, color: secText),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLeadingWidget(
                          isDark,
                          themeState,
                          appsState,
                          isAppInstall,
                          isUpdate,
                          isBday,
                          isCalReminder,
                          isFile,
                          pkg,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryText), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(content, style: TextStyle(fontSize: 12, color: secText), maxLines: 2, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    if (otherActions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: otherActions.map((action) {
                            return InkWell(
                              onTap: () => _executeAction(action['index']),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                                child: Text(action['title'] ?? 'Action', style: TextStyle(fontSize: 11, color: themeState.foregroundAccentColor, fontWeight: FontWeight.bold)),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      
                    if (replyAction != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 36,
                                child: TextField(
                                  controller: _replyController,
                                  onTap: () {
                                    setState(() => _isReplying = true);
                                    _autoDismissTimer?.cancel();
                                  },
                                  style: TextStyle(color: primaryText, fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'Type a reply...',
                                    hintStyle: TextStyle(color: secText, fontSize: 13),
                                    filled: true,
                                    fillColor: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                                  ),
                                  onSubmitted: (_) => _executeAction(replyAction?['index']),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => _executeAction(replyAction?['index']),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Text('Send', style: TextStyle(fontSize: 12, color: primaryText, fontWeight: FontWeight.w600)),
                              ),
                            )
                          ],
                        ),
                      )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}