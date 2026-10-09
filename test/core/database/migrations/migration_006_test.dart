import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finora/core/database/migrations/migration_006.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('assigns only records with unambiguous existing ownership', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('CREATE TABLE users (id TEXT PRIMARY KEY)');
    await db.execute(
      'CREATE TABLE accounts (id INTEGER PRIMARY KEY, user_id TEXT)',
    );
    await db.execute(
      'CREATE TABLE categories (id INTEGER PRIMARY KEY, user_id TEXT)',
    );
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY,
        account_id INTEGER NOT NULL,
        category_id INTEGER NOT NULL,
        user_id TEXT,
        date TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE transfers (
        id INTEGER PRIMARY KEY,
        source_account_id INTEGER NOT NULL,
        destination_account_id INTEGER NOT NULL,
        user_id TEXT,
        date TEXT NOT NULL
      )
    ''');

    await db.insert('users', {'id': 'user-a'});
    await db.insert('users', {'id': 'user-b'});
    await db.insert('accounts', {'id': 1, 'user_id': 'user-a'});
    await db.insert('accounts', {'id': 2, 'user_id': 'user-b'});
    await db.insert('accounts', {'id': 3, 'user_id': null});
    await db.insert('accounts', {'id': 4, 'user_id': 'user-a'});
    await db.insert('categories', {'id': 1, 'user_id': null});
    await db.insert('categories', {'id': 2, 'user_id': 'user-b'});

    await db.insert('transactions', {
      'id': 1,
      'account_id': 1,
      'category_id': 1,
      'user_id': null,
      'date': '2026-01-01',
    });
    await db.insert('transactions', {
      'id': 2,
      'account_id': 1,
      'category_id': 2,
      'user_id': null,
      'date': '2026-01-02',
    });
    await db.insert('transactions', {
      'id': 3,
      'account_id': 3,
      'category_id': 1,
      'user_id': null,
      'date': '2026-01-03',
    });
    await db.insert('transfers', {
      'id': 1,
      'source_account_id': 1,
      'destination_account_id': 4,
      'user_id': null,
      'date': '2026-01-01',
    });
    await db.insert('transfers', {
      'id': 2,
      'source_account_id': 1,
      'destination_account_id': 2,
      'user_id': null,
      'date': '2026-01-02',
    });
    await db.insert('transfers', {
      'id': 3,
      'source_account_id': 3,
      'destination_account_id': 4,
      'user_id': null,
      'date': '2026-01-03',
    });

    await applyMigration006(db);

    final transactions = await db.query('transactions', orderBy: 'id');
    expect(transactions[0]['user_id'], 'user-a');
    expect(transactions[1]['user_id'], isNull);
    expect(transactions[2]['user_id'], isNull);

    final transfers = await db.query('transfers', orderBy: 'id');
    expect(transfers[0]['user_id'], 'user-a');
    expect(transfers[1]['user_id'], isNull);
    expect(transfers[2]['user_id'], isNull);

    final accounts = await db.query('accounts', orderBy: 'id');
    expect(accounts[2]['user_id'], isNull);

    final status = (await db.query('legacy_data_migration')).single;
    expect(status['status'], 'pending_review');
    expect(status['unassigned_accounts'], 1);
    expect(status['unassigned_transactions'], 2);
    expect(status['unassigned_transfers'], 2);

    // Running the migration again must not duplicate tracking rows or change
    // the ownership decision for ambiguous records.
    await applyMigration006(db);
    expect(await db.query('legacy_data_migration'), hasLength(1));
    expect((await db.query('accounts', where: 'id = ?', whereArgs: [3])).single['user_id'], isNull);
    expect((await db.query('transactions', where: 'id = ?', whereArgs: [2])).single['user_id'], isNull);
  });
}
