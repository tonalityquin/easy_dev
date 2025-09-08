part of '../minesweeper.dart';

// Isolate 파라미터/결과
class _GenParams {
  final int rows, cols, mines, sr, sc;
  const _GenParams({
    required this.rows,
    required this.cols,
    required this.mines,
    required this.sr,
    required this.sc,
  });
}

class _GenResult {
  final List<List<bool>> mine;
  final List<List<int>> adj;
  const _GenResult(this.mine, this.adj);
}

// 항상 노게스(결정 규칙만으로 완해) 보드 생성
_GenResult _generateNoGuessBoard(_GenParams p) {
  final rnd = Random();

  bool inRange(int r, int c) => r >= 0 && r < p.rows && c >= 0 && c < p.cols;
  Iterable<Point<int>> neighbors(int r, int c) sync* {
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final rr = r + dr, cc = c + dc;
        if (inRange(rr, cc)) yield Point(rr, cc);
      }
    }
  }

  bool inExcluded(int r, int c) => (r - p.sr).abs() <= 1 && (c - p.sc).abs() <= 1;

  while (true) {
    // 1) 무작위 배치(첫 클릭 3x3 제외)
    final mine = List.generate(p.rows, (_) => List<bool>.filled(p.cols, false));
    final idx = <int>[];
    for (int r = 0; r < p.rows; r++) {
      for (int c = 0; c < p.cols; c++) {
        if (!inExcluded(r, c)) idx.add(r * p.cols + c);
      }
    }
    idx.shuffle(rnd);
    final take = min(p.mines, idx.length);
    for (int i = 0; i < take; i++) {
      final id = idx[i];
      mine[id ~/ p.cols][id % p.cols] = true;
    }

    // 2) 인접수 계산
    final adj = List.generate(p.rows, (r) => List<int>.filled(p.cols, 0));
    for (int r = 0; r < p.rows; r++) {
      for (int c = 0; c < p.cols; c++) {
        if (mine[r][c]) continue;
        adj[r][c] = neighbors(r, c).where((q) => mine[q.x][q.y]).length;
      }
    }

    if (mine[p.sr][p.sc]) continue; // sr,sc 안전 보장

    // 3) 결정적 규칙 시뮬레이션
    final open = List.generate(p.rows, (r) => List<bool>.filled(p.cols, false));
    final flag = List.generate(p.rows, (r) => List<bool>.filled(p.cols, false));

    void flood(int rr, int cc) {
      final st = <Point<int>>[Point(rr, cc)];
      while (st.isNotEmpty) {
        final v = st.removeLast();
        final r = v.x, c = v.y;
        if (!inRange(r, c) || open[r][c] || flag[r][c]) continue;
        if (mine[r][c]) return;
        open[r][c] = true;
        if (adj[r][c] == 0) {
          for (final nb in neighbors(r, c)) {
            if (!open[nb.x][nb.y] && !flag[nb.x][nb.y] && !mine[nb.x][nb.y]) {
              st.add(nb);
            }
          }
        }
      }
    }

    flood(p.sr, p.sc);

    bool progress = true, contradiction = false;
    while (progress && !contradiction) {
      progress = false;
      for (int r = 0; r < p.rows; r++) {
        for (int c = 0; c < p.cols; c++) {
          if (!open[r][c]) continue;
          final num = adj[r][c];
          if (num == 0) continue;

          final nbs = neighbors(r, c).toList();
          int flags = 0, unknown = 0;
          final unknownCells = <Point<int>>[];
          for (final nb in nbs) {
            final rr = nb.x, cc = nb.y;
            if (flag[rr][cc]) {
              flags++;
            } else if (!open[rr][cc]) {
              unknown++;
              unknownCells.add(nb);
            }
          }

          // A: flags == num → unknown 오픈
          if (flags == num && unknown > 0) {
            for (final u in unknownCells) {
              if (mine[u.x][u.y]) {
                contradiction = true; // 지뢰를 열어야 하는 모순
                break;
              }
              flood(u.x, u.y);
              progress = true;
            }
          }
          if (contradiction) break;

          // B: flags + unknown == num → unknown 전부 지뢰(깃발)
          if (flags + unknown == num && unknown > 0) {
            for (final u in unknownCells) {
              if (!flag[u.x][u.y]) {
                flag[u.x][u.y] = true;
                progress = true;
              }
            }
          }
        }
        if (contradiction) break;
      }
    }
    if (contradiction) continue;

    int safe = 0, opened = 0;
    for (int r = 0; r < p.rows; r++) {
      for (int c = 0; c < p.cols; c++) {
        if (!mine[r][c]) {
          safe++;
          if (open[r][c]) opened++;
        }
      }
    }
    if (opened == safe) return _GenResult(mine, adj); // 성공
  }
}
