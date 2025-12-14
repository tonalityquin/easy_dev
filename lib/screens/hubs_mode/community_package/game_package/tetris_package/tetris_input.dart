// lib/screens/stub_package/game_package/tetris_package/tetris_input.dart
part of '../tetris.dart';

mixin TetrisInputDelegate on _TetrisBase {
  // 키보드 입력 (웹/데스크톱)
  @override
  void handleKey(RawKeyEvent e) {
    if (e is! RawKeyDownEvent) return;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      hardDrop();
    } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      moveH(-1);
    } else if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyD) {
      moveH(1);
    } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) {
      softStart();
      Future.delayed(const Duration(milliseconds: 120), softEnd);
    } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyX) {
      rotateCW();
    } else if (key == LogicalKeyboardKey.keyZ) {
      rotateCCW();
    } else if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.keyC) {
      holdSwap();
    }
  }
}
