import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/auth_repository.dart';
import '../domain/user.dart';
import '../../../core/database/automatic_backup_service.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

final sessionProvider =
    NotifierProvider<SessionNotifier, AppUser?>(SessionNotifier.new);

class SessionNotifier extends Notifier<AppUser?> {
  static const _rememberedUserIdKey = 'remembered_user_id';

  @override
  AppUser? build() {
    return null;
  }

  /// Restaura la sesión desde los datos guardados.
  Future<void> restore() async {
    final user = await getRememberedUser();
    state = user;
  }

  /// Comprueba si existe una cuenta recordada.
  Future<AppUser?> getRememberedUser() async {
    final preferences = await SharedPreferences.getInstance();

    final userId = preferences.getString(_rememberedUserIdKey);

    if (userId == null || userId.isEmpty) {
      return null;
    }

    final user = await ref.read(authRepositoryProvider).getUserById(userId);

    if (user == null) {
      await preferences.remove(_rememberedUserIdKey);
      return null;
    }

    return user;
  }

  /// Guarda qué cuenta debe aparecer en el próximo inicio.
  Future<void> rememberUser(AppUser user) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(
      _rememberedUserIdKey,
      user.id,
    );
  }

  /// Inicia la sesión actual después de verificar la contraseña.
  Future<void> setUser(AppUser user) async {
    await rememberUser(user);
    state = user;
    unawaited(
      const AutomaticBackupService().runIfDue(user.id).catchError(
        (Object error, StackTrace stackTrace) {
          // Backup failures must never prevent sign-in. The next sign-in can retry.
          return null;
        },
      ),
    );
  }

  /// Cierra la sesión, pero conserva la cuenta recordada.
  Future<void> clearSession() async {
    state = null;
  }

  /// Elimina completamente la cuenta recordada.
  Future<void> forgetUser() async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(_rememberedUserIdKey);

    state = null;
  }
}
