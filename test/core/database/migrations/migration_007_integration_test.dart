import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finora/core/database/migrations/migration_002.dart';
import 'package:finora/core/database/migrations/migration_003.dart';
import 'package:finora/core/database/migrations/migration_004.dart';
import 'package:finora/core/database/migrations/migration_005.dart';
import 'package:finora/core/database/migrations/migration_006.dart';
import 'package:finora/core/database/migrations/migration_007.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  Future<Database> openLegacyDatabaseThroughVersion6() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        initial_balance REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        is_archived INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL REFERENCES accounts(id),
        category_id INTEGER NOT NULL REFERENCES categories(id),
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT,
        date TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE transfers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_account_id INTEGER NOT NULL REFERENCES accounts(id),
        destination_account_id INTEGER NOT NULL REFERENCES accounts(id),
        amount REAL NOT NULL,
        description TEXT,
        date TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.insert('categories', {
      'id': 1,
      'name': 'Alimentación',
      'type': 'expense',
      'is_default': 1,
    });
    await db.insert('categories', {
      'id': 2,
      'name': 'Categoría personal',
      'type': 'expense',
      'is_default': 0,
    });

    await applyMigration002(db);
    await applyMigration003(db);
    await applyMigration004(db);
    await applyMigration005(db);

    await db.insert('accounts', {
      'id': 10,
      'name': 'Cuenta asignada',
      'type': 'checking',
      'initial_balance': 125.50,
      'created_at': '2026-01-01T00:00:00.000Z',
      'user_id': 'local-a',
    });
    await db.insert('accounts', {
      'id': 11,
      'name': 'Cuenta sin propietario',
      'type': 'cash',
      'initial_balance': 0,
      'created_at': '2026-01-02T00:00:00.000Z',
      'user_id': null,
    });
    await db.insert('accounts', {
      'id': 12,
      'name': 'Cuenta destino',
      'type': 'savings',
      'initial_balance': 20,
      'created_at': '2026-01-03T00:00:00.000Z',
      'user_id': 'local-a',
    });
    await db.insert('categories', {
      'id': 3,
      'name': 'Categoría asignada',
      'type': 'expense',
      'is_default': 0,
      'user_id': 'local-a',
    });

    await db.insert('transactions', {
      'id': 20,
      'account_id': 10,
      'category_id': 1,
      'type': 'expense',
      'amount': 12.34,
      'description': 'Transacción histórica con categoría global',
      'date': '2026-01-04',
      'created_at': '2026-01-04T12:00:00.000Z',
      'user_id': null,
    });
    await db.insert('transactions', {
      'id': 21,
      'account_id': 10,
      'category_id': 3,
      'type': 'expense',
      'amount': 5,
      'description': 'Transacción con categoría del usuario',
      'date': '2026-01-05',
      'created_at': '2026-01-05T12:00:00.000Z',
      'user_id': 'local-a',
    });
    await db.insert('transactions', {
      'id': 22,
      'account_id': 11,
      'category_id': 1,
      'type': 'expense',
      'amount': 3,
      'description': 'Propietario ambiguo',
      'date': '2026-01-06',
      'created_at': '2026-01-06T12:00:00.000Z',
      'user_id': null,
    });
    await db.insert('transfers', {
      'id': 30,
      'source_account_id': 10,
      'destination_account_id': 12,
      'amount': 8.75,
      'description': 'Transferencia histórica',
      'date': '2026-01-07',
      'created_at': '2026-01-07T12:00:00.000Z',
      'user_id': null,
    });

    await applyMigration006(db);
    return db;
  }

  test('upgrades a version-6 schema without losing data or guessing ownership', () async {
    final db = await openLegacyDatabaseThroughVersion6();
    addTearDown(db.close);

    final beforeAccountIds = (await db.query('accounts', columns: ['id']))
        .map((row) => row['id'])
        .toList();
    final beforeTransactionIds = (await db.query('transactions', columns: ['id']))
        .map((row) => row['id'])
        .toList();
    final beforeTransferIds = (await db.query('transfers', columns: ['id']))
        .map((row) => row['id'])
        .toList();

    await applyMigration007(db);

    expect(
      (await db.query('accounts', columns: ['id'])).map((row) => row['id']).toList(),
      beforeAccountIds,
    );
    expect(
      (await db.query('transactions', columns: ['id']))
          .map((row) => row['id'])
          .toList(),
      beforeTransactionIds,
    );
    expect(
      (await db.query('transfers', columns: ['id']))
          .map((row) => row['id'])
          .toList(),
      beforeTransferIds,
    );

    final ownedAccount = (await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [10],
    )).single;
    expect(ownedAccount['initial_balance_minor'], 12550);
    expect(ownedAccount['sync_id'], isA<String>());
    expect(ownedAccount['sync_status'], 'local_only');

    final inferredTransaction = (await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [20],
    )).single;
    expect(inferredTransaction['user_id'], 'local-a');
    expect(inferredTransaction['amount_minor'], 1234);
    expect(inferredTransaction['sync_id'], isA<String>());

    final explicitTransaction = (await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [21],
    )).single;
    expect(explicitTransaction['user_id'], 'local-a');
    expect(explicitTransaction['sync_id'], isA<String>());

    final ambiguousTransaction = (await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [22],
    )).single;
    expect(ambiguousTransaction['user_id'], isNull);
    expect(ambiguousTransaction['sync_id'], isA<String>());

    final inferredTransfer = (await db.query(
      'transfers',
      where: 'id = ?',
      whereArgs: [30],
    )).single;
    expect(inferredTransfer['user_id'], 'local-a');
    expect(inferredTransfer['amount_minor'], 875);
    expect(inferredTransfer['sync_id'], isA<String>());

    final globalCategory = (await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [1],
    )).single;
    expect(globalCategory['user_id'], isNull);
    expect(globalCategory['sync_id'], isNull);

    final migrationStatus = (await db.query('legacy_data_migration')).single;
    expect(migrationStatus['status'], 'pending_review');
    expect(migrationStatus['unassigned_accounts'], 1);
    expect(migrationStatus['unassigned_transactions'], 1);

    final syncState = (await db.query('sync_state')).single;
    expect(syncState['enabled'], 0);
    expect(syncState['cursor'], 0);
    expect(syncState['local_user_id'], isNull);
    expect(syncState['remote_user_id'], isNull);
  });

  test('creates independent unique sync identities for all eligible rows', () async {
    final db = await openLegacyDatabaseThroughVersion6();
    addTearDown(db.close);

    await applyMigration007(db);

    for (final table in ['accounts', 'transactions', 'transfers']) {
      final rows = await db.query(table, columns: ['id', 'sync_id', 'sync_status']);
      expect(rows, isNotEmpty);
      expect(rows.every((row) => row['sync_id'] is String), isTrue);
      expect(rows.every((row) => row['sync_status'] == 'local_only'), isTrue);
      expect(rows.map((row) => row['sync_id']).toSet(), hasLength(rows.length));
    }

    final ownedCategories = await db.query(
      'categories',
      where: 'user_id IS NOT NULL',
      columns: ['sync_id'],
    );
    expect(ownedCategories.every((row) => row['sync_id'] is String), isTrue);
    final sharedCategories = await db.query(
      'categories',
      where: 'user_id IS NULL',
      columns: ['sync_id'],
    );
    expect(sharedCategories.every((row) => row['sync_id'] == null), isTrue);
  });
}
