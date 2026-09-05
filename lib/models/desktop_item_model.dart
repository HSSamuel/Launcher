class DesktopItemModel {
  final String id;
  final String type; // 'system', 'app', 'file', 'widget', 'native_widget'
  String label;      
  final String? package;
  final String? path;
  final String? widgetType; 
  final int? appWidgetId;
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
    this.spanX = 1,
    this.spanY = 1,
    required this.page,
    required this.col,
    required this.row,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'label': label,
    'package': package,
    'path': path,
    'widgetType': widgetType,
    'appWidgetId': appWidgetId,
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
      spanX: json['spanX'] ?? (json['type'] == 'widget' || json['type'] == 'native_widget' ? 2 : 1),
      spanY: json['spanY'] ?? 1,
      page: json['page'] ?? 0,
      col: json['col'] ?? 0,
      row: json['row'] ?? 0,
    );
  }
}