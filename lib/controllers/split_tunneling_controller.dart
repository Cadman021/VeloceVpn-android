import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppInfo {
  final String name;
  final String packageName;
  final bool isSystem;
  final Uint8List? icon;

  AppInfo({
    required this.name,
    required this.packageName,
    required this.isSystem,
    this.icon,
  });
}

class SplitTunnelingController extends ChangeNotifier {
  static const _platform = MethodChannel('com.cadman.veloce/apps');
  static const _control = MethodChannel('com.cadman.veloce/control');

  bool isEnabled = false;
  String mode = 'exclusive'; // 'exclusive' | 'inclusive'
  bool showSystemApps = false;

  List<String> selectedPackages = [];
  List<String> excludedIpsDomains = [];

  List<AppInfo> allApps = [];
  bool isLoadingApps = false;
  String? appsError;

  bool _settingsLoaded = false;
  bool get settingsLoaded => _settingsLoaded;

  int _fetchGeneration = 0;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    isEnabled = prefs.getBool('split_enabled') ?? false;
    mode = prefs.getString('split_mode') ?? 'exclusive';
    showSystemApps = prefs.getBool('split_show_system') ?? false;
    selectedPackages = prefs.getStringList('selected_packages') ?? [];
    excludedIpsDomains = prefs.getStringList('excluded_ips') ?? [];
    _settingsLoaded = true;
    notifyListeners();
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('split_enabled', isEnabled);
    await prefs.setString('split_mode', mode);
    await prefs.setBool('split_show_system', showSystemApps);
    await prefs.setStringList('selected_packages', selectedPackages);
    await prefs.setStringList('excluded_ips', excludedIpsDomains);
    notifyListeners();
    await _syncNativeSettings();
  }

  /// Keeps the Quick Settings tile's last-connection settings in sync even
  /// when the user changes them while disconnected.
  Future<void> _syncNativeSettings() async {
    try {
      await _control.invokeMethod('saveSplitSettings', {
        'splitEnabled': isEnabled,
        'splitMode': mode,
        'selectedApps': selectedPackages,
        'excludedIps': excludedIpsDomains,
      });
    } catch (e) {
      debugPrint('Error syncing split settings to native: $e');
    }
  }

  Future<void> fetchApps() async {
    final generation = ++_fetchGeneration;
    isLoadingApps = true;
    appsError = null;
    notifyListeners();

    try {
      final List<dynamic> result =
          await _platform.invokeMethod('getInstalledApps', {
        'includeSystem': showSystemApps,
      });

      final apps = <AppInfo>[];
      for (final item in result) {
        if (item is! Map) continue;
        final name = item['name'];
        final package = item['package'];
        if (name is! String || package is! String) continue;

        Uint8List? icon;
        final rawIcon = item['icon'];
        if (rawIcon is List) {
          try {
            icon = Uint8List.fromList(List<int>.from(rawIcon));
          } catch (_) {
            icon = null;
          }
        }

        apps.add(AppInfo(
          name: name,
          packageName: package,
          isSystem: item['isSystem'] as bool? ?? false,
          icon: icon,
        ));
      }

      // Fast toggling of "show system apps" can start overlapping requests;
      // only the newest result may win.
      if (generation == _fetchGeneration) {
        allApps = apps;
      }
    } catch (e) {
      if (generation == _fetchGeneration) {
        appsError = e.toString();
      }
      debugPrint('Error fetching apps: $e');
    } finally {
      if (generation == _fetchGeneration) {
        isLoadingApps = false;
        notifyListeners();
      }
    }
  }

  void toggleEnabled(bool value) {
    isEnabled = value;
    saveSettings();
  }

  void setMode(String newMode) {
    if (newMode != 'exclusive' && newMode != 'inclusive') return;
    mode = newMode;
    saveSettings();
  }

  void toggleAppSelection(String packageName) {
    if (selectedPackages.contains(packageName)) {
      selectedPackages.remove(packageName);
    } else {
      selectedPackages.add(packageName);
    }
    saveSettings();
  }

  void toggleShowSystemApps(bool value) {
    showSystemApps = value;
    saveSettings();
    fetchApps();
  }

  void addIpExclusion(String item) {
    final value = item.trim();
    if (value.isEmpty || excludedIpsDomains.contains(value)) return;
    excludedIpsDomains.add(value);
    saveSettings();
  }

  void removeIpExclusion(String item) {
    excludedIpsDomains.remove(item);
    saveSettings();
  }

  void clearAllIpExclusions() {
    excludedIpsDomains.clear();
    saveSettings();
  }
}
