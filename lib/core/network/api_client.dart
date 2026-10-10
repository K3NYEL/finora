import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors/app_exception.dart';
import 'api_config.dart';

/// JSON HTTP transport for Finora DataBase.
/// Authentication and financial sync are deliberately not enabled yet.
class FinoraApiClient {
  FinoraApiClient({http.Client? httpClient, Duration timeout = const Duration(seconds: 15)})
      : _http = httpClient ?? http.Client(),
        _timeout = timeout;

  final http.Client _http;
  final Duration _timeout;

  bool get isConfigured => FinoraApiConfig.isConfigured;

  Future<Map<String, dynamic>> getJson(String path) => _sendJson('GET', path);

  Future<Map<String, dynamic>> postJson(String path, {required Map<String, Object?> body}) =>
      _sendJson('POST', path, body: body);

  Future<Map<String, dynamic>> _sendJson(String method, String path, {Map<String, Object?>? body}) async {
    if (!isConfigured) {
      throw const AppException('El servidor de Finora todavía no está configurado en esta instalación.');
    }

    final normalizedPath = path.replaceFirst(RegExp(r'^/+'), '');
    final uri = FinoraApiConfig.baseUri.resolve(normalizedPath);
    if (uri.scheme != 'https' && !{'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host)) {
      throw const AppException('La API debe utilizar HTTPS fuera del entorno local.');
    }

    try {
      final request = http.Request(method, uri)..headers['Accept'] = 'application/json';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json; charset=utf-8';
        request.body = jsonEncode(body);
      }
      final streamed = await _http.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AppException(_safeServerMessage(response.statusCode, response.body));
      }
      if (response.body.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const AppException('El servidor devolvió una respuesta no válida.');
      }
      return decoded;
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw const AppException('El servidor tardó demasiado en responder. Inténtalo de nuevo.');
    } on http.ClientException {
      throw const AppException('No se pudo conectar con el servidor de Finora.');
    } on FormatException {
      throw const AppException('El servidor devolvió datos con un formato no válido.');
    }
  }

  String _safeServerMessage(int statusCode, String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'];
        if (message is String && message.trim().isNotEmpty && message.length <= 180) return message;
      }
    } on FormatException {
      // Do not expose arbitrary HTML or server internals to the user.
    }
    switch (statusCode) {
      case 401:
        return 'La sesión del servidor no es válida.';
      case 403:
        return 'No tienes permiso para realizar esta operación.';
      case 404:
        return 'La función solicitada no está disponible en el servidor.';
      case 429:
        return 'Se hicieron demasiadas solicitudes. Espera un momento.';
      default:
        return statusCode >= 500
            ? 'El servidor de Finora tuvo un problema. Inténtalo más tarde.'
            : 'La solicitud no pudo completarse (HTTP $statusCode).';
    }
  }

  void close() => _http.close();
}
