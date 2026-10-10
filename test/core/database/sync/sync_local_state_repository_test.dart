import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finora/core/database/migrations/migration_007.dart';
import 'package:finora/core/database/sync/sync_local_state_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  Future<Database> openFixture() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE accounts (id INTEGER PRIMARY KEY, user_id TEXT)');
    await db.execute('CREATE TABLE categories (id INTEGER PRIMARY KEY, user_id TEXT)');
    await db.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY, user_id TEXT, category_id INTEGER)');
    await db.execute('CREATE TABLE transfers (id INTEGER PRIMARY KEY, user_id TEXT)');
    await db.insert('accounts', {'id': 1, 'user_id': 'local-a'});
    await db.insert('categories', {'id': 1, 'user_id': 'local-a'});
    await db.insert('categories', {'id': 2, 'user_id': null});
    await applyMigration007(db);
    return db;
  }

  test('readiness gate blocks sync until explicit local and remote linking', () async {
    final db = await openFixture();
    addTearDown(db.close);
    final repository = SyncLocalStateRepository(db);

    final initial = await repository.inspectForUser('local-a');
    expect(initial.ready, isFalse);
    expect(initial.blockers, contains('sync_disabled'));
    expect(initial.blockers, contains('local_account_not_linked'));
    expect(initial.blockers, contains('remote_account_not_linked'));

    await db.update('sync_state', {
      'enabled': 1,
      'local_user_id': 'local-a',
      'remote_user_id': 'remote-uuid-a',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'id = 1');

    final linked = await repository.inspectForUser('local-a');
    expect(linked.ready, isTrue);
    expect(linked.blockers, isEmpty);
  });

  test('readiness gate blocks unresolved legacy ownership and shared-category mapping', () async {
    final db = await openFixture();
    addTearDown(db.close);
    await db.insert('accounts', {'id': 2, 'user_id': null});
    await db.insert('transactions', {
      'id': 1,
      'user_id': 'local-a',
      'category_id': 2,
    });
    await db.update('sync_state', {
      'enabled': 1,
      'local_user_id': 'local-a',
      'remote_user_id': 'remote-uuid-a',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'id = 1');

    final result = await SyncLocalStateRepository(db).inspectForUser('local-a');
    expect(result.ready, isFalse);
    expect(result.blockers, contains('legacy_ownership_unresolved'));
    expect(result.blockers, contains('shared_category_mapping_required'));
  });
}
