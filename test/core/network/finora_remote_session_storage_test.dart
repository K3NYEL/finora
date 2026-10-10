import 'package:flutter_test/flutter_test.dart';
import 'package:finora/core/network/finora_remote_auth_api.dart';
import 'package:finora/core/network/finora_remote_session_storage.dart';

class MemorySessionStorage implements RemoteSessionStorage {
  String? value;
  int deletes = 0;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> delete() async {
    deletes++;
    value = null;
  }
}

FinoraRemoteSession makeSession({String token = 'a' * 43, String expires = '2099-01-01T00:00:00.000Z'}) {
  return FinoraRemoteSession.fromJson({
    'user': {
      'id': '8e7f6b7a-1234-4234-8234-123456789abc',
      'username': 'finora_user',
      'createdAt': '2026-10-01T12:00:00.000Z',
    },
    'accessToken': token,
    'tokenType': 'Bearer',
    'expiresAt': expires,
  });
}

void main() {
  group('FinoraRemoteSessionRepository', () {
    test('saves and reloads a session through the secure storage boundary', () async {
      final storage = MemorySessionStorage();
      final repository = FinoraRemoteSessionRepository(storage);
      final session = makeSession();

      await repository.save(session);
      final loaded = await repository.load();

      expect(loaded, isNotNull);
      expect(loaded!.user.id, session.user.id);
      expect(loaded.accessToken, session.accessToken);
      expect(loaded.expiresAt, session.expiresAt);
      expect(storage.deletes, 0);
    });

    test('clears malformed persisted credentials', () async {
      final storage = MemorySessionStorage()..value = '{bad json';
      final repository = FinoraRemoteSessionRepository(storage);

      expect(await repository.load(), isNull);
      expect(storage.value, isNull);
      expect(storage.deletes, 1);
    });

    test('clears expired persisted sessions', () async {
      final storage = MemorySessionStorage()
        ..value = '{"user":{"id":"id","username":"user","createdAt":"2026-10-01T00:00:00Z"},'
            '"accessToken":"NaN","tokenType":"Bearer","expiresAt":"2000-01-01T00:00:00Z"}';
      final repository = FinoraRemoteSessionRepository(storage);

      expect(await repository.load(), isNull);
      expect(storage.value, isNull);
      expect(storage.deletes, 1);
    });

    test('clears session explicitly', () async {
      final storage = MemorySessionStorage();
      final repository = FinoraRemoteSessionRepository(storage);
      await repository.save(makeSession());

      await repository.clear();

      expect(storage.value, isNull);
      expect(storage.deletes, 1);
    });
  });
}
