import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app_settings/app_settings.dart';

import '../../states/theme_state.dart';
import '../../states/system_state.dart';
import '../../states/apps_state.dart';
import '../../services/native_bridge.dart';
import 'settings_widgets.dart';
import 'settings_system_screens.dart';
import 'settings_bluetooth_view.dart';
import 'settings_network_view.dart';
import 'settings_personalization_screens.dart';
import 'settings_gestures_view.dart';
import 'settings_apps_view.dart';
import 'settings_accounts_view.dart'; 
import 'settings_time_language_view.dart'; 
import 'settings_privacy_security_view.dart'; 
import 'settings_update_view.dart'; 
import 'settings_backup_screen.dart';
import 'settings_repository.dart'; 
import 'settings_activation_screen.dart';

class SettingsApp extends StatefulWidget {
  const SettingsApp({Key? key}) : super(key: key);
  @override
  State<SettingsApp> createState() => _SettingsAppState();
}

class _SettingsAppState extends State<SettingsApp> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<NavigatorState> _nestedNavKey = GlobalKey<NavigatorState>();
  
  AppsState? _appsState;
  int _selectedIndex = 3; 
  
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>('');
  Timer? _searchDebounce;

  final List<Map<String, dynamic>> _categories = [
    {'title': 'System', 'icon': Icons.laptop, 'color': Colors.blue},
    {'title': 'Bluetooth & devices', 'icon': Icons.bluetooth, 'color': Colors.blueAccent},
    {'title': 'Network & Internet', 'icon': Icons.wifi, 'color': Colors.blue.shade700},
    {'title': 'Personalization', 'icon': Icons.brush, 'color': Colors.orange.shade400},
    {'title': 'Gestures', 'icon': Icons.touch_app, 'color': Colors.lightBlue},
    {'title': 'Apps', 'icon': Icons.grid_view, 'color': Colors.grey.shade600},
    {'title': 'Accounts', 'icon': Icons.person, 'color': Colors.teal.shade400},
    {'title': 'Time & language', 'icon': Icons.language, 'color': Colors.blue},
    {'title': 'Privacy & security', 'icon': Icons.security, 'color': Colors.grey.shade700},
    {'title': 'Launcher Update', 'icon': Icons.sync, 'color': Colors.lightBlueAccent},
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appsState ??= context.read<AppsState>();
    _appsState?.registerBackHandler('settings', _handleBack);
  }

  @override
  void dispose() {
    _appsState?.unregisterBackHandler('settings');
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchQueryNotifier.dispose();
    super.dispose();
  }

  Future<bool> _handleBack() async {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      _scaffoldKey.currentState!.closeDrawer();
      return true;
    }
    if (_nestedNavKey.currentState?.canPop() == true) {
      _nestedNavKey.currentState!.pop();
      return true;
    }
    return false; 
  }

  void _onCategorySelected(int index, bool isCompact) {
    setState(() => _selectedIndex = index);
    if (_nestedNavKey.currentState != null) {
      // Clear out any pushed sub-routes (such as ActivationScreen) so the selected category root displays immediately
      _nestedNavKey.currentState!.pushAndRemoveUntil(
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          pageBuilder: (ctx, _, __) => _buildActiveContent(ctx, isCompact),
        ),
        (route) => false,
      );
    }
    if (isCompact && _scaffoldKey.currentState?.isDrawerOpen == true) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  Widget _buildActiveContent(BuildContext innerContext, bool isCompact) {
    switch (_selectedIndex) {
      case 0: return SystemViewScreen(innerContext: innerContext);
      case 1: return const SettingsBluetoothView(); 
      case 2: return const SettingsNetworkView(); 
      case 3: return PersonalizationViewScreen(innerContext: innerContext);
      case 4: return const SettingsGesturesView(); 
      case 5: return const SettingsAppsView(); 
      case 6: return const SettingsAccountsView();
      case 7: return const SettingsTimeLanguageView(); 
      case 8: return const SettingsPrivacySecurityView(); 
      case 9: return const SettingsUpdateView(); 
      default: return SystemViewScreen(innerContext: innerContext);
    }
  }

  Widget _buildSearchResultsList(BuildContext context, String query, Color textColor, Color subTextColor, bool isCompact) {
    final allSettings = SettingsRepository.actions;
    final matches = allSettings.where((item) {
      final title = item['title'].toString().toLowerCase();
      final subtitle = item['subtitle'].toString().toLowerCase();
      return title.contains(query) || subtitle.contains(query);
    }).toList();

    if (matches.isEmpty) {
      return Center(
        child: Text('No results found for "$query"', style: TextStyle(color: subTextColor, fontSize: 13)),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero, 
      physics: const BouncingScrollPhysics(), 
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final item = matches[index];
        return InkWell(
          onTap: () { 
            FocusScope.of(context).unfocus();
            final void Function(BuildContext) onTapAction = item['onTap'];
            final int catIndex = item['categoryIndex'];

            _onCategorySelected(catIndex, isCompact);

            Future.delayed(const Duration(milliseconds: 250), () {
              if (mounted && _nestedNavKey.currentContext != null) {
                final nestedCtx = _nestedNavKey.currentContext!;
                onTapAction(nestedCtx);
                _searchController.clear();
                _searchQueryNotifier.value = '';
              }
            });
          },
          child: Container(
            decoration: const BoxDecoration(color: Colors.transparent),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Icon(item['icon'], size: 20, color: Colors.blueAccent), 
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['title'], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(item['subtitle'], style: TextStyle(fontSize: 11, color: subTextColor), overflow: TextOverflow.ellipsis, maxLines: 1),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryList(SystemState systemState, bool isDark, Color textColor, Color subTextColor, Color searchBg, Color borderColor, Color selectedTileColor, bool isCompact) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Row(
            children: [
              Container(
                width: 56, height: 56, decoration: BoxDecoration(color: Colors.blueAccent.shade100, shape: BoxShape.circle),
                child: systemState.userImageBytes != null ? ClipOval(child: Image.memory(systemState.userImageBytes!, fit: BoxFit.cover)) : const Icon(Icons.person, size: 32, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(systemState.userName.toUpperCase(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(systemState.userEmail, style: TextStyle(fontSize: 12, color: subTextColor), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        ValueListenableBuilder<String>(
          valueListenable: _searchQueryNotifier,
          builder: (context, query, _) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(const Duration(milliseconds: 200), () {
                    _searchQueryNotifier.value = value.toLowerCase().trim();
                  });
                },
                style: TextStyle(fontSize: 13, color: textColor),
                decoration: InputDecoration(
                  isDense: true, 
                  hintText: 'Find a setting', 
                  hintStyle: TextStyle(fontSize: 13, color: subTextColor), 
                  filled: true, 
                  fillColor: searchBg, 
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)), 
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)), 
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.blueAccent)),
                  prefixIcon: Icon(Icons.search, size: 16, color: subTextColor),
                  suffixIcon: query.isNotEmpty 
                      ? IconButton(
                          icon: Icon(Icons.clear, size: 16, color: textColor),
                          onPressed: () {
                            _searchController.clear();
                            _searchQueryNotifier.value = '';
                            FocusScope.of(context).unfocus();
                          },
                        )
                      : null,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        
        Expanded(
          child: ValueListenableBuilder<String>(
            valueListenable: _searchQueryNotifier,
            builder: (context, query, _) {
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                switchInCurve: const Cubic(0.05, 0.7, 0.1, 1.0),
                child: query.isNotEmpty
                  ? _buildSearchResultsList(context, query, textColor, subTextColor, isCompact)
                  : ListView.builder(
                      key: const ValueKey('CategoriesList'),
                      padding: EdgeInsets.zero, 
                      physics: const BouncingScrollPhysics(), 
                      itemCount: _categories.length,
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        final isSelected = _selectedIndex == index;
                        return InkWell(
                          // Route through _onCategorySelected to clear sub-screens and close the drawer cleanly
                          onTap: () => _onCategorySelected(index, isCompact),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected ? selectedTileColor : Colors.transparent, 
                              border: Border(
                                left: BorderSide(
                                  color: isSelected ? Colors.blueAccent : Colors.transparent, 
                                  width: 4,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            child: Row(
                              children: [
                                Icon(category['icon'], size: 20, color: category['color']), 
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    category['title'], 
                                    style: TextStyle(
                                      fontSize: 13, 
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, 
                                      color: textColor,
                                    ), 
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final systemState = context.watch<SystemState>();
    final isDark = themeState.isDarkMode;
    
    final backgroundColor = isDark ? const Color(0xFF191919) : const Color(0xFFF3F3F3);
    final drawerBg = isDark ? const Color(0xFF202020) : const Color(0xFFF9F9F9);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final searchBg = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade400;
    final selectedTileColor = isDark ? Colors.white10 : const Color(0xFFE2E2E2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;
        
        final nestedNavigator = Navigator(
          key: _nestedNavKey,
          onGenerateRoute: (settings) => MaterialPageRoute(
            builder: (innerContext) => _buildActiveContent(innerContext, isCompact),
          ),
        );
        
        return Scaffold(
          key: _scaffoldKey, 
          backgroundColor: backgroundColor, 
          drawer: isCompact ? Drawer(
            width: constraints.maxWidth * 0.75, 
            backgroundColor: drawerBg, 
            child: _buildCategoryList(systemState, isDark, textColor, subTextColor, searchBg, borderColor, selectedTileColor, isCompact),
          ) : null,
          body: isCompact 
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.menu, color: textColor), 
                            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _categories[_selectedIndex]['title'], 
                              style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: nestedNavigator),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: 280,
                      color: drawerBg,
                      child: _buildCategoryList(systemState, isDark, textColor, subTextColor, searchBg, borderColor, selectedTileColor, isCompact),
                    ),
                    Expanded(
                      child: Scaffold(
                        backgroundColor: backgroundColor,
                        body: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 32, top: 24, bottom: 16),
                              child: Text(_categories[_selectedIndex]['title'], style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold)),
                            ),
                            Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: nestedNavigator)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class SystemViewScreen extends StatelessWidget {
  final BuildContext innerContext;
  const SystemViewScreen({Key? key, required this.innerContext}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          SettingsCard(title: 'Default Launcher', subtitle: 'Set this application as your primary home screen', icon: Icons.home_filled, trailing: const SizedBox.shrink(), onTap: () => NativeBridge.instance.openSettings('home')),
          SettingsCard(title: 'Display', subtitle: 'Monitors, brightness, night light, display profile', icon: Icons.desktop_windows_outlined, trailing: const SizedBox.shrink(), onTap: () => AppSettings.openAppSettings(type: AppSettingsType.display)),
          SettingsCard(title: 'Sound', subtitle: 'Volume levels, output, input, sound device', icon: Icons.volume_up_outlined, trailing: const SizedBox.shrink(), onTap: () => NativeBridge.instance.openSettings('sound')),
          SettingsCard(title: 'Notifications', subtitle: 'Alerts from apps and system', icon: Icons.notifications_none, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
          SettingsCard(title: 'Recent apps', subtitle: 'Most used apps and games', icon: Icons.filter_none, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const RecentAppsScreen()))),
          SettingsCard(title: 'Power & battery', subtitle: 'Sleep, battery usage, battery saver', icon: Icons.power_settings_new, trailing: const SizedBox.shrink(), onTap: () => AppSettings.openAppSettings(type: AppSettingsType.batteryOptimization)),
          SettingsCard(title: 'Backup & Restore', subtitle: 'Save or load your launcher layout and preferences', icon: Icons.save_alt, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const BackupRestoreScreen()))),
          SettingsCard(title: 'Activation', subtitle: 'Activation state, in app purchases, product key', icon: Icons.check_circle_outline, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const ActivationScreen()))),
          SettingsCard(title: 'About', subtitle: 'Device specifications, rename PC, Launcher specification', icon: Icons.info_outline, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const AboutScreen()))),
          SettingsCard(title: 'Device Support', subtitle: 'Report a bug, request new features and more', icon: Icons.devices, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const DeviceSupportScreen()))),
        ],
      ),
    );
  }
}

class PersonalizationViewScreen extends StatelessWidget {
  final BuildContext innerContext;
  const PersonalizationViewScreen({Key? key, required this.innerContext}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsCard(title: 'Background', subtitle: 'Background image, folder, slideshow', icon: Icons.image_outlined, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const BackgroundScreen()))),
          SettingsCard(title: 'Themes', subtitle: 'Install, create, manage', icon: Icons.color_lens_outlined, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const ThemesScreen()))),
          SettingsCard(title: 'Start', subtitle: 'Recent apps and items, folders', icon: Icons.apps_outage, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const StartSettingsScreen()))),
          SettingsCard(title: 'Search', subtitle: 'Manage search types, indexing', icon: Icons.search, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const SearchScreen()))),
          SettingsCard(title: 'Taskbar', subtitle: 'Taskbar behaviours, system pin', icon: Icons.border_bottom, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const TaskbarScreen()))),
          SettingsCard(title: 'Desktop', subtitle: 'Icon size, double tap to sleep', icon: Icons.desktop_windows_outlined, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const DesktopSettingsScreen()))),
          SettingsCard(title: 'File manager', subtitle: 'Manage files, view styles', icon: Icons.snippet_folder_outlined, onTap: () => Navigator.push(innerContext, MaterialPageRoute(builder: (_) => const FileManagerScreen()))),
        ],
      ),
    );
  }
}