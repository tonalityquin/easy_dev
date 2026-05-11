import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tetris_base.dart';

mixin TetrisInputDelegate<T extends StatefulWidget> on TetrisBase<T> {
  static const Duration _das = Duration(milliseconds: 140);
  static const Duration _arr = Duration(milliseconds: 35);

  Timer? _dasTimer;
  Timer? _arrTimer;
  int? _heldHorizontalDir;
  bool _softHeld = false;

  @override
  void handleKey(KeyEvent e) {
    final key = e.logicalKey;

    if (e is KeyUpEvent) {
      if ((key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) && _heldHorizontalDir == -1) {
        _stopHorizontalRepeat();
      } else if ((key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyD) && _heldHorizontalDir == 1) {
        _stopHorizontalRepeat();
      } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) {
        _stopSoftDrop();
      }
      return;
    }

    if (e is! KeyDownEvent) return;

    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      _startHorizontalRepeat(-1);
    } else if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyD) {
      _startHorizontalRepeat(1);
    } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) {
      _startSoftDrop();
    } else if (key == LogicalKeyboardKey.space) {
      hardDrop();
    } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyX) {
      rotateCW();
    } else if (key == LogicalKeyboardKey.keyZ) {
      rotateCCW();
    } else if (key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight || key == LogicalKeyboardKey.keyC) {
      holdSwap();
    }
  }

  void _startHorizontalRepeat(int dir) {
    if (_heldHorizontalDir == dir) return;
    _stopHorizontalRepeat();
    _heldHorizontalDir = dir;
    moveH(dir);
    _dasTimer = Timer(_das, () {
      _arrTimer = Timer.periodic(_arr, (_) => moveH(dir));
    });
  }

  void _stopHorizontalRepeat() {
    _dasTimer?.cancel();
    _arrTimer?.cancel();
    _dasTimer = null;
    _arrTimer = null;
    _heldHorizontalDir = null;
  }

  void _startSoftDrop() {
    if (_softHeld) return;
    _softHeld = true;
    softStart();
  }

  void _stopSoftDrop() {
    if (!_softHeld) return;
    _softHeld = false;
    softEnd();
  }

  void cancelInputTimers() {
    _stopHorizontalRepeat();
    _stopSoftDrop();
  }
}
