import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'database/db_helper.dart';
import 'services/settings_service.dart';
import 'services/update_service.dart';
import 'models/currencies.dart';
import 'models/entry.dart';
import 'models/tag.dart';
import 'repositories/expense_repository.dart';
import 'widgets/add_entry_dialog.dart' show AddEntryDialog;
import 'widgets/calculator_dialog.dart' show CalculatorDialog;
import 'widgets/app_shell.dart' show AppShell;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch Flutter framework errors
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  // Catch async errors not caught by Flutter
  PlatformDispatcher.instance.onError = (error, stack) {
    return true;
  };

  // Initialize settings
  await SettingsService().init();

  // Warn user if database had to be recreated due to corruption
  DBHelper.onDatabaseReset = (reason) {
    debugPrint('Database reset: $reason');
  };

  runApp(const ExpenseApp());
}

class ExpenseApp extends StatefulWidget {
  const ExpenseApp({super.key});

  @override
  State<ExpenseApp> createState() => _ExpenseAppState();
}

class _ExpenseAppState extends State<ExpenseApp> {
  @override
  void initState() {
    super.initState();
    SettingsService.themeModeNotifier.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SettingsService.themeModeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      themeMode: SettingsService().getThemeMode(),
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
      home: const AppShell(),
    );
  }
}

class ExpenseHome extends StatefulWidget {
  final VoidCallback? onOpenSettings;

  const ExpenseHome({super.key, this.onOpenSettings});

  @override
  State<ExpenseHome> createState() => ExpenseHomeState();
}

class ExpenseHomeState extends State<ExpenseHome> with TickerProviderStateMixin {
  List<Entry> _entries = [];
  List<Tag> _tags = [];
  bool _isLoading = true;
  String? _errorMessage;
  double _balance = 0.0;
  String _currencySymbol = '\u20b1';
  String _currencyCode = 'PHP';
  bool _isCheckingForUpdates = false;
  bool _sortByGroup = true;

  // Staggered list entrance animation
  late AnimationController _listAnimController;
  late Animation<double> _balanceScale;
  late Animation<double> _balanceFade;
  late AnimationController _balanceController;

  List<Tag> get tags => List.unmodifiable(_tags);
  String get currencySymbol => _currencySymbol;
  String get currencyCode => _currencyCode;

  List<Entry>? _cachedSortedEntries;

  Future<void> loadData() => _loadData();
  Future<bool> addEntry(Entry entry) => _addEntry(entry);

  @override
  void initState() {
    super.initState();

    _listAnimController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _balanceController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _balanceScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _balanceController, curve: Curves.elasticOut),
    );
    _balanceFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _balanceController, curve: Curves.easeOut),
    );

    _loadSettings();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  @override
  void dispose() {
    _listAnimController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    if (_isCheckingForUpdates) {
      return;
    }

    final updateService = UpdateService();
    if (!updateService.supportsInAppUpdates) {
      return;
    }

    _isCheckingForUpdates = true;
    try {
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
    setState(() {
      _currencyCode = currencyCode;
      _currencySymbol = currencies[currencyCode]?.symbol ?? '₱';
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

      _cachedSortedEntries = null;
      setState(() {
        _entries = results[0] as List<Entry>;
        _tags = results[1] as List<Tag>;
        _balance = results[2] as double;
        _isLoading = false;
      });

      // Trigger staggered entrance animations
      _listAnimController.forward(from: 0);
      _balanceController.forward(from: 0);
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
    if (entry.id == null) return;
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
        currencyCode: _currencyCode,
        onUseResult: (result) {
          final text = _formatMoney(result);
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
    );
  }

  Tag? _getTagForEntry(Entry entry) {
    for (final tag in _tags) {
      if (tag.id == entry.tagId) return tag;
    }
    return null;
  }

  List<Entry> _sortedEntries() {
    if (_cachedSortedEntries != null) {
      return _cachedSortedEntries!;
    }
    if (!_sortByGroup) {
      _cachedSortedEntries = List.unmodifiable(_entries);
      return _cachedSortedEntries!;
    }

    final sortedEntries = List<Entry>.from(_entries);
    sortedEntries.sort((left, right) {
      final leftTag = _getTagForEntry(left);
      final rightTag = _getTagForEntry(right);

      final leftGroup = leftTag?.normalizedGroupName ?? 'Ungrouped';
      final rightGroup = rightTag?.normalizedGroupName ?? 'Ungrouped';
      final groupCompare = leftGroup.toLowerCase().compareTo(rightGroup.toLowerCase());
      if (groupCompare != 0) {
        return groupCompare;
      }

      final leftTagName = leftTag?.name.toLowerCase() ?? '';
      final rightTagName = rightTag?.name.toLowerCase() ?? '';
      final tagCompare = leftTagName.compareTo(rightTagName);
      if (tagCompare != 0) {
        return tagCompare;
      }

      return right.date.compareTo(left.date);
    });

    _cachedSortedEntries = List.unmodifiable(sortedEntries);
    return _cachedSortedEntries!;
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
          if (widget.onOpenSettings != null)
            IconButton(
              icon: const Icon(Icons.settings_rounded),
              tooltip: 'Settings',
              onPressed: widget.onOpenSettings,
            ),
        ],
      ),
      body: _isLoading
          ? _buildShimmerLoading(colorScheme)
          : _errorMessage != null
          ? _buildErrorView()
          : _buildContent(colorScheme),
    );
  }

  Widget _buildShimmerLoading(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Shimmer balance card
          _ShimmerBox(
            width: double.infinity,
            height: 140,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(height: 16),
          // Shimmer summary chips
          Row(
            children: [
              Expanded(
                child: _ShimmerBox(
                  width: double.infinity,
                  height: 60,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ShimmerBox(
                  width: double.infinity,
                  height: 60,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Shimmer list items
          ...List.generate(5, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ShimmerBox(
              width: double.infinity,
              height: 72,
              borderRadius: BorderRadius.circular(12),
            ),
          )),
        ],
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
    final sortedEntries = _sortedEntries();

    return Column(
      children: [
        // Balance Card
        AnimatedBuilder(
          animation: _balanceController,
          builder: (context, child) {
            return Transform.scale(
              scale: _balanceScale.value,
              alignment: Alignment.topCenter,
              child: Opacity(
                opacity: _balanceFade.value,
                child: child,
              ),
            );
          },
          child: Card(
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

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              const Text(
                'Entries',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              ActionChip(
                avatar: Icon(
                  _sortByGroup ? Icons.sort_by_alpha : Icons.sort,
                  size: 18,
                  color: colorScheme.primary,
                ),
                label: Text(_sortByGroup ? 'Grouped' : 'Default order'),
                labelStyle: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: colorScheme.primary.withValues(alpha: 0.08),
                side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.18)),
                tooltip: _sortByGroup ? 'Grouped Sorting On' : 'Grouped Sorting Off',
                onPressed: () {
                  setState(() {
                    _sortByGroup = !_sortByGroup;
                    _cachedSortedEntries = null;
                  });
                },
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
              : AnimatedBuilder(
            animation: _listAnimController,
            builder: (context, child) {
              return ListView.builder(
                itemCount: sortedEntries.length,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (context, index) {
                  final entry = sortedEntries[index];
                  final tag = _getTagForEntry(entry);
                  // Staggered animation: each item delays based on index
                  final itemDelay = (index / (sortedEntries.length.clamp(1, 15))).clamp(0.0, 1.0);
                  final itemAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
                    CurvedAnimation(
                      parent: _listAnimController,
                      curve: Interval(itemDelay, (itemDelay + 0.4).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
                    ),
                  );
                  return Transform.translate(
                    offset: Offset(0, 20 * (1 - itemAnimation.value)),
                    child: Opacity(
                      opacity: itemAnimation.value,
                      child: _buildEntryTile(entry, tag),
                    ),
                  );
                },
              );
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
        if (confirm != true) return false;
        await _deleteEntry(entry);
        return true;
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
              currencyCode: _currencyCode,
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
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (tag.hasGroup)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                           color: color.withValues(alpha: 0.1),
                           borderRadius: BorderRadius.circular(8),
                           border: Border.all(color: color.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          tag.groupName!,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.label, size: 14, color: tag.type.color),
                        const SizedBox(width: 4),
                        Text(
                          tag.name,
                          style: TextStyle(color: tag.type.color, fontSize: 12),
                        ),
                      ],
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
                    currencyCode: _currencyCode,
                    initialEntry: entry,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                onPressed: () async {
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
                  if (confirm == true) _deleteEntry(entry);
                },
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

/// Animated shimmer placeholder used while data is loading.
class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final highlight = Theme.of(context).colorScheme.surface;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [base, highlight, base],
              stops: [
                (_animation.value - 0.3).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}
