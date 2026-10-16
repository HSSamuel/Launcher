// settings_backup_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';

import '../../states/theme_state.dart';
import '../../services/backup_service.dart';
import '../../services/native_bridge.dart';
import '../../ui/explorer/file_system_service.dart'; 
import '../../models/file_item.dart'; 
import 'settings_widgets.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({Key? key}) : super(key: key);

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _isProcessing = false;
  bool _autoBackupEnabled = true;
  static const String _lastBackupPathKey = 'last_backup_export_path';

  @override
  void initState() {
    super.initState();
    _loadAutoBackupPreference();
  }

  Future<void> _loadAutoBackupPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoBackupEnabled = prefs.getBool(BackupService.keyAutoBackupEnabled) ?? true;
    });
  }

  Future<void> _toggleAutoBackup(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(BackupService.keyAutoBackupEnabled, value);
    setState(() => _autoBackupEnabled = value);
    if (value) {
      BackupService.instance.checkAndRunWeeklyBackup();
    }
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    
    final screenHeight = MediaQuery.of(context).size.height;
    
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13, color: Colors.white), textAlign: TextAlign.center),
        backgroundColor: isError ? Colors.redAccent : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        margin: EdgeInsets.only(
          bottom: screenHeight / 2 - 24,
          left: 32,
          right: 32,
        ),
      ),
    );
  }

  Future<void> _handleExport() async {
    setState(() => _isProcessing = true);
    try {
      final zipBytes = await BackupService.instance.generateBackupArchive();
      
      final now = DateTime.now();
      final day = now.day.toString().padLeft(2, '0');
      final month = now.month.toString().padLeft(2, '0');
      final year = now.year.toString();
      final fileName = 'Win11Launcher_Backup_$day-$month-$year.zip';

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(zipBytes, flush: true);

      final bool success = await NativeBridge.instance.saveToDownloads(tempFile.path, fileName);
      
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      if (success) {
        String downloadPath = '/storage/emulated/0/Download';
        try {
          final extDir = await getExternalStorageDirectory();
          if (extDir != null && extDir.path.contains('/Android')) {
            final rootPath = extDir.path.substring(0, extDir.path.indexOf('/Android'));
            downloadPath = '$rootPath/Download';
          }
        } catch (_) {}

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastBackupPathKey, '$downloadPath/$fileName');
        _showToast('Backup saved successfully to Downloads folder!');
      } else {
        _showToast('Backup export cancelled or failed.');
      }
    } catch (e) {
      _showToast('Failed to export backup: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _importBackup() async {
    try {
      setState(() => _isProcessing = true);
      
      // CRITICAL FIX: Safe path derivation for Downloads to support Scoped Storage
      String downloadPath = '/storage/emulated/0/Download';
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null && extDir.path.contains('/Android')) {
          final rootPath = extDir.path.substring(0, extDir.path.indexOf('/Android'));
          downloadPath = '$rootPath/Download';
        }
      } catch (_) {}

      final List<FileItem> downloadFiles = await FileSystemService.getDirectoryContentsNative(downloadPath);
      final zipFiles = downloadFiles.where((f) => !f.isDir && f.path.toLowerCase().endsWith('.zip')).toList();

      setState(() => _isProcessing = false);

      if (zipFiles.isEmpty) {
        _showToast('No .zip backup files found in your Downloads folder.', isError: true);
        return;
      }

      final isDark = context.read<ThemeState>().isDarkMode;
      
      final FileItem? selectedFile = await showDialog<FileItem>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: Text('Select Backup File', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: zipFiles.length,
              itemBuilder: (context, index) {
                 final file = zipFiles[index];
                 return ListTile(
                   leading: const Icon(Icons.folder_zip, color: Colors.orangeAccent),
                   title: Text(file.path.split('/').last, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13)),
                   subtitle: Text('${(file.size / 1024).toStringAsFixed(1)} KB', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 11)),
                   onTap: () => Navigator.pop(ctx, file),
                 );
              }
            )
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx), 
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))
            )
          ],
        )
      );

      if (selectedFile != null) {
        setState(() => _isProcessing = true);
        
        final bool success = await BackupService.instance.restoreBackup(selectedFile.path);
        
        if (!success) {
          _showToast('Invalid backup file or corrupt data', isError: true);
          return;
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastBackupPathKey, selectedFile.path);

        if (!mounted) return;
        setState(() => _isProcessing = false);
        _showRestartDialog();
      }
    } catch (e) {
      _showToast('Failed to read Downloads folder: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showRestartDialog() {
    final isDark = context.read<ThemeState>().isDarkMode;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(
          'Restore Complete',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'All settings, app layouts, PIN security, and custom wallpapers have been successfully restored.\n\nThe launcher will now restart to finalize the installation.',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              NativeBridge.instance.restartApp();
            },
            child: const Text('Restart Launcher', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'System > Backup & Restore'),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            physics: const BouncingScrollPhysics(),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 16),
                child: Text(
                  'Protect your custom layouts, wallpapers, folders, and system setup by exporting them into an all-in-one file. You can overwrite an existing backup or import it onto another device.',
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13, height: 1.4),
                ),
              ),
              SettingsCard(
                title: 'Export Backup',
                subtitle: 'Save a .zip package containing all launcher settings and wallpaper assets.',
                icon: Icons.upload_file_outlined,
                onTap: _isProcessing ? null : _handleExport,
              ),
              SettingsCard(
                title: 'Import Backup',
                subtitle: 'Select a previously saved .zip backup file from your Downloads folder.',
                icon: Icons.restore_page_outlined,
                onTap: _isProcessing ? null : _importBackup,
              ),
              const SizedBox(height: 8),
              SettingsCard(
                title: 'Automatic Weekly Backup',
                subtitle: _autoBackupEnabled
                    ? 'Silently backs up settings and wallpaper every 7 days'
                    : 'Automated weekly backups are disabled',
                icon: Icons.update,
                trailing: Switch(
                  value: _autoBackupEnabled,
                  activeColor: Colors.blueAccent,
                  onChanged: _toggleAutoBackup,
                ),
              ),
            ],
          ),
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.4),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.blueAccent),
              ),
            ),
        ],
      ),
    );
  }
}