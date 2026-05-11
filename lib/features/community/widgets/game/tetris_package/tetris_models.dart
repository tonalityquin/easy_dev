import 'dart:math';

import 'package:flutter/material.dart';

enum Tetromino { I, O, T, S, Z, J, L }

enum TetrisRotation { cw, ccw }

enum TetrisSfx { move, rotate, soft, hard, hold, line, lock, gameover }

class TetrisKick {
  final int dx;
  final int dy;

  const TetrisKick(this.dx, this.dy);
}

class TetrisRotationPair {
  final int from;
  final int to;

  const TetrisRotationPair(this.from, this.to);

  @override
  bool operator ==(Object other) => other is TetrisRotationPair && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

class TetrisPieceTemplate {
  final Tetromino kind;
  final Color color;
  final Point<int> spawnPosition;
  final List<List<Point<int>>> shapes;
  final Map<TetrisRotationPair, List<TetrisKick>> kicks;

  const TetrisPieceTemplate({
    required this.kind,
    required this.color,
    required this.spawnPosition,
    required this.shapes,
    required this.kicks,
  });

  List<Point<int>> shapeAt(int rot) => shapes[rot % shapes.length];

  List<TetrisKick> kicksFor(int from, int to) => kicks[TetrisRotationPair(from, to)] ?? const [TetrisKick(0, 0)];
}

class TetrisPiece {
  final TetrisPieceTemplate template;
  final int rot;
  final Point<int> pos;

  const TetrisPiece({
    required this.template,
    required this.rot,
    required this.pos,
  });

  factory TetrisPiece.fromTemplate(TetrisPieceTemplate t) => TetrisPiece(template: t, rot: 0, pos: t.spawnPosition);

  TetrisPiece reset() => TetrisPiece(template: template, rot: 0, pos: template.spawnPosition);

  TetrisPiece moved(Point<int> d) => TetrisPiece(template: template, rot: rot, pos: Point(pos.x + d.x, pos.y + d.y));

  TetrisPiece rotateTo(int r) => TetrisPiece(template: template, rot: r, pos: pos);

  Tetromino get kind => template.kind;

  Color get color => template.color;

  List<Point<int>> get cells => template.shapeAt(rot);
}
