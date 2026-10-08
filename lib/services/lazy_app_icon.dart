import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

class LazyAppIcon extends StatefulWidget {
  final String packageName;
  final double size;
  final Widget? fallbackIcon;

  static const int maxCacheSize = 500;
  static final Map<String, Uint8List> globalIconCache = {};
  static final Set<String> failedFetches = {};
  
  // PERFORMANCE FIX: Concurrency-controlled fetch queue
  static final Set<String> _pendingFetches = {};
  static final List<String> _queue = [];
  static int _activeConcurrentFetches = 0;
  static const int _maxConcurrent = 4;
  static final Map<String, List<VoidCallback>> _listeners = {};

  const LazyAppIcon({
    Key? key,
    required this.packageName,
    required this.size,
    this.fallbackIcon,
  }) : super(key: key);

  static void invalidateCache(String packageName) {
    globalIconCache.remove(packageName);
    failedFetches.remove(packageName);
    _pendingFetches.remove(packageName);
    _queue.remove(packageName);
    _listeners.remove(packageName);
  }

  /// Silently pre-caches installed app icons into memory in the background
  static void prewarmIcons(List<String> packages) {
    for (final pkg in packages) {
      if (!globalIconCache.containsKey(pkg) && 
          !failedFetches.contains(pkg) && 
          !_pendingFetches.contains(pkg) && 
          !_queue.contains(pkg)) {
        _queue.add(pkg);
      }
    }
    _processNext();
  }

  static void _processNext() async {
    while (_activeConcurrentFetches < _maxConcurrent && _queue.isNotEmpty) {
      final pkg = _queue.removeAt(0);
      _activeConcurrentFetches++;
      _pendingFetches.add(pkg);

      _fetchNative(pkg).whenComplete(() {
        _activeConcurrentFetches--;
        _pendingFetches.remove(pkg);
        _processNext();
      });
    }
  }

  static Future<void> _fetchNative(String pkg) async {
    try {
      AppInfo? info = await InstalledApps.getAppInfo(pkg);
      if (info?.icon != null) {
        if (globalIconCache.length >= maxCacheSize) {
          globalIconCache.remove(globalIconCache.keys.first);
        }
        globalIconCache[pkg] = info!.icon!;
      } else {
        failedFetches.add(pkg);
      }
    } catch (_) {
      failedFetches.add(pkg);
    }

    final callbacks = _listeners.remove(pkg);
    if (callbacks != null) {
      for (final cb in callbacks) {
        cb();
      }
    }
  }

  @override
  State<LazyAppIcon> createState() => _LazyAppIconState();
}

class _LazyAppIconState extends State<LazyAppIcon> {
  Uint8List? _iconBytes;
  bool _hasAttemptedFetch = false;

  @override
  void initState() {
    super.initState();
    final cached = LazyAppIcon.globalIconCache[widget.packageName];
    if (cached != null) {
      _iconBytes = cached;
      _hasAttemptedFetch = true;
    } else {
      _enqueueFetch();
    }
  }

  @override
  void didUpdateWidget(LazyAppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageName != widget.packageName) {
      final cached = LazyAppIcon.globalIconCache[widget.packageName];
      if (cached != null) {
        _iconBytes = cached;
        _hasAttemptedFetch = true;
      } else {
        _iconBytes = null;
        _hasAttemptedFetch = false;
        _enqueueFetch();
      }
    }
  }

  void _enqueueFetch() {
    if (LazyAppIcon.globalIconCache.containsKey(widget.packageName)) {
      _iconBytes = LazyAppIcon.globalIconCache[widget.packageName];
      _hasAttemptedFetch = true;
      return;
    }

    if (LazyAppIcon.failedFetches.contains(widget.packageName)) {
      _hasAttemptedFetch = true;
      return;
    }

    LazyAppIcon._listeners.putIfAbsent(widget.packageName, () => []).add(() {
      if (mounted) {
        setState(() {
          _iconBytes = LazyAppIcon.globalIconCache[widget.packageName];
          _hasAttemptedFetch = true;
        });
      }
    });

    if (!LazyAppIcon._pendingFetches.contains(widget.packageName) &&
        !LazyAppIcon._queue.contains(widget.packageName)) {
      LazyAppIcon._queue.insert(0, widget.packageName); // High priority for currently visible items
      LazyAppIcon._processNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_iconBytes != null) {
      return Image.memory(
        _iconBytes!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        cacheWidth: (widget.size * 2.0).toInt().clamp(48, 144),
        cacheHeight: (widget.size * 2.0).toInt().clamp(48, 144),
      );
    }

    if (!_hasAttemptedFetch) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
      );
    }

    return widget.fallbackIcon ?? Icon(Icons.android, size: widget.size, color: Colors.green);
  }
}