import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';
import 'dart:io';
import '../database/db_helper.dart';
import '../models/currencies.dart';
import '../repositories/expense_repository.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import 'calculator_dialog.dart' show CalculatorDialog;

class SettingsPage extends StatefulWidget {
  final VoidCallback? onChanged;
  final VoidCallback? onOpenSettings;

  const SettingsPage({super.key, this.onChanged, this.onOpenSettings});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _selectedCurrencyCode = 'PHP';
  ThemeMode _themeMode = ThemeMode.system;
  bool _isLoading = false;
  String _appVersionLabel = 'Version -';

  String get _themeName {
    final name = _themeMode.toString().split('.').last;
    return name[0].toUpperCase() + name.substring(1);
  }

  void _notifyChanged() {
    if (widget.onChanged != null) {
      widget.onChanged!();
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAppVersion();
  }

  void _loadSettings() {
    final settings = SettingsService();
    setState(() {
      _selectedCurrencyCode = settings.getCurrency();
      _themeMode = settings.getThemeMode();
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final label = 'Version $version';

      if (mounted) {
        setState(() => _appVersionLabel = label);
      }
    } catch (_) {}
  }

  Future<(String, String, Uint8List)> _createBackupData() async {
    final entries = await ExpenseRepository.getAllEntries(orderBy: 'date DESC');
    final tags = await ExpenseRepository.getAllTags();
    final groups = await ExpenseRepository.getAllTagGroups();

    final exportData = {
      'exportDate': DateTime.now().toIso8601String(),
      'appVersion': _appVersionLabel.replaceFirst('Version ', ''),
      'currency': _selectedCurrencyCode,
      'tagGroups': groups.map((g) => g.toMap()).toList(),
      'tags': tags.map((t) => t.toMap()).toList(),
      'entries': entries.map((e) => e.toMap()).toList(),
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
    final fileName = 'expense_backup_${DateTime.now().millisecondsSinceEpoch}.json';
    final bytes = Uint8List.fromList(utf8.encode(jsonString));
    return (fileName, jsonString, bytes);
  }

  Future<void> _shareBackupFile(String fileName, String jsonString) async {
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsString(jsonString);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Expense Tracker Backup',
      ),
    );
  }

  Future<bool> _saveBackupFile(String fileName, Uint8List bytes) async {
    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Save Expense Backup',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );

    if (savePath == null) {
      return false;
    }

    return true;
  }

  Future<String?> _showExportOptions() async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Data'),
        content: const Text('How would you like to export your backup file?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('Save File'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('share'),
            child: const Text('Share File'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeCurrency(String currencyCode) async {
    final settings = SettingsService();
    await settings.setCurrency(currencyCode);

    setState(() {
      _selectedCurrencyCode = currencyCode;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Currency changed to ${currencies[currencyCode]?.name ?? currencyCode}'),
        ),
      );
      _notifyChanged();
    }
  }

  Future<void> _exportDatabase() async {
    final exportMode = await _showExportOptions();
    if (exportMode == null) return;

    setState(() => _isLoading = true);

    try {
      final backup = await _createBackupData();
      final fileName = backup.$1;
      final jsonString = backup.$2;
      final bytes = backup.$3;

      final completed = exportMode == 'save'
          ? await _saveBackupFile(fileName, bytes)
          : true;

      if (exportMode == 'share') {
        await _shareBackupFile(fileName, jsonString);
      }

      if (!completed) {
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database exported successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _parseImportData(String rawContent) {
    String normalize(String value) {
      var normalized = value.trim();
      if (normalized.startsWith('\uFEFF')) {
        normalized = normalized.substring(1).trimLeft();
      }
      return normalized;
    }

    dynamic decodeContent(String content) {
      final decoded = jsonDecode(content);
      if (decoded is String) {
        return decodeContent(normalize(decoded));
      }
      return decoded;
    }

    final normalized = normalize(rawContent);

    try {
      final decoded = decodeContent(normalized);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      final firstBrace = normalized.indexOf('{');
      final lastBrace = normalized.lastIndexOf('}');

      if (firstBrace != -1 && lastBrace > firstBrace) {
        final extracted = normalized.substring(firstBrace, lastBrace + 1);
        final decoded = decodeContent(extracted);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }
      rethrow;
    }

    throw const FormatException('Backup file is not a valid JSON object.');
  }

  Future<void> _importDatabase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Data'),
        content: const Text(
            'WARNING: This will affect your current data. '
                'Make sure to export your current data first if you want to keep it.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final filePath = result.files.first.path;
      if (filePath == null) {
        throw Exception('Invalid file path');
      }

      final file = File(filePath);
      final jsonString = await file.readAsString();
      final importData = _parseImportData(jsonString);

      if (!importData.containsKey('tags') || !importData.containsKey('entries')) {
        throw Exception('Invalid backup file format');
      }

      if (mounted) {
        final mergeOption = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Import Options'),
            content: const Text('How would you like to import the data?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop('cancel'),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop('replace'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Replace All'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop('merge'),
                child: const Text('Merge'),
              ),
            ],
          ),
        );

        if (mergeOption == 'cancel' || mergeOption == null) {
          setState(() => _isLoading = false);
          return;
        }

        await _processImport(importData, mergeOption);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _processImport(Map<String, dynamic> importData, String mode) async {
    final importedCurrency = importData['currency'] as String?;
    final importedGroups = (importData['tagGroups'] as List? ?? const [])
        .map((group) => Map<String, dynamic>.from(group as Map))
        .toList();
    final importedTags = (importData['tags'] as List)
        .map((tag) => Map<String, dynamic>.from(tag as Map))
        .toList();
    final importedEntries = (importData['entries'] as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();

    final importedGroupIds = <int>{};
    for (final groupMap in importedGroups) {
      final oldId = (groupMap['id'] as num?)?.toInt();
      final groupName = (groupMap['name'] as String?)?.trim() ?? '';

      if (oldId == null) {
        throw const FormatException('Each imported group must include an id.');
      }
      if (groupName.isEmpty) {
        throw const FormatException('Imported groups must have a name.');
      }

      importedGroupIds.add(oldId);
    }

    final importedTagIds = <int>{};
    for (final tagMap in importedTags) {
      final oldId = (tagMap['id'] as num?)?.toInt();
      final tagName = (tagMap['name'] as String?)?.trim() ?? '';
      final tagType = tagMap['type'] as String?;
      final groupId = (tagMap['group_id'] as num?)?.toInt();

      if (oldId == null) {
        throw const FormatException('Each imported tag must include an id.');
      }
      if (tagName.isEmpty) {
        throw const FormatException('Imported tags must have a name.');
      }
      if (tagType != 'expense' && tagType != 'income') {
        throw FormatException('Invalid tag type found for "$tagName".');
      }
      if (groupId != null && !importedGroupIds.contains(groupId)) {
        throw FormatException('Imported tag "$tagName" references an unknown group id: $groupId');
      }

      importedTagIds.add(oldId);
    }

    for (final entryMap in importedEntries) {
      final tagId = (entryMap['tag_id'] as num?)?.toInt();
      if (tagId == null || !importedTagIds.contains(tagId)) {
        throw FormatException('Import file contains an entry with unknown tag id: $tagId');
      }
    }

    final db = await DBHelper.database;

    final importCounts = await db.transaction<(int, int, int)>((txn) async {
      if (mode == 'replace') {
        await txn.delete('entries');
        await txn.delete('tags');
        await txn.delete('tag_groups');
      }

      final groupIdMap = <int, int>{};
      final tagIdMap = <int, int>{};
      var importedGroupCount = 0;
      var importedTagCount = 0;
      var importedEntryCount = 0;

      for (final groupMap in importedGroups) {
        final oldId = (groupMap['id'] as num).toInt();
        final groupName = (groupMap['name'] as String).trim();

        if (mode == 'merge') {
          final existing = await txn.query(
            'tag_groups',
            where: 'LOWER(name) = LOWER(?)',
            whereArgs: [groupName],
            limit: 1,
          );

          if (existing.isNotEmpty) {
            groupIdMap[oldId] = existing.first['id'] as int;
            continue;
          }
        }

        final newId = await txn.insert('tag_groups', {'name': groupName});
        importedGroupCount++;
        groupIdMap[oldId] = newId;
      }

      for (final tagMap in importedTags) {
        final oldId = (tagMap['id'] as num).toInt();
        final tagName = (tagMap['name'] as String).trim();
        final tagType = tagMap['type'] as String;
        final oldGroupId = (tagMap['group_id'] as num?)?.toInt();
        final newGroupId = oldGroupId == null ? null : groupIdMap[oldGroupId];

        if (mode == 'merge') {
          final existing = await txn.query(
            'tags',
            where: 'LOWER(name) = LOWER(?) AND type = ?',
            whereArgs: [tagName, tagType],
            limit: 1,
          );

          if (existing.isNotEmpty) {
            final existingId = existing.first['id'] as int;
            tagIdMap[oldId] = existingId;
            if (newGroupId != null) {
              await txn.update(
                'tags',
                {'group_id': newGroupId},
                where: 'id = ? AND group_id IS NULL',
                whereArgs: [existingId],
              );
            }
            continue;
          }
        }

        final newId = await txn.insert('tags', {
          'name': tagName,
          'type': tagType,
          'group_id': newGroupId,
        });

        importedTagCount++;
        tagIdMap[oldId] = newId;
      }

      for (final entryMap in importedEntries) {
        final oldTagId = (entryMap['tag_id'] as num).toInt();
        final newTagId = tagIdMap[oldTagId];

        if (newTagId == null) {
          throw FormatException('Unable to map imported entry to tag id $oldTagId');
        }

        final amount = (entryMap['amount'] as num).toDouble();
        final date = entryMap['date'] as String;
        final note = entryMap['note'] as String?;

        if (mode == 'merge') {
          final existing = await txn.query(
            'entries',
            columns: ['note'],
            where: 'amount = ? AND date = ? AND tag_id = ?',
            whereArgs: [amount, date, newTagId],
          );

          final duplicateExists = existing.any((row) => row['note'] == note);
          if (duplicateExists) {
            continue;
          }
        }

        await txn.insert('entries', {
          'amount': amount,
          'date': date,
          'note': note,
          'tag_id': newTagId,
        });
        importedEntryCount++;
      }

      return (importedGroupCount, importedTagCount, importedEntryCount);
    });

    if (importedCurrency != null && currencies.containsKey(importedCurrency)) {
      await SettingsService().setCurrency(importedCurrency);
      if (mounted) {
        setState(() => _selectedCurrencyCode = importedCurrency);
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
                  'Import successful! '
                  '${importCounts.$1} groups, '
                  '${importCounts.$2} tags, '
                  '${importCounts.$3} entries imported.'
          ),
        ),
      );
      _notifyChanged();
    }
  }

  Future<void> _clearAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data', style: TextStyle(color: Colors.red)),
        content: const Text(
            'This will PERMANENTLY delete all your entries and tags. '
                'This action cannot be undone. Are you sure?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final db = await DBHelper.database;
      await db.delete('entries');
      await db.delete('tags');
      await db.delete('tag_groups');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data cleared')),
        );
        _notifyChanged();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing data: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() => _isLoading = true);

    try {
      final updateService = UpdateService();
      final updateResult = await updateService.checkForUpdate();
      if (!mounted) {
        return;
      }

      if (updateResult.hasUpdate) {
        await updateService.showRequiredUpdateDialog(context, updateResult);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updateResult.message ?? 'You already have the latest version installed.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update check failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCurrency = currencies[_selectedCurrencyCode] ?? currencies['PHP']!;
    final updateService = UpdateService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate),
            tooltip: 'Calculator',
            onPressed: () => showDialog(
              context: context,
              builder: (context) => CalculatorDialog(
                currencyCode: _selectedCurrencyCode,
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
        children: [
          _buildSectionHeader('Currency'),
          ListTile(
            leading: const Icon(Icons.attach_money),
            title: const Text('Currency'),
            subtitle: Text('${selectedCurrency.flag} ${selectedCurrency.name} (${selectedCurrency.symbol})'),
            trailing: DropdownButton<String>(
              value: _selectedCurrencyCode,
              underline: const SizedBox(),
              items: currencies.entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(entry.value.flag),
                      const SizedBox(width: 8),
                      Text('${entry.value.symbol} ${entry.key}'),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) _changeCurrency(value);
              },
            ),
          ),

           const Divider(),

           _buildSectionHeader('Theme'),

           ListTile(
             leading: const Icon(Icons.dark_mode),
             title: Text(_themeName),
             trailing: SegmentedButton<ThemeMode>(
               segments: const [
                 ButtonSegment(
                   value: ThemeMode.system,
                   icon: Icon(Icons.brightness_auto),
                   label: Text('System'),
                 ),
                 ButtonSegment(
                   value: ThemeMode.light,
                   icon: Icon(Icons.light_mode),
                   label: Text('Light'),
                 ),
                 ButtonSegment(
                   value: ThemeMode.dark,
                   icon: Icon(Icons.dark_mode),
                   label: Text('Dark'),
                 ),
               ],
               selected: {_themeMode},
               onSelectionChanged: (value) {
                 final mode = value.first;
                 SettingsService().setThemeMode(mode);
                 setState(() => _themeMode = mode);
               },
             ),
           ),

          const Divider(),

          _buildSectionHeader('Data Management'),

          ListTile(
            leading: const Icon(Icons.upload_file, color: Colors.green),
            title: const Text('Export Data'),
            subtitle: const Text('Backup your data to share or save'),
            onTap: _exportDatabase,
          ),

          ListTile(
            leading: const Icon(Icons.download, color: Colors.blue),
            title: const Text('Import Data'),
            subtitle: const Text('Restore from backup file'),
            onTap: _importDatabase,
          ),

          const Divider(),

          _buildSectionHeader('Application'),

          ListTile(
            leading: const Icon(Icons.system_update_alt, color: Colors.orange),
            title: Text(updateService.settingsTitle),
            subtitle: Text(updateService.settingsSubtitle),
            onTap: _checkForUpdates,
          ),

          const Divider(),

          _buildSectionHeader('Danger Zone', color: Colors.red),

          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Clear All Data', style: TextStyle(color: Colors.red)),
            subtitle: const Text('Permanently delete everything'),
            onTap: _clearAllData,
          ),

          const SizedBox(height: 32),

          Center(
            child: Column(
              children: [
                Text(
                  'Expense Tracker',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _appVersionLabel,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color ?? Colors.grey.shade600,
        ),
      ),
    );
  }
}
