import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/settings_provider.dart';
import '../../../../core/settings/app_preferences.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
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
              subtitle: 'USD — Dólar estadounidense',
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
              subtitle: 'Comprobar si existe una nueva versión',
              onTap: () {
                // Próximamente conectaremos UpdateService.
              },
            ),
            const _SettingsTile(
              icon: Icons.info_outline,
              title: 'Versión actual',
              subtitle: '0.2.0',
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
              onTap: () {
                showLicensePage(
                  context: context,
                  applicationName: 'Finora',
                  applicationVersion: '0.2.0',
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
