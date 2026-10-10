import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'finora_skeleton.dart';

class AsyncValueView<T> extends StatefulWidget {
  final AsyncValue<T> state;
  final Widget Function(T value) data;
  final VoidCallback? onRetry;
  final Widget? loading;
  final Duration minimumSkeletonDuration;

  const AsyncValueView({
    super.key,
    required this.state,
    required this.data,
    this.onRetry,
    this.loading,
    this.minimumSkeletonDuration = const Duration(milliseconds: 450),
  });

  @override
  State<AsyncValueView<T>> createState() => _AsyncValueViewState<T>();
}

class _AsyncValueViewState<T> extends State<AsyncValueView<T>> {
  Timer? _minimumTimer;
  bool _holdSkeleton = false;

  @override
  void initState() {
    super.initState();
    if (widget.state.isLoading) _startMinimumSkeleton();
  }

  @override
  void didUpdateWidget(covariant AsyncValueView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.isLoading && !oldWidget.state.isLoading) {
      _startMinimumSkeleton();
    }
  }

  void _startMinimumSkeleton() {
    _minimumTimer?.cancel();
    _holdSkeleton = true;
    _minimumTimer = Timer(widget.minimumSkeletonDuration, () {
      if (mounted) setState(() => _holdSkeleton = false);
    });
  }

  @override
  void dispose() {
    _minimumTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_holdSkeleton || widget.state.isLoading) {
      return widget.loading ?? const _DefaultSkeletonLoading();
    }

    return widget.state.when(
      loading: () => widget.loading ?? const _DefaultSkeletonLoading(),
      error: (error, _) => _ErrorView(onRetry: widget.onRetry),
      data: widget.data,
    );
  }
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
