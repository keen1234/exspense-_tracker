import 'package:flutter/material.dart';
import '../main.dart' show ExpenseHome, ExpenseHomeState;
import '../models/currencies.dart';
import '../services/settings_service.dart';
import 'add_entry_dialog.dart' show AddEntryDialog;
import 'fab_speed_dial.dart' show FabSpeedDial;
import 'scanner_page.dart' show ScannerPage;
import 'statistics_page.dart' show StatisticsPage;
import 'tag_manager_page.dart' show TagManagerPage;
import 'profile_page.dart' show ProfilePage;
import 'settings_page.dart' show SettingsPage;

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with TickerProviderStateMixin {
  int _currentIndex = 0;
  final _homeKey = GlobalKey<ExpenseHomeState>();
  late final PageController _pageController;

  // FAB show/hide animation
  late AnimationController _fabController;
  late Animation<double> _fabScale;

  // Nav bar entrance animation
  late AnimationController _navEntranceController;
  late Animation<Offset> _navSlide;
  late Animation<double> _navFade;

  String _currencySymbol = '\u20b1';
  String _currencyCode = 'PHP';

  static const _navItems = [
    _NavItem(Icons.home_rounded, 'Home'),
    _NavItem(Icons.bar_chart_rounded, 'Stats'),
    _NavItem(Icons.category_rounded, 'Tags'),
    _NavItem(Icons.person_rounded, 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrency();
    _pageController = PageController(initialPage: 0);

    // FAB show/hide
    _fabController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fabScale = CurvedAnimation(
      parent: _fabController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInBack,
    );

    // Nav bar entrance
    _navEntranceController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _navSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _navEntranceController,
      curve: Curves.easeOutCubic,
    ));
    _navFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _navEntranceController,
      curve: Curves.easeOut,
    ));

    _fabController.value = 1.0;
    _navEntranceController.forward();
  }

  @override
  void dispose() {
    _fabController.dispose();
    _navEntranceController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _loadCurrency() {
    final settings = SettingsService();
    final code = settings.getCurrency();
    if (mounted) {
      setState(() {
        _currencyCode = code;
        _currencySymbol = currencies[code]?.symbol ?? '\u20b1';
      });
    }
  }

  void _onTabSelected(int index, {bool animate = true}) {
    if (_currentIndex == index) return;

    final isHome = index == 0;
    final wasHome = _currentIndex == 0;

    setState(() => _currentIndex = index);

    if (animate) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _pageController.jumpToPage(index);
    }

    if (isHome) {
      _fabController.forward();
      _homeKey.currentState?.loadData();
    } else if (wasHome) {
      _fabController.reverse();
    }
  }

  Future<void> _onFabPressed() async {
    if (_currentIndex != 0) return;

    final tags = _homeKey.currentState?.tags ?? [];

    await showDialog(
      context: context,
      builder: (_) => AddEntryDialog(
        onSaveEntry: (e) async {
          final home = _homeKey.currentState;
          if (home != null) {
            return home.addEntry(e);
          }
          return false;
        },
        tags: tags,
        currencySymbol: _currencySymbol,
        currencyCode: _currencyCode,
      ),
    );
  }

  void _onScannerPressed() {
    if (_currentIndex != 0) return;
    final tags = _homeKey.currentState?.tags ?? [];

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          onSaveEntry: (e) async {
            final home = _homeKey.currentState;
            if (home != null) {
              return home.addEntry(e);
            }
            return false;
          },
          tags: tags,
          currencySymbol: _currencySymbol,
          currencyCode: _currencyCode,
        ),
      ),
    );
  }

  void _onSettingsChanged() {
    _loadCurrency();
    _homeKey.currentState?.loadData();
  }

  bool get _showFab => _currentIndex == 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final pages = <Widget>[
      ExpenseHome(key: _homeKey, onOpenSettings: () => _onTabSelected(4, animate: false)),
      StatisticsPage(currencySymbol: _currencySymbol, currencyCode: _currencyCode, onOpenSettings: () => _onTabSelected(4, animate: false)),
      TagManagerPage(currencyCode: _currencyCode, onOpenSettings: () => _onTabSelected(4, animate: false)),
      ProfilePage(onOpenSettings: () => _onTabSelected(4, animate: false)),
      SettingsPage(onChanged: _onSettingsChanged, onOpenSettings: () => _onTabSelected(4, animate: false)),
    ];

    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(pages.length, (index) {
          return AnimatedBuilder(
            animation: _pageController,
            builder: (context, child) {
              final pos = _pageController.page ?? _currentIndex.toDouble();
              final diff = (pos - index).abs().clamp(0.0, 1.0);
              final slideOffset = Offset(diff * 60 * (index < pos ? -1 : 1), 0);
              return Transform.translate(
                offset: slideOffset,
                child: Transform.scale(
                  scale: 1.0 - (diff * 0.1),
                  child: Opacity(
                    opacity: 1.0 - (diff * 0.5),
                    child: child,
                  ),
                ),
              );
            },
            child: pages[index],
          );
        }),
      ),
      floatingActionButton: Transform.translate(
        offset: const Offset(0, -50),
        child: ScaleTransition(
          scale: _fabScale,
          child: IgnorePointer(
            ignoring: !_showFab,
            child: FabSpeedDial(
              onAddEntry: _onFabPressed,
              onScanner: _onScannerPressed,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: SlideTransition(
        position: _navSlide,
        child: FadeTransition(
          opacity: _navFade,
          child: BottomAppBar(
            color: colorScheme.surface,
            elevation: 8,
            shadowColor: colorScheme.shadow.withValues(alpha: 0.12),
            child: SafeArea(
              child: SizedBox(
                height: 56,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavItem(0, colorScheme),
                    _buildNavItem(1, colorScheme),
                    _buildNavItem(2, colorScheme),
                    _buildNavItem(3, colorScheme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, ColorScheme colorScheme) {
    final item = _navItems[index];
    final isActive = _currentIndex == index;

    return GestureDetector(
      onTap: () => _onTabSelected(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isActive
              ? colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isActive ? 1.2 : 1.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              child: Icon(
                item.icon,
                color: isActive
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                size: 24,
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                fontSize: isActive ? 11 : 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}
