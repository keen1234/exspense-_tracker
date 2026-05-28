import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../services/receipt_scanner_service.dart';

/// A self-contained offline receipt scanner screen.
///
/// Usage:
///   Navigator.push(context, MaterialPageRoute(
///     builder: (_) => ReceiptScannerScreen(onResult: (result) { ... }),
///   ));
class ReceiptScannerScreen extends StatefulWidget {
  /// Called when the user confirms a scan result.
  final void Function(ReceiptResult result)? onResult;

  const ReceiptScannerScreen({super.key, this.onResult});

  @override
  State<ReceiptScannerScreen> createState() => _ReceiptScannerScreenState();
}

enum _ScanPhase { idle, processing, result }

class _ReceiptScannerScreenState extends State<ReceiptScannerScreen> {
  final _picker = ImagePicker();
  final _scanner = ReceiptScannerService();

  _ScanPhase _phase = _ScanPhase.idle;
  File? _imageFile;
  ReceiptResult? _result;
  String? _error;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  // ── Image source selection ────────────────────────────────────────

  Future<void> _pickFromCamera() => _scan(ImageSource.camera);
  Future<void> _pickFromGallery() => _scan(ImageSource.gallery);

  Future<void> _scan(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() {
        _imageFile = File(picked.path);
        _phase = _ScanPhase.processing;
        _error = null;
      });

      final result = await _scanner.scanReceipt(picked.path);

      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _ScanPhase.result;
        if (result.error != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error!),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to scan: $e';
        _phase = _ScanPhase.idle;
      });
    }
  }

  void _reset() {
    setState(() {
      _phase = _ScanPhase.idle;
      _imageFile = null;
      _result = null;
      _error = null;
    });
  }

  void _confirm() {
    if (_result != null) {
      widget.onResult?.call(_result!);
    }
    Navigator.of(context).pop(_result);
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Receipt'),
        centerTitle: true,
        actions: [
          if (_phase == _ScanPhase.result)
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'New Scan', onPressed: _reset),
        ],
      ),
      body: switch (_phase) {
        _ScanPhase.idle => _buildIdle(cs),
        _ScanPhase.processing => _buildProcessing(cs),
        _ScanPhase.result => _buildResult(cs),
      },
    );
  }

  // ── Idle / picker ──────────────────────────────────────────────────

  Widget _buildIdle(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!, style: TextStyle(color: cs.onErrorContainer)),
            ),
          _OptionCard(
            icon: Icons.camera_alt_rounded,
            title: 'Take Photo',
            subtitle: 'Point your camera at the receipt',
            cs: cs,
            onTap: _pickFromCamera,
          ),
          const SizedBox(height: 16),
          _OptionCard(
            icon: Icons.photo_library_rounded,
            title: 'Choose from Gallery',
            subtitle: 'Select a receipt photo',
            cs: cs,
            onTap: _pickFromGallery,
          ),
          const SizedBox(height: 32),
          Text(
            'Tip: Place the receipt on a dark, flat surface with even lighting.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Processing ─────────────────────────────────────────────────────

  Widget _buildProcessing(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_imageFile != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(width: 200, height: 200, child: Image.file(_imageFile!, fit: BoxFit.cover)),
              ),
            ),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Reading receipt ...', style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  // ── Result ─────────────────────────────────────────────────────────

  Widget _buildResult(ColorScheme cs) {
    final r = _result!;
    final dateStr = r.date != null ? DateFormat('MMM dd, yyyy').format(r.date!) : '—';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Receipt thumbnail
          if (_imageFile != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(height: 140, child: Image.file(_imageFile!, fit: BoxFit.cover)),
              ),
            ),

          // ---- Merchant & Date ----
          _sectionHeader(cs, 'Receipt Info'),
          const SizedBox(height: 8),
          _infoRow(Icons.store_rounded, 'Merchant', r.merchantName ?? 'Not detected'),
          _infoRow(Icons.calendar_today_rounded, 'Date', dateStr),

          const SizedBox(height: 20),

          // ---- Items ----
          if (r.items.isNotEmpty) ...[
            _sectionHeader(cs, 'Items (${r.items.length})'),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: r.items.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant),
                itemBuilder: (_, i) {
                  final item = r.items[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(child: Text(item.name, style: const TextStyle(fontSize: 14))),
                        Text(
                          item.quantity > 1 ? '${item.quantity}x ' : '',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                        Text(
                          '\$${item.price.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ---- Total ----
          _sectionHeader(cs, 'Total'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text('Amount Due:', style: TextStyle(color: cs.onPrimaryContainer)),
                const Spacer(),
                Text(
                  r.totalAmount != null ? '\$${r.totalAmount!.toStringAsFixed(2)}' : 'Not detected',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ---- Action buttons ----
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _confirm,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Use This Data'),
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

  // ── Helpers ─────────────────────────────────────────────────────────

  Widget _sectionHeader(ColorScheme cs, String title) {
    return Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.primary));
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

// ── Reusable option card ──────────────────────────────────────────────

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 28, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
