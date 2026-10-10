import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finora/core/database/migrations/migration_003.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('preserves legacy rows and converts money to integer minor units', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY,
        initial_balance REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY,
        amount REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE transfers (
        id INTEGER PRIMARY KEY,
        amount REAL NOT NULL
      )
    ''');

    await db.insert('accounts', {'id': 7, 'initial_balance': 123.45});
    await db.insert('accounts', {'id': 8, 'initial_balance': 0.1});
    await db.insert('transactions', {'id': 21, 'amount': 19.99});
    await db.insert('transactions', {'id': 22, 'amount': 0.1});
    await db.insert('transfers', {'id': 31, 'amount': 25.5});

    await applyMigration003(db);

    final accounts = await db.query('accounts', orderBy: 'id');
    expect(accounts, hasLength(2));
    expect(accounts[0]['id'], 7);
    expect(accounts[0]['initial_balance'], 123.45);
    expect(accounts[0]['initial_balance_minor'], 12345);
    expect(accounts[1]['id'], 8);
    expect(accounts[1]['initial_balance_minor'], 10);

    final transactions = await db.query('transactions', orderBy: 'id');
    expect(transactions, hasLength(2));
    expect(transactions[0]['id'], 21);
    expect(transactions[0]['amount'], 19.99);
    expect(transactions[0]['amount_minor'], 1999);
    expect(transactions[1]['id'], 22);
    expect(transactions[1]['amount_minor'], 10);

    final transfers = await db.query('transfers');
    expect(transfers, hasLength(1));
    expect(transfers.single['id'], 31);
    expect(transfers.single['amount'], 25.5);
    expect(transfers.single['amount_minor'], 2550);
  });
}
