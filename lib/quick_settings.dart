import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:win11_pc_launcher/services/battery_mock.dart';

import 'states/theme_state.dart';
import 'services/native_bridge.dart';
import 'ui/shared/acrylic_container.dart';

class QuickSettings extends StatefulWidget {
  final Map<String, bool> settingsState;
  final Function(String) onToggle;
  final double brightness;
  final Function(double) onBrightnessChanged;
  final VoidCallback? onBrightnessDragStart;
  final ValueChanged<double>? onBrightnessDragEnd;
  final double volume;
  final Function(double) onVolumeChanged;
  final VoidCallback? onVolumeDragStart;
  final ValueChanged<double>? onVolumeDragEnd;
  final int batteryLevel;
  final BatteryState batteryState; 
  final VoidCallback onOpenSettings;
  
  final List<String> visibleTiles;
  final List<String> hiddenTiles;
  final Function(String) onToggleVisibility;
  final Map<String, dynamic>? activeMedia;

  const QuickSettings({
    Key? key,
    required this.settingsState,
    required this.onToggle,
    required this.brightness,
    required this.onBrightnessChanged,
    this.onBrightnessDragStart,
    this.onBrightnessDragEnd,
    required this.volume,
    required this.onVolumeChanged,
    this.onVolumeDragStart,
    this.onVolumeDragEnd,
    required this.batteryLevel,
    required this.batteryState,
    required this.onOpenSettings,
    required this.visibleTiles,
    required this.hiddenTiles,
    required this.onToggleVisibility,
    this.activeMedia,
  }) : super(key: key);

  @override
  State<QuickSettings> createState() => _QuickSettingsState();
}

class _QuickSettingsState extends State<QuickSettings> {
  bool _isEditing = false;
  
  String? _cachedMediaTitle;
  ImageProvider? _cachedMediaBg;

  IconData _getIcon(String key) {
    switch (key) {
      case 'Airplane mode': return Icons.airplanemode_active;
      case 'Battery saver': return Icons.battery_saver;
      case 'Wi-Fi': return Icons.wifi;
      case 'Bluetooth': return Icons.bluetooth;
      case 'Flash': return Icons.flashlight_on;
      case 'Data': return Icons.swap_vert;
      case 'Rotate': return Icons.screen_rotation;
      case 'Location': return Icons.location_on;
      case 'Hotspot': return Icons.wifi_tethering;
      case 'Brightness': return Icons.brightness_6;
      case 'Accessibility': return Icons.accessibility;
      
      case 'Play': return Icons.play_arrow;
      case 'Ring': return Icons.notifications_active;
      case 'ChatGPT': return Icons.auto_awesome; 
      case 'Storage': return Icons.storage;
      case 'Dark Theme': return Icons.dark_mode;
      case 'Calculator': return Icons.calculate;
      case 'Song Search': return Icons.music_note;
      case 'DND': return Icons.do_not_disturb_on;
      case 'Screen Cast': return Icons.cast;
      case 'Eye Care': return Icons.remove_red_eye;
      case 'Scan QR Code': return Icons.qr_code_scanner;
      case 'Users & Account': return Icons.computer;
      case 'Kids Mode': return Icons.child_care;
      default: return Icons.widgets;
    }
  }

  Widget _buildMediaPlayer(bool isDark, Color accentColor, Color primaryText, Color secText) {
    final media = widget.activeMedia;
    final title = media?['title']?.toString() ?? 'Ready to Play';
    final artist = media?['text']?.toString() ?? 'Tap play to resume audio';
    final bool isPlaying = media?['isPlaying'] == true;
    
    if (_cachedMediaTitle != title || (_cachedMediaBg == null && media?['largeIcon'] != null)) {
      _cachedMediaTitle = title;
      _cachedMediaBg?.evict(); 
      _cachedMediaBg = null;
      
      if (media != null && media['largeIcon'] != null) {
        try {
          final dynamic rawIcon = media['largeIcon'];
          if (rawIcon is String) {
            final file = File(rawIcon);
            if (file.existsSync()) {
              _cachedMediaBg = ResizeImage(FileImage(file), width: 160, height: 160);
            }
          } else if (rawIcon is Uint8List) {
            _cachedMediaBg = ResizeImage(MemoryImage(rawIcon), width: 160, height: 160);
          } else if (rawIcon is List) {
            _cachedMediaBg = ResizeImage(MemoryImage(Uint8List.fromList(rawIcon.map((e) => e as int).toList())), width: 160, height: 160);
          }
        } catch (e) {
          debugPrint('Media artwork parse error: $e');
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
        image: _cachedMediaBg != null ? DecorationImage(
          image: _cachedMediaBg!,
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.65), BlendMode.darken),
        ) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: TextStyle(color: _cachedMediaBg != null ? Colors.white : primaryText, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(artist, style: TextStyle(color: _cachedMediaBg != null ? Colors.white70 : secText, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.skip_previous, size: 22, color: _cachedMediaBg != null ? Colors.white : primaryText), 
                onPressed: () => NativeBridge.instance.sendMediaCommand('prev')
              ),
              IconButton(
                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 28, color: _cachedMediaBg != null ? Colors.white : primaryText), 
                onPressed: () {
                  NativeBridge.instance.sendMediaCommand('play_pause');
                  if (widget.activeMedia == null) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (widget.activeMedia == null) {
                        NativeBridge.instance.toggleHardware('Play', true);
                      }
                    });
                  }
                }
              ),
              IconButton(
                icon: Icon(Icons.skip_next, size: 22, color: _cachedMediaBg != null ? Colors.white : primaryText), 
                onPressed: () => NativeBridge.instance.sendMediaCommand('next')
              ),
              const SizedBox(width: 4),
            ]
          )
        ]
      )
    );
  }

  Widget _buildTile(String key, bool isDark, Color accentColor, Color primaryText, Color inactiveTileBg, {bool isEditMode = false, bool isHidden = false}) {
    bool isActive = widget.settingsState[key] ?? false;
    
    Color bgColor = isEditMode ? inactiveTileBg : (isActive ? accentColor : inactiveTileBg);
    Color activeContentColor = accentColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    Color contentColor = isEditMode ? primaryText : (isActive ? activeContentColor : primaryText);

    return InkWell(
      onTap: isEditMode ? () => widget.onToggleVisibility(key) : () => widget.onToggle(key),
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: bgColor, 
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black12, width: 0.5)
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_getIcon(key), color: contentColor, size: 20),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: Text(
                      key, 
                      textAlign: TextAlign.center, 
                      style: TextStyle(fontSize: 10, color: contentColor, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isEditMode)
            Positioned(
              top: 2, right: 2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: isHidden ? Colors.green : Colors.red, shape: BoxShape.circle),
                child: Icon(isHidden ? Icons.add : Icons.remove, size: 10, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required IconData icon,
    required double value,
    required ValueChanged<double> onChanged,
    VoidCallback? onChangeStart,
    ValueChanged<double>? onChangeEnd,
    required Color accentColor,
    required Color iconColor,
    required Color inactiveTrackColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0), 
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              onChangeStart: (_) => onChangeStart?.call(),
              onChanged: onChanged,
              onChangeEnd: (val) => onChangeEnd?.call(val),
              activeColor: accentColor,
              inactiveColor: inactiveTrackColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNormalMode(bool isDark, Color accentColor, Color primaryText, Color secText, Color borderCol, Color inactiveTileBg, Color inactiveTrackColor) {
    bool isCharging = widget.batteryState == BatteryState.charging || widget.batteryState == BatteryState.full;
    double sBright = widget.brightness.isNaN || widget.brightness.isInfinite ? 0.5 : widget.brightness.clamp(0.0, 1.0);
    double sVol = widget.volume.isNaN || widget.volume.isInfinite ? 0.5 : widget.volume.clamp(0.0, 1.0);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMediaPlayer(isDark, accentColor, primaryText, secText),

          GridView.count(
            padding: EdgeInsets.zero, 
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            childAspectRatio: 1.35, 
            mainAxisSpacing: 4, 
            crossAxisSpacing: 4, 
            children: widget.visibleTiles.map((key) => _buildTile(key, isDark, accentColor, primaryText, inactiveTileBg)).toList(),
          ),
          const SizedBox(height: 8),
          _buildSliderRow(
            icon: Icons.brightness_6, 
            value: sBright, 
            onChanged: widget.onBrightnessChanged,
            onChangeStart: widget.onBrightnessDragStart,
            onChangeEnd: widget.onBrightnessDragEnd,
            accentColor: accentColor, 
            iconColor: secText, 
            inactiveTrackColor: inactiveTrackColor,
          ),
          _buildSliderRow(
            icon: Icons.volume_up, 
            value: sVol, 
            onChanged: widget.onVolumeChanged,
            onChangeStart: widget.onVolumeDragStart,
            onChangeEnd: widget.onVolumeDragEnd,
            accentColor: accentColor, 
            iconColor: secText, 
            inactiveTrackColor: inactiveTrackColor,
          ),
          Divider(height: 12, thickness: 1, color: borderCol), 
          Row(
            children: [
              Icon(
                isCharging ? Icons.battery_charging_full : Icons.battery_full, 
                size: 16, 
                color: isCharging ? Colors.green.shade500 : primaryText
              ),
              const SizedBox(width: 6),
              Text('${widget.batteryLevel}%', style: TextStyle(fontSize: 11, color: primaryText, fontWeight: FontWeight.bold)),
              const Spacer(),
              InkWell(
                onTap: () => setState(() => _isEditing = true),
                child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.edit, size: 16, color: primaryText)),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: widget.onOpenSettings,
                child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.settings, size: 16, color: primaryText)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditMode(bool isDark, Color accentColor, Color primaryText, Color inactiveTileBg) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Visible Panels', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: primaryText)),
              InkWell(
                onTap: () => setState(() => _isEditing = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(16)),
                  child: Text('Done', style: TextStyle(color: accentColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            childAspectRatio: 1.35,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: widget.visibleTiles.map((key) => _buildTile(key, isDark, accentColor, primaryText, inactiveTileBg, isEditMode: true, isHidden: false)).toList(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: Text('Hidden Panels', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: primaryText)),
          ),
          GridView.count(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            childAspectRatio: 1.35,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: widget.hiddenTiles.map((key) => _buildTile(key, isDark, accentColor, primaryText, inactiveTileBg, isEditMode: true, isHidden: true)).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;
    final accentColor = themeState.currentAccentColor;

    final primaryText = isDark ? Colors.white : Colors.black87;
    final secText = isDark ? Colors.white70 : Colors.black54;
    final borderCol = isDark ? Colors.white24 : Colors.grey.shade300;
    
    final inactiveTileBg = isDark ? Colors.white10 : Colors.grey.shade200;
    final inactiveTrackColor = isDark ? Colors.white24 : Colors.grey.shade300;

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () {}, 
        behavior: HitTestBehavior.opaque,
        child: Win11AcrylicContainer(
          padding: const EdgeInsets.only(top: 10, left: 12, right: 12, bottom: 12),
          child: _isEditing 
              ? _buildEditMode(isDark, accentColor, primaryText, inactiveTileBg) 
              : _buildNormalMode(isDark, accentColor, primaryText, secText, borderCol, inactiveTileBg, inactiveTrackColor),
        ),
      ),
    );
  }
}