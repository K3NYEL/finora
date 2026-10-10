import 'package:flutter_test/flutter_test.dart';
import 'package:finora/core/network/api_client.dart';
import 'package:finora/core/network/finora_remote_auth_api.dart';

void main() {
  group('FinoraRemoteAuthApi registration validation', () {
    test('rejects usernames outside the server contract before networking', () async {
      final client = FinoraApiClient();
      final api = FinoraRemoteAuthApi(client);
      addTearDown(client.close);

      await expectLater(
        api.register(username: 'x', password: 'correct-horse-battery'),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects passwords shorter than the server contract before networking', () async {
      final client = FinoraApiClient();
      final api = FinoraRemoteAuthApi(client);
      addTearDown(client.close);

      await expectLater(
        api.register(username: 'finora_user', password: 'short'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('FinoraRemoteSession', () {
    test('parses a valid in-memory session', () {
      final session = FinoraRemoteSession.fromJson({
        'user': {
          'id': '8e7f6b7a-1234-4234-8234-123456789abc',
          'username': 'finora_user',
          'createdAt': '2026-10-01T12:00:00.000Z',
        },
        'accessToken': List.filled(43, 'a').join(),
        'tokenType': 'Bearer',
        'expiresAt': '2099-01-01T00:00:00.000Z',
      });

      expect(session.user.username, 'finora_user');
      expect(session.accessToken, hasLength(43));
      expect(session.isExpired, isFalse);
    });

    test('rejects the legacy firstName/lastName API response contract', () {
      expect(
        () => FinoraRemoteSession.fromJson({
          'user': {
            'id': 'remote-user',
            'firstName': 'Finora',
            'lastName': 'User',
            'loginIdentifier': 'finora_user',
          },
          'accessToken': List.filled(43, 'a').join(),
          'tokenType': 'Bearer',
          'expiresAt': '2099-01-01T00:00:00.000Z',
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects non-Bearer token types from the API', () {
      expect(
        () => FinoraRemoteSession.fromJson({
          'user': {
            'id': 'remote-user',
            'username': 'finora_user',
            'createdAt': '2026-10-01T12:00:00.000Z',
          },
          'accessToken': List.filled(43, 'a').join(),
          'tokenType': 'Basic',
          'expiresAt': '2099-01-01T00:00:00.000Z',
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects malformed bearer tokens', () {
      expect(
        () => FinoraRemoteSession.fromJson({
          'user': {
            'id': 'remote-user',
            'username': 'finora_user',
            'createdAt': '2026-10-01T12:00:00.000Z',
          },
          'accessToken': 'not-a-token',
          'tokenType': 'Bearer',
          'expiresAt': '2099-01-01T00:00:00.000Z',
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects expired sessions', () {
      expect(
        () => FinoraRemoteSession.fromJson({
          'user': {
            'id': 'remote-user',
            'username': 'finora_user',
            'createdAt': '2026-10-01T12:00:00.000Z',
          },
          'accessToken': List.filled(43, 'a').join(),
          'tokenType': 'Bearer',
          'expiresAt': '2000-01-01T00:00:00.000Z',
        }),
        throwsA(isA<Exception>()),
      );
    });
  });
}
