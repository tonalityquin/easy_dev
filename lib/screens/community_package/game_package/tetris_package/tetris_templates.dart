// lib/screens/stub_package/game_package/tetris_package/tetris_templates.dart
part of '../tetris.dart';

Map<_Tetromino, _PieceTemplate> _makeTemplates() {
  List<List<Point<int>>> T = [
    [const Point(0, 1), const Point(1, 0), const Point(1, 1), const Point(1, 2)],
    [const Point(0, 1), const Point(1, 1), const Point(2, 1), const Point(1, 2)],
    [const Point(1, 0), const Point(1, 1), const Point(1, 2), const Point(2, 1)],
    [const Point(0, 1), const Point(1, 1), const Point(2, 1), const Point(1, 0)],
  ];
  List<List<Point<int>>> J = [
    [const Point(0, 0), const Point(1, 0), const Point(2, 0), const Point(2, 1)],
    [const Point(1, 0), const Point(1, 1), const Point(1, 2), const Point(0, 2)],
    [const Point(0, 0), const Point(0, 1), const Point(1, 1), const Point(2, 1)],
    [const Point(1, 0), const Point(1, 1), const Point(1, 2), const Point(2, 0)],
  ];
  List<List<Point<int>>> L = [
    [const Point(0, 1), const Point(1, 1), const Point(2, 1), const Point(2, 0)],
    [const Point(1, 0), const Point(1, 1), const Point(1, 2), const Point(2, 2)],
    [const Point(0, 0), const Point(0, 1), const Point(1, 0), const Point(2, 0)],
    [const Point(0, 0), const Point(1, 0), const Point(1, 1), const Point(1, 2)],
  ];
  List<List<Point<int>>> S = [
    [const Point(0, 1), const Point(0, 2), const Point(1, 0), const Point(1, 1)],
    [const Point(0, 0), const Point(1, 0), const Point(1, 1), const Point(2, 1)],
  ];
  List<List<Point<int>>> Z = [
    [const Point(0, 0), const Point(0, 1), const Point(1, 1), const Point(1, 2)],
    [const Point(0, 1), const Point(1, 0), const Point(1, 1), const Point(2, 0)],
  ];
  List<List<Point<int>>> O = [
    [const Point(0, 0), const Point(0, 1), const Point(1, 0), const Point(1, 1)],
  ];
  List<List<Point<int>>> I = [
    [const Point(0, 0), const Point(0, 1), const Point(0, 2), const Point(0, 3)],
    [const Point(0, 1), const Point(1, 1), const Point(2, 1), const Point(3, 1)],
  ];

  // 정식 SRS 킥 오프셋 — JLSTZ
  final Map<_RotPair, List<_Kick>> jlstzKicks = {
    const _RotPair(0, 1): [_Kick(0, 0), _Kick(-1, 0), _Kick(-1, -1), _Kick(0, 2), _Kick(-1, 2)],
    const _RotPair(1, 0): [_Kick(0, 0), _Kick(1, 0), _Kick(1, 1), _Kick(0, -2), _Kick(1, -2)],
    const _RotPair(1, 2): [_Kick(0, 0), _Kick(1, 0), _Kick(1, 1), _Kick(0, -2), _Kick(1, -2)],
    const _RotPair(2, 1): [_Kick(0, 0), _Kick(-1, 0), _Kick(-1, -1), _Kick(0, 2), _Kick(-1, 2)],
    const _RotPair(2, 3): [_Kick(0, 0), _Kick(1, 0), _Kick(1, -1), _Kick(0, 2), _Kick(1, 2)],
    const _RotPair(3, 2): [_Kick(0, 0), _Kick(-1, 0), _Kick(-1, 1), _Kick(0, -2), _Kick(-1, -2)],
    const _RotPair(3, 0): [_Kick(0, 0), _Kick(-1, 0), _Kick(-1, 1), _Kick(0, -2), _Kick(-1, -2)],
    const _RotPair(0, 3): [_Kick(0, 0), _Kick(1, 0), _Kick(1, -1), _Kick(0, 2), _Kick(1, 2)],
  };

  // 정식 SRS 킥 오프셋 — I
  final Map<_RotPair, List<_Kick>> iKicks = {
    const _RotPair(0, 1): [_Kick(0, 0), _Kick(-2, 0), _Kick(1, 0), _Kick(-2, -1), _Kick(1, 2)],
    const _RotPair(1, 0): [_Kick(0, 0), _Kick(2, 0), _Kick(-1, 0), _Kick(2, 1), _Kick(-1, -2)],
    const _RotPair(1, 2): [_Kick(0, 0), _Kick(-1, 0), _Kick(2, 0), _Kick(-1, 2), _Kick(2, -1)],
    const _RotPair(2, 1): [_Kick(0, 0), _Kick(1, 0), _Kick(-2, 0), _Kick(1, -2), _Kick(-2, 1)],
    const _RotPair(2, 3): [_Kick(0, 0), _Kick(2, 0), _Kick(-1, 0), _Kick(2, 1), _Kick(-1, -2)],
    const _RotPair(3, 2): [_Kick(0, 0), _Kick(-2, 0), _Kick(1, 0), _Kick(-2, -1), _Kick(1, 2)],
    const _RotPair(3, 0): [_Kick(0, 0), _Kick(1, 0), _Kick(-2, 0), _Kick(1, -2), _Kick(-2, 1)],
    const _RotPair(0, 3): [_Kick(0, 0), _Kick(-1, 0), _Kick(2, 0), _Kick(-1, 2), _Kick(2, -1)],
  };

  return {
    _Tetromino.T: _PieceTemplate(kind: _Tetromino.T, color: Colors.purple, shapes: T, kicks: jlstzKicks),
    _Tetromino.J: _PieceTemplate(kind: _Tetromino.J, color: Colors.blue, shapes: J, kicks: jlstzKicks),
    _Tetromino.L: _PieceTemplate(kind: _Tetromino.L, color: Colors.orange, shapes: L, kicks: jlstzKicks),
    _Tetromino.S: _PieceTemplate(kind: _Tetromino.S, color: Colors.green, shapes: S, kicks: jlstzKicks),
    _Tetromino.Z: _PieceTemplate(kind: _Tetromino.Z, color: Colors.red, shapes: Z, kicks: jlstzKicks),
    _Tetromino.O: _PieceTemplate(
      kind: _Tetromino.O, color: Colors.yellow, shapes: O, kicks: {
      const _RotPair(0, 1): [_Kick(0, 0)],
      const _RotPair(1, 2): [_Kick(0, 0)],
      const _RotPair(2, 3): [_Kick(0, 0)],
      const _RotPair(3, 0): [_Kick(0, 0)],
      const _RotPair(1, 0): [_Kick(0, 0)],
      const _RotPair(2, 1): [_Kick(0, 0)],
      const _RotPair(3, 2): [_Kick(0, 0)],
      const _RotPair(0, 3): [_Kick(0, 0)],
    },
    ),
    _Tetromino.I: _PieceTemplate(kind: _Tetromino.I, color: Colors.cyan, shapes: I, kicks: iKicks),
  };
}
