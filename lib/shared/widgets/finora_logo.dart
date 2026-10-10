import 'package:flutter/material.dart';

/// Identidad visual de Finora: fondo azul noche, barras y flecha ascendente.
/// Mantiene el mismo símbolo que el icono nativo de Android (ic_finora.xml).
class FinoraLogo extends StatelessWidget {
  const FinoraLogo({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _FinoraLogoPainter(),
      ),
    );
  }
}

class _FinoraLogoPainter extends CustomPainter {
  static const _background = Color(0xFF0F172A);
  static const _accent = Color(0xFF38BDF8);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 108, size.height / 108);

    final backgroundPaint = Paint()..color = _background;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 108, 108),
        const Radius.circular(24),
      ),
      backgroundPaint,
    );

    final accentPaint = Paint()
      ..color = _accent
      ..style = PaintingStyle.fill;

    // Three ascending bars.
    canvas.drawRect(const Rect.fromLTWH(12, 68, 20, 28), accentPaint);
    canvas.drawRect(const Rect.fromLTWH(38, 48, 20, 48), accentPaint);
    canvas.drawRect(const Rect.fromLTWH(64, 28, 20, 68), accentPaint);

    // Rising arrow, matching the native Android launcher vector.
    final arrow = Path()
      ..moveTo(14, 47)
      ..lineTo(40, 28)
      ..lineTo(55, 37)
      ..lineTo(82, 10)
      ..lineTo(98, 10)
      ..lineTo(98, 26)
      ..lineTo(56, 66)
      ..lineTo(41, 57)
      ..lineTo(24, 70)
      ..close();
    canvas.drawPath(arrow, accentPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FinoraLogoPainter oldDelegate) => false;
}
