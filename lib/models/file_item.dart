class FileItem {
  final String path;
  final bool isDir;
  final int size;
  final DateTime modified;
  final int itemCount;
  
  FileItem({
    required this.path, 
    required this.isDir, 
    required this.size, 
    required this.modified, 
    this.itemCount = 0
  });
}