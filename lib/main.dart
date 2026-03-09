import 'package:flutter/material.dart';
import 'services/settings_service.dart';
import 'services/update_service.dart';
import 'models/entry.dart';
import 'models/tag.dart';
import 'repositories/expense_repository.dart';
import 'widgets/add_entry_dialog.dart' show AddEntryDialog;
import 'widgets/tag_manager_page.dart' show TagManagerPage;
import 'widgets/statistics_page.dart' show StatisticsPage;
import 'widgets/calculator_dialog.dart' show CalculatorDialog;
import 'widgets/settings_page.dart' show SettingsPage;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize settings
  await SettingsService().init();

  runApp(const ExpenseApp());
}

class ExpenseApp extends StatelessWidget {
  const ExpenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ExpenseHome(),
    );
  }
}

class ExpenseHome extends StatefulWidget {
  const ExpenseHome({super.key});

  @override
  State<ExpenseHome> createState() => _ExpenseHomeState();
}

class _ExpenseHomeState extends State<ExpenseHome> {
  List<Entry> _entries = [];
  List<Tag> _tags = [];
  bool _isLoading = true;
  String? _errorMessage;
  double _balance = 0.0;
  String _currencySymbol = '₱';
  String _currencyCode = 'PHP';
  bool _isCheckingForUpdates = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    if (_isCheckingForUpdates) {
      return;
    }

    _isCheckingForUpdates = true;
    try {
      final updateService = UpdateService();
      final updateResult = await updateService.checkForUpdate();
      if (!mounted || !updateResult.hasUpdate) {
        return;
      }

      await updateService.showRequiredUpdateDialog(context, updateResult);
    } finally {
      _isCheckingForUpdates = false;
    }
  }

  void _loadSettings() {
    final settings = SettingsService();
    final currencyCode = settings.getCurrency();
    final currencies = {
      'PHP': '₱', 'USD': '\$', 'EUR': '€', 'GBP': '£', 'JPY': '¥',
      'KRW': '₩', 'CNY': '¥', 'INR': '₹', 'AUD': 'A\$', 'CAD': 'C\$',
      'CHF': 'Fr', 'SGD': 'S\$', 'HKD': 'HK\$', 'THB': '฿', 'IDR': 'Rp',
      'MYR': 'RM', 'VND': '₫', 'NZD': 'NZ\$', 'BRL': 'R\$', 'MXN': '\$',
      'RUB': '₽', 'ZAR': 'R', 'AED': 'د.إ', 'SAR': '﷼', 'TRY': '₺',
    };

    setState(() {
      _currencyCode = currencyCode;
      _currencySymbol = currencies[currencyCode] ?? '₱';
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        ExpenseRepository.getAllEntries(),
        ExpenseRepository.getAllTags(),
        ExpenseRepository.getBalance(),
      ]);

      setState(() {
        _entries = results[0] as List<Entry>;
        _tags = results[1] as List<Tag>;
        _balance = results[2] as double;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load data: $e';
        _isLoading = false;
      });
    }
  }

  Future<bool> _addEntry(Entry entry) async {
    try {
      await ExpenseRepository.insertEntry(entry);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry added successfully')),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add entry: $e')),
        );
      }
      return false;
    }
  }

  Future<bool> _updateEntry(Entry entry) async {
    try {
      await ExpenseRepository.updateEntry(entry);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry updated successfully')),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update entry: $e')),
        );
      }
      return false;
    }
  }

  Future<void> _deleteEntry(Entry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry'),
        content: Text('Delete ${_formatMoney(entry.amount)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || entry.id == null) return;

    try {
      await ExpenseRepository.deleteEntry(entry.id!);
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  void _openCalculator() {
    showDialog(
      context: context,
      builder: (context) => CalculatorDialog(
        onUseResult: (result) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Calculated: ${_formatMoney(result)}'),
              action: SnackBarAction(
                label: 'Copy',
                onPressed: () {},
              ),
            ),
          );
        },
      ),
    );
  }

  void _openSettings() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );

    // Refresh data and settings if import was successful or currency changed
    if (result == true) {
      _loadSettings();
      _loadData();
    }
  }

  Tag? _getTagForEntry(Entry entry) {
    try {
      return _tags.firstWhere((t) => t.id == entry.tagId);
    } catch (e) {
      return null;
    }
  }

  String _formatMoney(double amount, {bool absolute = false}) {
    final value = absolute ? amount.abs() : amount;
    final sign = !absolute && value < 0 ? '-' : '';
    return '$sign$_currencySymbol${value.abs().toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Tracker'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate),
            tooltip: 'Calculator',
            onPressed: _openCalculator,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Statistics',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StatisticsPage(currencySymbol: _currencySymbol),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.category),
            tooltip: 'Manage Tags',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TagManagerPage()),
              ).then((_) => _loadData());
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorView()
          : _buildContent(colorScheme),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _tags.isEmpty
            ? () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TagManagerPage()),
          ).then((_) => _loadData());
        }
            : () => showDialog(
          context: context,
          builder: (_) => AddEntryDialog(
            onSaveEntry: _addEntry,
            tags: _tags,
            currencySymbol: _currencySymbol,
          ),
        ),
        icon: const Icon(Icons.add),
        label: Text(_tags.isEmpty ? 'Create Tag' : 'Add Entry'),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadData,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme) {
    return Column(
      children: [
        // Balance Card
        Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  'Current Balance ($_currencyCode)',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatMoney(_balance),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: _balance >= 0 ? Colors.green : Colors.red,
                  ),
                ),
                if (_balance != 0)
                  Text(
                    _balance > 0 ? 'Positive Balance' : 'Negative Balance',
                    style: TextStyle(
                      color: _balance > 0 ? Colors.green : Colors.red,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Summary Chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _buildSummaryChip(
                  'Income',
                  _entries.where((e) => e.isIncome).fold(0.0, (sum, e) => sum + e.amount),
                  Colors.green,
                  Icons.arrow_upward,
                  absolute: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSummaryChip(
                  'Expenses',
                  _entries.where((e) => e.isExpense).fold(0.0, (sum, e) => sum + e.amount.abs()),
                  Colors.red,
                  Icons.arrow_downward,
                  absolute: true,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Entries List
        Expanded(
          child: _entries.isEmpty
              ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No entries yet',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                Text(
                  'Tap + to add your first entry',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          )
              : ListView.builder(
            itemCount: _entries.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              final entry = _entries[index];
              final tag = _getTagForEntry(entry);
              return _buildEntryTile(entry, tag);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryChip(
    String label,
    double amount,
    Color color,
    IconData icon, {
    bool absolute = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text(
                  _formatMoney(amount, absolute: absolute),
                  style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryTile(Entry entry, Tag? tag) {
    final isIncome = entry.isIncome;
    final color = isIncome ? Colors.green : Colors.red;

    return Dismissible(
      key: Key('entry_${entry.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        await _deleteEntry(entry);
        return false;
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          onTap: () => showDialog(
            context: context,
            builder: (_) => AddEntryDialog(
              onSaveEntry: _updateEntry,
              tags: _tags,
              currencySymbol: _currencySymbol,
              initialEntry: entry,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.1),
            child: Icon(
              isIncome ? Icons.arrow_upward : Icons.arrow_downward,
              color: color,
            ),
          ),
          title: Text(
            _formatMoney(entry.amount),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (tag != null)
                Row(
                  children: [
                    Icon(Icons.label, size: 14, color: tag.type.color),
                    const SizedBox(width: 4),
                    Text(
                      tag.name,
                      style: TextStyle(color: tag.type.color, fontSize: 12),
                    ),
                  ],
                ),
              if (entry.note != null) ...[
                const SizedBox(height: 4),
                Text(
                  entry.note!,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 4),
              Text(
                _formatDate(entry.date),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.grey),
                tooltip: 'Edit Entry',
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => AddEntryDialog(
                    onSaveEntry: _updateEntry,
                    tags: _tags,
                    currencySymbol: _currencySymbol,
                    initialEntry: entry,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                onPressed: () => _deleteEntry(entry),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entryDate = DateTime(date.year, date.month, date.day);

    if (entryDate == today) {
      return 'Today';
    } else if (entryDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
