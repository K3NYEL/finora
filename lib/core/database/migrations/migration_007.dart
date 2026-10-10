import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Adds stable UUIDs without replacing legacy integer primary keys.
///
/// This migration only prepares local identity and checkpoints. It does not
/// enqueue records, link an account, or enable any network synchronization.
Future<void> applyMigration007(Database database) async {
  const uuid = Uuid();
  for (final table in ['accounts', 'categories', 'transactions', 'transfers']) {
    await database.execute('ALTER TABLE $table ADD COLUMN sync_id TEXT');
    await database.execute('ALTER TABLE $table ADD COLUMN remote_sync_version INTEGER');
    await database.execute('''
      ALTER TABLE $table ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'local_only'
      CHECK (sync_status IN ('local_only', 'pending', 'synced', 'conflict'))
    ''');

    // Built-in/shared categories have user_id IS NULL and must not acquire a
    // server identity; they are local templates, not user-owned remote data.
    final where = table == 'categories' ? 'WHERE user_id IS NOT NULL' : '';
    final rows = await database.query(table, columns: ['id'], where: where.isEmpty ? null : where);
    for (final row in rows) {
      await database.update(
        table,
        {'sync_id': uuid.v4()},
        where: 'id = ? AND sync_id IS NULL',
        whereArgs: [row['id']],
      );
    }
    await database.execute(
      'CREATE UNIQUE INDEX idx_${table}_sync_id ON $table(sync_id) WHERE sync_id IS NOT NULL',
    );
    await database.execute(
      'CREATE INDEX idx_${table}_sync_status ON $table(sync_status, user_id)',
    );
  }

  await database.execute('''
    CREATE TABLE sync_state (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      cursor INTEGER NOT NULL DEFAULT 0 CHECK (cursor >= 0),
      enabled INTEGER NOT NULL DEFAULT 0 CHECK (enabled IN (0, 1)),
      linked_user_id TEXT,
      last_pull_at TEXT,
      last_push_at TEXT,
      updated_at TEXT NOT NULL
    )
  ''');
  await database.insert('sync_state', {
    'id': 1,
    'cursor': 0,
    'enabled': 0,
    'linked_user_id': null,
    'last_pull_at': null,
    'last_push_at': null,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  });
}
