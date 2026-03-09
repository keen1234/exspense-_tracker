import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/tag.dart';
import '../models/entry.dart';
import 'calculator_dialog.dart';

class AddEntryDialog extends StatefulWidget {
  final Future<bool> Function(Entry) onSaveEntry;
  final List<Tag> tags;
  final String currencySymbol;
  final Entry? initialEntry;

  const AddEntryDialog({
    Key? key,
    required this.onSaveEntry,
    required this.tags,
    this.currencySymbol = '₱',
    this.initialEntry,
  }) : super(key: key);

  @override
  State<AddEntryDialog> createState() => _AddEntryDialogState();
}

class _AddEntryDialogState extends State<AddEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  int? _selectedTagId;
  late DateTime _selectedDate;
  bool _isSaving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final initialEntry = widget.initialEntry;
    _selectedDate = _normalizeDate(initialEntry?.date ?? DateTime.now());
    if (initialEntry != null) {
      _amountController.text = initialEntry.absoluteAmount.toStringAsFixed(2);
      _noteController.text = initialEntry.note ?? '';
      _selectedTagId = initialEntry.tagId;
    }
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _formatSelectedDate() {
    return DateFormat('MMM d, yyyy').format(_selectedDate);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 20),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() => _selectedDate = _normalizeDate(picked));
  }

  String? _validateAmount(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter an amount';
    }
    final amount = double.tryParse(value);
    if (amount == null) {
      return 'Please enter a valid number';
    }
    if (amount <= 0) {
      return 'Amount must be greater than 0';
    }
    if (amount > 999999999) {
      return 'Amount is too large';
    }
    return null;
  }

  void _openCalculator() {
    showDialog(
      context: context,
      builder: (context) => CalculatorDialog(
        onUseResult: (result) {
          setState(() {
            _amountController.text = result.toStringAsFixed(2);
          });
        },
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTagId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a tag')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final amount = double.parse(_amountController.text);
    final selectedTag = widget.tags.firstWhere((t) => t.id == _selectedTagId!);

    final signedAmount = selectedTag.type == TagType.expense ? -amount : amount;

    final entry = Entry(
      id: widget.initialEntry?.id,
      amount: signedAmount,
      date: _selectedDate,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      tagId: _selectedTagId!,
    );

    try {
      final saved = await widget.onSaveEntry(entry);
      if (!mounted) return;

      if (saved) {
        Navigator.of(context).pop();
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save entry: $e')),
        );
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final incomeTags = widget.tags.where((t) => t.type == TagType.income).toList();
    final expenseTags = widget.tags.where((t) => t.type == TagType.expense).toList();

    return AlertDialog(
      title: Text(widget.initialEntry == null ? 'Add Entry' : 'Edit Entry'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                        controller: _amountController,
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          prefixText: widget.currencySymbol,
                          border: const OutlineInputBorder(),
                        ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      validator: _validateAmount,
                      autofocus: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _openCalculator,
                    icon: const Icon(Icons.calculate, size: 28),
                    tooltip: 'Open Calculator',
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              InkWell(
                onTap: _isSaving ? null : _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(_formatSelectedDate()),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Grocery shopping',
                ),
                maxLength: 100,
              ),
              const SizedBox(height: 16),

              if (widget.tags.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No tags available. Create tags first.',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Tag',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: _selectedTagId,
                          hint: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('Choose a tag...'),
                          ),
                          icon: const Icon(Icons.arrow_drop_down),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          borderRadius: BorderRadius.circular(8),
                          items: [
                            if (incomeTags.isNotEmpty)
                              const DropdownMenuItem<int>(
                                enabled: false,
                                child: Text(
                                  'INCOME',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ...incomeTags.map((tag) => DropdownMenuItem<int>(
                              value: tag.id,
                              child: Row(
                                children: [
                                  Icon(
                                    tag.type.icon,
                                    color: tag.type.color,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tag.name,
                                      style: TextStyle(color: tag.type.color),
                                    ),
                                  ),
                                ],
                              ),
                            )),

                            if (incomeTags.isNotEmpty && expenseTags.isNotEmpty)
                              const DropdownMenuItem<int>(
                                enabled: false,
                                child: Divider(),
                              ),

                            if (expenseTags.isNotEmpty)
                              const DropdownMenuItem<int>(
                                enabled: false,
                                child: Text(
                                  'EXPENSE',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                            ...expenseTags.map((tag) => DropdownMenuItem<int>(
                              value: tag.id,
                              child: Row(
                                children: [
                                  Icon(
                                    tag.type.icon,
                                    color: tag.type.color,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tag.name,
                                      style: TextStyle(color: tag.type.color),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedTagId = value;
                            });
                          },
                        ),
                      ),
                    ),

                    if (_selectedTagId != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _getSelectedTagColor()?.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _getSelectedTagColor() ?? Colors.grey,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getSelectedTagIcon(),
                              color: _getSelectedTagColor(),
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Selected: ${_getSelectedTagName()}',
                              style: TextStyle(
                                color: _getSelectedTagColor(),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: widget.tags.isEmpty || _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : Text(widget.initialEntry == null ? 'Save Entry' : 'Update Entry'),
        ),
      ],
    );
  }

  Tag? _getSelectedTag() {
    if (_selectedTagId == null) return null;
    try {
      return widget.tags.firstWhere((t) => t.id == _selectedTagId);
    } catch (e) {
      return null;
    }
  }

  String _getSelectedTagName() {
    final tag = _getSelectedTag();
    return tag?.name ?? 'Unknown';
  }

  Color? _getSelectedTagColor() {
    final tag = _getSelectedTag();
    return tag?.type.color;
  }

  IconData? _getSelectedTagIcon() {
    final tag = _getSelectedTag();
    return tag?.type.icon;
  }
}
