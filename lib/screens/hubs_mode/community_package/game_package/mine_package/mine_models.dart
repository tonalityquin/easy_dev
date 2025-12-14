import 'dart:math';

enum GameStatus { ready, generating, playing, won, lost }

class Difficulty {
  final String key;
  final String name;
  final int rows;
  final int cols;
  final int mines;
  const Difficulty({
    required this.key,
    required this.name,
    required this.rows,
    required this.cols,
    required this.mines,
  });
}

class Difficulties {
  static const beginner     = Difficulty(key: 'beg', name: 'Beginner',     rows: 9,  cols: 9,  mines: 10);
  static const intermediate = Difficulty(key: 'int', name: 'Intermediate', rows: 16, cols: 16, mines: 40);
  static const expert       = Difficulty(key: 'exp', name: 'Expert',       rows: 16, cols: 30, mines: 99);

  static const all = <Difficulty>[beginner, intermediate, expert];
}

class Cell {
  bool mine;
  bool open;
  bool flagged;
  bool exploded;
  int adj;

  Cell({
    this.mine = false,
    this.open = false,
    this.flagged = false,
    this.exploded = false,
    this.adj = 0,
  });

  Cell copy() => Cell(mine: mine, open: open, flagged: flagged, exploded: exploded, adj: adj);
}

Iterable<Point<int>> neighbors(int r, int c, int rows, int cols) sync* {
  for (int dr = -1; dr <= 1; dr++) {
    for (int dc = -1; dc <= 1; dc++) {
      if (dr == 0 && dc == 0) continue;
      final nr = r + dr, nc = c + dc;
      if (nr >= 0 && nr < rows && nc >= 0 && nc < cols) yield Point(nr, nc);
    }
  }
}

bool in3x3(int r, int c, int sr, int sc) => (r - sr).abs() <= 1 && (c - sc).abs() <= 1;
