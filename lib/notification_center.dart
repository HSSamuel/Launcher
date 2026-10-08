import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:installed_apps/app_info.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart';

import '../../states/theme_state.dart';
import '../../states/system_state.dart';
import '../../states/apps_state.dart';
import '../../services/native_bridge.dart';
import '../../services/lazy_app_icon.dart';
import 'ui/shared/acrylic_container.dart';

Map<String, List<String>> _processCalendarEventsIsolate(List<Map<String, dynamic>> rawEvents) {
  final Map<String, List<String>> grouped = {};
  for (var item in rawEvents) {
    final startIso = item['start'] as String?;
    final title = item['title'] as String? ?? 'Event';
    if (startIso != null) {
      final dt = DateTime.tryParse(startIso)?.toLocal();
      if (dt != null) {
        final dateKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        if (grouped.containsKey(dateKey)) {
          grouped[dateKey]!.add(title);
        } else {
          grouped[dateKey] = [title];
        }
      }
    }
  }
  return grouped;
}

class NotificationCenterPanel extends StatefulWidget {
  final bool isOpen; 
  final List<Map<String, dynamic>> notifications;
  final VoidCallback onClearAll;
  final VoidCallback onClosePanel; 
  final Function(Map<String, dynamic>) onRemoveNotification;
  final Function(String) onLaunchApp;
  final List<AppInfo> installedApps; 

  const NotificationCenterPanel({
    Key? key,
    required this.isOpen,
    required this.notifications,
    required this.onClearAll,
    required this.onClosePanel,
    required this.onRemoveNotification,
    required this.onLaunchApp,
    required this.installedApps,
  }) : super(key: key);

  @override
  State<NotificationCenterPanel> createState() => _NotificationCenterPanelState();
}

class _NotificationCenterPanelState extends State<NotificationCenterPanel> with WidgetsBindingObserver {
  late DateTime _currentMonth;
  DateTime? _selectedDate;
  
  bool _isCalendarExpanded = false; 
  bool _isAllFolded = false;
  bool _isSyncingCalendar = false;
  
  final Set<String> _expandedPackages = {};
  final Set<String> _collapsedPackages = {};
  final Set<String> _collapsedMessageKeys = {};
  final Set<String> _optimisticallyHidden = {};
  
  String? _selectedEventDesc;
  String? _activeReplyKey;
  int? _activeReplyIndex;
  
  final TextEditingController _replyController = TextEditingController();

  late PageController _calendarPageController;
  final int _baseMonthIndex = 1200;
  late DateTime _baseMonth;

  final List<String> _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  final List<String> _fullWeekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  final List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  final Map<String, List<String>> _syncedEvents = {};
  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    final initialDate = DateTime.now();
    _baseMonth = DateTime(initialDate.year, initialDate.month, 1);
    _currentMonth = _baseMonth;
    _calendarPageController = PageController(initialPage: _baseMonthIndex);
    
    _syncGoogleCalendar();
  }

  @override
  void didUpdateWidget(NotificationCenterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isOpen && !oldWidget.isOpen) {
      final now = DateTime.now();
      final currentBase = DateTime(now.year, now.month, 1);
      
      bool needsUpdate = false;
      
      if (_currentMonth.year != currentBase.year || _currentMonth.month != currentBase.month) {
        _currentMonth = currentBase;
        _selectedDate = null;
        _selectedEventDesc = null;
        needsUpdate = true;
        
        if (_calendarPageController.hasClients) {
          _calendarPageController.jumpToPage(_baseMonthIndex);
        }
      }

      if (needsUpdate) {
        setState(() {});
        _syncGoogleCalendar();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _replyController.dispose();
    _calendarPageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncGoogleCalendar();
    }
  }

  Future<void> _syncGoogleCalendar() async {
    if (_isSyncingCalendar) return;
    _isSyncingCalendar = true;
    
    try {
      var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
      if (permissionsGranted.isSuccess && !(permissionsGranted.data ?? false)) {
        permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
        if (!permissionsGranted.isSuccess || !(permissionsGranted.data ?? false)) {
          _isSyncingCalendar = false;
          return;
        } 
      }

      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      if (calendarsResult.isSuccess && calendarsResult.data != null) {
        late Location safeLocation;
        try {
          safeLocation = local; 
        } catch (e) {
          safeLocation = getLocation('UTC'); 
        }

        final startDate = TZDateTime(safeLocation, _currentMonth.year, _currentMonth.month, 1);
        final endDate = TZDateTime(safeLocation, _currentMonth.year, _currentMonth.month + 1, 0);

        final eventResults = await Future.wait(
          calendarsResult.data!.map(
            (cal) => _deviceCalendarPlugin.retrieveEvents(
              cal.id,
              RetrieveEventsParams(startDate: startDate, endDate: endDate),
            ),
          ),
        );

        final List<Map<String, dynamic>> rawList = [];
        for (var res in eventResults) {
          if (res.isSuccess && res.data != null) {
            for (var ev in res.data!) {
              if (ev.start != null) {
                rawList.add({
                  'title': ev.title ?? 'Event',
                  'start': ev.start!.toIso8601String(),
                });
              }
            }
          }
        }

        final grouped = await compute(_processCalendarEventsIsolate, rawList);

        if (mounted) {
          setState(() {
            _syncedEvents.clear();
            _syncedEvents.addAll(grouped);
            
            if (_selectedDate != null) {
              String dateKey = '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
              if (_syncedEvents.containsKey(dateKey)) {
                _selectedEventDesc = _syncedEvents[dateKey]!.map((title) => "• $title").join("\n");
              } else {
                _selectedEventDesc = null;
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error syncing Google Calendar: $e");
    } finally {
      _isSyncingCalendar = false;
    }
  }

  String _format24HTime(DateTime time) {
    int h = time.hour; int m = time.minute; int s = time.second;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatShortTime(DateTime time) {
    int h = time.hour; 
    int m = time.minute;
    String period = h >= 12 ? 'pm' : 'am';
    h = h % 12; 
    if (h == 0) h = 12; 
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $period';
  }

  String _formatFullDate(DateTime date) {
    return '${_fullWeekdays[date.weekday - 1]}, ${date.day} ${_months[date.month - 1]}';
  }

  void _previousMonth() { 
    if (_calendarPageController.hasClients) {
      _calendarPageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut); 
    }
  }
  
  void _nextMonth() { 
    if (_calendarPageController.hasClients) {
      _calendarPageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut); 
    }
  }

  int _getCalendarRows(DateTime month) {
    int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    int firstWeekday = DateTime(month.year, month.month, 1).weekday;
    int offset = firstWeekday == 7 ? 0 : firstWeekday;
    return ((offset + daysInMonth) / 7).ceil() + 1; 
  }

  void _triggerDeepLink(Map<String, dynamic> event, String pkg) {
    if (event['_isUpdateToast'] == true) {
      NativeBridge.instance.launchApp(event['_updateUrl'] ?? 'market://details?id=com.samuel.winlauncher');
      widget.onRemoveNotification(event);
      return;
    }

    final key = event['key'];
    setState(() => _optimisticallyHidden.add(key));
    
    NativeBridge.instance.triggerNotificationAction(key, -1).then((success) {
      if (!success) NativeBridge.instance.launchApp(pkg);
    });
    
    widget.onRemoveNotification(event);
  }

  void _sendInlineReply(String key) async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    
    setState(() {
      _optimisticallyHidden.add(key);
      _activeReplyKey = null;
      _replyController.clear();
    });
    
    await NativeBridge.instance.triggerNotificationAction(key, _activeReplyIndex ?? -1, replyText: text);
  }

  Widget _buildNotificationHeader(bool isDark, Color primaryText, Color borderCol, Color cardBg, int totalCount, List<String> currentPackages, List<String> allEventKeys) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, top: 12, bottom: 6),
      child: Row(
        children: [
          Text('Notifications', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryText)),
          const Spacer(),
          if (totalCount > 1)
            InkWell(
              onTap: () {
                setState(() {
                  _isAllFolded = !_isAllFolded;
                  if (_isAllFolded) {
                    _expandedPackages.clear();
                    _collapsedPackages.addAll(currentPackages);
                    _collapsedMessageKeys.addAll(allEventKeys);
                  } else {
                    _collapsedPackages.clear();
                    _expandedPackages.addAll(currentPackages);
                    _collapsedMessageKeys.clear();
                  }
                });
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Text('+$totalCount', style: const TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    Icon(_isAllFolded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, size: 16, color: isDark ? Colors.white70 : Colors.black54),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () {
              widget.onClearAll();
              setState(() => _optimisticallyHidden.clear());
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              minimumSize: const Size(0, 26),
              side: BorderSide(color: borderCol),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              backgroundColor: cardBg,
            ),
            child: Text('Clear all', style: TextStyle(fontSize: 12, color: primaryText, fontWeight: FontWeight.w400)),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleEvent(
    Map<String, dynamic> event, 
    String pkg, 
    bool isDark, 
    Color primaryText, 
    Color secText, 
    {bool isGrouped = false}
  ) {
    List<dynamic> rawActions = event['actions'] ?? [];
    List<Map<String, dynamic>> actions = [];
    
    for (var rawAction in rawActions) {
      if (rawAction is Map) {
        actions.add(Map<String, dynamic>.from(rawAction));
      }
    }
    
    DateTime notifTime = DateTime.now();
    if (event['postTime'] != null) {
      notifTime = DateTime.fromMillisecondsSinceEpoch(event['postTime'] as int);
    }
    String timeStr = _formatShortTime(notifTime);

    String content = event['text']?.toString().trim() ?? "";
    bool isLongText = content.length > 50 || content.contains('\n');
    bool hasExpandableContent = isLongText || actions.isNotEmpty;
    bool isMessageExpanded = hasExpandableContent && !_collapsedMessageKeys.contains(event['key']);

    return Dismissible(
      key: Key(event['key'].toString()),
      direction: DismissDirection.horizontal,
      onDismissed: (_) {
        setState(() => _optimisticallyHidden.add(event['key']));
        widget.onRemoveNotification(event);
      },
      background: Container(color: Colors.redAccent, alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 24), child: const Icon(Icons.delete_outline, color: Colors.white, size: 20)),
      secondaryBackground: Container(color: Colors.redAccent, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), child: const Icon(Icons.delete_outline, color: Colors.white, size: 20)),
      child: InkWell(
        onTap: () => _triggerDeepLink(event, pkg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 2, height: 24, margin: const EdgeInsets.only(right: 8, top: 4), color: Colors.blue.shade400),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event['title'] ?? "", 
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: primaryText),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(timeStr, style: TextStyle(fontSize: 11, color: secText)),
                        
                        if (hasExpandableContent) ...[
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () {
                              setState(() {
                                if (isMessageExpanded) {
                                  _collapsedMessageKeys.add(event['key']);
                                } else {
                                  _collapsedMessageKeys.remove(event['key']);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: Icon(
                                isMessageExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, 
                                size: 16, 
                                color: secText
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildMultiLineContentText(event, secText, isExpanded: isMessageExpanded),
                          
                          if (isMessageExpanded && actions.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: actions.map((action) {
                                  bool isReplyAction = action['title'] != null && action['title'].toString().toLowerCase().contains('reply');
                                  String titleStr = action['title']?.toString().toLowerCase() ?? '';
                                  bool isDismissiveAction = titleStr.contains('read') || titleStr.contains('delete') || titleStr.contains('mute') || titleStr.contains('clear') || titleStr.contains('archive');
                                  
                                  return InkWell(
                                    onTap: () {
                                      if (isReplyAction) {
                                        setState(() {
                                          if (_activeReplyKey == event['key']) {
                                            _activeReplyKey = null; 
                                          } else {
                                            _activeReplyKey = event['key'];
                                            _activeReplyIndex = action['index'];
                                          }
                                        });
                                      } else {
                                        if (isDismissiveAction) {
                                          setState(() => _optimisticallyHidden.add(event['key']));
                                        }
                                        
                                        if (event['_isUpdateToast'] == true) {
                                          NativeBridge.instance.launchApp(event['_updateUrl'] ?? 'market://details?id=com.samuel.winlauncher');
                                          widget.onRemoveNotification(event);
                                        } else {
                                          NativeBridge.instance.triggerNotificationAction(event['key'], action['index']);
                                        }
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                                      child: Text(action['title'] ?? 'Action', style: TextStyle(fontSize: 11, color: Colors.blueAccent.shade400, fontWeight: FontWeight.bold)),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            
                          if (isMessageExpanded && _activeReplyKey == event['key'])
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 36,
                                      child: TextField(
                                        controller: _replyController,
                                        autofocus: true,
                                        style: TextStyle(color: primaryText, fontSize: 13),
                                        decoration: InputDecoration(
                                          hintText: 'Type a reply...',
                                          hintStyle: TextStyle(color: secText, fontSize: 13),
                                          filled: true,
                                          fillColor: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                                        ),
                                        onSubmitted: (_) => _sendInlineReply(event['key']),
                                      ),
                                    )
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _sendInlineReply(event['key']),
                                    child: Container(
                                      width: 36, height: 36,
                                      decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
                                      child: const Icon(Icons.send, color: Colors.white, size: 16),
                                    ),
                                  )
                                ],
                              )
                            )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isGrouped)
                InkWell(
                  onTap: () {
                    setState(() => _optimisticallyHidden.add(event['key']));
                    widget.onRemoveNotification(event);
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6.0, top: 4.0),
                    child: Icon(Icons.close, size: 14, color: secText),
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMultiLineContentText(Map<String, dynamic> event, Color secText, {required bool isExpanded}) {
    String title = event['title']?.toString().trim() ?? "";
    String content = event['text']?.toString().trim() ?? "";

    if (title.isNotEmpty && content.startsWith('$title:')) {
      content = content.substring(title.length + 1).trim();
    }

    if (content.isEmpty) return const SizedBox.shrink();

    return Text(
      content,
      style: TextStyle(fontSize: 12, color: secText),
      maxLines: isExpanded ? 20 : 2, 
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildGroupedNotificationSection(
    String pkg,
    List<Map<String, dynamic>> rawEvents,
    bool isDark,
    Color primaryText,
    Color secText,
    Color borderCol,
    Color cardBg,
    ThemeState themeState,
    AppsState appsState,
  ) {
    final rawFiltered = rawEvents.where((e) => !_optimisticallyHidden.contains(e['key'])).toList();
    if (rawFiltered.isEmpty) return const SizedBox.shrink();

    String appName = pkg;
    if (appName.contains('.')) appName = appName.split('.').last;
    if (appName.toLowerCase().contains('telegram')) appName = "Telegram";
    if (appName.toLowerCase().contains('whatsapp')) appName = "WhatsApp";
    appName = appName[0].toUpperCase() + appName.substring(1);

    List<Map<String, dynamic>> initialEvents = [];
    List<dynamic> masterActions = [];

    for (var rawE in rawFiltered) {
      String title = rawE['title']?.toString().trim() ?? '';
      String text = rawE['text']?.toString().trim() ?? '';
      List<dynamic> actions = rawE['actions'] ?? [];

      if (actions.isNotEmpty) masterActions = actions;

      bool isGenericSummary = title.toLowerCase() == appName.toLowerCase() || 
                              text.toLowerCase().contains('new messages') || 
                              text.toLowerCase().contains('unread messages');
                              
      if (!isGenericSummary) {
        initialEvents.add(Map<String, dynamic>.from(rawE));
      }
    }

    List<Map<String, dynamic>> events = [];
    Set<String> seenCompositeKeys = {};

    for (var e in initialEvents) {
      String tTitle = e['title']?.toString().trim() ?? '';
      String tText = e['text']?.toString().trim() ?? '';
      String cleanText = tText.startsWith('$tTitle:') ? tText.substring(tTitle.length + 1).trim() : tText;

      String compositeKey = '${tTitle}_$cleanText';
      
      if (!seenCompositeKeys.contains(compositeKey)) {
        events.add(e);
        seenCompositeKeys.add(compositeKey);
      }
    }

    for (int i = 0; i < events.length; i++) {
       List<dynamic> currentActions = events[i]['actions'] ?? [];
       if (currentActions.isEmpty && masterActions.isNotEmpty) {
           events[i]['actions'] = List.from(masterActions); 
       }
    }

    if (events.isEmpty && rawFiltered.isNotEmpty) {
       events = [Map<String, dynamic>.from(rawFiltered.first)];
    }

    final isMultiEvent = events.length > 1;

    bool isAppGroupExpanded;
    if (_expandedPackages.contains(pkg)) {
      isAppGroupExpanded = true;
    } else if (_collapsedPackages.contains(pkg)) {
      isAppGroupExpanded = false;
    } else {
      isAppGroupExpanded = true; 
    }

    AppInfo? appInfo;
    try { 
      appInfo = widget.installedApps.firstWhere((app) => app.packageName == pkg); 
    } catch (_) {}

    Widget defaultFallbackIcon = Container(
      width: 16, height: 16,
      decoration: BoxDecoration(color: Colors.blueGrey, borderRadius: BorderRadius.circular(4)),
      child: Center(child: Text(appName[0], style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
    );

    Widget fallbackIcon = appInfo?.packageName != null
        ? LazyAppIcon(
            packageName: appInfo!.packageName!, 
            size: 16.0,
            fallbackIcon: defaultFallbackIcon,
          )
        : defaultFallbackIcon;

    Widget appIcon;
    if (themeState.cachedIconsPath != null) {
      appIcon = Image.file(
        File('${themeState.cachedIconsPath}/$pkg.png'), width: 16, height: 16, gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallbackIcon,
      );
    } else {
      appIcon = fallbackIcon;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderCol)
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isMultiEvent ? () {
                  setState(() {
                    if (isAppGroupExpanded) {
                      _expandedPackages.remove(pkg);
                      _collapsedPackages.add(pkg);
                    } else {
                      _collapsedPackages.remove(pkg);
                      _expandedPackages.add(pkg);
                    }
                  });
                } : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                  child: Row(
                    children: [
                      appIcon,
                      const SizedBox(width: 8),
                      Expanded(child: Text(appName, style: TextStyle(fontSize: 12, color: primaryText, fontWeight: FontWeight.w600))),
                      
                      if (isMultiEvent) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(color: Colors.blue.shade600, borderRadius: BorderRadius.circular(10)),
                          child: Text('${events.length}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                        Icon(isAppGroupExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 16, color: secText),
                        const SizedBox(width: 8),
                      ],

                      InkWell(
                        onTap: () {
                          for (var e in events) {
                            setState(() => _optimisticallyHidden.add(e['key']));
                            widget.onRemoveNotification(e);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(2.0),
                          child: Icon(Icons.close, size: 15, color: secText),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
            
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF222222) : const Color(0xFFF9F9F9),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                ),
                child: Column(
                  children: [
                    ...(isAppGroupExpanded ? events.take(6).toList() : [events.first]).map((e) {
                      return _buildSingleEvent(e, pkg, isDark, primaryText, secText, isGrouped: isMultiEvent);
                    }).toList(),
                    if (isAppGroupExpanded && events.length > 6)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('+ ${events.length - 6} more', style: TextStyle(color: secText, fontSize: 11)),
                      ),
                  ]
                )
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarGrid(DateTime month, bool isDark, Color accentColor, Color primaryText, Color secText, Color borderCol, Color cardBg) {
    final now = DateTime.now();
    int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    int firstWeekday = DateTime(month.year, month.month, 1).weekday;
    int offset = firstWeekday == 7 ? 0 : firstWeekday;
    int prevMonthDays = DateTime(month.year, month.month, 0).day;

    int requiredCells = offset + daysInMonth;
    int totalRows = (requiredCells / 7).ceil();
    int remainingCells = (totalRows * 7) - requiredCells;
    int totalCells = 7 + (totalRows * 7);

    final weekendBg = isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04);

    BoxDecoration getWeekendDecoration(int index) {
      bool isWeekend = (index % 7 == 0 || index % 7 == 6);
      if (!isWeekend) return const BoxDecoration();
      
      BorderRadius radius = BorderRadius.zero;
      if (index < 7) {
        radius = const BorderRadius.vertical(top: Radius.circular(8));
      } else if (index >= totalCells - 7) {
        radius = const BorderRadius.vertical(bottom: Radius.circular(8));
      }
      return BoxDecoration(color: weekendBg, borderRadius: radius);
    }

    List<Widget> dayWidgets = [];
    int cellIndex = 0;

    for (String day in _weekdays) {
      dayWidgets.add(
        Container(
          decoration: getWeekendDecoration(cellIndex),
          child: Center(child: Text(day, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.grey.shade800)))
        )
      );
      cellIndex++;
    }

    for (int i = offset - 1; i >= 0; i--) {
      dayWidgets.add(
        Container(
          decoration: getWeekendDecoration(cellIndex),
          child: Center(child: Text('${prevMonthDays - i}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white24 : Colors.grey.shade500)))
        )
      );
      cellIndex++;
    }

    for (int i = 1; i <= daysInMonth; i++) {
      DateTime thisDay = DateTime(month.year, month.month, i);
      bool isToday = thisDay.year == now.year && thisDay.month == now.month && thisDay.day == now.day;
      
      String dateKey = '${thisDay.year}-${thisDay.month.toString().padLeft(2, '0')}-${thisDay.day.toString().padLeft(2, '0')}';
      bool hasEvent = _syncedEvents.containsKey(dateKey);
      bool isSelected = _selectedDate != null && thisDay.year == _selectedDate!.year && thisDay.month == _selectedDate!.month && thisDay.day == _selectedDate!.day;

      Color cellBgColor = Colors.transparent;
      Border? cellBorder;
      Color cellTextColor = primaryText;
      Color cellDotColor = isDark ? Colors.white70 : Colors.blueGrey.shade600;

      if (isToday) {
        cellBgColor = accentColor; 
        
        Color contrastColor = accentColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
        cellTextColor = contrastColor; 
        cellDotColor = contrastColor; 
        
        if (isSelected) {
          cellBorder = Border.all(color: isDark ? Colors.white54 : Colors.black54, width: 1.5);
        }
      } else if (isSelected) {
        cellBgColor = isDark ? Colors.white12 : Colors.black.withOpacity(0.06); 
        cellBorder = Border.all(color: accentColor, width: 1.5); 
        cellTextColor = primaryText;
      }

      dayWidgets.add(
        Container(
          decoration: getWeekendDecoration(cellIndex),
          child: Container(
            margin: const EdgeInsets.all(2.0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cellBgColor,
              border: cellBorder,
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.hardEdge,
              child: InkWell(
                onTap: () {
                  setState(() {
                    if (isSelected && hasEvent) {
                      _selectedDate = null;
                      _selectedEventDesc = null;
                    } else {
                      _selectedDate = thisDay;
                      if (hasEvent) {
                        _selectedEventDesc = _syncedEvents[dateKey]!.map((title) => "• $title").join("\n");
                      } else {
                        _selectedEventDesc = null;
                      }
                    }
                  });
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      '$i', 
                      style: TextStyle(
                        fontSize: 13, 
                        color: cellTextColor, 
                        fontWeight: (isToday || isSelected) ? FontWeight.bold : FontWeight.w500
                      )
                    ),
                    if (hasEvent)
                      Positioned(
                        bottom: 5, 
                        child: Container(
                          width: 4.5, height: 4.5, 
                          decoration: BoxDecoration(color: cellDotColor, shape: BoxShape.circle)
                        )
                      ),
                  ],
                ),
              ),
            ),
          ),
        )
      );
      cellIndex++;
    }

    for (int i = 1; i <= remainingCells; i++) {
      dayWidgets.add(
        Container(
          decoration: getWeekendDecoration(cellIndex),
          child: Center(child: Text('$i', style: TextStyle(fontSize: 12, color: isDark ? Colors.white24 : Colors.grey.shade500)))
        )
      );
      cellIndex++;
    }

    return GridView.count(
      padding: const EdgeInsets.only(top: 4),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      childAspectRatio: 1.35, 
      mainAxisSpacing: 0,
      crossAxisSpacing: 0,
      children: dayWidgets,
    );
  }

  Widget _buildBottomCalendar(bool isDark, Color accentColor, Color primaryText, Color secText, Color borderCol, Color cardBg) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Win11AcrylicContainer(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderCol, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StreamBuilder<DateTime>(
                  stream: TimeService.clockStream,
                  builder: (context, snapshot) {
                    final now = snapshot.data ?? DateTime.now();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_format24HTime(now), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w400, color: primaryText, letterSpacing: -0.5)),
                        Text(_formatFullDate(now), style: TextStyle(fontSize: 13, color: secText, fontWeight: FontWeight.w400)),
                      ],
                    );
                  }
                ),
                OutlinedButton(
                  onPressed: () => setState(() => _isCalendarExpanded = !_isCalendarExpanded),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(28, 28),
                    side: BorderSide(color: borderCol),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    backgroundColor: cardBg,
                  ),
                  child: Icon(_isCalendarExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, size: 18, color: primaryText),
                ),
              ],
            ),
            
            if (_isCalendarExpanded) ...[
              const SizedBox(height: 6),
              Divider(height: 1, color: borderCol),
              const SizedBox(height: 4), 
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        final themeState = context.read<ThemeState>();
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: _currentMonth,
                          firstDate: DateTime(1990),
                          lastDate: DateTime(2100),
                          initialDatePickerMode: DatePickerMode.year,
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: isDark 
                                    ? ColorScheme.dark(
                                        primary: themeState.foregroundAccentColor,
                                        onPrimary: themeState.textOnAccentColor,
                                        surface: cardBg,
                                      )
                                    : ColorScheme.light(
                                        primary: themeState.foregroundAccentColor,
                                        onPrimary: themeState.textOnAccentColor,
                                        surface: cardBg,
                                      ),
                              ),
                              child: child!,
                            );
                          }
                        );
                        if (picked != null) {
                          int monthDiff = (picked.year - _baseMonth.year) * 12 + (picked.month - _baseMonth.month);
                          if (_calendarPageController.hasClients) {
                            _calendarPageController.jumpToPage(_baseMonthIndex + monthDiff);
                          } else {
                            setState(() {
                              _currentMonth = DateTime(picked.year, picked.month, 1);
                              _selectedEventDesc = null;
                            });
                            _syncGoogleCalendar();
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                        child: Text('${_months[_currentMonth.month - 1]} ${_currentMonth.year}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryText)),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.manage_accounts_outlined, color: primaryText, size: 20),
                        tooltip: 'Add Google Account',
                        onPressed: () => NativeBridge.instance.openSettings('add_account'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(Icons.keyboard_arrow_left, color: primaryText, size: 20),
                        onPressed: _previousMonth,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                      IconButton(
                        icon: Icon(Icons.keyboard_arrow_right, color: primaryText, size: 20),
                        onPressed: _nextMonth,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ],
                  )
                ],
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  double cellWidth = constraints.maxWidth / 7;
                  double cellHeight = cellWidth / 1.35; 
                  double dynamicHeight = cellHeight * _getCalendarRows(_currentMonth) + 4; 

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    height: dynamicHeight,
                    child: PageView.builder(
                      controller: _calendarPageController,
                      physics: const BouncingScrollPhysics(),
                      onPageChanged: (index) {
                        setState(() {
                          _currentMonth = DateTime(_baseMonth.year, _baseMonth.month + (index - _baseMonthIndex), 1);
                          _selectedEventDesc = null;
                        });
                        _syncGoogleCalendar();
                      },
                      itemBuilder: (context, index) {
                        DateTime targetMonth = DateTime(_baseMonth.year, _baseMonth.month + (index - _baseMonthIndex), 1);
                        return _buildCalendarGrid(targetMonth, isDark, accentColor, primaryText, secText, borderCol, cardBg);
                      },
                    ),
                  );
                },
              ),
              if (_selectedEventDesc != null)
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 0),
                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(6), border: Border.all(color: borderCol)),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (_selectedDate != null) {
                          final epoch = _selectedDate!.millisecondsSinceEpoch;
                          NativeBridge.instance.launchApp('content://com.android.calendar/time/$epoch');
                        } else {
                          NativeBridge.instance.launchApp('content://com.android.calendar/time/');
                        }
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                "Events & Holidays\n\n${_selectedEventDesc!}", 
                                style: TextStyle(fontSize: 12, color: primaryText, fontWeight: FontWeight.w500, height: 1.25)
                              ),
                            ),
                            Icon(Icons.open_in_new, size: 16, color: secText),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final appsState = context.watch<AppsState>();
    final isDark = themeState.isDarkMode;
    final accentColor = themeState.currentAccentColor;
    
    final primaryText = isDark ? Colors.white : Colors.black87;
    final secText = isDark ? Colors.white70 : Colors.grey.shade700;
    final borderCol = isDark ? Colors.white24 : Colors.grey.shade200;
    final cardBg = isDark ? const Color(0xFF2B2B2B) : Colors.white;

    Map<String, List<Map<String, dynamic>>> groupedNotifications = {};
    int totalVisibleCount = 0;
    List<String> allEventKeys = [];

    for (var n in widget.notifications) {
      if (_optimisticallyHidden.contains(n['key'])) continue;
      
      final pkg = n['package'] ?? 'system';
      if (!groupedNotifications.containsKey(pkg)) {
        groupedNotifications[pkg] = [];
      }
      groupedNotifications[pkg]!.add(n);
      allEventKeys.add(n['key'].toString());
      totalVisibleCount++;
    }

    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Win11AcrylicContainer(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderCol, width: 1),
              child: CustomScrollView(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildNotificationHeader(isDark, primaryText, borderCol, cardBg, totalVisibleCount, groupedNotifications.keys.toList(), allEventKeys),
                  ),
                  if (groupedNotifications.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40.0),
                        child: Center(child: Text('No new notifications', style: TextStyle(color: secText, fontSize: 13))),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final pkg = groupedNotifications.keys.elementAt(index);
                          final events = groupedNotifications[pkg]!;
                          return _buildGroupedNotificationSection(pkg, events, isDark, primaryText, secText, borderCol, cardBg, themeState, appsState);
                        },
                        childCount: groupedNotifications.keys.length,
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          _buildBottomCalendar(isDark, accentColor, primaryText, secText, borderCol, cardBg),
        ],
      ),
    );
  }
}