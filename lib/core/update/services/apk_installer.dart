import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/update_info.dart';

class ApkInstaller {
  const ApkInstaller._();

  static Future<bool> downloadAndInstall(UpdateAsset apk) async {
    if (kIsWeb || !Platform.isAndroid) {
      debugPrint(
        '[FINORA UPDATE] La instalación automática solo está disponible en Android.',
      );
      return false;
    }

    try {
      debugPrint('[FINORA UPDATE] Descargando ${apk.name}...');

      final directory = await getTemporaryDirectory();
      final apkFile = File('${directory.path}/${apk.name}');

      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final response = await http
          .get(Uri.parse(apk.downloadUrl))
          .timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) {
        debugPrint(
          '[FINORA UPDATE] Error HTTP ${response.statusCode} al descargar APK.',
        );
        return false;
      }

      await apkFile.writeAsBytes(response.bodyBytes, flush: true);

      if (!await apkFile.exists()) {
        debugPrint('[FINORA UPDATE] El APK no pudo guardarse.');
        return false;
      }

      debugPrint('[FINORA UPDATE] APK descargado: ${apkFile.path}');

      final result = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      debugPrint(
        '[FINORA UPDATE] Instalador: ${result.type} - ${result.message}',
      );

      return result.type == ResultType.done;
    } catch (e, stackTrace) {
      debugPrint('[FINORA UPDATE] Error instalando actualización: $e');
      debugPrint('$stackTrace');
      return false;
    }
  }
}
