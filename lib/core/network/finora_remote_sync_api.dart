import '../errors/app_exception.dart';
import 'api_client.dart';

const _syncResources = <String>{
  'accounts',
  'categories',
  'transactions',
  'transfers',
  'budgets',
};

/// A server-side change. Tombstones are represented by a non-null deletedAt.
class FinoraRemoteChange {
  const FinoraRemoteChange({
    required this.resource,
    required this.data,
  });

  final String resource;
  final Map<String, dynamic> data;

  String get id => data['id'] as String;
  int get syncVersion => data['syncVersion'] as int;
  int get syncCursor => data['syncCursor'] as int;
  bool get isDeleted => data['deletedAt'] != null;

  factory FinoraRemoteChange.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['resource'] is! String ||
        !_syncResources.contains(value['resource']) ||
        value['data'] is! Map<String, dynamic>) {
      throw const AppException('La API devolvió un cambio de sincronización no válido.');
    }
    final data = value['data'] as Map<String, dynamic>;
    if (data['id'] is! String ||
        (data['id'] as String).isEmpty ||
        data['syncVersion'] is! int ||
        (data['syncVersion'] as int) < 1 ||
        data['syncCursor'] is! int ||
        (data['syncCursor'] as int) < 1 ||
        data['updatedAt'] is! String ||
        DateTime.tryParse(data['updatedAt'] as String) == null ||
        (data['deletedAt'] != null &&
            (data['deletedAt'] is! String ||
                DateTime.tryParse(data['deletedAt'] as String) == null))) {
      throw const AppException('La API devolvió metadatos de sincronización no válidos.');
    }
    return FinoraRemoteChange(
      resource: value['resource'] as String,
      data: Map<String, dynamic>.unmodifiable(data),
    );
  }
}

class FinoraRemoteChangesPage {
  const FinoraRemoteChangesPage({
    required this.changes,
    required this.nextCursor,
    required this.hasMore,
    required this.limit,
  });

  final List<FinoraRemoteChange> changes;
  final int nextCursor;
  final bool hasMore;
  final int limit;

  factory FinoraRemoteChangesPage.fromJson(Map<String, dynamic> json) {
    final rawChanges = json['changes'];
    final cursor = json['nextCursor'];
    final hasMore = json['hasMore'];
    final limit = json['limit'];
    if (rawChanges is! List ||
        cursor is! int ||
        cursor < 0 ||
        hasMore is! bool ||
        limit is! int ||
        limit < 1 ||
        limit > 200) {
      throw const AppException('La API devolvió una página de sincronización no válida.');
    }
    return FinoraRemoteChangesPage(
      changes: List<FinoraRemoteChange>.unmodifiable(
        rawChanges.map(FinoraRemoteChange.fromJson),
      ),
      nextCursor: cursor,
      hasMore: hasMore,
      limit: limit,
    );
  }
}

class FinoraRemoteSyncResult {
  const FinoraRemoteSyncResult({
    required this.opId,
    required this.action,
    required this.resource,
    required this.id,
    required this.syncVersion,
  });

  final String opId;
  final String action;
  final String resource;
  final String id;
  final int syncVersion;

  factory FinoraRemoteSyncResult.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['opId'] is! String ||
        !{'create', 'update', 'delete'}.contains(value['action']) ||
        value['resource'] is! String ||
        !_syncResources.contains(value['resource']) ||
        value['id'] is! String ||
        value['syncVersion'] is! int ||
        (value['syncVersion'] as int) < 1) {
      throw const AppException('La API devolvió un resultado de sincronización no válido.');
    }
    return FinoraRemoteSyncResult(
      opId: value['opId'] as String,
      action: value['action'] as String,
      resource: value['resource'] as String,
      id: value['id'] as String,
      syncVersion: value['syncVersion'] as int,
    );
  }
}

class FinoraRemoteSyncBatchResult {
  const FinoraRemoteSyncBatchResult({required this.results});

  final List<FinoraRemoteSyncResult> results;

  factory FinoraRemoteSyncBatchResult.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'];
    if (json['applied'] != true || rawResults is! List) {
      throw const AppException('La API no confirmó la aplicación del lote de sincronización.');
    }
    return FinoraRemoteSyncBatchResult(
      results: List<FinoraRemoteSyncResult>.unmodifiable(
        rawResults.map(FinoraRemoteSyncResult.fromJson),
      ),
    );
  }
}

/// Explicitly invoked transport for the incremental sync API.
///
/// This class never reads the local database and never starts background work.
/// A caller must first complete account linking, inspect local sync readiness,
/// show the user a preview, and explicitly confirm a push.
class FinoraRemoteSyncApi {
  FinoraRemoteSyncApi(this._client);

  final FinoraApiClient _client;

  Future<FinoraRemoteChangesPage> pullChanges({
    required String bearerToken,
    int cursor = 0,
    int limit = 100,
  }) async {
    if (bearerToken.trim().isEmpty || cursor < 0 || limit < 1 || limit > 200) {
      throw const AppException('Los parámetros de consulta de sincronización no son válidos.');
    }
    final json = await _client.getJson(
      '/api/v1/sync/changes?cursor=$cursor&limit=$limit',
      bearerToken: bearerToken,
    );
    return FinoraRemoteChangesPage.fromJson(json);
  }

  Future<FinoraRemoteSyncBatchResult> pushBatch({
    required String bearerToken,
    required String idempotencyKey,
    required List<Map<String, Object?>> operations,
  }) async {
    if (bearerToken.trim().isEmpty ||
        !RegExp(r'^[A-Za-z0-9._:-]{8,128}$').hasMatch(idempotencyKey) ||
        operations.isEmpty ||
        operations.length > 50) {
      throw const AppException('El lote de sincronización no cumple los límites permitidos.');
    }
    final json = await _client.postJson(
      '/api/v1/sync/push',
      bearerToken: bearerToken,
      idempotencyKey: idempotencyKey,
      body: <String, Object?>{'operations': operations},
    );
    return FinoraRemoteSyncBatchResult.fromJson(json);
  }

  void close() => _client.close();
}
