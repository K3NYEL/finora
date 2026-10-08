import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/auth_repository.dart';
import '../domain/user.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

final sessionProvider =
    NotifierProvider<SessionNotifier, AppUser?>(SessionNotifier.new);

class SessionNotifier extends Notifier<AppUser?> {
  static const _userIdKey = 'current_user_id';

  @override
  AppUser? build() {
    return null;
  }

  Future<void> restore() async {
    await _restoreSession();
  }

  Future<void> _restoreSession() async {
    final preferences = await SharedPreferences.getInstance();
    final userId = preferences.getString(_userIdKey);

    if (userId == null || userId.isEmpty) {
      return;
    }

    final user = await ref.read(authRepositoryProvider).getUserById(userId);

    if (user != null) {
      state = user;
    } else {
      await preferences.remove(_userIdKey);
    }
  }

  Future<void> setUser(AppUser user) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(_userIdKey, user.id);

    state = user;
  }

  Future<void> clearSession() async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(_userIdKey);

    state = null;
  }
}
