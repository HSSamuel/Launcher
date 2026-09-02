import 'package:flutter/material.dart';

class QuickSettings extends StatelessWidget {
  final Map<String, bool> settingsState;
  final Function(String) onToggle;
  final double brightness;
  final Function(double) onBrightnessChanged;
  final double volume;
  final Function(double) onVolumeChanged;
  final int batteryLevel;
  final VoidCallback onOpenSettings;

  const QuickSettings({
    Key? key,
    required this.settingsState,
    required this.onToggle,
    required this.brightness,
    required this.onBrightnessChanged,
    required this.volume,
    required this.onVolumeChanged,
    required this.batteryLevel,
    required this.onOpenSettings,
  }) : super(key: key);

  IconData _getIconForSetting(String key) {
    switch(key) {
      case 'Airplane mode': return Icons.airplanemode_active;
      case 'Battery saver': return Icons.battery_saver;
      case 'Wi-Fi': return Icons.wifi;
      case 'Bluetooth': return Icons.bluetooth;
      case 'Flash': return Icons.flash_on;
      case 'Data': return Icons.swap_vert;
      case 'Rotate': return Icons.screen_rotation;
      case 'Location': return Icons.location_on;
      case 'Hotspot': return Icons.podcasts;
      case 'VPN': return Icons.vpn_key;
      case 'Brightness': return Icons.brightness_medium;
      case 'Accessibility': return Icons.accessibility;
      default: return Icons.settings;
    }
  }

  Widget _buildQuickSettingTile(IconData icon, String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF1871D9) : const Color(0xFFF3F3F3),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: isActive ? Colors.transparent : Colors.grey.shade200),
              ),
              child: Icon(icon, color: isActive ? Colors.white : Colors.black87, size: 20), // CRISP ICON
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.black87, 
              fontSize: 10, // COMPACT FONT
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14), // SLIM PADDING
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3, 
            crossAxisSpacing: 7, // TIGHTER GRID
            mainAxisSpacing: 10, // TIGHTER GRID
            childAspectRatio: 1.35, 
            children: settingsState.entries.map((entry) {
              return _buildQuickSettingTile(
                _getIconForSetting(entry.key),
                entry.key,
                entry.value,
                () => onToggle(entry.key),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 20), 
          
          Row(
            children: [
              const Icon(Icons.brightness_medium, color: Colors.black87, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4, 
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: brightness,
                    onChanged: onBrightnessChanged,
                    activeColor: const Color(0xFF1871D9),
                    inactiveColor: Colors.grey.shade300,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 13), // PERFECT SPACING

          Row(
            children: [
              const Icon(Icons.volume_up, color: Colors.black87, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4, 
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: volume,
                    onChanged: onVolumeChanged,
                    activeColor: const Color(0xFF1871D9),
                    inactiveColor: Colors.grey.shade300,
                  ),
                ),
              ),
            ],
          ),
          
          const Divider(color: Colors.black12, height: 24, thickness: 1),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.battery_full, color: Colors.black87, size: 16),
                  const SizedBox(width: 6),
                  Text('$batteryLevel%', style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              Row(
                children: [
                  InkWell(
                    onTap: () {},
                    child: const Icon(Icons.edit_outlined, color: Colors.black87, size: 16)
                  ),
                  const SizedBox(width: 16),
                  InkWell(
                    onTap: onOpenSettings,
                    child: const Icon(Icons.settings_outlined, color: Colors.black87, size: 16)
                  ),
                ],
              )
            ],
          )
        ],
      ),
    );
  }
}