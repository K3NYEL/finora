import 'package:sqflite/sqflite.dart';

/// Tracks legacy financial records that still need an explicit owner.
///
/// Records are never assigned to a user merely because that user is the first
/// person to sign in. Ownership is inferred only from an already-owned account
/// (and, for transactions, a compatible category owner).
Future<void> applyMigration006(Database database) async {
  await database.execute('''
    CREATE TABLE IF NOT EXISTS legacy_data_migration(
      id INTEGER PRIMARY KEY CHECK (id = 1),
      status TEXT NOT NULL CHECK (
        status IN ('complete', 'pending_review')
      ),
      unassigned_accounts INTEGER NOT NULL DEFAULT 0,
      unassigned_transactions INTEGER NOT NULL DEFAULT 0,
      unassigned_transfers INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    )
  ''');

  // A transaction can inherit ownership from its account only when the
  // category is global or belongs to the same user.
  await database.execute('''
    UPDATE transactions
    SET user_id = (
      SELECT a.user_id
      FROM accounts a
      JOIN categories c ON c.id = transactions.category_id
      WHERE a.id = transactions.account_id
        AND a.user_id IS NOT NULL
        AND (c.user_id IS NULL OR c.user_id = a.user_id)
    )
    WHERE user_id IS NULL
      AND EXISTS (
        SELECT 1
        FROM accounts a
        JOIN categories c ON c.id = transactions.category_id
        WHERE a.id = transactions.account_id
          AND a.user_id IS NOT NULL
          AND (c.user_id IS NULL OR c.user_id = a.user_id)
      )
  ''');

  // A transfer can inherit ownership only if both accounts have the same
  // established owner. Ambiguous transfers remain untouched for review.
  await database.execute('''
    UPDATE transfers
    SET user_id = (
      SELECT s.user_id
      FROM accounts s
      JOIN accounts d ON d.id = transfers.destination_account_id
      WHERE s.id = transfers.source_account_id
        AND s.user_id IS NOT NULL
        AND d.user_id = s.user_id
    )
    WHERE user_id IS NULL
      AND EXISTS (
        SELECT 1
        FROM accounts s
        JOIN accounts d ON d.id = transfers.destination_account_id
        WHERE s.id = transfers.source_account_id
          AND s.user_id IS NOT NULL
          AND d.user_id = s.user_id
      )
  ''');

  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_transactions_user_date '
    'ON transactions(user_id, date)',
  );
  await database.execute(
    'CREATE INDEX IF NOT EXISTS idx_transfers_user_date '
    'ON transfers(user_id, date)',
  );

  final accountCount = Sqflite.firstIntValue(await database.rawQuery(
        'SELECT COUNT(*) FROM accounts WHERE user_id IS NULL',
      )) ??
      0;
  final transactionCount = Sqflite.firstIntValue(await database.rawQuery(
        'SELECT COUNT(*) FROM transactions WHERE user_id IS NULL',
      )) ??
      0;
  final transferCount = Sqflite.firstIntValue(await database.rawQuery(
        'SELECT COUNT(*) FROM transfers WHERE user_id IS NULL',
      )) ??
      0;

  final hasUnassignedRecords =
      accountCount > 0 || transactionCount > 0 || transferCount > 0;

  await database.insert(
    'legacy_data_migration',
    {
      'id': 1,
      'status': hasUnassignedRecords ? 'pending_review' : 'complete',
      'unassigned_accounts': accountCount,
      'unassigned_transactions': transactionCount,
      'unassigned_transfers': transferCount,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
