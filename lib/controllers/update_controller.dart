import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_version.dart';
import '../services/update_service.dart';

/// Checks GitHub Releases at most once per day and exposes a dismissible
/// update prompt. No analytics or device identifiers are sent.
class UpdateController extends ChangeNotifier {
  UpdateController({
    UpdateService? service,
    Future<String> Function()? currentVersionLoader,
  })  : _service = service ?? UpdateService(),
        _currentVersionLoader = currentVersionLoader ??
            (() async => (await PackageInfo.fromPlatform()).version);

  static const Duration _checkInterval = Duration(hours: 24);
  static const String _lastCheckedKey = 'updateLastCheckedAt';
  static const String _cachedReleaseKey = 'updateCachedRelease';
  static const String _ignoredVersionKey = 'updateIgnoredVersion';

  final UpdateService _service;
  final Future<String> Function() _currentVersionLoader;

  ReleaseInfo? available;
  bool isChecking = false;
  String? error;
  DateTime? lastChecked;

  bool _loaded = false;
  Future<void>? _loadFuture;
  String _currentVersion = '';

  bool get hasUpdate => available != null;

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _currentVersion = await _safeCurrentVersion();

    final checkedAt = prefs.getInt(_lastCheckedKey);
    if (checkedAt != null) {
      lastChecked = DateTime.fromMillisecondsSinceEpoch(checkedAt);
    }

    final ignored = prefs.getString(_ignoredVersionKey);
    final raw = prefs.getString(_cachedReleaseKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final release = ReleaseInfo.fromJson(jsonDecode(raw));
        if (release != null &&
            release.version != ignored &&
            AppVersion.tryParse(release.tag)?.isNewerThan(_currentVersion) ==
                true) {
          available = release;
        }
      } catch (e) {
        debugPrint('[Update] ignoring corrupt cache: $e');
      }
    }

    _loaded = true;
    notifyListeners();
  }

  Future<String> _safeCurrentVersion() async {
    try {
      final value = await _currentVersionLoader();
      return value.trim();
    } catch (e) {
      debugPrint('[Update] could not read installed version: $e');
      return '0.0.0';
    }
  }

  /// `force` bypasses the 24-hour interval (used by Settings).
  Future<void> check({bool force = false}) async {
    await load();
    if (isChecking) return;

    if (!force &&
        lastChecked != null &&
        DateTime.now().difference(lastChecked!) < _checkInterval) {
      return;
    }

    isChecking = true;
    error = null;
    notifyListeners();

    try {
      final release = await _service.fetchLatest(
        currentVersion: _currentVersion,
      );
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      lastChecked = now;
      await prefs.setInt(_lastCheckedKey, now.millisecondsSinceEpoch);

      final ignored = prefs.getString(_ignoredVersionKey);
      if (release != null && release.version != ignored) {
        available = release;
        await prefs.setString(
          _cachedReleaseKey,
          jsonEncode(release.toJson()),
        );
      } else {
        available = null;
        await prefs.remove(_cachedReleaseKey);
      }
    } catch (e) {
      debugPrint('[Update] check failed: $e');
      error = e.toString();
    } finally {
      isChecking = false;
      notifyListeners();
    }
  }

  /// Hides the current release until a newer one is published.
  Future<void> dismiss() async {
    final release = available;
    if (release == null) return;
    available = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ignoredVersionKey, release.version);
    await prefs.remove(_cachedReleaseKey);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
