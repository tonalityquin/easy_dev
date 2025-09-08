import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Minesweeper extends StatefulWidget {
  const Minesweeper({super.key});

  @override
  State<Minesweeper> createState() => _MinesweeperState();
}

enum _Difficulty { easy, normal, hard }

class _Cell {
  bool mine = false;
  bool open = false;
  bool flag = false;
  int adj = 0; // 주변 지뢰 수
}

class _MinesweeperState extends State<Minesweeper> {
  // 기본값(Easy)
  _Difficulty _diff = _Difficulty.easy;
  int _rows = 9;
  int _cols = 9;
  int _mines = 10;

  late List<List<_Cell>> _board;
  bool _firstTap = true; // 첫 클릭에서만 지뢰 배치
  bool _alive = true; // 게임오버 여부
  bool _win = false;

  // ▶ No-guess 모드 토글
  bool _noGuess = false;

  Timer? _timer;
  int _secs = 0;

  int get _flags => _board.fold(0, (sum, r) => sum + r.where((c) => c.flag).length);

  int get _minesLeft => max(0, _mines - _flags);

  @override
  void initState() {
    super.initState();
    _newGame(); // 첫 게임 시작
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _applyDifficulty(_Difficulty d) {
    _diff = d;
    switch (d) {
      case _Difficulty.easy:
        _rows = 9;
        _cols = 9;
        _mines = 10;
        break;
      case _Difficulty.normal:
        _rows = 12;
        _cols = 12;
        _mines = 22;
        break;
      case _Difficulty.hard:
        _rows = 16;
        _cols = 16;
        _mines = 40;
        break;
    }
  }

  void _newGame({_Difficulty? diff}) {
    if (diff != null) _applyDifficulty(diff);
    _timer?.cancel();
    _secs = 0;
    _alive = true;
    _win = false;
    _firstTap = true;
    _board = List.generate(_rows, (_) => List.generate(_cols, (_) => _Cell()));
    setState(() {});
  }

  void _startTimerIfNeeded() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_alive || _win) {
        _timer?.cancel();
        _timer = null;
        return;
      }
      setState(() => _secs++);
    });
  }

  // ─────────────────────────────────────────────────────
  // 지뢰 배치(첫 클릭 시 호출) — No-guess 지원
  // ─────────────────────────────────────────────────────

  void _placeMinesForFirstTap(int sr, int sc) {
    if (_noGuess) {
      // No-guess: 결정적 규칙만으로 전체 해답이 가능한 보드가 나올 때까지 반복
      final ok = _placeNoGuess(sr, sc);
      if (ok) return;
      // 혹시 매우 드문 실패 시 랜덤으로 fallback
      _placeMinesExcludingRandom(sr, sc);
    } else {
      _placeMinesExcludingRandom(sr, sc);
    }
  }

  // 기존 랜덤 배치(안전영역 제외) + 인접수 계산
  void _placeMinesExcludingRandom(int sr, int sc) {
    final rnd = Random();
    final excluded = _excluded3x3(sr, sc);

    var placed = 0;
    while (placed < _mines) {
      final r = rnd.nextInt(_rows);
      final c = rnd.nextInt(_cols);
      if (excluded.contains(Point(r, c))) continue;
      final cell = _board[r][c];
      if (!cell.mine) {
        cell.mine = true;
        placed++;
      }
    }
    _recalcAdjAll();
  }

  // No-guess 전용 배치: 결정적 솔버로 풀리는 보드가 나올 때까지 시도
  bool _placeNoGuess(int sr, int sc) {
    final rnd = Random();
    final excluded = _excluded3x3(sr, sc);
    const maxAttempts = 2000; // 충분히 큼

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      // 보드 초기화
      for (final row in _board) {
        for (final cell in row) {
          cell.mine = false;
          cell.open = false;
          cell.flag = false;
          cell.adj = 0;
        }
      }

      // 배치
      var placed = 0;
      while (placed < _mines) {
        final r = rnd.nextInt(_rows);
        final c = rnd.nextInt(_cols);
        if (excluded.contains(Point(r, c))) continue;
        final cell = _board[r][c];
        if (!cell.mine) {
          cell.mine = true;
          placed++;
        }
      }

      // 인접수 계산
      _recalcAdjAll();

      // 결정적 솔버로 완전 해소 가능한지 검사
      if (_deterministicSolvableFrom(sr, sc)) {
        return true; // 이 배치를 채택
      }
    }
    return false; // 실패(드묾)
  }

  Set<Point<int>> _excluded3x3(int sr, int sc) {
    final excluded = <Point<int>>{};
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        final r = sr + dr, c = sc + dc;
        if (_in(r, c)) excluded.add(Point(r, c));
      }
    }
    return excluded;
  }

  void _recalcAdjAll() {
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        if (_board[r][c].mine) continue;
        _board[r][c].adj = _neighbors(r, c).where((p) => _board[p.x][p.y].mine).length;
      }
    }
  }

  // 결정적 솔버: 첫 클릭(sr,sc) 오픈 후
  //   규칙 A) 깃발 수==숫자 → 나머지 이웃 자동 오픈
  //   규칙 B) 미오픈 수+깃발 수==숫자 → 미오픈 전부 지뢰(가상 깃발)
  // 를 반복 적용해 모든 안전 칸을 열 수 있으면 true
  bool _deterministicSolvableFrom(int sr, int sc) {
    // 복제 상태(원본 변형 금지)
    final mine = List.generate(_rows, (r) => List.generate(_cols, (c) => _board[r][c].mine));
    final adj = List.generate(_rows, (r) => List.generate(_cols, (c) => _board[r][c].adj));
    final open = List.generate(_rows, (r) => List<bool>.filled(_cols, false));
    final flag = List.generate(_rows, (r) => List<bool>.filled(_cols, false));

    // sr,sc는 항상 안전(3x3 제외 배치)
    if (mine[sr][sc]) return false;

    // 0 flood
    void flood(int rr, int cc) {
      final stack = <Point<int>>[Point(rr, cc)];
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        final r = p.x, c = p.y;
        if (!_in(r, c) || open[r][c] || flag[r][c]) continue;
        open[r][c] = true;
        if (adj[r][c] == 0) {
          for (final nb in _neighbors(r, c)) {
            if (!open[nb.x][nb.y] && !flag[nb.x][nb.y] && !mine[nb.x][nb.y]) {
              stack.add(nb);
            }
          }
        }
      }
    }

    flood(sr, sc);

    bool progress = true;
    while (progress) {
      progress = false;

      for (int r = 0; r < _rows; r++) {
        for (int c = 0; c < _cols; c++) {
          if (!open[r][c]) continue;
          final num = adj[r][c];
          if (num == 0) continue;

          final nbs = _neighbors(r, c).toList();
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

          // 규칙 A: flags==num -> unknown 전부 오픈
          if (flags == num && unknown > 0) {
            for (final u in unknownCells) {
              if (!mine[u.x][u.y] && !open[u.x][u.y]) {
                flood(u.x, u.y);
                progress = true;
              } else if (mine[u.x][u.y]) {
                // 지뢰인데 오픈해야 한다면 논리 모순 → 실패
                return false;
              }
            }
          }

          // 규칙 B: flags+unknown==num -> unknown 전부 지뢰(가상 깃발)
          if (flags + unknown == num && unknown > 0) {
            for (final u in unknownCells) {
              if (!flag[u.x][u.y]) {
                flag[u.x][u.y] = true;
                progress = true;
              }
            }
          }
        }
      }
    }

    // 모두 열렸는지
    int safeTotal = 0, opened = 0;
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        if (!mine[r][c]) {
          safeTotal++;
          if (open[r][c]) opened++;
        }
      }
    }
    return opened == safeTotal;
  }

  // ─────────────────────────────────────────────────────
  // 보드/이웃
  // ─────────────────────────────────────────────────────
  bool _in(int r, int c) => r >= 0 && r < _rows && c >= 0 && c < _cols;

  Iterable<Point<int>> _neighbors(int r, int c) sync* {
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final rr = r + dr, cc = c + dc;
        if (_in(rr, cc)) yield Point(rr, cc);
      }
    }
  }

  // ─────────────────────────────────────────────────────
  // 게임 진행
  // ─────────────────────────────────────────────────────
  void _toggleFlag(int r, int c) {
    if (!_alive || _win) return;
    final cell = _board[r][c];
    if (cell.open) return;
    setState(() => cell.flag = !cell.flag);
  }

  void _openCell(int r, int c) {
    if (!_alive || _win) return;
    final cell = _board[r][c];
    if (cell.open || cell.flag) return;

    _startTimerIfNeeded();

    if (_firstTap) {
      _placeMinesForFirstTap(r, c);
      _firstTap = false;
    }

    if (cell.mine) {
      // 게임 오버
      setState(() {
        _alive = false;
        _revealAllMines();
      });
      _timer?.cancel();
      return;
    }

    _floodOpen(r, c);
    _checkWin();
  }

  void _revealAllMines() {
    for (final row in _board) {
      for (final cell in row) {
        if (cell.mine) cell.open = true;
      }
    }
  }

  void _floodOpen(int sr, int sc) {
    final q = <Point<int>>[Point(sr, sc)];
    while (q.isNotEmpty) {
      final p = q.removeLast();
      final r = p.x, c = p.y;
      final cell = _board[r][c];
      if (cell.open || cell.flag) continue;
      cell.open = true;

      if (cell.adj == 0) {
        for (final nb in _neighbors(r, c)) {
          final ncell = _board[nb.x][nb.y];
          if (!ncell.open && !ncell.flag && !ncell.mine) {
            q.add(nb);
          }
        }
      }
    }
    setState(() {});
  }

  void _checkWin() {
    for (final row in _board) {
      for (final cell in row) {
        if (!cell.mine && !cell.open) return; // 아직 미오픈 일반칸 존재
      }
    }
    setState(() {
      _win = true;
      _alive = true;
    });
    _timer?.cancel();
  }

  Color _numberColor(int n) {
    switch (n) {
      case 1:
        return const Color(0xFF1976D2);
      case 2:
        return const Color(0xFF388E3C);
      case 3:
        return const Color(0xFFD32F2F);
      case 4:
        return const Color(0xFF512DA8);
      case 5:
        return const Color(0xFFF57C00);
      case 6:
        return const Color(0xFF0097A7);
      case 7:
        return const Color(0xFF455A64);
      case 8:
        return const Color(0xFF6D4C41);
      default:
        return Colors.transparent;
    }
  }

  // ─────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minesweeper'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        actions: [
          DropdownButton<_Difficulty>(
            value: _diff,
            underline: const SizedBox.shrink(),
            style: const TextStyle(color: Colors.black87),
            iconEnabledColor: Colors.black87,
            dropdownColor: Colors.white,
            onChanged: (v) {
              if (v != null) _newGame(diff: v);
            },
            items: const [
              DropdownMenuItem(value: _Difficulty.easy, child: Text('Easy 9×9')),
              DropdownMenuItem(value: _Difficulty.normal, child: Text('Normal 12×12')),
              DropdownMenuItem(value: _Difficulty.hard, child: Text('Hard 16×16')),
            ],
          ),
          IconButton(
            tooltip: '새 게임',
            onPressed: () => _newGame(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // 상단 정보바
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                _pill(Icons.brightness_5, '$_minesLeft'),
                const SizedBox(width: 10),
                _pill(Icons.timer, '$_secs s'),
                const SizedBox(width: 12),
                // ▶ No-guess 스위치
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No-guess', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Switch.adaptive(
                      value: _noGuess,
                      onChanged: (v) {
                        setState(() => _noGuess = v);
                        _newGame();
                      },
                    ),
                  ],
                ),
                const Spacer(),
                if (!_alive)
                  Text('Game Over',
                      style: text.titleMedium?.copyWith(color: Colors.redAccent, fontWeight: FontWeight.w800)),
                if (_win)
                  Text('You Win!', style: text.titleMedium?.copyWith(color: Colors.green, fontWeight: FontWeight.w800)),
              ],
            ),
          ),

          // 보드
          Expanded(
            child: LayoutBuilder(
              builder: (context, cons) {
                final side = min(cons.maxWidth, cons.maxHeight);
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Center(
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: GridView.builder(
                        key: ValueKey('grid_${_rows}x$_cols'),
                        primary: false,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _cols,
                          childAspectRatio: 1,
                        ),
                        itemCount: _rows * _cols,
                        itemBuilder: (_, i) {
                          final r = i ~/ _cols;
                          final c = i % _cols;
                          final cell = _board[r][c];
                          return _tile(r, c, cell);
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData data, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(data, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _tile(int r, int c, _Cell cell) {
    final bg = cell.open ? (cell.mine ? const Color(0xFFFFEBEE) : const Color(0xFFF5F5F5)) : const Color(0xFFEEEEEE);
    final border = Border.all(color: Colors.black.withOpacity(.08));

    Widget content;
    if (cell.open) {
      if (cell.mine) {
        content = const Icon(Icons.brightness_1, color: Colors.redAccent, size: 18); // 지뢰 점
      } else if (cell.adj > 0) {
        content = Text(
          '${cell.adj}',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: _numberColor(cell.adj),
            fontSize: 16,
          ),
        );
      } else {
        content = const SizedBox.shrink(); // 0칸: 비움
      }
    } else if (cell.flag) {
      content = const Icon(Icons.flag, color: Colors.deepOrange, size: 20);
    } else {
      content = const SizedBox.shrink();
    }

    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: BoxDecoration(color: bg, border: border),
        child: InkWell(
          onTap: () {
            final current = _board[r][c];
            if (current.open || current.flag) {
              HapticFeedback.selectionClick();
              return;
            }
            _openCell(r, c);
          },
          onLongPress: () {
            final current = _board[r][c];
            if (current.open) {
              HapticFeedback.selectionClick();
              return;
            }
            _toggleFlag(r, c);
          },
          child: Center(child: content),
        ),
      ),
    );
  }
}
