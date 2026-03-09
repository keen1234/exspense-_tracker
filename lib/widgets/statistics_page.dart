import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/entry.dart';
import '../models/tag.dart';
import '../repositories/expense_repository.dart';

class StatisticsPage extends StatefulWidget {
  final String currencySymbol;

  const StatisticsPage({Key? key, this.currencySymbol = '₱'}) : super(key: key);

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Entry> _entries = [];
  List<Tag> _tags = [];
  bool _isLoading = true;

  // Date filters
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String _selectedPeriod = 'Last 30 Days';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final entries = await ExpenseRepository.getEntriesByDateRange(_startDate, _endDate);
      final tags = await ExpenseRepository.getAllTags();
      setState(() {
        _entries = entries;
        _tags = tags;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _setPeriod(String period) {
    final now = DateTime.now();
    setState(() {
      _selectedPeriod = period;
      switch (period) {
        case 'Today':
          _startDate = DateTime(now.year, now.month, now.day);
          _endDate = now;
          break;
        case 'This Week':
          _startDate = now.subtract(Duration(days: now.weekday - 1));
          _endDate = now;
          break;
        case 'This Month':
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = now;
          break;
        case 'Last 30 Days':
          _startDate = now.subtract(const Duration(days: 30));
          _endDate = now;
          break;
        case 'This Year':
          _startDate = DateTime(now.year, 1, 1);
          _endDate = now;
          break;
        case 'All Time':
          _startDate = DateTime(2000);
          _endDate = now;
          break;
      }
    });
    _loadData();
  }

  Map<String, dynamic> _calculateStats() {
    double totalIncome = 0;
    double totalExpense = 0;
    Map<int, double> tagTotals = {};
    Map<String, double> dailyTotals = {};
    Map<String, double> monthlyTotals = {};

    for (final entry in _entries) {
      if (entry.isIncome) {
        totalIncome += entry.amount;
      } else {
        totalExpense += entry.amount.abs();
      }

      // Tag totals
      tagTotals[entry.tagId] = (tagTotals[entry.tagId] ?? 0) + entry.amount.abs();

      // Daily totals
      final dayKey = DateFormat('yyyy-MM-dd').format(entry.date);
      dailyTotals[dayKey] = (dailyTotals[dayKey] ?? 0) + entry.amount;

      // Monthly totals
      final monthKey = DateFormat('yyyy-MM').format(entry.date);
      monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? 0) + entry.amount;
    }

    return {
      'income': totalIncome,
      'expense': totalExpense,
      'balance': totalIncome - totalExpense,
      'tagTotals': tagTotals,
      'dailyTotals': dailyTotals,
      'monthlyTotals': monthlyTotals,
    };
  }

  String _formatMoney(double amount, {bool absolute = false}) {
    final value = absolute ? amount.abs() : amount;
    final sign = !absolute && value < 0 ? '-' : '';
    return '$sign${widget.currencySymbol}${value.abs().toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.pie_chart), text: 'Overview'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Trends'),
            Tab(icon: Icon(Icons.category), text: 'Categories'),
            Tab(icon: Icon(Icons.calendar_today), text: 'Daily'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            initialValue: _selectedPeriod,
            onSelected: _setPeriod,
            itemBuilder: (context) => [
              'Today',
              'This Week',
              'This Month',
              'Last 30 Days',
              'This Year',
              'All Time',
            ].map((period) => PopupMenuItem(
              value: period,
              child: Text(period),
            )).toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(_selectedPeriod),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildTrendsTab(),
          _buildCategoriesTab(),
          _buildDailyTab(),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final stats = _calculateStats();
    final income = stats['income'] as double;
    final expense = stats['expense'] as double;
    final balance = stats['balance'] as double;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Summary Cards
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Income',
                  income,
                  Colors.green,
                  Icons.arrow_upward,
                  absolute: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Expenses',
                  expense,
                  Colors.red,
                  Icons.arrow_downward,
                  absolute: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildStatCard('Net Balance', balance, balance >= 0 ? Colors.green : Colors.red, Icons.account_balance),

          const SizedBox(height: 24),

          // Pie Chart
          if (income > 0 || expense > 0) ...[
            const Text('Income vs Expenses', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: PieChart(
                PieChartData(
                  sections: [
                    if (income > 0)
                      PieChartSectionData(
                        color: Colors.green,
                        value: income,
                        title: '${((income / (income + expense)) * 100).toStringAsFixed(1)}%',
                        radius: 100,
                        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    if (expense > 0)
                      PieChartSectionData(
                        color: Colors.red,
                        value: expense,
                        title: '${((expense / (income + expense)) * 100).toStringAsFixed(1)}%',
                        radius: 100,
                        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                  ],
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegend('Income', Colors.green),
                const SizedBox(width: 16),
                _buildLegend('Expenses', Colors.red),
              ],
            ),
          ] else
            const Center(
              child: Text('No data for selected period', style: TextStyle(color: Colors.grey)),
            ),
        ],
      ),
    );
  }

  Widget _buildTrendsTab() {
    final stats = _calculateStats();
    final dailyTotals = stats['dailyTotals'] as Map<String, double>;

    if (dailyTotals.isEmpty) {
      return const Center(child: Text('No data available'));
    }

    final sortedDays = dailyTotals.keys.toList()..sort();
    final spots = sortedDays.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), dailyTotals[e.value] ?? 0);
    }).toList();

    final maxY = dailyTotals.values.reduce((a, b) => a > b ? a : b).abs();
    final minY = dailyTotals.values.reduce((a, b) => a < b ? a : b);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text('Daily Balance Trend', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= 0 && value.toInt() < sortedDays.length) {
                          final date = DateTime.parse(sortedDays[value.toInt()]);
                          return Text('${date.day}/${date.month}', style: const TextStyle(fontSize: 10));
                        }
                        return const Text('');
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: true),
                minX: 0,
                maxX: (sortedDays.length - 1).toDouble(),
                minY: minY * 1.1,
                maxY: maxY * 1.1,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 3,
                    dotData: FlDotData(show: sortedDays.length < 15),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.blue.withOpacity(0.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesTab() {
    final stats = _calculateStats();
    final tagTotals = stats['tagTotals'] as Map<int, double>;

    if (tagTotals.isEmpty) {
      return const Center(child: Text('No data available'));
    }

    final sortedTags = tagTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final total = tagTotals.values.reduce((a, b) => a + b);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedTags.length,
      itemBuilder: (context, index) {
        final tagId = sortedTags[index].key;
        final amount = sortedTags[index].value;
        final tag = _tags.firstWhere((t) => t.id == tagId, orElse: () => Tag(name: 'Unknown', type: TagType.expense));
        final percentage = (amount / total) * 100;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: tag.type.color.withOpacity(0.2),
              child: Icon(tag.type.icon, color: tag.type.color),
            ),
            title: Text(tag.name),
            subtitle: LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(tag.type.color),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatMoney(amount, absolute: true),
                  style: TextStyle(fontWeight: FontWeight.bold, color: tag.type.color),
                ),
                Text('${percentage.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDailyTab() {
    final stats = _calculateStats();
    final dailyTotals = stats['dailyTotals'] as Map<String, double>;

    if (dailyTotals.isEmpty) {
      return const Center(child: Text('No data available'));
    }

    final sortedDays = dailyTotals.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedDays.length,
      itemBuilder: (context, index) {
        final day = sortedDays[index];
        final amount = dailyTotals[day]!;
        final date = DateTime.parse(day);
        final isPositive = amount >= 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isPositive ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
              child: Icon(
                isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                color: isPositive ? Colors.green : Colors.red,
              ),
            ),
            title: Text(DateFormat('EEEE, MMM d, yyyy').format(date)),
            trailing: Text(
              _formatMoney(amount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isPositive ? Colors.green : Colors.red,
                fontSize: 16,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
    String title,
    double amount,
    Color color,
    IconData icon, {
    bool absolute = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              _formatMoney(amount, absolute: absolute),
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(String label, Color color) {
    return Row(
      children: [
        Container(width: 16, height: 16, color: color),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }
}
