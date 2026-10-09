import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/user.dart';

class AuthRepository {
  AuthRepository();

  final Uuid _uuid = const Uuid();

  Future<Database> get _db => AppDatabase.instance;

  String _generateSalt() {
    final random = Random.secure();

    final randomBytes = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    );

    return base64UrlEncode(randomBytes);
  }

  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode('$salt$password');
    return sha256.convert(bytes).toString();
  }

  String _createPasswordHash(String password) {
    final salt = _generateSalt();
    final hash = _hashPassword(password, salt);

    return '$salt:$hash';
  }

  bool _verifyPassword(String password, String storedHash) {
    final parts = storedHash.split(':');

    if (parts.length != 2) {
      return false;
    }

    final salt = parts[0];
    final expectedHash = parts[1];
    final actualHash = _hashPassword(password, salt);

    return actualHash == expectedHash;
  }

  String _generateUserId() {
    return 'usr_${_uuid.v4().replaceAll('-', '')}';
  }

  Future<AppUser> createUser({
    required String firstName,
    required String lastName,
    required String password,
  }) async {
    final cleanFirstName = firstName.trim();
    final cleanLastName = lastName.trim();

    if (cleanFirstName.isEmpty) {
      throw const AppException(
        'Escribe tus nombres.',
      );
    }

    if (cleanLastName.isEmpty) {
      throw const AppException(
        'Escribe tus apellidos.',
      );
    }

    if (password.length < 6) {
      throw const AppException(
        'La contraseña debe tener al menos 6 caracteres.',
      );
    }

    final database = await _db;

    // Login identifies local users by first and last name. Prevent duplicates
    // here, otherwise two users with the same name could not log in reliably.
    final existingUsers = await database.query(
      'users',
      columns: ['id'],
      where: 'LOWER(first_name) = LOWER(?) AND LOWER(last_name) = LOWER(?)',
      whereArgs: [cleanFirstName, cleanLastName],
      limit: 1,
    );
    if (existingUsers.isNotEmpty) {
      throw const AppException(
        'Ya existe una cuenta con esos nombres y apellidos. '
        'Usa otros datos para identificar tu cuenta.',
      );
    }

    final now = DateTime.now().toIso8601String();
    final userId = _generateUserId();

    await database.insert(
      'users',
      {
        'id': userId,
        'first_name': cleanFirstName,
        'last_name': cleanLastName,
        'password_hash': _createPasswordHash(password),
        'created_at': now,
        'last_login': now,
      },
    );

    return AppUser(
      id: userId,
      firstName: cleanFirstName,
      lastName: cleanLastName,
      createdAt: DateTime.parse(now),
      lastLogin: DateTime.parse(now),
    );
  }

  Future<AppUser> login({
    required String firstName,
    required String lastName,
    required String password,
  }) async {
    final database = await _db;

    final cleanFirstName = firstName.trim();
    final cleanLastName = lastName.trim();

    if (cleanFirstName.isEmpty) {
      throw const AppException(
        'Escribe tus nombres.',
      );
    }

    if (cleanLastName.isEmpty) {
      throw const AppException(
        'Escribe tus apellidos.',
      );
    }

    if (password.isEmpty) {
      throw const AppException(
        'Escribe tu contraseña.',
      );
    }

    final rows = await database.query(
      'users',
      where: 'LOWER(first_name) = LOWER(?) AND LOWER(last_name) = LOWER(?)',
      whereArgs: [
        cleanFirstName,
        cleanLastName,
      ],
    );

    if (rows.isEmpty) {
      throw const AppException(
        'Nombres, apellidos o contraseña incorrectos.',
      );
    }

    if (rows.length > 1) {
      throw const AppException(
        'Hay varias cuentas con esos nombres y apellidos. '
        'Será necesario utilizar otro identificador.',
      );
    }

    final user = rows.first;
    final storedHash = user['password_hash'] as String;

    if (!_verifyPassword(password, storedHash)) {
      throw const AppException(
        'Nombres, apellidos o contraseña incorrectos.',
      );
    }

    final now = DateTime.now().toIso8601String();

    await database.update(
      'users',
      {'last_login': now},
      where: 'id = ?',
      whereArgs: [user['id']],
    );

    return AppUser.fromMap({
      ...user,
      'last_login': now,
    });
  }

  Future<AppUser?> getUserById(String id) async {
    final database = await _db;

    final rows = await database.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return AppUser.fromMap(rows.first);
  }
}
