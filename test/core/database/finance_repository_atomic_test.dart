import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finora/core/database/database.dart';
import 'package:finora/features/finance/data/finance_repository.dart';

void main() {
  late Directory temporaryDirectory;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temporaryDirectory =
        await Directory.systemTemp.createTemp('finora-finance-atomic-');
    await databaseFactory.setDatabasesPath(temporaryDirectory.path);
  });

  tearDownAll(() async {
    await AppDatabase.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('concurrent expenses cannot spend the same balance twice', () async {
    final db = await AppDatabase.instance;
    const userId = 'atomic-finance-user';
    await db.insert('users', {
      'id': userId,
      'first_name': 'Atomic',
      'last_name': 'Test',
      'password_hash': 'test-only-hash',
      'created_at': '2026-01-01T00:00:00.000Z',
    });

    final repository = FinanceRepository(userId: userId);
    await repository.addAccount('Cuenta de prueba', 'cash', 100);
    final accounts = await db.query(
      'accounts',
      columns: ['id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    final accountId = accounts.single['id'] as int;
    final categories = await repository.categories('expense');
    expect(categories, isNotEmpty);
    final categoryId = categories.first.id;

    final results = await Future.wait([
      _tryExpense(repository, accountId, categoryId),
      _tryExpense(repository, accountId, categoryId),
    ]);

    expect(results.where((success) => success), hasLength(1));
    final refreshedAccounts = await repository.accounts();
    expect(refreshedAccounts.single.balance, 20);

    final movements = await db.query(
      'transactions',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    expect(movements, hasLength(1));
    expect(movements.single['amount_minor'], 8000);
  });
}

Future<bool> _tryExpense(
  FinanceRepository repository,
  int accountId,
  int categoryId,
) async {
  try {
    await repository.addTransaction(
      accountId: accountId,
      categoryId: categoryId,
      type: 'expense',
      amount: 80,
      description: 'Prueba concurrente',
    );
    return true;
  } catch (_) {
    return false;
  }
}
