import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/update_info.dart';

class GithubReleaseRepository {
  const GithubReleaseRepository();

  static const _latestReleaseUrl =
      'https://api.github.com/repos/K3NYEL/finora/releases/latest';

  Future<ReleaseInfo> fetchLatestRelease() async {
    try {
      final uri = Uri.parse(_latestReleaseUrl).replace(
        queryParameters: {
          'v': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );

      debugPrint('[FINORA UPDATE] Consultando GitHub Releases...');
      final response = await http.get(
        uri,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw UpdateCheckException(
          'GitHub respondió HTTP ${response.statusCode} al consultar la release.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const UpdateCheckException(
          'GitHub devolvió una respuesta de release inválida.',
        );
      }

      final tagName = decoded['tag_name'] as String?;
      final name = decoded['name'] as String?;
      final body = decoded['body'] as String? ?? '';
      if (tagName == null || tagName.isEmpty) {
        throw const UpdateCheckException(
          'La última release de GitHub no contiene un tag válido.',
        );
      }

      final assets = <String, ReleaseAsset>{};
      final rawAssets = decoded['assets'];
      if (rawAssets is List) {
        for (final rawAsset in rawAssets) {
          if (rawAsset is! Map<String, dynamic>) continue;
          final assetName = rawAsset['name'] as String?;
          final downloadUrl = rawAsset['browser_download_url'] as String?;
          final rawDigest = rawAsset['digest'] as String?;
          final size = rawAsset['size'];
          if (assetName == null ||
              assetName.isEmpty ||
              downloadUrl == null ||
              downloadUrl.isEmpty ||
              size is! int ||
              size < 1) {
            continue;
          }
          final digestMatch = rawDigest == null
              ? null
              : RegExp(r'^sha256:([a-fA-F0-9]{64})$').firstMatch(rawDigest);
          assets[assetName] = ReleaseAsset(
            name: assetName,
            downloadUrl: downloadUrl,
            size: size,
            sha256: digestMatch?.group(1)?.toLowerCase(),
          );
        }
      }

      return ReleaseInfo(
        tagName: tagName,
        name: name ?? 'Finora $tagName',
        body: body,
        assets: assets,
      );
    } on SocketException catch (e, stackTrace) {
      debugPrint('[FINORA UPDATE] Error de conexión: $e');
      debugPrint('$stackTrace');
      throw const UpdateCheckException(
        'No fue posible conectar con GitHub para comprobar actualizaciones.',
      );
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('[FINORA UPDATE] Tiempo de espera agotado: $e');
      debugPrint('$stackTrace');
      throw const UpdateCheckException(
        'La comprobación de actualizaciones agotó el tiempo de espera.',
      );
    } on FormatException catch (e, stackTrace) {
      debugPrint('[FINORA UPDATE] JSON inválido: $e');
      debugPrint('$stackTrace');
      throw const UpdateCheckException(
        'GitHub devolvió datos de release inválidos.',
      );
    } on UpdateCheckException {
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('[FINORA UPDATE] Error inesperado: $e');
      debugPrint('$stackTrace');
      throw const UpdateCheckException(
        'No se pudo consultar GitHub Releases.',
      );
    }
  }
}
