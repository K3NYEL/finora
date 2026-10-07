import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AsyncValueView<T> extends StatelessWidget {
  final AsyncValue<T> state;
  final Widget Function(T value) data;
  final VoidCallback? onRetry;

  const AsyncValueView({
    super.key,
    required this.state,
    required this.data,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) => state.when(
        loading: () => const SizedBox(
          height: 72,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => _ErrorView(onRetry: onRetry),
        data: data,
      );
}

class _ErrorView extends StatelessWidget {
  final VoidCallback? onRetry;
  const _ErrorView({this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            const Text('No pudimos cargar estos datos.'),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      );
}
