import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'finora_skeleton.dart';

class AsyncValueView<T> extends StatelessWidget {
  final AsyncValue<T> state;
  final Widget Function(T value) data;
  final VoidCallback? onRetry;
  final Widget? loading;

  const AsyncValueView({
    super.key,
    required this.state,
    required this.data,
    this.onRetry,
    this.loading,
  });

  @override
  Widget build(BuildContext context) => state.when(
        loading: () => loading ?? const _DefaultSkeletonLoading(),
        error: (error, _) => _ErrorView(onRetry: onRetry),
        data: data,
      );
}

class _DefaultSkeletonLoading extends StatelessWidget {
  const _DefaultSkeletonLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          SkeletonCard(height: 68),
          SizedBox(height: 8),
          SkeletonCard(height: 68),
        ],
      ),
    );
  }
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
