import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists app light/dark mode and exposes [ThemeMode] for [MaterialApp].
class ThemeProvider extends ChangeNotifier {
  static const _prefKey = 'use_dark_theme';

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final useDark = prefs.getBool(_prefKey) ?? false;
    _themeMode = useDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> setDarkMode(bool enabled) async {
    _themeMode = enabled ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
  }
}
