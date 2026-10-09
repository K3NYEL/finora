import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/user.dart';

class AuthRepository {
  AuthRepository();

  static const _passwordHashAlgorithm = 'pbkdf2_sha256';
  static const _passwordHashIterations = 120000;
  static const _passwordHashBytes = 32;
  static const _passwordSaltBytes = 16;

  final Uuid _uuid = const Uuid();

  Future<Database> get _db => AppDatabase.instance;

  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  /// PBKDF2-HMAC-SHA256; versioned format allows future parameter upgrades.
  String _createPasswordHash(String password) {
    final salt = _generateRandomBytes(_passwordSaltBytes);
    final hash = _pbkdf2(
      password: password,
      salt: salt,
      iterations: _passwordHashIterations,
    );
    return '${_passwordHashAlgorithm}\$${_passwordHashIterations}\$'
        '${base64UrlEncode(salt)}\$'
        '${base64UrlEncode(hash)}';
  }

  Uint8List _pbkdf2({
    required String password,
    required List<int> salt,
    required int iterations,
  }) {
    final mac = Hmac(sha256, utf8.encode(password));
    final block = Uint8List(salt.length + 4)
      ..setRange(0, salt.length, salt)
      ..[salt.length] = 0
      ..[salt.length + 1] = 0
      ..[salt.length + 2] = 0
      ..[salt.length + 3] = 1;

    var u = mac.convert(block).bytes;
    final result = Uint8List.fromList(u);

    for (var i = 1; i < iterations; i++) {
      u = mac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }

  bool _verifyPassword(String password, String storedHash) {
    final parts = storedHash.split(r'$');
    if (parts.length == 4 && parts[0] == _passwordHashAlgorithm) {
      final iterations = int.tryParse(parts[1]);
      if (iterations == null ||
          iterations < 10000 ||
          iterations > 1000000) {
        return false;
      }
      try {
        final salt = base64Url.decode(base64Url.normalize(parts[2]));
        final expected = base64Url.decode(base64Url.normalize(parts[3]));
        if (salt.length < _passwordSaltBytes ||
            expected.length != _passwordHashBytes) {
          return false;
        }
        final actual = _pbkdf2(
          password: password,
          salt: salt,
          iterations: iterations,
        );
        return _constantTimeEquals(actual, expected);
      } on FormatException {
        return false;
      }
    }

    // Backward compatibility for existing accounts using the legacy salted
    // SHA-256 format. A successful login upgrades the hash automatically.
    final legacyParts = storedHash.split(':');
    if (legacyParts.length != 2) return false;
    final actual = sha256.convert(utf8.encode('${legacyParts[0]}$password')).bytes;
    final expected = _hexToBytes(legacyParts[1]);
    return expected != null && _constantTimeEquals(actual, expected);
  }

  List<int>? _hexToBytes(String value) {
    if (value.length != 64 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
      return null;
    }
    return List<int>.generate(
      32,
      (i) => int.parse(value.substring(i * 2, i * 2 + 2), radix: 16),
    );
  }

  bool _needsPasswordHashUpgrade(String storedHash) =>
      !storedHash.startsWith('${_passwordHashAlgorithm}\$');

  String _generateUserId() => 'usr_${_uuid.v4().replaceAll('-', '')}';

  Future<AppUser> createUser({
    required String firstName,
    required String lastName,
    required String password,
  }) async {
    final cleanFirstName = firstName.trim();
    final cleanLastName = lastName.trim();

    if (cleanFirstName.isEmpty) {
      throw const AppException('Escribe tus nombres.');
    }
    if (cleanLastName.isEmpty) {
      throw const AppException('Escribe tus apellidos.');
    }
    if (password.length < 8) {
      throw const AppException(
        'La contraseña debe tener al menos 8 caracteres.',
      );
    }
    if (password.length > 128) {
      throw const AppException(
        'La contraseña no puede superar los 128 caracteres.',
      );
    }

    final database = await _db;
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
    await database.insert('users', {
      'id': userId,
      'first_name': cleanFirstName,
      'last_name': cleanLastName,
      'password_hash': _createPasswordHash(password),
      'created_at': now,
      'last_login': now,
    });

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
      throw const AppException('Escribe tus nombres.');
    }
    if (cleanLastName.isEmpty) {
      throw const AppException('Escribe tus apellidos.');
    }
    if (password.isEmpty) {
      throw const AppException('Escribe tu contraseña.');
    }

    final rows = await database.query(
      'users',
      where: 'LOWER(first_name) = LOWER(?) AND LOWER(last_name) = LOWER(?)',
      whereArgs: [cleanFirstName, cleanLastName],
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
    final updates = <String, Object?>{'last_login': now};
    if (_needsPasswordHashUpgrade(storedHash)) {
      updates['password_hash'] = _createPasswordHash(password);
    }
    await database.update(
      'users',
      updates,
      where: 'id = ?',
      whereArgs: [user['id']],
    );

    return AppUser.fromMap({...user, ...updates});
  }

  Future<AppUser?> getUserById(String id) async {
    final database = await _db;
    final rows = await database.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AppUser.fromMap(rows.first);
  }
}
