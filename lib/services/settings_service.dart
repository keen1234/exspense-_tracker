import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _currencyKey = 'selected_currency';
  static const String _firstRunKey = 'first_run';

  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Currency
  String getCurrency() {
    return _prefs?.getString(_currencyKey) ?? 'PHP'; // Default to PHP
  }

  Future<void> setCurrency(String currencyCode) async {
    await _prefs?.setString(_currencyKey, currencyCode);
  }

  // Check if first run (for database initialization)
  bool isFirstRun() {
    return _prefs?.getBool(_firstRunKey) ?? true;
  }

  Future<void> setFirstRun(bool value) async {
    await _prefs?.setBool(_firstRunKey, value);
  }

  // Clear all settings
  Future<void> clear() async {
    await _prefs?.clear();
  }
}