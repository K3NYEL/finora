import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finora/core/settings/app_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Automatic backup timestamps', () {
    test('stores last backup time independently for each user', () async {
      final first = DateTime.utc(2026, 10, 10, 10);
      final second = DateTime.utc(2026, 10, 10, 11);

      await AppPreferences.setLastAutoBackupAt('user-a', first);
      await AppPreferences.setLastAutoBackupAt('user-b', second);

      expect(await AppPreferences.getLastAutoBackupAt('user-a'), first);
      expect(await AppPreferences.getLastAutoBackupAt('user-b'), second);
    });

    test('rejects an empty user identifier', () async {
      await expectLater(
        AppPreferences.getLastAutoBackupAt('  '),
        throwsArgumentError,
      );
    });
  });
}
