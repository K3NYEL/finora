import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/update_info.dart';

class ApkInstaller {
  const ApkInstaller._();

  static Future<bool> downloadAndInstall(
    UpdateAsset apk, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    VoidCallback? onOpeningInstaller,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      debugPrint(
        '[FINORA UPDATE] La instalación automática solo está disponible en Android.',
      );
      return false;
    }

    final client = http.Client();
    IOSink? sink;

    try {
      debugPrint('[FINORA UPDATE] Descargando ${apk.name}...');

      final directory = await getTemporaryDirectory();
      final apkFile = File('${directory.path}/${apk.name}');

      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final request = http.Request('GET', Uri.parse(apk.downloadUrl));
      final response = await client
          .send(request)
          .timeout(const Duration(minutes: 2));

      if (response.statusCode != HttpStatus.ok) {
        debugPrint(
          '[FINORA UPDATE] Error HTTP ${response.statusCode} al descargar APK.',
        );
        await response.stream.drain<void>();
        return false;
      }

      final contentLength = response.contentLength;
      final totalBytes = contentLength != null && contentLength > 0
          ? contentLength
          : null;
      var receivedBytes = 0;
      sink = apkFile.openWrite();

      onProgress?.call(0, totalBytes);

      await for (final chunk
          in response.stream.timeout(const Duration(minutes: 5))) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(receivedBytes, totalBytes);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (!await apkFile.exists() || receivedBytes == 0) {
        debugPrint('[FINORA UPDATE] El APK no pudo guardarse o está vacío.');
        return false;
      }

      if (totalBytes != null && receivedBytes != totalBytes) {
        debugPrint(
          '[FINORA UPDATE] Descarga incompleta: $receivedBytes de $totalBytes bytes.',
        );
        await apkFile.delete();
        return false;
      }

      debugPrint(
        '[FINORA UPDATE] APK descargado: ${apkFile.path} ($receivedBytes bytes)',
      );

      onOpeningInstaller?.call();

      final result = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      debugPrint(
        '[FINORA UPDATE] Instalador: ${result.type} - ${result.message}',
      );

      // Esto confirma que se abrió el manejador, no que el usuario completó
      // la instalación desde Android.
      return result.type == ResultType.done;
    } catch (e, stackTrace) {
      debugPrint('[FINORA UPDATE] Error instalando actualización: $e');
      debugPrint('$stackTrace');
      return false;
    } finally {
      if (sink != null) {
        await sink.close();
      }
      client.close();
    }
  }
}
