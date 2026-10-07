import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'migrations/migration_002.dart';
import 'migrations/migration_003.dart';

class AppDatabase {
  static Database? _db;
  static Future<Database>? _opening;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    return _opening ??= _open();
  }

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'finora.db');
    return openDatabase(
      path,
      version: 3,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, _) async {
        await d.execute('''CREATE TABLE accounts(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type TEXT NOT NULL,
          initial_balance REAL NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
          is_archived INTEGER NOT NULL DEFAULT 0)''');
        await d.execute('''CREATE TABLE categories(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type TEXT NOT NULL,
          is_default INTEGER NOT NULL DEFAULT 1)''');
        await d.execute('''CREATE TABLE transactions(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          account_id INTEGER NOT NULL REFERENCES accounts(id),
          category_id INTEGER NOT NULL REFERENCES categories(id),
          type TEXT NOT NULL, amount REAL NOT NULL, description TEXT,
          date TEXT NOT NULL, created_at TEXT NOT NULL)''');
        await d.execute('''CREATE TABLE transfers(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source_account_id INTEGER NOT NULL REFERENCES accounts(id),
          destination_account_id INTEGER NOT NULL REFERENCES accounts(id),
          amount REAL NOT NULL, description TEXT, date TEXT NOT NULL, created_at TEXT NOT NULL)''');
        const exp = [
          'Alimentación',
          'Transporte',
          'Vivienda',
          'Salud',
          'Ocio',
          'Otros gastos'
        ];
        const inc = ['Salario', 'Otros ingresos'];
        for (final n in exp) {
          await d.insert('categories', {'name': n, 'type': 'expense'});
        }
        for (final n in inc) {
          await d.insert('categories', {'name': n, 'type': 'income'});
        }
        await applyMigration002(d);
        await applyMigration003(d);
      },
      onUpgrade: (d, oldVersion, newVersion) async {
        if (oldVersion < 2) await applyMigration002(d);
        if (oldVersion < 3) await applyMigration003(d);
      },
    ).then((database) {
      _db = database;
      _opening = null;
      return database;
    }, onError: (Object error, StackTrace stackTrace) {
      _opening = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  static Future<void> close() async {
    final database = _db;
    _db = null;
    _opening = null;
    await database?.close();
  }
}
