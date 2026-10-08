class DesktopItemModel {
  final String id;
  final String type; // 'system', 'app', 'file', 'widget', 'native_widget', 'folder'
  String label;      
  final String? package;
  final String? path;
  final String? widgetType; 
  final int? appWidgetId;
  List<String>? folderApps; 
  int spanX;
  int spanY;
  int page;
  int col;
  int row;

  DesktopItemModel({
    required this.id,
    required this.type,
    required this.label,
    this.package,
    this.path,
    this.widgetType,
    this.appWidgetId,
    this.folderApps,
    this.spanX = 1,
    this.spanY = 1,
    required this.page,
    required this.col,
    required this.row,
  });

  DesktopItemModel copyWith({
    String? id,
    String? type,
    String? label,
    String? package,
    String? path,
    String? widgetType,
    int? appWidgetId,
    List<String>? folderApps,
    int? spanX,
    int? spanY,
    int? page,
    int? col,
    int? row,
  }) {
    return DesktopItemModel(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      package: package ?? this.package,
      path: path ?? this.path,
      widgetType: widgetType ?? this.widgetType,
      appWidgetId: appWidgetId ?? this.appWidgetId,
      folderApps: folderApps ?? this.folderApps,
      spanX: spanX ?? this.spanX,
      spanY: spanY ?? this.spanY,
      page: page ?? this.page,
      col: col ?? this.col,
      row: row ?? this.row,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'label': label,
    'package': package,
    'path': path,
    'widgetType': widgetType,
    'appWidgetId': appWidgetId,
    'folderApps': folderApps,
    'spanX': spanX,
    'spanY': spanY,
    'page': page,
    'col': col,
    'row': row,
  };

  factory DesktopItemModel.fromJson(Map<String, dynamic> json) {
    return DesktopItemModel(
      id: json['id'],
      type: json['type'],
      label: json['label'],
      package: json['package'],
      path: json['path'],
      widgetType: json['widgetType'],
      appWidgetId: json['appWidgetId'],
      folderApps: json['folderApps'] != null ? List<String>.from(json['folderApps']) : null,
      spanX: json['spanX'] ?? (json['type'] == 'widget' || json['type'] == 'native_widget' ? 2 : 1),
      spanY: json['spanY'] ?? 1,
      page: json['page'] ?? 0,
      col: json['col'] ?? 0,
      row: json['row'] ?? 0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DesktopItemModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}