import 'package:flutter/material.dart';

class FabSpeedDial extends StatefulWidget {
  final VoidCallback onAddEntry;
  final VoidCallback onScanner;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const FabSpeedDial({
    super.key,
    required this.onAddEntry,
    required this.onScanner,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  State<FabSpeedDial> createState() => _FabSpeedDialState();
}

class _FabSpeedDialState extends State<FabSpeedDial>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotation;

  late AnimationController _childController;
  late Animation<double> _childScale;
  late Animation<double> _childFade;

  // Pulse glow
  late AnimationController _pulseController;
  late Animation<double> _pulse;

  bool _isOpen = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _rotation = Tween<double>(begin: 0.0, end: 0.75).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _childController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _childScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _childController, curve: Curves.easeOutBack),
    );
    _childFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _childController, curve: Curves.easeOut),
    );

    // Continuous pulse glow
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _childController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _isOpen = !_isOpen);
    if (_isOpen) {
      _controller.forward();
      _childController.forward();
    } else {
      _childController.reverse();
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = widget.backgroundColor ?? colorScheme.primaryContainer;
    final fgColor = widget.foregroundColor ?? colorScheme.onPrimaryContainer;

    return SizedBox(
      width: 320,
      height: 160,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // Row with: [Add Entry] --- [+] --- [Scanner]
          AnimatedBuilder(
            animation: _childController,
            builder: (context, child) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left: Add Entry
                    Transform.translate(
                      offset: Offset(-20 * (1 - _childScale.value), 0),
                      child: Opacity(
                        opacity: _childFade.value.clamp(0.0, 1.0),
                        child: _buildMiniFab(
                          icon: Icons.edit_note_rounded,
                          label: 'Add Entry',
                          bgColor: bgColor,
                          fgColor: fgColor,
                          colorScheme: colorScheme,
                          onTap: () {
                            if (_isOpen) _toggle();
                            widget.onAddEntry();
                          },
                        ),
                      ),
                    ),

                    // Center spacer for main FAB
                    const SizedBox(width: 80),

                    // Right: Scanner
                    Transform.translate(
                      offset: Offset(20 * (1 - _childScale.value), 0),
                      child: Opacity(
                        opacity: _childFade.value.clamp(0.0, 1.0),
                        child: _buildMiniFab(
                          icon: Icons.document_scanner_rounded,
                          label: 'Scanner',
                          bgColor: bgColor,
                          fgColor: fgColor,
                          colorScheme: colorScheme,
                          onTap: () {
                            if (_isOpen) _toggle();
                            widget.onScanner();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Main FAB with pulse glow
          AnimatedBuilder(
            animation: Listenable.merge([_controller, _pulseController]),
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.25 + _pulse.value * 0.2),
                      blurRadius: 16 + _pulse.value * 8,
                      spreadRadius: _pulse.value * 2,
                    ),
                  ],
                ),
                child: Transform.rotate(
                  angle: _rotation.value * 3.14159 * 2,
                  child: FloatingActionButton(
                    onPressed: _toggle,
                    backgroundColor: bgColor,
                    foregroundColor: fgColor,
                    elevation: 0,
                    shape: const CircleBorder(),
                    child: Icon(
                      _isOpen ? Icons.close : Icons.add,
                      size: 28,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMiniFab({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color fgColor,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: bgColor,
            shape: const CircleBorder(),
            elevation: 4,
            shadowColor: colorScheme.shadow.withValues(alpha: 0.2),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(icon, color: fgColor, size: 22),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
