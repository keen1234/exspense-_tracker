import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/entry.dart';
import '../models/tag.dart';
import '../services/receipt_scanner_service.dart';
import 'add_entry_dialog.dart';

enum _ScannerState { choosing, processing, result }

class ScannerPage extends StatefulWidget {
  final Future<bool> Function(Entry) onSaveEntry;
  final List<Tag> tags;
  final String currencySymbol;
  final String currencyCode;

  const ScannerPage({
    super.key,
    required this.onSaveEntry,
    required this.tags,
    required this.currencySymbol,
    required this.currencyCode,
  });

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  _ScannerState _state = _ScannerState.choosing;
  File? _imageFile;
  ReceiptResult? _result;
  String? _errorMessage;

  // Editable controllers
  late TextEditingController _vendorController;
  late TextEditingController _totalController;
  DateTime _selectedDate = DateTime.now();

  final _imagePicker = ImagePicker();
  final _scannerService = ReceiptScannerService();

  @override
  void initState() {
    super.initState();
    _vendorController = TextEditingController();
    _totalController = TextEditingController();
  }

  @override
  void dispose() {
    _vendorController.dispose();
    _totalController.dispose();
    _scannerService.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (picked == null) return;

      setState(() {
        _imageFile = File(picked.path);
        _state = _ScannerState.processing;
        _errorMessage = null;
      });

      await _processImage();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to pick image: $e';
          _state = _ScannerState.choosing;
        });
      }
    }
  }

  Future<void> _processImage() async {
    if (_imageFile == null) return;
    try {
      final result = await _scannerService.scanReceipt(_imageFile!.path);

      if (!result.hasData) {
        if (mounted) {
          setState(() {
            _errorMessage = result.error ?? 'Could not read this receipt. Try a clearer photo.';
            _state = _ScannerState.choosing;
          });
        }
        return;
      }

      _vendorController.text = result.merchantName ?? '';
      _totalController.text = result.totalAmount?.toStringAsFixed(2) ?? '';
      _selectedDate = result.date ?? DateTime.now();

      if (mounted) {
        setState(() {
          _result = result;
          _state = _ScannerState.result;
        });

        if (result.error != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.error!), duration: const Duration(seconds: 4)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to read receipt: $e';
          _state = _ScannerState.choosing;
        });
      }
    }
  }

  void _tryAgain() {
    setState(() {
      _imageFile = null;
      _result = null;
      _errorMessage = null;
      _state = _ScannerState.choosing;
    });
  }

  Future<void> _saveEntry() async {
    final totalText = _totalController.text.trim();
    final amount = double.tryParse(totalText);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid total amount')),
      );
      return;
    }

    final vendor = _vendorController.text.trim();

    // Build a receipt summary from scanned items
    String? receiptSummary;
    final items = _result?.items ?? [];
    if (items.isNotEmpty || vendor.isNotEmpty) {
      final buf = StringBuffer();
      if (vendor.isNotEmpty) buf.writeln(vendor);
      for (final item in items) {
        buf.writeln(item.quantity > 1
            ? '  \u2022 ${item.name} x${item.quantity}  ${widget.currencySymbol}${item.price.toStringAsFixed(2)}'
            : '  \u2022 ${item.name}  ${widget.currencySymbol}${item.price.toStringAsFixed(2)}');
      }
      receiptSummary = buf.toString().trim();
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AddEntryDialog(
        onSaveEntry: widget.onSaveEntry,
        tags: widget.tags,
        currencySymbol: widget.currencySymbol,
        currencyCode: widget.currencyCode,
        initialAmount: amount,
        initialDate: _selectedDate,
        initialNote: vendor.isNotEmpty ? vendor : null,
        initialReceiptSummary: receiptSummary,
      ),
    );
    if (mounted && saved == true) Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Receipt'),
        centerTitle: true,
      ),
      body: switch (_state) {
        _ScannerState.choosing => _buildChooser(colorScheme),
        _ScannerState.processing => _buildProcessing(colorScheme),
        _ScannerState.result => _buildResult(colorScheme),
      },
    );
  }

  // ── Chooser ────────────────────────────────────────────────────────

  Widget _buildChooser(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: colorScheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
          _buildOptionCard(
            icon: Icons.camera_alt_rounded,
            title: 'Take Photo',
            subtitle: 'Use your camera to photograph the receipt',
            colorScheme: colorScheme,
            onTap: () => _pickImage(ImageSource.camera),
          ),
          const SizedBox(height: 20),
          _buildOptionCard(
            icon: Icons.photo_library_rounded,
            title: 'Import from Files',
            subtitle: 'Select a receipt photo from your gallery',
            colorScheme: colorScheme,
            onTap: () => _pickImage(ImageSource.gallery),
          ),
          const SizedBox(height: 32),
          Text(
            'Tip: For best results, make sure the receipt is well-lit and the text is clearly visible.',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  // ── Processing ─────────────────────────────────────────────────────

  Widget _buildProcessing(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_imageFile != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 200, height: 200, child: Image.file(_imageFile!, fit: BoxFit.cover)),
            ),
            const SizedBox(height: 24),
          ],
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Reading receipt...', style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  // ── Result (Editable Preview) ──────────────────────────────────────

  Widget _buildResult(ColorScheme colorScheme) {
    final r = _result!;
    final dateFormat = DateFormat('MM/dd/yyyy');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Receipt image
          if (_imageFile != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(height: 160, child: Image.file(_imageFile!, fit: BoxFit.cover)),
            ),
            const SizedBox(height: 16),
          ],

          // Section: Receipt Info
          Text('Receipt Info', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colorScheme.primary)),
          const SizedBox(height: 10),
          _buildEditableField(
            controller: _vendorController,
            label: 'Vendor / Store',
            icon: Icons.store_rounded,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 8),
          _buildDateRow(dateFormat, colorScheme),
          const SizedBox(height: 16),

          // Section: Line Items
          if (r.items.isNotEmpty) ...[
            Text('Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colorScheme.primary)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: r.items.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: colorScheme.outlineVariant),
                itemBuilder: (context, index) {
                  final item = r.items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              if (item.quantity > 1)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'x${item.quantity}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ),
                              Flexible(
                                child: Text(item.name, style: TextStyle(fontSize: 14, color: colorScheme.onSurface)),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${widget.currencySymbol}${item.price.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Section: Total
          Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colorScheme.primary)),
          const SizedBox(height: 10),
          _buildEditableField(
            controller: _totalController,
            label: 'Total',
            icon: Icons.attach_money_rounded,
            colorScheme: colorScheme,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            isBold: true,
          ),
          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _tryAgain,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveEntry,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save Entry'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ColorScheme colorScheme,
    TextInputType? keyboardType,
    bool isBold = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(
        fontSize: isBold ? 18 : 14,
        fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildDateRow(DateFormat dateFormat, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 20, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text('Date', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
            const Spacer(),
            Text(
              dateFormat.format(_selectedDate),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
