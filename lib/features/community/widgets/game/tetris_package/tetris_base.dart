import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tetris_models.dart';

abstract class TetrisBase<T extends StatefulWidget> extends State<T> {
  bool get isPaused;
  bool get gameOver;
  bool get embedded;
  double get speed;
  int get level;
  int get lines;
  int get score;
  int get highScore;
  int get combo;
  bool get backToBack;
  int get boardVersion;
  List<TetrisPiece> get nextQueue;
  TetrisPiece? get hold;
  List<List<Color?>> get board;
  TetrisPiece? get cur;

  int get kCols;
  int get kVisibleRows;

  FocusNode get focusNode;

  VoidCallback? get closeHandler;

  void togglePause();
  void startGame();
  void moveH(int dir);
  void rotateCW();
  void rotateCCW();
  void softStart();
  void softEnd();
  void hardDrop();
  void holdSwap();
  void speedUp();
  void speedDown();

  void handleKey(KeyEvent e);

  List<Point<int>> ghostCells();
}
