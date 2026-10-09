import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';

import '../../../../features/auth/presentation/session_provider.dart';
import '../../../../app/settings_provider.dart';
import '../../../../core/platform/update_service.dart';
import '../../../../core/database/database.dart';
import '../../../../core/database/migrations/legacy_data_migration_service.dart';
import '../../../finance/presentation/providers.dart';
import '../../../../core/settings/app_preferences.dart';
import '../../../../shared/widgets/update_dialog.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _checkingForUpdate = false;
  String? _currentVersion;

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();

      if (!mounted) return;

      setState(() {
        _currentVersion = packageInfo.version;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _currentVersion = 'Desconocida';
      });
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checkingForUpdate) return;

    setState(() {
      _checkingForUpdate = true;
    });

    try {
      final update = await UpdateService.checkForUpdate();

      if (!mounted) return;

      if (update != null) {
        await showUpdateDialog(context, update);
      } else {
        await _showUpdateMessage(
          title: 'Finora está actualizada',
          message: 'No hay una versión nueva disponible para este dispositivo.',
          icon: Icons.check_circle_outline_rounded,
        );
      }
    } on UpdateCheckException catch (e) {
      if (!mounted) return;

      await _showUpdateMessage(
        title: 'No se pudo comprobar',
        message: e.message,
        icon: Icons.cloud_off_outlined,
      );
    } catch (e) {
      if (!mounted) return;

      await _showUpdateMessage(
        title: 'No se pudo comprobar',
        message: 'Ocurrió un error inesperado al comprobar actualizaciones.',
        icon: Icons.error_outline_rounded,
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingForUpdate = false;
        });
      }
    }
  }

  Future<void> _showUpdateMessage({
    required String title,
    required String message,
    required IconData icon,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title),
              ),
            ],
          ),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Aceptar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _recoverLegacyData() async {
    final user = ref.read(sessionProvider);
    if (user == null) return;

    final database = await AppDatabase.instance;
    final migration = LegacyDataMigrationService(database);
    final status = await migration.getStatus();
    final accounts = (status['unassigned_accounts'] as num?)?.toInt() ?? 0;
    final transactions =
        (status['unassigned_transactions'] as num?)?.toInt() ?? 0;
    final transfers = (status['unassigned_transfers'] as num?)?.toInt() ?? 0;
    final total = accounts + transactions + transfers;

    if (!mounted) return;
    if (total == 0) {
      await _showUpdateMessage(
        title: 'No hay datos pendientes',
        message: 'No se encontraron cuentas, movimientos ni transferencias '
            'antiguas pendientes de recuperar.',
        icon: Icons.check_circle_outline_rounded,
      );
      return;
    }

    final confirmationController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recuperar datos antiguos'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Finora encontró datos financieros sin propietario asignado '
                'en esta instalación:',
              ),
              const SizedBox(height: 12),
              Text('• Cuentas: $accounts'),
              Text('• Movimientos: $transactions'),
              Text('• Transferencias: $transfers'),
              const SizedBox(height: 12),
              const Text(
                'Si continúas, las cuentas antiguas sin propietario se '
                'asignarán a tu perfil y los movimientos compatibles se '
                'vincularán a esas cuentas. Los registros que entren en '
                'conflicto permanecerán sin asignar.',
              ),
              const SizedBox(height: 12),
              Text(
                'No continúes si este dispositivo fue compartido y esos datos '
                'podrían pertenecer a otra persona. Esta acción no se puede '
                'deshacer desde la aplicación.',
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Escribe exactamente: '
                '${LegacyDataMigrationService.confirmationPhrase}',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmationController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmación',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Recuperar datos'),
          ),
        ],
      ),
    );
    final confirmation = confirmationController.text;
    confirmationController.dispose();

    if (confirmed != true || !mounted) return;

    try {
      await migration.adoptLegacyData(
        userId: user.id,
        confirmation: confirmation,
      );

      ref.invalidate(accountsProvider);
      ref.invalidate(movementsProvider);
      ref.invalidate(summaryProvider);
      ref.invalidate(byCategoryProvider);

      if (!mounted) return;
      await _showUpdateMessage(
        title: 'Revisión completada',
        message: 'Finora procesó los datos antiguos. Si quedaron registros '
            'en conflicto, permanecerán sin asignar para proteger la '
            'privacidad de las cuentas.',
        icon: Icons.check_circle_outline_rounded,
      );
    } catch (error) {
      if (!mounted) return;
      await _showUpdateMessage(
        title: 'No se pudieron recuperar los datos',
        message: error is Exception
            ? error.toString()
            : 'Ocurrió un error inesperado. No se confirmó la recuperación.',
        icon: Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cerrar sesión'),
          content: const Text(
            '¿Seguro que quieres cerrar tu sesión? '
            'Tus datos permanecerán guardados en este dispositivo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Cerrar sesión'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await ref.read(sessionProvider.notifier).clearSession();

    if (!mounted) return;

    context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              tooltip: 'Volver',
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/');
                }
              },
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configuración',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Personaliza Finora y administra tus datos.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.65),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // =========================
        // APARIENCIA
        // =========================
        _SettingsSection(
          title: 'Apariencia',
          children: [
            _SettingsTile(
              icon: Icons.palette_outlined,
              title: 'Tema',
              subtitle: _themeLabel(settings.theme),
              onTap: () => _showThemeSelector(context, ref),
            ),
            _SettingsTile(
              icon: Icons.animation_outlined,
              title: 'Animaciones',
              subtitle:
                  settings.animationsEnabled ? 'Activadas' : 'Desactivadas',
              trailing: Switch(
                value: settings.animationsEnabled,
                onChanged: (value) {
                  ref.read(settingsProvider.notifier).setAnimations(value);
                },
              ),
            ),
          ],
        ),

        // =========================
        // FINANZAS
        // =========================
        _SettingsSection(
          title: 'Finanzas',
          children: [
            _SettingsTile(
              icon: Icons.attach_money_rounded,
              title: 'Moneda',
              subtitle: 'DOP — Peso dominicano',
              onTap: () {
                // Próximamente.
              },
            ),
            _SettingsTile(
              icon: Icons.category_outlined,
              title: 'Categorías',
              subtitle: 'Administrar categorías de ingresos y gastos',
              onTap: () {
                // Próximamente.
              },
            ),
          ],
        ),

        _SettingsSection(
          title: 'Cuenta',
          children: [
            _SettingsTile(
              icon: Icons.logout_rounded,
              title: 'Cerrar sesión',
              subtitle: 'Salir de tu cuenta en este dispositivo',
              onTap: _logout,
            ),
          ],
        ),

        // =========================
        // DATOS
        // =========================
        _SettingsSection(
          title: 'Datos',
          children: [
            _SettingsTile(
              icon: Icons.backup_outlined,
              title: 'Copia de seguridad',
              subtitle: 'Guardar una copia de tus datos',
              onTap: () {
                // Próximamente.
              },
            ),
            _SettingsTile(
              icon: Icons.restore_outlined,
              title: 'Restaurar datos',
              subtitle: 'Restaurar una copia existente',
              onTap: () {
                // Próximamente.
              },
            ),
            _SettingsTile(
              icon: Icons.history_rounded,
              title: 'Recuperar datos antiguos',
              subtitle: 'Revisar y recuperar datos sin propietario asignado',
              onTap: _recoverLegacyData,
            ),
            _SettingsTile(
              icon: Icons.sync_outlined,
              title: 'Sincronización',
              subtitle: 'Sincronización con la nube',
              onTap: () {
                // Próximamente: Supabase.
              },
            ),
          ],
        ),

        // =========================
        // ACTUALIZACIONES
        // =========================
        _SettingsSection(
          title: 'Actualizaciones',
          children: [
            _SettingsTile(
              icon: Icons.system_update_outlined,
              title: 'Buscar actualizaciones',
              subtitle: _checkingForUpdate
                  ? 'Comprobando la última versión...'
                  : 'Comprobar si existe una nueva versión',
              trailing: _checkingForUpdate
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _checkingForUpdate ? null : _checkForUpdate,
            ),
            _SettingsTile(
              icon: Icons.info_outline,
              title: 'Versión actual',
              subtitle:
                  _currentVersion == null ? 'Cargando...' : 'v$_currentVersion',
            ),
          ],
        ),

        // =========================
        // ACERCA DE
        // =========================
        _SettingsSection(
          title: 'Acerca de',
          children: [
            _SettingsTile(
              icon: Icons.auto_graph_rounded,
              title: 'Acerca de Finora',
              subtitle: 'Información sobre la aplicación',
              onTap: () {
                // Próximamente.
              },
            ),
            _SettingsTile(
              icon: Icons.description_outlined,
              title: 'Licencias',
              subtitle: 'Licencias de código abierto',
              onTap: () async {
                final packageInfo = await PackageInfo.fromPlatform();

                if (!context.mounted) return;

                showLicensePage(
                  context: context,
                  applicationName: 'Finora',
                  applicationVersion: packageInfo.version,
                );
              },
            ),
          ],
        ),

        const SizedBox(height: 24),

        Center(
          child: Text(
            'Finora',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.45),
                ),
          ),
        ),

        const SizedBox(height: 8),

        Center(
          child: Text(
            'Gestión financiera personal',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.35),
                ),
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  String _themeLabel(ThemePreference theme) {
    switch (theme) {
      case ThemePreference.system:
        return 'Usar configuración del sistema';
      case ThemePreference.light:
        return 'Tema claro';
      case ThemePreference.dark:
        return 'Tema oscuro';
    }
  }

  Future<void> _showThemeSelector(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final current = ref.read(settingsProvider).theme;

    final selected = await showModalBottomSheet<ThemePreference>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tema',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              _ThemeOption(
                value: ThemePreference.system,
                current: current,
                title: 'Sistema',
                subtitle: 'Usar la configuración de apariencia del dispositivo',
                onSelected: (value) {
                  Navigator.pop(context, value);
                },
              ),
              _ThemeOption(
                value: ThemePreference.light,
                current: current,
                title: 'Claro',
                subtitle: 'Usar siempre el tema claro',
                onSelected: (value) {
                  Navigator.pop(context, value);
                },
              ),
              _ThemeOption(
                value: ThemePreference.dark,
                current: current,
                title: 'Oscuro',
                subtitle: 'Usar siempre el tema oscuro',
                onSelected: (value) {
                  Navigator.pop(context, value);
                },
              ),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      await ref.read(settingsProvider.notifier).setTheme(selected);
    }
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.value,
    required this.current,
    required this.title,
    required this.subtitle,
    required this.onSelected,
  });

  final ThemePreference value;
  final ThemePreference current;
  final String title;
  final String subtitle;
  final ValueChanged<ThemePreference> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = value == current;

    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () => onSelected(value),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: _withDividers(children),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> items) {
    final result = <Widget>[];

    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);

      if (i < items.length - 1) {
        result.add(const Divider(height: 1));
      }
    }

    return result;
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minVerticalPadding: 12,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(subtitle),
      ),
      trailing: trailing ??
          (onTap != null ? const Icon(Icons.chevron_right_rounded) : null),
      onTap: onTap,
    );
  }
}
