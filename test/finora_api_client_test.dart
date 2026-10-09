import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:finora/core/network/finora_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('reports when the remote API has not been configured', () async {
    final client = FinoraApiClient(baseUrl: '');
    expect(client.isConfigured, isFalse);
    await expectLater(
      client.health(),
      throwsA(
        isA<FinoraApiException>().having(
          (error) => error.message,
          'message',
          contains('no está configurada'),
        ),
      ),
    );
    client.close();
  });

  test('calls health endpoint using the configured base path', () async {
    Uri? requestedUri;
    final client = FinoraApiClient(
      baseUrl: 'https://api.example.test/finora/',
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      }),
    );

    final result = await client.health();

    expect(requestedUri, Uri.parse('https://api.example.test/finora/health'));
    expect(result['status'], 'ok');
    client.close();
  });

  test('parses successful login response and sends JSON', () async {
    late http.Request captured;
    final client = FinoraApiClient(
      baseUrl: 'https://api.example.test',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'user': {
              'id': 'usr_123',
              'firstName': 'Ada',
              'lastName': 'Lovelace',
              'loginIdentifier': 'ada@example.test',
            },
            'accessToken': 'access-token',
            'tokenType': 'Bearer',
            'expiresIn': 900,
          }),
          200,
        );
      }),
    );

    final session = await client.login(
      loginIdentifier: 'ada@example.test',
      password: 'a-secure-password',
    );

    expect(captured.url.path, '/v1/auth/login');
    expect(captured.headers['content-type'], 'application/json');
    expect(jsonDecode(captured.body), {
      'loginIdentifier': 'ada@example.test',
      'password': 'a-secure-password',
    });
    expect(session.userId, 'usr_123');
    expect(session.accessToken, 'access-token');
    expect(session.expiresIn, 900);
    client.close();
  });

  test('maps invalid credentials to a safe message', () async {
    final client = FinoraApiClient(
      baseUrl: 'https://api.example.test',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'invalid_credentials'}),
          401,
        ),
      ),
    );

    await expectLater(
      client.login(loginIdentifier: 'ada', password: 'wrong'),
      throwsA(
        isA<FinoraApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having(
              (error) => error.message,
              'message',
              contains('incorrectos'),
            ),
      ),
    );
    client.close();
  });

  test('rejects insecure non-local API URLs', () {
    expect(
      () => FinoraApiClient(baseUrl: 'http://api.example.test'),
      throwsA(isA<FinoraApiException>()),
    );
  });

  test('rejects incomplete session responses', () {
    expect(
      () => FinoraApiSession.fromJson({'accessToken': 'token'}),
      throwsA(isA<FinoraApiException>()),
    );
  });
}
