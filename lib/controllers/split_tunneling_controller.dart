import 'package:flutter/material.dart';
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
  static const _platform = MethodChannel('com.veloce.veloce_vpn/apps');

  bool isEnabled = false;
  String mode = 'exclusive'; // 'exclusive' | 'inclusive'
  bool showSystemApps = false;
  
  List<String> selectedPackages = [];
  List<String> excludedIpsDomains = [];

  List<AppInfo> allApps = [];
  bool isLoadingApps = false;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    isEnabled = prefs.getBool('split_enabled') ?? false;
    mode = prefs.getString('split_mode') ?? 'exclusive';
    selectedPackages = prefs.getStringList('selected_packages') ?? [];
    excludedIpsDomains = prefs.getStringList('excluded_ips') ?? [];
    notifyListeners();
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('split_enabled', isEnabled);
    await prefs.setString('split_mode', mode);
    await prefs.setStringList('selected_packages', selectedPackages);
    await prefs.setStringList('excluded_ips', excludedIpsDomains);
    notifyListeners();
  }

  Future<void> fetchApps() async {
    isLoadingApps = true;
    notifyListeners();

    try {
      final List<dynamic> result = await _platform.invokeMethod('getInstalledApps', {
        'includeSystem': showSystemApps,
      });

      allApps = result.map((item) {
        return AppInfo(
          name: item['name'] as String,
          packageName: item['package'] as String,
          isSystem: item['isSystem'] as bool,
          icon: item['icon'] != null ? Uint8List.fromList(List<int>.from(item['icon'])) : null,
        );
      }).toList();
    } catch (e) {
      debugPrint("Error fetching apps: $e");
    } finally {
      isLoadingApps = false;
      notifyListeners();
    }
  }

  void toggleEnabled(bool value) {
    isEnabled = value;
    saveSettings();
  }

  void setMode(String newMode) {
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
    fetchApps();
  }

  void addIpExclusion(String item) {
    if (item.trim().isNotEmpty && !excludedIpsDomains.contains(item.trim())) {
      excludedIpsDomains.add(item.trim());
      saveSettings();
    }
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