import 'package:flutter/material.dart';

class UserStatementSignaturePainter extends CustomPainter {
  UserStatementSignaturePainter({
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
    
    final bg = Paint()..color = background;
    canvas.drawRect(Offset.zero & size, bg);

    
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
      final hint = TextSpan(
        text: '화면 전체가 서명 영역입니다. 서명을 시작해 주세요.',
        style: TextStyle(
          color: hintColor,
          fontSize: 14,
        ),
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
        style: TextStyle(
          color: overlayTextColor,
          fontSize: 12,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 16);

    const pad = 8.0;
    final dx = size.width - overlayTP.width - pad;
    final dy = size.height - overlayTP.height - pad;
    overlayTP.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(UserStatementSignaturePainter old) {
    return old.points != points ||
        old.strokeWidth != strokeWidth ||
        old.color != color ||
        old.background != background ||
        old.overlayName != overlayName ||
        old.overlayDateText != overlayDateText ||
        old.guideColor != guideColor ||
        old.hintColor != hintColor ||
        old.overlayTextColor != overlayTextColor;
  }
}
