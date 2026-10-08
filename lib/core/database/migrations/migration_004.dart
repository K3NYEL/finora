import 'package:sqflite/sqflite.dart';

Future<void> applyMigration004(Database database) async {
  await database.execute('''
    CREATE TABLE IF NOT EXISTS users(
      id TEXT PRIMARY KEY,
      first_name TEXT NOT NULL,
      last_name TEXT NOT NULL,
      password_hash TEXT NOT NULL,
      created_at TEXT NOT NULL,
      last_login TEXT
    )
  ''');

  await database.execute(
    'ALTER TABLE accounts ADD COLUMN user_id TEXT',
  );

  await database.execute(
    'ALTER TABLE transactions ADD COLUMN user_id TEXT',
  );

  await database.execute(
    'ALTER TABLE transfers ADD COLUMN user_id TEXT',
  );

  await database.execute(
    'ALTER TABLE categories ADD COLUMN user_id TEXT',
  );

  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_accounts_user_id '
    'ON accounts(user_id)',
  );

  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_transactions_user_id '
    'ON transactions(user_id)',
  );

  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_transfers_user_id '
    'ON transfers(user_id)',
  );

  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_categories_user_id '
    'ON categories(user_id)',
  );
}
