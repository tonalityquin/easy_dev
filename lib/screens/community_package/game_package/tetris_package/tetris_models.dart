// lib/screens/stub_package/game_package/tetris_package/tetris_models.dart
part of '../tetris.dart';

enum _Tetromino { I, O, T, S, Z, J, L }

class _Kick {
  final int dx; // +오른쪽
  final int dy; // +아래
  const _Kick(this.dx, this.dy);
}

class _RotPair {
  final int from;
  final int to;
  const _RotPair(this.from, this.to);

  @override
  bool operator ==(Object other) => other is _RotPair && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

class _PieceTemplate {
  final _Tetromino kind;
  final Color color;
  final List<List<Point<int>>> shapes; // 회전 상태별 셀
  final Map<_RotPair, List<_Kick>> kicks;

  const _PieceTemplate({
    required this.kind,
    required this.color,
    required this.shapes,
    required this.kicks,
  });

  List<Point<int>> shapeAt(int rot) => shapes[rot % shapes.length];

  List<_Kick> kicksFor(int from, int to) => kicks[_RotPair(from, to)] ?? const [_Kick(0, 0)];
}

class _Piece {
  final _PieceTemplate template;
  final int rot; // 0,R,2,L
  final Point<int> pos; // (row, col)

  _Piece({required this.template, required this.rot, required this.pos});

  factory _Piece.fromTemplate(_PieceTemplate t, Point<int> pos) => _Piece(template: t, rot: 0, pos: pos);

  _Piece reset(Point<int> p) => _Piece(template: template, rot: 0, pos: p);

  _Piece moved(Point<int> d) => _Piece(template: template, rot: rot, pos: Point(pos.x + d.x, pos.y + d.y));

  _Piece rotateTo(int r) => _Piece(template: template, rot: r, pos: pos);

  _Tetromino get kind => template.kind;
  Color get color => template.color;
  List<Point<int>> get cells => template.shapeAt(rot);
}

enum _Rot { cw, ccw }
enum _Sfx { move, rotate, soft, hard, hold, line, lock, gameover }
