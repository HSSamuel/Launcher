import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:provider/provider.dart';

// CRITICAL FIX: Imported timezone library (exported via device_calendar) and initialization
import 'package:timezone/timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'launcher_state.dart';

class NotificationCenterPanel extends StatefulWidget {
  final List<Map<String, dynamic>> notifications;
  final VoidCallback onClearAll;
  final VoidCallback onClosePanel; 
  final Function(Map<String, dynamic>) onRemoveNotification;
  final Function(String) onLaunchApp;
  final List<AppInfo> installedApps; 

  const NotificationCenterPanel({
    Key? key,
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
  late DateTime _now;
  late DateTime _currentMonth;
  DateTime? _selectedDate;
  Timer? _timer;
  
  bool _isCalendarExpanded = false; 
  final Set<String> _expandedPackages = {};
  String? _selectedEventDesc;

  final List<String> _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  final List<String> _fullWeekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  final List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  final Map<String, List<Event>> _syncedEvents = {};
  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();
  
  static const platform = MethodChannel('win_launcher/native');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // CRITICAL FIX: Initialized TimeZones required for TZDateTime.local()
    tz_data.initializeTimeZones();
    
    _now = DateTime.now();
    _currentMonth = DateTime(_now.year, _now.month, 1);
    
    _startTimer();
    _syncGoogleCalendar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() => _now = DateTime.now());
      _startTimer();
      _syncGoogleCalendar();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _stopTimer();
    }
  }

  void _startTimer() {
    _stopTimer();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }
  
  Future<void> _syncGoogleCalendar() async {
    try {
      var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
      if (permissionsGranted.isSuccess && !(permissionsGranted.data ?? false)) {
        permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
        if (!permissionsGranted.isSuccess || !(permissionsGranted.data ?? false)) return; 
      }

      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      if (calendarsResult.isSuccess && calendarsResult.data != null) {
        final startDate = TZDateTime.local(_currentMonth.year, _currentMonth.month, 1);
        final endDate = TZDateTime.local(_currentMonth.year, _currentMonth.month + 1, 0);

        _syncedEvents.clear(); 

        for (var calendar in calendarsResult.data!) {
          final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
            calendar.id,
            RetrieveEventsParams(startDate: startDate, endDate: endDate),
          );

          if (eventsResult.isSuccess && eventsResult.data != null) {
            for (var event in eventsResult.data!) {
              if (event.start != null) {
                String dateKey = '${event.start!.year}-${event.start!.month.toString().padLeft(2, '0')}-${event.start!.day.toString().padLeft(2, '0')}';
                if (_syncedEvents.containsKey(dateKey)) {
                  _syncedEvents[dateKey]!.add(event);
                } else {
                  _syncedEvents[dateKey] = [event];
                }
              }
            }
          }
        }
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint("Error syncing Google Calendar: $e");
    }
  }

  String _format24HTime(DateTime time) {
    int h = time.hour; int m = time.minute; int s = time.second;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatShortTime(DateTime time) {
    int h = time.hour; int m = time.minute;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _formatFullDate(DateTime date) {
    return '${_fullWeekdays[date.weekday - 1]}, ${date.day} ${_months[date.month - 1]}';
  }

  void _previousMonth() { setState(() { _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1); _selectedEventDesc = null; }); _syncGoogleCalendar(); }
  void _nextMonth() { setState(() { _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1); _selectedEventDesc = null; }); _syncGoogleCalendar(); }

  Widget _buildNotificationHeader(bool isDark, Color primaryText, Color borderCol, Color cardBg) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, top: 12, bottom: 4),
      child: Row(
        children: [
          Text('Notifications', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryText)),
          const Spacer(),
          Icon(Icons.notifications_paused_outlined, size: 18, color: isDark ? Colors.white70 : Colors.black54),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: widget.onClearAll,
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

  void _triggerDeepLink(String key, String pkg) async {
    widget.onClosePanel();
    await Future.delayed(const Duration(milliseconds: 150));
    bool success = await platform.invokeMethod('triggerNotificationAction', {'key': key, 'actionIndex': -1});
    if (!success) platform.invokeMethod('launchApp', {'package': pkg});
  }

  Widget _buildGroupedNotificationSection(
    String pkg,
    List<Map<String, dynamic>> events,
    bool isDark,
    Color primaryText,
    Color secText,
    Color borderCol,
    Color cardBg,
  ) {
    final firstEvent = events.first;
    String appName = pkg;
    if (appName.contains('.')) appName = appName.split('.').last;
    if (appName.toLowerCase().contains('telegram')) appName = "Telegram";
    if (appName.toLowerCase().contains('whatsapp')) appName = "WhatsApp";
    appName = appName[0].toUpperCase() + appName.substring(1);

    bool isExpanded = _expandedPackages.contains(pkg);
    String timeStr = _formatShortTime(DateTime.now());

    AppInfo? appInfo;
    try { appInfo = widget.installedApps.firstWhere((app) => app.packageName == pkg); } catch (_) {}

    Widget appIcon = appInfo?.icon != null 
        ? Image.memory(appInfo!.icon!, width: 16, height: 16)
        : Container(
            width: 16, height: 16,
            decoration: BoxDecoration(color: Colors.blueGrey, borderRadius: BorderRadius.circular(4)),
            child: Center(child: Text(appName[0], style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderCol)
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() {
                    if (isExpanded) _expandedPackages.remove(pkg);
                    else _expandedPackages.add(pkg);
                  });
                },
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8), bottom: Radius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                  child: Row(
                    children: [
                      appIcon,
                      const SizedBox(width: 8),
                      Expanded(child: Text(appName, style: TextStyle(fontSize: 12, color: primaryText, fontWeight: FontWeight.w600))),
                      if (events.length > 1) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.blue.shade600, borderRadius: BorderRadius.circular(10)),
                          child: Text('${events.length}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(timeStr, style: TextStyle(fontSize: 11, color: secText)),
                      const SizedBox(width: 8),
                      Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: secText),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          for (var e in events) widget.onRemoveNotification(e);
                        },
                        child: Icon(Icons.close, size: 16, color: secText)
                      )
                    ],
                  ),
                ),
              ),
            ),
            
            if (!isExpanded) ...[
              InkWell(
                onTap: () => _triggerDeepLink(firstEvent['key'], pkg),
                child: Padding(
                  padding: const EdgeInsets.only(left: 34.0, right: 10.0, bottom: 10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (firstEvent['title'] != null && firstEvent['title'].toString().isNotEmpty)
                        Text(firstEvent['title'], style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryText), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (firstEvent['text'] != null && firstEvent['text'].toString().isNotEmpty)
                        Text(firstEvent['text'], style: TextStyle(fontSize: 12, color: secText), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              )
            ] else ...[
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF222222) : const Color(0xFFF9F9F9),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                ),
                child: Column(
                  children: events.asMap().entries.map((entry) {
                    var e = entry.value;
                    List<dynamic> actions = e['actions'] ?? [];
                    return InkWell(
                      onTap: () => _triggerDeepLink(e['key'], pkg),
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
                                  _buildMultiLineContent(e, isDark, primaryText, secText),
                                  if (actions.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Wrap(
                                        spacing: 8,
                                        children: actions.map((action) {
                                          return InkWell(
                                            onTap: () {
                                              platform.invokeMethod('triggerNotificationAction', {'key': e['key'], 'actionIndex': action['index']});
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(4)),
                                              child: Text(action['title'] ?? 'Action', style: TextStyle(fontSize: 11, color: Colors.blueAccent.shade400, fontWeight: FontWeight.bold)),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    )
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: () => widget.onRemoveNotification(e),
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Icon(Icons.close, size: 14, color: secText),
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              )
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildMultiLineContent(Map<String, dynamic> event, bool isDark, Color primaryText, Color secText) {
    String title = event['title'] ?? "";
    String content = event['text'] ?? "";
    List<String> lines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) Text(title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: primaryText)),
        if (title.isNotEmpty) const SizedBox(height: 2),
        if (lines.length > 1)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines.map((line) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.0),
              child: Text(line, style: TextStyle(fontSize: 12, color: secText)),
            )).toList(),
          )
        else if (content.isNotEmpty)
          Text(content, style: TextStyle(fontSize: 12, color: secText)),
      ],
    );
  }

  Widget _buildCalendarGrid(bool isDark, Color accentColor, Color primaryText, Color borderCol, Color cardBg) {
    int daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    int firstWeekday = DateTime(_currentMonth.year, _currentMonth.month, 1).weekday;
    int offset = firstWeekday == 7 ? 0 : firstWeekday;
    int prevMonthDays = DateTime(_currentMonth.year, _currentMonth.month, 0).day;

    List<Widget> dayWidgets = [];

    for (String day in _weekdays) {
      dayWidgets.add(Center(child: Text(day, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.grey.shade800))));
    }

    for (int i = offset - 1; i >= 0; i--) {
      dayWidgets.add(Center(child: Text('${prevMonthDays - i}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white24 : Colors.grey.shade300))));
    }

    for (int i = 1; i <= daysInMonth; i++) {
      DateTime thisDay = DateTime(_currentMonth.year, _currentMonth.month, i);
      bool isToday = thisDay.year == _now.year && thisDay.month == _now.month && thisDay.day == _now.day;
      
      String dateKey = '${thisDay.year}-${thisDay.month.toString().padLeft(2, '0')}-${thisDay.day.toString().padLeft(2, '0')}';
      bool hasEvent = _syncedEvents.containsKey(dateKey);
      bool isSelected = _selectedDate != null && thisDay.year == _selectedDate!.year && thisDay.month == _selectedDate!.month && thisDay.day == _selectedDate!.day;

      dayWidgets.add(
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected && !isToday ? (isDark ? Colors.white12 : Colors.grey.shade200) : Colors.transparent,
            border: isToday ? Border.all(color: accentColor, width: 1.5) : null,
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
                      _selectedEventDesc = _syncedEvents[dateKey]!.map((e) => "• ${e.title}").join("\n");
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
                      color: isToday ? accentColor : primaryText, 
                      fontWeight: isToday ? FontWeight.bold : FontWeight.w500
                    )
                  ),
                  if (hasEvent)
                    Positioned(
                      bottom: 4, 
                      child: Container(
                        width: 5, height: 5, 
                        decoration: BoxDecoration(color: isDark ? Colors.white70 : Colors.blueGrey.shade600, shape: BoxShape.circle)
                      )
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    int remainingCells = 42 - (offset + daysInMonth);
    for (int i = 1; i <= remainingCells; i++) {
      dayWidgets.add(Center(child: Text('$i', style: TextStyle(fontSize: 12, color: isDark ? Colors.white24 : Colors.grey.shade300))));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 7,
          childAspectRatio: 1.1,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
          children: dayWidgets,
        ),
        
        if (_selectedEventDesc != null)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(6), border: Border.all(color: borderCol)),
            child: Text(
              "Events & Holidays\n\n${_selectedEventDesc!}", 
              style: TextStyle(fontSize: 12, color: primaryText, fontWeight: FontWeight.w500, height: 1.25)
            ),
          )
      ],
    );
  }

  Widget _buildBottomCalendar(bool isDark, Color accentColor, Color primaryText, Color secText, Color borderCol, Color cardBg, Color calBg) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Container(
        decoration: BoxDecoration(
          color: calBg,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
          border: Border(top: BorderSide(color: borderCol)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_format24HTime(_now), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w400, color: primaryText, letterSpacing: -0.5)),
                    Text(_formatFullDate(_now), style: TextStyle(fontSize: 13, color: secText, fontWeight: FontWeight.w400)),
                  ],
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
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${_months[_currentMonth.month - 1]} ${_currentMonth.year}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryText)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.manage_accounts_outlined, color: primaryText, size: 20),
                        tooltip: 'Add Google Account',
                        onPressed: () => platform.invokeMethod('openSettings', {'type': 'add_account'}),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(Icons.keyboard_arrow_up, color: primaryText, size: 20),
                        onPressed: _previousMonth,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                      IconButton(
                        icon: Icon(Icons.keyboard_arrow_down, color: primaryText, size: 20),
                        onPressed: _nextMonth,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 2), 
              _buildCalendarGrid(isDark, accentColor, primaryText, borderCol, cardBg),
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    
    final theme = state.win11Themes.firstWhere((t) => t.name == state.currentThemeName, orElse: () => state.win11Themes.first);
    final accentColor = theme.accentColor;
    
    final primaryText = isDark ? Colors.white : Colors.black87;
    final secText = isDark ? Colors.white70 : Colors.grey.shade700;
    final borderCol = isDark ? Colors.white24 : Colors.grey.shade200;
    final cardBg = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final calBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
    
    final baseBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
    final panelBg = Color.alphaBlend(accentColor.withOpacity(0.08), baseBg).withOpacity(0.98);

    Map<String, List<Map<String, dynamic>>> groupedNotifications = {};
    for (var n in widget.notifications) {
      final pkg = n['package'] ?? 'system';
      groupedNotifications.putIfAbsent(pkg, () => []).add(n);
    }

    return Container(
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderCol, width: 1),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildNotificationHeader(isDark, primaryText, borderCol, cardBg),
          
          if (widget.notifications.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40.0),
              child: Center(child: Text('No new notifications', style: TextStyle(color: secText, fontSize: 13))),
            )
          else
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 12),
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: groupedNotifications.keys.length,
                itemBuilder: (context, index) {
                  final pkg = groupedNotifications.keys.elementAt(index);
                  final events = groupedNotifications[pkg]!;
                  return _buildGroupedNotificationSection(pkg, events, isDark, primaryText, secText, borderCol, cardBg);
                },
              ),
            ),
          
          _buildBottomCalendar(isDark, accentColor, primaryText, secText, borderCol, cardBg, calBg),
        ],
      ),
    );
  }
}