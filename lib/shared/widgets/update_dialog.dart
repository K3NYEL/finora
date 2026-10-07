import 'package:flutter/material.dart';

import '../../core/platform/update_service.dart';

Future<void> showUpdateDialog(
  BuildContext context,
  UpdateInfo update,
) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('Nueva versión disponible'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              update.releaseName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Versión actual: ${update.currentVersion}',
            ),
            Text(
              'Nueva versión: ${update.latestVersion}',
            ),
            if (update.apk != null) ...[
              const SizedBox(height: 12),
              Text(
                'APK: ${update.apk!.name}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Más tarde'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();

              await UpdateService.downloadAndInstall(
                update,
              );
            },
            child: const Text('Actualizar'),
          ),
        ],
      );
    },
  );
}
