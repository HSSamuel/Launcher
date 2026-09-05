import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../launcher_state.dart';

class ExplorerTitleBar extends StatelessWidget {
  final bool isDark;
  final VoidCallback onRestoreStatusBar;

  const ExplorerTitleBar({Key? key, required this.isDark, required this.onRestoreStatusBar}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final bgColor = isDark ? const Color(0xFF191919) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accent = state.currentAccentColor;

    return Container(
      height: 36, color: bgColor,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Container(width: 14, height: 12, color: accent),
          const SizedBox(width: 8),
          Text('This PC', style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w400)),
          const Spacer(),
          InkWell(
            onTap: () { onRestoreStatusBar(); state.minimizeApp('explorer'); }, 
            child: SizedBox(width: 44, height: 36, child: Center(child: Icon(Icons.remove, size: 16, color: textColor)))
          ),
          InkWell(
            onTap: () => state.toggleMaximizeApp('explorer'), 
            child: SizedBox(width: 44, height: 36, child: Center(child: Icon(Icons.crop_square, size: 14, color: textColor)))
          ),
          InkWell(
            onTap: () { onRestoreStatusBar(); state.closeApp('explorer'); }, 
            hoverColor: Colors.red, 
            child: SizedBox(width: 44, height: 36, child: Center(child: Icon(Icons.close, size: 16, color: textColor)))
          ),
        ],
      ),
    );
  }
}

class ExplorerToolbar extends StatelessWidget {
  final bool isDark;
  final bool hasSelection;
  final bool isSingleSelection;
  final bool canPaste;
  final VoidCallback onNewFolder;
  final VoidCallback onCut;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  const ExplorerToolbar({
    Key? key, required this.isDark, required this.hasSelection, required this.isSingleSelection, 
    required this.canPaste, required this.onNewFolder, required this.onCut, required this.onCopy, 
    required this.onPaste, required this.onRename, required this.onDelete, required this.onShare,
  }) : super(key: key);

  PopupMenuItem<String> _buildPopupItem(String title, IconData? icon, bool isDark, {bool isActive = false}) {
    final textColor = isDark ? Colors.white : Colors.black87;
    return PopupMenuItem<String>(
      value: title, height: 32, padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(width: 16, child: isActive ? Icon(Icons.circle, size: 5, color: textColor) : null),
          if (icon != null) Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(fontSize: 12, color: textColor))),
          if (title == 'Show') Icon(Icons.chevron_right, size: 16, color: textColor)
        ],
      ),
    );
  }

  Widget _toolBtn(IconData icon, bool isDark, {bool disabled = false, Color? color, VoidCallback? onTap}) {
    final defaultColor = color ?? (isDark ? Colors.white : Colors.black87);
    final disabledColor = isDark ? Colors.white24 : Colors.black26;
    return InkWell(
      onTap: disabled ? null : (onTap ?? () {}),
      borderRadius: BorderRadius.circular(4),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Icon(icon, size: 16, color: disabled ? disabledColor : defaultColor)),
    );
  }

  Widget _divider(bool isDark) => Container(height: 14, width: 1, color: isDark ? Colors.white24 : Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 2));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final activeColor = state.currentAccentColor;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black87;
    final popupBg = isDark ? const Color(0xFF2B2B2B) : Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor))),
      child: Row(
        children: [
          InkWell(
            onTap: onNewFolder, borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline, size: 16, color: activeColor), const SizedBox(width: 4),
                  Text('New', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w400)), const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down, size: 14, color: isDark ? Colors.white54 : Colors.black54),
                ],
              ),
            ),
          ),
          _divider(isDark),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _toolBtn(Icons.content_cut, isDark, disabled: !isSingleSelection, color: activeColor, onTap: onCut),
                  _toolBtn(Icons.content_copy, isDark, disabled: !isSingleSelection, color: activeColor, onTap: onCopy),
                  _toolBtn(Icons.assignment_outlined, isDark, disabled: !canPaste, color: activeColor, onTap: onPaste),
                  _toolBtn(Icons.drive_file_rename_outline, isDark, disabled: !isSingleSelection, color: activeColor, onTap: onRename),
                  _toolBtn(Icons.share_outlined, isDark, disabled: !isSingleSelection, color: activeColor, onTap: onShare),
                  _toolBtn(Icons.delete_outline, isDark, disabled: !hasSelection, color: activeColor, onTap: onDelete),
                  _divider(isDark),
                ],
              ),
            ),
          ),
          _toolBtn(Icons.swap_vert, isDark),
          PopupMenuButton<String>(
            tooltip: '', offset: const Offset(0, 24), color: popupBg, elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            itemBuilder: (context) => [ _buildPopupItem('Extra Large Icons', Icons.crop_square, isDark), _buildPopupItem('Large Icons', Icons.crop_din, isDark), _buildPopupItem('Medium Icons', Icons.crop_7_5, isDark), _buildPopupItem('Small Icons', Icons.grid_view, isDark), _buildPopupItem('List', Icons.format_list_bulleted, isDark, isActive: true), const PopupMenuDivider(), _buildPopupItem('Show', null, isDark) ],
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Icon(Icons.web_asset, size: 16, color: isDark ? Colors.white : Colors.black87)), 
          ),
          _divider(isDark),
          PopupMenuButton<String>(
            tooltip: '', offset: const Offset(0, 24), color: popupBg, elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            itemBuilder: (context) => [ _buildPopupItem('Pin to Quick Access', Icons.push_pin_outlined, isDark), const PopupMenuDivider(), _buildPopupItem('Select all', Icons.select_all, isDark), _buildPopupItem('Select none', Icons.grid_off_outlined, isDark), _buildPopupItem('Invert selection', Icons.flip_to_back_outlined, isDark), const PopupMenuDivider(), _buildPopupItem('Properties', Icons.description_outlined, isDark) ],
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Icon(Icons.more_horiz, size: 16, color: isDark ? Colors.white : Colors.black87)), 
          ),
        ],
      ),
    );
  }
}

class ExplorerAddressBar extends StatelessWidget {
  final bool isDark;
  final bool isAtHome;
  final String currentPath;
  final String rootPath;
  final List<String> pathHistory;
  final VoidCallback onGoBack;
  final VoidCallback onGoHome;
  final Function(String) onNavigate;

  const ExplorerAddressBar({
    Key? key, required this.isDark, required this.isAtHome, required this.currentPath, required this.rootPath, 
    required this.pathHistory, required this.onGoBack, required this.onGoHome, required this.onNavigate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final accent = state.currentAccentColor;
    final btnStyle = IconButton.styleFrom(padding: const EdgeInsets.all(2), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap);
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final inputBg = isDark ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    List<Widget> breadcrumbs = [
      Container(width: 12, height: 10, color: accent), const SizedBox(width: 4),
      InkWell(onTap: onGoHome, child: Text('This PC', style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600))), const SizedBox(width: 2),
      Icon(Icons.chevron_right, size: 14, color: textColor),
    ];

    if (!isAtHome) {
      final folders = currentPath.replaceFirst(rootPath, '').split('/').where((e) => e.isNotEmpty).toList();
      String cumulativePath = rootPath;
      for (var folder in folders) {
        cumulativePath += '/$folder';
        final targetPath = cumulativePath;
        breadcrumbs.add(const SizedBox(width: 2));
        breadcrumbs.add(InkWell(onTap: () => onNavigate(targetPath), child: Text(folder, style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600))));
        breadcrumbs.add(const SizedBox(width: 2));
        breadcrumbs.add(Icon(Icons.chevron_right, size: 14, color: textColor));
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200))),
      child: Row(
        children: [
          IconButton(icon: Icon(Icons.arrow_back, size: 18, color: textColor), onPressed: pathHistory.isEmpty ? null : onGoBack, style: btnStyle), const SizedBox(width: 2),
          IconButton(icon: Icon(Icons.arrow_forward, size: 18, color: isDark ? Colors.white30 : Colors.black38), onPressed: null, style: btnStyle), const SizedBox(width: 4),
          Expanded(
            flex: 7,
            child: Container(
              height: 26, padding: const EdgeInsets.symmetric(horizontal: 4), 
              decoration: BoxDecoration(border: Border.all(color: borderColor), color: inputBg, borderRadius: BorderRadius.circular(2)),
              child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: breadcrumbs)),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 3,
            child: Container(
              height: 26, padding: const EdgeInsets.symmetric(horizontal: 4), 
              decoration: BoxDecoration(border: Border.all(color: borderColor), color: inputBg, borderRadius: BorderRadius.circular(2)),
              child: Row(children: [Icon(Icons.search, size: 12, color: isDark ? Colors.white54 : Colors.black54), const SizedBox(width: 4), Expanded(child: Text('Search...', style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade600), overflow: TextOverflow.ellipsis))]),
            ),
          ),
        ],
      ),
    );
  }
}

class ExplorerSidebar extends StatefulWidget {
  final double width;
  final bool isDark;
  final bool isAtHome;
  final String rootPath;
  final VoidCallback onGoHome;
  final Function(String) onNavigate;

  const ExplorerSidebar({
    Key? key, required this.width, required this.isDark, required this.isAtHome, required this.rootPath, required this.onGoHome, required this.onNavigate,
  }) : super(key: key);

  @override
  State<ExplorerSidebar> createState() => _ExplorerSidebarState();
}

class _ExplorerSidebarState extends State<ExplorerSidebar> {
  bool _isQuickAccessExpanded = true;
  bool _isThisPCExpanded = true;

  Widget _buildSidebarHeader(IconData icon, String label, Color iconColor, bool isSelected, VoidCallback? onTap, bool isExpanded, VoidCallback onToggle) {
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    return Material(
      color: isSelected ? (widget.isDark ? Colors.white12 : Colors.lightBlue.withOpacity(0.08)) : Colors.transparent,
      child: Row(
        children: [
          InkWell(onTap: onToggle, child: Padding(padding: const EdgeInsets.all(6.0), child: Icon(isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: textColor))),
          Expanded(
            child: InkWell(
              onTap: onTap ?? onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: iconColor), const SizedBox(width: 6),
                    Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarAssetItem(String label, String assetName, VoidCallback? onTap) {
    final hoverColor = widget.isDark ? Colors.white10 : Colors.lightBlue.withOpacity(0.08);
    final textColor = widget.isDark ? Colors.white70 : Colors.grey.shade700;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap, hoverColor: hoverColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
          child: Row(
            children: [
              const SizedBox(width: 16), 
              Image.asset('assets/icons/$assetName.png', width: 16, height: 16, errorBuilder: (_, __, ___) => const Icon(Icons.folder, size: 16, color: Colors.amber)),
              const SizedBox(width: 8), 
              Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: textColor), overflow: TextOverflow.ellipsis))
            ]
          )
        )
      ),
    );
  }

  Widget _buildSidebarItem(String label, IconData icon, Color color, VoidCallback? onTap) {
    final textColor = widget.isDark ? Colors.white70 : Colors.grey.shade700;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap, 
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
          child: Row(children: [const SizedBox(width: 16), Icon(icon, color: color, size: 16), const SizedBox(width: 8), Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: textColor), overflow: TextOverflow.ellipsis))])
        )
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final bgColor = widget.isDark ? const Color(0xFF202020) : Colors.white;
    final borderColor = widget.isDark ? Colors.white12 : Colors.grey.shade200;
    final accent = state.currentAccentColor;

    return Container(
      width: widget.width,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: borderColor)), color: bgColor),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4), physics: const BouncingScrollPhysics(),
        children: [
          _buildSidebarHeader(Icons.star, 'Quick access', Colors.orange.shade400, false, null, _isQuickAccessExpanded, () => setState(() => _isQuickAccessExpanded = !_isQuickAccessExpanded)),
          if (_isQuickAccessExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Column(
                children: state.pinnedQuickAccess.map((name) {
                  return _buildSidebarItem(name, Icons.push_pin, widget.isDark ? Colors.white54 : Colors.grey.shade600, () {});
                }).toList(),
              ),
            ),
          _buildSidebarHeader(Icons.folder, 'This PC', accent, widget.isAtHome, widget.onGoHome, _isThisPCExpanded, () => setState(() => _isThisPCExpanded = !_isThisPCExpanded)),
          if (_isThisPCExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Column(
                children: [
                  _buildSidebarAssetItem('Desktop', 'desktop', () => widget.onNavigate(widget.rootPath)),
                  _buildSidebarAssetItem('Documents', 'documents', () => widget.onNavigate('${widget.rootPath}/Documents')),
                  _buildSidebarAssetItem('Downloads', 'downloads', () => widget.onNavigate('${widget.rootPath}/Download')),
                  _buildSidebarAssetItem('Music', 'music', () => widget.onNavigate('${widget.rootPath}/Music')),
                  _buildSidebarAssetItem('Pictures', 'pictures', () => widget.onNavigate('${widget.rootPath}/Pictures')),
                  _buildSidebarAssetItem('Videos', 'videos', () => widget.onNavigate('${widget.rootPath}/Movies')),
                  Material(
                    color: Colors.transparent, 
                    child: InkWell(
                      onTap: () => widget.onNavigate(widget.rootPath), 
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
                        child: Row(children: [const SizedBox(width: 16), Image.asset('assets/icons/drive.png', width: 16, height: 16, errorBuilder: (_, __, ___) => const Icon(Icons.storage, size: 16, color: Colors.grey)), const SizedBox(width: 8), Expanded(child: Text('Local Disk (C:)', style: TextStyle(fontSize: 12, color: widget.isDark ? Colors.white70 : Colors.grey.shade700), overflow: TextOverflow.ellipsis))])
                      )
                    )
                  )
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ExplorerStatusBar extends StatelessWidget {
  final bool isDark;
  final bool isAtHome;
  final int itemCount;
  final int selectedCount;
  final double sidebarWidthPercent;
  final bool isGridView;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<bool> onViewChanged;

  const ExplorerStatusBar({
    Key? key, required this.isDark, required this.isAtHome, required this.itemCount, required this.selectedCount, 
    required this.sidebarWidthPercent, required this.isGridView, required this.onWidthChanged, required this.onViewChanged,
  }) : super(key: key);

  void _showWidthAdjustmentDialog(BuildContext context, Color accent) {
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;
    double tempWidth = sidebarWidthPercent;

    showDialog(
      context: context, barrierColor: Colors.transparent, 
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Stack(
              children: [
                Positioned(
                  bottom: 60, right: 10,
                  child: Material(
                    elevation: 8, borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 250, padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: borderColor)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [Text('Select Quick Access width', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor)), InkWell(onTap: () => Navigator.pop(context), child: Icon(Icons.close, size: 16, color: textColor))],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.orange, size: 24),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(trackHeight: 4.0, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0)),
                                  child: Slider(
                                    value: tempWidth, min: 15, max: 50, activeColor: accent, inactiveColor: accent.withOpacity(0.2),
                                    onChanged: (val) { setDialogState(() => tempWidth = val); onWidthChanged(val); }
                                  ),
                                ),
                              ),
                              Text('${tempWidth.toInt()} %', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textColor)),
                            ]
                          )
                        ]
                      )
                    )
                  )
                )
              ]
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final accent = state.currentAccentColor;
    final bgColor = isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3);
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final textColor = isDark ? Colors.white70 : Colors.grey.shade700;

    return Container(
      height: 28, padding: const EdgeInsets.symmetric(horizontal: 12), 
      decoration: BoxDecoration(color: bgColor, border: Border(top: BorderSide(color: borderColor, width: 0.8))),
      child: Row(
        children: [
          if (isAtHome) ...[
            Text('7 items', style: TextStyle(fontSize: 11, color: textColor)),
          ] else ...[
            Text('$itemCount items  |  ${selectedCount > 0 ? '$selectedCount items selected  |' : ''}', style: TextStyle(fontSize: 11, color: textColor)), 
            const Spacer(), 
            InkWell(onTap: () => _showWidthAdjustmentDialog(context, accent), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: Text('${sidebarWidthPercent.toInt()} %', style: TextStyle(fontSize: 11, color: textColor)))),
            const SizedBox(width: 8), 
            InkWell(onTap: () => onViewChanged(false), child: Padding(padding: const EdgeInsets.all(4.0), child: Icon(Icons.format_list_bulleted, size: 14, color: !isGridView ? accent : textColor))), 
            const SizedBox(width: 6), 
            InkWell(onTap: () => onViewChanged(true), child: Padding(padding: const EdgeInsets.all(4.0), child: Icon(Icons.grid_view_sharp, size: 14, color: isGridView ? accent : textColor)))
          ]
        ]
      ),
    );
  }
}

class SafeInputDialog extends StatefulWidget {
  final String title;
  final String initialText;
  final String hintText;
  final String actionText;
  final bool isDark;

  const SafeInputDialog({Key? key, required this.title, required this.initialText, required this.hintText, required this.actionText, required this.isDark}) : super(key: key);

  @override
  State<SafeInputDialog> createState() => _SafeInputDialogState();
}

class _SafeInputDialogState extends State<SafeInputDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final accent = state.currentAccentColor;
    final bgColor = widget.isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = widget.isDark ? Colors.white : Colors.black87;

    return AlertDialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Text(widget.title, style: TextStyle(fontSize: 15, color: textColor)),
      content: TextField(
        controller: _controller,
        style: TextStyle(color: textColor, fontSize: 13),
        decoration: InputDecoration(
          hintText: widget.hintText, hintStyle: TextStyle(color: widget.isDark ? Colors.white54 : Colors.black54),
          isDense: true, enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: widget.isDark ? Colors.white38 : Colors.black38)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accent)),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black87))),
        TextButton(onPressed: () => Navigator.pop(context, _controller.text), child: Text(widget.actionText, style: TextStyle(color: accent))),
      ],
    );
  }
}