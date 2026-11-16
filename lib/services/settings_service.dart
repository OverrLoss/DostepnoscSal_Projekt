import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  static const String _keyThemeMode = 'app_theme_mode';
  static const String _keyAccentColor = 'app_accent_color';
  static const String _keyDefaultCategory = 'app_default_category';
  static const String _keyDefaultSort = 'app_default_sort';

  ThemeMode _themeMode = ThemeMode.dark;
  String _accentColorName = 'blue';
  String _defaultCategory = 'Prywatny';
  String _defaultSort = 'lastName_asc';
  bool _isInitialized = false;

  ThemeMode get themeMode => _themeMode;
  String get accentColorName => _accentColorName;
  String get defaultCategory => _defaultCategory;
  String get defaultSort => _defaultSort;
  bool get isInitialized => _isInitialized;

  Color get accentColor {
    switch (_accentColorName) {
      case 'blue':
        return const Color(0xFFF2F2F2); // biały (domyślny akcent)
      case 'purple':
        return Colors.purpleAccent;
      case 'amber':
        return Colors.amberAccent;
      case 'green':
      default:
        return Colors.greenAccent;
    }
  }

  String get sqlOrderBy {
    switch (_defaultSort) {
      case 'lastName_desc':
        return 'lastName COLLATE NOCASE DESC, firstName COLLATE NOCASE DESC';
      case 'firstName_asc':
        return 'firstName COLLATE NOCASE ASC, lastName COLLATE NOCASE ASC';
      case 'newest':
        return 'id DESC';
      case 'lastName_asc':
      default:
        return 'lastName COLLATE NOCASE ASC, firstName COLLATE NOCASE ASC';
    }
  }

  Future<void> init() async {
    if (_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();

    final themeStr = prefs.getString(_keyThemeMode) ?? 'dark';
    if (themeStr == 'light') {
      _themeMode = ThemeMode.light;
    } else if (themeStr == 'system') {
      _themeMode = ThemeMode.system;
    } else {
      _themeMode = ThemeMode.dark;
    }

    _accentColorName = prefs.getString(_keyAccentColor) ?? 'blue';
    _defaultCategory = prefs.getString(_keyDefaultCategory) ?? 'Prywatny';
    _defaultSort = prefs.getString(_keyDefaultSort) ?? 'lastName_asc';

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    String val = 'dark';
    if (mode == ThemeMode.light) val = 'light';
    if (mode == ThemeMode.system) val = 'system';
    await prefs.setString(_keyThemeMode, val);
  }

  Future<void> setAccentColorName(String name) async {
    _accentColorName = name;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccentColor, name);
  }

  Future<void> setDefaultCategory(String category) async {
    _defaultCategory = category;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultCategory, category);
  }

  Future<void> setDefaultSort(String sortKey) async {
    _defaultSort = sortKey;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultSort, sortKey);
  }
}
