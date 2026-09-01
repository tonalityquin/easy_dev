import 'package:flutter/material.dart';

const Color debugCautionYellow = Color(0xFFFFD400);
const Color debugCautionBlack = Color(0xFF151515);
const Color debugCautionBorder = Color(0xFF050505);

class DebugCautionSurface extends StatelessWidget {
  const DebugCautionSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
    this.borderWidth = 1,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: CustomPaint(
        painter: const _DebugCautionPainter(),
        foregroundPainter: _DebugCautionBorderPainter(
          borderRadius: borderRadius,
          borderWidth: borderWidth,
        ),
        child: child,
      ),
    );
  }
}

class DebugCautionLabel extends StatelessWidget {
  const DebugCautionLabel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: debugCautionBlack.withOpacity(0.94),
        borderRadius: borderRadius,
        border: Border.all(
          color: debugCautionYellow.withOpacity(0.72),
          width: 0.8,
        ),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: debugCautionYellow),
        child: IconTheme.merge(
          data: const IconThemeData(color: debugCautionYellow),
          child: child,
        ),
      ),
    );
  }
}

class _DebugCautionPainter extends CustomPainter {
  const _DebugCautionPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = debugCautionBlack,
    );
    const stripeWidth = 12.0;
    const step = stripeWidth * 2;
    final paint = Paint()..color = debugCautionYellow;
    for (double x = -size.height - step; x < size.width + size.height + step; x += step) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + stripeWidth, size.height)
        ..lineTo(x + stripeWidth + size.height, 0)
        ..lineTo(x + size.height, 0)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DebugCautionBorderPainter extends CustomPainter {
  const _DebugCautionBorderPainter({
    required this.borderRadius,
    required this.borderWidth,
  });

  final BorderRadius borderRadius;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (borderWidth <= 0) return;
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect).deflate(borderWidth / 2);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..color = debugCautionBorder,
    );
  }

  @override
  bool shouldRepaint(covariant _DebugCautionBorderPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
        oldDelegate.borderWidth != borderWidth;
  }
}
