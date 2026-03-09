import 'package:intl/intl.dart';

class Entry {
  final int? id;
  final double amount;
  final DateTime date;
  final String? note;
  final int tagId;

  Entry({
    this.id,
    required this.amount,
    required this.date,
    this.note,
    required this.tagId,
  });

  factory Entry.fromMap(Map<String, dynamic> map) {
    return Entry(
      id: map['id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String),
      note: map['note'] as String?,
      tagId: map['tag_id'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'date': DateFormat('yyyy-MM-dd').format(date),
      'note': note,
      'tag_id': tagId,
    };
  }

  bool get isIncome => amount > 0;
  bool get isExpense => amount < 0;
  double get absoluteAmount => amount.abs();

  String get formattedAmount {
    final formatter = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    return formatter.format(amount);
  }

  String get formattedAbsoluteAmount {
    final formatter = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    return formatter.format(absoluteAmount);
  }

  String formatAmount({String symbol = '₱'}) {
    final formatter = NumberFormat.currency(symbol: symbol, decimalDigits: 2);
    return formatter.format(amount);
  }

  String formatAbsoluteAmount({String symbol = '₱'}) {
    final formatter = NumberFormat.currency(symbol: symbol, decimalDigits: 2);
    return formatter.format(absoluteAmount);
  }
}
