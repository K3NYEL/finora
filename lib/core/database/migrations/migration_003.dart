import 'package:sqflite/sqflite.dart';

Future<void> applyMigration003(Database database) async {
  await database.execute(
    'ALTER TABLE accounts ADD COLUMN initial_balance_minor INTEGER',
  );
  await database.execute(
    'ALTER TABLE transactions ADD COLUMN amount_minor INTEGER',
  );
  await database.execute(
    'ALTER TABLE transfers ADD COLUMN amount_minor INTEGER',
  );

  await database.execute(
    'UPDATE accounts SET initial_balance_minor = '
    'CAST(ROUND(initial_balance * 100) AS INTEGER) '
    'WHERE initial_balance_minor IS NULL',
  );
  await database.execute(
    'UPDATE transactions SET amount_minor = '
    'CAST(ROUND(amount * 100) AS INTEGER) '
    'WHERE amount_minor IS NULL',
  );
  await database.execute(
    'UPDATE transfers SET amount_minor = '
    'CAST(ROUND(amount * 100) AS INTEGER) '
    'WHERE amount_minor IS NULL',
  );
}
