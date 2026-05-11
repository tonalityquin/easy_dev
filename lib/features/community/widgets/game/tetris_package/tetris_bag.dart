import 'dart:math';

import 'tetris_models.dart';

class TetrisBag {
  final Random _random;
  final List<Tetromino> _bag = [];

  TetrisBag({Random? random}) : _random = random ?? Random();

  void clear() {
    _bag.clear();
  }

  Tetromino draw() {
    if (_bag.isEmpty) {
      _bag.addAll(Tetromino.values);
      _bag.shuffle(_random);
    }
    return _bag.removeLast();
  }

  List<Tetromino> snapshot() => List<Tetromino>.of(_bag);

  void restore(List<Tetromino> values) {
    _bag
      ..clear()
      ..addAll(values);
  }
}
