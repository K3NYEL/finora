import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finora/core/database/migrations/migration_007.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('adds stable UUIDs without changing local IDs or enabling sync', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('CREATE TABLE accounts (id INTEGER PRIMARY KEY, user_id TEXT)');
    await db.execute('CREATE TABLE categories (id INTEGER PRIMARY KEY, user_id TEXT)');
    await db.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY, user_id TEXT)');
    await db.execute('CREATE TABLE transfers (id INTEGER PRIMARY KEY, user_id TEXT)');

    await db.insert('accounts', {'id': 10, 'user_id': 'user-a'});
    await db.insert('accounts', {'id': 11, 'user_id': null});
    await db.insert('categories', {'id': 20, 'user_id': 'user-a'});
    await db.insert('categories', {'id': 21, 'user_id': null});
    await db.insert('transactions', {'id': 30, 'user_id': 'user-a'});
    await db.insert('transfers', {'id': 40, 'user_id': 'user-a'});

    await applyMigration007(db);

    final account = (await db.query('accounts', where: 'id = ?', whereArgs: [10])).single;
    final unassignedAccount = (await db.query('accounts', where: 'id = ?', whereArgs: [11])).single;
    final ownedCategory = (await db.query('categories', where: 'id = ?', whereArgs: [20])).single;
    final globalCategory = (await db.query('categories', where: 'id = ?', whereArgs: [21])).single;

    expect(account['id'], 10);
    expect(account['sync_id'], matches(RegExp(r'^[0-9a-f-]{36}$', caseSensitive: false)));
    expect(unassignedAccount['id'], 11);
    expect(unassignedAccount['sync_id'], isNotNull);
    expect(account['sync_status'], 'local_only');
    expect(account['remote_sync_version'], isNull);
    expect(ownedCategory['sync_id'], isNotNull);
    expect(globalCategory['sync_id'], isNull);

    for (final table in ['transactions', 'transfers']) {
      final row = (await db.query(table)).single;
      expect(row['sync_id'], isNotNull);
      expect(row['sync_status'], 'local_only');
    }

    final state = (await db.query('sync_state')).single;
    expect(state['id'], 1);
    expect(state['cursor'], 0);
    expect(state['enabled'], 0);
    expect(state['local_user_id'], isNull);
    expect(state['remote_user_id'], isNull);
  });

  test('creates unique indexes and can persist a stable sync identity', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('CREATE TABLE accounts (id INTEGER PRIMARY KEY, user_id TEXT)');
    await db.execute('CREATE TABLE categories (id INTEGER PRIMARY KEY, user_id TEXT)');
    await db.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY, user_id TEXT)');
    await db.execute('CREATE TABLE transfers (id INTEGER PRIMARY KEY, user_id TEXT)');
    await db.insert('accounts', {'id': 1, 'user_id': 'user-a'});
    await applyMigration007(db);

    final before = (await db.query('accounts')).single['sync_id'];
    await db.update('accounts', {'user_id': 'user-a'}, where: 'id = ?', whereArgs: [1]);
    final after = (await db.query('accounts')).single['sync_id'];
    expect(after, before);

    await expectLater(
      db.insert('accounts', {'id': 2, 'user_id': 'user-a', 'sync_id': before}),
      throwsA(isA<Exception>()),
    );
  });
}
