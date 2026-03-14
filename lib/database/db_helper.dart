import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../services/settings_service.dart';

class DatabaseException implements Exception {
  final String message;
  DatabaseException(this.message);
  @override
  String toString() => 'DatabaseException: $message';
}

class DBHelper {
  static Database? _db;
  static Future<Database>? _initializationFuture;
  static String? _initializationPath;
  static const int _databaseVersion = 4;

  static Future<Database> get database async {
    final path = await _getDatabasePath();

    if (_db != null && _db!.isOpen && _db!.path == path) {
      return _db!;
    }

    if (_db != null && _db!.isOpen && _db!.path != path) {
      await close();
    }

    if (_initializationFuture != null && _initializationPath == path) {
      return _initializationFuture!;
    }

    _initializationPath = path;
    _initializationFuture = _initDB(path);
    try {
      _db = await _initializationFuture!;
      return _db!;
    } finally {
      _initializationFuture = null;
      _initializationPath = null;
    }
  }

  static Future<Database> _initDB(String path) async {
    try {
      // Check if we need to delete old/corrupted database
      await _validateOrRecreateDatabase(path);

      final db = await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: (db) async {
          // Enable foreign keys
          await db.execute('PRAGMA foreign_keys = ON');
        },
      );

      return db;
    } catch (e) {
      throw DatabaseException('Failed to initialize database: $e');
    }
  }

  static Future<String> _getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    final databaseName = SettingsService().getCurrentDatabaseName();
    return join(dbPath, databaseName);
  }

  /// Validates existing database schema before opening it normally.
  static Future<void> _validateOrRecreateDatabase(String path) async {
    final exists = await databaseExists(path);
    if (!exists) {
      return;
    }

    Database? testDb;
    try {
      testDb = await openDatabase(
        path,
        readOnly: true,
        singleInstance: false,
      );

      final tables = await testDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );

      final tableNames = tables
          .map((table) => table['name'])
          .whereType<String>()
          .toSet();

      if (tableNames.isNotEmpty &&
          (!tableNames.contains('tags') || !tableNames.contains('entries'))) {
        throw DatabaseException(
          'Existing database schema is missing required tables.',
        );
      }
    } finally {
      if (testDb != null && testDb.isOpen) {
        await testDb.close();
      }
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tag_groups(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE tags(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('expense', 'income')),
        group_id INTEGER,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ,FOREIGN KEY(group_id) REFERENCES tag_groups(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        tag_id INTEGER NOT NULL,
        note TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('CREATE INDEX idx_entries_date ON entries(date)');
    await db.execute('CREATE INDEX idx_entries_tag ON entries(tag_id)');
    await _createTagUniqueIndex(db);
    await _createTagGroupUniqueIndex(db);
    await _createTagGroupIndex(db);
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE tags ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE entries ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP');
      } catch (_) {}
    }

    if (oldVersion < 3) {
      await _mergeDuplicateTags(db);
      await _createTagUniqueIndex(db);
    }

    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS tag_groups(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      try {
        await db.execute(
          'ALTER TABLE tags ADD COLUMN group_id INTEGER REFERENCES tag_groups(id) ON DELETE SET NULL',
        );
      } catch (_) {}
      await _createTagGroupUniqueIndex(db);
      await _createTagGroupIndex(db);
    }
  }

  static Future<void> _mergeDuplicateTags(Database db) async {
    final duplicates = await db.rawQuery('''
      SELECT MIN(id) AS keep_id, name, type
      FROM tags
      GROUP BY name COLLATE NOCASE, type
      HAVING COUNT(*) > 1
    ''');

    for (final duplicate in duplicates) {
      final keepId = duplicate['keep_id'] as int;
      final name = duplicate['name'] as String;
      final type = duplicate['type'] as String;

      final duplicateRows = await db.query(
        'tags',
        columns: ['id'],
        where: 'name = ? COLLATE NOCASE AND type = ? AND id != ?',
        whereArgs: [name, type, keepId],
      );

      for (final row in duplicateRows) {
        final duplicateId = row['id'] as int;
        await db.update(
          'entries',
          {'tag_id': keepId},
          where: 'tag_id = ?',
          whereArgs: [duplicateId],
        );
        await db.delete(
          'tags',
          where: 'id = ?',
          whereArgs: [duplicateId],
        );
      }
    }
  }

  static Future<void> _createTagUniqueIndex(Database db) async {
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_name_type_unique '
      'ON tags(name COLLATE NOCASE, type)',
    );
  }

  static Future<void> _createTagGroupUniqueIndex(Database db) async {
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_tag_groups_name_unique '
      'ON tag_groups(name COLLATE NOCASE)',
    );
  }

  static Future<void> _createTagGroupIndex(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tags_group_id ON tags(group_id)',
    );
  }

  // Safe database access with retry
  static Future<T> _safeDbAccess<T>(Future<T> Function(Database db) operation) async {
    int retries = 0;
    const maxRetries = 3;

    while (retries < maxRetries) {
      try {
        final db = await database;
        if (!db.isOpen) {
          throw DatabaseException('Database is closed');
        }
        return await operation(db);
      } catch (e) {
        if (e.toString().contains('database_closed') || e.toString().contains('DatabaseException')) {
          retries++;
          _db = null;
          _initializationFuture = null;
          if (retries < maxRetries) {
            await Future.delayed(Duration(milliseconds: 100 * retries));
            continue;
          }
        }
        rethrow;
      }
    }
    throw DatabaseException('Max retries exceeded');
  }

  static Future<int> insert(String table, Map<String, dynamic> data) async {
    return _safeDbAccess((db) async {
      return await db.insert(
        table,
        data,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }

  static Future<List<Map<String, dynamic>>> getAll(
      String table, {
        String? orderBy,
        int? limit,
        int? offset,
      }) async {
    return _safeDbAccess((db) async {
      return await db.query(
        table,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
    });
  }

  static Future<int> update(
      String table,
      Map<String, dynamic> data,
      String where,
      List<dynamic> whereArgs,
      ) async {
    return _safeDbAccess((db) async {
      return await db.update(
        table,
        data,
        where: where,
        whereArgs: whereArgs,
      );
    });
  }

  static Future<int> delete(String table, String where, List<dynamic> whereArgs) async {
    return _safeDbAccess((db) async {
      return await db.delete(
        table,
        where: where,
        whereArgs: whereArgs,
      );
    });
  }

  static Future<List<Map<String, dynamic>>> rawQuery(
      String sql, [
        List<dynamic>? arguments,
      ]) async {
    return _safeDbAccess((db) async {
      return await db.rawQuery(sql, arguments);
    });
  }

  static Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
    _initializationFuture = null;
  }

  static Future<void> resetDatabase() async {
    try {
      final path = await _getDatabasePath();

      await close();
      await deleteDatabase(path);
      _db = null;
      _initializationFuture = null;

      await database;
    } catch (e) {
      throw DatabaseException('Failed to reset database: $e');
    }
  }
}
