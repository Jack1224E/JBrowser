import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';

final vaultDbProvider = Provider<VaultDb>((ref) {
  return VaultDb();
});

class VaultDb {
  static Database? _database;
  bool _isInit = false;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    if (!_isInit && Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _isInit = true;
    }

    final home = Platform.environment['HOME'] ?? '/tmp';
    final dbDir = Directory('$home/.local/state/jbrowser/vault');
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }
    
    final path = join(dbDir.path, 'whiteboard.sqlite');
    
    dev.log('[WHITEBOARD] Initializing database at $path');
    
    return await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE vault (
              gid TEXT PRIMARY KEY,
              url TEXT NOT NULL,
              file_path TEXT,
              status TEXT NOT NULL,
              journaled_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          dev.log('[WHITEBOARD] Database created with standard schemas.');
        },
      ),
    );
  }

  Future<void> insertTask({
    required String gid, 
    required String url, 
    String status = 'pending',
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'vault',
      {
        'gid': gid,
        'url': url,
        'status': status,
        'journaled_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    dev.log('[WHITEBOARD] Inserted Task GID: $gid');
  }

  Future<void> markDeleted(String gid) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'vault',
      {
        'status': 'deleted',
        'updated_at': now,
      },
      where: 'gid = ?',
      whereArgs: [gid],
    );
    dev.log('[WHITEBOARD] Marked GID $gid as deleted in DB.');
  }

  Future<void> updateStatus(String gid, String status) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'vault',
      {
        'status': status,
        'updated_at': now,
      },
      where: 'gid = ?',
      whereArgs: [gid],
    );
  }

  Future<List<Map<String, dynamic>>> getActiveAndPending() async {
    final db = await database;
    return await db.query(
      'vault',
      where: 'status != ?',
      whereArgs: ['deleted'],
      orderBy: 'journaled_at DESC',
    );
  }
}
