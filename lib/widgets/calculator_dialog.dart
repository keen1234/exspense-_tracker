import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

class CalculatorDialog extends StatefulWidget {
  final Function(double result) onUseResult;

  const CalculatorDialog({
    Key? key,
    required this.onUseResult,
  }) : super(key: key);

  @override
  State<CalculatorDialog> createState() => _CalculatorDialogState();
}

class _CalculatorDialogState extends State<CalculatorDialog> {
  String _display = '0';
  String _previousValue = '';
  String _operation = '';
  bool _shouldResetDisplay = false;
  List<String> _history = [];

  void _onNumberPress(String number) {
    setState(() {
      if (_display == '0' || _shouldResetDisplay) {
        _display = number;
        _shouldResetDisplay = false;
      } else {
        if (_display.length < 12) {
          _display += number;
        }
      }
    });
  }

  void _onDecimalPress() {
    setState(() {
      if (_shouldResetDisplay) {
        _display = '0.';
        _shouldResetDisplay = false;
      } else if (!_display.contains('.')) {
        _display += '.';
      }
    });
  }

  void _onOperationPress(String operation) {
    setState(() {
      if (_operation.isNotEmpty && !_shouldResetDisplay) {
        _calculate();
      }
      _previousValue = _display;
      _operation = operation;
      _shouldResetDisplay = true;
    });
  }

  void _calculate() {
    if (_previousValue.isEmpty || _operation.isEmpty) return;

    double prev = double.tryParse(_previousValue) ?? 0;
    double current = double.tryParse(_display) ?? 0;
    double result = 0;

    switch (_operation) {
      case '+':
        result = prev + current;
        break;
      case '-':
        result = prev - current;
        break;
      case '×':
        result = prev * current;
        break;
      case '÷':
        if (current != 0) {
          result = prev / current;
        } else {
          _showError('Cannot divide by zero');
          return;
        }
        break;
      case '%':
        result = prev % current;
        break;
      case '^':
        result = math.pow(prev, current).toDouble();
        break;
    }

    // Add to history
    _history.add('$_previousValue $_operation $current = ${result.toStringAsFixed(2)}');
    if (_history.length > 10) _history.removeAt(0);

    setState(() {
      _display = _formatResult(result);
      _previousValue = '';
      _operation = '';
      _shouldResetDisplay = true;
    });
  }

  String _formatResult(double result) {
    if (result.isInfinite || result.isNaN) return 'Error';

    String formatted = result.toStringAsFixed(8);
    formatted = formatted.replaceAll(RegExp(r'0*$'), '');
    formatted = formatted.replaceAll(RegExp(r'\.$'), '');

    if (formatted.length > 12) {
      formatted = result.toStringAsExponential(6);
    }

    return formatted;
  }

  void _onEqualsPress() {
    if (_operation.isNotEmpty) {
      _calculate();
    }
  }

  void _onClear() {
    setState(() {
      _display = '0';
      _previousValue = '';
      _operation = '';
      _shouldResetDisplay = false;
    });
  }

  void _onClearEntry() {
    setState(() {
      _display = '0';
    });
  }

  void _onBackspace() {
    setState(() {
      if (_display.length > 1) {
        _display = _display.substring(0, _display.length - 1);
      } else {
        _display = '0';
      }
    });
  }

  void _onPercentage() {
    setState(() {
      double value = double.tryParse(_display) ?? 0;
      _display = _formatResult(value / 100);
    });
  }

  void _onSquareRoot() {
    setState(() {
      double value = double.tryParse(_display) ?? 0;
      if (value < 0) {
        _showError('Invalid input');
        return;
      }
      _display = _formatResult(math.sqrt(value));
    });
  }

  void _onSquare() {
    setState(() {
      double value = double.tryParse(_display) ?? 0;
      _display = _formatResult(value * value);
    });
  }

  void _onNegate() {
    setState(() {
      if (_display.startsWith('-')) {
        _display = _display.substring(1);
      } else if (_display != '0') {
        _display = '-$_display';
      }
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _useResult() {
    final result = double.tryParse(_display);
    if (result != null) {
      widget.onUseResult(result);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 350,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_previousValue.isNotEmpty)
                    Text(
                      '$_previousValue $_operation',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  Text(
                    _display,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Scientific functions row
            Row(
              children: [
                _buildButton('√', _onSquareRoot, color: Colors.orange),
                _buildButton('x²', _onSquare, color: Colors.orange),
                _buildButton('%', _onPercentage, color: Colors.orange),
                _buildButton('CE', _onClearEntry, color: Colors.red.shade300),
              ],
            ),

            const SizedBox(height: 8),

            // Main calculator grid
            Row(
              children: [
                _buildButton('C', _onClear, color: Colors.red),
                _buildButton('⌫', _onBackspace, color: Colors.orange),
                _buildButton('^', () => _onOperationPress('^'), color: Colors.orange),
                _buildButton('÷', () => _onOperationPress('÷'), color: Colors.orange),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildButton('7', () => _onNumberPress('7')),
                _buildButton('8', () => _onNumberPress('8')),
                _buildButton('9', () => _onNumberPress('9')),
                _buildButton('×', () => _onOperationPress('×'), color: Colors.orange),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildButton('4', () => _onNumberPress('4')),
                _buildButton('5', () => _onNumberPress('5')),
                _buildButton('6', () => _onNumberPress('6')),
                _buildButton('-', () => _onOperationPress('-'), color: Colors.orange),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildButton('1', () => _onNumberPress('1')),
                _buildButton('2', () => _onNumberPress('2')),
                _buildButton('3', () => _onNumberPress('3')),
                _buildButton('+', () => _onOperationPress('+'), color: Colors.orange),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildButton('±', _onNegate, color: Colors.grey),
                _buildButton('0', () => _onNumberPress('0')),
                _buildButton('.', _onDecimalPress),
                _buildButton('=', _onEqualsPress, color: Colors.green),
              ],
            ),

            const SizedBox(height: 16),

            // History
            if (_history.isNotEmpty) ...[
              const Text('History', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: _history.length,
                  reverse: true,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      child: Text(
                        _history[_history.length - 1 - index],
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _useResult,
                    icon: const Icon(Icons.check),
                    label: const Text('Use Result'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(String text, VoidCallback onPressed, {Color? color}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? Colors.grey.shade200,
            foregroundColor: color != null && (color == Colors.orange || color == Colors.red || color == Colors.green)
                ? Colors.white
                : Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}