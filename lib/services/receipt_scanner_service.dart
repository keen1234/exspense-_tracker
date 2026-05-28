import 'dart:io';
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class ScannedItem {
  final String name;
  final double price;
  final int quantity;
  ScannedItem({required this.name, required this.price, this.quantity = 1});
}

class ReceiptResult {
  final String? merchantName;
  final DateTime? date;
  final double? totalAmount;
  final List<ScannedItem> items;
  final String rawText;
  final String? error;

  const ReceiptResult({
    this.merchantName,
    this.date,
    this.totalAmount,
    this.items = const [],
    required this.rawText,
    this.error,
  });

  bool get hasData =>
      merchantName != null || date != null || totalAmount != null || items.isNotEmpty;
}

// ---------------------------------------------------------------------------
// Regional number parser
// ---------------------------------------------------------------------------

/// Parses a price string that may use European/regional formatting.
///
/// Examples:
///   "12.50"     → 12.50
///   "12,50"     → 12.50   (comma as decimal)
///   "1.234,56"  → 1234.56 (dot as thousand separator, comma as decimal)
///   "1,234.56"  → 1234.56 (comma as thousand separator, dot as decimal)
double? parseRegionalPrice(String raw) {
  if (raw.isEmpty) return null;

  // Remove non-numeric chars except '.' and ','
  String s = raw.trim();

  // Detect format: if comma appears after a dot → European (1.234,56)
  final dotPos = s.indexOf('.');
  final commaPos = s.indexOf(',');
  final hasDot = dotPos >= 0;
  final hasComma = commaPos >= 0;

  if (hasDot && hasComma && commaPos > dotPos) {
    // European: 1.234,56 → remove dots (thousands), replace comma with dot
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (hasComma && !hasDot) {
    // Could be "12,50" (comma as decimal) or "1,234" (comma as thousand)
    // Count digits after comma
    final afterComma = s.substring(commaPos + 1);
    if (afterComma.length <= 2 && RegExp(r'^\d{1,2}$').hasMatch(afterComma)) {
      // "12,50" → comma is decimal: replace with dot
      s = s.replaceAll(',', '.');
    } else {
      // "1,234" → comma is thousand separator: remove it
      s = s.replaceAll(',', '');
    }
  } else if (hasComma && hasDot && dotPos > commaPos) {
    // Rare: "1,234.56" → comma is thousand separator: remove it
    s = s.replaceAll(',', '');
  } else if (hasDot && '.'.allMatches(s).length > 1) {
    // Multiple dots (e.g., "5.710.79") — keep last dot as decimal separator
    final lastDot = s.lastIndexOf('.');
    s = '${s.substring(0, lastDot).replaceAll('.', '')}${s.substring(lastDot)}';
  } else {
    // Standard or no separators: just remove commas
    s = s.replaceAll(',', '');
  }

  return double.tryParse(s);
}

// ---------------------------------------------------------------------------
// Helper Class for Layout Sorting
// ---------------------------------------------------------------------------
class _LineBox {
  final String text;
  final Rect box;
  _LineBox(this.text, this.box);
}

// ---------------------------------------------------------------------------
// Receipt Scanner Service
// ---------------------------------------------------------------------------

class ReceiptScannerService {
  TextRecognizer? _recognizer;

  /// Initialize the ML Kit text recognizer (lazy).
  TextRecognizer get _textRecognizer {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _recognizer!;
  }

  /// Release native resources.
  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }

  // ── Public entry point ──────────────────────────────────────────────

  /// Scan a receipt image at [imagePath] and return structured [ReceiptResult].
  Future<ReceiptResult> scanReceipt(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return ReceiptResult(
          rawText: '',
          error: 'Image file not found at $imagePath',
        );
      }

      final inputImage = InputImage.fromFile(file);
      final recognised = await _textRecognizer.processImage(inputImage);

      final rawText = recognised.text.trim();
      if (rawText.isEmpty) {
        return ReceiptResult(
          rawText: '',
          error: 'No text could be read. Try a clearer photo with better lighting.',
        );
      }

      // ── GEOMETRIC ROW STITCHING ──
      // ML Kit's block API separates multi-column layouts vertically.
      // We use boundingBox Y-coordinates to re-stitch rows horizontally.
      // 1. Flatten all lines across all blocks with their bounding boxes
      final allLines = <_LineBox>[];
      for (final block in recognised.blocks) {
        for (final line in block.lines) {
          if (line.text.trim().isNotEmpty) {
            allLines.add(_LineBox(line.text.trim(), line.boundingBox));
          }
        }
      }

      // 2. Sort vertically top-to-bottom
      allLines.sort((a, b) => a.box.top.compareTo(b.box.top));

      // 3. Group lines whose Y-centers are within tolerance into rows
      final rows = <List<_LineBox>>[];
      for (final lb in allLines) {
        bool placed = false;
        final centerY = lb.box.top + (lb.box.height / 2);
        for (final row in rows) {
          final anchor = row.first;
          final anchorCenter = anchor.box.top + (anchor.box.height / 2);
          if ((centerY - anchorCenter).abs() < anchor.box.height * 0.7) {
            row.add(lb);
            placed = true;
            break;
          }
        }
        if (!placed) rows.add([lb]);
      }

      // 4. Sort each row left-to-right and join
      final stitched = <String>[];
      for (final row in rows) {
        row.sort((a, b) => a.box.left.compareTo(b.box.left));
        stitched.add(row.map((l) => l.text).join(' '));
      }

      return _parseReceipt(rawText, stitched);
    } catch (e) {
      return ReceiptResult(
        rawText: '',
        error: 'Failed to process receipt: $e',
      );
    }
  }

  // ── Core parsing ────────────────────────────────────────────────────

  ReceiptResult _parseReceipt(String rawText, List<String> lines) {
    // 1. Clean every line
    final cleaned = lines.map(_cleanLine).where((l) => l.isNotEmpty).toList();
    if (cleaned.isEmpty) {
      return ReceiptResult(
        rawText: rawText,
        error: 'No readable content found on the receipt.',
      );
    }

    // 2. Extract fields
    final merchantName = _extractMerchant(cleaned);
    final date = _extractDate(cleaned);
    final totalAmount = _extractTotal(cleaned);
    final items = _extractItems(cleaned, totalAmount);

    // 3. Build error message if extraction was poor
    String? error;
    if (totalAmount == null && items.isEmpty && merchantName == null && date == null) {
      error = 'Could not extract any data. Try a closer or clearer photo.';
    } else if (totalAmount == null && items.isEmpty) {
      error = 'Found text but could not read prices or items clearly.';
    }

    return ReceiptResult(
      merchantName: merchantName,
      date: date,
      totalAmount: totalAmount,
      items: items,
      rawText: rawText,
      error: error,
    );
  }

  // ── Text cleaning ───────────────────────────────────────────────────

  String _cleanLine(String line) {
    var s = line.trim();
    if (s.isEmpty) return '';

    // Collapse multiple spaces / tabs into one
    s = s.replaceAll(RegExp(r'\s{2,}'), ' ');

    // Fix common OCR digit misreads
    s = s.replaceAllMapped(RegExp(r'(\d)[Oo](\d)'), (m) => '${m[1]}0${m[2]}');
    s = s.replaceAllMapped(RegExp(r'(\d)[Oo]$'), (m) => '${m[1]}0');
    s = s.replaceAllMapped(RegExp(r'(?<!\d)[Oo](\d)'), (m) => '0${m[1]}');

    // Fix letter 'l' mistaken for digit '1' in common words
    s = s.replaceAllMapped(
      RegExp(r'\b(TOlAL|TOlAI|SubTOlAl|subtoial)\b', caseSensitive: false),
      (m) => m.group(0)!.replaceAll('l', 't').replaceAll('L', 'T'),
    );

    return s;
  }

  // ── Merchant name extraction ────────────────────────────────────────

  String? _extractMerchant(List<String> lines) {
    // Merchant is typically the first meaningful line in the first ~5 lines
    // that does NOT look like a date, address, or receipt boilerplate.
    for (final line in lines.take(5)) {
      if (line.length < 3) continue;

      // Skip pure number lines
      if (RegExp(r'^[\d\s\-/:,.\s]+$').hasMatch(line)) continue;

      // Skip common header lines
      if (RegExp(
        r'^(receipt|invoice|sales|order|official|cashier|register|pos|terminal|branch|store|shop|tel|phone|fax|www|http|email|date|time|tin|vat|gst|tax|or|ref)',
        caseSensitive: false,
      ).hasMatch(line)) {
        continue;
      }

      // Skip if more than 50 % of characters are digits
      final digitCount = RegExp(r'\d').allMatches(line).length;
      if (digitCount / line.length > 0.5) continue;

      // If it has at least some alphabetic characters, it is likely the merchant
      if (RegExp(r'[a-zA-Z\u00C0-\u024F]').hasMatch(line)) {
        return line;
      }
    }
    return null;
  }

  // ── Date extraction ─────────────────────────────────────────────────

  DateTime? _extractDate(List<String> lines) {
    // Priority pass: search lines with transaction markers first
    for (final line in lines) {
      if (!RegExp(r'(TRANS|TERMINAL|DATE|TRAN\b)', caseSensitive: false).hasMatch(line)) {
        continue;
      }
      final dt = _tryAllDatePatterns(line);
      if (dt != null) return dt;
    }
    // General pass: scan all lines
    for (final line in lines) {
      final dt = _tryAllDatePatterns(line);
      if (dt != null) return dt;
    }
    return null;
  }

  DateTime? _tryAllDatePatterns(String line) {
    DateTime? dt;

    // ISO: 2024-01-15
    dt = _tryDatePattern(line, RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'), iso: true);
    if (dt != null) return dt;

    // US/PH: 01/15/2024 or 15/01/2024
    dt = _tryDatePattern(line, RegExp(r'(\d{1,2})[/-](\d{1,2})[/-](\d{4})'));
    if (dt != null) return dt;

    // Short year: 01/15/24 or 15/01/24
    final short = RegExp(r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{2})\b').firstMatch(line);
    if (short != null) {
      final a = int.tryParse(short.group(1)!);
      final b = int.tryParse(short.group(2)!);
      var y = int.tryParse(short.group(3)!);
      if (a != null && b != null && y != null) {
        if (y < 100) y += 2000;
        // Heuristic: if first > 12 then it is day, else month/day
        final (month, day) = a > 12 ? (b, a) : b > 12 ? (a, b) : (a, b);
        if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
          dt = DateTime.tryParse('$y-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}');
          if (dt != null && _isValidDate(dt)) return dt;
        }
      }
    }

    // Month name: Jan 15, 2024 or 15 Jan 2024
    dt = _tryMonthNameDate(line);
    if (dt != null) return dt;

    return null;
  }

  DateTime? _tryDatePattern(String line, RegExp pattern, {bool iso = false}) {
    final m = pattern.firstMatch(line);
    if (m == null) return null;
    try {
      final a = int.parse(m.group(1)!);
      final b = int.parse(m.group(2)!);
      var c = int.parse(m.group(3)!);
      int year, month, day;
      if (iso) {
        year = a;
        month = b;
        day = c;
      } else {
        month = a;
        day = b;
        year = c;
      }
      if (year < 100) year += 2000;
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      final dt = DateTime.tryParse('$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}');
      if (dt != null && _isValidDate(dt)) return dt;
    } catch (_) {}
    return null;
  }

  DateTime? _tryMonthNameDate(String line) {
    final months = r'(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)';
    // "Jan 15, 2024"
    final m1 = RegExp('$months\\s+(\\d{1,2}),?\\s+(\\d{4})', caseSensitive: false)
        .firstMatch(line);
    if (m1 != null) {
      final formatted = '${m1.group(1)} ${m1.group(2)}, ${m1.group(3)}';
      for (final fmt in ['MMMM d, yyyy', 'MMM d, yyyy']) {
        final dt = DateFormat(fmt).tryParse(formatted);
        if (dt != null && _isValidDate(dt)) return dt;
      }
    }
    // "15 Jan 2024"
    final m2 = RegExp('(\\d{1,2})\\s+$months\\s+(\\d{4})', caseSensitive: false)
        .firstMatch(line);
    if (m2 != null) {
      final formatted = '${m2.group(2)} ${m2.group(1)}, ${m2.group(3)}';
      for (final fmt in ['MMM d, yyyy', 'MMMM d, yyyy']) {
        final dt = DateFormat(fmt).tryParse(formatted);
        if (dt != null && _isValidDate(dt)) return dt;
      }
    }
    return null;
  }

  bool _isValidDate(DateTime dt) {
    final now = DateTime.now();
    return dt.isAfter(DateTime(2000)) && dt.isBefore(now.add(const Duration(days: 2)));
  }

  // ── Total amount extraction ─────────────────────────────────────────

  double? _extractTotal(List<String> lines) {
    // Pass 1: explicit total keywords
    for (final line in lines.reversed) {
      if (_isTotalLine(line) && !_isSubtotalLine(line)) {
        final amt = _findBiggestAmount(line);
        if (amt != null && amt > 0) return amt;
      }
    }
    // Pass 2: line with currency symbol (skip subtotal)
    for (final line in lines.reversed) {
      if (RegExp(r'[₱$€£¥₩₹]').hasMatch(line)) {
        if (_isSubtotalLine(line)) continue;
        final amt = _findBiggestAmount(line);
        if (amt != null && amt > 0) return amt;
      }
    }
    // Pass 3: any line with a positive decimal amount (last wins / bottom of receipt)
    for (final line in lines.reversed) {
      if (_isSubtotalLine(line)) continue;
      final amt = _findBiggestAmount(line);
      if (amt != null && amt > 0) return amt;
    }
    return null;
  }

  bool _isTotalLine(String line) {
    final lower = line.toLowerCase().trim();
    if (lower.startsWith('sub')) return false;
    return RegExp(
      r'(total|amount\s*due|grand\s*total|amount\s*paid|balance\s*due|please\s*pay|you\s*pay|amt\s*due|net\s*amount|final)',
      caseSensitive: false,
    ).hasMatch(line);
  }

  bool _isSubtotalLine(String line) {
    return RegExp(r'sub\s*[-]?\s*total', caseSensitive: false).hasMatch(line);
  }

  /// Find the largest decimal amount in a line (most likely the total value).
  double? _findBiggestAmount(String line) {
    // Match multi-segment numbers (e.g. "5.710.79", "10.99") preceded by optional currency
    final multiPat = RegExp(r'[₱$€£¥₩₹]?\s*\(?\s*(\d+([.,]\d+)+)\s*\)?');
    double? largest;
    for (final match in multiPat.allMatches(line)) {
      final value = parseRegionalPrice(match.group(1)!);
      if (value != null && (largest == null || value > largest)) {
        largest = value;
      }
    }
    // Also match simpler single-segment numbers for fallback
    if (largest == null) {
      final simplePat = RegExp(r'[₱$€£¥₩₹]?\s*\(?\s*(\d[\d,]*\.?\d{0,2})\s*\)?');
      for (final match in simplePat.allMatches(line)) {
        final raw = match.group(1)?.replaceAll(RegExp(r'[,，]'), '');
        final value = double.tryParse(raw ?? '');
        if (value != null && (largest == null || value > largest)) {
          largest = value;
        }
      }
    }
    return largest;
  }

  // ── Line-item extraction ────────────────────────────────────────────

  List<ScannedItem> _extractItems(List<String> lines, double? knownTotal) {
    final items = <ScannedItem>[];

    // Match prices at the absolute end of a line, with optional currency prefix.
    // Handles both integers ($300) and decimals ($50.20 / 5.710.79).
    final endPrice = RegExp(r'[₱$€£¥₩₹]?\s*(\d+([.,]\d+)*)\s*$');

    // Match a leading quantity integer before the item description, e.g. "2 32131357 EG"
    final leadingQty = RegExp(r'^(\d+)\s+');

    final skipTerms = RegExp(
      r'(subtotal|tax|total|store|sale#|-\s*sale\s*-|tel|phone|terminal|trans|credit|debit|cash|change|road|street|st\b|ave\b|suite)',
      caseSensitive: false,
    );

    for (final line in lines) {
      final t = line.trim();
      if (t.length < 3) continue;
      if (skipTerms.hasMatch(t)) continue;
      if (_isSubtotalLine(t)) continue;
      if (!RegExp(r'[a-zA-Z\u00C0-\u024F]').hasMatch(t)) continue;

      final priceMatch = endPrice.firstMatch(t);
      if (priceMatch == null) continue;

      final price = parseRegionalPrice(priceMatch.group(1)!);
      if (price == null || price <= 0) continue;
      if (knownTotal != null && (price - knownTotal).abs() < 0.01) continue;

      // Everything before the price — this is the description + optional qty
      String remainder = t.substring(0, priceMatch.start).trim();

      // Parse leading quantity prefix
      int quantity = 1;
      final qtyMatch = leadingQty.firstMatch(remainder);
      if (qtyMatch != null) {
        quantity = int.tryParse(qtyMatch.group(1)!) ?? 1;
        remainder = remainder.substring(qtyMatch.end).trim();
      }

      // Strip stray currency symbols from the description
      remainder = remainder.replaceAll(RegExp(r'[₱$€£¥₩₹]'), '').trim();

      // Safety filter: skip address/metadata lines where digits outnumber letters
      final letterCount = RegExp(r'[a-zA-Z]').allMatches(remainder).length;
      final digitCount = RegExp(r'\d').allMatches(remainder).length;
      if (digitCount > letterCount) continue;

      if (remainder.isEmpty) remainder = 'Item';

      items.add(ScannedItem(name: remainder, price: price, quantity: quantity));
    }

    return items;
  }
}
