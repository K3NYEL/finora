import 'package:flutter/material.dart';

/// Marca de Finora basada en el icono auto_graph_rounded usado en «Acerca de».
class FinoraLogo extends StatelessWidget {
  const FinoraLogo({super.key, this.size = 88});

  final double size;

  static const Color _background = Color(0xFF0F172A);
  static const Color _accent = Color(0xFF38BDF8);

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _background,
          borderRadius: BorderRadius.circular(size * 0.22),
        ),
        child: Center(
          child: Icon(
            Icons.auto_graph_rounded,
            color: _accent,
            size: size * 0.70,
          ),
        ),
      ),
    );
  }
}
