import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:installed_apps/app_info.dart';
import 'package:image_picker/image_picker.dart';
import 'launcher_state.dart';

class StartMenu extends StatefulWidget {
  final VoidCallback onPowerTapped;
  final VoidCallback onOverlaysClosed;

  const StartMenu({Key? key, required this.onPowerTapped, required this.onOverlaysClosed}) : super(key: key);
  @override
  State<StartMenu> createState() => _StartMenuState();
}

class _StartMenuState extends State<StartMenu> {
  String _currentView = 'List';
  bool _isPinnedExpanded = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  Widget _buildAppIcon(AppInfo app, LauncherState state, Color textColor, {bool isList = false}) {
    if (isList) {
      return InkWell(
        onTap: () { widget.onOverlaysClosed(); state.launchNativeApp(app.packageName!); },
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Row(
            children: [
              Container(width: 32, height: 32, decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)), child: Image.memory(app.icon!)),
              const SizedBox(width: 12),
              Expanded(child: Text(app.name!, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      );
    }
    return InkWell(
      onTap: () { widget.onOverlaysClosed(); state.launchNativeApp(app.packageName!); },
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]), child: Image.memory(app.icon!)),
          const SizedBox(height: 6),
          Flexible(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2.0), child: Text(app.name!, style: TextStyle(color: textColor, fontSize: 9.5), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center))),
        ],
      ),
    );
  }

  Widget _buildCategoryView(List<AppInfo> appsToCategorize, LauncherState state, Color textColor) {
    Map<String, List<AppInfo>> categorized = {};
    for (var app in appsToCategorize) {
      String firstLetter = app.name!.substring(0, 1).toUpperCase();
      if (!RegExp(r'[A-Z]').hasMatch(firstLetter)) firstLetter = '#';
      if (!categorized.containsKey(firstLetter)) categorized[firstLetter] = [];
      categorized[firstLetter]!.add(app);
    }
    final sortedKeys = categorized.keys.toList()..sort();

    return ListView.builder(
      shrinkWrap: true, physics: const BouncingScrollPhysics(), itemCount: sortedKeys.length,
      itemBuilder: (context, index) {
        String letter = sortedKeys[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0), child: Text(letter, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13))),
            ...categorized[letter]!.map((app) => _buildAppIcon(app, state, textColor, isList: true)).toList(),
            const Divider(color: Colors.white10),
          ],
        );
      },
    );
  }

  void _editProfile(LauncherState state, bool isDark) {
    TextEditingController nameController = TextEditingController(text: state.userName);
    Uint8List? tempImageBytes = state.userImageBytes; 
    final dialogBg = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: dialogBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: 160, 
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Edit Profile', style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () async {
                        try {
                          final picker = ImagePicker(); final image = await picker.pickImage(source: ImageSource.gallery);
                          if (image != null) { final bytes = await image.readAsBytes(); setDialogState(() => tempImageBytes = bytes); }
                        } catch (_) {}
                      },
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle), child: tempImageBytes != null ? ClipOval(child: Image.memory(tempImageBytes!, fit: BoxFit.cover, width: 56, height: 56)) : const Icon(Icons.person, size: 28, color: Colors.blueAccent)),
                          Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)), child: const Icon(Icons.camera_alt, size: 10, color: Colors.white)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController, style: TextStyle(color: textColor, fontSize: 11), textAlign: TextAlign.center, 
                      decoration: InputDecoration(labelText: "Display Name", labelStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 9), floatingLabelAlignment: FloatingLabelAlignment.center, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 6), enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)), focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent, width: 1.5))),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 10))), const SizedBox(width: 4),
                        TextButton(onPressed: () { state.saveProfile(nameController.text, tempImageBytes); Navigator.pop(context); }, child: const Text('Save', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 11))),
                      ],
                    )
                  ],
                ),
              ),
            ),
          );
        });
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    
    final bgColor = isDark ? const Color(0xFF242424) : Colors.white;
    final searchBg = isDark ? const Color(0xFF333333) : const Color(0xFFF3F3F3);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black45;
    final borderColor = isDark ? Colors.white10 : Colors.black.withOpacity(0.05);

    List<AppInfo> validApps = state.installedApps.where((app) => app.name != null && app.icon != null).toList();
    List<AppInfo> searchResults = validApps.where((app) => app.name!.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    List<AppInfo> pinnedApps = validApps.take(8).toList();
    List<AppInfo> mostUsedApps = validApps.skip(8).take(3).toList();
    List<AppInfo> allApps = validApps.skip(11).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.5 : 0.15), blurRadius: 20, offset: const Offset(0, 4))]),
      child: Column(
        mainAxisSize: MainAxisSize.max, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 36, decoration: BoxDecoration(color: searchBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: borderColor)),
            child: TextField(
              controller: _searchController, onChanged: (value) => setState(() => _searchQuery = value), style: TextStyle(color: textColor, fontSize: 12),
              decoration: InputDecoration(hintText: 'Search for apps, settings...', hintStyle: TextStyle(color: subTextColor, fontSize: 11), prefixIcon: Icon(Icons.search, color: subTextColor, size: 16), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 12), isDense: true),
            ),
          ),
          const SizedBox(height: 16),
          
          Expanded(
            child: state.isLoadingApps 
              ? const Center(child: CircularProgressIndicator(color: Colors.blue))
              : SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: _searchQuery.isNotEmpty 
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(padding: const EdgeInsets.only(left: 4.0, bottom: 8.0), child: Text('Best match', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 12))),
                          if (searchResults.isEmpty) Padding(padding: const EdgeInsets.all(16.0), child: Text("No apps found.", style: TextStyle(color: subTextColor))),
                          ...searchResults.map((app) => _buildAppIcon(app, state, textColor, isList: true)).toList(),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Padding(padding: const EdgeInsets.only(left: 4.0), child: Text('Pinned', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 12))),
                              InkWell(onTap: () => setState(() => _isPinnedExpanded = !_isPinnedExpanded), borderRadius: BorderRadius.circular(4), child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), child: Row(children: [Text(_isPinnedExpanded ? 'Show less' : 'Show more', style: TextStyle(color: subTextColor, fontSize: 10)), Icon(_isPinnedExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: subTextColor, size: 14)])))
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_isPinnedExpanded) GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 4, mainAxisSpacing: 12, crossAxisSpacing: 4, childAspectRatio: 0.75, children: pinnedApps.map((app) => _buildAppIcon(app, state, textColor, isList: false)).toList()),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Padding(padding: const EdgeInsets.only(left: 4.0), child: Text('All', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 12))),
                              Theme(
                                data: isDark ? ThemeData.dark() : ThemeData.light(),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    dropdownColor: bgColor, value: _currentView, icon: Icon(Icons.keyboard_arrow_down, size: 16, color: textColor), isDense: true, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w500),
                                    items: ['Category', 'Grid', 'List'].map((String value) => DropdownMenuItem<String>(value: value, child: Text('View: $value', style: TextStyle(color: textColor)))).toList(), onChanged: (newValue) => setState(() => _currentView = newValue!),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_currentView == 'Category') _buildCategoryView(allApps, state, textColor)
                          else ...[
                            Padding(padding: const EdgeInsets.only(left: 4.0, bottom: 8.0), child: Text('Most used', style: TextStyle(color: subTextColor, fontSize: 10, fontWeight: FontWeight.w500))),
                            if (_currentView == 'List') ...mostUsedApps.map((app) => _buildAppIcon(app, state, textColor, isList: true)).toList() else if (_currentView == 'Grid') GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 4, mainAxisSpacing: 12, crossAxisSpacing: 4, childAspectRatio: 0.75, children: mostUsedApps.map((app) => _buildAppIcon(app, state, textColor, isList: false)).toList()),
                            Divider(color: borderColor, height: 24),
                            if (_currentView == 'List') ...allApps.map((app) => _buildAppIcon(app, state, textColor, isList: true)).toList() else if (_currentView == 'Grid') GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 4, mainAxisSpacing: 12, crossAxisSpacing: 4, childAspectRatio: 0.75, children: allApps.map((app) => _buildAppIcon(app, state, textColor, isList: false)).toList()),
                          ],
                        ],
                      ),
                ),
          ),
          
          Divider(color: borderColor, height: 20),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => _editProfile(state, isDark), borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
                  child: Row(
                    children: [
                      Container(width: 28, height: 28, decoration: BoxDecoration(color: Colors.blueAccent.shade100, shape: BoxShape.circle), child: state.userImageBytes != null ? ClipOval(child: Image.memory(state.userImageBytes!, width: 28, height: 28, fit: BoxFit.cover)) : const Icon(Icons.person, size: 16, color: Colors.white)), const SizedBox(width: 8),
                      Text(state.userName, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              Theme(
                data: isDark ? ThemeData.dark() : ThemeData.light(),
                child: PopupMenuButton<String>(
                  icon: Icon(Icons.power_settings_new, color: textColor, size: 18), color: bgColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), offset: const Offset(0, -140), 
                  onSelected: (value) { if (value == 'Lock' || value == 'Shut down') widget.onPowerTapped(); },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(height: 30, value: 'Sleep', child: Text('Sleep', style: TextStyle(color: textColor, fontSize: 12))),
                    PopupMenuItem<String>(height: 30, value: 'Shut down', child: Text('Shut down', style: TextStyle(color: textColor, fontSize: 12))),
                    PopupMenuItem<String>(height: 30, value: 'Restart', child: Text('Restart', style: TextStyle(color: textColor, fontSize: 12))),
                    PopupMenuItem<String>(height: 30, value: 'Lock', child: Text('Lock', style: TextStyle(color: textColor, fontSize: 12))),
                  ],
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}