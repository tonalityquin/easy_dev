import 'dart:math';
import 'package:flutter/foundation.dart';
import 'mine_models.dart';

/// Isolate-safe 퍼즐 생성기
/// 입력: {rows, cols, mines, sr, sc, fair(bool), seed(int?), maxAttempts, timeoutMs}
/// 출력: {'mine': List<List<bool>>, 'adj': List<List<int>>}
Future<Map<String, dynamic>> generateBoardMap(Map<String, dynamic> params) async {
  return compute<Map<String, dynamic>, Map<String, dynamic>>(_generateBoardMap, params);
}

Map<String, dynamic> _generateBoardMap(Map<String, dynamic> p) {
  final rows = p['rows'] as int;
  final cols = p['cols'] as int;
  final mines = p['mines'] as int;
  final sr = p['sr'] as int;
  final sc = p['sc'] as int;
  final fair = (p['fair'] as bool?) ?? true;
  final seed = p['seed'] as int?;
  final maxAttempts = (p['maxAttempts'] as int?) ?? 400;
  final timeoutMs = (p['timeoutMs'] as int?) ?? 800;

  final sw = Stopwatch()..start();
  final rnd = Random(seed);

  List<List<bool>> bestMine = [];
  List<List<int>> bestAdj = [];

  bool attemptFair() {
    // 1) 무작위 배치(3×3 보호)
    final mine = List.generate(rows, (_) => List<bool>.filled(cols, false));
    int placed = 0;
    while (placed < mines) {
      final r = rnd.nextInt(rows);
      final c = rnd.nextInt(cols);
      if (in3x3(r, c, sr, sc)) continue;
      if (!mine[r][c]) {
        mine[r][c] = true;
        placed++;
      }
    }
    // 2) adj 계산
    final adj = List.generate(rows, (_) => List<int>.filled(cols, 0));
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (mine[r][c]) continue;
        int cnt = 0;
        for (final p in neighbors(r, c, rows, cols)) {
          if (mine[p.x][p.y]) cnt++;
        }
        adj[r][c] = cnt;
      }
    }

    if (!fair) {
      bestMine = mine;
      bestAdj = adj;
      return true;
    }

    // 3) 공정성 체크(A/B 규칙으로 전부 열리는가)
    final opened = List.generate(rows, (_) => List<bool>.filled(cols, false));
    final flagged = List.generate(rows, (_) => List<bool>.filled(cols, false));

    void open(int r, int c) {
      if (opened[r][c] || flagged[r][c]) return;
      opened[r][c] = true;
      if (adj[r][c] == 0) {
        for (final p in neighbors(r, c, rows, cols)) {
          if (!opened[p.x][p.y] && !mine[p.x][p.y]) open(p.x, p.y);
        }
      }
    }

    open(sr, sc);

    bool step() {
      bool changed = false;
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          if (!opened[r][c]) continue;
          final nList = neighbors(r, c, rows, cols).toList();
          final hidden = <Point<int>>[];
          int flaggedCnt = 0;
          for (final p0 in nList) {
            if (flagged[p0.x][p0.y]) flaggedCnt++;
            if (!opened[p0.x][p0.y] && !flagged[p0.x][p0.y]) hidden.add(p0);
          }
          final need = adj[r][c];

          // A: 필요 지뢰 수 == 숨김칸 수 → 숨김 전부 지뢰
          if (hidden.isNotEmpty && need - flaggedCnt == hidden.length) {
            for (final q in hidden) {
              if (!flagged[q.x][q.y]) {
                flagged[q.x][q.y] = true;
                changed = true;
              }
            }
          }

          // B: 필요 지뢰 수 == 깃발 수 → 숨김 전부 안전
          if (hidden.isNotEmpty && need == flaggedCnt) {
            for (final q in hidden) {
              if (!opened[q.x][q.y] && !flagged[q.x][q.y] && !mine[q.x][q.y]) {
                open(q.x, q.y);
                changed = true;
              }
            }
          }
        }
      }
      return changed;
    }

    while (step()) {}

    // 모든 안전칸이 열렸으면 공정 보드
    bool ok = true;
    outer:
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (!mine[r][c] && !opened[r][c]) {
          ok = false; break outer;
        }
      }
    }
    if (ok) {
      bestMine = mine;
      bestAdj = adj;
      return true;
    }
    return false;
  }

  int attempts = 0;
  while (attempts < maxAttempts && sw.elapsedMilliseconds < timeoutMs) {
    attempts++;
    if (attemptFair()) break;
  }

  // 실패 시 폴백(공정성 미보장): 3×3 제외 랜덤
  if (bestMine.isEmpty) {
    final mine = List.generate(rows, (_) => List<bool>.filled(cols, false));
    int placed = 0;
    while (placed < mines) {
      final r = rnd.nextInt(rows);
      final c = rnd.nextInt(cols);
      if (in3x3(r, c, sr, sc)) continue;
      if (!mine[r][c]) {
        mine[r][c] = true;
        placed++;
      }
    }
    final adj = List.generate(rows, (_) => List<int>.filled(cols, 0));
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (mine[r][c]) continue;
        int cnt = 0;
        for (final p in neighbors(r, c, rows, cols)) {
          if (mine[p.x][p.y]) cnt++;
        }
        adj[r][c] = cnt;
      }
    }
    bestMine = mine;
    bestAdj = adj;
  }

  return {'mine': bestMine, 'adj': bestAdj};
}
