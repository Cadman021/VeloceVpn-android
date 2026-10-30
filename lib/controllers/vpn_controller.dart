import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'split_tunneling_controller.dart';
import '../services/api_service.dart';
import '../services/models.dart';

class NativeVpnBridge {
  static const _channel = MethodChannel('com.veloce.veloce_vpn/control');

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

enum ConnStatus { disconnected, connecting, connected, reconnecting }

/// نوع خطای قابل نمایش به کاربر در مرحله‌ی اتصال.
enum VpnErrorKind { configFailed, permissionDenied, startFailed, unknown }

class VpnController extends ChangeNotifier {
  final NativeVpnBridge bridge = NativeVpnBridge();
  final ApiService api = ApiService();

  ConnStatus status = ConnStatus.disconnected;
  SelectedLocationMeta? selectedMeta;
  bool adblockOn = false;
  DateTime? connectedAt;

  /// آخرین خطای اتصال برای نمایش در UI (null یعنی خطایی نیست).
  VpnErrorKind? lastErrorKind;

  /// پیام اختیاری از لایه‌ی ناتیو (مثلاً دلیل شکست Xray).
  String? lastErrorDetail;

  List<CountryGroup> cachedLocations = [];
  bool isLocationsLoaded = false;
  bool loadFailed = false;

  final Set<String> favoriteIds = {};
  final List<SelectedLocationMeta> recentLocations = [];

  final _statusController = StreamController<ConnStatus>.broadcast();
  Stream<ConnStatus> get statusStream => _statusController.stream;

  static const int _localSocksPort = 10808;

  Future<void> initPreferences() async {
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
      } catch (_) {}
    }
  }

  Future<bool> preloadLocations({bool force = false}) async {
    if (isLocationsLoaded && !force && cachedLocations.isNotEmpty) return true;
    try {
      cachedLocations = await api.fetchCandidates();
      isLocationsLoaded = true;
      loadFailed = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[Preload Locations Error]: $e');
      loadFailed = true;
      notifyListeners();
      return false;
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

  Future<void> pingLocationsInParallel(
    List<CityLocation> locs, {
    int concurrency = 8,
    required void Function(CityLocation) onProgress,
  }) async {
    int cursor = 0;
    Future<void> worker() async {
      while (cursor < locs.length) {
        final currentIdx = cursor++;
        final loc = locs[currentIdx];
        final ms = await pingLocation(loc.id);
        loc.ping = ms;
        loc.unreachable = (ms == null);
        onProgress(loc);
      }
    }

    final workerCount = concurrency.clamp(1, locs.isEmpty ? 1 : locs.length);
    final workers = List.generate(workerCount, (_) => worker());
    await Future.wait(workers);
    notifyListeners();
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

    lastErrorKind = null;
    lastErrorDetail = null;

    status = ConnStatus.connecting;
    _statusController.add(status);
    notifyListeners();

    try {
      final Map<String, dynamic> xrayConfig;
      try {
        xrayConfig = await api.fetchXrayConfig(selectedMeta!.id, adblock: adblockOn);
      } catch (e) {
        debugPrint('[Connect] config download failed: $e');
        _fail(VpnErrorKind.configFailed, null);
        return false;
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
        connectedAt = DateTime.now();
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
        e.code == 'vpn_start_failed' ? VpnErrorKind.startFailed : VpnErrorKind.unknown,
        e.message,
      );
      return false;
    } catch (e) {
      debugPrint('[Connect Error]: $e');
      _fail(VpnErrorKind.unknown, null);
      return false;
    }

    _statusController.add(status);
    notifyListeners();
    return status == ConnStatus.connected;
  }

  void _fail(VpnErrorKind kind, String? detail) {
    lastErrorKind = kind;
    lastErrorDetail = detail;
    status = ConnStatus.disconnected;
    connectedAt = null;
    _statusController.add(status);
    notifyListeners();
  }

  /// پاک کردن خطای نمایش‌داده‌شده (بعد از نمایش SnackBar).
  void clearError() {
    if (lastErrorKind == null) return;
    lastErrorKind = null;
    lastErrorDetail = null;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await bridge.stop();
    status = ConnStatus.disconnected;
    connectedAt = null;
    _statusController.add(status);
    notifyListeners();
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
      final ms = await bridge.testPing(xrayConfig).timeout(const Duration(seconds: 20));
      if (ms == null) {
        debugPrint('[Ping] testPing returned null for $configId (see logcat VelocePing for reason)');
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('adblockEnabled', value);
    notifyListeners();
  }

  @override
  void dispose() {
    _statusController.close();
    super.dispose();
  }
}