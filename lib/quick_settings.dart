import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:provider/provider.dart';
import 'launcher_state.dart';

class QuickSettings extends StatefulWidget {
  final Map<String, bool> settingsState;
  final Function(String) onToggle;
  final double brightness;
  final Function(double) onBrightnessChanged;
  final double volume;
  final Function(double) onVolumeChanged;
  final int batteryLevel;
  final BatteryState batteryState; 
  final VoidCallback onOpenSettings;
  
  final List<String> visibleTiles;
  final List<String> hiddenTiles;
  final Function(String) onToggleVisibility;

  const QuickSettings({
    Key? key,
    required this.settingsState,
    required this.onToggle,
    required this.brightness,
    required this.onBrightnessChanged,
    required this.volume,
    required this.onVolumeChanged,
    required this.batteryLevel,
    required this.batteryState,
    required this.onOpenSettings,
    required this.visibleTiles,
    required this.hiddenTiles,
    required this.onToggleVisibility,
  }) : super(key: key);

  @override
  State<QuickSettings> createState() => _QuickSettingsState();
}

class _QuickSettingsState extends State<QuickSettings> {
  bool _isEditing = false;

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
      case 'VPN': return Icons.vpn_key;
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
      case 'PC Connection': return Icons.computer;
      case 'Kids Mode': return Icons.child_care;
      default: return Icons.widgets;
    }
  }

  Widget _buildTile(String key, bool isDark, Color accentColor, Color primaryText, Color inactiveTileBg, {bool isEditMode = false, bool isHidden = false}) {
    bool isActive = widget.settingsState[key] ?? false;
    
    Color bgColor = isEditMode ? inactiveTileBg : (isActive ? accentColor : inactiveTileBg);
    Color contentColor = isEditMode ? primaryText : (isActive ? Colors.white : primaryText);

    return InkWell(
      onTap: isEditMode ? () => widget.onToggleVisibility(key) : () => widget.onToggle(key),
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)),
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

  Widget _buildSliderRow(IconData icon, double value, Function(double) onChanged, Color accentColor, Color iconColor, Color inactiveTrackColor) {
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
              value: value, 
              onChanged: onChanged, 
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: GridView.count(
              padding: EdgeInsets.zero, 
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              childAspectRatio: 1.35, 
              mainAxisSpacing: 4, 
              crossAxisSpacing: 4, 
              children: widget.visibleTiles.map((key) => _buildTile(key, isDark, accentColor, primaryText, inactiveTileBg)).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildSliderRow(Icons.brightness_6, widget.brightness, widget.onBrightnessChanged, accentColor, secText, inactiveTrackColor),
        _buildSliderRow(Icons.volume_up, widget.volume, widget.onVolumeChanged, accentColor, secText, inactiveTrackColor),
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
    );
  }

  Widget _buildEditMode(bool isDark, Color accentColor, Color primaryText, Color inactiveTileBg) {
    return Column(
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
                child: const Text('Done', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Flexible(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    
    final theme = state.win11Themes.firstWhere((t) => t.name == state.currentThemeName, orElse: () => state.win11Themes.first);
    final accentColor = theme.accentColor;

    final primaryText = isDark ? Colors.white : Colors.black87;
    final secText = isDark ? Colors.white70 : Colors.black54;
    final borderCol = isDark ? Colors.white24 : Colors.grey.shade300;
    
    final baseBg = isDark ? const Color(0xFF1C1C1C) : const Color(0xFFF3F3F3);
    final panelBg = Color.alphaBlend(accentColor.withOpacity(0.08), baseBg).withOpacity(0.95);
    
    final inactiveTileBg = isDark ? Colors.white10 : Colors.grey.shade200;
    final inactiveTrackColor = isDark ? Colors.white24 : Colors.grey.shade300;

    return Container(
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderCol, width: 1),
        boxShadow: [BoxShadow(color: isDark ? Colors.black54 : Colors.black26, blurRadius: 10, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.only(top: 10, left: 12, right: 12, bottom: 12),
      child: _isEditing 
          ? _buildEditMode(isDark, accentColor, primaryText, inactiveTileBg) 
          : _buildNormalMode(isDark, accentColor, primaryText, secText, borderCol, inactiveTileBg, inactiveTrackColor),
    );
  }
}