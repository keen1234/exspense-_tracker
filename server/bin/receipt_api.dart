import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

void main() async {
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_router);

   final server = await io.serve(handler, '0.0.0.0', 8080);
   // ignore: avoid_print
   print('Receipt Scanner API running on http://${server.address.host}:${server.port}');
}

Future<Response> _router(Request request) async {
  // Health check
  if (request.url.path == 'health' && request.method == 'GET') {
    return Response.ok(
      jsonEncode({'status': 'ok'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // Scan receipt
  if (request.url.path == 'scan' && request.method == 'POST') {
    return await _handleScan(request);
  }

  return Response.notFound(jsonEncode({'error': 'Endpoint not found'}),
      headers: {'Content-Type': 'application/json'});
}

Future<Response> _handleScan(Request request) async {
  File? tempFile;
  TextRecognizer? textRecognizer;

  try {
    // Read image bytes from request body
    final bytes = await request.read().expand((e) => e).toList();

    if (bytes.isEmpty) {
      return Response(400,
          body: jsonEncode({'error': 'No image data provided'}),
          headers: {'Content-Type': 'application/json'});
    }

    // Write to temp file
    tempFile = File(p.join(Directory.systemTemp.path, 'receipt_${DateTime.now().millisecondsSinceEpoch}.jpg'));
    await tempFile.writeAsBytes(bytes);

    // Run OCR
    textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final inputImage = InputImage.fromFile(tempFile);
    final recognizedText = await textRecognizer.processImage(inputImage);

    // Extract structured lines
    final structuredLines = <String>[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isNotEmpty) {
          structuredLines.add(text);
        }
      }
    }

    // Parse receipt
    final parsed = parseReceipt(recognizedText.text, structuredLines: structuredLines);

    return Response.ok(
      jsonEncode({
        'vendor': parsed.vendor,
        'date': parsed.date?.toIso8601String(),
        'currencyCode': parsed.currencyCode,
        'subtotal': parsed.subtotal,
        'tax': parsed.tax,
        'discount': parsed.discount,
        'tip': parsed.tip,
        'serviceCharge': parsed.serviceCharge,
        'total': parsed.amount,
        'items': parsed.items.map((i) => {
          'name': i.name,
          'price': i.price,
          'quantity': i.quantity,
          'unitPrice': i.unitPrice,
        }).toList(),
        'parseError': parsed.parseError,
        'rawText': parsed.rawText,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stack) {
    return Response(500,
        body: jsonEncode({
          'error': 'Failed to process receipt',
          'details': e.toString(),
          'stackTrace': stack.toString(),
        }),
        headers: {'Content-Type': 'application/json'});
  } finally {
    await textRecognizer?.close();
    if (tempFile != null && await tempFile.exists()) {
      await tempFile.delete();
    }
  }
}

// ── Receipt Parser (copied from lib/services/receipt_parser.dart) ──

class ReceiptItem {
  final String name;
  final double price;
  final int quantity;
  final double? unitPrice;

  const ReceiptItem({
    required this.name,
    required this.price,
    this.quantity = 1,
    this.unitPrice,
  });
}

class ReceiptData {
  final double? amount;
  final double? subtotal;
  final double? tax;
  final double? discount;
  final double? tip;
  final double? serviceCharge;
  final DateTime? date;
  final String? vendor;
  final String? currencyCode;
  final List<ReceiptItem> items;
  final String rawText;
  final String? parseError;

  const ReceiptData({
    this.amount,
    this.subtotal,
    this.tax,
    this.discount,
    this.tip,
    this.serviceCharge,
    this.date,
    this.vendor,
    this.currencyCode,
    this.items = const [],
    required this.rawText,
    this.parseError,
  });

  bool get hasData => amount != null || date != null || vendor != null || items.isNotEmpty;
}

ReceiptData parseReceipt(String ocrText, {List<String>? structuredLines}) {
  final lines = structuredLines ??
      ocrText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  final cleaned = lines.map(_cleanLine).where((l) => l.isNotEmpty).toList();

  if (cleaned.isEmpty) {
    return ReceiptData(rawText: ocrText, parseError: 'No readable text found on the receipt.');
  }

  final vendor = _extractVendor(cleaned);
  final date = _extractDate(cleaned);
  final currencyCode = _detectCurrency(cleaned);
  final total = _extractTotal(cleaned);
  final subtotal = _extractSubtotal(cleaned);
  final tax = _extractTax(cleaned);
  final discount = _extractDiscount(cleaned);
  final tip = _extractTip(cleaned);
  final serviceCharge = _extractServiceCharge(cleaned);
  final items = _extractItems(cleaned, total);

  String? error;
  if (total == null && items.isEmpty && vendor == null && date == null) {
    error = 'Could not extract any data. Try a clearer photo.';
  } else if (total == null && items.isEmpty) {
    error = 'Could not read prices or items.';
  }

  return ReceiptData(
    vendor: vendor, date: date, currencyCode: currencyCode,
    items: items, subtotal: subtotal, tax: tax,
    discount: discount, tip: tip, serviceCharge: serviceCharge,
    amount: total, rawText: ocrText, parseError: error,
  );
}

String _cleanLine(String line) {
  var s = line.trim();
  if (s.isEmpty) return '';
  s = s.replaceAll(RegExp(r'\s{2,}'), ' ');
  s = s.replaceAllMapped(RegExp(r'(\d)[Oo](\d)'), (m) => '${m[1]}0${m[2]}');
  s = s.replaceAllMapped(RegExp(r'(\d)[Oo]$'), (m) => '${m[1]}0');
  s = s.replaceAllMapped(RegExp(r'^[Oo](\d)'), (m) => '0${m[1]}');
  return s;
}

String? _detectCurrency(List<String> lines) {
  final text = lines.join(' ');
  if (RegExp(r'₱').hasMatch(text)) return 'PHP';
  if (RegExp(r'\$').hasMatch(text)) return 'USD';
  if (RegExp(r'€').hasMatch(text)) return 'EUR';
  if (RegExp(r'£').hasMatch(text)) return 'GBP';
  if (RegExp(r'¥').hasMatch(text)) return 'JPY';
  if (RegExp(r'₩').hasMatch(text)) return 'KRW';
  if (RegExp(r'₹').hasMatch(text)) return 'INR';
  if (RegExp(r'₫').hasMatch(text)) return 'VND';
  if (RegExp(r'฿').hasMatch(text)) return 'THB';
  return null;
}

double? _extractTotal(List<String> lines) {
  for (final line in lines.reversed) {
    if (_isTotalLine(line) && !_isSubtotalLine(line)) {
      final amount = _findAmount(line);
      if (amount != null && amount > 0) return amount;
    }
  }
  for (final line in lines.reversed) {
    if (RegExp(r'[₱$€£¥₩₹]').hasMatch(line)) {
      if (_isSubtotalLine(line)) continue;
      final amount = _findAmount(line);
      if (amount != null && amount > 0) return amount;
    }
  }
  // Fallback: last line with any positive amount
  for (final line in lines.reversed) {
    if (_isSubtotalLine(line)) continue;
    final amount = _findAmount(line);
    if (amount != null && amount > 0) return amount;
  }
  return null;
}

bool _isTotalLine(String line) {
  final lower = line.toLowerCase().trim();
  if (lower.startsWith('sub')) return false;
  return RegExp(r'(total|amount\s*due|grand\s*total|amount\s*paid|balance\s*due|please\s*pay|you\s*pay|amt\s*due)', caseSensitive: false).hasMatch(line);
}

double? _extractSubtotal(List<String> lines) {
  for (final line in lines.reversed) {
    if (_isSubtotalLine(line)) return _findAmount(line);
  }
  return null;
}

bool _isSubtotalLine(String line) {
  return RegExp(r'sub\s*[-]?\s*total', caseSensitive: false).hasMatch(line);
}

double? _extractTax(List<String> lines) {
  for (final line in lines.reversed) {
    if (RegExp(r'(^|\s)(tax|vat|gst|hst)\s', caseSensitive: false).hasMatch(line)) {
      final amount = _findAmount(line);
      if (amount != null && amount > 0) return amount;
    }
  }
  return null;
}

double? _extractDiscount(List<String> lines) {
  for (final line in lines.reversed) {
    if (RegExp(r'(discount|promo|coupon|savings|less|deduction)', caseSensitive: false).hasMatch(line)) {
      final amount = _findAmount(line);
      if (amount != null && amount > 0) return amount;
    }
  }
  return null;
}

double? _extractTip(List<String> lines) {
  for (final line in lines.reversed) {
    if (RegExp(r'(tip|gratuity)', caseSensitive: false).hasMatch(line)) {
      final amount = _findAmount(line);
      if (amount != null && amount > 0) return amount;
    }
  }
  return null;
}

double? _extractServiceCharge(List<String> lines) {
  for (final line in lines.reversed) {
    if (RegExp(r'service\s*charge', caseSensitive: false).hasMatch(line)) {
      final amount = _findAmount(line);
      if (amount != null && amount > 0) return amount;
    }
  }
  return null;
}

List<ReceiptItem> _extractItems(List<String> lines, double? knownTotal) {
  final items = <ReceiptItem>[];

  final summaryOnly = RegExp(
    r'^(total|subtotal|sub\s*total|tax|vat|gst|hst|amount\s*due|grand\s*total|balance\s*due|change|cash\s*tendered|payment|discount|tip|gratuity|service\s*charge|net\s*amount)\s*[:\s\-]*[₱$€£¥₩₹]?\s*\d[\s\d,.]*$',
    caseSensitive: false,
  );

  ReceiptItem? tryParseItem(String line) {
    final pricePattern = RegExp(r'\d[\d,]*\.\d{1,2}');
    final priceMatches = pricePattern.allMatches(line).toList();
    if (priceMatches.isEmpty) return null;
    final lastPrice = priceMatches.last;
    final price = _parseNum(lastPrice.group(0));
    if (price == null || price <= 0) return null;
    final name = line.substring(0, lastPrice.start).trim();
    if (name.length < 2) return null;
    if (!RegExp(r'[a-zA-Z\u00C0-\u024F]').hasMatch(name)) return null;
    if (knownTotal != null && (price - knownTotal).abs() < 0.01) return null;
    if (RegExp(r'^(total|subtotal|tax|vat|change|cash|card|credit|debit|payment|discount|due|paid|tip|gratuity|service|charge|balance|amount|net|sum|please|thank|welcome|receipt|invoice)$',
        caseSensitive: false).hasMatch(name.trim())) {
      return null;
    }
    return ReceiptItem(name: name, price: price);
  }

  final itemPattern = RegExp(
    r'^(.+)\s+[₱$€£¥₩₹P]?\s*(\d[\d,]*\.?\d{0,2})\s*$',
  );

  final patQtyFirst = RegExp(
    r'^(\d+)\s*[xX\*]\s+(.+)\s+[₱$€£¥₩₹P]?\s*(\d[\d,]*\.?\d{0,2})\s*$',
  );
  final patQtyLast = RegExp(
    r'^(.+)\s+[xX\*]\s*(\d+)\s+[₱$€£¥₩₹P]?\s*(\d[\d,]*\.?\d{0,2})\s*$',
  );

  for (final line in lines) {
    if (line.length < 3) continue;
    if (summaryOnly.hasMatch(line)) continue;
    if (RegExp(r'^[\d\s\.\-/:,]+$').hasMatch(line) && !RegExp(r'[a-zA-Z\u00C0-\u024F]').hasMatch(line)) continue;
    if (RegExp(r'^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}$').hasMatch(line)) continue;
    if (RegExp(r'^(OR|INV|REF|TXN|ID)[\s:#]*\d+', caseSensitive: false).hasMatch(line)) continue;
    if (RegExp(r'^\+?\d[\d\s\-]{7,}$').hasMatch(line)) continue;
    if (!RegExp(r'[a-zA-Z\u00C0-\u024F]').hasMatch(line)) continue;

    ReceiptItem? item;

    final m1 = patQtyFirst.firstMatch(line);
    if (m1 != null) {
      final qty = int.tryParse(m1.group(1) ?? '') ?? 1;
      final name = m1.group(2)?.trim();
      final totalPrice = _parseNum(m1.group(3));
      if (name != null && name.isNotEmpty && totalPrice != null && totalPrice > 0) {
        final unit = qty > 1 ? totalPrice / qty : null;
        item = ReceiptItem(name: qty > 1 ? '$qty x $name' : name, price: totalPrice, quantity: qty, unitPrice: unit);
      }
    }

    if (item == null) {
      final m2 = patQtyLast.firstMatch(line);
      if (m2 != null) {
        final name = m2.group(1)?.trim();
        final qty = int.tryParse(m2.group(2) ?? '') ?? 1;
        final totalPrice = _parseNum(m2.group(3));
        if (name != null && name.isNotEmpty && totalPrice != null && totalPrice > 0) {
          final unit = qty > 1 ? totalPrice / qty : null;
          item = ReceiptItem(name: qty > 1 ? '$name x$qty' : name, price: totalPrice, quantity: qty, unitPrice: unit);
        }
      }
    }

    if (item == null) {
      final m3 = itemPattern.firstMatch(line);
      if (m3 != null) {
        final name = m3.group(1)?.trim();
        final price = _parseNum(m3.group(2));
        if (name != null && name.length >= 2 && price != null && price > 0 &&
            RegExp(r'[a-zA-Z\u00C0-\u024F]').hasMatch(name) &&
            !(knownTotal != null && (price - knownTotal).abs() < 0.01) &&
            !RegExp(r'^(total|subtotal|tax|vat|change|cash|card|credit|debit|payment|discount|due|paid|tip|gratuity|service|charge|balance|amount|net|sum|please|thank|welcome|receipt|invoice)$',
                caseSensitive: false).hasMatch(name.trim())) {
          item = ReceiptItem(name: name, price: price);
        }
      }
    }

    item ??= tryParseItem(line);

    if (item != null) {
      items.add(item);
    }
  }

  return items;
}

String? _extractVendor(List<String> lines) {
  for (final line in lines.take(5)) {
    if (line.length < 2) continue;
    final digitCount = RegExp(r'\d').allMatches(line).length;
    if (digitCount / line.length > 0.5) continue;
    if (RegExp(r'(receipt|invoice|transaction|order|cashier|register|tel\s*:|phone|fax|www\.|http|@|tax\s*id|TIN|VAT|OR\s*#|date|time|branch|address|welcome|thank|please)', caseSensitive: false).hasMatch(line)) continue;
    if (RegExp(r'^[\d\s\.\-/:]+$').hasMatch(line)) continue;
    if (RegExp(r'^[^a-zA-Z\u00C0-\u024F\u0400-\u04FF]+$').hasMatch(line)) continue;
    if (RegExp(r'^\+?\d[\d\s\-]{7,}$').hasMatch(line)) continue;
    return line;
  }
  return null;
}

DateTime? _extractDate(List<String> lines) {
  for (final line in lines) {
    DateTime? dt;
    dt = _tryParseDate(line, RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'), iso: true);
    if (dt != null) return dt;
    dt = _tryParseDate(line, RegExp(r'(\d{1,2})[/-](\d{1,2})[/-](\d{4})'));
    if (dt != null) return dt;

    final shortDate = RegExp(r'(\d{1,2})[/-](\d{1,2})[/-](\d{2})$');
    final shortMatch = shortDate.firstMatch(line);
    if (shortMatch != null) {
      final a = int.tryParse(shortMatch.group(1) ?? '');
      final b = int.tryParse(shortMatch.group(2) ?? '');
      var y = int.tryParse(shortMatch.group(3) ?? '');
      if (a != null && b != null && y != null) {
        if (y < 100) y += 2000;
        int month, day;
        if (a > 12) { day = a; month = b; }
        else if (b > 12) { month = a; day = b; }
        else { month = a; day = b; }
        if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
          dt = DateTime.tryParse('$y-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}');
          if (dt != null && _isValidDate(dt)) return dt;
        }
      }
    }

    dt = _tryParseMonthName(line);
    if (dt != null) return dt;
    dt = _tryParseDayMonthYear(line);
    if (dt != null) return dt;
  }
  return null;
}

DateTime? _tryParseDate(String line, RegExp pattern, {bool iso = false}) {
  final match = pattern.firstMatch(line);
  if (match == null) return null;
  try {
    final a = int.parse(match.group(1)!);
    final b = int.parse(match.group(2)!);
    var c = int.parse(match.group(3)!);
    int year, month, day;
    if (iso) { year = a; month = b; day = c; }
    else { month = a; day = b; year = c; }
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final dt = DateTime.tryParse('$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}');
    if (dt != null && _isValidDate(dt)) return dt;
  } catch (_) {}
  return null;
}

DateTime? _tryParseMonthName(String line) {
  final pattern = RegExp(r'(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+(\d{1,2}),?\s+(\d{4})', caseSensitive: false);
  final match = pattern.firstMatch(line);
  if (match == null) return null;
  try {
    final formatted = '${match.group(1)} ${match.group(2)}, ${match.group(3)}';
    final dt = _tryParseFormats(formatted, ['MMMM d, yyyy', 'MMM d, yyyy']);
    if (dt != null && _isValidDate(dt)) return dt;
  } catch (_) {}
  return null;
}

DateTime? _tryParseDayMonthYear(String line) {
  final pattern = RegExp(r'(\d{1,2})\s+(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+(\d{4})', caseSensitive: false);
  final match = pattern.firstMatch(line);
  if (match == null) return null;
  try {
    final formatted = '${match.group(2)} ${match.group(1)}, ${match.group(3)}';
    final dt = _tryParseFormats(formatted, ['MMM d, yyyy', 'MMMM d, yyyy']);
    if (dt != null && _isValidDate(dt)) return dt;
  } catch (_) {}
  return null;
}

DateTime? _tryParseFormats(String text, List<String> formats) {
  for (final fmt in formats) {
    try {
      final dt = DateFormat(fmt).tryParse(text);
      if (dt != null) return dt;
    } catch (_) {}
  }
  return null;
}

bool _isValidDate(DateTime dt) {
  final now = DateTime.now();
  return dt.isAfter(DateTime(2000)) && dt.isBefore(now.add(const Duration(days: 2)));
}

double? _findAmount(String line) {
  final pattern = RegExp(r'[₱$€£¥₩₹]?\s*\(?\s*(\d{1,3}(?:[,，]\d{3})*(?:\.\d{1,2})?)\s*\)?');
  double? largest;
  for (final match in pattern.allMatches(line)) {
    final raw = match.group(1)?.replaceAll(RegExp(r'[,，]'), '');
    final value = double.tryParse(raw ?? '');
    if (value != null && (largest == null || value > largest)) largest = value;
  }
  return largest;
}

double? _parseNum(String? s) {
  if (s == null) return null;
  return double.tryParse(s.replaceAll(RegExp(r'[,，]'), ''));
}

