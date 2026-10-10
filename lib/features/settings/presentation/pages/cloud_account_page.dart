import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/network/finora_remote_auth_api.dart';
import '../../../../core/network/finora_remote_session_storage.dart';

class CloudAccountPage extends StatefulWidget {
  const CloudAccountPage({super.key});

  @override
  State<CloudAccountPage> createState() => _CloudAccountPageState();
}

class _CloudAccountPageState extends State<CloudAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _sessionRepository = FinoraRemoteSessionRepository(
    SecureRemoteSessionStorage(),
  );

  FinoraRemoteSession? _session;
  bool _loading = true;
  bool _submitting = false;
  bool _creatingAccount = false;
  bool _consentGiven = false;
  bool _obscurePassword = true;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      final session = await _sessionRepository.load();
      if (!mounted) return;
      setState(() {
        _session = session;
        _loading = false;
        if (session != null) _usernameController.text = session.user.username;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMessage = 'No se pudo leer la sesión segura de este dispositivo.';
        _statusIsError = true;
      });
    }
  }

  Future<void> _linkAccount() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    if (!_consentGiven) {
      setState(() {
        _statusMessage = 'Confirma que entiendes qué hace y qué no hace esta vinculación.';
        _statusIsError = true;
      });
      return;
    }
    if (!FinoraApiConfig.isConfigured) {
      setState(() {
        _statusMessage = 'El servidor remoto aún no está configurado en esta versión de Finora. No se enviaron credenciales.';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _statusMessage = null;
    });
    final api = FinoraRemoteAuthApi(FinoraApiClient());
    try {
      final session = _creatingAccount
          ? await api.register(
              username: _usernameController.text,
              password: _passwordController.text,
            )
          : await api.login(
              username: _usernameController.text,
              password: _passwordController.text,
            );
      await _sessionRepository.save(session);
      if (!mounted) return;
      setState(() {
        _session = session;
        _passwordController.clear();
        _statusMessage = 'Cuenta remota vinculada. Tus datos financieros siguen únicamente en este dispositivo; la sincronización aún no está activada.';
        _statusIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = error.toString().replaceFirst('Exception: ', '');
        _statusIsError = true;
      });
    } finally {
      api.close();
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _unlinkAccount() async {
    final session = _session;
    if (session == null || _submitting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desvincular cuenta remota'),
        content: const Text(
          'Se eliminará de este dispositivo la sesión remota guardada. '
          'Tus cuentas y movimientos locales no se borrarán. La sincronización '
          'no está activada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
      _statusMessage = null;
    });
    final api = FinoraRemoteAuthApi(FinoraApiClient());
    var serverLogoutSucceeded = false;
    try {
      if (FinoraApiConfig.isConfigured) {
        try {
          await api.logout(bearerToken: session.accessToken);
          serverLogoutSucceeded = true;
        } catch (_) {
          // Always clear local credentials even if the server is unavailable.
        }
      }
      await _sessionRepository.clear();
      if (!mounted) return;
      setState(() {
        _session = null;
        _consentGiven = false;
        _passwordController.clear();
        _statusMessage = serverLogoutSucceeded
            ? 'Cuenta desvinculada. Tus datos locales se conservaron.'
            : 'Sesión eliminada de este dispositivo. No se pudo confirmar el cierre remoto; revisa esa sesión cuando el servidor esté disponible.';
        _statusIsError = !serverLogoutSucceeded;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'No se pudo borrar la sesión segura. La cuenta sigue vinculada en este dispositivo.';
        _statusIsError = true;
      });
    } finally {
      api.close();
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Vincular cuenta'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.cloud_sync_outlined, size: 34, color: colors.primary),
                        const SizedBox(height: 12),
                        Text(
                          _session == null ? 'Conecta tu cuenta Finora' : 'Cuenta remota vinculada',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _session == null
                              ? 'Inicia sesión o crea una cuenta remota para preparar la futura sincronización entre dispositivos.'
                              : 'Conectada como ${_session!.user.username}. La sesión se guarda en el almacenamiento seguro del sistema.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.shield_outlined),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Tus finanzas no se subirán al vincular la cuenta.',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Esta pantalla solo inicia sesión y guarda la sesión remota de forma segura. '
                            'No copia cuentas, categorías, presupuestos ni movimientos. La sincronización '
                            'seguirá desactivada hasta completar y probar esa función por separado.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_session == null) ...[
                    const SizedBox(height: 20),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('Iniciar sesión'),
                          icon: Icon(Icons.login_rounded),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('Crear cuenta'),
                          icon: Icon(Icons.person_add_alt_1_rounded),
                        ),
                      ],
                      selected: {_creatingAccount},
                      onSelectionChanged: _submitting
                          ? null
                          : (selection) => setState(() {
                                _creatingAccount = selection.first;
                                _statusMessage = null;
                              }),
                    ),
                    const SizedBox(height: 16),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _usernameController,
                            enabled: !_submitting,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            textCapitalization: TextCapitalization.none,
                            decoration: const InputDecoration(
                              labelText: 'Usuario remoto',
                              hintText: 'usuario.finora',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final username = (value ?? '').trim().toLowerCase();
                              if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$').hasMatch(username)) {
                                return 'Usa entre 3 y 32 caracteres: letras, números, punto, guion o guion bajo.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            enabled: !_submitting,
                            obscureText: _obscurePassword,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: 'Contraseña remota',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword ? 'Mostrar contraseña' : 'Ocultar contraseña',
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              ),
                            ),
                            validator: (value) {
                              final password = value ?? '';
                              if (password.length < 12 || password.length > 128) {
                                return 'La contraseña debe tener entre 12 y 128 caracteres.';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _linkAccount(),
                          ),
                          const SizedBox(height: 14),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _consentGiven,
                            onChanged: _submitting
                                ? null
                                : (value) => setState(() => _consentGiven = value ?? false),
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('Entiendo y acepto la vinculación de la cuenta remota.'),
                            subtitle: const Text(
                              'Esto no autoriza a subir ni sincronizar mis datos financieros.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _submitting ? null : _linkAccount,
                              icon: _submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Icon(_creatingAccount ? Icons.person_add_alt_1_rounded : Icons.login_rounded),
                              label: Text(
                                _submitting
                                    ? 'Conectando…'
                                    : _creatingAccount
                                        ? 'Crear y vincular cuenta'
                                        : 'Vincular cuenta',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _submitting ? null : _unlinkAccount,
                      icon: const Icon(Icons.link_off_rounded),
                      label: const Text('Desvincular cuenta remota'),
                    ),
                  ],
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (_statusIsError ? colors.errorContainer : colors.primaryContainer).withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          color: _statusIsError ? colors.onErrorContainer : colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                  if (!FinoraApiConfig.isConfigured) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Estado técnico: el endpoint de la API no está configurado en esta compilación. '
                      'La vinculación permanecerá bloqueada hasta configurar y validar un servidor HTTPS.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
