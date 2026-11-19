import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/models.dart';
import 'split_tunneling_controller.dart';

class NativeVpnBridge {
  static const _channel = MethodChannel('com.cadman.veloce/control');

  Future<bool> start({
    required Map<String, dynamic> xrayConfig,
    required int localSocksPort,
    required bool splitEnabled,
    required String splitMode,
    required List<String> selectedApps,
    required List<String> excludedIps,
  }) async {
    final result = await _channel.invokeMethod<bool>('start', {
      'xrayConfigJson': jsonEncode(xrayConfig),
      'localSocksPort': localSocksPort,
      'splitEnabled': splitEnabled,
      'splitMode': splitMode,
      'selectedApps': selectedApps,
      'excludedIps': excludedIps,
    });
    return result ?? false;
  }

  Future<void> stop() => _channel.invokeMethod('stop');

  Future<bool> status() async {
    final result = await _channel.invokeMethod<bool>('status');
    return result ?? false;
  }

  Future<bool> isNativeReconnecting() async {
    final result = await _channel.invokeMethod<bool>('reconnecting');
    return result ?? false;
  }

  Future<Map<String, dynamic>> diagnostics() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('diagnostics');
    return result ?? const {};
  }

  Future<int?> testPing(Map<String, dynamic> xrayConfig) async {
    final result = await _channel.invokeMethod<int>('testPing', {
      'xrayConfigJson': jsonEncode(xrayConfig),
    });
    return result;
  }

  Future<Map<String, int>> speed() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('speed');
    return {
      'downBps': (result?['downBps'] as num?)?.toInt() ?? 0,
      'upBps': (result?['upBps'] as num?)?.toInt() ?? 0,
    };
  }
}

enum ConnStatus { disconnected, connecting, connected, reconnecting, switching }

/// نوع خطای قابل نمایش به کاربر در مرحله‌ی اتصال.
enum VpnErrorKind {
  configFailed,
  permissionDenied,
  startFailed,
  emptyInclusiveSelection,
  unknown,
}

class VpnController extends ChangeNotifier with WidgetsBindingObserver {
  VpnController({ApiService? api, NativeVpnBridge? bridge})
      : api = api ?? ApiService(),
        bridge = bridge ?? NativeVpnBridge();

  final NativeVpnBridge bridge;
  final ApiService api;

  ConnStatus status = ConnStatus.disconnected;
  SelectedLocationMeta? selectedMeta;

  /// سروری که تونل واقعاً با آن بالا آمده است. ممکن است با [selectedMeta]
  /// فرق داشته باشد (مثلاً کاربر سرور جدید را انتخاب کرده ولی هنوز reconnect
  /// انجام نشده است).
  SelectedLocationMeta? connectedMeta;

  bool adblockOn = false;
  DateTime? connectedAt;

  /// آخرین خطای اتصال برای نمایش در UI (null یعنی خطایی نیست).
  VpnErrorKind? lastErrorKind;

  /// پیام اختیاری از لایه‌ی ناتیو (مثلاً دلیل شکست Xray).
  String? lastErrorDetail;

  /// اگر تنظیماتی مثل adblock یا split tunneling بعد از اتصال عوض شود،
  /// تا reconnect بعدی اعمال نمی‌شود.
  bool needsReconnect = false;

  /// اگر کانفیگ adblock در دسترس نبود و از کانفیگ عادی استفاده شد.
  bool adblockFallbackUsed = false;

  List<CountryGroup> cachedLocations = [];
  bool isLocationsLoaded = false;
  bool isLoadingLocations = false;
  bool loadFailed = false;

  /// لیست نمایش‌داده‌شده از کش محلی است و ممکن است قدیمی باشد.
  bool usingCachedLocations = false;

  final Set<String> favoriteIds = {};
  final List<SelectedLocationMeta> recentLocations = [];

  final _statusController = StreamController<ConnStatus>.broadcast();
  Stream<ConnStatus> get statusStream => _statusController.stream;

  static const int _localSocksPort = 10808;
  static const String _cachedCandidatesKey = 'cachedCandidatesV1';

  Timer? _statusTimer;
  bool _disposed = false;
  bool _connectInFlight = false;
  bool _disconnectInFlight = false;
  bool _observerAdded = false;

  Future<void> initPreferences() async {
    WidgetsBinding.instance.addObserver(this);
    _observerAdded = true;
    final prefs = await SharedPreferences.getInstance();

    final id = prefs.getString('selectedConfigId');
    if (id != null) {
      selectedMeta = SelectedLocationMeta(
        id: id,
        country: prefs.getString('countryName') ?? '',
        city: prefs.getString('cityName') ?? '',
        countryCode: prefs.getString('countryCode') ?? '',
      );
    }
    adblockOn = prefs.getBool('adblockEnabled') ?? false;

    final favList = prefs.getStringList('favoriteConfigIds') ?? [];
    favoriteIds.addAll(favList);

    final recentRaw = prefs.getStringList('recentLocationsList') ?? [];
    recentLocations.clear();
    for (final str in recentRaw) {
      try {
        recentLocations.add(SelectedLocationMeta.fromJson(jsonDecode(str)));
      } catch (_) {
        // Ignore a corrupt preference entry instead of failing app startup.
      }
    }

    // The Quick Settings tile can start/stop the tunnel while Flutter is
    // closed. Keep the Dart state in sync with the native service.
    await syncStatus();
    _startStatusTimer();
  }

  void _startStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) => syncStatus());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      syncStatus();
      _startStatusTimer();
    } else {
      // No need to poll the platform channel while the app is in the
      // background; the service keeps running independently.
      _statusTimer?.cancel();
      _statusTimer = null;
    }
  }

  Future<bool> preloadLocations({bool force = false}) async {
    if (isLocationsLoaded && !force && cachedLocations.isNotEmpty) return true;
    if (isLoadingLocations && !force) return false;

    isLoadingLocations = true;
    notifyListeners();

    try {
      final groups = await api.fetchCandidates();
      cachedLocations = groups;
      isLocationsLoaded = true;
      loadFailed = false;
      usingCachedLocations = false;
      await _saveCachedCandidates(groups);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[Preload Locations Error]: $e');
      final cached = await _readCachedCandidates();
      if (cached != null && cached.isNotEmpty) {
        cachedLocations = cached;
        isLocationsLoaded = true;
        loadFailed = false;
        usingCachedLocations = true;
        notifyListeners();
        return true;
      }
      loadFailed = true;
      usingCachedLocations = false;
      return false;
    } finally {
      isLoadingLocations = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _saveCachedCandidates(List<CountryGroup> groups) async {
    try {
      final flat = <Map<String, dynamic>>[];
      for (final group in groups) {
        for (final loc in group.locations) {
          flat.add(loc.toJson());
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachedCandidatesKey, jsonEncode(flat));
    } catch (e) {
      debugPrint('[Cache Locations] save failed: $e');
    }
  }

  Future<List<CountryGroup>?> _readCachedCandidates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachedCandidatesKey);
      if (raw == null || raw.isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;

      final grouped = <String, CountryGroup>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['id'];
        final countryCode = map['countryCode'];
        if (id is! String || countryCode is! String) continue;
        final loc = CityLocation.fromJson(map);
        grouped.putIfAbsent(
          countryCode,
          () => CountryGroup(
            countryName: loc.country,
            countryCode: countryCode,
            locations: [],
          ),
        );
        grouped[countryCode]!.locations.add(loc);
      }
      return grouped.values.toList()
        ..sort((a, b) => a.countryName.compareTo(b.countryName));
    } catch (e) {
      debugPrint('[Cache Locations] read failed: $e');
      return null;
    }
  }

  Future<void> toggleFavorite(String configId) async {
    if (favoriteIds.contains(configId)) {
      favoriteIds.remove(configId);
    } else {
      favoriteIds.add(configId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favoriteConfigIds', favoriteIds.toList());
    notifyListeners();
  }

  Future<void> _recordRecent(SelectedLocationMeta meta) async {
    recentLocations.removeWhere((r) => r.id == meta.id);
    recentLocations.insert(0, meta);
    if (recentLocations.length > 5) {
      recentLocations.removeRange(5, recentLocations.length);
    }
    final prefs = await SharedPreferences.getInstance();
    final list = recentLocations.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList('recentLocationsList', list);
  }

  Future<void> selectLocation(SelectedLocationMeta meta) async {
    selectedMeta = meta;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedConfigId', meta.id);
    await prefs.setString('countryName', meta.country);
    await prefs.setString('cityName', meta.city);
    await prefs.setString('countryCode', meta.countryCode);
    notifyListeners();
  }

  /// انتخاب لوکیشن جدید در حالی که تونل فعال است: اتصال فعلی را می‌بندد،
  /// انتخاب جدید را ذخیره می‌کند و با همان تنظیمات دوباره وصل می‌شود.
  Future<bool> switchLocation(
    SelectedLocationMeta meta,
    SplitTunnelingController split,
  ) async {
    final wasActive = status == ConnStatus.connected ||
        status == ConnStatus.connecting ||
        status == ConnStatus.reconnecting ||
        status == ConnStatus.switching;

    await selectLocation(meta);
    if (!wasActive) return true;

    status = ConnStatus.switching;
    _statusController.add(status);
    notifyListeners();

    await disconnect(waitForNative: true);
    return connect(split);
  }

  Future<bool> reconnect(SplitTunnelingController split) async {
    if (selectedMeta == null) return false;
    await disconnect(waitForNative: true);
    return connect(split);
  }

  /// بعد از تغییر تنظیماتی که فقط با reconnect اعمال می‌شوند صدا زده می‌شود.
  void markSettingsChanged() {
    if (status == ConnStatus.connected ||
        status == ConnStatus.connecting ||
        status == ConnStatus.reconnecting) {
      needsReconnect = true;
      notifyListeners();
    }
  }

  Future<void> pingLocationsInParallel(
    List<CityLocation> locs, {
    int concurrency = 4,
    required void Function(CityLocation) onProgress,
  }) async {
    int cursor = 0;
    Future<void> worker() async {
      while (!_disposed && cursor < locs.length) {
        final currentIdx = cursor++;
        final loc = locs[currentIdx];
        final ms = await pingLocation(loc.id);
        if (_disposed) return;
        loc.ping = ms;
        loc.unreachable = (ms == null);
        onProgress(loc);
      }
    }

    final workerCount = concurrency.clamp(1, locs.isEmpty ? 1 : locs.length);
    final workers = List.generate(workerCount, (_) => worker());
    await Future.wait(workers);
    if (!_disposed) notifyListeners();
  }

  CityLocation? getOptimalLocation() {
    CityLocation? best;
    for (final group in cachedLocations) {
      for (final loc in group.locations) {
        if (loc.ping != null && loc.ping! > 0 && !loc.unreachable) {
          if (best == null || loc.ping! < (best.ping ?? 99999)) {
            best = loc;
          }
        }
      }
    }
    return best;
  }

  /// متد اتصال که تنظیمات SplitTunnelingController را به لایه ناتیو ارسال می‌کند
  Future<bool> connect(SplitTunnelingController splitController) async {
    if (selectedMeta == null) return false;
    if (_connectInFlight || status == ConnStatus.connecting) return false;
    if (status == ConnStatus.connected) return true;

    _connectInFlight = true;
    lastErrorKind = null;
    lastErrorDetail = null;
    adblockFallbackUsed = false;

    if (splitController.isEnabled &&
        splitController.mode == 'inclusive' &&
        splitController.selectedPackages.isEmpty) {
      _connectInFlight = false;
      _fail(VpnErrorKind.emptyInclusiveSelection, null);
      return false;
    }

    status = ConnStatus.connecting;
    _statusController.add(status);
    notifyListeners();

    try {
      Map<String, dynamic> xrayConfig;
      try {
        xrayConfig = await api.fetchXrayConfig(
          selectedMeta!.id,
          adblock: adblockOn,
        );
      } catch (e) {
        debugPrint('[Connect] config download failed: $e');
        if (!adblockOn) {
          _fail(VpnErrorKind.configFailed, null);
          return false;
        }

        // Ad-block is an optional variant. If the backend does not have it,
        // fall back to the normal configuration instead of making the server
        // unusable.
        try {
          xrayConfig = await api.fetchXrayConfig(selectedMeta!.id);
          adblockFallbackUsed = true;
        } catch (fallbackError) {
          debugPrint('[Connect] adblock fallback failed: $fallbackError');
          _fail(VpnErrorKind.configFailed, null);
          return false;
        }
      }

      final ok = await bridge.start(
        xrayConfig: xrayConfig,
        localSocksPort: _localSocksPort,
        splitEnabled: splitController.isEnabled,
        splitMode: splitController.mode,
        selectedApps: splitController.selectedPackages,
        excludedIps: splitController.excludedIpsDomains,
      );
      if (ok) {
        status = ConnStatus.connected;
        connectedMeta = selectedMeta;
        connectedAt = DateTime.now();
        needsReconnect = false;
        await _recordRecent(selectedMeta!);
        lastErrorKind = null;
        lastErrorDetail = null;
      } else {
        // کاربر مجوز VPN را رد کرده است (ناتیو در این حالت false برمی‌گرداند).
        _fail(VpnErrorKind.permissionDenied, null);
        return false;
      }
    } on PlatformException catch (e) {
      debugPrint('[Connect] native error ${e.code}: ${e.message}');
      _fail(
        e.code == 'vpn_start_failed'
            ? VpnErrorKind.startFailed
            : VpnErrorKind.unknown,
        e.message,
      );
      return false;
    } catch (e) {
      debugPrint('[Connect Error]: $e');
      _fail(VpnErrorKind.unknown, null);
      return false;
    } finally {
      _connectInFlight = false;
    }

    _statusController.add(status);
    notifyListeners();
    return status == ConnStatus.connected;
  }

  void _fail(VpnErrorKind kind, String? detail) {
    lastErrorKind = kind;
    lastErrorDetail = detail;
    status = ConnStatus.disconnected;
    connectedMeta = null;
    connectedAt = null;
    _statusController.add(status);
    if (!_disposed) notifyListeners();
  }

  /// پاک کردن خطای نمایش‌داده‌شده (بعد از نمایش SnackBar).
  void clearError() {
    if (lastErrorKind == null) return;
    lastErrorKind = null;
    lastErrorDetail = null;
    notifyListeners();
  }

  Future<void> disconnect({bool waitForNative = false}) async {
    if (_disconnectInFlight) return;
    _disconnectInFlight = true;
    try {
      await bridge.stop();
      if (waitForNative) {
        await _waitForNativeStopped();
      }
    } catch (e) {
      debugPrint('[Disconnect] native stop failed: $e');
    } finally {
      status = ConnStatus.disconnected;
      connectedMeta = null;
      connectedAt = null;
      _statusController.add(status);
      _disconnectInFlight = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _waitForNativeStopped({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (!await bridge.status()) return;
      } catch (_) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// وضعیت native را می‌خواند تا start/stop از tile یا notification هم در
  /// UI منعکس شود. این متد به‌صورت دوره‌ای هم اجرا می‌شود.
  Future<void> syncStatus() async {
    if (_disposed || _connectInFlight || _disconnectInFlight) return;
    final bool running;
    final bool reconnecting;
    try {
      running = await bridge.status();
      reconnecting = running ? false : await bridge.isNativeReconnecting();
    } catch (_) {
      return;
    }
    if (_disposed) return;

    if (running && status != ConnStatus.connected) {
      status = ConnStatus.connected;
      connectedMeta ??= selectedMeta;
      connectedAt ??= DateTime.now();
      _statusController.add(status);
      notifyListeners();
    } else if (!running && reconnecting) {
      if (status != ConnStatus.reconnecting) {
        status = ConnStatus.reconnecting;
        connectedMeta ??= selectedMeta;
        connectedAt ??= DateTime.now();
        _statusController.add(status);
        notifyListeners();
      }
    } else if (!running && status == ConnStatus.connected) {
      status = ConnStatus.disconnected;
      connectedMeta = null;
      connectedAt = null;
      _statusController.add(status);
      notifyListeners();
    } else if (!running && status == ConnStatus.reconnecting) {
      status = ConnStatus.disconnected;
      connectedMeta = null;
      connectedAt = null;
      _statusController.add(status);
      notifyListeners();
    }
  }

  Future<int?> pingLocation(String configId) async {
    final Map<String, dynamic> xrayConfig;
    try {
      xrayConfig = await api.fetchXrayConfig(configId);
    } catch (e) {
      debugPrint('[Ping] fetchXrayConfig failed for $configId: $e');
      return null;
    }
    try {
      final ms =
          await bridge.testPing(xrayConfig).timeout(const Duration(seconds: 20));
      if (ms == null) {
        debugPrint(
          '[Ping] testPing returned null for $configId (see logcat VelocePing for reason)',
        );
      }
      return ms;
    } catch (e) {
      debugPrint('[Ping] testPing failed for $configId: $e');
      return null;
    }
  }

  Future<Map<String, int>> getSpeed() {
    if (status != ConnStatus.connected) {
      return Future.value({'downBps': 0, 'upBps': 0});
    }
    return bridge.speed();
  }

  Future<void> setAdblock(bool value) async {
    adblockOn = value;
    needsReconnect = status == ConnStatus.connected;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('adblockEnabled', value);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_observerAdded) WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    _statusController.close();
    super.dispose();
  }
}
