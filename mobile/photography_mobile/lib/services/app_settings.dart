import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final instance = AppSettings._();
  static const _key = 'snapsync_theme_mode';
  final _storage = const FlutterSecureStorage();
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;
  bool saving = false;
  String? error;

  Future<void> load() async {
    try {
      final value = await _storage.read(key: _key);
      _themeMode = switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      error = null;
    } catch (_) {
      error = 'Could not restore your appearance preference. Choose a theme to save it again.';
    }
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode value) async {
    if (saving) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await _storage.write(key: _key, value: value.name);
      _themeMode = value;
    } catch (_) {
      error = 'Could not save your preference. Please try again.';
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
