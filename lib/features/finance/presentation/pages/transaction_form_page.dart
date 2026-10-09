import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/amount_parser.dart';
import '../../../../shared/widgets/async_state_view.dart';
import '../providers.dart';

class TransactionFormPage extends ConsumerStatefulWidget {
  final String kind; // income | expense | transfer
  const TransactionFormPage({super.key, required this.kind});
  @override
  ConsumerState<TransactionFormPage> createState() => _State();
}

class _State extends ConsumerState<TransactionFormPage> {
  final _amount = TextEditingController(), _desc = TextEditingController();
  int? _acc, _dest, _cat;
  bool _busy = false;
  bool get _isTransfer => widget.kind == 'transfer';

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final repo = ref.read(repoProvider);
    final amount = parseAmount(_amount.text) ?? 0;
    String? error;
    try {
      if (_acc == null) throw const AppException('Elige una cuenta.');
      if (amount <= 0) {
        throw const AppException('Escribe un monto válido mayor que cero.');
      }
      if (_isTransfer) {
        if (_dest == null) throw const AppException('Elige la cuenta destino.');
        await repo.addTransfer(_acc!, _dest!, amount, _desc.text);
      } else {
        await repo.addTransaction(
          accountId: _acc!,
          categoryId: _cat,
          type: widget.kind,
          amount: amount,
          description: _desc.text,
        );
      }
    } on AppException catch (e) {
      error = e.message;
    } catch (e) {
      debugPrint('Error al guardar: $e');
      error = 'No pudimos guardar el movimiento. Inténtalo nuevamente.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    refreshTransactions(ref);
    context.pop();
  }

  Widget _drop(String label, int? value, List<DropdownMenuItem<int>> items,
          ValueChanged<int?> on) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<int>(
          initialValue: value,
          items: items,
          onChanged: on,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final accountsState = ref.watch(accountsProvider);
    final categoriesState =
        _isTransfer ? null : ref.watch(categoriesProvider(widget.kind));
    if (accountsState.hasError) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: AsyncStateView(
          error: accountsState.error,
          onRetry: () => ref.invalidate(accountsProvider),
        ),
      );
    }
    if (categoriesState?.hasError ?? false) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: AsyncStateView(
          error: categoriesState!.error,
          onRetry: () => ref.invalidate(categoriesProvider(widget.kind)),
        ),
      );
    }
    if (accountsState.isLoading || (categoriesState?.isLoading ?? false)) {
      return const Scaffold(body: AsyncStateView());
    }

    final accounts = accountsState.value ?? [];
    final categories = categoriesState?.value ?? [];
    final accountItems = [
      for (final account in accounts)
        DropdownMenuItem(value: account.id, child: Text(account.name)),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: Theme.of(context).textTheme.headlineMedium,
            decoration: const InputDecoration(labelText: 'Monto (RD$)'),
          ),
          const SizedBox(height: 12),
          _drop(
            _isTransfer ? 'Cuenta origen' : 'Cuenta',
            _acc,
            accountItems,
            (value) => setState(() => _acc = value),
          ),
          if (_isTransfer)
            _drop(
              'Cuenta destino',
              _dest,
              accountItems,
              (value) => setState(() => _dest = value),
            ),
          if (!_isTransfer)
            _drop(
              'Categoría',
              _cat,
              [
                for (final category in categories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              (value) => setState(() => _cat = value),
            ),
          TextField(
            controller: _desc,
            decoration:
                const InputDecoration(labelText: 'Descripción (opcional)'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar'),
            ),
          ),
        ],
      ),
    );
  }

  String get _title => {
        'income': 'Nuevo ingreso',
        'expense': 'Nuevo gasto',
        'transfer': 'Transferencia',
      }[widget.kind]!;
}
