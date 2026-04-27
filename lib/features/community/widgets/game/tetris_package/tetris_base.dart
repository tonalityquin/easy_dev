
part of '../tetris.dart';


abstract class _TetrisBase extends State<Tetris> {
  
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

  
  int get kCols;
  int get kVisibleRows;

  
  FocusNode get focusNode;

  
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

  
  void handleKey(RawKeyEvent e);

  
  List<Point<int>> ghostCells();
}
