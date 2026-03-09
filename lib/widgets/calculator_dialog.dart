import 'package:flutter/material.dart';
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
  static const String _multiply = '×';
  static const String _divide = '÷';

  String _display = '0';
  String _expression = '';
  bool _justEvaluated = false;
  final List<String> _history = [];

  void _onNumberPress(String number) {
    setState(() {
      if (_justEvaluated) {
        _expression = '';
        _justEvaluated = false;
      }

      if (_shouldInsertImplicitMultiply()) {
        _expression += _multiply;
      }

      _expression += number;
      _refreshDisplay();
    });
  }

  void _onDecimalPress() {
    setState(() {
      if (_justEvaluated) {
        _expression = '';
        _justEvaluated = false;
      }

      if (_shouldInsertImplicitMultiply()) {
        _expression += _multiply;
      }

      final currentNumber = _getCurrentNumberToken();
      if (currentNumber.contains('.')) {
        return;
      }

      if (currentNumber.isEmpty) {
        _expression += '0.';
      } else {
        _expression += '.';
      }
      _refreshDisplay();
    });
  }

  void _onOperationPress(String operation) {
    setState(() {
      if (_expression.isEmpty) {
        if (operation == '-') {
          _expression = '-';
          _refreshDisplay();
        }
        return;
      }

      if (_endsWithOperator(_expression)) {
        _expression = _expression.substring(0, _expression.length - 1) + operation;
      } else if (_expression.endsWith('(')) {
        if (operation == '-') {
          _expression += operation;
        }
      } else {
        _expression += operation;
      }

      _justEvaluated = false;
      _refreshDisplay();
    });
  }

  void _refreshDisplay() {
    if (_expression.isEmpty) {
      _display = '0';
      return;
    }

    final currentToken = _getCurrentNumberToken();
    if (currentToken.isNotEmpty && currentToken != '-') {
      _display = currentToken;
      return;
    }

    final preview = _tryEvaluateExpression();
    _display = preview != null ? _formatResult(preview) : _expression;
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
    final expression = _expression;
    final result = _tryEvaluateExpression();
    if (expression.isEmpty || result == null) {
      _showError('Invalid expression');
      return;
    }

    setState(() {
      _history.add('$expression = ${_formatResult(result)}');
      if (_history.length > 10) {
        _history.removeAt(0);
      }
      _expression = _formatResult(result);
      _display = _expression;
      _justEvaluated = true;
    });
  }

  void _onClear() {
    setState(() {
      _display = '0';
      _expression = '';
      _justEvaluated = false;
    });
  }

  void _onClearEntry() {
    setState(() {
      final range = _findLastOperandRange();
      if (range == null) {
        _expression = '';
      } else {
        _expression = _expression.replaceRange(range.$1, range.$2, '');
      }
      _refreshDisplay();
    });
  }

  void _onBackspace() {
    setState(() {
      if (_justEvaluated) {
        _expression = '';
        _display = '0';
        _justEvaluated = false;
        return;
      }

      if (_expression.isNotEmpty) {
        _expression = _expression.substring(0, _expression.length - 1);
      }
      _refreshDisplay();
    });
  }

  void _onPercentage() {
    setState(() {
      final range = _findLastOperandRange();
      if (range == null) return;
      final operand = _expression.substring(range.$1, range.$2);
      _expression = _expression.replaceRange(range.$1, range.$2, '($operand$_divide100Expression)');
      _refreshDisplay();
    });
  }

  void _onSquareRoot() {
    setState(() {
      final range = _findLastOperandRange();
      if (range == null) {
        return;
      }
      final operand = _expression.substring(range.$1, range.$2);
      _expression = _expression.replaceRange(range.$1, range.$2, '√($operand)');
      _refreshDisplay();
    });
  }

  void _onSquare() {
    setState(() {
      final range = _findLastOperandRange();
      if (range == null) {
        return;
      }
      final operand = _expression.substring(range.$1, range.$2);
      _expression = _expression.replaceRange(range.$1, range.$2, '($operand)^2');
      _refreshDisplay();
    });
  }

  void _onNegate() {
    setState(() {
      final range = _findLastOperandRange();
      if (range == null) {
        if (_expression.isEmpty) {
          _expression = '-';
        }
        _refreshDisplay();
        return;
      }

      final operand = _expression.substring(range.$1, range.$2);
      final replacement = _toggleOperandSign(operand);
      if (replacement == null) {
        return;
      }

      _expression = _expression.replaceRange(range.$1, range.$2, replacement);
      _refreshDisplay();
    });
  }

  void _onParenthesisPress(String parenthesis) {
    setState(() {
      if (_justEvaluated && parenthesis == '(') {
        _expression = '';
        _justEvaluated = false;
      }

      if (parenthesis == '(') {
        if (_shouldInsertImplicitMultiply()) {
          _expression += _multiply;
        }
        _expression += '(';
      } else {
        final openCount = '('.allMatches(_expression).length;
        final closeCount = ')'.allMatches(_expression).length;
        if (openCount > closeCount &&
            _expression.isNotEmpty &&
            !_endsWithOperator(_expression) &&
            !_expression.endsWith('(')) {
          _expression += ')';
        }
      }

      _refreshDisplay();
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _useResult() {
    final result = _tryEvaluateExpression() ?? double.tryParse(_display);
    if (result != null) {
      widget.onUseResult(result);
      Navigator.of(context).pop();
    }
  }

  bool _endsWithOperator(String value) {
    return value.endsWith('+') ||
        value.endsWith('-') ||
        value.endsWith(_multiply) ||
        value.endsWith(_divide) ||
        value.endsWith('^');
  }

  bool _shouldInsertImplicitMultiply() {
    return _expression.isNotEmpty &&
        (RegExp(r'[0-9)]$').hasMatch(_expression) || _expression.endsWith('.'));
  }

  String _getCurrentNumberToken() {
    final match = RegExp(r'-?\d*\.?\d+$').firstMatch(_expression);
    return match?.group(0) ?? '';
  }

  (int, int)? _findLastOperandRange() {
    if (_expression.isEmpty) {
      return null;
    }

    var end = _expression.length;
    var index = end - 1;
    if (index < 0) {
      return null;
    }

    if (_expression[index] == ')') {
      var depth = 0;
      for (var i = index; i >= 0; i--) {
        final char = _expression[i];
        if (char == ')') {
          depth++;
        } else if (char == '(') {
          depth--;
          if (depth == 0) {
            var start = i;
            while (start > 0 && _expression[start - 1] == '√') {
              start--;
            }
            return (start, end);
          }
        }
      }
      return null;
    }

    while (index >= 0 && RegExp(r'[0-9.]').hasMatch(_expression[index])) {
      index--;
    }

    if (index == end - 1) {
      return null;
    }

    final start = index + 1;
    if (index >= 0 &&
        _expression[index] == '-' &&
        (index == 0 || _endsWithOperator(_expression.substring(0, index + 1)) || _expression[index - 1] == '(')) {
      return (index, end);
    }

    return (start, end);
  }

  String? _toggleOperandSign(String operand) {
    final numericValue = double.tryParse(operand);
    if (numericValue != null) {
      if (operand.startsWith('-')) {
        return operand.substring(1);
      }
      return '-$operand';
    }

    if (operand.startsWith('(0-') && operand.endsWith(')')) {
      return operand.substring(3, operand.length - 1);
    }

    return '(0-$operand)';
  }

  double? _tryEvaluateExpression() {
    if (_expression.isEmpty) {
      return 0;
    }

    try {
      return _evaluateExpression(_expression);
    } catch (_) {
      return null;
    }
  }

  double _evaluateExpression(String expression) {
    final tokens = _tokenize(expression);
    final output = <String>[];
    final operators = <String>[];

    for (final token in tokens) {
      if (double.tryParse(token) != null) {
        output.add(token);
        continue;
      }

      if (token == '√') {
        operators.add(token);
        continue;
      }

      if (token == '(') {
        operators.add(token);
        continue;
      }

      if (token == ')') {
        while (operators.isNotEmpty && operators.last != '(') {
          output.add(operators.removeLast());
        }
        if (operators.isEmpty) {
          throw const FormatException('Mismatched parentheses');
        }
        operators.removeLast();
        if (operators.isNotEmpty && operators.last == '√') {
          output.add(operators.removeLast());
        }
        continue;
      }

      while (operators.isNotEmpty &&
          operators.last != '(' &&
          (_precedence(operators.last) > _precedence(token) ||
              (_precedence(operators.last) == _precedence(token) && !_isRightAssociative(token)))) {
        output.add(operators.removeLast());
      }
      operators.add(token);
    }

    while (operators.isNotEmpty) {
      final operator = operators.removeLast();
      if (operator == '(') {
        throw const FormatException('Mismatched parentheses');
      }
      output.add(operator);
    }

    final stack = <double>[];
    for (final token in output) {
      final numericValue = double.tryParse(token);
      if (numericValue != null) {
        stack.add(numericValue);
        continue;
      }

      if (token == '√') {
        if (stack.isEmpty) {
          throw const FormatException('Invalid expression');
        }
        final value = stack.removeLast();
        if (value < 0) {
          throw const FormatException('Invalid input');
        }
        stack.add(math.sqrt(value));
        continue;
      }

      if (stack.length < 2) {
        throw const FormatException('Invalid expression');
      }

      final right = stack.removeLast();
      final left = stack.removeLast();
      switch (token) {
        case '+':
          stack.add(left + right);
          break;
        case '-':
          stack.add(left - right);
          break;
        case _multiply:
          stack.add(left * right);
          break;
        case _divide:
          if (right == 0) {
            throw const FormatException('Cannot divide by zero');
          }
          stack.add(left / right);
          break;
        case '%':
          if (right == 0) {
            throw const FormatException('Cannot divide by zero');
          }
          stack.add(left % right);
          break;
        case '^':
          stack.add(math.pow(left, right).toDouble());
          break;
        default:
          throw const FormatException('Unsupported operator');
      }
    }

    if (stack.length != 1) {
      throw const FormatException('Invalid expression');
    }

    return stack.single;
  }

  List<String> _tokenize(String expression) {
    final tokens = <String>[];
    var index = 0;

    while (index < expression.length) {
      final char = expression[index];
      if (char == ' ') {
        index++;
        continue;
      }

      if (char == '√' || char == '(' || char == ')' || char == '+' || char == _multiply || char == _divide || char == '^' || char == '%') {
        tokens.add(char);
        index++;
        continue;
      }

      if (char == '-') {
        final previous = tokens.isEmpty ? null : tokens.last;
        final isUnary = previous == null ||
            previous == '(' ||
            previous == '+' ||
            previous == '-' ||
            previous == _multiply ||
            previous == _divide ||
            previous == '^' ||
            previous == '%' ||
            previous == '√';

        if (isUnary) {
          final buffer = StringBuffer('-');
          index++;
          while (index < expression.length && RegExp(r'[0-9.]').hasMatch(expression[index])) {
            buffer.write(expression[index]);
            index++;
          }
          if (buffer.length == 1) {
            tokens.add('0');
            tokens.add('-');
          } else {
            tokens.add(buffer.toString());
          }
        } else {
          tokens.add('-');
          index++;
        }
        continue;
      }

      if (RegExp(r'[0-9.]').hasMatch(char)) {
        final buffer = StringBuffer();
        while (index < expression.length && RegExp(r'[0-9.]').hasMatch(expression[index])) {
          buffer.write(expression[index]);
          index++;
        }
        tokens.add(buffer.toString());
        continue;
      }

      throw FormatException('Invalid character: $char');
    }

    return tokens;
  }

  int _precedence(String operator) {
    switch (operator) {
      case '√':
        return 4;
      case '^':
        return 3;
      case _multiply:
      case _divide:
      case '%':
        return 2;
      case '+':
      case '-':
        return 1;
      default:
        return 0;
    }
  }

  bool _isRightAssociative(String operator) {
    return operator == '^' || operator == '√';
  }

  String get _divide100Expression => '${_divide}100';

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
                  if (_expression.isNotEmpty)
                    Text(
                      _expression,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                _buildButton('(', () => _onParenthesisPress('('), color: Colors.orange),
                _buildButton(')', () => _onParenthesisPress(')'), color: Colors.orange),
                _buildButton('√', _onSquareRoot, color: Colors.orange),
                _buildButton('x²', _onSquare, color: Colors.orange),
                _buildButton('%', _onPercentage, color: Colors.orange),
              ],
            ),

            const SizedBox(height: 8),

            // Main calculator grid
            Row(
              children: [
                _buildButton('CE', _onClearEntry, color: Colors.red.shade300),
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