import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../features/auth/presentation/session_provider.dart';
import '../../../../app/settings_provider.dart';
import '../../../../core/platform/update_service.dart';
import '../../../../core/database/database.dart';
import '../../../../core/database/backup_service.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/database/migrations/legacy_data_migration_service.dart';
import '../../../finance/presentation/providers.dart';
import '../../../../core/settings/app_preferences.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../shared/widgets/update_dialog.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _checkingForUpdate = false;
  bool _dataOperationInProgress = false;
  String? _currentVersion;
  String _currencyCode = 'DOP';

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
    _loadCurrency();
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

  Future<void> _loadCurrency() async {
    final currency = await AppPreferences.getCurrency();
    if (!mounted) return;
    setState(() => _currencyCode = currency);
  }

  Future<void> _showCurrencySelector() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Moneda de visualización'),
              subtitle: Text('Cambia el símbolo; no convierte los importes.'),
            ),
            RadioGroup<String>(
              groupValue: _currencyCode,
              onChanged: (value) => Navigator.pop(sheetContext, value),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'DOP',
                    title: Text('Peso dominicano'),
                    subtitle: Text(r'RD$'),
                  ),
                  RadioListTile<String>(
                    value: 'USD',
                    title: Text('Dólar estadounidense'),
                    subtitle: Text(r'USD$'),
                  ),
                  RadioListTile<String>(
                    value: 'EUR',
                    title: Text('Euro'),
                    subtitle: Text('€'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await AppPreferences.setCurrency(selected);
    if (mounted) setState(() => _currencyCode = selected);
  }

  Future<void> _showCategoryManager() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _CategoryManagerDialog(),
    );
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


  Future<File> _saveBackupFile(String jsonText) async {
    final baseDirectory = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final backupDirectory =
        Directory(p.join(baseDirectory.path, 'Finora', 'backups'));
    await backupDirectory.create(recursive: true);

    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final file = File(p.join(backupDirectory.path, 'finora-backup-$stamp.json'));
    await file.writeAsString(jsonText, encoding: utf8, flush: true);

    // Keep only the five newest Finora backup files in this directory.
    final backups = backupDirectory
        .listSync(followLinks: false)
        .whereType<File>()
        .where((candidate) =>
            p.basename(candidate.path).startsWith('finora-backup-') &&
            p.basename(candidate.path).endsWith('.json'))
        .toList();
    backups.sort((a, b) =>
        b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final oldBackup in backups.skip(5)) {
      await oldBackup.delete();
    }
    return file;
  }

  Future<void> _backupData() async {
    if (_dataOperationInProgress) return;
    final user = ref.read(sessionProvider);
    if (user == null) {
      await _showUpdateMessage(
        title: 'Inicia sesión',
        message: 'Debes iniciar sesión para crear una copia de tus datos.',
        icon: Icons.lock_outline_rounded,
      );
      return;
    }
    setState(() => _dataOperationInProgress = true);
    var loadingOpen = false;
    Future<void>? loadingRoute;
    try {
      loadingRoute = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _OperationLoadingDialog(
          title: 'Creando copia de seguridad',
          message: 'Preparando tus datos y guardando el archivo localmente…',
        ),
      );
      loadingOpen = true;
      await Future<void>.delayed(Duration.zero);
      final jsonText = await const BackupService().createBackup(user.id);
      final file = await _saveBackupFile(jsonText);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      loadingOpen = false;
      await loadingRoute;
      await _showUpdateMessage(
        title: 'Copia guardada',
        message: 'La copia se guardó automáticamente.\n\nRuta:\n${file.path}\n\nConserva este archivo en un lugar privado. No contiene contraseñas ni hashes de acceso.',
        icon: Icons.check_circle_outline_rounded,
      );
    } catch (error) {
      if (!mounted) return;
      if (loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
        if (loadingRoute != null) await loadingRoute;
      }
      await _showUpdateMessage(
        title: 'No se pudo crear la copia',
        message: error is AppException ? error.message : 'Ocurrió un error al generar o guardar la copia de seguridad.',
        icon: Icons.error_outline_rounded,
      );
    } finally {
      if (loadingOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        if (loadingRoute != null) await loadingRoute;
      }
      if (mounted) setState(() => _dataOperationInProgress = false);
    }
  }

  Future<Directory> _getBackupDirectory() async {
    final baseDirectory = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    return Directory(p.join(baseDirectory.path, 'Finora', 'backups'));
  }

  Future<List<File>> _findLocalBackups() async {
    final directory = await _getBackupDirectory();
    if (!await directory.exists()) return <File>[];
    final backups = directory
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) {
          final name = p.basename(file.path);
          return name.startsWith('finora-backup-') && name.endsWith('.json');
        })
        .toList();
    backups.sort((a, b) =>
        b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return backups;
  }

  Future<String?> _chooseBackup(List<File> backups) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurar copia'),
        content: SizedBox(
          width: 460,
          child: backups.isEmpty
              ? const Text(
                  'No se encontraron copias de Finora en la carpeta habitual. '
                  'Puedes buscar una copia guardada en otra ubicación.',
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: backups.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final backup = backups[index];
                      final modified = backup.lastModifiedSync().toLocal();
                      final date = '${modified.year.toString().padLeft(4, '0')}-'
                          '${modified.month.toString().padLeft(2, '0')}-'
                          '${modified.day.toString().padLeft(2, '0')} '
                          '${modified.hour.toString().padLeft(2, '0')}:'
                          '${modified.minute.toString().padLeft(2, '0')}';
                      return ListTile(
                        leading: const Icon(Icons.backup_outlined),
                        title: Text(
                          p.basename(backup.path),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('Última modificación: $date'),
                        onTap: () =>
                            Navigator.of(dialogContext).pop(backup.path),
                      );
                    },
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop('__external__'),
            child: const Text('Buscar otro archivo…'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreData() async {
    if (_dataOperationInProgress) return;
    final user = ref.read(sessionProvider);
    if (user == null) {
      await _showUpdateMessage(
        title: 'Inicia sesión',
        message: 'Debes iniciar sesión para restaurar una copia.',
        icon: Icons.lock_outline_rounded,
      );
      return;
    }

    setState(() => _dataOperationInProgress = true);
    var restoreLoadingOpen = false;
    Future<void>? restoreLoadingRoute;
    Future<void> closeRestoreLoading() async {
      if (restoreLoadingOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        restoreLoadingOpen = false;
        if (restoreLoadingRoute != null) await restoreLoadingRoute;
      }
    }
    try {
      final localBackups = await _findLocalBackups();
      if (!mounted) return;
      final selectedPath = await _chooseBackup(localBackups);
      if (!mounted || selectedPath == null) return;

      List<int> bytes;
      String fileName;
      if (selectedPath == '__external__') {
        final externalFile = await FilePicker.pickFile(
          dialogTitle: 'Seleccionar copia de seguridad de Finora',
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (!mounted || externalFile == null) return;
        bytes = await externalFile.readAsBytes();
        fileName = externalFile.name;
      } else {
        final localFile = File(selectedPath);
        bytes = await localFile.readAsBytes();
        fileName = p.basename(localFile.path);
      }
      if (!mounted) return;
      if (bytes.length > BackupService.maxBackupBytes) {
        throw const AppException('La copia supera el límite de 10 MB.');
      }
      final jsonText = utf8.decode(bytes, allowMalformed: false);

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Restaurar copia de seguridad'),
          content: Text(
            'Se importarán los datos de "$fileName" a la cuenta actual. '
            'Los datos existentes no se borrarán; las cuentas y movimientos '
            'se agregarán a los que ya tienes. Antes de importar, Finora '
            'creará una copia preventiva de tus datos actuales. La misma '
            'copia no puede restaurarse dos veces en esta cuenta.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Restaurar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      restoreLoadingRoute = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _OperationLoadingDialog(
          title: 'Restaurando copia de seguridad',
          message: 'Validando e importando los datos. No cierres Finora…',
        ),
      );
      restoreLoadingOpen = true;
      await Future<void>.delayed(Duration.zero);

      // Do not begin importing unless the current account's data has first
      // been saved successfully. This protects against accidental merges
      // and gives the user a rollback file if they selected the wrong copy.
      final currentData = await const BackupService().createBackup(user.id);
      final safetyFile = await _saveBackupFile(currentData);

      final counts = await const BackupService().restoreBackup(
        userId: user.id,
        jsonText: jsonText,
      );
      await closeRestoreLoading();
      ref.invalidate(accountsProvider);
      ref.invalidate(movementsProvider);
      ref.invalidate(summaryProvider);
      ref.invalidate(byCategoryProvider);

      if (!mounted) return;
      await _showUpdateMessage(
        title: 'Restauración completada',
        message: 'Se importaron ${counts['accounts']} cuentas, '
            '${counts['transactions']} movimientos y '
            '${counts['transfers']} transferencias. '
            'Tus datos anteriores se conservaron. Copia preventiva: '
            '${p.basename(safetyFile.path)}.',
        icon: Icons.check_circle_outline_rounded,
      );
    } on AppException catch (error) {
      await closeRestoreLoading();
      if (!mounted) return;
      await _showUpdateMessage(
        title: 'No se pudo restaurar',
        message: error.message,
        icon: Icons.error_outline_rounded,
      );
    } on FormatException {
      await closeRestoreLoading();
      if (!mounted) return;
      await _showUpdateMessage(
        title: 'Archivo no válido',
        message: 'El archivo no contiene texto UTF-8 válido.',
        icon: Icons.error_outline_rounded,
      );
    } catch (_) {
      await closeRestoreLoading();
      if (!mounted) return;
      await _showUpdateMessage(
        title: 'No se pudo restaurar',
        message: 'Ocurrió un error. No se completó la importación.',
        icon: Icons.error_outline_rounded,
      );
    } finally {
      await closeRestoreLoading();
      if (mounted) setState(() => _dataOperationInProgress = false);
    }
  }

  Future<void> _showSyncInfo() async {
    await _showUpdateMessage(
      title: 'Sincronización en la nube',
      message: 'La sincronización todavía no está disponible porque Finora '
          'no tiene un backend de sincronización configurado. Tus datos '
          'siguen guardándose localmente. Mientras tanto, usa Copia de '
          'seguridad para moverlos manualmente entre dispositivos.',
      icon: Icons.cloud_off_outlined,
    );
  }

  Future<void> _recoverLegacyData() async {
    if (_dataOperationInProgress) return;
    final user = ref.read(sessionProvider);
    if (user == null) {
      await _showUpdateMessage(
        title: 'Inicia sesión',
        message: 'Debes iniciar sesión para recuperar datos antiguos.',
        icon: Icons.lock_outline_rounded,
      );
      return;
    }

    setState(() => _dataOperationInProgress = true);
    TextEditingController? confirmationController;
    var loadingOpen = false;
    Future<void>? loadingRoute;
    Future<void> closeLoading() async {
      if (loadingOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
        if (loadingRoute != null) await loadingRoute;
      }
    }

    try {
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

      final controller = TextEditingController();
      confirmationController = controller;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Recuperar datos antiguos'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Finora encontró datos financieros sin propietario '
                    'asignado en esta instalación:',
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
                    'No continúes si este dispositivo fue compartido y esos '
                    'datos podrían pertenecer a otra persona. Esta acción no '
                    'se puede deshacer desde la aplicación.',
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Escribe exactamente: '
                    '${LegacyDataMigrationService.confirmationPhrase}',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    onChanged: (_) => setDialogState(() {}),
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
                onPressed: controller.text ==
                        LegacyDataMigrationService.confirmationPhrase
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: const Text('Recuperar datos'),
              ),
            ],
          ),
        ),
      );
      final confirmation = controller.text;
      if (confirmed != true || !mounted) return;

      loadingRoute = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _OperationLoadingDialog(
          title: 'Recuperando datos antiguos',
          message: 'Comprobando relaciones y asignando registros…',
        ),
      );
      loadingOpen = true;
      await Future<void>.delayed(Duration.zero);
      await migration.adoptLegacyData(
        userId: user.id,
        confirmation: confirmation,
      );
      await closeLoading();

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
      await closeLoading();
      if (!mounted) return;
      await _showUpdateMessage(
        title: 'No se pudieron recuperar los datos',
        message: error is AppException
            ? error.message
            : 'Ocurrió un error inesperado. No se confirmó la recuperación.',
        icon: Icons.error_outline_rounded,
      );
    } finally {
      confirmationController?.dispose();
      await closeLoading();
      if (mounted) setState(() => _dataOperationInProgress = false);
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
              subtitle: currencyLabel(_currencyCode),
              onTap: _showCurrencySelector,
            ),
            _SettingsTile(
              icon: Icons.category_outlined,
              title: 'Categorías',
              subtitle: 'Administrar categorías de ingresos y gastos',
              onTap: _showCategoryManager,
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
              subtitle: _dataOperationInProgress
                  ? 'Preparando operación...'
                  : 'Exportar cuentas y movimientos a un archivo JSON',
              onTap: _dataOperationInProgress ? null : _backupData,
            ),
            _SettingsTile(
              icon: Icons.restore_outlined,
              title: 'Restaurar datos',
              subtitle: _dataOperationInProgress
                  ? 'Preparando operación...'
                  : 'Importar una copia JSON sin borrar los datos actuales',
              onTap: _dataOperationInProgress ? null : _restoreData,
            ),
            _SettingsTile(
              icon: Icons.history_rounded,
              title: 'Recuperar datos antiguos',
              subtitle: _dataOperationInProgress
                  ? 'Preparando operación...'
                  : 'Revisar y recuperar datos sin propietario asignado',
              onTap: _dataOperationInProgress ? null : _recoverLegacyData,
            ),
            _SettingsTile(
              icon: Icons.sync_outlined,
              title: 'Sincronización',
              subtitle: 'Consultar el estado de la sincronización',
              onTap: _showSyncInfo,
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