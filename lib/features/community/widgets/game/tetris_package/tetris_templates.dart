import 'dart:math';

import 'package:flutter/material.dart';

import 'tetris_models.dart';

Map<Tetromino, TetrisPieceTemplate> makeTetrisTemplates() {
  const List<List<Point<int>>> t = [
    [Point(0, 1), Point(1, 0), Point(1, 1), Point(1, 2)],
    [Point(0, 1), Point(1, 1), Point(2, 1), Point(1, 2)],
    [Point(1, 0), Point(1, 1), Point(1, 2), Point(2, 1)],
    [Point(0, 1), Point(1, 1), Point(2, 1), Point(1, 0)],
  ];

  const List<List<Point<int>>> j = [
    [Point(0, 0), Point(1, 0), Point(2, 0), Point(2, 1)],
    [Point(1, 0), Point(1, 1), Point(1, 2), Point(0, 2)],
    [Point(0, 0), Point(0, 1), Point(1, 1), Point(2, 1)],
    [Point(1, 0), Point(1, 1), Point(1, 2), Point(2, 0)],
  ];

  const List<List<Point<int>>> l = [
    [Point(0, 1), Point(1, 1), Point(2, 1), Point(2, 0)],
    [Point(1, 0), Point(1, 1), Point(1, 2), Point(2, 2)],
    [Point(0, 0), Point(0, 1), Point(1, 0), Point(2, 0)],
    [Point(0, 0), Point(1, 0), Point(1, 1), Point(1, 2)],
  ];

  const List<List<Point<int>>> s = [
    [Point(0, 1), Point(0, 2), Point(1, 0), Point(1, 1)],
    [Point(0, 0), Point(1, 0), Point(1, 1), Point(2, 1)],
    [Point(1, 1), Point(1, 2), Point(2, 0), Point(2, 1)],
    [Point(0, 1), Point(1, 1), Point(1, 2), Point(2, 2)],
  ];

  const List<List<Point<int>>> z = [
    [Point(0, 0), Point(0, 1), Point(1, 1), Point(1, 2)],
    [Point(0, 1), Point(1, 0), Point(1, 1), Point(2, 0)],
    [Point(1, 0), Point(1, 1), Point(2, 1), Point(2, 2)],
    [Point(0, 2), Point(1, 1), Point(1, 2), Point(2, 1)],
  ];

  const List<List<Point<int>>> o = [
    [Point(0, 0), Point(0, 1), Point(1, 0), Point(1, 1)],
  ];

  const List<List<Point<int>>> i = [
    [Point(1, 0), Point(1, 1), Point(1, 2), Point(1, 3)],
    [Point(0, 2), Point(1, 2), Point(2, 2), Point(3, 2)],
    [Point(2, 0), Point(2, 1), Point(2, 2), Point(2, 3)],
    [Point(0, 1), Point(1, 1), Point(2, 1), Point(3, 1)],
  ];

  final Map<TetrisRotationPair, List<TetrisKick>> jlstzKicks = {
    TetrisRotationPair(0, 1): [TetrisKick(0, 0), TetrisKick(-1, 0), TetrisKick(-1, -1), TetrisKick(0, 2), TetrisKick(-1, 2)],
    TetrisRotationPair(1, 0): [TetrisKick(0, 0), TetrisKick(1, 0), TetrisKick(1, 1), TetrisKick(0, -2), TetrisKick(1, -2)],
    TetrisRotationPair(1, 2): [TetrisKick(0, 0), TetrisKick(1, 0), TetrisKick(1, 1), TetrisKick(0, -2), TetrisKick(1, -2)],
    TetrisRotationPair(2, 1): [TetrisKick(0, 0), TetrisKick(-1, 0), TetrisKick(-1, -1), TetrisKick(0, 2), TetrisKick(-1, 2)],
    TetrisRotationPair(2, 3): [TetrisKick(0, 0), TetrisKick(1, 0), TetrisKick(1, -1), TetrisKick(0, 2), TetrisKick(1, 2)],
    TetrisRotationPair(3, 2): [TetrisKick(0, 0), TetrisKick(-1, 0), TetrisKick(-1, 1), TetrisKick(0, -2), TetrisKick(-1, -2)],
    TetrisRotationPair(3, 0): [TetrisKick(0, 0), TetrisKick(-1, 0), TetrisKick(-1, 1), TetrisKick(0, -2), TetrisKick(-1, -2)],
    TetrisRotationPair(0, 3): [TetrisKick(0, 0), TetrisKick(1, 0), TetrisKick(1, -1), TetrisKick(0, 2), TetrisKick(1, 2)],
  };

  final Map<TetrisRotationPair, List<TetrisKick>> iKicks = {
    TetrisRotationPair(0, 1): [TetrisKick(0, 0), TetrisKick(-2, 0), TetrisKick(1, 0), TetrisKick(-2, -1), TetrisKick(1, 2)],
    TetrisRotationPair(1, 0): [TetrisKick(0, 0), TetrisKick(2, 0), TetrisKick(-1, 0), TetrisKick(2, 1), TetrisKick(-1, -2)],
    TetrisRotationPair(1, 2): [TetrisKick(0, 0), TetrisKick(-1, 0), TetrisKick(2, 0), TetrisKick(-1, 2), TetrisKick(2, -1)],
    TetrisRotationPair(2, 1): [TetrisKick(0, 0), TetrisKick(1, 0), TetrisKick(-2, 0), TetrisKick(1, -2), TetrisKick(-2, 1)],
    TetrisRotationPair(2, 3): [TetrisKick(0, 0), TetrisKick(2, 0), TetrisKick(-1, 0), TetrisKick(2, 1), TetrisKick(-1, -2)],
    TetrisRotationPair(3, 2): [TetrisKick(0, 0), TetrisKick(-2, 0), TetrisKick(1, 0), TetrisKick(-2, -1), TetrisKick(1, 2)],
    TetrisRotationPair(3, 0): [TetrisKick(0, 0), TetrisKick(1, 0), TetrisKick(-2, 0), TetrisKick(1, -2), TetrisKick(-2, 1)],
    TetrisRotationPair(0, 3): [TetrisKick(0, 0), TetrisKick(-1, 0), TetrisKick(2, 0), TetrisKick(-1, 2), TetrisKick(2, -1)],
  };

  return {
    Tetromino.T: TetrisPieceTemplate(kind: Tetromino.T, color: Colors.purple, spawnPosition: Point(-1, 3), shapes: t, kicks: jlstzKicks),
    Tetromino.J: TetrisPieceTemplate(kind: Tetromino.J, color: Colors.blue, spawnPosition: Point(-1, 3), shapes: j, kicks: jlstzKicks),
    Tetromino.L: TetrisPieceTemplate(kind: Tetromino.L, color: Colors.orange, spawnPosition: Point(-1, 3), shapes: l, kicks: jlstzKicks),
    Tetromino.S: TetrisPieceTemplate(kind: Tetromino.S, color: Colors.green, spawnPosition: Point(-1, 3), shapes: s, kicks: jlstzKicks),
    Tetromino.Z: TetrisPieceTemplate(kind: Tetromino.Z, color: Colors.red, spawnPosition: Point(-1, 3), shapes: z, kicks: jlstzKicks),
    Tetromino.O: TetrisPieceTemplate(kind: Tetromino.O, color: Colors.yellow, spawnPosition: Point(-1, 4), shapes: o, kicks: {TetrisRotationPair(0, 0): [TetrisKick(0, 0)]}),
    Tetromino.I: TetrisPieceTemplate(kind: Tetromino.I, color: Colors.cyan, spawnPosition: Point(-2, 3), shapes: i, kicks: iKicks),
  };
}
