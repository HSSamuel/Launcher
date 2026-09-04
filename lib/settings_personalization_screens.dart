import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:app_settings/app_settings.dart';

import 'launcher_state.dart';
import 'settings_widgets.dart';

// --- 1. Themes Screen ---
class ThemesScreen extends StatelessWidget {
  const ThemesScreen({Key? key}) : super(key: key);

  void _showThemePicker(BuildContext context, LauncherState state) {
    // FIX: Removed hardcoded white colors so the dialog correctly applies Dark Mode
    final isDark = state.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text('Select Theme', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.light_mode, color: Colors.orange),
              title: Text('Light theme', style: TextStyle(color: textColor, fontSize: 14)),
              trailing: !state.isDarkMode && !state.currentThemeName.contains('Windows') ? const Icon(Icons.check, color: Colors.blueAccent) : null,
              onTap: () { state.setDarkMode(false); Navigator.pop(ctx); },
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode, color: Colors.indigo),
              title: Text('Dark theme', style: TextStyle(color: textColor, fontSize: 14)),
              trailing: state.isDarkMode && !state.currentThemeName.contains('Windows') ? const Icon(Icons.check, color: Colors.blueAccent) : null,
              onTap: () { state.setDarkMode(true); Navigator.pop(ctx); },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_suggest, color: Colors.teal),
              title: Text('Sync with Android OS', style: TextStyle(color: textColor, fontSize: 14)),
              subtitle: Text('Open Display Settings', style: TextStyle(color: subTextColor, fontSize: 11)),
              onTap: () { Navigator.pop(ctx); AppSettings.openAppSettings(type: AppSettingsType.display); },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Personalization > Themes'),
      body: ListView(
        padding: const EdgeInsets.all(12), physics: const BouncingScrollPhysics(),
        children: [
          SettingsCard(
            title: 'Current theme', subtitle: 'Select launcher theme', icon: Icons.phone_android,
            trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)), child: Text(state.currentThemeName, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600))),
            onTap: () => _showThemePicker(context, state),
          ),
          SettingsCard(title: 'Browse themes', subtitle: 'Themes repository', icon: Icons.art_track, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BrowseThemesScreen()))),
        ],
      ),
    );
  }
}

// --- 1.1 Browse Themes Screen ---
class BrowseThemesScreen extends StatelessWidget {
  const BrowseThemesScreen({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    final cardBg = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Themes > Browse Themes'),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: GridView.builder(
          physics: const BouncingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85),
          itemCount: state.win11Themes.length,
          itemBuilder: (context, index) {
            final theme = state.win11Themes[index];
            final isSelected = state.currentThemeName == theme.name;
            return InkWell(
              onTap: () {
                state.applyPresetTheme(theme);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied ${theme.name} theme!'), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: isSelected ? Colors.blueAccent : borderColor, width: isSelected ? 2.5 : 0.8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)), 
                        child: Image.asset(
                          theme.wallpaperUrl, 
                          fit: BoxFit.cover, 
                          width: double.infinity, 
                          errorBuilder: (_, __, ___) => Container(color: isDark ? Colors.black54 : Colors.grey.shade200)
                        )
                      )
                    ),
                    Padding(padding: const EdgeInsets.all(10.0), child: Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: theme.accentColor, shape: BoxShape.circle)), const SizedBox(width: 8), Expanded(child: Text(theme.name, style: TextStyle(color: textColor, fontSize: 11.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600), overflow: TextOverflow.ellipsis))])),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// --- 2. Background Screen ---
class BackgroundScreen extends StatelessWidget {
  const BackgroundScreen({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Personalization > Background'),
      body: ListView(
        padding: const EdgeInsets.all(12), physics: const BouncingScrollPhysics(),
        children: [
          SettingsCard(
            title: 'Personalize your background', subtitle: 'Pick an image from your gallery', icon: Icons.image_outlined, trailing: const SizedBox.shrink(),
            onTap: () async {
              final picker = ImagePicker();
              final XFile? image = await picker.pickImage(source: ImageSource.gallery);
              if (image != null) {
                state.changeWallpaper(image.path);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Custom wallpaper applied!'), behavior: SnackBarBehavior.floating));
              }
            },
          ),
          SettingsCard(
            title: 'Choose default folder for background', subtitle: state.slideshowFolderPath ?? 'Select a device folder for wallpaper slideshow', icon: Icons.snippet_folder_outlined, trailing: const SizedBox.shrink(),
            onTap: () async {
              String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
              if (selectedDirectory != null) {
                state.setSlideshowFolder(selectedDirectory);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Slideshow folder set to: $selectedDirectory'), behavior: SnackBarBehavior.floating));
              }
            },
          ),
        ],
      ),
    );
  }
}

// --- 3. Start Settings Screen ---
class StartSettingsScreen extends StatelessWidget {
  const StartSettingsScreen({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Personalization > Start'),
      body: ListView(
        padding: const EdgeInsets.all(12), physics: const BouncingScrollPhysics(),
        children: [
          SettingsCard(title: 'Show recently added apps', icon: Icons.access_time, trailing: Switch(value: state.showRecentlyAdded, activeColor: Colors.blueAccent, onChanged: (val) => state.setStartMenuOptions(recentlyAdded: val))),
          SettingsCard(title: 'Show most used apps', icon: Icons.star_border, trailing: Switch(value: state.showMostUsed, activeColor: Colors.blueAccent, onChanged: (val) => state.setStartMenuOptions(mostUsed: val))),
          SettingsCard(title: 'Show recommended files & apps', icon: Icons.recommend, trailing: Switch(value: state.showRecommended, activeColor: Colors.blueAccent, onChanged: (val) => state.setStartMenuOptions(recommended: val))),
          SettingsCard(title: 'Folders', subtitle: 'Choose which folders appear on Start next to the power button', icon: Icons.folder_open, onTap: () {}),
        ],
      ),
    );
  }
}

// --- 4. Search Screen ---
class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}
class _SearchScreenState extends State<SearchScreen> {
  bool isCategoriesExpanded = false; 

  Widget _buildInnerSwitch(String label, bool value, Function(bool) onChanged, bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), 
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, 
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)), 
          Switch(value: value, activeColor: Colors.blueAccent, onChanged: onChanged)
        ]
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white54 : Colors.black54;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Personalization > Search'),
      body: ListView(
        padding: const EdgeInsets.all(12), physics: const BouncingScrollPhysics(),
        children: [
          // FIX: Fully linked to persistent state
          SettingsCard(title: 'Show top apps', icon: Icons.vertical_align_bottom, trailing: Switch(value: state.searchShowTopApps, activeColor: Colors.blueAccent, onChanged: (val) => state.updateSearchSetting('showTopApps', val))),
          SettingsCard(title: 'Default page', subtitle: 'Select the first page to be displayed', icon: Icons.home_outlined, trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)), child: Text('Default', style: TextStyle(color: textColor, fontSize: 12)))),
          SettingsCard(title: 'Max result count', subtitle: 'Select numbers of results to be shown', icon: Icons.list_alt, trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)), child: Text('5', style: TextStyle(color: textColor, fontSize: 12)))),
          ExpandableSettingsCard(
            title: 'Included categories', subtitle: 'Select categories to include results while\nsearching.', isExpanded: isCategoriesExpanded, onToggle: () => setState(() => isCategoriesExpanded = !isCategoriesExpanded),
            children: Column(
              children: [
                Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12), const SizedBox(height: 8), 
                _buildInnerSwitch('Apps', state.searchCatApps, (v) => state.updateSearchSetting('catApps', v), isDark), 
                _buildInnerSwitch('Documents', state.searchCatDocs, (v) => state.updateSearchSetting('catDocs', v), isDark), 
                _buildInnerSwitch('Photos', state.searchCatPhotos, (v) => state.updateSearchSetting('catPhotos', v), isDark), 
                _buildInnerSwitch('Audios', state.searchCatAudio, (v) => state.updateSearchSetting('catAudio', v), isDark), 
                _buildInnerSwitch('Videos', state.searchCatVideos, (v) => state.updateSearchSetting('catVideos', v), isDark), 
                _buildInnerSwitch('Settings', state.searchCatSettings, (v) => state.updateSearchSetting('catSettings', v), isDark)
              ]
            ),
          )
        ],
      ),
    );
  }
}

// --- 5. Taskbar Screen ---
class TaskbarScreen extends StatefulWidget {
  const TaskbarScreen({Key? key}) : super(key: key);
  @override
  State<TaskbarScreen> createState() => _TaskbarScreenState();
}
class _TaskbarScreenState extends State<TaskbarScreen> {
  bool isItemsExpanded = false; bool isOverflowExpanded = false; 

  Widget _buildInnerSwitch(String label, bool value, Function(bool) onChanged, bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), 
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, 
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)), 
          Switch(value: value, activeColor: Colors.blueAccent, onChanged: onChanged)
        ]
      )
    );
  }

  void _showAlignmentDialog(BuildContext context, LauncherState state) {
    final isDark = state.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor, 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), 
        title: Text('Taskbar Alignment', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)), 
        content: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            ListTile(leading: const Icon(Icons.align_horizontal_left, color: Colors.blueAccent), title: Text('Left', style: TextStyle(color: textColor, fontSize: 14)), trailing: state.taskbarAlignment == 'left' ? const Icon(Icons.check, color: Colors.blueAccent) : null, onTap: () { state.setTaskbarAlignment('left'); Navigator.pop(ctx); }), 
            ListTile(leading: const Icon(Icons.align_horizontal_center, color: Colors.blueAccent), title: Text('Center', style: TextStyle(color: textColor, fontSize: 14)), trailing: state.taskbarAlignment == 'center' ? const Icon(Icons.check, color: Colors.blueAccent) : null, onTap: () { state.setTaskbarAlignment('center'); Navigator.pop(ctx); })
          ]
        )
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Personalization > Taskbar'),
      body: ListView(
        padding: const EdgeInsets.all(12), physics: const BouncingScrollPhysics(),
        children: [
          // FIX: Fully linked to persistent state
          ExpandableSettingsCard(
            title: 'Taskbar items', subtitle: 'Select items to show', isExpanded: isItemsExpanded, onToggle: () => setState(() => isItemsExpanded = !isItemsExpanded),
            children: Column(children: [Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12), const SizedBox(height: 8), _buildInnerSwitch('Search', state.taskbarItemSearch, (v) => state.updateTaskbarSetting('itemSearch', v), isDark), _buildInnerSwitch('Task view', state.taskbarItemTaskView, (v) => state.updateTaskbarSetting('itemTaskView', v), isDark), _buildInnerSwitch('Widget', state.taskbarItemWidget, (v) => state.updateTaskbarSetting('itemWidget', v), isDark)]),
          ),
          ExpandableSettingsCard(
            title: 'Taskbar corner overflow', subtitle: 'Select items to show', isExpanded: isOverflowExpanded, onToggle: () => setState(() => isOverflowExpanded = !isOverflowExpanded),
            children: Column(children: [Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12), const SizedBox(height: 8), _buildInnerSwitch('Internet', state.taskbarOverInternet, (v) => state.updateTaskbarSetting('overInternet', v), isDark), _buildInnerSwitch('Sound', state.taskbarOverSound, (v) => state.updateTaskbarSetting('overSound', v), isDark), _buildInnerSwitch('Battery', state.taskbarOverBattery, (v) => state.updateTaskbarSetting('overBattery', v), isDark), _buildInnerSwitch('Date & time', state.taskbarOverDate, (v) => state.updateTaskbarSetting('overDate', v), isDark)]),
          ),
          SettingsCard(title: 'Taskbar alignment', subtitle: 'Select the position of the taskbar to be\nshown', icon: Icons.border_bottom, trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)), child: Text(state.taskbarAlignment == 'center' ? 'Center' : 'Left', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600))), onTap: () => _showAlignmentDialog(context, state)),
          SettingsCard(title: 'Hide network icons when taskbar is center in\nmobile devices', icon: Icons.block, trailing: Switch(value: state.hideNetworkIcons, activeColor: Colors.blueAccent, onChanged: (val) => state.updateTaskbarSetting('hideNetworkIcons', val))),
        ],
      ),
    );
  }
}

// --- 6. Desktop Settings Screen ---
class DesktopSettingsScreen extends StatelessWidget {
  const DesktopSettingsScreen({Key? key}) : super(key: key);

  void _showIconSizeDialog(BuildContext context, LauncherState state) {
    final isDark = state.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor, 
        title: Text('Icon Size', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)), 
        content: Column(
          mainAxisSize: MainAxisSize.min, 
          children: ['Small', 'Medium', 'Large'].map((size) => RadioListTile<String>(title: Text(size, style: TextStyle(color: textColor)), value: size, groupValue: state.iconSize, activeColor: Colors.blueAccent, onChanged: (val) { state.updateDesktopSetting('iconSize', val!); Navigator.pop(ctx); })).toList()
        )
      )
    );
  }

  void _showGridDialog(BuildContext context, LauncherState state, bool isPortrait) {
    final isDark = state.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    // FIX: Safely clamp to prevent the Flutter DropdownButton assertion crash
    int currentX = (isPortrait ? state.portraitGridX : state.landscapeGridX).clamp(3, 12);
    int currentY = (isPortrait ? state.portraitGridY : state.landscapeGridY).clamp(3, 12);
    
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: bgColor,
            title: Text('${isPortrait ? "Portrait" : "Landscape"} Grid', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Columns (X):', style: TextStyle(color: textColor)), DropdownButton<int>(value: currentX, dropdownColor: bgColor, style: TextStyle(color: textColor), items: List.generate(10, (i) => DropdownMenuItem(value: i + 3, child: Text('${i + 3}'))), onChanged: (val) => setDialogState(() => currentX = val!))]),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Rows (Y):', style: TextStyle(color: textColor)), DropdownButton<int>(value: currentY, dropdownColor: bgColor, style: TextStyle(color: textColor), items: List.generate(10, (i) => DropdownMenuItem(value: i + 3, child: Text('${i + 3}'))), onChanged: (val) => setDialogState(() => currentY = val!))]),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
              TextButton(onPressed: () {
                state.updateDesktopSetting(isPortrait ? 'portraitGridX' : 'landscapeGridX', currentX);
                state.updateDesktopSetting(isPortrait ? 'portraitGridY' : 'landscapeGridY', currentY);
                Navigator.pop(ctx);
              }, child: const Text('Save', style: TextStyle(color: Colors.blueAccent))),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Personalization > Desktop'),
      body: ListView(
        padding: const EdgeInsets.all(12), physics: const BouncingScrollPhysics(),
        children: [
          SettingsCard(title: 'Icon size', subtitle: 'Select desktop icon size', icon: Icons.photo_size_select_small, trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)), child: Text(state.iconSize, style: TextStyle(color: textColor, fontSize: 12))), onTap: () => _showIconSizeDialog(context, state)),
          SettingsCard(title: 'Portrait Grid count', subtitle: '${state.portraitGridX} x ${state.portraitGridY}', icon: Icons.grid_on, trailing: const SizedBox.shrink(), onTap: () => _showGridDialog(context, state, true)),
          SettingsCard(title: 'Landscape Grid count', subtitle: '${state.landscapeGridX} x ${state.landscapeGridY}', icon: Icons.grid_on, trailing: const SizedBox.shrink(), onTap: () => _showGridDialog(context, state, false)),
          SettingsCard(title: 'Double tap to sleep', subtitle: 'Tap the empty desktop wallpaper to instantly return to\nthe Lock Screen.', icon: Icons.touch_app, trailing: Switch(value: state.doubleTapToSleep, activeColor: Colors.blueAccent, onChanged: (val) => state.updateDesktopSetting('doubleTapToSleep', val))),
          SettingsCard(title: 'Drag icons', icon: Icons.pan_tool_outlined, trailing: Switch(value: state.dragIcons, activeColor: Colors.blueAccent, onChanged: (val) => state.updateDesktopSetting('dragIcons', val))),
          SettingsCard(title: 'Hide Status Bar', icon: Icons.open_in_full, trailing: Switch(value: state.hideStatusBar, activeColor: Colors.blueAccent, onChanged: (val) => state.updateDesktopSetting('hideStatusBar', val))),
          SettingsCard(title: 'Hide Navigation Bar', icon: Icons.open_in_full_outlined, trailing: Switch(value: state.hideNavBar, activeColor: Colors.blueAccent, onChanged: (val) => state.updateDesktopSetting('hideNavBar', val))),
          SettingsCard(title: 'Create shortcut for new apps', icon: Icons.layers_outlined, trailing: Switch(value: state.createShortcut, activeColor: Colors.blueAccent, onChanged: (val) => state.updateDesktopSetting('createShortcut', val))),
          SettingsCard(title: 'Notch type [*Experimental]', subtitle: 'Select your device notch type', icon: Icons.smartphone, trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)), child: Text('Default', style: TextStyle(color: textColor, fontSize: 12)))),
        ],
      ),
    );
  }
}

// --- 7. File Manager Screen ---
class FileManagerScreen extends StatelessWidget {
  const FileManagerScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Personalization > File manager'),
      body: ListView(
        padding: const EdgeInsets.all(12), 
        physics: const BouncingScrollPhysics(),
        children: [
          SettingsCard(
            title: 'Show hidden files', 
            icon: Icons.visibility_off_outlined, 
            trailing: Switch(
              value: state.showHiddenFiles, 
              activeColor: Colors.blueAccent, 
              onChanged: (val) => state.updateDesktopSetting('showHiddenFiles', val)
            ),
          ),
          SettingsCard(
            title: 'Preview files', 
            icon: Icons.preview_outlined, 
            trailing: Switch(
              value: state.previewFiles, 
              activeColor: Colors.blueAccent, 
              onChanged: (val) => state.updateDesktopSetting('previewFiles', val)
            ),
          ),
          SettingsCard(
            title: 'Mouse click sound', 
            icon: Icons.mouse_outlined, 
            trailing: Switch(
              value: state.mouseSound, 
              activeColor: Colors.blueAccent, 
              onChanged: (val) => state.updateDesktopSetting('mouseSound', val)
            ),
          ),
        ],
      ),
    );
  }
}