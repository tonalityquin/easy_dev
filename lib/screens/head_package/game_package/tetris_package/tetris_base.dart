// lib/screens/stub_package/game_package/tetris_package/tetris_base.dart
part of '../tetris.dart';

/// UI/입력 믹스인이 기대하는 최소한의 표면(interface)
abstract class _TetrisBase extends State<Tetris> {
  // 상태/필드 (getter로 노출)
  bool get isPaused;
  bool get gameOver;
  double get speed;
  int get level;
  int get lines;
  int get score;
  int get highScore;
  List<_Piece> get nextQueue;
  _Piece? get hold;
  List<List<Color?>> get board;
  _Piece? get cur;

  // 보드 상수
  int get kCols;
  int get kVisibleRows;

  // 입력
  FocusNode get focusNode;

  // 조작(명령)
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

  // 키보드 핸들러 (입력 믹스인이 구현)
  void handleKey(RawKeyEvent e);

  // 헬퍼
  List<Point<int>> ghostCells();
}
