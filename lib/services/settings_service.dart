import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/account_session.dart';

class SettingsService {
  static const String _currencyKey = 'selected_currency';
  static const String _firstRunKey = 'first_run';
  static const String _accountsKey = 'accounts';
  static const String _activeAccountIdKey = 'active_account_id';
  static const String _defaultAccountId = 'default';
  static const String _defaultDatabaseName = 'expenses.db';

  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _ensureAccountsInitialized();
  }

  // Currency
  String getCurrency() {
    return _prefs?.getString(_currencyKeyForAccount(getCurrentAccount().id)) ??
        'PHP';
  }

  Future<void> setCurrency(String currencyCode) async {
    await _prefs?.setString(
      _currencyKeyForAccount(getCurrentAccount().id),
      currencyCode,
    );
  }

  List<AccountSession> getAccounts() {
    final rawAccounts = _prefs?.getStringList(_accountsKey) ?? const [];
    final accounts = rawAccounts
        .map((value) => jsonDecode(value) as Map<String, dynamic>)
        .map(AccountSession.fromMap)
        .toList()
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));

    if (accounts.isNotEmpty) {
      return accounts;
    }

    return [
      AccountSession(
        id: _defaultAccountId,
        name: 'Personal',
        databaseName: _defaultDatabaseName,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    ];
  }

  AccountSession getCurrentAccount() {
    final accounts = getAccounts();
    final activeAccountId = _prefs?.getString(_activeAccountIdKey);

    return accounts.firstWhere(
      (account) => account.id == activeAccountId,
      orElse: () => accounts.first,
    );
  }

  String getCurrentDatabaseName() {
    return getCurrentAccount().databaseName;
  }

  Future<AccountSession> addAccount(
    String name, {
    String initialCurrencyCode = 'PHP',
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Account name cannot be empty.');
    }

    final accounts = getAccounts();
    final nameExists = accounts.any(
      (account) => account.name.toLowerCase() == trimmedName.toLowerCase(),
    );
    if (nameExists) {
      throw StateError('An account with that name already exists.');
    }

    final createdAt = DateTime.now();
    final id = 'account_${createdAt.microsecondsSinceEpoch}';
    final account = AccountSession(
      id: id,
      name: trimmedName,
      databaseName: 'expenses_$id.db',
      createdAt: createdAt,
    );

    accounts.add(account);
    await _writeAccounts(accounts);
    await _prefs?.setString(
      _currencyKeyForAccount(account.id),
      initialCurrencyCode,
    );
    await switchAccount(account.id);

    return account;
  }

  Future<void> switchAccount(String accountId) async {
    final accountExists = getAccounts().any((account) => account.id == accountId);
    if (!accountExists) {
      throw StateError('Selected account no longer exists.');
    }

    await _prefs?.setString(_activeAccountIdKey, accountId);
  }

  Future<AccountSession> renameAccount(String accountId, String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Account name cannot be empty.');
    }

    final accounts = getAccounts();
    final accountIndex = accounts.indexWhere((account) => account.id == accountId);
    if (accountIndex == -1) {
      throw StateError('Selected account no longer exists.');
    }

    final nameExists = accounts.any(
      (account) =>
          account.id != accountId &&
          account.name.toLowerCase() == trimmedName.toLowerCase(),
    );
    if (nameExists) {
      throw StateError('An account with that name already exists.');
    }

    final current = accounts[accountIndex];
    final updated = AccountSession(
      id: current.id,
      name: trimmedName,
      databaseName: current.databaseName,
      createdAt: current.createdAt,
    );

    accounts[accountIndex] = updated;
    await _writeAccounts(accounts);
    return updated;
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

  Future<void> _ensureAccountsInitialized() async {
    final accounts = _prefs?.getStringList(_accountsKey) ?? const [];
    if (accounts.isEmpty) {
      final legacyCurrency = _prefs?.getString(_currencyKey);
      final defaultAccount = AccountSession(
        id: _defaultAccountId,
        name: 'Personal',
        databaseName: _defaultDatabaseName,
        createdAt: DateTime.now(),
      );
      await _writeAccounts([defaultAccount]);
      await _prefs?.setString(_activeAccountIdKey, defaultAccount.id);
      if (legacyCurrency != null) {
        await _prefs?.setString(
          _currencyKeyForAccount(defaultAccount.id),
          legacyCurrency,
        );
      }
      return;
    }

    final activeAccountId = _prefs?.getString(_activeAccountIdKey);
    if (activeAccountId == null ||
        !getAccounts().any((account) => account.id == activeAccountId)) {
      await _prefs?.setString(_activeAccountIdKey, getAccounts().first.id);
    }
  }

  String _currencyKeyForAccount(String accountId) {
    return '${_currencyKey}_$accountId';
  }

  Future<void> _writeAccounts(List<AccountSession> accounts) async {
    await _prefs?.setStringList(
      _accountsKey,
      accounts.map((account) => jsonEncode(account.toMap())).toList(),
    );
  }
}
