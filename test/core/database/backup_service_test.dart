import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:finora/core/database/backup_service.dart';
import 'package:finora/core/errors/app_exception.dart';

void main() {
  final service = BackupService();

  group('BackupService.restoreBackup validation', () {
    test('rejects invalid JSON before opening the database', () async {
      await expectLater(
        service.restoreBackup(userId: 'user-1', jsonText: '{not json'),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects oversized input at the service boundary', () async {
      final chunk = List<String>.filled(8192, ' ').join();
      final buffer = StringBuffer();
      while (buffer.length <= BackupService.maxBackupBytes) {
        buffer.write(chunk);
      }

      await expectLater(
        service.restoreBackup(
          userId: 'user-1',
          jsonText: buffer.toString(),
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects an unknown backup format', () async {
      await expectLater(
        service.restoreBackup(
          userId: 'user-1',
          jsonText: '{"format":"other","schema_version":1,'
              '"accounts":[],"categories":[],"transactions":[],"transfers":[]}',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects duplicate account identifiers', () async {
      await expectLater(
        service.restoreBackup(
          userId: 'user-1',
          jsonText: '''
          {
            "format": "finora-backup",
            "schema_version": 1,
            "accounts": [
              {"id": 1, "name": "Cuenta A", "type": "cash",
               "initial_balance": 0, "created_at": "2026-01-01"},
              {"id": 1, "name": "Cuenta B", "type": "cash",
               "initial_balance": 0, "created_at": "2026-01-02"}
            ],
            "categories": [],
            "transactions": [],
            "transfers": []
          }
          ''',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects movements referencing missing backup records', () async {
      await expectLater(
        service.restoreBackup(
          userId: 'user-1',
          jsonText: '''
          {
            "format": "finora-backup",
            "schema_version": 1,
            "accounts": [
              {"id": 1, "name": "Cuenta", "type": "cash",
               "initial_balance": 0, "created_at": "2026-01-01"}
            ],
            "categories": [],
            "transactions": [
              {"id": 1, "account_id": 999, "category_id": 888,
               "type": "income", "amount": 10, "date": "2026-01-01"}
            ],
            "transfers": []
          }
          ''',
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('BackupService recovery integration', () {
    late Database db;
    late BackupService isolatedService;

    setUpAll(() {
      sqfliteFfiInit();
    });

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE users (id TEXT PRIMARY KEY)');
      await db.execute('''
        CREATE TABLE accounts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          initial_balance REAL NOT NULL DEFAULT 0,
          initial_balance_minor INTEGER,
          created_at TEXT NOT NULL,
          is_archived INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          is_default INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          account_id INTEGER NOT NULL,
          category_id INTEGER NOT NULL,
          type TEXT NOT NULL,
          amount REAL NOT NULL,
          amount_minor INTEGER,
          description TEXT,
          date TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE transfers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          source_account_id INTEGER NOT NULL,
          destination_account_id INTEGER NOT NULL,
          amount REAL NOT NULL,
          amount_minor INTEGER,
          description TEXT,
          date TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.insert('users', {'id': 'user-a'});
      await db.insert('users', {'id': 'user-b'});
      isolatedService = BackupService(databaseProvider: () async => db);
    });

    tearDown(() async {
      await db.close();
    });

    const backup = '''
    {
      "format": "finora-backup",
      "schema_version": 1,
      "created_at": "2026-10-10T00:00:00Z",
      "accounts": [
        {"id": 10, "name": "Efectivo", "type": "cash",
         "initial_balance": 12.5, "initial_balance_minor": 1250,
         "created_at": "2026-01-01T00:00:00Z", "is_archived": 0},
        {"id": 11, "name": "Banco", "type": "bank",
         "initial_balance": 0, "initial_balance_minor": 0,
         "created_at": "2026-01-02T00:00:00Z", "is_archived": 0}
      ],
      "categories": [
        {"id": 20, "name": "Alimentación", "type": "expense"}
      ],
      "transactions": [
        {"id": 30, "account_id": 10, "category_id": 20,
         "type": "expense", "amount": 20, "amount_minor": 2000,
         "description": "Compra", "date": "2026-01-03",
         "created_at": "2026-01-03T12:00:00Z"}
      ],
      "transfers": [
        {"id": 40, "source_account_id": 10, "destination_account_id": 11,
         "amount": 5.25, "amount_minor": 525, "description": "Traspaso",
         "date": "2026-01-04", "created_at": "2026-01-04T12:00:00Z"}
      ]
    }
    ''';

    test('restores the same backup independently for two local users', () async {
      final first = await isolatedService.restoreBackup(
        userId: 'user-a',
        jsonText: backup,
      );
      final second = await isolatedService.restoreBackup(
        userId: 'user-b',
        jsonText: backup,
      );

      expect(first, {'accounts': 2, 'transactions': 1, 'transfers': 1, 'categories': 1});
      expect(second, first);
      expect(await db.rawQuery(
        "SELECT user_id, COUNT(*) AS total FROM accounts GROUP BY user_id ORDER BY user_id",
      ), [
        {'user_id': 'user-a', 'total': 2},
        {'user_id': 'user-b', 'total': 2},
      ]);
      expect(await db.rawQuery(
        "SELECT user_id, COUNT(*) AS total FROM transactions GROUP BY user_id ORDER BY user_id",
      ), [
        {'user_id': 'user-a', 'total': 1},
        {'user_id': 'user-b', 'total': 1},
      ]);
      expect(await db.rawQuery(
        "SELECT user_id, COUNT(*) AS total FROM transfers GROUP BY user_id ORDER BY user_id",
      ), [
        {'user_id': 'user-a', 'total': 1},
        {'user_id': 'user-b', 'total': 1},
      ]);
      final balances = await db.query('accounts', columns: ['initial_balance_minor']);
      expect(balances.map((row) => row['initial_balance_minor']).toSet(), {0, 1250});
      final amounts = await db.query('transactions', columns: ['amount_minor']);
      expect(amounts.single['amount_minor'], 2000);
    });

    test('blocks repeated restore for one user without changing existing data', () async {
      await isolatedService.restoreBackup(userId: 'user-a', jsonText: backup);
      await expectLater(
        isolatedService.restoreBackup(userId: 'user-a', jsonText: backup),
        throwsA(isA<AppException>()),
      );
      expect(await db.rawQuery("SELECT COUNT(*) AS total FROM accounts WHERE user_id = 'user-a'"),
          [{'total': 2}]);
      expect(await db.rawQuery("SELECT COUNT(*) AS total FROM transactions WHERE user_id = 'user-a'"),
          [{'total': 1}]);
    });

    test('rejects a missing destination user before inserting any records', () async {
      await expectLater(
        isolatedService.restoreBackup(userId: 'missing-user', jsonText: backup),
        throwsA(isA<AppException>()),
      );
      expect(await db.query('accounts'), isEmpty);
      expect(await db.query('transactions'), isEmpty);
      expect(await db.query('transfers'), isEmpty);
    });
  });

}
