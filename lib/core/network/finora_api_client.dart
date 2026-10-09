import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// HTTP client for the Finora API. Configure the base URL at build time with
/// --dart-define=FINORA_API_BASE_URL=https://your-api.example.
class FinoraApiClient {
  FinoraApiClient({
    String baseUrl = const String.fromEnvironment('FINORA_API_BASE_URL'),
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  })  : _baseUrl = _parseBaseUrl(baseUrl),
        _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final Uri? _baseUrl;
  final http.Client _httpClient;
  final bool _ownsClient;
  final Duration timeout;

  bool get isConfigured => _baseUrl != null;

  static Uri? _parseBaseUrl(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;

    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FinoraApiException(
        'La dirección de la API de Finora no es válida.',
      );
    }
    if (uri.scheme != 'https' &&
        uri.host != 'localhost' &&
        uri.host != '127.0.0.1' &&
        uri.host != '10.0.2.2') {
      throw const FinoraApiException(
        'La API debe usar HTTPS fuera del entorno local de desarrollo.',
      );
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''));
  }

  Uri _uri(String path) {
    final base = _baseUrl;
    if (base == null) {
      throw const FinoraApiException(
        'La API remota no está configurada. Finora puede seguir usando sus datos locales.',
      );
    }
    final cleanPath = path.replaceFirst(RegExp(r'^/+'), '');
    return base.replace(path: '${base.path}/$cleanPath');
  }

  Future<Map<String, dynamic>> health() => _request('GET', '/health');

  Future<Map<String, dynamic>> readiness() => _request('GET', '/ready');

  Future<FinoraApiSession> register({
    required String firstName,
    required String lastName,
    required String loginIdentifier,
    required String password,
    required String passwordConfirmation,
  }) async {
    final result = await _request(
      'POST',
      '/v1/auth/register',
      body: {
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'loginIdentifier': loginIdentifier.trim(),
        'password': password,
        'passwordConfirmation': passwordConfirmation,
      },
    );
    return FinoraApiSession.fromJson(result);
  }

  Future<FinoraApiSession> login({
    required String loginIdentifier,
    required String password,
  }) async {
    final result = await _request(
      'POST',
      '/v1/auth/login',
      body: {
        'loginIdentifier': loginIdentifier.trim(),
        'password': password,
      },
    );
    return FinoraApiSession.fromJson(result);
  }

  Future<Map<String, dynamic>> me(String accessToken) =>
      _request('GET', '/v1/me', accessToken: accessToken);

  /// Validates a local backup on the server without importing any records.
  Future<FinoraBackupPreview> previewBackup({
    required String accessToken,
    required String backupJson,
    required String currencyCode,
  }) async {
    final result = await _request(
      'POST',
      '/v1/import/preview',
      accessToken: accessToken,
      body: {'backupJson': backupJson, 'currencyCode': currencyCode},
    );
    return FinoraBackupPreview.fromJson(result);
  }

  /// Imports a backup only after the caller explicitly confirms the preview.
  Future<Map<String, dynamic>> importBackup({
    required String accessToken,
    required String backupJson,
    required String currencyCode,
    required bool confirm,
  }) {
    if (!confirm) {
      throw const FinoraApiException(
        'Confirma la importación después de revisar la vista previa.',
      );
    }
    return _request(
      'POST',
      '/v1/import/backup',
      accessToken: accessToken,
      body: {
        'backupJson': backupJson,
        'currencyCode': currencyCode,
        'confirm': true,
      },
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? accessToken,
  }) async {
    final headers = <String, String>{'accept': 'application/json'};
    if (body != null) headers['content-type'] = 'application/json';
    if (accessToken != null && accessToken.isNotEmpty) {
      headers['authorization'] = 'Bearer $accessToken';
    }

    try {
      final uri = _uri(path);
      final response = await switch (method) {
        'GET' => _httpClient.get(uri, headers: headers).timeout(timeout),
        'POST' => _httpClient
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(timeout),
        _ => throw const FinoraApiException('Método HTTP no compatible.'),
      };
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : _decodeObject(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FinoraApiException(
          _messageFor(decoded, response.statusCode),
          statusCode: response.statusCode,
        );
      }
      return decoded;
    } on TimeoutException {
      throw const FinoraApiException(
        'La API de Finora tardó demasiado en responder.',
      );
    } on FinoraApiException {
      rethrow;
    } catch (_) {
      throw const FinoraApiException(
        'No se pudo conectar con la API de Finora.',
      );
    }
  }

  Map<String, dynamic> _decodeObject(String body) {
    try {
      final value = jsonDecode(body);
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      // Replaced below with a stable, user-safe error.
    }
    throw const FinoraApiException('La API devolvió una respuesta inválida.');
  }

  String _messageFor(Map<String, dynamic> body, int statusCode) {
    switch (body['error']) {
      case 'invalid_credentials':
        return 'El identificador o la contraseña son incorrectos.';
      case 'account_unavailable':
        return 'No se pudo crear la cuenta con esos datos.';
      case 'invalid_request':
        return 'Revisa los datos introducidos e inténtalo de nuevo.';
      case 'invalid_session':
        return 'La sesión ha caducado. Inicia sesión de nuevo.';
      case 'service_unavailable':
        return 'El servicio de Finora no está disponible temporalmente.';
      case 'backup_already_imported':
        return 'Esta copia ya fue importada en esta cuenta.';
      case 'explicit_confirmation_required':
        return 'La importación requiere confirmación explícita.';
      default:
        if (statusCode == 401) return 'Debes iniciar sesión de nuevo.';
        if (statusCode == 409) return 'La operación entra en conflicto con datos existentes.';
        if (statusCode >= 500) return 'El servidor de Finora tiene un problema temporal.';
        return 'La API de Finora rechazó la solicitud ($statusCode).';
    }
  }

  void close() {
    if (_ownsClient) _httpClient.close();
  }
}

class FinoraBackupPreview {
  const FinoraBackupPreview({
    required this.checksum,
    required this.alreadyImported,
    required this.currencyCode,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.transfers,
  });

  final String checksum;
  final bool alreadyImported;
  final String currencyCode;
  final int accounts;
  final int categories;
  final int transactions;
  final int transfers;

  factory FinoraBackupPreview.fromJson(Map<String, dynamic> json) {
    final counts = json['counts'];
    if (json['checksum'] is! String ||
        json['alreadyImported'] is! bool ||
        json['currencyCode'] is! String ||
        counts is! Map<String, dynamic> ||
        !['accounts', 'categories', 'transactions', 'transfers'].every(
          (key) => counts[key] is int && (counts[key] as int) >= 0,
        )) {
      throw const FinoraApiException(
        'La API devolvió una vista previa de copia inválida.',
      );
    }
    return FinoraBackupPreview(
      checksum: json['checksum'] as String,
      alreadyImported: json['alreadyImported'] as bool,
      currencyCode: json['currencyCode'] as String,
      accounts: counts['accounts'] as int,
      categories: counts['categories'] as int,
      transactions: counts['transactions'] as int,
      transfers: counts['transfers'] as int,
    );
  }
}

class FinoraApiSession {
  const FinoraApiSession({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.loginIdentifier,
    required this.accessToken,
    required this.expiresIn,
  });

  final String userId;
  final String firstName;
  final String lastName;
  final String loginIdentifier;
  final String accessToken;
  final int expiresIn;

  factory FinoraApiSession.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    final token = json['accessToken'];
    final expiresIn = json['expiresIn'];
    if (user is! Map<String, dynamic> ||
        user['id'] is! String ||
        user['firstName'] is! String ||
        user['lastName'] is! String ||
        user['loginIdentifier'] is! String ||
        token is! String ||
        token.isEmpty ||
        expiresIn is! int ||
        expiresIn <= 0) {
      throw const FinoraApiException(
        'La API devolvió datos de sesión incompletos.',
      );
    }
    return FinoraApiSession(
      userId: user['id'] as String,
      firstName: user['firstName'] as String,
      lastName: user['lastName'] as String,
      loginIdentifier: user['loginIdentifier'] as String,
      accessToken: token,
      expiresIn: expiresIn,
    );
  }
}

class FinoraApiException implements Exception {
  const FinoraApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
