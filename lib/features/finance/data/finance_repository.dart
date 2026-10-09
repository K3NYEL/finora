import '../../../core/database/database.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/models.dart';
import 'package:sqflite/sqflite.dart';

class FinanceRepository {
  FinanceRepository({
    required this.userId,
  });

  final String userId;

  Future<Database> get _db => AppDatabase.instance;

  static int _toMinorUnits(double amount) => (amount * 100).round();

  // El balance se deriva de los movimientos: nunca queda desincronizado.
  static const _accountsSql = '''
  SELECT a.id, a.name, a.type,
    COALESCE(a.initial_balance_minor / 100.0, a.initial_balance)
      + COALESCE((
          SELECT SUM(
            CASE t.type
              WHEN 'income'
                THEN COALESCE(t.amount_minor / 100.0, t.amount)
              ELSE -COALESCE(t.amount_minor / 100.0, t.amount)
            END
          )
          FROM transactions t
          WHERE t.account_id = a.id
            AND t.user_id = ?
        ), 0)
      + COALESCE((
          SELECT SUM(COALESCE(amount_minor / 100.0, amount))
          FROM transfers
          WHERE destination_account_id = a.id
            AND user_id = ?
        ), 0)
      - COALESCE((
          SELECT SUM(COALESCE(amount_minor / 100.0, amount))
          FROM transfers
          WHERE source_account_id = a.id
            AND user_id = ?
        ), 0) AS balance
  FROM accounts a
  WHERE a.is_archived = 0
    AND a.user_id = ?
''';

  Future<List<Account>> accounts() async {
    final rows = await (await _db).rawQuery(
      '$_accountsSql ORDER BY a.id',
      [userId, userId, userId, userId],
    );

    return [
      for (final r in rows)
        Account(
          r['id'] as int,
          r['name'] as String,
          r['type'] as String,
          (r['balance'] as num).toDouble(),
        ),
    ];
  }

  Future<void> addAccount(String name, String type, double initial) async {
    if (name.trim().isEmpty) {
      throw const AppException('Escribe un nombre para la cuenta.');
    }
    if (initial < 0) {
      throw const AppException('El balance inicial no puede ser negativo.');
    }
    await (await _db).insert('accounts', {
      'user_id': userId,
      'name': name.trim(),
      'type': type,
      'initial_balance': initial,
      'initial_balance_minor': _toMinorUnits(initial),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Category>> categories(String type) async {
    final rows = await (await _db)
        .query('categories', where: 'type = ?', whereArgs: [type]);
    return [
      for (final r in rows) Category(r['id'] as int, r['name'] as String)
    ];
  }

  Future<Account> _account(int id) async {
    final rows = await (await _db).rawQuery(
      '$_accountsSql AND a.id = ?',
      [userId, userId, userId, userId, id],
    );

    if (rows.isEmpty) {
      throw const AppException('La cuenta no existe.');
    }

    final row = rows.first;

    return Account(
      row['id'] as int,
      row['name'] as String,
      row['type'] as String,
      (row['balance'] as num).toDouble(),
    );
  }

  Future<void> addTransaction({
    required int accountId,
    required int? categoryId,
    required String type,
    required double amount,
    String description = '',
  }) async {
    if (amount <= 0) {
      throw const AppException('El monto debe ser mayor que cero.');
    }
    if (type != 'income' && type != 'expense') {
      throw const AppException('El tipo de movimiento no es válido.');
    }
    if (categoryId == null) {
      throw const AppException('Elige una categoría.');
    }
    final acc = await _account(accountId);
    if (type == 'expense' && acc.balance < amount) {
      throw const AppException('Saldo insuficiente en esta cuenta.');
    }
    final now = DateTime.now().toIso8601String();
    await (await _db).insert('transactions', {
      'user_id': userId,
      'account_id': accountId,
      'category_id': categoryId,
      'type': type,
      'amount': amount,
      'amount_minor': _toMinorUnits(amount),
      'description': description.trim(),
      'date': now,
      'created_at': now,
    });
  }

  Future<void> addTransfer(
      int from, int to, double amount, String description) async {
    if (amount <= 0) {
      throw const AppException('El monto debe ser mayor que cero.');
    }
    if (from == to) {
      throw const AppException('Elige dos cuentas diferentes.');
    }
    final src = await _account(from);
    await _account(to);
    if (src.balance < amount) {
      throw const AppException('Saldo insuficiente en la cuenta origen.');
    }
    final now = DateTime.now().toIso8601String();
    await (await _db).insert('transfers', {
      'user_id': userId,
      'source_account_id': from,
      'destination_account_id': to,
      'amount': amount,
      'amount_minor': _toMinorUnits(amount),
      'description': description.trim(),
      'date': now,
      'created_at': now,
    });
  }

  Future<List<Movement>> movements() async {
    final rows = await (await _db).rawQuery('''
      SELECT t.type AS kind, COALESCE(NULLIF(t.description, ''), c.name) AS title,
             a.name AS subtitle, COALESCE(t.amount_minor / 100.0, t.amount) AS amount, t.date AS date
      FROM transactions t JOIN accounts a ON a.id = t.account_id JOIN categories c ON c.id = t.category_id
      WHERE t.user_id = ?
      UNION ALL
      SELECT 'transfer', COALESCE(NULLIF(tr.description, ''), 'Transferencia'),
             s.name || ' → ' || d.name,
             COALESCE(tr.amount_minor / 100.0, tr.amount), tr.date
      FROM transfers tr JOIN accounts s ON s.id = tr.source_account_id
                        JOIN accounts d ON d.id = tr.destination_account_id
      WHERE tr.user_id = ?
      ORDER BY date DESC LIMIT 200''');
    return [
      for (final r in rows)
        Movement(
            r['kind'] as String,
            r['title'] as String,
            r['subtitle'] as String,
            (r['amount'] as num).toDouble(),
            r['date'] as String)
    ];
  }

  Future<Summary> monthSummary() async {
    final n = DateTime.now();
    final r = await (await _db).rawQuery('''
            SELECT COALESCE(SUM(CASE WHEN type='income'
              THEN COALESCE(amount_minor / 100.0, amount) END), 0) AS i,
              COALESCE(SUM(CASE WHEN type='expense'
              THEN COALESCE(amount_minor / 100.0, amount) END), 0) AS e
      FROM transactions WHERE user_id = ? AND date >= ?''',
        [userId, DateTime(n.year, n.month).toIso8601String()]);
    return Summary(
        (r.first['i'] as num).toDouble(), (r.first['e'] as num).toDouble());
  }

  Future<List<(String, double)>> expenseByCategory() async {
    final n = DateTime.now();
    final rows = await (await _db).rawQuery('''
            SELECT c.name AS name,
              SUM(COALESCE(t.amount_minor / 100.0, t.amount)) AS total
              FROM transactions t
      JOIN categories c ON c.id = t.category_id
      WHERE t.user_id = ? AND t.type = 'expense' AND t.date >= ? GROUP BY c.id ORDER BY total DESC''',
        [userId, DateTime(n.year, n.month).toIso8601String()]);
    return [
      for (final r in rows)
        (r['name'] as String, (r['total'] as num).toDouble())
    ];
  }
}
