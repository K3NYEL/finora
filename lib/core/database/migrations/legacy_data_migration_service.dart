import 'package:sqflite/sqflite.dart';

import '../../errors/app_exception.dart';

/// Provides an explicit, user-confirmed path for adopting legacy local data.
///
/// This must only be called after the UI has shown the pending-record counts
/// and the user has deliberately entered the confirmation phrase.
class LegacyDataMigrationService {
  LegacyDataMigrationService(this.database);

  final Database database;

  static const confirmationPhrase = 'RECUPERAR MIS DATOS ANTIGUOS';

  Future<Map<String, Object?>> getStatus() async {
    final rows = await database.query(
      'legacy_data_migration',
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.single;

    return {
      'id': 1,
      'status': 'complete',
      'unassigned_accounts': 0,
      'unassigned_transactions': 0,
      'unassigned_transfers': 0,
    };
  }

  /// Assigns legacy financial records to [userId] only after explicit
  /// confirmation. The operation is atomic and safe to retry.
  ///
  /// This deliberately adopts every still-unassigned legacy account in this
  /// local database. The caller must warn users not to do this on a shared
  /// device if the old records may belong to another person.
  Future<void> adoptLegacyData({
    required String userId,
    required String confirmation,
  }) async {
    if (userId.trim().isEmpty) {
      throw const AppException('No se pudo identificar la cuenta actual.');
    }
    if (confirmation != confirmationPhrase) {
      throw const AppException(
        'La confirmación no coincide. No se modificaron los datos.',
      );
    }

    await database.transaction((txn) async {
      final users = await txn.query(
        'users',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      if (users.isEmpty) {
        throw const AppException('La cuenta actual no existe.');
      }

      // Accounts are claimed only after explicit confirmation. Their
      // associated records are assigned below only when their references
      // agree with the same owner.
      await txn.update(
        'accounts',
        {'user_id': userId},
        where: 'user_id IS NULL',
      );

      await txn.rawUpdate('''
        UPDATE transactions
        SET user_id = ?
        WHERE user_id IS NULL
          AND EXISTS (
            SELECT 1 FROM accounts a
            JOIN categories c ON c.id = transactions.category_id
            WHERE a.id = transactions.account_id
              AND a.user_id = ?
              AND (c.user_id IS NULL OR c.user_id = ?)
          )
      ''', [userId, userId, userId]);

      await txn.rawUpdate('''
        UPDATE transfers
        SET user_id = ?
        WHERE user_id IS NULL
          AND EXISTS (
            SELECT 1 FROM accounts s
            JOIN accounts d ON d.id = transfers.destination_account_id
            WHERE s.id = transfers.source_account_id
              AND d.id = transfers.destination_account_id
              AND s.user_id = ?
              AND d.user_id = ?
          )
      ''', [userId, userId, userId]);

      final accountCount = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM accounts WHERE user_id IS NULL',
          )) ??
          0;
      final transactionCount = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM transactions WHERE user_id IS NULL',
          )) ??
          0;
      final transferCount = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM transfers WHERE user_id IS NULL',
          )) ??
          0;
      final pending = accountCount > 0 ||
          transactionCount > 0 ||
          transferCount > 0;

      await txn.insert(
        'legacy_data_migration',
        {
          'id': 1,
          'status': pending ? 'pending_review' : 'complete',
          'unassigned_accounts': accountCount,
          'unassigned_transactions': transactionCount,
          'unassigned_transfers': transferCount,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }
}
