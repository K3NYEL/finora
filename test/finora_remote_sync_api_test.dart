import 'dart:convert';

import 'package:finora/core/network/api_client.dart';
import 'package:finora/core/network/finora_remote_sync_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('pulls a cursor page with bearer auth and parses tombstones', () async {
    late http.Request captured;
    final api = FinoraRemoteSyncApi(FinoraApiClient(
      baseUrl: 'https://api.example.test',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({
          'changes': [{
            'resource': 'accounts',
            'data': {
              'id': '2b2a1f4b-cc86-4f42-8c0f-06c77f7f15de',
              'syncVersion': 2,
              'syncCursor': 7,
              'createdAt': '2026-10-10T12:00:00.000Z',
              'updatedAt': '2026-10-10T12:05:00.000Z',
              'deletedAt': '2026-10-10T12:05:00.000Z',
              'name': 'Cuenta',
              'type': 'cash',
              'currencyCode': 'DOP',
              'openingBalanceMinor': 0,
            }
          }],
          'nextCursor': 7,
          'hasMore': false,
          'limit': 50,
        }), 200);
      }),
    ));

    final page = await api.pullChanges(
      bearerToken: 'valid-token-value-for-testing-12345678901234567890',
      cursor: 3,
      limit: 50,
    );

    expect(captured.url.path, '/api/v1/sync/changes');
    expect(captured.url.queryParameters, {'cursor': '3', 'limit': '50'});
    expect(captured.headers['authorization'], startsWith('Bearer '));
    expect(page.nextCursor, 7);
    expect(page.hasMore, isFalse);
    expect(page.changes.single.isDeleted, isTrue);
    expect(page.changes.single.syncVersion, 2);
    api.close();
  });

  test('pushes only explicitly supplied operations with idempotency key', () async {
    late http.Request captured;
    final api = FinoraRemoteSyncApi(FinoraApiClient(
      baseUrl: 'https://api.example.test',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({
          'applied': true,
          'results': [{
            'opId': 'create-account-1',
            'action': 'create',
            'resource': 'accounts',
            'id': '2b2a1f4b-cc86-4f42-8c0f-06c77f7f15de',
            'syncVersion': 1,
          }],
        }), 200);
      }),
    ));

    final result = await api.pushBatch(
      bearerToken: 'valid-token-value-for-testing-12345678901234567890',
      idempotencyKey: 'batch-20261010-001',
      operations: [{
        'opId': 'create-account-1',
        'action': 'create',
        'resource': 'accounts',
        'data': {
          'id': '2b2a1f4b-cc86-4f42-8c0f-06c77f7f15de',
          'name': 'Cuenta',
          'type': 'cash',
          'currencyCode': 'DOP',
          'openingBalanceMinor': 0,
        },
      }],
    );

    expect(captured.url.path, '/api/v1/sync/push');
    expect(captured.headers['authorization'], startsWith('Bearer '));
    expect(captured.headers['idempotency-key'], 'batch-20261010-001');
    expect(jsonDecode(captured.body)['operations'], hasLength(1));
    expect(result.results.single.syncVersion, 1);
    api.close();
  });

  test('rejects oversized push batches before making a request', () async {
    var sent = false;
    final api = FinoraRemoteSyncApi(FinoraApiClient(
      baseUrl: 'https://api.example.test',
      httpClient: MockClient((_) async {
        sent = true;
        return http.Response('{}', 200);
      }),
    ));

    await expectLater(
      api.pushBatch(
        bearerToken: 'valid-token-value-for-testing-12345678901234567890',
        idempotencyKey: 'batch-20261010-001',
        operations: List.generate(51, (i) => <String, Object?>{'opId': 'op-$i'}),
      ),
      throwsA(isA<Exception>()),
    );
    expect(sent, isFalse);
    api.close();
  });
}
