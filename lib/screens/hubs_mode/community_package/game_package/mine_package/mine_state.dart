import 'dart:collection';
import 'dart:math';
import 'mine_models.dart';

/// 순수 보드 로직 (Flutter 비의존)
class BoardLogic {
  final int rows;
  final int cols;
  final int mines;

  late List<List<Cell>> _g;
  bool _hasMines = false;
  bool exploded = false;

  BoardLogic({required this.rows, required this.cols, required this.mines}) {
    _g = List.generate(rows, (_) => List.generate(cols, (_) => Cell()));
  }

  bool get hasMines => _hasMines;
  Cell cell(int r, int c) => _g[r][c];

  int get flagCount {
    int f = 0;
    for (var row in _g) {
      for (var s in row) {
        if (s.flagged) f++;
      }
    }
    return f;
  }

  bool get allSafeOpened {
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final s = _g[r][c];
        if (!s.mine && !s.open) return false;
      }
    }
    return true;
  }

  void inject({required List<List<bool>> mine, required List<List<int>> adj}) {
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final s = _g[r][c];
        s.mine = mine[r][c];
        s.adj = adj[r][c];
        s.open = false;
        s.flagged = false;
        s.exploded = false;
      }
    }
    _hasMines = true;
    exploded = false;
  }

  /// 3×3 제외 랜덤 배치 (폴백)
  void placeRandomMinesExcluding3x3(int sr, int sc, {int? seed}) {
    final rnd = seed == null ? Random() : Random(seed);
    int placed = 0;
    while (placed < mines) {
      final r = rnd.nextInt(rows);
      final c = rnd.nextInt(cols);
      if (in3x3(r, c, sr, sc)) continue;
      final s = _g[r][c];
      if (!s.mine) {
        s.mine = true;
        placed++;
      }
    }
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (_g[r][c].mine) continue;
        int cnt = 0;
        for (final p in neighbors(r, c, rows, cols)) {
          if (_g[p.x][p.y].mine) cnt++;
        }
        _g[r][c].adj = cnt;
      }
    }
    _hasMines = true;
    exploded = false;
  }

  void toggleFlag(int r, int c) {
    final s = _g[r][c];
    if (s.open) return;
    s.flagged = !s.flagged;
  }

  void openCell(int r, int c) {
    final s = _g[r][c];
    if (s.open || s.flagged) return;
    if (s.mine) {
      s.open = true;
      s.exploded = true;
      exploded = true;
      return;
    }
    _openSafe(r, c);
  }

  void _openSafe(int r, int c) {
    final q = ListQueue<Point<int>>();
    void push(int rr, int cc) {
      final ss = _g[rr][cc];
      if (!ss.open && !ss.flagged && !ss.mine) {
        ss.open = true;
        q.add(Point(rr, cc));
      }
    }

    push(r, c);
    while (q.isNotEmpty) {
      final p0 = q.removeFirst();
      final sr = p0.x, sc = p0.y;
      final s0 = _g[sr][sc];
      if (s0.adj == 0) {
        for (final nb in neighbors(sr, sc, rows, cols)) {
          final nn = _g[nb.x][nb.y];
          if (!nn.open && !nn.flagged && !nn.mine) {
            nn.open = true;
            if (nn.adj == 0) q.add(Point(nb.x, nb.y));
          }
        }
      }
    }
  }

  /// Chording: 열려있는 숫자칸 기준, 깃발 수 == 숫자 → 나머지 오픈
  void chordOpen(int r, int c) {
    final s = _g[r][c];
    if (!s.open || s.adj == 0) return;

    int flaggedCnt = 0;
    final hidden = <Point<int>>[];
    for (final nb in neighbors(r, c, rows, cols)) {
      final q = _g[nb.x][nb.y];
      if (q.flagged) flaggedCnt++;
      if (!q.open && !q.flagged) hidden.add(Point(nb.x, nb.y));
    }
    if (hidden.isEmpty) return;

    if (flaggedCnt == s.adj) {
      for (final h in hidden) {
        openCell(h.x, h.y);
        if (exploded) return;
      }
    }
  }

  /// A/B 규칙 기반 자동 추론 보조(한 스텝)
  bool deterministicAssistStep() {
    bool changed = false;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final s = _g[r][c];
        if (!s.open) continue;

        final nbs = neighbors(r, c, rows, cols).toList();
        int flaggedCnt = 0;
        final hidden = <Point<int>>[];
        for (final nb in nbs) {
          final q = _g[nb.x][nb.y];
          if (q.flagged) flaggedCnt++;
          if (!q.open && !q.flagged) hidden.add(nb);
        }
        if (hidden.isEmpty) continue;

        // A: 필요 지뢰 수 == 숨김칸 수 → 전부 깃발
        if (s.adj - flaggedCnt == hidden.length) {
          for (final h in hidden) {
            final q = _g[h.x][h.y];
            if (!q.flagged) {
              q.flagged = true;
              changed = true;
            }
          }
        }

        // B: 필요 지뢰 수 == 깃발 수 → 전부 안전
        if (s.adj == flaggedCnt) {
          for (final h in hidden) {
            final q = _g[h.x][h.y];
            if (!q.open && !q.flagged && !q.mine) {
              _openSafe(h.x, h.y);
              changed = true;
              if (exploded) return true;
            }
          }
        }
      }
    }
    return changed;
  }

  void runDeterministicAssistLoop() {
    while (deterministicAssistStep()) {
      if (exploded) break;
    }
  }
}
