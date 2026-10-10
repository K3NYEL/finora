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

  /// Checks account linkage, the disabled-by-default switch, unresolved
  /// ownership, and local rows that still lack stable remote identities.
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
      return (Sqflite.firstIntValue(rows) ?? 0);
    }

    if (await count('SELECT COUNT(*) FROM accounts WHERE user_id IS NULL') > 0 ||
        await count('SELECT COUNT(*) FROM transactions WHERE user_id IS NULL') > 0 ||
        await count('SELECT COUNT(*) FROM transfers WHERE user_id IS NULL') > 0) {
      blockers.add('legacy_ownership_unresolved');
    }

    final resourceCounts = <String, String>{
      'accounts': 'user_id = ? AND sync_id IS NULL',
      'categories': 'user_id = ? AND sync_id IS NULL',
      'transactions': 'user_id = ? AND sync_id IS NULL',
      'transfers': 'user_id = ? AND sync_id IS NULL',
    };
    for (final entry in resourceCounts.entries) {
      if (await count('SELECT COUNT(*) FROM ${entry.key} WHERE ${entry.value}', [localUserId]) > 0) {
        blockers.add('missing_sync_identity_${entry.key}');
      }
    }

    // Shared built-in categories have no server identity. A later adapter
    // must create/resolve an owned remote category before pushing these rows.
    if (await count('''
      SELECT COUNT(*)
      FROM transactions t
      JOIN categories c ON c.id = t.category_id
      WHERE t.user_id = ? AND c.user_id IS NULL
    ''', [localUserId]) > 0) {
      blockers.add('shared_category_mapping_required');
    }

    return SyncReadiness(
      ready: blockers.isEmpty,
      blockers: List.unmodifiable(blockers),
    );
  }
}
