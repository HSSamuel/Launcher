// backup_service.dart
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'native_bridge.dart';

class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const String keyAutoBackupEnabled = 'auto_weekly_backup_enabled';
  static const String keyLastAutoBackupTimestamp = 'last_auto_backup_timestamp';
  static const String defaultAutoBackupFileName = 'auto_backup_weekly.zip';

  static Future<Uint8List> _isolateGenerateZipBytes(Map<String, dynamic> args) async {
    final prefsMap = args['prefsMap'] as Map<String, dynamic>;
    final userImagePath = args['userImagePath'] as String?;
    final wallpaperPath = args['wallpaperPath'] as String?;

    final archive = Archive();

    final prefsData = utf8.encode(jsonEncode(prefsMap));
    archive.addFile(ArchiveFile('preferences.json', prefsData.length, prefsData));

    if (userImagePath != null) {
      final file = File(userImagePath);
      if (file.existsSync() && file.lengthSync() < 4 * 1024 * 1024) {
        try {
          final bytes = file.readAsBytesSync();
          archive.addFile(ArchiveFile('profile_pic.png', bytes.length, bytes));
        } catch (_) {}
      }
    }

    if (wallpaperPath != null && !wallpaperPath.startsWith('assets/')) {
      final file = File(wallpaperPath);
      if (file.existsSync() && file.lengthSync() < 8 * 1024 * 1024) {
        try {
          final bytes = file.readAsBytesSync();
          final ext = wallpaperPath.split('.').last;
          archive.addFile(ArchiveFile('wallpaper.$ext', bytes.length, bytes));
        } catch (_) {}
      }
    }

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  Future<Uint8List> generateBackupArchive() async {
    final prefs = await SharedPreferences.getInstance();

    final Map<String, dynamic> preferencesMap = {};
    for (String key in prefs.getKeys()) {
      if (key == 'last_backup_export_path' || key == keyLastAutoBackupTimestamp) continue;
      preferencesMap[key] = prefs.get(key);
    }
    
    final userImagePath = prefs.getString('userImagePath');
    final wallpaperPath = prefs.getString('wallpaper');

    return await compute(_isolateGenerateZipBytes, {
      'prefsMap': preferencesMap,
      'userImagePath': userImagePath,
      'wallpaperPath': wallpaperPath,
    });
  }

  static Future<Map<String, dynamic>> _isolateRestoreZipFromDisk(String zipPath) async {
    final file = File(zipPath);
    final bytes = file.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
      
    String? prefsJson;
    Uint8List? profilePicBytes;
    Uint8List? wallpaperBytes;
    String? wallpaperExt;

    for (final file in archive) {
      if (file.isFile) {
        final data = file.content as List<int>;
        if (file.name == 'preferences.json') {
          prefsJson = utf8.decode(data);
        } else if (file.name.startsWith('profile_pic')) {
          profilePicBytes = Uint8List.fromList(data);
        } else if (file.name.startsWith('wallpaper.')) {
          wallpaperExt = file.name.split('.').last;
          wallpaperBytes = Uint8List.fromList(data);
        }
      }
    }
      
    return {
      'prefsJson': prefsJson,
      'profilePicBytes': profilePicBytes,
      'wallpaperBytes': wallpaperBytes,
      'wallpaperExt': wallpaperExt,
    };
  }

  Future<bool> restoreBackup(String zipPath) async {
    try {
      final extractedData = await compute(_isolateRestoreZipFromDisk, zipPath);
      final prefsJson = extractedData['prefsJson'] as String?;
      
      if (prefsJson == null) return false;

      final prefs = await SharedPreferences.getInstance();
      final appDocsDir = await getApplicationDocumentsDirectory();

      final prefMap = jsonDecode(prefsJson) as Map<String, dynamic>;
            
      if (prefMap.containsKey('desktop_items') && prefMap['desktop_items'] is String) {
        try {
          final List<dynamic> items = jsonDecode(prefMap['desktop_items']);
          final List<dynamic> cleanItems = [];
          for (var item in items) {
            if (item is Map) {
              if (item['type'] == 'native_widget') continue;
              cleanItems.add(item);
            }
          }
          prefMap['desktop_items'] = jsonEncode(cleanItems);
        } catch (_) {}
      }

      for (var entry in prefMap.entries) {
        final String key = entry.key;
        final dynamic val = entry.value;

        if (key == 'userImagePath' || (key == 'wallpaper' && val is String && !val.startsWith('assets/'))) {
          continue;
        }
        if (val == null) continue;

        if (val is bool) {
          await prefs.setBool(key, val);
        } else if (val is num) {
          if (val is double || key.toLowerCase().contains('scale') || key.toLowerCase().contains('size') || key.toLowerCase().contains('height')) {
            await prefs.setDouble(key, val.toDouble());
          } else {
            await prefs.setInt(key, val.toInt());
          }
        } else if (val is String) {
          await prefs.setString(key, val);
        } else if (val is List) {
          final stringList = val.map((e) => e?.toString() ?? '').toList();
          await prefs.setStringList(key, stringList);
        }
      }
      
      final profileBytes = extractedData['profilePicBytes'] as Uint8List?;
      if (profileBytes != null) {
        final outFile = File('${appDocsDir.path}/restored_profile.png');
        await outFile.writeAsBytes(profileBytes, flush: true);
        await prefs.setString('userImagePath', outFile.path);
      }
      
      final wallpaperBytes = extractedData['wallpaperBytes'] as Uint8List?;
      if (wallpaperBytes != null) {
        final ext = extractedData['wallpaperExt'] ?? 'png';
        final outFile = File('${appDocsDir.path}/restored_wallpaper.$ext');
        await outFile.writeAsBytes(wallpaperBytes, flush: true);
        await prefs.setString('wallpaper', outFile.path);
      }

      return true;
    } catch (e) {
      debugPrint("Fatal error restoring backup payload: $e");
      return false;
    }
  }

  Future<bool> checkAndRunWeeklyBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool isEnabled = prefs.getBool(keyAutoBackupEnabled) ?? true;
      if (!isEnabled) return false;

      final int? lastRun = prefs.getInt(keyLastAutoBackupTimestamp);
      final int now = DateTime.now().millisecondsSinceEpoch;
      const int sevenDaysMs = 604800000;

      if (lastRun != null && (now - lastRun) < sevenDaysMs) {
        return false;
      }

      final zipPayload = await generateBackupArchive();
      
      // CRITICAL FIX: Route automated backups to the App's Scoped Storage directory.
      // This bypasses the MANAGE_EXTERNAL_STORAGE requirement and eliminates OS Error 13.
      final extDir = await getExternalStorageDirectory();
      final docsDir = await getApplicationDocumentsDirectory();
      
      final Directory backupDir = extDir != null 
          ? Directory('${extDir.path}/Win11_Backups') 
          : Directory('${docsDir.path}/Win11_Backups');

      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final backupFile = File('${backupDir.path}/$defaultAutoBackupFileName');
      await backupFile.writeAsBytes(zipPayload, flush: true);

      await prefs.setInt(keyLastAutoBackupTimestamp, now);
      debugPrint("Automatic weekly backup written safely to ${backupFile.path}");
      return true;
    } catch (e) {
      debugPrint("Automatic weekly backup failed: $e");
      return false;
    }
  }
}