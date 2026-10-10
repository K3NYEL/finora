import 'dart:convert';

import '../errors/app_exception.dart';
import 'api_client.dart';

const _syncResources = {'accounts', 'categories', 'transactions', 'transfers', 'budgets'};

/// A single remote change. [data] is validated as an object before it reaches
/// the reconciliation layer; this class does not write to SQLite.
class FinoraRemoteChange {
  const FinoraRemoteChange({required this.resource, required this.data});

  final String resource;
  final Map<String, dynamic> data;

  factory FinoraRemoteChange.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const AppException('El servidor devolvió un cambio de sincronización no válido.');
    }
    final resource = value['resource'];
    final data = value['data'];
    if (resource is! String ||
        !_syncResources.contains(resource) ||
        data is! Map<String, dynamic> ||
        data['id'] is! String ||
        (data['syncVersion'] is! int) ||
        (data['syncCursor'] is! int)) {
      throw const AppException('El servidor devolvió un cambio de sincronización no válido.');
    }
    return FinoraRemoteChange(
      resource: resource,
      data: Map<String, dynamic>.unmodifiable(data),
    );
  }
}

/// Cursor-paginated remote changes. Parsing is deliberately separate from
/// applying changes, so callers can validate a complete page before a DB tx.
class FinoraSyncPage {
  const FinoraSyncPage({
    required this.changes,
    required this.nextCursor,
    required this.hasMore,
    required this.limit,
  });

  final List<FinoraRemoteChange> changes;
  final int nextCursor;
  final bool hasMore;
  final int limit;

  factory FinoraSyncPage.fromJson(
    Map<String, dynamic> json, {
    required int requestedCursor,
  }) {
    final rawChanges = json['changes'];
    final nextCursor = json['nextCursor'];
    final hasMore = json['hasMore'];
    final limit = json['limit'];
    if (rawChanges is! List ||
        nextCursor is! int ||
        nextCursor < requestedCursor ||
        hasMore is! bool ||
        limit is! int ||
        limit < 1 ||
        limit > 200) {
      throw const AppException('El servidor devolvió una página de sincronización no válida.');
    }
    final changes = rawChanges.map(FinoraRemoteChange.fromJson).toList(growable: false);
    if (changes.length > limit) {
      throw const AppException('El servidor devolvió demasiados cambios en una página.');
    }
    return FinoraSyncPage(
      changes: List.unmodifiable(changes),
      nextCursor: nextCursor,
      hasMore: hasMore,
      limit: limit,
    );
  }
}

class FinoraSyncOperationResult {
  const FinoraSyncOperationResult({
    required this.operationId,
    required this.action,
    required this.resource,
    required this.id,
    required this.syncVersion,
  });

  final String operationId;
  final String action;
  final String resource;
  final String id;
  final int syncVersion;

  factory FinoraSyncOperationResult.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['opId'] is! String ||
        !{'create', 'update', 'delete'}.contains(value['action']) ||
        value['resource'] is! String ||
        !_syncResources.contains(value['resource']) ||
        value['id'] is! String ||
        value['syncVersion'] is! int ||
        (value['syncVersion'] as int) < 1) {
      throw const AppException('El servidor devolvió un resultado de sincronización no válido.');
    }
    return FinoraSyncOperationResult(
      operationId: value['opId'] as String,
      action: value['action'] as String,
      resource: value['resource'] as String,
      id: value['id'] as String,
      syncVersion: value['syncVersion'] as int,
    );
  }
}

class FinoraSyncPushResult {
  const FinoraSyncPushResult({required this.results, required this.applied});

  final List<FinoraSyncOperationResult> results;
  final bool applied;

  factory FinoraSyncPushResult.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'];
    if (json['applied'] != true || rawResults is! List || rawResults.isEmpty) {
      throw const AppException('El servidor no confirmó la operación de sincronización.');
    }
    return FinoraSyncPushResult(
      results: List.unmodifiable(rawResults.map(FinoraSyncOperationResult.fromJson)),
      applied: true,
    );
  }
}

/// Explicit API adapter only: no timer, background task, automatic push, local
/// database mutation, or consent change is performed by this class.
class FinoraSyncApi {
  FinoraSyncApi(this._client);

  final FinoraApiClient _client;

  Future<FinoraSyncPage> pullChanges({
    required String bearerToken,
    required int cursor,
    int limit = 100,
  }) async {
    if (bearerToken.trim().isEmpty) {
      throw const AppException('Debes iniciar sesión en la cuenta remota.');
    }
    if (cursor < 0 || limit < 1 || limit > 200) {
      throw const AppException('El cursor o el límite de sincronización no son válidos.');
    }
    final json = await _client.getJson(
      '/api/v1/sync/changes?cursor=$cursor&limit=$limit',
      bearerToken: bearerToken,
    );
    return FinoraSyncPage.fromJson(json, requestedCursor: cursor);
  }

  /// Pushes a pre-built batch only when explicitly called by a future,
  /// consent-gated coordinator. The caller must provide a fresh idempotency key.
  Future<FinoraSyncPushResult> pushBatch({
    required String bearerToken,
    required String idempotencyKey,
    required List<Map<String, Object?>> operations,
  }) async {
    if (bearerToken.trim().isEmpty) {
      throw const AppException('Debes iniciar sesión en la cuenta remota.');
    }
    if (operations.isEmpty || operations.length > 50) {
      throw const AppException('La sincronización admite entre 1 y 50 operaciones por lote.');
    }
    final ids = <String>{};
    for (final operation in operations) {
      final opId = operation['opId'];
      if (opId is! String || opId.trim().isEmpty || !ids.add(opId)) {
        throw const AppException('El lote contiene identificadores de operación inválidos o repetidos.');
      }
    }
    final json = await _client.postJson(
      '/api/v1/sync/push',
      body: <String, Object?>{'operations': operations},
      bearerToken: bearerToken,
      idempotencyKey: idempotencyKey,
    );
    return FinoraSyncPushResult.fromJson(json);
  }

  void close() => _client.close();
}
