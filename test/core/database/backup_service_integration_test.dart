import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finora/core/database/backup_service.dart';
import 'package:finora/core/database/database.dart';
import 'package:finora/core/errors/app_exception.dart';

void main() {
  late Directory temporaryDirectory;
  const service = BackupService();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temporaryDirectory =
        await Directory.systemTemp.createTemp('finora-backup-integration-');
    await databaseFactory.setDatabasesPath(temporaryDirectory.path);
  });

  tearDownAll(() async {
    await AppDatabase.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('backup restores accounts, transactions and transfers for another user',
      () async {
    final db = await AppDatabase.instance;
    const sourceUser = 'backup-source-user';
    const destinationUser = 'backup-destination-user';

    for (final userId in [sourceUser, destinationUser]) {
      await db.insert('users', {
        'id': userId,
        'first_name': 'Test',
        'last_name': 'User',
        'password_hash': 'not-exported-test-hash',
        'created_at': '2026-01-01T00:00:00.000Z',
      });
    }

    final sourceAccount = await db.insert('accounts', {
      'user_id': sourceUser,
      'name': 'Cuenta principal',
      'type': 'cash',
      'initial_balance': 500.00,
      'initial_balance_minor': 50000,
      'created_at': '2026-01-01T00:00:00.000Z',
      'is_archived': 0,
    });
    final destinationAccount = await db.insert('accounts', {
      'user_id': sourceUser,
      'name': 'Ahorros',
      'type': 'savings',
      'initial_balance': 25.00,
      'initial_balance_minor': 2500,
      'created_at': '2026-01-01T00:00:00.000Z',
      'is_archived': 0,
    });
    final categories = await db.query(
      'categories',
      columns: ['id'],
      where: "name = ? AND type = 'income' AND user_id IS NULL",
      whereArgs: ['Salario'],
      limit: 1,
    );
    expect(categories, isNotEmpty);
    final categoryId = categories.first['id'] as int;

    await db.insert('transactions', {
      'user_id': sourceUser,
      'account_id': sourceAccount,
      'category_id': categoryId,
      'type': 'income',
      'amount': 100.00,
      'amount_minor': 10000,
      'description': 'Nómina de prueba',
      'date': '2026-01-02T12:00:00.000Z',
      'created_at': '2026-01-02T12:00:00.000Z',
    });
    await db.insert('transfers', {
      'user_id': sourceUser,
      'source_account_id': sourceAccount,
      'destination_account_id': destinationAccount,
      'amount': 25.00,
      'amount_minor': 2500,
      'description': 'Ahorro de prueba',
      'date': '2026-01-03T12:00:00.000Z',
      'created_at': '2026-01-03T12:00:00.000Z',
    });

    final backup = await service.createBackup(sourceUser);
    expect(backup, contains('finora-backup'));
    expect(backup, isNot(contains('not-exported-test-hash')));

    final restored = await service.restoreBackup(
      userId: destinationUser,
      jsonText: backup,
    );
    expect(restored, {
      'accounts': 2,
      'transactions': 1,
      'transfers': 1,
      'categories': 1,
    });

    final restoredAccounts = await db.query(
      'accounts',
      where: 'user_id = ?',
      whereArgs: [destinationUser],
    );
    expect(restoredAccounts, hasLength(2));
    expect(restoredAccounts.map((row) => row['id']).toSet().length, 2);
    expect(restoredAccounts.map((row) => row['name']).toSet(),
        {'Cuenta principal', 'Ahorros'});

    final restoredTransactions = await db.query(
      'transactions',
      where: 'user_id = ?',
      whereArgs: [destinationUser],
    );
    expect(restoredTransactions, hasLength(1));
    expect(restoredTransactions.single['amount_minor'], 10000);
    expect(
      restoredTransactions.single['account_id'],
      isNot(sourceAccount),
    );
    expect(restoredTransactions.single['category_id'], categoryId);

    final restoredTransfers = await db.query(
      'transfers',
      where: 'user_id = ?',
      whereArgs: [destinationUser],
    );
    expect(restoredTransfers, hasLength(1));
    expect(restoredTransfers.single['amount_minor'], 2500);
    expect(
      restoredTransfers.single['source_account_id'],
      isNot(sourceAccount),
    );
    expect(
      restoredTransfers.single['destination_account_id'],
      isNot(destinationAccount),
    );

    await expectLater(
      service.restoreBackup(userId: destinationUser, jsonText: backup),
      throwsA(isA<AppException>()),
    );

    // Importing into the destination must not alter the original owner's data.
    expect(
      Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM accounts WHERE user_id = ?',
        [sourceUser],
      )),
      2,
    );
    expect(
      Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM transactions WHERE user_id = ?',
        [sourceUser],
      )),
      1,
    );
    expect(
      Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM transfers WHERE user_id = ?',
        [sourceUser],
      )),
      1,
    );
  });
}
