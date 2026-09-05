import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class NativeBridge {
  NativeBridge._privateConstructor();
  static final NativeBridge instance = NativeBridge._privateConstructor();

  static const MethodChannel _channel = MethodChannel('win_launcher/native');
  static const EventChannel _notifChannel = EventChannel('win_launcher/notifications');
  static const EventChannel _hwChannel = EventChannel('win_launcher/hardware_events'); 

  Stream<dynamic> get notificationStream => _notifChannel.receiveBroadcastStream();
  Stream<dynamic> get hardwareStateStream => _hwChannel.receiveBroadcastStream(); 

  Future<Map<String, dynamic>> getHardwareState() async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getHardwareState');
      if (result != null) return Map<String, dynamic>.from(result);
    } catch (e) {
      debugPrint("NativeBridge Error (getHardwareState): $e");
    }
    return {};
  }

  Future<void> setSystemBrightness(double value) async {
    try { await _channel.invokeMethod('setSystemBrightness', {'brightness': value}); } catch (_) {}
  }

  // --- Identical Legacy Methods ---
  Future<List<Map<String, dynamic>>> getActiveNotifications() async { try { final List<dynamic>? active = await _channel.invokeMethod('getActiveNotifications'); if (active != null) return active.map((e) => Map<String, dynamic>.from(e)).toList(); } catch (_) {} return []; }
  Future<Map<String, dynamic>?> pickWidget() async { try { final result = await _channel.invokeMethod('pickWidget'); if (result != null) return Map<String, dynamic>.from(result); } catch (_) {} return null; }
  Future<bool> removeWidget(int appWidgetId) async { try { return await _channel.invokeMethod('removeWidget', {'appWidgetId': appWidgetId}) ?? false; } catch (_) { return false; } }
  Future<bool> updateWidgetSize(int appWidgetId, int width, int height) async { try { return await _channel.invokeMethod('updateWidgetSize', {'appWidgetId': appWidgetId, 'width': width, 'height': height,}) ?? false; } catch (_) { return false; } }
  Future<bool> launchApp(String packageName) async { try { return await _channel.invokeMethod('launchApp', {'package': packageName}) ?? false; } catch (_) { return false; } }
  Future<bool> uninstallApp(String packageName) async { try { return await _channel.invokeMethod('uninstallApp', {'package': packageName}) ?? false; } catch (_) { return false; } }
  Future<void> lockScreen() async { try { await _channel.invokeMethod('lockScreen'); } catch (_) {} }
  Future<bool> showPowerDialog() async { try { return await _channel.invokeMethod('showPowerDialog') ?? false; } catch (_) { return false; } }
  Future<bool> toggleRecents() async { try { return await _channel.invokeMethod('toggleRecents') ?? false; } catch (_) { return false; } }
  Future<void> openSettings(String type) async { try { await _channel.invokeMethod('openSettings', {'type': type}); } catch (_) {} }
  Future<void> toggleHardware(String key, bool enable) async { try { await _channel.invokeMethod('toggleHardware', {'key': key, 'enable': enable}); } catch (_) {} }
  Future<Map<String, bool>> getPermissionStatuses() async { try { final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getPermissionStatuses'); if (result != null) return Map<String, bool>.from(result); } catch (_) {} return {}; }
  Future<void> openFile(String path) async { try { await _channel.invokeMethod('openFile', {'path': path}); } catch (_) {} }
  Future<void> shareFile(String path) async { try { await _channel.invokeMethod('shareFile', {'path': path}); } catch (_) {} }
  Future<void> openWebSearch(String query) async { try { await _channel.invokeMethod('openWebSearch', {'query': query}); } catch (_) {} }
  Future<Map<String, dynamic>?> searchMedia(String query) async { try { final result = await _channel.invokeMethod('searchMedia', {'query': query}); if (result != null) return Map<String, dynamic>.from(result); } catch (_) {} return null; }
  Future<Map<String, double>?> getStorageStats() async { try { final Map<dynamic, dynamic>? stats = await _channel.invokeMethod('getStorageStats'); if (stats != null) return Map<String, double>.from(stats); } catch (_) {} return null; }
  Future<void> setStatusBarColor(String colorHex, bool darkIcons) async { try { await _channel.invokeMethod('setStatusBarColor', {'color': colorHex, 'darkIcons': darkIcons}); } catch (_) {} }
  Future<void> expandNotificationPanel() async { try { await _channel.invokeMethod('expandNotificationPanel'); } catch (_) {} }
  Future<void> clearAllNotifications() async { try { await _channel.invokeMethod('clearAllNotifications'); } catch (_) {} }
  Future<void> dismissNotification(String key) async { try { await _channel.invokeMethod('dismissNotification', {'key': key}); } catch (_) {} }
  Future<bool> triggerNotificationAction(String key, int actionIndex) async { try { return await _channel.invokeMethod('triggerNotificationAction', {'key': key, 'actionIndex': actionIndex}) ?? false; } catch (_) { return false; } }
}