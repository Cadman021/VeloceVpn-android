import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

class ThemeController extends ChangeNotifier {
  bool _isDark = true;
  bool get isDark => _isDark;
  AppColors get colors => _isDark ? AppColors.dark : AppColors.light;
  Brightness get brightness => _isDark ? Brightness.dark : Brightness.light;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isDark = (prefs.getString('theme') ?? 'dark') == 'dark';
    notifyListeners();
  }

  Future<void> setDark(bool dark) async {
    _isDark = dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', dark ? 'dark' : 'light');
    notifyListeners();
  }
}
