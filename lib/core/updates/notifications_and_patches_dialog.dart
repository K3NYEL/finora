import 'package:flutter/material.dart';

import '../platform/update_service.dart';
import 'finora_updates_service.dart';
import '../../shared/widgets/update_dialog.dart';

class NotificationsAndPatchesDialog extends StatefulWidget {
  const NotificationsAndPatchesDialog();

  @override
  State<NotificationsAndPatchesDialog> createState() =>
      NotificationsAndPatchesDialogState();
}

class NotificationsAndPatchesDialogState
    extends State<NotificationsAndPatchesDialog> {
  late Future<FinoraUpdatesManifest> _manifestFuture;

  @override
  void initState() {
    super.initState();
    _manifestFuture = const FinoraUpdatesService().fetchManifest();
  }

  void _retry() {
    setState(() {
      _manifestFuture = const FinoraUpdatesService().fetchManifest();
    });
  }

  Future<void> _checkAndOpenPatch() async {
    try {
      final update = await UpdateService.checkForUpdate();
      if (!mounted) return;
      if (update == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay una actualización instalada pendiente.')),
        );
        return;
      }
      await showUpdateDialog(context, update);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          error is UpdateCheckException
              ? error.message
              : 'No se pudo comprobar la actualización.',
        )),
      );
    }
  }

  String _dateLabel(DateTime? value) {
    if (value == null) return 'Fecha no indicada';
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Notificaciones y parches'),
      content: SizedBox(
        width: 520,
        child: FutureBuilder<FinoraUpdatesManifest>(
          future: _manifestFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No se pudieron cargar los avisos. Comprueba tu conexión e inténtalo de nuevo.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Volver a intentar'),
                  ),
                ],
              );
            }

            final manifest = snapshot.data!;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Avisos',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (manifest.notifications.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text('No hay avisos nuevos.'),
                    )
                  else
                    for (final notice in manifest.notifications)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: Icon(
                            notice.level == 'critical'
                                ? Icons.error_outline_rounded
                                : notice.level == 'warning'
                                    ? Icons.warning_amber_rounded
                                    : Icons.notifications_none_rounded,
                            color: notice.level == 'critical'
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(notice.title),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${notice.message}\n${_dateLabel(notice.publishedAt)}',
                            ),
                          ),
                        ),
                      ),
                  const SizedBox(height: 12),
                  Text(
                    'Parches y correcciones',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (manifest.patches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('No hay notas de parches publicadas.'),
                    )
                  else
                    for (final patch in manifest.patches)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${patch.title} · v${patch.version}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  if (patch.required)
                                    const Chip(
                                      label: Text('Importante'),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(patch.summary),
                              const SizedBox(height: 4),
                              Text(
                                _dateLabel(patch.publishedAt),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (patch.notes.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                for (final note in patch.notes)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text('• $note'),
                                  ),
                              ],
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: _checkAndOpenPatch,
                                  icon: const Icon(Icons.system_update_alt_rounded),
                                  label: const Text('Comprobar actualización'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: 8),
                  Text(
                    'Última actualización del listado: ${_dateLabel(manifest.updatedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _retry,
          child: const Text('Actualizar lista'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _OperationLoadingDialog extends StatelessWidget {
  const _OperationLoadingDialog({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryManagerDialog extends ConsumerStatefulWidget {
  const _CategoryManagerDialog();

  @override
  ConsumerState<_CategoryManagerDialog> createState() =>
      _CategoryManagerDialogState();
}

class _CategoryManagerDialogState
    extends ConsumerState<_CategoryManagerDialog> {
  String _type = 'expense';
  bool _busy = false;

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_type == 'income' ? 'Nueva categoría de ingreso' : 'Nueva categoría de gasto'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            hintText: 'Ej. Salario o Transporte',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).addCategory(name, _type);
      ref.invalidate(categoriesProvider(_type));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error is AppException ? error.message : 'No se pudo agregar la categoría.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCategory(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text('¿Quieres eliminar "$name"? Las categorías predeterminadas están protegidas y no se pueden eliminar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).deleteCategory(id);
      ref.invalidate(categoriesProvider(_type));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error is AppException ? error.message : 'No se pudo eliminar la categoría.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider(_type));
    return AlertDialog(
      title: const Text('Categorías financieras'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Gastos'), icon: Icon(Icons.south_west_rounded)),
                ButtonSegment(value: 'income', label: Text('Ingresos'), icon: Icon(Icons.north_east_rounded)),
              ],
              selected: {_type},
              onSelectionChanged: _busy ? null : (value) => setState(() => _type = value.first),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: categories.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (_, __) => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No se pudieron cargar las categorías.'),
                ),
                data: (items) => items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Todavía no hay categorías. Agrega la primera.'),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final category in items)
                            ListTile(
                              dense: true,
                              title: Text(category.name),
                              trailing: IconButton(
                                tooltip: 'Eliminar categoría personalizada',
                                onPressed: _busy ? null : () => _deleteCategory(category.id, category.name),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _addCategory,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Agregar'),
        ),
      ],
    );
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