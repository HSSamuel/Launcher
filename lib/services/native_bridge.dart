import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:app_settings/app_settings.dart';
import 'dart:async';

class NativeBridge {
  NativeBridge._privateConstructor();
  static final NativeBridge instance = NativeBridge._privateConstructor();

  static const MethodChannel _channel = MethodChannel('win_launcher/native');
  static const EventChannel _notifChannel = EventChannel('win_launcher/notifications');
  static const EventChannel _hwChannel = EventChannel('win_launcher/hardware_events'); 
  static const EventChannel _pkgChannel = EventChannel('win_launcher/package_events'); 
  static const EventChannel _fileChannel = EventChannel('win_launcher/file_events');

  late final Stream<dynamic> notificationStream = kIsWeb ? const Stream.empty() : _notifChannel.receiveBroadcastStream();
  late final Stream<dynamic> hardwareStateStream = kIsWeb ? const Stream.empty() : _hwChannel.receiveBroadcastStream(); 
  late final Stream<dynamic> packageEventStream = kIsWeb ? const Stream.empty() : _pkgChannel.receiveBroadcastStream(); 
  late final Stream<dynamic> fileEventStream = kIsWeb ? const Stream.empty() : _fileChannel.receiveBroadcastStream();

  void _logError(String method, dynamic e) {
    debugPrint("NativeBridge Error [$method]: $e");
  }

  Future<void> setNativeWallpaper(String path) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('setNativeWallpaper', {'path': path});
    } catch (e) {
      _logError('setNativeWallpaper', e);
    }
  }

  Future<Map<String, int>> optimizeSystem() async {
    if (kIsWeb) return {'signaled': 0, 'freedMb': 0};
    try {
      final Map<dynamic, dynamic>? res = await _channel.invokeMethod('optimizeSystem');
      if (res != null) {
        return {
          'signaled': res['signaled'] as int? ?? 0, 
          'freedMb': res['freedMb'] as int? ?? 0
        };
      }
      return {'signaled': 0, 'freedMb': 0};
    } catch (e) {
      _logError('optimizeSystem', e);
      return {'signaled': 0, 'freedMb': 0};
    }
  }

  Future<void> restartApp() async {
    if (kIsWeb) return;
    try { await _channel.invokeMethod('restartApp'); } 
    catch (e) { _logError('restartApp', e); }
  }

  Future<void> playSound(String type) async {
    if (kIsWeb) return;
    try { await _channel.invokeMethod('playSound', {'type': type}); } 
    catch (e) { _logError('playSound', e); }
  }

  Future<Map<String, dynamic>> getHardwareState() async {
    if (kIsWeb) return {'Wi-Fi': true, 'Bluetooth': false, 'sys_brightness': 0.8};
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getHardwareState');
      if (result != null) return Map<String, dynamic>.from(result);
    } catch (e) { _logError('getHardwareState', e); }
    return {};
  }

  Future<void> setSystemBrightness(double value) async {
    if (kIsWeb) return;
    try { await _channel.invokeMethod('setSystemBrightness', {'brightness': value}); } catch (e) { _logError('setSystemBrightness', e); }
  }

  Future<List<Map<String, dynamic>>> getActiveNotifications() async { 
    if (kIsWeb) return [];
    try { 
      final List<dynamic>? active = await _channel.invokeMethod('getActiveNotifications'); 
      if (active != null) return active.map((e) => Map<String, dynamic>.from(e)).toList(); 
    } catch (e) { _logError('getActiveNotifications', e); } 
    return []; 
  }
  
  Future<Map<String, dynamic>?> pickWidget() async { 
    if (kIsWeb) return null;
    try { 
      final result = await _channel.invokeMethod('pickWidget'); 
      if (result != null) return Map<String, dynamic>.from(result); 
    } catch (e) { _logError('pickWidget', e); } 
    return null; 
  }
  
  Future<bool> removeWidget(int appWidgetId) async { 
    if (kIsWeb) return true;
    try { return await _channel.invokeMethod('removeWidget', {'appWidgetId': appWidgetId}) ?? false; } 
    catch (e) { _logError('removeWidget', e); return false; } 
  }
  
  Future<bool> updateWidgetSize(int appWidgetId, int width, int height) async { 
    if (kIsWeb) return true;
    try { return await _channel.invokeMethod('updateWidgetSize', {'appWidgetId': appWidgetId, 'width': width, 'height': height,}) ?? false; } 
    catch (e) { _logError('updateWidgetSize', e); return false; } 
  }
  
  Future<bool> launchApp(String packageName) async { 
    if (kIsWeb) {
      debugPrint("Web Mock: Launched $packageName");
      return true;
    }
    try { return await _channel.invokeMethod('launchApp', {'package': packageName}) ?? false; } 
    catch (e) { _logError('launchApp', e); return false; } 
  }
  
  Future<bool> uninstallApp(String packageName) async { 
    if (kIsWeb) return true;
    try { return await _channel.invokeMethod('uninstallApp', {'package': packageName}) ?? false; } 
    catch (e) { _logError('uninstallApp', e); return false; } 
  }
  
  Future<bool> lockScreen() async {
    if (kIsWeb) return true;
    try {
      final bool? result = await _channel.invokeMethod<bool>('lockScreen');
      return result ?? false;
    } catch (e) {
      _logError('lockScreen', e);
      return false;
    }
  }

  Future<bool> dismissSystemLock() async {
    if (kIsWeb) return true;
    try {
      final bool? result = await _channel.invokeMethod<bool>('dismissSystemLock');
      return result ?? false;
    } catch (e) {
      _logError('dismissSystemLock', e);
      return false;
    }
  }

  Future<bool> isDeviceLocked() async {
    if (kIsWeb) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>('isDeviceLocked');
      return result ?? false;
    } catch (e) {
      _logError('isDeviceLocked', e);
      return false;
    }
  }

  Future<bool> checkAndClearScreenOffFlag() async {
    if (kIsWeb) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>('checkAndClearScreenOffFlag');
      return result ?? false;
    } catch (e) {
      _logError('checkAndClearScreenOffFlag', e);
      return false;
    }
  }
  
  Future<bool> showPowerDialog() async { 
    if (kIsWeb) return true;
    try { return await _channel.invokeMethod('showPowerDialog') ?? false; } 
    catch (e) { _logError('showPowerDialog', e); return false; } 
  }
  
  Future<bool> toggleRecents() async { 
    if (kIsWeb) return true;
    try { return await _channel.invokeMethod('toggleRecents') ?? false; } 
    catch (e) { _logError('toggleRecents', e); return false; } 
  }
  
  Future<void> openSettings(String type) async { 
    if (kIsWeb) {
      debugPrint("Web Mock: Opened settings -> $type");
      return;
    }
    try { 
      await _channel.invokeMethod('openSettings', {'type': type}); 
    } catch (e) { 
      _logError('openSettings', e); 
      try {
        AppSettings.openAppSettings(type: AppSettingsType.settings);
      } catch (_) {}
    } 
  }
  
  Future<void> toggleHardware(String key, bool enable) async { 
    if (kIsWeb) return;
    try { await _channel.invokeMethod('toggleHardware', {'key': key, 'enable': enable}); } 
    catch (e) { _logError('toggleHardware', e); } 
  }
  
  Future<Map<String, bool>> getPermissionStatuses() async { 
    if (kIsWeb) return {'storage': true, 'notification': true, 'admin': true, 'write_settings': true};
    try { 
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getPermissionStatuses'); 
      if (result != null) return Map<String, bool>.from(result); 
    } catch (e) { _logError('getPermissionStatuses', e); } 
    return {}; 
  }

  Future<bool> openSystemDocumentPicker() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod('openSystemDocumentPicker') ?? false;
    } catch (e) {
      _logError('openSystemDocumentPicker', e);
      return false;
    }
  }
  
  Future<void> openFile(String path) async { 
    if (kIsWeb) return;
    try { await _channel.invokeMethod('openFile', {'path': path}); } 
    catch (e) { _logError('openFile', e); } 
  }
  
  Future<void> shareFile(String path) async { 
    if (kIsWeb) return;
    try { await _channel.invokeMethod('shareFile', {'path': path}); } 
    catch (e) { _logError('shareFile', e); } 
  }
  
  Future<void> shareText(String text) async { 
    if (kIsWeb) return;
    try { await _channel.invokeMethod('shareText', {'text': text}); } 
    catch (e) { _logError('shareText', e); } 
  } 
  
  Future<void> openWebSearch(String query) async { 
    if (kIsWeb) {
      debugPrint("Web Mock: Searching web for -> $query");
      return;
    }
    try { await _channel.invokeMethod('openWebSearch', {'query': query}); } 
    catch (e) { _logError('openWebSearch', e); } 
  }

  Future<bool> saveToDownloads(String path, String fileName) async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod('saveToDownloads', {'path': path, 'fileName': fileName}) ?? false;
    } catch (e) {
      _logError('saveToDownloads', e);
      return false;
    }
  }

  Future<bool> deleteFile(String path) async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>('deleteFile', {'path': path}) ?? false;
    } catch (e) {
      _logError('deleteFile', e);
      return false;
    }
  }
  
  Future<Map<String, dynamic>?> searchMedia(String query) async { 
    if (kIsWeb) return null;
    try { 
      final result = await _channel.invokeMethod('searchMedia', {'query': query}); 
      if (result != null) return Map<String, dynamic>.from(result); 
    } catch (e) { _logError('searchMedia', e); } 
    return null; 
  }
  
  Future<Map<String, double>?> getStorageStats() async { 
    if (kIsWeb) return {'total': 128000000000.0, 'free': 45000000000.0};
    try { 
      final Map<dynamic, dynamic>? stats = await _channel.invokeMethod('getStorageStats'); 
      if (stats != null) return Map<String, double>.from(stats); 
    } catch (e) { _logError('getStorageStats', e); } 
    return null; 
  }

  Future<Map<String, dynamic>?> getSystemPerformanceStats() async {
    if (kIsWeb) {
      return {
        "ram_used_mb": 3840,
        "ram_total_mb": 8192,
        "ram_percent": 47,
        "rx_kbps": 128.5,
        "tx_kbps": 32.4,
        "cpu_temp": 36.5,
      };
    }
    try {
      final Map<dynamic, dynamic>? res = await _channel.invokeMethod('getSystemPerformanceStats');
      if (res != null) return Map<String, dynamic>.from(res);
    } catch (e) {
      _logError('getSystemPerformanceStats', e);
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getDisks() async {
    if (kIsWeb) return [];
    try {
      final List<dynamic>? disks = await _channel.invokeMethod('getDisks');
      if (disks != null) {
        return disks.map((d) => Map<String, dynamic>.from(d)).toList();
      }
    } catch (e) {
      _logError('getDisks', e);
    }
    return [];
  }
  
  Future<void> setStatusBarColor(String colorHex, bool darkIcons) async { 
    if (kIsWeb) return;
    try { await _channel.invokeMethod('setStatusBarColor', {'color': colorHex, 'darkIcons': darkIcons}); } 
    catch (e) { _logError('setStatusBarColor', e); } 
  }
  
  Future<void> expandNotificationPanel() async { 
    if (kIsWeb) return;
    try { await _channel.invokeMethod('expandNotificationPanel'); } 
    catch (e) { _logError('expandNotificationPanel', e); } 
  }
  
  Future<void> clearAllNotifications() async { 
    if (kIsWeb) return;
    try { await _channel.invokeMethod('clearAllNotifications'); } 
    catch (e) { _logError('clearAllNotifications', e); } 
  }
  
  Future<void> dismissNotification(String key) async { 
    if (kIsWeb) return;
    try { await _channel.invokeMethod('dismissNotification', {'key': key}); } 
    catch (e) { _logError('dismissNotification', e); } 
  }
  
  Future<bool> triggerNotificationAction(String key, int actionIndex, {String? replyText}) async { 
    if (kIsWeb) return true;
    try { 
      final Map<String, dynamic> args = {'key': key, 'actionIndex': actionIndex};
      if (replyText != null && replyText.isNotEmpty) {
        args['replyText'] = replyText;
      }
      return await _channel.invokeMethod('triggerNotificationAction', args) ?? false; 
    } 
    catch (e) { _logError('triggerNotificationAction', e); return false; } 
  }

  Future<List<Map<String, String>>> getAvailableIconPacks() async {
    if (kIsWeb) return [];
    try {
      final List<dynamic>? packs = await _channel.invokeMethod('getAvailableIconPacks');
      if (packs != null) {
        return packs.map((p) => Map<String, String>.from(p)).toList();
      }
    } catch (e) { _logError('getAvailableIconPacks', e); }
    return [];
  }

  Future<String?> applyIconPack(String? packageName) async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod('applyIconPack', {'package': packageName});
    } catch (e) { _logError('applyIconPack', e); return null; }
  }

  Future<bool> sendMediaCommand(String command) async {
    if (kIsWeb) return true;
    try {
      return await _channel.invokeMethod('sendMediaCommand', {'command': command}) ?? false;
    } catch (e) {
      _logError('sendMediaCommand', e);
      return false;
    }
  }
}