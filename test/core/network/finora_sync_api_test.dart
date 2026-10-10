import 'package:flutter_test/flutter_test.dart';
import 'package:finora/core/network/finora_sync_api.dart';

void main() {
  group('FinoraSyncPage', () {
    test('parses a valid page without mutating the cursor', () {
      final page = FinoraSyncPage.fromJson({
        'changes': [
          {
            'resource': 'accounts',
            'data': {
              'id': '8e7f6b7a-1234-4234-8234-123456789abc',
              'syncVersion': 1,
              'syncCursor': 4,
              'name': 'Cuenta de prueba',
            },
          },
        ],
        'nextCursor': 4,
        'hasMore': false,
        'limit': 100,
      }, requestedCursor: 3);

      expect(page.changes, hasLength(1));
      expect(page.changes.single.resource, 'accounts');
      expect(page.nextCursor, 4);
      expect(page.hasMore, isFalse);
    });

    test('rejects a cursor that moves backwards', () {
      expect(
        () => FinoraSyncPage.fromJson({
          'changes': <Object>[],
          'nextCursor': 2,
          'hasMore': false,
          'limit': 100,
        }, requestedCursor: 3),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects unknown resources and malformed change records', () {
      expect(
        () => FinoraRemoteChange.fromJson({
          'resource': 'users',
          'data': {'id': 'remote-id', 'syncVersion': 1, 'syncCursor': 1},
        }),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('FinoraSyncPushResult', () {
    test('parses a confirmed result', () {
      final result = FinoraSyncPushResult.fromJson({
        'applied': true,
        'results': [
          {
            'opId': 'op-123',
            'action': 'create',
            'resource': 'accounts',
            'id': '8e7f6b7a-1234-4234-8234-123456789abc',
            'syncVersion': 1,
          },
        ],
      });

      expect(result.applied, isTrue);
      expect(result.results.single.operationId, 'op-123');
      expect(result.results.single.syncVersion, 1);
    });

    test('rejects an unconfirmed batch', () {
      expect(
        () => FinoraSyncPushResult.fromJson({
          'applied': false,
          'results': <Object>[],
        }),
        throwsA(isA<Exception>()),
      );
    });
  });
}
