import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../states/theme_state.dart';
import '../../states/system_state.dart';
import '../../states/apps_state.dart';
import '../../states/desktop_state.dart';
import '../../states/monetization_state.dart';
import '../../services/native_bridge.dart';
import '../../services/lazy_app_icon.dart';
import '../../services/pro_gatekeeper.dart';

class SearchDashboard extends StatefulWidget {
  final List<String> recentQueries;
  final List<String> galleryImages;
  final List<Map<String, String>> infoSlides;
  final List<Map<String, String>> recentFiles;
  final int currentSlide;
  final Function(String) onQueryTap;
  final Function(String) onRemoveQuery;
  final Function(String) onRemoveRecentFile;

  const SearchDashboard({
    Key? key, 
    required this.recentQueries, 
    required this.galleryImages, 
    required this.infoSlides, 
    required this.recentFiles, 
    required this.currentSlide, 
    required this.onQueryTap, 
    required this.onRemoveQuery,
    required this.onRemoveRecentFile,
  }) : super(key: key);

  @override
  State<SearchDashboard> createState() => _SearchDashboardState();
}

class _SearchDashboardState extends State<SearchDashboard> {
  late PageController _pageController;
  Timer? _autoScrollTimer;
  Timer? _initialDelayTimer;
  int _activePageIndex = 0;
  bool _isUserInteractingWithSlider = false;
  Offset _lastTapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _startAutoScroll();
  }

  @override
  void didUpdateWidget(SearchDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.infoSlides.length != widget.infoSlides.length) {
      _startAutoScroll();
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _initialDelayTimer?.cancel();
    if (widget.infoSlides.length > 1) {
      _initialDelayTimer = Timer(const Duration(milliseconds: 2500), () {
        if (!mounted) return;
        _autoScrollTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
          if (_pageController.hasClients && !_isUserInteractingWithSlider) {
            int currentPage = _pageController.page?.round() ?? _activePageIndex;
            int nextPage = (currentPage + 1) % widget.infoSlides.length;
            _pageController.animateToPage(
              nextPage,
              duration: const Duration(milliseconds: 800),
              curve: Curves.fastOutSlowIn,
            );
          }
        });
      });
    }
  }

  void _pauseAutoScroll() {
    _isUserInteractingWithSlider = true;
    _initialDelayTimer?.cancel();
    _autoScrollTimer?.cancel();
  }

  void _resumeAutoScroll() {
    _isUserInteractingWithSlider = false;
    _startAutoScroll();
  }

  @override
  void dispose() {
    _initialDelayTimer?.cancel();
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildFileThumbnail(String path, String name, bool isDark) {
    final lower = name.toLowerCase();
    final isImage = lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp');

    if (isImage) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isDark ? Colors.white12 : Colors.black12, width: 0.8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          cacheWidth: 84,
          cacheHeight: 84,
          errorBuilder: (_, __, ___) => _buildFallbackBadge(lower, isDark),
        ),
      );
    }
    return _buildFallbackBadge(lower, isDark);
  }

  Widget _buildFallbackBadge(String lower, bool isDark) {
    IconData icon = Icons.description_outlined;
    Color color = Colors.blueAccent;
    Color bgColor = Colors.blueAccent.withOpacity(0.12);

    if (lower.endsWith('.pdf')) {
      icon = Icons.picture_as_pdf;
      color = Colors.redAccent;
      bgColor = Colors.redAccent.withOpacity(0.12);
    } else if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.m4a') || lower.endsWith('.aac') || lower.endsWith('.flac')) {
      icon = Icons.audio_file;
      color = Colors.amber.shade700;
      bgColor = Colors.amber.withOpacity(0.12);
    } else if (lower.endsWith('.mp4') || lower.endsWith('.mkv') || lower.endsWith('.mov') || lower.endsWith('.avi')) {
      icon = Icons.video_file;
      color = Colors.purpleAccent;
      bgColor = Colors.purpleAccent.withOpacity(0.12);
    } else if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      icon = Icons.description;
      color = Colors.blue.shade700;
      bgColor = Colors.blue.withOpacity(0.12);
    } else if (lower.endsWith('.xls') || lower.endsWith('.xlsx') || lower.endsWith('.csv')) {
      icon = Icons.table_chart;
      color = Colors.green.shade700;
      bgColor = Colors.green.withOpacity(0.12);
    } else if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      icon = Icons.slideshow;
      color = Colors.deepOrange;
      bgColor = Colors.deepOrange.withOpacity(0.12);
    } else if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z')) {
      icon = Icons.folder_zip;
      color = Colors.orangeAccent;
      bgColor = Colors.orangeAccent.withOpacity(0.12);
    } else if (lower.endsWith('.txt')) {
      icon = Icons.text_snippet_outlined;
      color = isDark ? Colors.white70 : Colors.black54;
      bgColor = (isDark ? Colors.white : Colors.black).withOpacity(0.08);
    }

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, color: color, size: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final appsState = context.watch<AppsState>();
    final systemState = context.watch<SystemState>();
    final desktopState = context.watch<DesktopState>();
    final isDark = themeState.isDarkMode;
    
    final cardBg = isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03);
    final popMenuBg = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;

    final now = DateTime.now();
    String greeting = "Good morning";
    if (now.hour >= 12 && now.hour < 17) greeting = "Good afternoon";
    else if (now.hour >= 17) greeting = "Good evening";
    final firstName = systemState.userName.split(' ').first;
    
    final double scale = desktopState.desktopIconScale.clamp(0.6, 1.8);
    final double baseSize = 32.0 * scale;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            physics: const BouncingScrollPhysics(),
            children: [
              Padding(padding: const EdgeInsets.only(left: 8, bottom: 8), child: Text('Recent', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13))),
              ...appsState.recentApps.take(4).map((pkg) {
                final appInfoMatches = appsState.installedApps.where((a) => a.packageName == pkg);
                if (appInfoMatches.isEmpty) return const SizedBox.shrink();
                final app = appInfoMatches.first;
                
                Widget appIconWidget = LazyAppIcon(packageName: pkg, size: baseSize);

                if (themeState.cachedIconsPath != null && File('${themeState.cachedIconsPath}/$pkg.png').existsSync()) {
                  appIconWidget = Image.file(File('${themeState.cachedIconsPath}/$pkg.png'), width: baseSize, height: baseSize, gaplessPlayback: true);
                }
                
                return Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () { appsState.launchNativeApp(pkg); },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Row(
                        children: [
                          appIconWidget,
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(app.name ?? pkg, style: TextStyle(color: textColor, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
              if (appsState.recentApps.isNotEmpty && widget.recentQueries.where((q) => q.trim().isNotEmpty).isNotEmpty) 
                const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Divider(height: 1, thickness: 0.5)),
              ...widget.recentQueries.where((q) => q.trim().isNotEmpty).take(6).map((q) => Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => widget.onQueryTap(q),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.history, color: subTextColor, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(q, style: TextStyle(color: textColor, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        InkWell(
                          onTap: () => widget.onRemoveQuery(q),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(Icons.close, color: subTextColor, size: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )).toList(),
            ],
          )
        ),
        Container(width: 1, color: borderColor),
        Expanded(
          flex: 6,
          child: ListView(
            padding: const EdgeInsets.all(12),
            physics: const BouncingScrollPhysics(),
            children: [
              Text('$greeting, $firstName', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 12),
              
              _ProLockedCardWrapper(
                featureName: 'Camera Memories',
                child: widget.galleryImages.isNotEmpty
                  ? InkWell(
                      onTap: () {
                        final path = widget.galleryImages[widget.currentSlide % widget.galleryImages.length];
                        NativeBridge.instance.openFile(path);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 120, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)), clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(seconds: 1), 
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey(widget.galleryImages[widget.currentSlide % widget.galleryImages.length]),
                                tween: Tween<double>(begin: 1.0, end: 1.15),
                                duration: const Duration(seconds: 10),
                                builder: (context, scale, child) {
                                  return Transform.scale(
                                    scale: scale, 
                                    child: Image.file(
                                       File(widget.galleryImages[widget.currentSlide % widget.galleryImages.length]), 
                                       fit: BoxFit.cover, 
                                       width: double.infinity, 
                                       height: double.infinity,
                                       cacheWidth: 400,
                                    )
                                  );
                                },
                              )
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                                  stops: const [0.4, 1.0]
                                )
                              )
                            ),
                            Positioned(bottom: 12, left: 12, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [Text('From your Camera', style: TextStyle(color: Colors.white70, fontSize: 10)), SizedBox(height: 2), Text('Memories', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))]))
                          ]
                        )
                      ),
                    )
                  : Container(height: 120, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), image: DecorationImage(image: AssetImage(themeState.actualWallpaperUrl.startsWith('assets/') ? themeState.actualWallpaperUrl : 'assets/wallpapers/theme_sunrise.jpg'), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.4), BlendMode.darken))), padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: const [Text('Image of the day', style: TextStyle(color: Colors.white70, fontSize: 10)), SizedBox(height: 2), Text('Enable Storage Permission for Camera', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))])),
              ),
              
              const SizedBox(height: 12),
              
              if (widget.infoSlides.isNotEmpty)
                _ProLockedCardWrapper(
                  featureName: 'Live Sports & News Feed',
                  child: SizedBox(
                    height: 164,
                    child: Listener(
                      onPointerDown: (_) => _pauseAutoScroll(),
                      onPointerUp: (_) => _resumeAutoScroll(),
                      onPointerCancel: (_) => _resumeAutoScroll(),
                      child: Stack(
                        children: [
                          PageView.builder(
                            controller: _pageController,
                            physics: const BouncingScrollPhysics(),
                            itemCount: widget.infoSlides.length,
                            onPageChanged: (index) {
                              setState(() => _activePageIndex = index);
                            },
                            itemBuilder: (context, index) {
                              final slide = widget.infoSlides[index];
                              
                              IconData icon = Icons.article_outlined;
                              Color iconColor = Colors.blueAccent;
                              
                              if (slide['type'] == 'Tech News') { icon = Icons.memory; iconColor = Colors.purpleAccent; } 
                              else if (slide['type'] == 'Global News') { icon = Icons.public; iconColor = Colors.lightBlueAccent; } 
                              else if (slide['type'] == 'Sports News') { icon = Icons.directions_run; iconColor = Colors.orangeAccent; } 
                              else if (slide['type'] == 'Live Match' || slide['type'] == 'Upcoming Match' || slide['type'] == 'Full Time') { icon = Icons.sports_soccer; iconColor = Colors.greenAccent; }
  
                              return Container(
                                decoration: BoxDecoration(color: const Color(0xFF161616), borderRadius: BorderRadius.circular(8), border: Border.all(color: borderColor)), clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: (slide['logo1'] != null)
                                        ? Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                            children: [
                                              if (slide['logo1']!.isNotEmpty) 
                                                Transform.scale(
                                                  scale: 1.4, 
                                                  child: Opacity(
                                                    opacity: 0.25, 
                                                    child: CachedNetworkImage(
                                                      imageUrl: slide['logo1']!, 
                                                      width: 60,
                                                      memCacheWidth: 120,
                                                      errorWidget: (context, url, error) => const SizedBox.shrink(),
                                                    )
                                                  )
                                                ),
                                              if (slide['logo2']!.isNotEmpty) 
                                                Transform.scale(
                                                  scale: 1.4, 
                                                  child: Opacity(
                                                    opacity: 0.25, 
                                                    child: CachedNetworkImage(
                                                      imageUrl: slide['logo2']!, 
                                                      width: 60,
                                                      memCacheWidth: 120,
                                                      errorWidget: (context, url, error) => const SizedBox.shrink(),
                                                    )
                                                  )
                                                ),
                                            ],
                                          )
                                        : CachedNetworkImage(
                                            imageUrl: slide['image'] ?? '', 
                                            fit: BoxFit.cover,
                                            memCacheWidth: 400,
                                            memCacheHeight: 250,
                                            errorWidget: (context, url, error) => const SizedBox.shrink(),
                                          ),
                                    ),
                                    Positioned.fill(
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [Colors.black38, Colors.black87],
                                            stops: [0.0, 0.8],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 12, top: 12, right: 12, bottom: 20),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [Icon(icon, color: iconColor, size: 14), const SizedBox(width: 6), Text(slide['type']!, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600))]), const SizedBox(height: 8),
                                          Text(slide['title']!, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 4),
                                          Expanded(child: Text(slide['subtitle']!, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis)),
                                          
                                          Material(
                                            color: Colors.white24,
                                            borderRadius: BorderRadius.circular(4),
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(4),
                                              onTap: () {
                                                NativeBridge.instance.launchApp(slide['url']!);
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12), 
                                                alignment: Alignment.center, 
                                                child: const Text('Read More', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                          ),
                          if (widget.infoSlides.length > 1)
                            Positioned(
                              bottom: 8,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(widget.infoSlides.length, (index) {
                                  bool isActive = _activePageIndex == index;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                                    height: 4,
                                    width: isActive ? 14 : 4,
                                    decoration: BoxDecoration(
                                      color: isActive ? Colors.white : Colors.white.withOpacity(0.4),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  );
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              
              const SizedBox(height: 12),
              
              _ProLockedCardWrapper(
                featureName: 'Recent Work Files',
                child: Container(
                  padding: const EdgeInsets.all(10), 
                  decoration: BoxDecoration(
                    color: cardBg, 
                    borderRadius: BorderRadius.circular(8), 
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Continue Working', style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w600)), 
                      const SizedBox(height: 6),
                      if (widget.recentFiles.isEmpty)
                         Padding(
                           padding: const EdgeInsets.symmetric(vertical: 8.0),
                           child: Text('No recent files found.', style: TextStyle(color: subTextColor, fontSize: 11)),
                         )
                      else
                        ...widget.recentFiles.map((f) {
                          return Material(
                            type: MaterialType.transparency,
                            child: Listener(
                              onPointerDown: (e) => _lastTapPosition = e.position,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: () {
                                  NativeBridge.instance.openFile(f['path']!);
                                },
                                onLongPress: () {
                                  showMenu<String>(
                                     context: context,
                                     position: RelativeRect.fromLTRB(_lastTapPosition.dx, _lastTapPosition.dy, _lastTapPosition.dx, _lastTapPosition.dy),
                                     color: popMenuBg,
                                     elevation: 8,
                                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: borderColor)),
                                     items: [
                                        PopupMenuItem(value: 'share', height: 32, padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [Icon(Icons.share_outlined, size: 16, color: textColor), const SizedBox(width: 12), Text('Share', style: TextStyle(color: textColor, fontSize: 13))])),
                                        PopupMenuItem(value: 'delete', height: 32, padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent), const SizedBox(width: 12), const Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 13))])),
                                        PopupMenuItem(value: 'location', height: 32, padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [Icon(Icons.folder_open, size: 16, color: textColor), const SizedBox(width: 12), Text('Open file location', style: TextStyle(color: textColor, fontSize: 13))])),
                                        PopupMenuItem(value: 'remove', height: 32, padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [const Icon(Icons.close, size: 16, color: Colors.redAccent), const SizedBox(width: 12), const Text('Remove from list', style: TextStyle(color: Colors.redAccent, fontSize: 13))])),
                                     ]
                                   ).then((val) {
                                     if (!context.mounted) return;
                                     if (val == 'share') {
                                       NativeBridge.instance.shareFile(f['path']!);
                                     } else if (val == 'delete') {
                                       final file = File(f['path']!);
                                       showDialog(
                                         context: context,
                                         builder: (ctx) => AlertDialog(
                                           backgroundColor: popMenuBg,
                                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                           title: Text('Delete File?', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                                           content: Text('Are you sure you want to permanently delete "${f['name']}"?', style: TextStyle(color: subTextColor, fontSize: 13)),
                                           actions: [
                                             TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: subTextColor))),
                                             TextButton(
                                               onPressed: () async {
                                                 Navigator.pop(ctx);
                                                 try {
                                                   if (await file.exists()) {
                                                     await file.delete();
                                                     widget.onRemoveRecentFile(f['path']!);
                                                     appsState.triggerExplorerRefresh();
                                                     if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File deleted successfully')));
                                                   }
                                                 } catch (e) {
                                                   if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete file. Check permissions.')));
                                                 }
                                               },
                                               child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                             ),
                                           ],
                                         ),
                                       );
                                     } else if (val == 'location') {
                                       final file = File(f['path']!);
                                       final dirPath = file.parent.path;
                                       appsState.highlightFileName = file.path.split('/').last; 
                                       appsState.requestExplorerNavigation(dirPath);
                                       Navigator.of(context).pop();
                                     } else if (val == 'remove') {
                                       widget.onRemoveRecentFile(f['path']!);
                                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from recent files'), duration: Duration(seconds: 1)));
                                     }
                                   });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 3.5),
                                  child: Row(
                                    children: [
                                      _buildFileThumbnail(f['path']!, f['name']!, isDark),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          f['name']!, 
                                          maxLines: 1, 
                                          overflow: TextOverflow.ellipsis, 
                                          style: TextStyle(color: textColor, fontSize: 11.5, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 12),
              
              _ProLockedCardWrapper(
                featureName: 'Copilot AI Assistant',
                child: Container(
                  padding: const EdgeInsets.all(10), 
                  decoration: BoxDecoration(
                    color: cardBg, 
                    borderRadius: BorderRadius.circular(8), 
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Productivity & AI', style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w600)), const SizedBox(height: 8),
                      Container(
                        height: 38,
                        decoration: BoxDecoration(color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(18), border: Border.all(color: borderColor, width: 0.5)),
                        child: Center(
                          child: TextField(
                            textAlign: TextAlign.start,
                            textAlignVertical: TextAlignVertical.center,
                            style: TextStyle(fontSize: 12, color: textColor),
                            decoration: InputDecoration(
                              isDense: true,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: 'Ask Copilot/ChatGPT...',
                              hintStyle: TextStyle(fontSize: 12, color: subTextColor),
                              border: InputBorder.none,
                              prefixIcon: const Icon(Icons.auto_awesome, size: 16, color: Colors.purpleAccent),
                              prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 38),
                            ),
                            onSubmitted: (val) {
                              if (val.isNotEmpty) {
                                NativeBridge.instance.launchApp('https://chatgpt.com/?q=${Uri.encodeComponent(val)}');
                              }
                            }
                          ),
                        )
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProLockedCardWrapper extends StatelessWidget {
  final Widget child;
  final String featureName;

  const _ProLockedCardWrapper({
    Key? key,
    required this.child,
    required this.featureName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final systemState = context.watch<SystemState>();
    final monetization = context.watch<MonetizationState>();
    final isPro = systemState.isActivated || monetization.isPro;

    if (isPro) return child;

    return Stack(
      children: [
        AbsorbPointer(
          absorbing: true,
          child: Opacity(
            opacity: 0.35,
            child: child,
          ),
        ),
        Positioned.fill(
          child: InkWell(
            onTap: () => ProGatekeeper.checkAccess(context, featureName: featureName),
            borderRadius: BorderRadius.circular(8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amber.shade400, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.lock_outline, size: 14, color: Colors.amber),
                    SizedBox(width: 6),
                    Text(
                      'Unlock with Pro',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}