import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'database.dart';
import '../errors/app_exception.dart';

/// Versioned, user-scoped JSON backup. Credentials and password hashes are
/// intentionally never exported.
class BackupService {
  const BackupService();

  static const format = 'finora-backup';
  static const schemaVersion = 1;

  Future<String> createBackup(String userId) async {
    if (userId.trim().isEmpty) {
      throw const AppException('No se pudo identificar la cuenta actual.');
    }

    final db = await AppDatabase.instance;
    return db.transaction((txn) async {
        final accounts = await txn.query(
          'accounts',
          where: 'user_id = ?',
          whereArgs: [userId],
          orderBy: 'id',
        );
        final transactions = await txn.query(
          'transactions',
          where: 'user_id = ?',
          whereArgs: [userId],
          orderBy: 'id',
        );
        final transfers = await txn.query(
          'transfers',
          where: 'user_id = ?',
          whereArgs: [userId],
          orderBy: 'id',
        );

        final categoryIds = <int>{};
        for (final row in transactions) {
          final id = row['category_id'];
          if (id is int) categoryIds.add(id);
        }

        final categories = <Map<String, Object?>>[];
        for (final id in categoryIds) {
          final rows = await txn.query(
            'categories',
            where: 'id = ? AND (user_id IS NULL OR user_id = ?)',
            whereArgs: [id, userId],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            final row = rows.first;
            categories.add({
              'id': row['id'],
              'name': row['name'],
              'type': row['type'],
            });
          }
        }

        return const JsonEncoder.withIndent('  ').convert({
          'format': format,
          'schema_version': schemaVersion,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'accounts': accounts.map(_safeAccount).toList(),
          'categories': categories,
          'transactions': transactions.map(_safeTransaction).toList(),
          'transfers': transfers.map(_safeTransfer).toList(),
        });
    });
  }

  /// Merges records into the signed-in user's data; never deletes existing
  /// data. IDs are remapped to avoid collisions with records already present.
  Future<Map<String, int>> restoreBackup({
    required String userId,
    required String jsonText,
  }) async {
    if (userId.trim().isEmpty) {
      throw const AppException('No se pudo identificar la cuenta actual.');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw const AppException('El archivo no contiene JSON válido.');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        decoded['schema_version'] != schemaVersion) {
      throw const AppException(
        'El archivo no es una copia de Finora compatible.',
      );
    }

    final accounts = _records(decoded, 'accounts');
    final categories = _records(decoded, 'categories');
    final transactions = _records(decoded, 'transactions');
    final transfers = _records(decoded, 'transfers');

    // Validate the complete structure before writing anything.
    final accountIds = <int>{};
    for (final row in accounts) {
      _requireInt(row, 'id');
      _requireString(row, 'name');
      _requireString(row, 'type');
      _requireNumber(row, 'initial_balance');
      _requireString(row, 'created_at');
      if ((row['initial_balance'] as num) < 0 ||
          !_minorUnitsMatch(
            row,
            'initial_balance_minor',
            (row['initial_balance'] as num).toDouble(),
            allowZero: true,
          )) {
        throw const AppException('La copia contiene un balance inicial inválido.');
      }
      if (!accountIds.add(row['id'] as int)) {
        throw const AppException('La copia contiene cuentas duplicadas.');
      }
    }
    final categoryIds = <int>{};
    for (final row in categories) {
      _requireInt(row, 'id');
      _requireString(row, 'name');
      _requireString(row, 'type');
      if (row['type'] != 'income' && row['type'] != 'expense') {
        throw const AppException('La copia contiene una categoría inválida.');
      }
      if (!categoryIds.add(row['id'] as int)) {
        throw const AppException('La copia contiene categorías duplicadas.');
      }
    }
    final categoryTypes = <int, String>{
      for (final row in categories) row['id'] as int: row['type'] as String,
    };
    for (final row in transactions) {
      _requireInt(row, 'account_id');
      _requireInt(row, 'category_id');
      _requireString(row, 'type');
      _requireNumber(row, 'amount');
      _requireString(row, 'date');
      if (!accountIds.contains(row['account_id']) ||
          !categoryIds.contains(row['category_id'])) {
        throw const AppException(
          'La copia contiene movimientos con referencias inválidas.',
        );
      }
      if (row['type'] != 'income' && row['type'] != 'expense') {
        throw const AppException('La copia contiene un tipo de movimiento inválido.');
      }
      if (categoryTypes[row['category_id']] != row['type']) {
        throw const AppException('La categoría no coincide con el tipo de movimiento.');
      }
      if ((row['amount'] as num) <= 0 ||
          !_minorUnitsMatch(
            row,
            'amount_minor',
            (row['amount'] as num).toDouble(),
          )) {
        throw const AppException('La copia contiene un monto inválido.');
      }
    }
    for (final row in transfers) {
      _requireInt(row, 'source_account_id');
      _requireInt(row, 'destination_account_id');
      _requireNumber(row, 'amount');
      _requireString(row, 'date');
      if (!accountIds.contains(row['source_account_id']) ||
          !accountIds.contains(row['destination_account_id']) ||
          row['source_account_id'] == row['destination_account_id'] ||
          (row['amount'] as num) <= 0 ||
          !_minorUnitsMatch(
            row,
            'amount_minor',
            (row['amount'] as num).toDouble(),
          )) {
        throw const AppException(
          'La copia contiene una transferencia inválida.',
        );
      }
    }

    final checksum = sha256.convert(utf8.encode(jsonText)).toString();
    final db = await AppDatabase.instance;
    return db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS finora_backup_imports(
          checksum TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          imported_at TEXT NOT NULL
        )
      ''');
      final previousImport = await txn.query(
        'finora_backup_imports',
        where: 'checksum = ? AND user_id = ?',
        whereArgs: [checksum, userId],
        limit: 1,
      );
      if (previousImport.isNotEmpty) {
        throw const AppException('Esta copia ya se restauró en esta cuenta.');
      }

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

      final accountMap = <int, int>{};
      for (final row in accounts) {
        final id = await txn.insert('accounts', {
          'user_id': userId,
          'name': row['name'],
          'type': row['type'],
          'initial_balance': (row['initial_balance'] as num).toDouble(),
          'initial_balance_minor': row['initial_balance_minor'] is num
              ? (row['initial_balance_minor'] as num).toInt()
              : ((row['initial_balance'] as num) * 100).round(),
          'created_at': row['created_at'],
          'is_archived': row['is_archived'] == 1 ? 1 : 0,
        });
        accountMap[row['id'] as int] = id;
      }

      final categoryMap = <int, int>{};
      for (final row in categories) {
        final matches = await txn.query(
          'categories',
          columns: ['id'],
          where: 'name = ? AND type = ? AND (user_id IS NULL OR user_id = ?)',
          whereArgs: [row['name'], row['type'], userId],
          orderBy: 'user_id IS NOT NULL',
          limit: 1,
        );
        final int categoryId;
        if (matches.isNotEmpty) {
          categoryId = matches.first['id'] as int;
        } else {
          categoryId = await txn.insert('categories', {
            'user_id': userId,
            'name': row['name'],
            'type': row['type'],
            'is_default': 0,
          });
        }
        categoryMap[row['id'] as int] = categoryId;
      }

      for (final row in transactions) {
        await txn.insert('transactions', {
          'user_id': userId,
          'account_id': accountMap[row['account_id']]!,
          'category_id': categoryMap[row['category_id']]!,
          'type': row['type'],
          'amount': (row['amount'] as num).toDouble(),
          'amount_minor': row['amount_minor'] is num
              ? (row['amount_minor'] as num).toInt()
              : ((row['amount'] as num) * 100).round(),
          'description': row['description'] is String ? row['description'] : '',
          'date': row['date'],
          'created_at': row['created_at'] is String
              ? row['created_at']
              : row['date'],
        });
      }

      for (final row in transfers) {
        await txn.insert('transfers', {
          'user_id': userId,
          'source_account_id': accountMap[row['source_account_id']]!,
          'destination_account_id':
              accountMap[row['destination_account_id']]!,
          'amount': (row['amount'] as num).toDouble(),
          'amount_minor': row['amount_minor'] is num
              ? (row['amount_minor'] as num).toInt()
              : ((row['amount'] as num) * 100).round(),
          'description': row['description'] is String ? row['description'] : '',
          'date': row['date'],
          'created_at': row['created_at'] is String
              ? row['created_at']
              : row['date'],
        });
      }

      await txn.insert('finora_backup_imports', {
        'checksum': checksum,
        'user_id': userId,
        'imported_at': DateTime.now().toUtc().toIso8601String(),
      });

      return {
        'accounts': accounts.length,
        'transactions': transactions.length,
        'transfers': transfers.length,
        'categories': categories.length,
      };
    });
  }

  static Map<String, Object?> _safeAccount(Map<String, Object?> row) => {
        'id': row['id'],
        'name': row['name'],
        'type': row['type'],
        'initial_balance': row['initial_balance'],
        'initial_balance_minor': row['initial_balance_minor'],
        'created_at': row['created_at'],
        'is_archived': row['is_archived'],
      };

  static Map<String, Object?> _safeTransaction(Map<String, Object?> row) => {
        'id': row['id'],
        'account_id': row['account_id'],
        'category_id': row['category_id'],
        'type': row['type'],
        'amount': row['amount'],
        'amount_minor': row['amount_minor'],
        'description': row['description'],
        'date': row['date'],
        'created_at': row['created_at'],
      };

  static Map<String, Object?> _safeTransfer(Map<String, Object?> row) => {
        'id': row['id'],
        'source_account_id': row['source_account_id'],
        'destination_account_id': row['destination_account_id'],
        'amount': row['amount'],
        'amount_minor': row['amount_minor'],
        'description': row['description'],
        'date': row['date'],
        'created_at': row['created_at'],
      };

  static List<Map<String, dynamic>> _records(
    Map<String, dynamic> root,
    String key,
  ) {
    final value = root[key];
    if (value is! List || value.any((row) => row is! Map<String, dynamic>)) {
      throw AppException('La copia tiene una sección "$key" inválida.');
    }
    return value.cast<Map<String, dynamic>>();
  }

  static bool _minorUnitsMatch(
    Map<String, dynamic> row,
    String key,
    double amount, {
    bool allowZero = false,
  }) {
    final value = row[key];
    if (value == null) return true; // Legacy backups can omit minor units.
    if (value is! int || value < (allowZero ? 0 : 1)) return false;
    return value == (amount * 100).round();
  }

  static void _requireInt(Map<String, dynamic> row, String key) {
    if (row[key] is! int) {
      throw AppException('La copia contiene un campo "$key" inválido.');
    }
  }

  static void _requireString(Map<String, dynamic> row, String key) {
    if (row[key] is! String || (row[key] as String).isEmpty) {
      throw AppException('La copia contiene un campo "$key" inválido.');
    }
  }

  static void _requireNumber(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! num || !value.isFinite) {
      throw AppException('La copia contiene un campo "$key" inválido.');
    }
  }
}
