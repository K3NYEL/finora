import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finora/core/database/migrations/legacy_data_migration_service.dart';
import 'package:finora/core/errors/app_exception.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  Future<Database> createDatabase() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
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
    await db.execute('''
      CREATE TABLE legacy_data_migration(
        id INTEGER PRIMARY KEY,
        status TEXT NOT NULL,
        unassigned_accounts INTEGER NOT NULL,
        unassigned_transactions INTEGER NOT NULL,
        unassigned_transfers INTEGER NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.insert('users', {'id': 'user-a'});
    await db.insert('users', {'id': 'user-b'});
    await db.insert('accounts', {'id': 1, 'user_id': null});
    await db.insert('accounts', {'id': 2, 'user_id': null});
    await db.insert('accounts', {'id': 3, 'user_id': 'user-b'});
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
      'account_id': 2,
      'category_id': 2,
      'user_id': null,
      'date': '2026-01-02',
    });
    await db.insert('transfers', {
      'id': 1,
      'source_account_id': 1,
      'destination_account_id': 2,
      'user_id': null,
      'date': '2026-01-01',
    });
    await db.insert('transfers', {
      'id': 2,
      'source_account_id': 1,
      'destination_account_id': 3,
      'user_id': null,
      'date': '2026-01-02',
    });
    return db;
  }

  test('rejects missing confirmation without changing ownership', () async {
    final db = await createDatabase();
    addTearDown(db.close);
    final service = LegacyDataMigrationService(db);

    await expectLater(
      service.adoptLegacyData(
        userId: 'user-a',
        confirmation: 'sí',
      ),
      throwsA(isA<AppException>()),
    );

    final accounts = await db.query('accounts', orderBy: 'id');
    expect(accounts[0]['user_id'], isNull);
    expect(accounts[1]['user_id'], isNull);
  });

  test('adopts legacy records atomically and preserves conflicts', () async {
    final db = await createDatabase();
    addTearDown(db.close);
    final service = LegacyDataMigrationService(db);

    await service.adoptLegacyData(
      userId: 'user-a',
      confirmation: LegacyDataMigrationService.confirmationPhrase,
    );

    final accounts = await db.query('accounts', orderBy: 'id');
    expect(accounts[0]['user_id'], 'user-a');
    expect(accounts[1]['user_id'], 'user-a');
    expect(accounts[2]['user_id'], 'user-b');

    final transactions = await db.query('transactions', orderBy: 'id');
    expect(transactions[0]['user_id'], 'user-a');
    // A category belonging to another user is a conflict; do not reassign it.
    expect(transactions[1]['user_id'], isNull);

    final transfers = await db.query('transfers', orderBy: 'id');
    expect(transfers[0]['user_id'], 'user-a');
    // Never attach a transfer that points to another user's account.
    expect(transfers[1]['user_id'], isNull);

    final status = (await service.getStatus());
    expect(status['status'], 'pending_review');
    expect(status['unassigned_accounts'], 0);
    expect(status['unassigned_transactions'], 1);
    expect(status['unassigned_transfers'], 1);

    // A second confirmed run is idempotent.
    await service.adoptLegacyData(
      userId: 'user-a',
      confirmation: LegacyDataMigrationService.confirmationPhrase,
    );
    expect(await db.query('accounts'), hasLength(3));
  });

  test('rejects a user id that does not exist', () async {
    final db = await createDatabase();
    addTearDown(db.close);
    final service = LegacyDataMigrationService(db);

    await expectLater(
      service.adoptLegacyData(
        userId: 'missing-user',
        confirmation: LegacyDataMigrationService.confirmationPhrase,
      ),
      throwsA(isA<AppException>()),
    );

    expect(
      (await db.query('accounts', where: 'user_id IS NULL')).length,
      2,
    );
  });
}
