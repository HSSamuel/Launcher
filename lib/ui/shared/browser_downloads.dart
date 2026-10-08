import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/theme_state.dart';
import '../../services/native_bridge.dart';

class BrowserDownloadsScreen extends StatefulWidget {
  final VoidCallback onBack;

  const BrowserDownloadsScreen({Key? key, required this.onBack}) : super(key: key);

  @override
  State<BrowserDownloadsScreen> createState() => _BrowserDownloadsScreenState();
}

class _BrowserDownloadsScreenState extends State<BrowserDownloadsScreen> {
  List<FileSystemEntity> _downloadedFiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDownloads();
  }

  Future<void> _fetchDownloads() async {
    setState(() => _isLoading = true);
    
    List<FileSystemEntity> files = [];
    // Scan standard Android download paths
    final paths = ['/storage/emulated/0/Download', '/storage/emulated/0/Downloads'];

    for (var path in paths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        try {
          final dirFiles = await dir.list().toList();
          files.addAll(dirFiles.where((f) => f is File && !f.path.split('/').last.startsWith('.')));
        } catch (_) {}
      }
    }

    files.sort((a, b) {
      try {
        return b.statSync().modified.compareTo(a.statSync().modified);
      } catch (_) {
        return 0;
      }
    });

    if (mounted) {
      setState(() {
        _downloadedFiles = files;
        _isLoading = false;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    int i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final isToday = now.year == date.year && now.month == date.month && now.day == date.day;
    
    int h = date.hour % 12 == 0 ? 12 : date.hour % 12;
    String p = date.hour >= 12 ? 'PM' : 'AM';
    String time = '$h:${date.minute.toString().padLeft(2, '0')} $p';

    if (isToday) return 'Today, $time';
    return '${date.month}/${date.day}/${date.year}';
  }

  Widget _buildFileIcon(String extension, bool isDark) {
    IconData icon = Icons.insert_drive_file_outlined;
    Color color = isDark ? Colors.white70 : Colors.black54;
    Color bgColor = isDark ? Colors.white12 : Colors.black.withOpacity(0.05);

    if (['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(extension)) {
      icon = Icons.image; color = Colors.blue; bgColor = Colors.blue.withOpacity(0.15);
    } else if (['pdf'].contains(extension)) {
      icon = Icons.picture_as_pdf; color = Colors.red; bgColor = Colors.red.withOpacity(0.15);
    } else if (['mp4', 'mkv', 'avi'].contains(extension)) {
      icon = Icons.video_file; color = Colors.purple; bgColor = Colors.purple.withOpacity(0.15);
    } else if (['mp3', 'wav', 'm4a'].contains(extension)) {
      icon = Icons.audio_file; color = Colors.orange; bgColor = Colors.orange.withOpacity(0.15);
    } else if (['zip', 'rar', '7z'].contains(extension)) {
      icon = Icons.folder_zip; color = Colors.amber.shade600; bgColor = Colors.amber.withOpacity(0.15);
    } else if (['apk'].contains(extension)) {
      icon = Icons.android; color = Colors.green; bgColor = Colors.green.withOpacity(0.15);
    }

    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color, size: 20),
    );
  }

  void _deleteFile(File file) async {
    try {
      if (await file.exists()) {
        final success = await NativeBridge.instance.deleteFile(file.path);
        if (success) {
          _fetchDownloads();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File deleted')));
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deletion cancelled')));
        }
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete file')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeState>().isDarkMode;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;
    final borderColor = isDark ? Colors.white12 : Colors.black12;

    return Container(
      color: bgColor,
      child: Column(
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor)),
              color: isDark ? const Color(0xFF2B2B2B) : Colors.white,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: textColor, size: 20),
                  onPressed: widget.onBack,
                  tooltip: 'Back to browsing',
                ),
                const SizedBox(width: 8),
                Text('Downloads', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.folder_open, color: textColor, size: 20),
                  onPressed: () {
                    NativeBridge.instance.launchApp('com.google.android.documentsui'); 
                  },
                  tooltip: 'Open in File Manager',
                ),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _downloadedFiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.download_done, size: 48, color: borderColor),
                        const SizedBox(height: 16),
                        Text('No downloaded files', style: TextStyle(color: subTextColor, fontSize: 14)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _downloadedFiles.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                    itemBuilder: (context, index) {
                      final file = _downloadedFiles[index] as File;
                      final fileName = file.path.split('/').last;
                      final extension = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
                      
                      int size = 0;
                      DateTime modified = DateTime.now();
                      try {
                        final stat = file.statSync();
                        size = stat.size;
                        modified = stat.modified;
                      } catch (_) {}

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => NativeBridge.instance.openFile(file.path),
                          hoverColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            child: Row(
                              children: [
                                _buildFileIcon(extension, isDark),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        fileName, 
                                        style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500),
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_formatBytes(size)} • ${_formatDate(modified)}', 
                                        style: TextStyle(color: subTextColor, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert, color: subTextColor, size: 20),
                                  color: isDark ? const Color(0xFF2B2B2B) : Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  onSelected: (val) {
                                    if (val == 'open') NativeBridge.instance.openFile(file.path);
                                    else if (val == 'share') NativeBridge.instance.shareFile(file.path);
                                    else if (val == 'delete') _deleteFile(file);
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(value: 'open', height: 36, child: Row(children: [Icon(Icons.open_in_new, size: 18, color: textColor), const SizedBox(width: 12), Text('Open', style: TextStyle(color: textColor, fontSize: 13))])),
                                    PopupMenuItem(value: 'share', height: 36, child: Row(children: [Icon(Icons.share, size: 18, color: textColor), const SizedBox(width: 12), Text('Share', style: TextStyle(color: textColor, fontSize: 13))])),
                                    PopupMenuItem(value: 'delete', height: 36, child: Row(children: [const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), const SizedBox(width: 12), const Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 13))])),
                                  ],
                                )
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}