import '../database/db_helper.dart';
import '../models/entry.dart';
import '../models/tag.dart';
import '../models/tag_group.dart';

class ExpenseRepository {
  static Future<List<Tag>> getAllTags() async {
    final maps = await DBHelper.rawQuery('''
      SELECT
        t.id,
        t.name,
        t.type,
        t.group_id,
        g.name AS group_name
      FROM tags t
      LEFT JOIN tag_groups g ON g.id = t.group_id
      ORDER BY
        CASE WHEN g.name IS NULL THEN 1 ELSE 0 END,
        LOWER(COALESCE(g.name, '')),
        CASE WHEN t.type = 'income' THEN 0 ELSE 1 END,
        LOWER(t.name)
    ''');
    return maps.map((m) => Tag.fromMap(m)).toList();
  }

  static Future<List<TagGroup>> getAllTagGroups() async {
    final maps = await DBHelper.getAll('tag_groups', orderBy: 'name COLLATE NOCASE ASC');
    return maps.map((m) => TagGroup.fromMap(m)).toList();
  }

  static Future<Tag?> getTagById(int id) async {
    final results = await DBHelper.rawQuery(
      '''
      SELECT
        t.id,
        t.name,
        t.type,
        t.group_id,
        g.name AS group_name
      FROM tags t
      LEFT JOIN tag_groups g ON g.id = t.group_id
      WHERE t.id = ?
      ''',
      [id],
    );
    if (results.isEmpty) return null;
    return Tag.fromMap(results.first);
  }

  static Future<int> insertTag(Tag tag) async {
    return await DBHelper.insert('tags', tag.toMap());
  }

  static Future<int> insertTagGroup(TagGroup group) async {
    return await DBHelper.insert('tag_groups', group.toMap());
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

  static Future<int> updateTagGroup(TagGroup group) async {
    if (group.id == null) {
      throw ArgumentError('Group id is required for update');
    }

    return await DBHelper.update(
      'tag_groups',
      group.toMap(),
      'id = ?',
      [group.id],
    );
  }

  static Future<int> deleteTag(int id) async {
    return await DBHelper.delete('tags', 'id = ?', [id]);
  }

  static Future<int> deleteTagGroup(int id) async {
    return await DBHelper.delete('tag_groups', 'id = ?', [id]);
  }

  static Future<void> replaceGroupMembership(int groupId, List<int> tagIds) async {
    final db = await DBHelper.database;
    await db.transaction((txn) async {
      await txn.update(
        'tags',
        {'group_id': null},
        where: 'group_id = ?',
        whereArgs: [groupId],
      );

      for (final tagId in tagIds) {
        await txn.update(
          'tags',
          {'group_id': groupId},
          where: 'id = ?',
          whereArgs: [tagId],
        );
      }
    });
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
      SELECT t.id, t.name, t.type, t.group_id, g.name AS group_name, SUM(e.amount) as total
      FROM entries e
      JOIN tags t ON e.tag_id = t.id
      LEFT JOIN tag_groups g ON g.id = t.group_id
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
