import 'package:sqflite/sqflite.dart';

/// Reports whether a local profile is safe to synchronize.
///
/// This class is intentionally read-only: it cannot enable sync, link accounts,
/// or send financial data. Those actions require a separate explicit opt-in
/// flow and review.
class SyncReadiness {
  const SyncReadiness({required this.ready, required this.blockers});

  final bool ready;
  final List<String> blockers;
}

class SyncLocalStateRepository {
  SyncLocalStateRepository(this.database);

  final Database database;

  Future<Map<String, Object?>> getState() async {
    final rows = await database.query('sync_state', where: 'id = 1', limit: 1);
    if (rows.isEmpty) {
      return const {
        'id': 1,
        'cursor': 0,
        'enabled': 0,
        'local_user_id': null,
        'remote_user_id': null,
      };
    }
    return rows.single;
  }

  /// Checks linkage, unresolved ownership, stable identities, and whether every
  /// financial relationship stays inside the same local owner's data.
  Future<SyncReadiness> inspectForUser(String localUserId) async {
    final blockers = <String>[];
    if (localUserId.trim().isEmpty) {
      blockers.add('local_user_missing');
      return SyncReadiness(ready: false, blockers: List.unmodifiable(blockers));
    }

    final state = await getState();
    if (state['enabled'] != 1) blockers.add('sync_disabled');
    if (state['local_user_id'] != localUserId) blockers.add('local_account_not_linked');
    if (state['remote_user_id'] is! String ||
        (state['remote_user_id'] as String).trim().isEmpty) {
      blockers.add('remote_account_not_linked');
    }

    Future<int> count(String sql, [List<Object?> args = const []]) async {
      final rows = await database.rawQuery(sql, args);
      return Sqflite.firstIntValue(rows) ?? 0;
    }

    if (await count('SELECT COUNT(*) FROM accounts WHERE user_id IS NULL') > 0 ||
        await count('SELECT COUNT(*) FROM transactions WHERE user_id IS NULL') > 0 ||
        await count('SELECT COUNT(*) FROM transfers WHERE user_id IS NULL') > 0) {
      blockers.add('legacy_ownership_unresolved');
    }

    // Financial values must be present as integer minor units before upload.
    // Never fall back to REAL amounts or silently round corrupted records.
    if (await count('''
      SELECT COUNT(*) FROM accounts
      WHERE user_id = ?
        AND (initial_balance_minor IS NULL OR typeof(initial_balance_minor) <> 'integer')
    ''', [localUserId]) > 0 ||
        await count('''
      SELECT COUNT(*) FROM transactions
      WHERE user_id = ?
        AND (amount_minor IS NULL OR typeof(amount_minor) <> 'integer' OR amount_minor <= 0)
    ''', [localUserId]) > 0 ||
        await count('''
      SELECT COUNT(*) FROM transfers
      WHERE user_id = ?
        AND (amount_minor IS NULL OR typeof(amount_minor) <> 'integer' OR amount_minor <= 0)
    ''', [localUserId]) > 0) {
      blockers.add('financial_amount_integrity_failed');
    }

    final resourceCounts = <String, String>{
      'accounts': 'user_id = ? AND sync_id IS NULL',
      'categories': 'user_id = ? AND sync_id IS NULL',
      'transactions': 'user_id = ? AND sync_id IS NULL',
      'transfers': 'user_id = ? AND sync_id IS NULL',
    };
    for (final entry in resourceCounts.entries) {
      if (await count(
            'SELECT COUNT(*) FROM ${entry.key} WHERE ${entry.value}',
            [localUserId],
          ) >
          0) {
        blockers.add('missing_sync_identity_${entry.key}');
      }
    }

    // Never sync a transaction if its account is missing, unowned, owned by
    // another profile, or its category belongs to another profile.
    if (await count('''
      SELECT COUNT(*)
      FROM transactions t
      LEFT JOIN accounts a ON a.id = t.account_id
      LEFT JOIN categories c ON c.id = t.category_id
      WHERE t.user_id = ?
        AND (
          a.id IS NULL OR a.user_id IS NULL OR a.user_id <> t.user_id
          OR c.id IS NULL
          OR (c.user_id IS NOT NULL AND c.user_id <> t.user_id)
        )
    ''', [localUserId]) >
        0) {
      blockers.add('transaction_relationship_owner_mismatch');
    }

    // Both sides of a transfer must exist and belong to the transfer owner.
    if (await count('''
      SELECT COUNT(*)
      FROM transfers t
      LEFT JOIN accounts s ON s.id = t.source_account_id
      LEFT JOIN accounts d ON d.id = t.destination_account_id
      WHERE t.user_id = ?
        AND (
          s.id IS NULL OR d.id IS NULL
          OR s.user_id IS NULL OR d.user_id IS NULL
          OR s.user_id <> t.user_id OR d.user_id <> t.user_id
        )
    ''', [localUserId]) >
        0) {
      blockers.add('transfer_relationship_owner_mismatch');
    }

    // Shared built-in categories have no server identity. A later adapter must
    // resolve them to an owned remote category before pushing dependent rows.
    if (await count('''
      SELECT COUNT(*)
      FROM transactions t
      JOIN categories c ON c.id = t.category_id
      WHERE t.user_id = ? AND c.user_id IS NULL
    ''', [localUserId]) >
        0) {
      blockers.add('shared_category_mapping_required');
    }

    return SyncReadiness(
      ready: blockers.isEmpty,
      blockers: List.unmodifiable(blockers),
    );
  }

  /// Produces a count-only dry run for the selected local profile. This method
  /// does not enable sync, modify rows/checkpoints, or call the network.
  Future<SyncDryRunPreview> previewForUser(String localUserId) async {
    final readiness = await inspectForUser(localUserId);
    if (localUserId.trim().isEmpty) {
      return SyncDryRunPreview(readiness: readiness, recordCounts: const {});
    }

    Future<int> count(String table) async {
      final rows = await database.rawQuery(
        'SELECT COUNT(*) FROM $table WHERE user_id = ?',
        [localUserId],
      );
      return Sqflite.firstIntValue(rows) ?? 0;
    }

    final counts = <String, int>{
      'accounts': await count('accounts'),
      'categories': await count('categories'),
      'transactions': await count('transactions'),
      'transfers': await count('transfers'),
    };
    return SyncDryRunPreview(
      readiness: readiness,
      recordCounts: Map.unmodifiable(counts),
    );
  }

}

/// Count-only synchronization preview. It never reads or returns financial
/// values and never changes the checkpoint or sends a network request.
class SyncDryRunPreview {
  const SyncDryRunPreview({
    required this.readiness,
    required this.recordCounts,
  });

  final SyncReadiness readiness;
  final Map<String, int> recordCounts;

  int get totalRecords =>
      recordCounts.values.fold(0, (total, count) => total + count);

  /// Be deliberately conservative: if any gate is blocked, the preview must
  /// not describe any record as eligible for upload.
  int get eligibleRecords => readiness.ready ? totalRecords : 0;

}
