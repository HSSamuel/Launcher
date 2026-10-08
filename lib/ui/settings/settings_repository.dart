import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import '../../services/native_bridge.dart';
import 'settings_system_screens.dart';
import 'settings_personalization_screens.dart';
import 'settings_usb_screen.dart';
import 'settings_apps_view.dart';
import 'settings_accounts_view.dart';
import 'settings_backup_screen.dart';
import 'settings_sign_in_options.dart'; 
import 'settings_gestures_view.dart';
import 'settings_privacy_security_view.dart';
import 'settings_update_view.dart';

class SettingsRepository {
  static final List<Map<String, dynamic>> actions = [
    // System Category (0)
    {'categoryIndex': 0, 'title': 'Default Launcher', 'subtitle': 'Set this application as your primary home screen', 'icon': Icons.home_filled, 'onTap': (BuildContext ctx) => NativeBridge.instance.openSettings('home')},
    {'categoryIndex': 0, 'title': 'Display', 'subtitle': 'Monitors, brightness, night light, display profile', 'icon': Icons.desktop_windows_outlined, 'onTap': (BuildContext ctx) => AppSettings.openAppSettings(type: AppSettingsType.display)},
    {'categoryIndex': 0, 'title': 'Sound', 'subtitle': 'Volume levels, output, input, sound device', 'icon': Icons.volume_up_outlined, 'onTap': (BuildContext ctx) => NativeBridge.instance.openSettings('sound')},
    {'categoryIndex': 0, 'title': 'Notifications', 'subtitle': 'Alerts from apps and system', 'icon': Icons.notifications_none, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const NotificationsScreen()))},
    {'categoryIndex': 0, 'title': 'Recent apps', 'subtitle': 'Most used apps and games', 'icon': Icons.filter_none, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const RecentAppsScreen()))},
    {'categoryIndex': 0, 'title': 'Power & battery', 'subtitle': 'Sleep, battery usage, battery saver', 'icon': Icons.power_settings_new, 'onTap': (BuildContext ctx) => AppSettings.openAppSettings(type: AppSettingsType.batteryOptimization)},
    {'categoryIndex': 0, 'title': 'Backup & Restore', 'subtitle': 'Save or load your launcher layout and preferences', 'icon': Icons.save_alt, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const BackupRestoreScreen()))},
    {'categoryIndex': 0, 'title': 'About', 'subtitle': 'Device specifications, rename PC, Launcher specification', 'icon': Icons.info_outline, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const AboutScreen()))},
    {'categoryIndex': 0, 'title': 'Device Support', 'subtitle': 'Report a bug, request new features and more', 'icon': Icons.devices, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const DeviceSupportScreen()))},
    
    // Bluetooth & devices (1)
    {'categoryIndex': 1, 'title': 'Bluetooth', 'subtitle': 'Bluetooth is turned off', 'icon': Icons.bluetooth, 'onTap': (BuildContext ctx) => AppSettings.openAppSettings(type: AppSettingsType.bluetooth)},
    {'categoryIndex': 1, 'title': 'Printers & scanners', 'subtitle': 'Preferences, troubleshoot', 'icon': Icons.print_outlined, 'onTap': (BuildContext ctx) => NativeBridge.instance.openSettings('print_settings')},
    {'categoryIndex': 1, 'title': 'USB', 'subtitle': 'Notifications, USB battery saver, mobile device preferences', 'icon': Icons.usb, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const SettingsUsbScreen()))},
    
    // Network & Internet (2)
    {'categoryIndex': 2, 'title': 'Wi-Fi', 'subtitle': 'Connect, manage known networks, metered network', 'icon': Icons.wifi, 'onTap': (BuildContext ctx) => AppSettings.openAppSettings(type: AppSettingsType.wifi)},
    {'categoryIndex': 2, 'title': 'Mobile hotspot', 'subtitle': 'Share your internet connection', 'icon': Icons.wifi_tethering, 'onTap': (BuildContext ctx) => AppSettings.openAppSettings(type: AppSettingsType.hotspot)},
    {'categoryIndex': 2, 'title': 'Airplane mode', 'subtitle': 'Stop all wireless communication', 'icon': Icons.airplanemode_active, 'onTap': (BuildContext ctx) => AppSettings.openAppSettings(type: AppSettingsType.wireless)},
    
    // Personalization (3)
    {'categoryIndex': 3, 'title': 'Background', 'subtitle': 'Background image, folder, slideshow', 'icon': Icons.image_outlined, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const BackgroundScreen()))},
    {'categoryIndex': 3, 'title': 'Themes', 'subtitle': 'Install, create, manage', 'icon': Icons.color_lens_outlined, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ThemesScreen()))},
    {'categoryIndex': 3, 'title': 'Start', 'subtitle': 'Recent apps and items, folders', 'icon': Icons.apps_outage, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const StartSettingsScreen()))},
    {'categoryIndex': 3, 'title': 'Search', 'subtitle': 'Manage search types, indexing', 'icon': Icons.search, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const SearchScreen()))},
    {'categoryIndex': 3, 'title': 'Taskbar', 'subtitle': 'Taskbar behaviours, system pin', 'icon': Icons.border_bottom, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const TaskbarScreen()))},
    {'categoryIndex': 3, 'title': 'Desktop', 'subtitle': 'Icon size, double tap to sleep', 'icon': Icons.desktop_windows_outlined, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const DesktopSettingsScreen()))},
    {'categoryIndex': 3, 'title': 'File manager', 'subtitle': 'Manage files, view styles', 'icon': Icons.snippet_folder_outlined, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const FileManagerScreen()))},
    
    // Gestures (4)
    {'categoryIndex': 4, 'title': 'Gestures Preferences', 'subtitle': 'Haptic feedback, Double tap, Swipe Gestures', 'icon': Icons.touch_app, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const SettingsGesturesView()))},
    
    // Apps (5)
    {'categoryIndex': 5, 'title': 'Apps & features', 'subtitle': 'Installed apps, system apps', 'icon': Icons.format_list_bulleted, 'onTap': (BuildContext ctx) => NativeBridge.instance.openSettings('manage_apps')},
    {'categoryIndex': 5, 'title': 'Default apps', 'subtitle': 'Defaults for file and link types, other defaults', 'icon': Icons.app_shortcut, 'onTap': (BuildContext ctx) => NativeBridge.instance.openSettings('default_apps')},
    {'categoryIndex': 5, 'title': 'Optional features', 'subtitle': 'Extra functionality for your device', 'icon': Icons.add_box_outlined, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const OptionalFeaturesScreen()))},
    
    // Accounts (6)
    {'categoryIndex': 6, 'title': 'Your info', 'subtitle': 'Accounts used by email, calendar and contacts', 'icon': Icons.person_search_outlined, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const YourInfoScreen()))},
    {'categoryIndex': 6, 'title': 'Sign-in options', 'subtitle': 'PIN configuration, Windows Hello', 'icon': Icons.lock_outline, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const SignInOptionsScreen()))},
    {'categoryIndex': 6, 'title': 'Email & accounts', 'subtitle': 'Accounts used by email, calendar and contacts', 'icon': Icons.mail_outline, 'onTap': (BuildContext ctx) => NativeBridge.instance.openSettings('add_account')},
    
    // Time & language (7)
    {'categoryIndex': 7, 'title': 'Date & time', 'subtitle': 'Time zones, automatic clock settings, calendar display', 'icon': Icons.access_time, 'onTap': (BuildContext ctx) => AppSettings.openAppSettings(type: AppSettingsType.date)},
    {'categoryIndex': 7, 'title': 'Language & region', 'subtitle': 'Windows display language, preferred languages, regional format', 'icon': Icons.language, 'onTap': (BuildContext ctx) => NativeBridge.instance.openSettings('locale')},
    {'categoryIndex': 7, 'title': 'Typing', 'subtitle': 'Touch keyboard, text suggestions, preferences', 'icon': Icons.keyboard_outlined, 'onTap': (BuildContext ctx) => NativeBridge.instance.openSettings('keyboard')},
    
    // Privacy & security (8)
    {'categoryIndex': 8, 'title': 'Privacy & Security', 'subtitle': 'App Lock, Hidden Apps Vault, Permissions', 'icon': Icons.security, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const SettingsPrivacySecurityView()))},
    
    // Launcher Update (9)
    {'categoryIndex': 9, 'title': 'Launcher Update', 'subtitle': 'System Update Available, Check for updates', 'icon': Icons.sync, 'onTap': (BuildContext ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const SettingsUpdateView()))},
  ];

  static List<Map<String, dynamic>> getAllSettingsActions() => actions;
}