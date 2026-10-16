import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../models/file_item.dart';

class FileSystemService {
  static const MethodChannel _channel = MethodChannel('win_launcher/native');

  static Future<void> isolateCopyDirectory(Map<String, String> args) async {
    final source = Directory(args['source']!);
    final destination = Directory(args['destination']!);
    
    if (destination.path.startsWith('${source.path}/') || destination.path == source.path) {
      throw ArgumentError('Cannot copy a directory into its own child subdirectory.');
    }
    
    await _copyDirectoryRecursive(source, destination);
  }

  static Future<void> _copyDirectoryRecursive(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (var entity in source.list(recursive: false, followLinks: false)) {
      try {
        if (entity is Directory) {
          var newDirectory = Directory('${destination.path}/${entity.path.split('/').last}');
          await _copyDirectoryRecursive(entity, newDirectory);
        } else if (entity is File) {
          await entity.copy('${destination.path}/${entity.path.split('/').last}');
        }
      } catch (e) {
        debugPrint('Failed to copy ${entity.path}: $e');
      }
    }
  }

  // NOTE: READ_MEDIA_* permissions allow dart:io to successfully scan standard 
  // media directories on Android 11+ without requiring MANAGE_EXTERNAL_STORAGE.
  // We can safely leave this heavily optimized isolate logic intact.
  static Future<List<FileItem>> scanAggregatedMediaIsolate(Map<String, dynamic> params) async {
    final String rootPath = params['rootPath'];
    final String category = params['category'];
    
    final Set<String> extensions = {};
    if (category == 'Pictures') {
      extensions.addAll(['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic']);
    } else if (category == 'Music') {
      extensions.addAll(['.mp3', '.wav', '.m4a', '.aac', '.flac', '.ogg', '.wma']);
    } else if (category == 'Videos') {
      extensions.addAll(['.mp4', '.mkv', '.mov', '.avi', '.3gp', '.webm', '.flv']);
    } else if (category == 'Documents') {
      extensions.addAll(['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.csv', '.rtf']);
    }

    final List<FileItem> results = [];
    final Set<String> seenSignatures = {};
    
    final List<String> targetDirs = [
      '$rootPath/DCIM',
      '$rootPath/Pictures',
      '$rootPath/Download',
      '$rootPath/Music',
      '$rootPath/Movies',
      '$rootPath/WhatsApp/Media',
      '$rootPath/Telegram',
      '$rootPath/Documents',
    ];

    void walkSafely(Directory dir, int depth) {
      if (depth > 5) return; 
      try {
        final list = dir.listSync(followLinks: false);
        
        if (list.any((e) => e.path.split('/').last == '.nomedia')) return;

        for (final entity in list) {
          final name = entity.path.split('/').last;
          if (name.startsWith('.')) continue; 
          
          if (entity is Directory) {
            final lower = name.toLowerCase();
            if (lower == 'android' || lower == 'data') continue; 
            walkSafely(entity, depth + 1);
          } else if (entity is File) {
            final dotIdx = name.lastIndexOf('.');
            if (dotIdx != -1) {
  final ext = name.substring(dotIdx).toLowerCase();
  if (extensions.contains(ext)) {
    try {
      final stat = entity.statSync();
      
      // CRITICAL FIX: Skip and purge 0-byte ghost files from library views
      if (stat.size == 0) {
        try { entity.deleteSync(); } catch (_) {}
        continue;
      }

      final signature = '${name}_${stat.size}';
      
      if (!seenSignatures.contains(signature)) {
                    seenSignatures.add(signature);
                    results.add(FileItem(
                      path: entity.path,
                      isDir: false,
                      size: stat.size,
                      modified: stat.modified,
                    ));
                  }
                } catch (_) {}
              }
            }
          }
        }
      } catch (_) {}
    }

    for (String target in targetDirs) {
      final dir = Directory(target);
      if (dir.existsSync()) {
        walkSafely(dir, 0);
      }
    }

    results.sort((a, b) => b.modified.compareTo(a.modified));
    return results.length > 500 ? results.sublist(0, 500) : results;
  }

  // =========================================================================
  // CRITICAL NEW METHOD: Fetches folder contents natively via MediaStore.
  // Bypasses Android 11+ Scoped Storage blocks for non-media files.
  // =========================================================================
  // MUST BE CALLED DIRECTLY ON THE MAIN THREAD - DO NOT USE compute() 
  // (The Kotlin bridging backend utilizes Dispatchers.IO to prevent freezing)
  static Future<List<FileItem>> getDirectoryContentsNative(String dirPath) async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod('getFilesInDirectory', {'path': dirPath});
      
      if (result != null) {
        return result.map((e) => FileItem(
          path: e['path'] as String,
          isDir: e['isDir'] == true,
          size: (e['size'] as num?)?.toInt() ?? 0,
          modified: DateTime.fromMillisecondsSinceEpoch((e['modified'] as num?)?.toInt() ?? 0),
          itemCount: 0,
        )).toList();
      }
    } catch (e) {
      debugPrint('Native MediaStore query failed: $e');
    }
    return [];
  }

  // NOTE: This method is retained strictly to prevent breaking code references in your unedited files.
  // However, it will fail on restricted directories (like Downloads) on Android 11+ and above.
  static Future<List<FileItem>> processDirectoryInBackground(String dirPath) async {
    final dir = Directory(dirPath);
    final items = <FileItem>[];
    try {
      final entities = dir.listSync(followLinks: false);
      for (var e in entities) {
        if (e.path.split('/').last == '.nomedia' || e.path.split('/').last == '.recycle_index.json') continue;
        final stat = e.statSync();
        items.add(FileItem(path: e.path, isDir: e is Directory, size: stat.size, modified: stat.modified, itemCount: 0));
      }
    } catch (_) {}
    return items;
  }
}