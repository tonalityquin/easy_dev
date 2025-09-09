part of '../minesweeper.dart';

enum _Difficulty { easy, normal, hard }

class _Cell {
  bool mine = false;
  bool open = false;
  bool flag = false;
  int adj = 0;
}
