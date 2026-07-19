import 'package:flutter/material.dart';

class SignaturePainter extends CustomPainter {
  SignaturePainter({
    required this.points,
    required this.strokeWidth,
    required this.color,
    required this.background,
    required this.overlayName,
    required this.overlayDateText,
    required this.guideColor,
    required this.hintColor,
    required this.overlayTextColor,
  });

  final List<Offset?> points;
  final double strokeWidth;
  final Color color;
  final Color background;
  final String overlayName;
  final String overlayDateText;
  final Color guideColor;
  final Color hintColor;
  final Color overlayTextColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    final guide = Paint()
      ..color = guideColor
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

    final stroke = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (int index = 0; index < points.length - 1; index++) {
      final current = points[index];
      final next = points[index + 1];
      if (current != null && next != null) {
        canvas.drawLine(current, next, stroke);
      }
    }

    if (!points.any((point) => point != null)) {
      final hintPainter = TextPainter(
        text: TextSpan(
          text: '화면 전체가 서명 영역입니다. 서명을 시작해 주세요.',
          style: TextStyle(
            color: hintColor,
            fontSize: 14,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 16);
      hintPainter.paint(
        canvas,
        Offset(
          (size.width - hintPainter.width) / 2,
          (size.height - hintPainter.height) / 2,
        ),
      );
    }

    final overlayPainter = TextPainter(
      text: TextSpan(
        text: '서명자: $overlayName   서명일시: $overlayDateText',
        style: TextStyle(
          color: overlayTextColor,
          fontSize: 12,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 16);

    const padding = 8.0;
    overlayPainter.paint(
      canvas,
      Offset(
        size.width - overlayPainter.width - padding,
        size.height - overlayPainter.height - padding,
      ),
    );
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.color != color ||
        oldDelegate.background != background ||
        oldDelegate.overlayName != overlayName ||
        oldDelegate.overlayDateText != overlayDateText ||
        oldDelegate.guideColor != guideColor ||
        oldDelegate.hintColor != hintColor ||
        oldDelegate.overlayTextColor != overlayTextColor;
  }
}
