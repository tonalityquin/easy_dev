// lib/screens/simple_package/simple_inside_package/sections/simple_inside_report_signature_painter.dart

import 'package:flutter/material.dart';

class SignaturePainter extends CustomPainter {
  SignaturePainter({
    required this.points,
    required this.strokeWidth,
    required this.color,
    required this.background,
    required this.overlayName,
    required this.overlayDateText,
  });

  final List<Offset?> points;
  final double strokeWidth;
  final Color color;
  final Color background;
  final String overlayName;
  final String overlayDateText;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = background;
    canvas.drawRect(Offset.zero & size, bg);

    final guide = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    canvas.drawLine(
      const Offset(8, 40),
      Offset(size.width - 8, 40),
      guide,
    );
    canvas.drawLine(
      Offset(8, size.height - 40),
      Offset(size.width - 8, size.height - 40),
      guide,
    );

    final p = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a != null && b != null) {
        canvas.drawLine(a, b, p);
      }
    }

    final hasAny = points.any((e) => e != null);
    if (!hasAny) {
      const hint = TextSpan(
        text: '화면 전체가 서명 영역입니다. 서명을 시작해 주세요.',
        style: TextStyle(color: Colors.black38, fontSize: 14),
      );
      final tp = TextPainter(
        text: hint,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 16);
      tp.paint(
        canvas,
        Offset(
          (size.width - tp.width) / 2,
          (size.height - tp.height) / 2,
        ),
      );
    }

    final overlayTP = TextPainter(
      text: TextSpan(
        text: '서명자: $overlayName   서명일시: $overlayDateText',
        style: const TextStyle(color: Colors.black45, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 16);

    const pad = 8.0;
    final dx = size.width - overlayTP.width - pad;
    final dy = size.height - overlayTP.height - pad;
    overlayTP.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(SignaturePainter old) {
    return old.points != points ||
        old.strokeWidth != strokeWidth ||
        old.color != color ||
        old.background != background ||
        old.overlayName != overlayName ||
        old.overlayDateText != overlayDateText;
  }
}
