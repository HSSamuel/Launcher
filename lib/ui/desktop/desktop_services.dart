import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:new_version_plus/new_version_plus.dart';
import 'package:confetti/confetti.dart';

class DesktopServices {
  static String? _extractBirthdayName(String rawTitle) {
    String clean = rawTitle.trim();

    // Strip out common birthday phrases and prefixes/suffixes
    clean = clean.replaceAll(RegExp(r"^(happy\s+)?(birthday|bday|b'day)(\s+to|\s+for|\s+of)?[\s,:\-–—!]*", caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r"('s)?(\s+\d+(st|nd|rd|th)?)?\s*(birthday|bday|b'day)[!.]*", caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\bhappy\b', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'^[\s,:\-–—!]+|[\s,:\-–—!]+$'), '').trim();

    // CRITICAL FIX: Return null if the string is empty, too short, or literally just the word "birthday"
    if (clean.isEmpty || clean.length < 2 || RegExp(r'^[^a-zA-Z]+$').hasMatch(clean)) {
      return null;
    }
    
    if (clean.toLowerCase() == 'birthday' || clean.toLowerCase() == 'bday') {
      return null;
    }
    
    return clean;
  }

  static Future<void> checkForBirthdaysToday({
    required DeviceCalendarPlugin calendarPlugin,
    required ConfettiController confettiController,
    required ValueNotifier<List<Map<String, dynamic>>> realNotifications,
    required ValueNotifier<int> unreadNotifications,
    required List<Map<String, dynamic>> activeToasts,
    required VoidCallback onToastAdded,
    bool isLauncherLocked = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final dateKey = '${now.year}-${now.month}-${now.day}';
      
      int currentStage = 0;
      if (now.hour >= 0 && now.hour < 5) {
        currentStage = 1; 
      } else if (now.hour >= 5 && now.hour < 18) {
        currentStage = 2; 
      } else {
        currentStage = 3; 
      }

      final stageKey = 'bday_${dateKey}_stage_$currentStage';
      if (prefs.getBool(stageKey) == true) return; 

      var permissionsGranted = await calendarPlugin.hasPermissions();
      if (permissionsGranted.isSuccess && !(permissionsGranted.data ?? false)) {
        permissionsGranted = await calendarPlugin.requestPermissions();
      }
      
      if (!permissionsGranted.isSuccess || !(permissionsGranted.data ?? false)) return;

      final calendarsResult = await calendarPlugin.retrieveCalendars();
      if (calendarsResult.isSuccess && calendarsResult.data != null) {
        late tz.Location safeLocation;
        try { 
          safeLocation = tz.local; 
        } catch (_) { 
          safeLocation = tz.getLocation('UTC'); 
        }
        
        final startDate = tz.TZDateTime(safeLocation, now.year, now.month, now.day).subtract(const Duration(days: 1));
        final endDate = startDate.add(const Duration(days: 3));
        
        final List<String> birthdayNames = [];
        bool hasNamelessBirthday = false;
        
        final eventResults = await Future.wait(
          calendarsResult.data!.map(
            (cal) => calendarPlugin.retrieveEvents(
              cal.id,
              RetrieveEventsParams(startDate: startDate, endDate: endDate),
            ),
          ),
        );
        
        final startOfDay = DateTime(now.year, now.month, now.day);
        final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

        for (var res in eventResults) {
          if (res.isSuccess && res.data != null) {
            for (var ev in res.data!) {
              if (ev.start == null) continue;
              
              DateTime localStart;
              DateTime localEnd;
              final isAllDayEvent = ev.allDay ?? false;
              
              if (isAllDayEvent) {
                localStart = DateTime(ev.start!.year, ev.start!.month, ev.start!.day);
                if (ev.end != null) {
                   localEnd = DateTime(ev.end!.year, ev.end!.month, ev.end!.day);
                } else {
                   localEnd = localStart;
                }
              } else {
                localStart = ev.start!.toLocal();
                localEnd = ev.end?.toLocal() ?? localStart;
              }
              
              final isToday = (localStart.year == now.year && localStart.month == now.month && localStart.day == now.day) ||
                              (localStart.isBefore(endOfDay) && localEnd.isAfter(startOfDay));
                              
              if (!isToday) continue;

              final title = (ev.title ?? '').trim();
              final lower = title.toLowerCase();
              
              if (lower.contains('birthday') || lower.contains('bday') || lower.contains("b'day") || lower.contains('cumpleaños')) {
                final extractedName = _extractBirthdayName(title);
                if (extractedName != null) {
                  birthdayNames.add(extractedName);
                } else {
                  hasNamelessBirthday = true;
                }
              }
            }
          }
        }
        
        if (birthdayNames.isNotEmpty || hasNamelessBirthday) {
          await prefs.setBool(stageKey, true);
          
          final uniqueNames = birthdayNames.toSet().toList();
          String namesStr = '';
          if (uniqueNames.length == 1) {
            namesStr = uniqueNames.first;
          } else if (uniqueNames.length == 2) {
            namesStr = '${uniqueNames[0]} & ${uniqueNames[1]}';
          } else if (uniqueNames.length > 2) {
            namesStr = '${uniqueNames.sublist(0, uniqueNames.length - 1).join(', ')} & ${uniqueNames.last}';
          }

          final bool hasSpecificName = namesStr.isNotEmpty;
          String toastTitle = '';
          String toastText = '';

          if (currentStage == 1) {
            if (!isLauncherLocked) confettiController.play();
            toastTitle = '🎂 Midnight Birthday Alert!';
            toastText = hasSpecificName 
                ? "It's officially $namesStr's birthday today!"
                : "A special birthday begins today! Don't forget to celebrate!";
          } else if (currentStage == 2) {
            if (!(prefs.getBool('bday_${dateKey}_stage_1') ?? false)) {
              if (!isLauncherLocked) confettiController.play();
            }
            toastTitle = "🎉 Today's Birthdays";
            toastText = hasSpecificName 
                ? "Don't forget to wish $namesStr a happy birthday today!"
                : "Someone special has a birthday today! Don't forget to send your wishes!";
          } else {
            toastTitle = '🎁 Birthday Wrap-up';
            toastText = hasSpecificName 
                ? "Hope $namesStr had a fantastic birthday today!"
                : "Hope everyone celebrating had a wonderful birthday today!";
          }

          final String toastIdStr = 'bday_toast_${dateKey}_$currentStage';
          final bdayToast = {
            'key': toastIdStr,
            'package': 'com.samuel.winlauncher', 
            'title': toastTitle,
            'text': toastText,
            'postTime': DateTime.now().millisecondsSinceEpoch,
            'actions': [],
            '_isBirthdayToast': true,
            '_toastId': toastIdStr,
          };
          
          if (activeToasts.any((t) => t['_toastId'] == toastIdStr)) return;
          
          if (activeToasts.length >= 3) activeToasts.removeAt(0);
          activeToasts.add(bdayToast);
          
          final currentNotifs = List<Map<String, dynamic>>.from(realNotifications.value);
          currentNotifs.insert(0, bdayToast);
          realNotifications.value = currentNotifs;
          unreadNotifications.value++;
          
          onToastAdded();
        }
      }
    } catch (e) {
      debugPrint("Birthday check error: $e");
    }
  }

  static Future<void> checkForUpcomingEvents({
    required DeviceCalendarPlugin calendarPlugin,
    required ValueNotifier<List<Map<String, dynamic>>> realNotifications,
    required ValueNotifier<int> unreadNotifications,
    required List<Map<String, dynamic>> activeToasts,
    required VoidCallback onToastAdded,
    int advanceNoticeMinutes = 30,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      var permissionsGranted = await calendarPlugin.hasPermissions();
      if (permissionsGranted.isSuccess && !(permissionsGranted.data ?? false)) {
        permissionsGranted = await calendarPlugin.requestPermissions();
      }
      if (!permissionsGranted.isSuccess || !(permissionsGranted.data ?? false)) return;

      final calendarsResult = await calendarPlugin.retrieveCalendars();
      if (!calendarsResult.isSuccess || calendarsResult.data == null) return;

      late tz.Location safeLocation;
      try {
        safeLocation = tz.local;
      } catch (_) {
        safeLocation = tz.getLocation('UTC');
      }

      final startDate = tz.TZDateTime(safeLocation, now.year, now.month, now.day, now.hour, now.minute);
      final endDate = startDate.add(Duration(minutes: advanceNoticeMinutes + 60));

      final eventResults = await Future.wait(
        calendarsResult.data!.map(
          (cal) => calendarPlugin.retrieveEvents(
            cal.id,
            RetrieveEventsParams(startDate: startDate, endDate: endDate),
          ),
        ),
      );

      for (var res in eventResults) {
        if (res.isSuccess && res.data != null) {
          for (var ev in res.data!) {
            if (ev.start == null) continue;
            
            DateTime localStart;
            final isAllDayEvent = ev.allDay ?? false;
            
            if (isAllDayEvent) {
               localStart = DateTime(ev.start!.year, ev.start!.month, ev.start!.day);
            } else {
               localStart = ev.start!.toLocal();
            }
            
            final diffMinutes = localStart.difference(now).inMinutes;
            if (diffMinutes < 0 || diffMinutes > advanceNoticeMinutes) continue;

            final title = (ev.title ?? '').trim();
            final lower = title.toLowerCase();

            if (lower.contains('birthday') || lower.contains('bday') || lower.contains("b'day") || lower.contains('cumpleaños')) {
              continue;
            }

            final safeEventId = ev.eventId?.isNotEmpty == true ? ev.eventId : title.hashCode.toString();
            final eventDedupKey = 'reminded_${safeEventId}_${localStart.millisecondsSinceEpoch}';
            if (prefs.getBool(eventDedupKey) == true) continue;

            await prefs.setBool(eventDedupKey, true);

            final int hour = localStart.hour % 12 == 0 ? 12 : localStart.hour % 12;
            final String ampm = localStart.hour >= 12 ? 'PM' : 'AM';
            final String minute = localStart.minute.toString().padLeft(2, '0');
            final String timeStr = '$hour:$minute $ampm';

            final String timePrompt = diffMinutes == 0 
                ? 'Starting now ($timeStr)' 
                : 'Starts at $timeStr (in $diffMinutes min)';

            final String locationText = (ev.location != null && ev.location!.isNotEmpty) 
                ? ' • ${ev.location}' 
                : '';

            final String toastIdStr = 'event_${ev.eventId}';
            final eventToast = {
              'key': toastIdStr,
              'package': 'com.samuel.winlauncher',
              'title': title.isNotEmpty ? title : 'Calendar Event',
              'text': '$timePrompt$locationText',
              'postTime': DateTime.now().millisecondsSinceEpoch,
              'actions': [
                {'title': 'Open in Calendar', 'index': 1}
              ],
              '_isCalendarReminder': true,
              '_eventStartEpoch': localStart.millisecondsSinceEpoch,
              '_toastId': toastIdStr,
            };

            if (activeToasts.any((t) => t['_toastId'] == toastIdStr)) continue;

            if (activeToasts.length >= 3) activeToasts.removeAt(0);
            activeToasts.add(eventToast);

            final currentNotifs = List<Map<String, dynamic>>.from(realNotifications.value);
            currentNotifs.insert(0, eventToast);
            realNotifications.value = currentNotifs;
            unreadNotifications.value++;

            onToastAdded();
          }
        }
      }
    } catch (e) {
      debugPrint("Event reminder check error: $e");
    }
  }

  static Future<void> checkAutomatedUpdate({
    required ValueNotifier<List<Map<String, dynamic>>> realNotifications,
    required ValueNotifier<int> unreadNotifications,
    required List<Map<String, dynamic>> activeToasts,
    required VoidCallback onToastAdded,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // CRITICAL FIX: Use integer milliseconds for a bulletproof 24-hour cooldown lock
      final lastPrompt = prefs.getInt('last_update_prompt_time') ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      if (nowMs - lastPrompt < 86400000) {
        return; 
      }

      final newVersionPlus = NewVersionPlus(androidId: 'com.samuel.winlauncher');
      final status = await newVersionPlus.getVersionStatus();

      if (status != null && status.canUpdate) {
        // Lock the prompt for the next 24 hours now that we are showing it
        await prefs.setInt('last_update_prompt_time', nowMs);

        final String toastIdStr = 'update_ready_v${status.storeVersion}';
        final updateEvent = {
          'key': 'win11_system_update_ready',
          'package': 'com.samuel.winlauncher', 
          'title': 'System Update Available',
          'text': 'Win11 PC Launcher v${status.storeVersion} is ready. Tap to download from Google Play.',
          'postTime': DateTime.now().millisecondsSinceEpoch,
          'actions': [
            {'title': 'Download Update', 'index': 999}
          ],
          '_isUpdateToast': true,
          '_updateUrl': status.appStoreLink.isNotEmpty ? status.appStoreLink : 'market://details?id=com.samuel.winlauncher',
          '_toastId': toastIdStr,
        };

        if (activeToasts.any((t) => t['_toastId'] == toastIdStr)) return;

        if (activeToasts.length >= 3) activeToasts.removeAt(0);
        activeToasts.add(updateEvent);
        
        final currentNotifs = List<Map<String, dynamic>>.from(realNotifications.value);
        currentNotifs.insert(0, updateEvent);
        realNotifications.value = currentNotifs;
        unreadNotifications.value++;
        
        onToastAdded();
      }
    } catch (_) {}
  }
}