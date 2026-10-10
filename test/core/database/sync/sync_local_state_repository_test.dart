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
    await db.execute('CREATE TABLE accounts (id INTEGER PRIMARY KEY, user_id TEXT, initial_balance_minor INTEGER)');
    await db.execute('CREATE TABLE categories (id INTEGER PRIMARY KEY, user_id TEXT)');
    await db.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY, user_id TEXT, account_id INTEGER, category_id INTEGER, amount_minor INTEGER)');
    await db.execute('CREATE TABLE transfers (id INTEGER PRIMARY KEY, user_id TEXT, source_account_id INTEGER, destination_account_id INTEGER, amount_minor INTEGER)');
    await db.insert('accounts', {'id': 1, 'user_id': 'local-a', 'initial_balance_minor': 10000});
    await db.insert('accounts', {'id': 2, 'user_id': 'local-b', 'initial_balance_minor': 5000});
    await db.insert('categories', {'id': 1, 'user_id': 'local-a'});
    await db.insert('categories', {'id': 2, 'user_id': null});
    await applyMigration007(db);
    return db;
  }

  Future<void> linkSync(Database db) async {
    await db.update('sync_state', {
      'enabled': 1,
      'local_user_id': 'local-a',
      'remote_user_id': 'remote-uuid-a',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'id = 1');
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

    await linkSync(db);
    final linked = await repository.inspectForUser('local-a');
    expect(linked.ready, isTrue);
    expect(linked.blockers, isEmpty);
  });

  test('readiness gate blocks unresolved legacy ownership and shared-category mapping', () async {
    final db = await openFixture();
    addTearDown(db.close);
    await db.insert('accounts', {'id': 3, 'user_id': null});
    await db.insert('transactions', {
      'id': 1,
      'user_id': 'local-a',
      'account_id': 1,
      'category_id': 2,
      'amount_minor': 250,
    });
    await linkSync(db);

    final result = await SyncLocalStateRepository(db).inspectForUser('local-a');
    expect(result.ready, isFalse);
    expect(result.blockers, contains('legacy_ownership_unresolved'));
    expect(result.blockers, contains('shared_category_mapping_required'));
  });

  test('readiness gate blocks transactions and transfers crossing owner boundaries', () async {
    final db = await openFixture();
    addTearDown(db.close);
    await db.insert('categories', {'id': 3, 'user_id': 'local-b'});
    await db.insert('transactions', {
      'id': 10,
      'user_id': 'local-a',
      'account_id': 2,
      'category_id': 1,
      'amount_minor': 100,
    });
    await db.insert('transactions', {
      'id': 11,
      'user_id': 'local-a',
      'account_id': 1,
      'category_id': 3,
      'amount_minor': 200,
    });
    await db.insert('transfers', {
      'id': 20,
      'user_id': 'local-a',
      'source_account_id': 1,
      'destination_account_id': 2,
      'amount_minor': 500,
    });
    await linkSync(db);

    final result = await SyncLocalStateRepository(db).inspectForUser('local-a');
    expect(result.ready, isFalse);
    expect(result.blockers, contains('transaction_relationship_owner_mismatch'));
    expect(result.blockers, contains('transfer_relationship_owner_mismatch'));
  });
  test('readiness gate blocks financial records with invalid minor-unit amounts', () async {
    final db = await openFixture();
    addTearDown(db.close);
    await db.insert('transactions', {
      'id': 30,
      'user_id': 'local-a',
      'account_id': 1,
      'category_id': 1,
      'amount_minor': null,
    });
    await linkSync(db);

    final result = await SyncLocalStateRepository(db).inspectForUser('local-a');
    expect(result.ready, isFalse);
    expect(result.blockers, contains('financial_amount_integrity_failed'));
  });

}
