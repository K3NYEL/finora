import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finora/core/database/database.dart';
import 'package:finora/core/errors/app_exception.dart';
import 'package:finora/features/auth/data/auth_repository.dart';

void main() {
  late Database database;
  late AuthRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    database = await AppDatabase.instance;
    repository = AuthRepository();
  });

  tearDownAll(() async {
    await AppDatabase.close();
  });

  test('new password hashes can be verified during login', () async {
    final firstName = 'Audit${DateTime.now().microsecondsSinceEpoch}';
    const lastName = 'Regression';

    final created = await repository.createUser(
      firstName: firstName,
      lastName: lastName,
      password: 'SecurePass123!',
    );

    try {
      final rows = await database.query(
        'users',
        columns: ['password_hash'],
        where: 'id = ?',
        whereArgs: [created.id],
        limit: 1,
      );
      expect(rows, hasLength(1));
      expect(
        rows.single['password_hash'],
        startsWith('pbkdf2_sha256\$120000\$'),
      );

      final loggedIn = await repository.login(
        firstName: firstName,
        lastName: lastName,
        password: 'SecurePass123!',
      );
      expect(loggedIn.id, created.id);
    } finally {
      await database.delete(
        'users',
        where: 'id = ?',
        whereArgs: [created.id],
      );
    }
  });

  test('login uses names and surnames, not the internal user id', () async {
    final firstName = 'Case${DateTime.now().microsecondsSinceEpoch}';
    const lastName = 'Regression';
    const password = 'SecurePass123!';

    final created = await repository.createUser(
      firstName: firstName,
      lastName: lastName,
      password: password,
    );

    try {
      final loggedIn = await repository.login(
        firstName: '  ${firstName.toLowerCase()}  ',
        lastName: '  regression  ',
        password: password,
      );

      expect(loggedIn.id, created.id);
      expect(loggedIn.fullName, '$firstName $lastName');
      expect(loggedIn.fullName, isNot(contains(created.id)));

      await expectLater(
        repository.login(
          firstName: firstName,
          lastName: lastName,
          password: 'WrongPassword123!',
        ),
        throwsA(isA<AppException>()),
      );
    } finally {
      await database.delete('users', where: 'id = ?', whereArgs: [created.id]);
    }
  });

  test('legacy password hashes upgrade after successful login', () async {
    final firstName = 'Legacy${DateTime.now().microsecondsSinceEpoch}';
    const lastName = 'Regression';
    const password = 'LegacyPass123!';
    final salt = base64UrlEncode(List<int>.generate(16, (i) => i + 1));
    final legacyHash = sha256.convert(utf8.encode('$salt$password')).toString();
    final id = 'audit_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();

    await database.insert('users', {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'password_hash': '$salt:$legacyHash',
      'created_at': now,
      'last_login': now,
    });

    try {
      final loggedIn = await repository.login(
        firstName: firstName,
        lastName: lastName,
        password: password,
      );
      expect(loggedIn.id, id);

      final rows = await database.query(
        'users',
        columns: ['password_hash'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      expect(
        rows.single['password_hash'],
        startsWith('pbkdf2_sha256\$120000\$'),
      );
    } finally {
      await database.delete('users', where: 'id = ?', whereArgs: [id]);
    }
  });
}
