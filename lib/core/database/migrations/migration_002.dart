import 'package:sqflite/sqflite.dart';

Future<void> applyMigration002(Database database) async {
  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_transactions_account_id '
    'ON transactions(account_id)',
  );
  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_transactions_category_date '
    'ON transactions(category_id, date)',
  );
  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_transactions_date '
    'ON transactions(date)',
  );
  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_transfers_source_date '
    'ON transfers(source_account_id, date)',
  );
  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_transfers_destination_date '
    'ON transfers(destination_account_id, date)',
  );
}
