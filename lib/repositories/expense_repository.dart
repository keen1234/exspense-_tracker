import '../database/db_helper.dart';
import '../models/entry.dart';
import '../models/tag.dart';

class ExpenseRepository {
  static Future<List<Tag>> getAllTags() async {
    final maps = await DBHelper.getAll('tags', orderBy: 'name ASC');
    return maps.map((m) => Tag.fromMap(m)).toList();
  }

  static Future<Tag?> getTagById(int id) async {
    final results = await DBHelper.rawQuery(
      'SELECT * FROM tags WHERE id = ?',
      [id],
    );
    if (results.isEmpty) return null;
    return Tag.fromMap(results.first);
  }

  static Future<int> insertTag(Tag tag) async {
    return await DBHelper.insert('tags', tag.toMap());
  }

  static Future<int> updateTag(Tag tag) async {
    if (tag.id == null) {
      throw ArgumentError('Tag id is required for update');
    }

    return await DBHelper.update(
      'tags',
      tag.toMap(),
      'id = ?',
      [tag.id],
    );
  }

  static Future<int> deleteTag(int id) async {
    return await DBHelper.delete('tags', 'id = ?', [id]);
  }

  static Future<List<Entry>> getAllEntries({String? orderBy}) async {
    final maps = await DBHelper.getAll(
      'entries',
      orderBy: orderBy ?? 'date DESC, id DESC',
    );
    return maps.map((m) => Entry.fromMap(m)).toList();
  }

  static Future<List<Entry>> getEntriesByDateRange(
      DateTime start,
      DateTime end,
      ) async {
    final maps = await DBHelper.rawQuery('''
      SELECT * FROM entries 
      WHERE date BETWEEN ? AND ?
      ORDER BY date DESC
    ''', [
      start.toIso8601String().split('T').first,
      end.toIso8601String().split('T').first,
    ]);
    return maps.map((m) => Entry.fromMap(m)).toList();
  }

  static Future<int> insertEntry(Entry entry) async {
    return await DBHelper.insert('entries', entry.toMap());
  }

  static Future<int> updateEntry(Entry entry) async {
    if (entry.id == null) {
      throw ArgumentError('Entry id is required for update');
    }

    return await DBHelper.update(
      'entries',
      entry.toMap(),
      'id = ?',
      [entry.id],
    );
  }

  static Future<int> deleteEntry(int id) async {
    return await DBHelper.delete('entries', 'id = ?', [id]);
  }

  static Future<double> getBalance() async {
    final result = await DBHelper.rawQuery(
      'SELECT SUM(amount) as total FROM entries',
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  static Future<Map<Tag, double>> getTotalsByTag() async {
    final results = await DBHelper.rawQuery('''
      SELECT t.id, t.name, t.type, SUM(e.amount) as total
      FROM entries e
      JOIN tags t ON e.tag_id = t.id
      GROUP BY t.id
      ORDER BY total DESC
    ''');

    final Map<Tag, double> totals = {};
    for (final row in results) {
      final tag = Tag.fromMap(row);
      totals[tag] = (row['total'] as num).toDouble();
    }
    return totals;
  }
}
