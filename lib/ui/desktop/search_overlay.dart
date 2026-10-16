import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart' as xml;

import '../../states/desktop_state.dart';
import '../../states/theme_state.dart';
import '../../states/apps_state.dart';
import '../../services/native_bridge.dart';
import '../../services/lazy_app_icon.dart';
import 'dashboard_panels.dart'; 
import '../shared/acrylic_container.dart';

dynamic _isolateJsonDecode(String source) => jsonDecode(source);

List<Map<String, String>> _isolateParseXmlNews(Map<String, dynamic> args) {
  final String xmlString = args['xml'];
  final String type = args['type'];
  final String subtitle = args['subtitle'];
  final String defaultImg = args['defaultImg'];
  final List<Map<String, String>> slides = [];

  try {
    String cleanXml = xmlString;
    final startIdx = cleanXml.indexOf('<');
    if (startIdx > 0) cleanXml = cleanXml.substring(startIdx);

    final document = xml.XmlDocument.parse(cleanXml);
    final items = document.findAllElements('item');

    for (var itemXml in items) {
      final pubDateElements = itemXml.findElements('pubDate');
      final pubDateStr = pubDateElements.isNotEmpty ? pubDateElements.first.innerText : '';

      String img = '';
      final mediaContents = itemXml.findAllElements('media:content');
      if (mediaContents.isNotEmpty) {
        img = mediaContents.first.getAttribute('url') ?? '';
      } else {
        final enclosures = itemXml.findAllElements('enclosure');
        if (enclosures.isNotEmpty) {
          img = enclosures.first.getAttribute('url') ?? '';
        } else {
          final thumbnails = itemXml.findAllElements('media:thumbnail');
          if (thumbnails.isNotEmpty) img = thumbnails.first.getAttribute('url') ?? '';
        }
      }
      if (img.isEmpty) img = defaultImg;

      final titleElements = itemXml.findElements('title');
      final linkElements = itemXml.findElements('link');
      final title = titleElements.isNotEmpty ? titleElements.first.innerText : '';
      final link = linkElements.isNotEmpty ? linkElements.first.innerText : '';

      slides.add({
        'type': type,
        'title': title.replaceAll('&amp;', '&').replaceAll('&#8217;', "'").replaceAll('&quot;', '"'),
        'subtitle': subtitle,
        'url': link,
        'image': img.replaceFirst('http://', 'https://'),
        'published_at': pubDateStr,
      });
      
      if (slides.length >= 5) break; 
    }
  } catch (e) {
    debugPrint("XML Parse Error in Isolate: $e");
  }
  return slides;
}

Future<List<Map<String, dynamic>>> _scanRecentFilesIsolate(Map<String, dynamic> params) async {
  final List<String> targetPaths = params['targetPaths'];
  final Set<String> hiddenFiles = Set<String>.from(params['hiddenFiles']);
  
  List<Map<String, dynamic>> results = [];
  final Set<String> extensions = {
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.csv',
    '.mp3', '.m4a', '.wav', '.aac', '.ogg', '.flac', 
    '.mp4', '.mkv', '.avi', '.mov', 
    '.jpg', '.png', '.jpeg', '.webp'
  };
  
  for (String basePath in targetPaths) {
    final dir = Directory(basePath);
    if (!dir.existsSync()) continue;
    
    void walkSafely(Directory currentDir, int depth) {
      if (depth > 4) return; 
      try {
        final dirName = currentDir.path.split('/').last.toLowerCase();
        if (dirName == 'android' || dirName == 'data' || dirName == 'cache') return;

        final list = currentDir.listSync(followLinks: false);
        
        for (final entity in list) {
           if (entity is File && entity.path.split('/').last == '.nomedia') return;
        }

        for (final entity in list) {
          final name = entity.path.split('/').last;
          if (name.startsWith('.')) continue; 
          
          if (entity is Directory) {
            walkSafely(entity, depth + 1);
          } else if (entity is File) {
            final lowerName = name.toLowerCase();
            final dotIdx = lowerName.lastIndexOf('.');
            if (dotIdx != -1) {
              final ext = lowerName.substring(dotIdx);
              if (extensions.contains(ext)) {
                if (!hiddenFiles.contains(entity.path)) {
                  try {
                    final stat = entity.statSync();
                    if (DateTime.now().difference(stat.modified).inDays <= 60) {
                      results.add({
                        'path': entity.path,
                        'name': name,
                        'modified': stat.modified.millisecondsSinceEpoch,
                      });
                    }
                  } catch (_) {}
                }
              }
            }
          }
        }
      } catch (_) {}
    }
    
    walkSafely(dir, 0);
  }
  
  results.sort((a, b) => (b['modified'] as int).compareTo(a['modified'] as int));
  
  return results.take(20).toList();
}

class SearchDataSync {
  static final ValueNotifier<List<Map<String, String>>> infoSlides = ValueNotifier([]);
  static DateTime? _lastApiFetch;
  static bool _isFetching = false;
  static Timer? _backgroundTimer;

  static final Set<String> _marqueeTeams = {
    'arsenal', 'manchester city', 'man city', 'liverpool', 'manchester united', 'man utd', 'chelsea', 'tottenham', 'newcastle', 'aston villa',
    'real madrid', 'barcelona', 'atlético madrid', 'atletico madrid', 'athletic club', 'real sociedad', 'girona', 'sevilla',
    'inter', 'inter milan', 'ac milan', 'milan', 'juventus', 'napoli', 'roma', 'atalanta', 'lazio',
    'bayern munich', 'bayern münchen', 'borussia dortmund', 'dortmund', 'bayer leverkusen', 'leverkusen', 'rb leipzig', 'leipzig',
    'paris saint-germain', 'psg', 'marseille', 'monaco', 'lyon', 'lille',
    'england', 'france', 'spain', 'germany', 'italy', 'portugal', 'netherlands', 'belgium', 'croatia', 'denmark', 'switzerland', 'brazil', 'argentina', 'uruguay', 'nigeria', 'greece', 'norway', 'sweden', 'austria', 'poland', 'wales', 'scotland', 'ireland', 'usa', 'mexico'
  };

  static Future<void> startBackgroundTimer() async {
    _backgroundTimer?.cancel();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString('cached_search_data');
      if (cachedStr != null) {
        final decoded = jsonDecode(cachedStr) as List;
        infoSlides.value = decoded.map((e) => Map<String, String>.from(e)).toList();
      }
    } catch (_) {}

    await fetchLiveNewsAndScores();
  }

  static void _scheduleNextTick() {
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer(const Duration(minutes: 5), () async {
      await fetchLiveNewsAndScores();
    });
  }

  static DateTime? parseRssDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final str = raw.trim();

    DateTime? parsed = DateTime.tryParse(str);
    if (parsed != null) return parsed.toLocal();

    try {
      final months = {
        'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
        'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
      };

      String cleaned = str;
      if (cleaned.contains(',')) {
        cleaned = cleaned.substring(cleaned.indexOf(',') + 1).trim();
      }

      final parts = cleaned.split(RegExp(r'\s+'));
      if (parts.length >= 4) {
        final day = int.tryParse(parts[0]);
        final monthStr = parts[1].toLowerCase();
        final month = months[monthStr];
        final year = int.tryParse(parts[2]);
        final timeParts = parts[3].split(':');

        if (day != null && month != null && year != null && timeParts.length >= 2) {
          final hour = int.tryParse(timeParts[0]) ?? 0;
          final minute = int.tryParse(timeParts[1]) ?? 0;
          final second = timeParts.length > 2 ? (int.tryParse(timeParts[2]) ?? 0) : 0;

          int offsetMinutes = 0;
          if (parts.length >= 5) {
            final tzStr = parts[4].toUpperCase();
            if (tzStr == 'GMT' || tzStr == 'UTC') {
              offsetMinutes = 0;
            } else if (RegExp(r'^[+-]\d{4}$').hasMatch(tzStr)) {
              final sign = tzStr.startsWith('-') ? -1 : 1;
              final tzH = int.tryParse(tzStr.substring(1, 3)) ?? 0;
              final tzM = int.tryParse(tzStr.substring(3, 5)) ?? 0;
              offsetMinutes = sign * (tzH * 60 + tzM);
            }
          }

          final utc = DateTime.utc(year, month, day, hour, minute, second).subtract(Duration(minutes: offsetMinutes));
          return utc.toLocal();
        }
      }
    } catch (_) {}
    return null;
  }

  static bool isItemExpired(DateTime? publishedAt, {int maxHours = 24}) {
    if (publishedAt == null) return false;
    final diff = DateTime.now().difference(publishedAt);
    return diff.inHours >= maxHours || (diff.isNegative && diff.inHours < -12);
  }

  static Future<void> fetchLiveNewsAndScores() async {
    if (_isFetching) return;
    _isFetching = true;
    final now = DateTime.now();

    int debounceMinutes = infoSlides.value.any((s) => s['type'] == 'Live Match') ? 2 : 5;

    if (infoSlides.value.isNotEmpty && _lastApiFetch != null && now.difference(_lastApiFetch!).inMinutes < debounceMinutes) {
      final currentList = List<Map<String, String>>.from(infoSlides.value);
      currentList.removeWhere((slide) {
        final date = parseRssDate(slide['published_at']);
        if (date == null) return false;
        final ageMinutes = now.difference(date).inMinutes;
        return slide['type'] == 'Full Time' ? ageMinutes >= 240 : ageMinutes >= (24 * 60);
      });
      
      if (currentList.length != infoSlides.value.length) {
        infoSlides.value = currentList;
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString('cached_search_data', jsonEncode(currentList));
        });
      }
      _isFetching = false;
      _scheduleNextTick();
      return;
    }

    try {
      final List<Map<String, String>> matchSlides = [];
      final List<Map<String, String>> newsSlides = [];

      final client = http.Client();
      
      final List<String> targetLeagues = [
        'eng.1', 'esp.1', 'ita.1', 'ger.1', 'fra.1', 'uefa.champions', 'uefa.europa', 'uefa.nations', 'fifa.friendly',
      ];

      final responses = await Future.wait(
        targetLeagues.map((leagueCode) => 
          client.get(Uri.parse('https://site.api.espn.com/apis/site/v2/sports/soccer/$leagueCode/scoreboard'))
                .timeout(const Duration(seconds: 8))
        )
      );

      final Set<String> seenMatchIds = {};
      final List<Map<String, dynamic>> liveMatches = [];
      final List<Map<String, dynamic>> postMatches = [];
      final Map<String, List<Map<String, dynamic>>> upcomingByLeague = {};

      for (int i = 0; i < responses.length; i++) {
        final res = responses[i];
        final currentLeagueCode = targetLeagues[i];

        if (res.statusCode == 200) {
          final data = await compute(_isolateJsonDecode, res.body);
          
          String leagueName = 'Football';
          if (data['leagues'] != null && (data['leagues'] as List).isNotEmpty) {
            leagueName = data['leagues'][0]['name'] ?? data['leagues'][0]['shortName'] ?? 'Football';
          }

          final events = data['events'] as List?;
          if (events != null) {
            for (var event in events) {
              final eventId = event['id']?.toString() ?? '';
              if (eventId.isNotEmpty && seenMatchIds.contains(eventId)) continue;
              if (eventId.isNotEmpty) seenMatchIds.add(eventId);

              final competitions = event['competitions'] as List?;
              if (competitions == null || competitions.isEmpty) continue;
              final comp = competitions[0];

              final rawStatus = comp['status'];
              String state = 'pre';
              String detail = '';
              String clock = '';

              if (rawStatus is Map) {
                clock = rawStatus['displayClock']?.toString() ?? '';
                final typeObj = rawStatus['type'];
                if (typeObj is Map) {
                  state = typeObj['state']?.toString() ?? 'pre';
                  detail = typeObj['detail']?.toString() ?? '';
                } else {
                  state = rawStatus['state']?.toString() ?? 'pre';
                }
              } else if (rawStatus is String) {
                state = rawStatus; 
              }
              
              if (state.toLowerCase().contains('postpone') || state.toLowerCase().contains('cancel') || state.toLowerCase().contains('delay')) continue;

              final comps = comp['competitors'] as List?;
              if (comps != null && comps.length >= 2) {
                final team1 = comps[0];
                final team2 = comps[1];

                final dateStr = event['date']?.toString();
                final eventDate = parseRssDate(dateStr) ?? DateTime.tryParse(dateStr ?? '')?.toLocal();
                
                int minutesSinceStart = eventDate != null ? now.difference(eventDate).inMinutes : 0;

                if (state == 'pre') {
                   if (minutesSinceStart < -7200) continue; 
                   if (minutesSinceStart > 180) continue;   
                } else if (state == 'in') {
                   if (minutesSinceStart > 300) continue;   
                } else if (state == 'post') {
                   if (minutesSinceStart > 240) continue;  
                }

                String matchType = 'Upcoming Match';
                int sortPriority = 2;

                if (state == 'in') {
                  matchType = 'Live Match';
                  sortPriority = 1;
                } else if (state == 'post') {
                  matchType = 'Full Time';
                  sortPriority = 3;
                }

                String scoreStr = '';
                if (state != 'pre') {
                  final score1 = team1['score']?.toString() ?? '0';
                  final score2 = team2['score']?.toString() ?? '0';
                  scoreStr = '$score1 - $score2';
                }

                String timePrompt = '';
                if (eventDate != null) {
                  final isToday = eventDate.year == now.year && eventDate.month == now.month && eventDate.day == now.day;
                  final isTomorrow = eventDate.year == now.year && eventDate.month == now.month && eventDate.day == now.day + 1;
                  int h = eventDate.hour % 12 == 0 ? 12 : eventDate.hour % 12;
                  String p = eventDate.hour >= 12 ? 'PM' : 'AM';
                  String m = eventDate.minute.toString().padLeft(2, '0');
                  String dayLabel = isToday ? 'Today' : (isTomorrow ? 'Tomorrow' : '${eventDate.month}/${eventDate.day}');
                  timePrompt = '$dayLabel at $h:$m $p';
                }

                String subtitle = leagueName;
                if (state == 'in') {
                  String timeIndicator = clock.isNotEmpty ? clock : (detail.isNotEmpty ? detail : 'LIVE');
                  subtitle = '$scoreStr • $timeIndicator ($leagueName)';
                } else if (state == 'post') {
                  subtitle = 'FT: $scoreStr • $leagueName';
                } else if (timePrompt.isNotEmpty) {
                  subtitle = '$timePrompt • $leagueName';
                }

                final t1 = team1['team'] ?? team1;
                final t2 = team2['team'] ?? team2;

                String logo1 = t1['logo']?.toString() ?? '';
                if (logo1.isEmpty && t1['logos'] is List && (t1['logos'] as List).isNotEmpty) {
                  logo1 = t1['logos'][0]['href']?.toString() ?? '';
                }

                String logo2 = t2['logo']?.toString() ?? '';
                if (logo2.isEmpty && t2['logos'] is List && (t2['logos'] as List).isNotEmpty) {
                  logo2 = t2['logos'][0]['href']?.toString() ?? '';
                }

                final name1 = t1['shortDisplayName'] ?? t1['displayName'] ?? t1['name'] ?? 'TBA';
                final name2 = t2['shortDisplayName'] ?? t2['displayName'] ?? t2['name'] ?? 'TBA';
                final matchTitle = '$name1 vs $name2';

                int excitement = 0;
                final n1 = name1.toString().toLowerCase();
                final n2 = name2.toString().toLowerCase();
                if (_marqueeTeams.any((t) => n1.contains(t))) excitement += 2;
                if (_marqueeTeams.any((t) => n2.contains(t))) excitement += 2;

                final matchData = {
                  'type': matchType,
                  'title': matchTitle,
                  'subtitle': subtitle,
                  'url': 'https://www.google.com/search?q=${Uri.encodeComponent(matchTitle)}',
                  'image': '',
                  'logo1': logo1.replaceFirst('http://', 'https://'),
                  'logo2': logo2.replaceFirst('http://', 'https://'),
                  'published_at': (eventDate ?? now).toIso8601String(),
                  '_sortPriority': sortPriority,
                  '_eventDateEpoch': eventDate?.millisecondsSinceEpoch ?? now.millisecondsSinceEpoch,
                  '_excitement': excitement,
                  '_leagueCode': currentLeagueCode,
                };

                if (state == 'in') {
                  liveMatches.add(matchData);
                } else if (state == 'post') {
                  postMatches.add(matchData);
                } else if (state == 'pre') {
                  if (!upcomingByLeague.containsKey(currentLeagueCode)) {
                    upcomingByLeague[currentLeagueCode] = [];
                  }
                  upcomingByLeague[currentLeagueCode]!.add(matchData);
                }
              }
            }
          }
        }
      }

      final List<Map<String, dynamic>> curatedUpcoming = [];
      upcomingByLeague.forEach((leagueCode, fixtures) {
        fixtures.sort((a, b) {
          int eA = a['_excitement'] as int;
          int eB = b['_excitement'] as int;
          if (eA != eB) return eB.compareTo(eA);

          int tA = a['_eventDateEpoch'] as int;
          int tB = b['_eventDateEpoch'] as int;
          return tA.compareTo(tB); 
        });
        curatedUpcoming.addAll(fixtures.take(2));
      });

      final List<Map<String, dynamic>> combinedMatches = [
        ...liveMatches,
        ...curatedUpcoming,
        ...postMatches.take(4),
      ];

      combinedMatches.sort((a, b) {
        int pA = a['_sortPriority'] as int;
        int pB = b['_sortPriority'] as int;
        if (pA != pB) return pA.compareTo(pB);

        int timeA = a['_eventDateEpoch'] as int;
        int timeB = b['_eventDateEpoch'] as int;
        
        if (pA == 3) {
          return timeB.compareTo(timeA); 
        } else {
          return timeA.compareTo(timeB); 
        }
      });

      for (var match in combinedMatches.take(20)) {
        matchSlides.add({
          'type': match['type'].toString(),
          'title': match['title'].toString(),
          'subtitle': match['subtitle'].toString(),
          'url': match['url'].toString(),
          'image': match['image'].toString(),
          'logo1': match['logo1'].toString(),
          'logo2': match['logo2'].toString(),
          'published_at': match['published_at'].toString(),
        });
      }

      final res1 = await client.get(Uri.parse('https://techcrunch.com/feed/')).timeout(const Duration(seconds: 6));
      if (res1.statusCode == 200 && res1.body.trim().startsWith('<') && !res1.body.toLowerCase().contains('<!doctype html>')) {
        final parsedSlides = await compute(_isolateParseXmlNews, {
          'xml': res1.body,
          'type': 'Tech News',
          'subtitle': 'TechCrunch • Fresh updates',
          'defaultImg': 'https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=500&q=80',
        });
        for (var slide in parsedSlides) {
          final pubDate = parseRssDate(slide['published_at']);
          if (isItemExpired(pubDate, maxHours: 24)) continue;
          slide['published_at'] = (pubDate ?? now).toIso8601String();
          newsSlides.add(slide);
          if (newsSlides.where((s) => s['type'] == 'Tech News').length >= 1) break;
        }
      }

      final res2 = await client.get(Uri.parse('https://feeds.bbci.co.uk/news/world/rss.xml')).timeout(const Duration(seconds: 6));
      if (res2.statusCode == 200 && res2.body.trim().startsWith('<') && !res2.body.toLowerCase().contains('<!doctype html>')) {
        final parsedSlides = await compute(_isolateParseXmlNews, {
          'xml': res2.body,
          'type': 'Global News',
          'subtitle': 'BBC News • Global coverage',
          'defaultImg': 'https://images.unsplash.com/photo-1495020689067-958852a7765e?auto=format&fit=crop&w=500&q=80',
        });
        for (var slide in parsedSlides) {
          final pubDate = parseRssDate(slide['published_at']);
          if (isItemExpired(pubDate, maxHours: 24)) continue;
          slide['published_at'] = (pubDate ?? now).toIso8601String();
          newsSlides.add(slide);
          if (newsSlides.where((s) => s['type'] == 'Global News').length >= 1) break;
        }
      }

      final List<Map<String, String>> finalSlides = [...matchSlides, ...newsSlides];

      if (finalSlides.isEmpty) {
        finalSlides.addAll([
          {
            'type': 'Tech News',
            'title': 'The future of mobile desktop computing',
            'subtitle': 'Tech Insights • Explore how launchers are evolving',
            'url': 'https://techcrunch.com',
            'image': 'https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=500&q=80',
            'published_at': now.toIso8601String(),
          },
          {
            'type': 'Global News',
            'title': 'Global markets shift rapidly in Q4',
            'subtitle': 'BBC News • Analysis and updates',
            'url': 'https://bbc.com/news',
            'image': 'https://images.unsplash.com/photo-1495020689067-958852a7765e?auto=format&fit=crop&w=500&q=80',
            'published_at': now.toIso8601String(),
          }
        ]);
      }

      infoSlides.value = finalSlides;
      _lastApiFetch = now;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_search_data', jsonEncode(finalSlides));
      
      client.close();
    } catch (e) {
      debugPrint("API Sync Error: $e");
    } finally {
      _isFetching = false;
      _scheduleNextTick(); 
    }
  }
}

class AppSearchOverlay extends StatefulWidget {
  final double width;
  final List<AppInfo> installedApps;
  final bool isDark;
  final Color accentColor;

  const AppSearchOverlay({
    Key? key, 
    required this.width,
    required this.installedApps, 
    required this.isDark, 
    required this.accentColor
  }) : super(key: key);

  @override
  State<AppSearchOverlay> createState() => _AppSearchOverlayState();
}

class _AppSearchOverlayState extends State<AppSearchOverlay> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(); 
  
  Timer? _debounce;
  Timer? _slideshowTimer;
  
  Offset _lastTapPosition = Offset.zero;
  
  List<AppInfo> _filteredApps = [];
  Map<String, dynamic> _mediaResults = {};
  
  List<String> _galleryImages = [];
  List<Map<String, String>> _infoSlides = [];
  List<Map<String, String>> _recentFiles = [];
  List<String> _recentQueries = [];
  List<String> _hiddenRecentFiles = []; 
  int _currentSlide = 0;
  
  bool _isSearchActive = false; 
  bool _isSearching = false;
  bool _hasStoragePermission = false;
  bool _isCheckingPermissions = true; 
  
  String _activeTab = 'All';
  final List<String> _tabs = ['All', 'Apps', 'Documents', 'Photos', 'Video', 'Audio', 'Web'];

  @override
  void initState() {
    super.initState();
    _filteredApps = widget.installedApps;
    _loadRecentQueries();
    
    SearchDataSync.infoSlides.addListener(_onInfoSlidesChanged);
    _infoSlides = SearchDataSync.infoSlides.value;
    
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) {
        _checkPermissions();
        if (context.read<DesktopState>().searchShowNews && SearchDataSync.infoSlides.value.isEmpty) {
          SearchDataSync.fetchLiveNewsAndScores();
        }
      }
    });

    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(() {
      setState(() {
        _isSearchActive = _searchFocusNode.hasFocus || _searchController.text.isNotEmpty;
      });
    });

    _slideshowTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (mounted) setState(() => _currentSlide++);
    });
  }

  void _onInfoSlidesChanged() {
    if (mounted) {
      setState(() {
        _infoSlides = SearchDataSync.infoSlides.value;
      });
    }
  }

  @override
  void dispose() {
    SearchDataSync.infoSlides.removeListener(_onInfoSlidesChanged);
    _debounce?.cancel();
    _slideshowTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecentQueries() async {
    final prefs = await SharedPreferences.getInstance();
    
    _hiddenRecentFiles = prefs.getStringList('hidden_recent_files') ?? [];
    
    List<String> raw = prefs.getStringList('recent_searches') ?? [];
    List<String> cleaned = raw.where((q) => q.trim().isNotEmpty).toList();
    if (raw.length != cleaned.length) {
      await prefs.setStringList('recent_searches', cleaned);
    }
    if (mounted) setState(() => _recentQueries = cleaned);
  }

  Future<void> _addRecentQuery(String q) async {
    if (q.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _recentQueries.remove(q);
    _recentQueries.insert(0, q);
    if (_recentQueries.length > 10) _recentQueries.removeLast();
    await prefs.setStringList('recent_searches', _recentQueries);
    if (mounted) setState(() {});
  }

  Future<void> _removeRecentQuery(String q) async {
    final prefs = await SharedPreferences.getInstance();
    _recentQueries.remove(q);
    await prefs.setStringList('recent_searches', _recentQueries);
    if (mounted) setState(() {});
  }

  Future<void> _removeRecentFile(String path) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_hiddenRecentFiles.contains(path)) {
      _hiddenRecentFiles.add(path);
      await prefs.setStringList('hidden_recent_files', _hiddenRecentFiles);
    }
    if (mounted) {
      setState(() {
        _recentFiles.removeWhere((f) => f['path'] == path);
      });
    }
  }

  Future<void> _fetchGalleryImages() async {
    if (!_hasStoragePermission || kIsWeb) return;
    List<String> images = [];
    try {
      String rootPath = '/storage/emulated/0';
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) rootPath = extDir.path.split('/Android')[0];

      final cameraDir1 = Directory('$rootPath/DCIM/Camera');
      final cameraDir2 = Directory('$rootPath/Pictures/Camera');
      
      for (var d in [cameraDir1, cameraDir2]) {
        if (await d.exists()) {
          await for (var f in d.list(recursive: false, followLinks: false).take(100)) {
            final p = f.path.toLowerCase();
            if (p.endsWith('.jpg') || p.endsWith('.png') || p.endsWith('.jpeg')) {
              images.add(f.path);
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Gallery Fetch Error: $e");
    }
    if (mounted && images.isNotEmpty) {
      images.shuffle();
      setState(() => _galleryImages = images.take(15).toList());
    }
  }

  Future<void> _fetchRecentFiles() async {
    if (!_hasStoragePermission || kIsWeb) return;
    try {
      String rootPath = '/storage/emulated/0';
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) rootPath = extDir.path.split('/Android')[0];

      List<String> targetPaths = [
        '$rootPath/Download', 
        '$rootPath/Documents',
        '$rootPath/Music', 
        '$rootPath/Movies',
        '$rootPath/Pictures',
        '$rootPath/WhatsApp/Media/WhatsApp Documents', 
        '$rootPath/WhatsApp/Media/WhatsApp Audio', 
        '$rootPath/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents', 
        '$rootPath/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio', 
        '$rootPath/Telegram/Telegram Documents',
        '$rootPath/Telegram/Telegram Audio',
        '$rootPath/Android/media/org.telegram.messenger/Telegram/Telegram Documents',
        '$rootPath/Android/media/org.telegram.messenger/Telegram/Telegram Audio',
      ];

      final files = await compute(_scanRecentFilesIsolate, {
        'targetPaths': targetPaths,
        'hiddenFiles': _hiddenRecentFiles,
      });

      if (mounted) {
        setState(() {
          _recentFiles = files.take(5).map((f) {
            return {'name': f['name'].toString(), 'path': f['path'].toString()};
          }).toList();
        });
      }
    } catch (_) {}
  }

  void _onSearchChanged() {
    setState(() {}); 
    if (_searchController.text.isNotEmpty && !_isSearchActive) _isSearchActive = true;
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _performSearch());
  }

  Future<void> _checkPermissions() async {
    setState(() => _isCheckingPermissions = true);
    if (!kIsWeb && Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      bool storageGranted = false;

      if (androidInfo.version.sdkInt >= 30) {
        // Restore MANAGE_EXTERNAL_STORAGE to allow File Explorer indexing for documents
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
        }
        storageGranted = status.isGranted;
      } else {
        final status = await Permission.storage.request();
        storageGranted = status.isGranted;
      }

      if (mounted) {
        setState(() {
          _hasStoragePermission = storageGranted;
          _isCheckingPermissions = false;
        });
        if (storageGranted) {
          _fetchGalleryImages();
          _fetchRecentFiles(); 
        }
      }
    } else {
      if (mounted) setState(() => _isCheckingPermissions = false);
    }
  }

  void _performSearch() async {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredApps = widget.installedApps;
        _mediaResults = {};
        _isSearching = false;
        if (!_searchFocusNode.hasFocus) _isSearchActive = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    List<AppInfo> apps = widget.installedApps.where((app) => (app.name ?? '').toLowerCase().contains(query)).toList();

    Map<String, dynamic> media = {};
    if (_hasStoragePermission) {
      try {
        final result = await NativeBridge.instance.searchMedia(query);
        if (result != null) media = result;
      } catch (e) {
        debugPrint("Native Media Search Error: $e");
      }
    } else {
      _checkPermissions();
    }

    if (mounted) {
      setState(() {
        _filteredApps = apps;
        _mediaResults = media;
        _isSearching = false;
      });
    }
  }

  void _launchFile(String path) {
    NativeBridge.instance.openFile(path);
  }

  void _launchWebSearch(String query) {
    _addRecentQuery(query);
    NativeBridge.instance.openWebSearch(query);
  }

  void _showFileContextMenu(
    BuildContext context, 
    Map<String, String> fileMap, 
    Offset tapPos, 
    AppsState appsState,
  ) {
    final filePath = fileMap['path'];
    if (filePath == null || filePath.isEmpty) return;

    final isDark = widget.isDark;
    final popMenuBg = isDark ? const Color(0xFF2B2B2B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(tapPos.dx, tapPos.dy, tapPos.dx, tapPos.dy),
      color: popMenuBg,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor),
      ),
      items: [
        PopupMenuItem(
          value: 'share',
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.share_outlined, size: 16, color: textColor),
              const SizedBox(width: 12),
              Text('Share', style: TextStyle(color: textColor, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
              const SizedBox(width: 12),
              const Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'location',
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 16, color: textColor),
              const SizedBox(width: 12),
              Text('Open file location', style: TextStyle(color: textColor, fontSize: 13)),
            ],
          ),
        ),
      ],
    ).then((val) async {
      if (!mounted) return;
      if (val == 'share') {
        NativeBridge.instance.shareFile(filePath);
      } else if (val == 'delete') {
        final file = File(filePath);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: popMenuBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            title: Text('Delete File?', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
            content: Text('Are you sure you want to permanently delete "${fileMap['name']}"?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    if (await file.exists()) {
                      final success = await NativeBridge.instance.deleteFile(file.path);
                      if (success) {
                        _removeRecentFile(filePath);
                        _performSearch();
                        appsState.triggerExplorerRefresh();
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File deleted successfully')));
                      } else {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delete failed. Android restricts deleting non-media files.')));
                      }
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
        final file = File(filePath);
        final dirPath = file.parent.path;
        appsState.highlightFileName = file.path.split('/').last;
        appsState.requestExplorerNavigation(dirPath);
      }
    });
  }

  Widget _buildCategory(String title, List<dynamic> items, IconData fallbackIcon, Color textColor, AppsState appsState) {
    if (items.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.6))),
        ),
        ...items.map((item) {
          final map = Map<String, String>.from(item);
          
          return Material(
            type: MaterialType.transparency, 
            child: Listener(
              onPointerDown: (e) => _lastTapPosition = e.position,
              child: InkWell(
                onTap: () => _launchFile(map['path'] ?? ''),
                onLongPress: () => _showFileContextMenu(context, map, _lastTapPosition, appsState),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      Icon(fallbackIcon, color: textColor.withOpacity(0.8), size: 24), 
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(map['name'] ?? 'Unknown', style: TextStyle(color: textColor, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(map['path'] ?? '', style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
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
    );
  }

  List<Widget> _buildFilteredResults(Color textColor, AppsState appsState, ThemeState themeState) {
    List<Widget> children = [];
    final desktopState = context.read<DesktopState>();
    
    final double scale = desktopState.desktopIconScale.clamp(0.6, 1.8);
    final double baseSize = 32.0 * scale; 
    final double fontSize = desktopState.desktopFontSize;
    
    if (!_isCheckingPermissions && !_hasStoragePermission) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(16.0), 
          child: Text(
            "Storage permission required to search files.", 
            style: TextStyle(color: Colors.red.shade400, fontSize: 12), 
            textAlign: TextAlign.center
          )
        )
      );
    }

    if (_activeTab == 'All' || _activeTab == 'Apps') {
      if (_filteredApps.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4), 
            child: Text('Apps', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.6)))
          )
        );

        children.addAll(_filteredApps.map((app) {
          Widget appIconWidget = app.packageName != null
              ? LazyAppIcon(packageName: app.packageName!, size: baseSize)
              : Icon(Icons.android, size: baseSize);
          
          if (themeState.cachedIconsPath != null && app.packageName != null) {
            final cacheFile = File('${themeState.cachedIconsPath}/${app.packageName}.png');
            if (cacheFile.existsSync()) {
              appIconWidget = Image.file(cacheFile, width: baseSize, height: baseSize, gaplessPlayback: true);
            }
          }

          return Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: appIconWidget,
              title: Text(app.name ?? 'Unknown App', style: TextStyle(color: textColor, fontSize: fontSize)),
              onTap: () { 
                _addRecentQuery(app.name!);
                InstalledApps.startApp(app.packageName!); 
              },
            ),
          );
        }));
      }
    }

    if (_activeTab == 'All' || _activeTab == 'Documents') children.add(_buildCategory('Documents', _mediaResults['Documents'] ?? [], Icons.description, textColor, appsState));
    if (_activeTab == 'All' || _activeTab == 'Photos') children.add(_buildCategory('Images', _mediaResults['Images'] ?? [], Icons.image, textColor, appsState));
    if (_activeTab == 'All' || _activeTab == 'Video') children.add(_buildCategory('Video', _mediaResults['Video'] ?? [], Icons.videocam, textColor, appsState));
    if (_activeTab == 'All' || _activeTab == 'Audio') children.add(_buildCategory('Audio', _mediaResults['Audio'] ?? [], Icons.music_note, textColor, appsState));
    
    if (_activeTab == 'All' || _activeTab == 'Web') {
      if (_searchController.text.isNotEmpty) {
        children.add(
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: const Icon(Icons.travel_explore, color: Colors.blue, size: 24),
              title: Text("Search Web for '${_searchController.text}'", style: TextStyle(color: Colors.blue.shade400, fontSize: 13, fontWeight: FontWeight.bold)),
              onTap: () => _launchWebSearch(_searchController.text),
            ),
          )
        );
      }
    }

    if (children.isEmpty && !_isSearching && _searchController.text.isNotEmpty && !_isCheckingPermissions) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(32.0), 
          child: Center(child: Text("No results found in $_activeTab", style: TextStyle(color: textColor.withOpacity(0.5))))
        )
      );
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final appsState = context.watch<AppsState>();
    final themeState = context.watch<ThemeState>(); 
    
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final safeAreaTop = MediaQuery.of(context).padding.top;
    
    final double assumedBottomOffset = math.max(64.0, keyboardHeight);
    final double maxAvailableHeight = screenHeight - assumedBottomOffset - safeAreaTop - 12.0;
    final double overlayHeight = math.min(520.0, math.max(250.0, maxAvailableHeight));

    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final borderColor = widget.isDark ? Colors.white24 : Colors.grey.shade300;
    final searchBgColor = widget.isDark ? const Color(0xFF333333).withOpacity(0.6) : Colors.white.withOpacity(0.6);
    final chipInactiveBg = widget.isDark ? Colors.transparent : Colors.white;

    return Material(
      type: MaterialType.transparency,
      child: Win11AcrylicContainer(
        width: widget.width,
        height: overlayHeight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 12.0),
              child: SizedBox(
                height: 38,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, _) {
                    return TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode, 
                      autofocus: false, // NEW: Ensure no auto pop-up
                      onTap: () {
                        // NEW: Only trigger keyboard on physical tap
                        if (!_searchFocusNode.hasFocus) {
                          FocusScope.of(context).requestFocus(_searchFocusNode);
                        }
                      },
                      textAlignVertical: TextAlignVertical.center,
                      style: TextStyle(color: textColor, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true, 
                        hintText: 'Type here to search...', 
                        hintStyle: TextStyle(color: textColor.withOpacity(0.5), fontSize: 13), 
                        prefixIcon: const Icon(Icons.search, color: Colors.blue, size: 18),
                        suffixIcon: value.text.isNotEmpty 
                            ? IconButton(
                                icon: Icon(Icons.close, size: 16, color: textColor.withOpacity(0.7)),
                                onPressed: () {
                                  _searchController.clear();
                                  FocusScope.of(context).unfocus();
                                  _performSearch();
                                },
                              )
                            : null,
                        filled: true, fillColor: searchBgColor, contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (val) { if (val.isNotEmpty) _launchWebSearch(val); },
                    );
                  }
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    fit: StackFit.expand,
                    alignment: Alignment.topLeft,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                child: !_isSearchActive
                    ? SearchDashboard(
                        key: const ValueKey('dashboard'),
                        recentQueries: _recentQueries,
                        galleryImages: _galleryImages,
                        infoSlides: context.watch<DesktopState>().searchShowNews ? _infoSlides : [],
                        recentFiles: _recentFiles, 
                        currentSlide: _currentSlide,
                        onQueryTap: (q) { 
                          FocusScope.of(context).unfocus();
                          _searchController.text = q; 
                          _performSearch(); 
                        },
                        onRemoveQuery: _removeRecentQuery,
                        onRemoveRecentFile: _removeRecentFile, 
                      )
                    : Column(
                        key: const ValueKey('search_results'),
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          SizedBox(
                            height: 34,
                            child: Row(
                              children: [
                                Padding(padding: const EdgeInsets.only(left: 12, right: 4), child: Icon(Icons.arrow_back, size: 16, color: textColor.withOpacity(0.7))),
                                Expanded(
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal, 
                                    physics: const BouncingScrollPhysics(), 
                                    itemCount: _tabs.length,
                                    itemBuilder: (context, index) {
                                      final tab = _tabs[index];
                                      final isActive = _activeTab == tab;
                                      return GestureDetector(
                                        onTap: () {
                                          FocusScope.of(context).unfocus();
                                          setState(() => _activeTab = tab);
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.only(right: 6), 
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          decoration: BoxDecoration(
                                            color: isActive ? Colors.blue.shade600 : chipInactiveBg, 
                                            borderRadius: BorderRadius.circular(16), 
                                            border: isActive ? null : Border.all(color: borderColor)
                                          ),
                                          child: Center(
                                            child: Text(
                                              tab, 
                                              style: TextStyle(
                                                fontSize: 12, 
                                                color: isActive ? Colors.white : textColor, 
                                                fontWeight: isActive ? FontWeight.bold : FontWeight.w500
                                              )
                                            )
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _isSearching 
                                ? const Center(child: CircularProgressIndicator())
                                : ListView(
                                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, // NEW: Drop keyboard
                                    physics: const BouncingScrollPhysics(), 
                                    children: _buildFilteredResults(textColor, appsState, themeState)
                                  ),
                          )
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}