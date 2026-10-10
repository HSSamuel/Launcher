import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../states/theme_state.dart';
import '../../states/desktop_state.dart';
import '../../states/system_state.dart';
import '../../states/monetization_state.dart';
import '../../services/native_bridge.dart';
import '../../services/pro_gatekeeper.dart';
import 'settings_widgets.dart';

class Win11SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool isDark;

  const Win11SettingsGroup({
    Key? key, required this.title, required this.children, required this.isDark
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 12, bottom: 4),
          child: Text(
            title, 
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white70 : Colors.black87)
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2B2B2B) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300, width: 0.8),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: Column(
            children: children.asMap().entries.map((entry) {
              final index = entry.key;
              final child = entry.value;
              final isLast = index == children.length - 1;
              return Column(
                children: [
                  child,
                  if (!isLast) Divider(height: 1, indent: 46, endIndent: 8, color: isDark ? Colors.white10 : Colors.grey.shade200),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class Win11SettingsTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool isDark;
  final bool isProLocked;

  const Win11SettingsTile({
    Key? key, 
    required this.title, 
    this.subtitle, 
    required this.icon, 
    required this.trailing, 
    this.onTap, 
    required this.isDark,
    this.isProLocked = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final systemState = context.watch<SystemState>();
    final monetization = context.watch<MonetizationState>();
    final bool isPro = systemState.isActivated || monetization.isPro;
    final bool showPadlock = isProLocked && !isPro;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: isDark ? Colors.white70 : Colors.black54),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            title, 
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (showPadlock) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.lock_outline, size: 14, color: Colors.amber),
                        ]
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(subtitle!, style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade600), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ]
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.45),
                child: trailing,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ThemesScreen extends StatelessWidget {
  const ThemesScreen({Key? key}) : super(key: key);

  void _showThemePicker(BuildContext context, ThemeState themeState) {
    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;
    final accent = themeState.currentAccentColor;

    final isPro = context.read<SystemState>().isActivated || 
                  context.read<MonetizationState>().isPro;

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
              trailing: (!themeState.isDarkMode && !themeState.syncWithSystemTheme) ? Icon(Icons.check, color: accent) : null,
              onTap: () { 
                themeState.setDarkMode(false, syncWithSystem: false); 
                Navigator.pop(ctx); 
              },
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode, color: Colors.indigo),
              title: Text('Dark theme', style: TextStyle(color: textColor, fontSize: 14)),
              trailing: (themeState.isDarkMode && !themeState.syncWithSystemTheme) ? Icon(Icons.check, color: accent) : null,
              onTap: () { 
                if (!isPro) {
                  Navigator.pop(ctx);
                  ProGatekeeper.checkAccess(context, featureName: 'Dark Theme');
                  return;
                }
                Navigator.pop(ctx);
                themeState.setDarkMode(true, syncWithSystem: false); 
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_suggest, color: Colors.teal),
              title: Text('Sync with Android OS', style: TextStyle(color: textColor, fontSize: 14)),
              subtitle: Text('Follow device settings', style: TextStyle(color: subTextColor, fontSize: 11)),
              trailing: themeState.syncWithSystemTheme ? Icon(Icons.check, color: accent) : null,
              onTap: () { 
                bool sysDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
                if (sysDark && !isPro) {
                  Navigator.pop(ctx);
                  ProGatekeeper.checkAccess(context, featureName: 'Dark Theme (via OS Sync)');
                  return;
                }
                Navigator.pop(ctx);
                themeState.setDarkMode(sysDark, syncWithSystem: true); 
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showColorPicker(BuildContext context, ThemeState initialThemeState) {
    final isDark = initialThemeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    final List<Color> customColors = [
      Colors.black, Colors.white, Colors.grey.shade700, Colors.blueGrey, Colors.brown,
      Colors.red, Colors.deepOrange, Colors.orange, Colors.amber, Colors.yellow.shade700,
      Colors.lime, Colors.lightGreen, Colors.green, Colors.teal, Colors.cyan,
      Colors.lightBlue, Colors.blue, Colors.indigo, Colors.deepPurple, Colors.purple,
      Colors.pink, const Color(0xFFE57373), const Color(0xFF4DB6AC), const Color(0xFF7986CB),
    ];

    bool isClosing = false;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text('Pick Accent Color', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 220),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6, crossAxisSpacing: 12, mainAxisSpacing: 12,
            ),
            itemCount: customColors.length,
            itemBuilder: (context, index) {
              final color = customColors[index];
              return Consumer<ThemeState>(
                builder: (context, themeState, _) {
                  final isSelected = themeState.customAccentColor?.value == color.value;
                  final checkColor = color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
                  final defaultBorder = isDark ? Colors.white30 : Colors.black26;

                  return InkWell(
                    onTap: () {
                      if (isClosing) return;
                      isClosing = true;
                      themeState.setManualAccentColor(color);
                      Future.delayed(const Duration(milliseconds: 150), () {
                        if (ctx.mounted) Navigator.pop(ctx);
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? (isDark ? Colors.white : Colors.black87) : defaultBorder, 
                          width: isSelected ? 2.5 : 1.0
                        ),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: isSelected ? Icon(Icons.check, color: checkColor, size: 16) : null,
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              initialThemeState.clearManualAccentColor();
              Navigator.pop(ctx);
            },
            child: Text('Reset to Default', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Personalization > Themes'),
      body: ListView(
        padding: const EdgeInsets.all(16), physics: const BouncingScrollPhysics(),
        children: [
          Win11SettingsGroup(
            title: 'Theme Management',
            isDark: isDark,
            children: [
              Win11SettingsTile(
                title: 'Current theme', subtitle: 'Select launcher theme', icon: Icons.phone_android, isDark: isDark,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), 
                  decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)), 
                  child: Text(themeState.currentThemeName, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)
                ),
                onTap: () => _showThemePicker(context, themeState),
              ),
              Win11SettingsTile(
                title: 'Material You (Dynamic Color)', 
                isProLocked: true,
                subtitle: themeState.syncAccentWithOS 
                    ? 'Active: Synchronized with Wallpaper palette' 
                    : 'Sync launcher accents with device wallpaper', 
                icon: Icons.format_paint_outlined, 
                isDark: isDark,
                trailing: Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: themeState.syncAccentWithOS,
                    activeColor: themeState.currentAccentColor,
                    onChanged: (val) {
                      if (val && !ProGatekeeper.checkAccess(context, featureName: 'Material You (Dynamic Color)')) return;
                      themeState.setSyncAccentWithOS(val);
                    },
                  ),
                ),
              ),
              if (!themeState.syncAccentWithOS)
                Win11SettingsTile(
                  title: 'Custom accent color', 
                  subtitle: 'Pick a specific color to match your background', 
                  icon: Icons.palette_outlined, 
                  isDark: isDark,
                  trailing: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: themeState.currentAccentColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: borderColor)
                    ),
                  ),
                  onTap: () => _showColorPicker(context, themeState),
                ),
              Win11SettingsTile(
                title: 'Transparency effects',
                subtitle: themeState.transparencyEffects
                    ? (themeState.isLegacyDevice 
                        ? 'Optimized blur active for older hardware' 
                        : 'Windows 11 acrylic blur active')
                    : 'Opaque backgrounds (maximum performance)',
                icon: Icons.opacity,
                isDark: isDark,
                trailing: Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: themeState.transparencyEffects,
                    activeColor: themeState.currentAccentColor,
                    onChanged: (val) => themeState.setTransparencyEffects(val),
                  ),
                ),
              ),
              Win11SettingsTile(
                title: 'Browse themes', subtitle: 'Curated Windows themes with matching colors', icon: Icons.art_track, isDark: isDark,
                trailing: Icon(Icons.chevron_right, size: 20, color: textColor),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BrowseThemesScreen()))
              ),
              Win11SettingsTile(
                title: 'Icon Packs', subtitle: 'Manage custom third-party icon packs', icon: Icons.style, isDark: isDark,
                trailing: Icon(Icons.chevron_right, size: 20, color: textColor),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IconPackScreen()))
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class BrowseThemesScreen extends StatelessWidget {
  const BrowseThemesScreen({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final cardBg = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Themes > Browse Themes'),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          physics: const BouncingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.85
          ),
          itemCount: themeState.win11Themes.length,
          itemBuilder: (context, index) {
            final theme = themeState.win11Themes[index];
            final isSelected = themeState.currentThemeName == theme.name;
            return InkWell(
              onTap: () {
                if (theme.isDark && !ProGatekeeper.checkAccess(context, featureName: 'Dark Theme')) return;

                themeState.applyPresetTheme(theme);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied ${theme.name} theme!'), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  color: cardBg, 
                  borderRadius: BorderRadius.circular(10), 
                  border: Border.all(color: isSelected ? theme.accentColor : borderColor, width: isSelected ? 2.5 : 0.8), 
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)), 
                        child: Image.asset(
                          theme.wallpaperUrl, fit: BoxFit.cover, width: double.infinity, 
                          cacheWidth: 400, errorBuilder: (_, __, ___) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [theme.accentColor, theme.isDark ? Colors.black87 : Colors.white], begin: Alignment.topLeft, end: Alignment.bottomRight))),
                        )
                      )
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10.0), 
                      child: Row(
                        children: [
                          Container(width: 14, height: 14, decoration: BoxDecoration(color: theme.accentColor, shape: BoxShape.circle)), 
                          const SizedBox(width: 8), 
                          Expanded(child: Text(theme.name, style: TextStyle(color: textColor, fontSize: 11.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600), overflow: TextOverflow.ellipsis))
                        ]
                      )
                    ),
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

class IconPackScreen extends StatefulWidget {
  const IconPackScreen({Key? key}) : super(key: key);

  @override
  State<IconPackScreen> createState() => _IconPackScreenState();
}

class _IconPackScreenState extends State<IconPackScreen> {
  List<Map<String, String>> _availablePacks = [];
  bool _isLoadingPacks = true;

  @override
  void initState() {
    super.initState();
    _fetchPacks();
  }

  Future<void> _fetchPacks() async {
    final packs = await NativeBridge.instance.getAvailableIconPacks();
    if (mounted) setState(() { _availablePacks = packs; _isLoadingPacks = false; });
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Themes > Icon Packs'),
      body: themeState.isProcessingIconPack 
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Colors.blueAccent),
                const SizedBox(height: 24),
                Text('Mapping custom icons to your apps...\nThis may take a moment.', textAlign: TextAlign.center, style: TextStyle(color: textColor, fontSize: 13, height: 1.5))
              ],
            )
          )
        : ListView(
            padding: const EdgeInsets.all(16), physics: const BouncingScrollPhysics(),
            children: [
              Win11SettingsGroup(
                title: 'Installed Icon Packs',
                isDark: isDark,
                children: [
                  Win11SettingsTile(
                    title: 'Default System Icons',
                    icon: Icons.android,
                    isDark: isDark,
                    trailing: themeState.currentIconPackPackage == null ? Icon(Icons.check, color: themeState.currentAccentColor) : const SizedBox.shrink(),
                    onTap: () async { 
                      await themeState.setIconPack(null); 
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restored Default Icons'))); 
                      }
                    },
                  ),
                  if (_isLoadingPacks)
                    const Padding(padding: EdgeInsets.all(16.0), child: Center(child: CircularProgressIndicator()))
                  else if (_availablePacks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16.0), 
                      child: Text('No compatible Icon Packs found. Install any Nova Launcher compatible pack from the Play Store.', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12))
                    )
                  else
                    ..._availablePacks.map((pack) {
                      final isSelected = themeState.currentIconPackPackage == pack['package'];
                      return Win11SettingsTile(
                        title: pack['name']!,
                        subtitle: pack['package']!,
                        icon: Icons.style,
                        isDark: isDark,
                        trailing: isSelected ? Icon(Icons.check, color: themeState.currentAccentColor) : const SizedBox.shrink(),
                        onTap: () async { 
                          if (!ProGatekeeper.checkAccess(context, featureName: 'Custom Icon Packs')) return;
                          
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applying ${pack['name']}...'))); 
                          await themeState.setIconPack(pack['package']); 
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${pack['name']} Successfully Applied!')));
                          }
                        },
                      );
                    }).toList(),
                ],
              )
            ],
          ),
    );
  }
}

class BackgroundScreen extends StatelessWidget {
  const BackgroundScreen({Key? key}) : super(key: key);

  void _showIntervalDialog(BuildContext context, ThemeState themeState) {
    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accent = themeState.currentAccentColor;

    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor, 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text('Slideshow Interval', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)), 
        content: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [1, 5, 15, 30, 60].map((mins) => RadioListTile<int>(
            title: Text(mins == 60 ? '1 hour' : '$mins minutes', style: TextStyle(color: textColor, fontSize: 14)), 
            value: mins, 
            groupValue: themeState.slideshowIntervalMinutes, 
            activeColor: accent, 
            onChanged: (val) { 
              themeState.updateSlideshowSettings(interval: val!); 
              Navigator.pop(ctx); 
            }
          )).toList()
        )
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Personalization > Background'),
      body: ListView(
        padding: const EdgeInsets.all(16), physics: const BouncingScrollPhysics(),
        children: [
          Win11SettingsGroup(
            title: 'Personalize your background',
            isDark: isDark,
            children: [
              Win11SettingsTile(
                title: 'Custom Wallpaper', subtitle: 'Pick a personal image from your gallery', icon: Icons.image_outlined, isDark: isDark,
                trailing: Icon(Icons.photo_library, size: 20, color: textColor),
                onTap: () async {
                  final picker = ImagePicker();
                  final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 2560, maxHeight: 1440);
                  if (image != null) {
                    final dir = await getApplicationDocumentsDirectory();
                    final File newWall = File('${dir.path}/custom_wall_${DateTime.now().millisecondsSinceEpoch}.jpg');
                    await File(image.path).copy(newWall.path);
                    themeState.changeWallpaper(newWall.path);
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Custom wallpaper applied! Slideshow paused.'), behavior: SnackBarBehavior.floating));
                  }
                },
              ),
              Win11SettingsTile(
                title: 'Windows Spotlight (Infinite)', 
                isProLocked: true,
                subtitle: 'Fetch an endless supply of stunning 4K web wallpapers', 
                icon: Icons.public, 
                isDark: isDark,
                trailing: Transform.scale(
                  scale: 0.85, 
                  child: Switch(
                    value: themeState.infiniteWebWallpapers, 
                    activeColor: themeState.currentAccentColor, 
                    onChanged: (val) {
                      if (val && !ProGatekeeper.checkAccess(context, featureName: 'Infinite Spotlight Wallpapers')) return;
                      themeState.setInfiniteWebWallpapers(val);
                    }
                  )
                ),
              ),
              Win11SettingsTile(
                title: 'Wallpaper Slideshow', 
                isProLocked: true,
                subtitle: 'Automatically cycle through your active theme set', 
                icon: Icons.slideshow, 
                isDark: isDark,
                trailing: Transform.scale(
                  scale: 0.85, 
                  child: Switch(
                    value: themeState.slideshowEnabled, 
                    activeColor: themeState.currentAccentColor, 
                    onChanged: (val) {
                      if (val && !ProGatekeeper.checkAccess(context, featureName: 'Wallpaper Slideshow')) {
                        return;
                      }
                      themeState.updateSlideshowSettings(enabled: val);
                    }
                  )
                ),
              ),
              if (themeState.slideshowEnabled)
                Win11SettingsTile(
                  title: 'Change picture every', subtitle: themeState.slideshowIntervalMinutes == 60 ? '1 hour' : '${themeState.slideshowIntervalMinutes} minutes', icon: Icons.timer_outlined, isDark: isDark,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), 
                    decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)), 
                    child: Text(themeState.slideshowIntervalMinutes == 60 ? '1 hour' : '${themeState.slideshowIntervalMinutes} min', style: TextStyle(color: textColor, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)
                  ),
                  onTap: () => _showIntervalDialog(context, themeState),
                ),
            ],
          )
        ],
      ),
    );
  }
}

class StartSettingsScreen extends StatelessWidget {
  const StartSettingsScreen({Key? key}) : super(key: key);

  void _showBootAnimationDialog(BuildContext context, ThemeState themeState) {
    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accent = themeState.currentAccentColor;
    final options = ['None', 'Windows 98 Retro', 'Windows XP Bliss', 'Windows 7 Aero'];

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: bgColor,
          title: Text('Boot Animation', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) => InkWell(
              onTap: () {
                themeState.setBootAnimation(opt);
                Navigator.pop(ctx);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(child: Text(opt, style: TextStyle(color: textColor, fontSize: 14))),
                    if (themeState.bootAnimation == opt) Icon(Icons.check, color: accent, size: 18),
                  ],
                ),
              ),
            )).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)))
          ]
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktopState = context.watch<DesktopState>();
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final accent = themeState.currentAccentColor;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Personalization > Start'),
      body: ListView(
        padding: const EdgeInsets.all(16), physics: const BouncingScrollPhysics(),
        children: [
          Win11SettingsGroup(
            title: 'Layout',
            isDark: isDark,
            children: [
              Win11SettingsTile(
                title: 'Show recently added apps', icon: Icons.access_time, isDark: isDark,
                trailing: Transform.scale(
                  scale: 0.85, 
                  child: Switch(value: desktopState.showRecentlyAdded, activeColor: accent, onChanged: (val) => desktopState.setStartMenuOptions(recentlyAdded: val))
                ),
              ),
            ],
          ),
          Win11SettingsGroup(
            title: 'Retro & Effects (Pro)',
            isDark: isDark,
            children: [
              Win11SettingsTile(
                title: 'System Sounds',
                subtitle: 'Play classic startup and system error chimes',
                icon: Icons.speaker_group_outlined,
                isDark: isDark,
                isProLocked: true,
                trailing: Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: themeState.enableSystemSounds,
                    activeColor: themeState.currentAccentColor,
                    onChanged: (val) {
                      if (val && !ProGatekeeper.checkAccess(context, featureName: 'Retro System Sounds')) return;
                      themeState.setSystemSounds(val);
                    },
                  ),
                ),
              ),
              Win11SettingsTile(
                title: 'Boot Animation',
                subtitle: themeState.bootAnimation == 'None' ? 'Disabled' : themeState.bootAnimation,
                icon: Icons.power_settings_new,
                isDark: isDark,
                isProLocked: true,
                trailing: Icon(Icons.chevron_right, size: 20, color: textColor),
                onTap: () {
                  if (!ProGatekeeper.checkAccess(context, featureName: 'Retro Boot Animations')) return;
                  _showBootAnimationDialog(context, themeState);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SearchScreen extends StatelessWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final desktopState = context.watch<DesktopState>();
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Personalization > Search'),
      body: ListView(
        padding: const EdgeInsets.all(16), 
        physics: const BouncingScrollPhysics(),
        children: [
          Win11SettingsGroup(
            title: 'Search Content',
            isDark: isDark,
            children: [
              Win11SettingsTile(
                title: 'Show News & Interests', 
                subtitle: 'Display live sports, global news, and tech updates in the search dashboard', 
                icon: Icons.article_outlined, 
                isDark: isDark,
                trailing: Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: desktopState.searchShowNews, 
                    activeColor: themeState.currentAccentColor, 
                    onChanged: (val) => desktopState.updateSearchSetting('showNews', val)
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Center(
              child: Text(
                'Search is globally integrated.\nAll apps and local media are indexed dynamically.',
                textAlign: TextAlign.center,
                style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13, height: 1.5),
              ),
            ),
          )
        ],
      ),
    );
  }
}

class TaskbarScreen extends StatelessWidget {
  const TaskbarScreen({Key? key}) : super(key: key);

  void _showAlignmentDialog(BuildContext context, DesktopState desktopState, ThemeState themeState) {
    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accent = themeState.currentAccentColor;

    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor, 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), 
        title: Text('Taskbar Alignment', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)), 
        content: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            ListTile(leading: Icon(Icons.align_horizontal_left, color: accent), title: Text('Left', style: TextStyle(color: textColor, fontSize: 14)), trailing: desktopState.taskbarAlignment == 'left' ? Icon(Icons.check, color: accent) : null, onTap: () { desktopState.setTaskbarAlignment('left'); Navigator.pop(ctx); }), 
            ListTile(leading: Icon(Icons.align_horizontal_center, color: accent), title: Text('Center', style: TextStyle(color: textColor, fontSize: 14)), trailing: desktopState.taskbarAlignment == 'center' ? Icon(Icons.check, color: accent) : null, onTap: () { desktopState.setTaskbarAlignment('center'); Navigator.pop(ctx); })
          ]
        )
      )
    );
  }

  void _showDimensionSliderDialog(
    BuildContext context, 
    String title, 
    String type, 
    double min, 
    double max, 
    double divisions, 
    double currentValue, 
    DesktopState desktopState, 
    ThemeState themeState
  ) {
    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accent = themeState.currentAccentColor;
    double tempValue = currentValue;

    showDialog(
      context: context, 
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: bgColor, 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              title: Text(title, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)), 
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: accent,
                      inactiveTrackColor: accent.withOpacity(0.2),
                      thumbColor: accent,
                    ),
                    child: Slider(
                      value: tempValue,
                      min: min,
                      max: max,
                      divisions: divisions.toInt(),
                      onChanged: (val) => setDialogState(() => tempValue = val),
                    ),
                  ),
                  Text(
                    type == 'height' ? 'Height: ${tempValue.toInt()} pt' 
                    : type == 'spacing' ? 'Spacing: ${tempValue.toInt()} pt' 
                    : 'Scale: ${tempValue.toStringAsFixed(2)}x', 
                    style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600)
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
                TextButton(
                  onPressed: () {
                    if (type == 'height') {
                      desktopState.setTaskbarDimensions(height: tempValue);
                    } else if (type == 'spacing') {
                      desktopState.setTaskbarDimensions(iconSpacing: tempValue);
                    } else {
                      desktopState.setTaskbarDimensions(iconScale: tempValue);
                    }
                    Navigator.pop(ctx);
                  }, 
                  child: Text('Save', style: TextStyle(color: accent, fontWeight: FontWeight.bold))
                ),
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktopState = context.watch<DesktopState>();
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Personalization > Taskbar'),
      body: ListView(
        padding: const EdgeInsets.all(16), physics: const BouncingScrollPhysics(),
        children: [
          Win11SettingsGroup(
            title: 'Taskbar layout & size',
            isDark: isDark,
            children: [
              Win11SettingsTile(
                title: 'Taskbar alignment', 
                subtitle: 'Select the position of the taskbar', 
                icon: Icons.border_bottom, 
                isDark: isDark,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), 
                  decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)), 
                  child: Text(desktopState.taskbarAlignment == 'center' ? 'Center' : 'Left', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)
                ), 
                onTap: () => _showAlignmentDialog(context, desktopState, themeState)
              ),
              Win11SettingsTile(
                title: 'Taskbar height', 
                subtitle: 'Adjust the vertical thickness of the taskbar', 
                icon: Icons.height, 
                isDark: isDark,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), 
                  decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)), 
                  child: Text('${desktopState.taskbarHeight.toInt()} pt', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)
                ), 
                onTap: () => _showDimensionSliderDialog(
                  context, 'Taskbar Height', 'height', 38.0, 72.0, 17, desktopState.taskbarHeight, desktopState, themeState
                )
              ),
              Win11SettingsTile(
                title: 'Taskbar icon scale', 
                subtitle: 'Adjust icon size for active and pinned apps', 
                icon: Icons.photo_size_select_small, 
                isDark: isDark,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), 
                  decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)), 
                  child: Text('${desktopState.taskbarIconScale.toStringAsFixed(2)}x', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)
                ), 
                onTap: () => _showDimensionSliderDialog(
                  context, 'Taskbar Icon Scale', 'scale', 0.6, 1.6, 20, desktopState.taskbarIconScale, desktopState, themeState
                )
              ),
              Win11SettingsTile(
                title: 'Taskbar icon spacing', 
                subtitle: 'Adjust the gap between apps on the taskbar', 
                icon: Icons.space_bar, 
                isDark: isDark,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), 
                  decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)), 
                  child: Text('${desktopState.taskbarIconSpacing.toInt()} pt', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)
                ), 
                onTap: () => _showDimensionSliderDialog(
                  context, 'Taskbar Icon Spacing', 'spacing', 0.0, 24.0, 24, desktopState.taskbarIconSpacing, desktopState, themeState
                )
              ),
              Win11SettingsTile(
                title: 'Start Menu Icon', 
                subtitle: 'Change the default Windows logo on the taskbar', 
                icon: Icons.dashboard_customize_outlined, 
                isDark: isDark,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (desktopState.customStartIconPath != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: InkWell(
                          onTap: () {
                            desktopState.setCustomStartIcon(null);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restored default Start icon')));
                          },
                          child: const Icon(Icons.restore, color: Colors.redAccent, size: 20),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.all(4), 
                      decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)), 
                      child: desktopState.customStartIconPath != null && File(desktopState.customStartIconPath!).existsSync()
                          ? Image.file(
                              File(desktopState.customStartIconPath!), 
                              width: 18, 
                              height: 18,
                              cacheWidth: 54,
                              cacheHeight: 54,
                              errorBuilder: (_, __, ___) => Icon(Icons.window, size: 18, color: textColor),
                            )
                          : Image.asset(
                              'assets/icons/start.png', 
                              width: 18, 
                              height: 18, 
                              errorBuilder: (_, __, ___) => Icon(Icons.window, size: 18, color: textColor)
                            ),
                    ),
                  ],
                ), 
                onTap: () async {
                  final picker = ImagePicker();
                  final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                  if (image != null) {
                    final dir = await getApplicationDocumentsDirectory();
                    final File newIcon = File('${dir.path}/custom_start_icon_${DateTime.now().millisecondsSinceEpoch}.png');
                    await File(image.path).copy(newIcon.path);
                    await desktopState.setCustomStartIcon(newIcon.path);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Custom Start icon applied!')));
                    }
                  }
                }
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DesktopSettingsScreen extends StatelessWidget {
  const DesktopSettingsScreen({Key? key}) : super(key: key);

  void _showPageTransitionDialog(BuildContext context, DesktopState desktopState, ThemeState themeState) {
    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accent = themeState.currentAccentColor;
    final options = ['Classical', '3D Cube', '3D Page Flip', '3D Card', 'Cube Carousel', '3D Swipe', 'Random'];

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: bgColor,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          title: Text('Page Transition', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: options.map((opt) => InkWell(
                onTap: () {
                  if (opt != 'Classical' && !ProGatekeeper.checkAccess(context, featureName: '3D Page Transitions')) {
                    Navigator.pop(ctx);
                    return;
                  }
                  desktopState.updateDesktopSetting('pageTransition', opt);
                  Navigator.pop(ctx);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(child: Text(opt, style: TextStyle(color: textColor, fontSize: 13))),
                      if (desktopState.pageTransition == opt) Icon(Icons.check, color: accent, size: 18),
                    ],
                  ),
                ),
              )).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)))
          ]
        );
      }
    );
  }

  void _showDoubleSliderDialog(
    BuildContext context, String title, String key, 
    double min, double max, double divisions, double currentValue, 
    DesktopState desktopState, ThemeState themeState
  ) {
    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accent = themeState.currentAccentColor;
    
    double tempValue = currentValue;

    showDialog(
      context: context, 
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: bgColor, 
              title: Text(title, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)), 
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: accent,
                      inactiveTrackColor: accent.withOpacity(0.2),
                      thumbColor: accent,
                    ),
                    child: Slider(
                      value: tempValue,
                      min: min,
                      max: max,
                      divisions: divisions.toInt(),
                      onChanged: (val) => setDialogState(() => tempValue = val),
                    ),
                  ),
                  Text(
                    key == 'desktopIconScale' ? 'Scale: ${tempValue.toStringAsFixed(2)}x' : 'Size: ${tempValue.toInt()} pt', 
                    style: TextStyle(color: textColor, fontSize: 14)
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
                TextButton(
                  onPressed: () {
                    desktopState.updateDesktopSetting(key, tempValue);
                    Navigator.pop(ctx);
                  }, 
                  child: Text('Save', style: TextStyle(color: accent))
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _showGridDialog(BuildContext context, DesktopState desktopState, ThemeState themeState, bool isPortrait) {
    final isDark = themeState.isDarkMode;
    final bgColor = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accent = themeState.currentAccentColor;
    
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = isPortrait ? math.min(screenSize.width, screenSize.height) : math.max(screenSize.width, screenSize.height);
    final screenHeight = isPortrait ? math.max(screenSize.width, screenSize.height) : math.min(screenSize.width, screenSize.height);

    final int calculatedMaxX = (screenWidth / 48.0).floor().clamp(3, 20);
    final int calculatedMaxY = (screenHeight / 64.0).floor().clamp(3, 20);
    
    int currentX = (isPortrait ? desktopState.portraitGridX : desktopState.landscapeGridX).clamp(3, calculatedMaxX);
    int currentY = (isPortrait ? desktopState.portraitGridY : desktopState.landscapeGridY).clamp(3, calculatedMaxY);
    
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                  children: [
                    Text('Columns (X):', style: TextStyle(color: textColor)), 
                    DropdownButton<int>(
                      value: currentX, 
                      dropdownColor: bgColor, 
                      style: TextStyle(color: textColor), 
                      items: List.generate(calculatedMaxX - 2, (i) => DropdownMenuItem(value: i + 3, child: Text('${i + 3}'))), 
                      onChanged: (val) => setDialogState(() => currentX = val!)
                    )
                  ]
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                  children: [
                    Text('Rows (Y):', style: TextStyle(color: textColor)), 
                    DropdownButton<int>(
                      value: currentY, 
                      dropdownColor: bgColor, 
                      style: TextStyle(color: textColor), 
                      items: List.generate(calculatedMaxY - 2, (i) => DropdownMenuItem(value: i + 3, child: Text('${i + 3}'))), 
                      onChanged: (val) => setDialogState(() => currentY = val!)
                    )
                  ]
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
              TextButton(onPressed: () {
                desktopState.updateDesktopSetting(isPortrait ? 'portraitGridX' : 'landscapeGridX', currentX);
                desktopState.updateDesktopSetting(isPortrait ? 'portraitGridY' : 'landscapeGridY', currentY);
                Navigator.pop(ctx);
              }, child: Text('Save', style: TextStyle(color: accent))),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktopState = context.watch<DesktopState>();
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accent = themeState.currentAccentColor;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Personalization > Desktop'),
      body: ListView(
        padding: const EdgeInsets.all(16), physics: const BouncingScrollPhysics(),
        children: [
          Win11SettingsGroup(
            title: 'Layout & scaling',
            isDark: isDark,
            children: [
              Win11SettingsTile(
                title: 'Allow Landscape Mode', 
                subtitle: desktopState.allowLandscape 
                    ? 'Launcher will rotate when phone is turned' 
                    : 'Locked to Portrait mode (Recommended for phones)', 
                icon: Icons.screen_rotation_outlined, 
                isDark: isDark,
                trailing: Transform.scale(
                  scale: 0.85, 
                  child: Switch(
                    value: desktopState.allowLandscape, 
                    activeColor: accent, 
                    onChanged: (val) => desktopState.setAllowLandscape(val),
                  ),
                ),
              ),
              Win11SettingsTile(
                title: 'Desktop Icon Size', subtitle: 'Manually adjust the scale of desktop apps', icon: Icons.photo_size_select_small, isDark: isDark,
                trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300), borderRadius: BorderRadius.circular(6)), child: Text('${desktopState.desktopIconScale.toStringAsFixed(2)}x', style: TextStyle(color: textColor, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)), 
                onTap: () => _showDoubleSliderDialog(context, 'Adjust Icon Size', 'desktopIconScale', 0.5, 2.0, 30, desktopState.desktopIconScale, desktopState, themeState)
              ),
              Win11SettingsTile(
                title: 'Desktop Font Size', subtitle: 'Manually adjust text size on the desktop', icon: Icons.format_size, isDark: isDark,
                trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300), borderRadius: BorderRadius.circular(6)), child: Text('${desktopState.desktopFontSize.toInt()} pt', style: TextStyle(color: textColor, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)), 
                onTap: () => _showDoubleSliderDialog(context, 'Adjust Font Size', 'desktopFontSize', 8.0, 18.0, 10, desktopState.desktopFontSize, desktopState, themeState)
              ),
              Win11SettingsTile(
                title: 'Portrait Grid count', subtitle: '${desktopState.portraitGridX} x ${desktopState.portraitGridY}', icon: Icons.grid_on, isDark: isDark,
                trailing: Icon(Icons.chevron_right, color: textColor, size: 20), 
                onTap: () => _showGridDialog(context, desktopState, themeState, true)
              ),
              if (desktopState.allowLandscape)
                Win11SettingsTile(
                  title: 'Landscape Grid count', subtitle: '${desktopState.landscapeGridX} x ${desktopState.landscapeGridY}', icon: Icons.grid_on, isDark: isDark,
                  trailing: Icon(Icons.chevron_right, color: textColor, size: 20), 
                  onTap: () => _showGridDialog(context, desktopState, themeState, false)
                ),
              Win11SettingsTile(
                title: 'Page Transition',
                subtitle: desktopState.pageTransition,
                icon: Icons.animation,
                isDark: isDark,
                trailing: Icon(Icons.chevron_right, color: textColor, size: 20),
                onTap: () => _showPageTransitionDialog(context, desktopState, themeState),
              ),
            ],
          ),
          Win11SettingsGroup(
            title: 'Interaction',
            isDark: isDark,
            children: [
              Win11SettingsTile(
                title: 'Drag icons', subtitle: 'Allow repositioning of desktop shortcuts', icon: Icons.pan_tool_outlined, isDark: isDark,
                trailing: Transform.scale(
                  scale: 0.85, 
                  child: Switch(value: desktopState.dragIcons, activeColor: accent, onChanged: (val) => desktopState.updateDesktopSetting('dragIcons', val))
                )
              ),
              Win11SettingsTile(
                title: 'Create shortcut for new apps', subtitle: 'Automatically add newly installed apps to desktop', icon: Icons.layers_outlined, isDark: isDark,
                trailing: Transform.scale(
                  scale: 0.85, 
                  child: Switch(value: desktopState.createShortcut, activeColor: accent, onChanged: (val) => desktopState.updateDesktopSetting('createShortcut', val))
                )
              ),
            ],
          ),
          Win11SettingsGroup(
            title: 'Visibility',
            isDark: isDark,
            children: [
              Win11SettingsTile(
                title: 'Hide Status Bar', icon: Icons.open_in_full, isDark: isDark, 
                trailing: Transform.scale(scale: 0.85, child: Switch(value: desktopState.hideStatusBar, activeColor: accent, onChanged: (val) => desktopState.updateDesktopSetting('hideStatusBar', val)))
              ),
              Win11SettingsTile(
                title: 'Hide Navigation Bar', icon: Icons.open_in_full_outlined, isDark: isDark, 
                trailing: Transform.scale(scale: 0.85, child: Switch(value: desktopState.hideNavBar, activeColor: accent, onChanged: (val) => desktopState.updateDesktopSetting('hideNavBar', val)))
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FileManagerScreen extends StatelessWidget {
  const FileManagerScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final desktopState = context.watch<DesktopState>();
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final accent = themeState.currentAccentColor;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const SubScreenAppBar(title: 'Personalization > File manager'),
      body: ListView(
        padding: const EdgeInsets.all(16), 
        physics: const BouncingScrollPhysics(),
        children: [
          Win11SettingsGroup(
            title: 'View Options',
            isDark: isDark,
            children: [
              Win11SettingsTile(
                title: 'Show hidden files', icon: Icons.visibility_off_outlined, isDark: isDark,
                trailing: Transform.scale(
                  scale: 0.85, 
                  child: Switch(value: desktopState.showHiddenFiles, activeColor: accent, onChanged: (val) => desktopState.updateDesktopSetting('showHiddenFiles', val))
                ),
              ),
              Win11SettingsTile(
                title: 'Preview files', icon: Icons.preview_outlined, isDark: isDark,
                trailing: Transform.scale(
                  scale: 0.85, 
                  child: Switch(value: desktopState.previewFiles, activeColor: accent, onChanged: (val) => desktopState.updateDesktopSetting('previewFiles', val))
                ),
              ),
            ],
          ),
          Win11SettingsGroup(
            title: 'Interaction',
            isDark: isDark,
            children: [
              Win11SettingsTile(
                title: 'Play navigation sounds', subtitle: 'Play a sound on folder clicks', icon: Icons.volume_up_outlined, isDark: isDark,
                trailing: Transform.scale(
                  scale: 0.85, 
                  child: Switch(value: desktopState.mouseSound, activeColor: accent, onChanged: (val) => desktopState.updateDesktopSetting('mouseSound', val))
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}