import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'backup_service.dart';
import '../settings/app_preferences.dart';

/// Runs due backups at successful sign-in. This is opportunistic, not a
/// background scheduler: the app must be opened and a user must sign in.
class AutomaticBackupService {
  const AutomaticBackupService();

  Future<File?> runIfDue(String userId) async {
    final frequency = await AppPreferences.getAutoBackupFrequency();
    if (frequency == 'disabled') return null;

    final now = DateTime.now().toUtc();
    final last = await AppPreferences.getLastAutoBackupAt(userId);
    final interval = frequency == 'daily'
        ? const Duration(days: 1)
        : const Duration(days: 7);
    final elapsed = last == null ? null : now.difference(last);
    if (elapsed != null && !elapsed.isNegative && elapsed < interval) {
      return null;
    }

    final jsonText = await const BackupService().createBackup(userId);
    final baseDirectory = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(baseDirectory.path, 'Finora', 'backups'));
    await directory.create(recursive: true);

    final stamp = now.millisecondsSinceEpoch;
    final userKey =
        sha256.convert(utf8.encode(userId)).toString().substring(0, 16);
    final file = File(
      p.join(directory.path, 'finora-backup-$userKey-$stamp.json'),
    );
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonText, flush: true);
    await temporary.rename(file.path);

    final backups = directory
        .listSync(followLinks: false)
        .whereType<File>()
        .where((candidate) {
          final name = p.basename(candidate.path);
          return name.startsWith('finora-backup-$userKey-') &&
              name.endsWith('.json');
        })
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final oldBackup in backups.skip(5)) {
      await oldBackup.delete();
    }

    await AppPreferences.setLastAutoBackupAt(userId, now);
    return file;
  }
}
