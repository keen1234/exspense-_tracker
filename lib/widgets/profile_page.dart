import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../database/db_helper.dart';
import '../models/account_session.dart';
import '../services/settings_service.dart';
import 'calculator_dialog.dart' show CalculatorDialog;

class ProfilePage extends StatefulWidget {
  final VoidCallback? onOpenSettings;

  const ProfilePage({super.key, this.onOpenSettings});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  List<AccountSession> _accounts = const [];
  String _activeAccountId = '';
  bool _isLoading = false;
  String _appVersionLabel = 'Version -';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAppVersion();
  }

  void _loadSettings() {
    final settings = SettingsService();
    setState(() {
      _accounts = settings.getAccounts();
      _activeAccountId = settings.getCurrentAccount().id;
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      if (mounted) {
        setState(() => _appVersionLabel = 'Version $version');
      }
    } catch (_) {}
  }

  Future<void> _addAccount() async {
    final controller = TextEditingController();
    final settings = SettingsService();
    final accountName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Account'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Account name',
            hintText: 'Personal, Work, Business',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();

    final trimmedName = accountName?.trim();
    if (trimmedName == null || trimmedName.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final account = await settings.addAccount(trimmedName);
      await DBHelper.close();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Switched to ${account.name}')),
      );
      _loadSettings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to add account: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _renameAccount(AccountSession account) async {
    final controller = TextEditingController(text: account.name);
    final accountName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Account Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Account name'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    final trimmedName = accountName?.trim();
    if (trimmedName == null || trimmedName.isEmpty || trimmedName == account.name) return;

    setState(() => _isLoading = true);

    try {
      await SettingsService().renameAccount(account.id, trimmedName);
      if (!mounted) return;
      _loadSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Renamed to $trimmedName')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to rename: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _switchAccount(String accountId) async {
    if (accountId == _activeAccountId) return;

    setState(() => _isLoading = true);

    try {
      final settings = SettingsService();
      final selectedAccount = _accounts.firstWhere((a) => a.id == accountId);
      await settings.switchAccount(accountId);
      await DBHelper.close();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Switched to ${selectedAccount.name}')),
      );
      _loadSettings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to switch: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentAccount = _accounts.isNotEmpty
        ? _accounts.firstWhere(
            (a) => a.id == _activeAccountId,
            orElse: () => _accounts.first,
          )
        : AccountSession(id: 'default', name: 'Personal', databaseName: 'expenses.db', createdAt: DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate),
            tooltip: 'Calculator',
            onPressed: () => showDialog(
              context: context,
              builder: (context) => CalculatorDialog(
                onUseResult: (result) {
                  if (!mounted) return;
                  final text = result.toStringAsFixed(2);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Calculated: $text'),
                      action: SnackBarAction(
                        label: 'Copy',
                        onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (widget.onOpenSettings != null)
            IconButton(
              icon: const Icon(Icons.settings_rounded),
              tooltip: 'Settings',
              onPressed: widget.onOpenSettings,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            currentAccount.name.isNotEmpty
                                ? currentAccount.name.substring(0, 1).toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          currentAccount.name,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _appVersionLabel,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'ACCOUNTS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (final account in _accounts)
                        ListTile(
                          leading: CircleAvatar(
                            child: Text(account.name.substring(0, 1).toUpperCase()),
                          ),
                          title: Text(account.name),
                          subtitle: Text(
                            account.id == _activeAccountId
                                ? 'Current session'
                                : 'Tap to switch',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                account.id == _activeAccountId
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: account.id == _activeAccountId
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).disabledColor,
                              ),
                              IconButton(
                                tooltip: 'Edit account name',
                                icon: const Icon(Icons.edit_outlined),
                                color: Theme.of(context).colorScheme.primary,
                                onPressed: () => _renameAccount(account),
                              ),
                            ],
                          ),
                          onTap: () => _switchAccount(account.id),
                        ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.person_add_alt_1),
                        title: const Text('Add Account'),
                        subtitle: const Text('Create another separate session'),
                        onTap: _addAccount,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
