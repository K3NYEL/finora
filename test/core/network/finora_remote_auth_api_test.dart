import 'package:flutter_test/flutter_test.dart';
import 'package:finora/core/network/finora_remote_auth_api.dart';

void main() {
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
