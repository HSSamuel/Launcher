class CloudFile {
  final String id;
  final String name;
  final String path;
  final bool isFolder;
  final int size;
  final DateTime? modifiedTime;
  final String provider; 
  final String? thumbnailLink; // NEW

  CloudFile({
    required this.id,
    required this.name,
    required this.path,
    required this.isFolder,
    required this.size,
    this.modifiedTime,
    required this.provider,
    this.thumbnailLink, // NEW
  });
}