import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../errors/app_exception.dart';
import 'finora_remote_auth_api.dart';

abstract interface class RemoteSessionStorage {
  Future<void> write(String value);
  Future<String?> read();
  Future<void> delete();
}

/// Stores the remote bearer token only in the platform secure-storage service.
/// It must be called only after the user explicitly links a remote account.
class SecureRemoteSessionStorage implements RemoteSessionStorage {
  SecureRemoteSessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'finora.remote_session.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Session repository with a replaceable storage boundary for tests.
/// It does not link a local profile, enable sync, or trigger network requests.
class FinoraRemoteSessionRepository {
  FinoraRemoteSessionRepository(this._storage);

  final RemoteSessionStorage _storage;

  Future<void> save(FinoraRemoteSession session) async {
    if (session.isExpired) {
      throw const AppException('No se puede guardar una sesión remota vencida.');
    }
    await _storage.write(jsonEncode({
      'user': {
        'id': session.user.id,
        'username': session.user.username,
        'createdAt': session.user.createdAt.toUtc().toIso8601String(),
      },
      'accessToken': session.accessToken,
      'tokenType': 'Bearer',
      'expiresAt': session.expiresAt.toUtc().toIso8601String(),
    }));
  }

  Future<FinoraRemoteSession?> load() async {
    final raw = await _storage.read();
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid remote session.');
      }
      final session = FinoraRemoteSession.fromJson(decoded);
      if (session.isExpired) {
        await _storage.delete();
        return null;
      }
      return session;
    } on Object {
      // Do not retain malformed, tampered, or obsolete credentials.
      await _storage.delete();
      return null;
    }
  }

  Future<void> clear() => _storage.delete();
}
