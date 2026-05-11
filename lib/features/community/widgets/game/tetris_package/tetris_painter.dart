import 'dart:math';

import 'package:flutter/material.dart';

import 'tetris_models.dart';

class TetrisBoardPainter extends CustomPainter {
  final int rows;
  final int cols;
  final List<List<Color?>> board;
  final TetrisPiece? current;
  final List<Point<int>> ghostCells;
  final int boardVersion;

  const TetrisBoardPainter({
    required this.rows,
    required this.cols,
    required this.board,
    required this.current,
    required this.ghostCells,
    required this.boardVersion,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    final cell = min(cellW, cellH);

    final gridPaint = Paint()
      ..color = const Color(0x11000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bg);

    final totalRows = board.length;
    for (int r = totalRows - rows; r < totalRows; r++) {
      final vr = r - (totalRows - rows);
      for (int c = 0; c < cols; c++) {
        final color = board[r][c];
        if (color != null) {
          _drawCell(canvas, vr, c, cell, color);
        }
      }
    }

    for (final p in ghostCells) {
      final r = p.x - (board.length - rows);
      final c = p.y;
      if (r >= 0 && r < rows && c >= 0 && c < cols) {
        _drawCell(canvas, r, c, cell, Colors.black.withOpacity(0.06));
      }
    }

    if (current != null) {
      for (final p in current!.cells) {
        final r = current!.pos.x + p.x - (board.length - rows);
        final c = current!.pos.y + p.y;
        if (r >= 0 && r < rows && c >= 0 && c < cols) {
          _drawCell(canvas, r, c, cell, current!.color);
        }
      }
    }

    for (int r = 0; r <= rows; r++) {
      final y = r * cell;
      canvas.drawLine(Offset(0, y), Offset(cols * cell, y), gridPaint);
    }
    for (int c = 0; c <= cols; c++) {
      final x = c * cell;
      canvas.drawLine(Offset(x, 0), Offset(x, rows * cell), gridPaint);
    }

    canvas.drawRect(Rect.fromLTWH(0, 0, cols * cell, rows * cell), borderPaint);
  }

  void _drawCell(Canvas canvas, int r, int c, double cell, Color color) {
    final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
    final paint = Paint()..color = color;
    canvas.drawRect(rect.deflate(0.5), paint);
    final hl = Paint()..color = Colors.white.withOpacity(0.12);
    canvas.drawRect(rect.deflate(cell * 0.2), hl);
  }

  @override
  bool shouldRepaint(covariant TetrisBoardPainter old) {
    return old.boardVersion != boardVersion || old.current != current || old.ghostCells != ghostCells;
  }
}
