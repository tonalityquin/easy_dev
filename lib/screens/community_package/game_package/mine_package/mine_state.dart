part of '../minesweeper.dart';

class _MinesweeperState extends State<Minesweeper> with _MinesweeperUI {
  // 기본값(Easy)
  _Difficulty _diff = _Difficulty.easy;
  int _rows = 9;
  int _cols = 9;
  int _mines = 10;

  late List<List<_Cell>> _board;
  bool _firstTap = true;
  bool _alive = true;
  bool _win = false;

  bool _noGuess = false;       // 노게스 토글
  bool _generating = false;    // 첫 클릭 생성 중

  Timer? _timer;
  int _secs = 0;

  int get _flags => _board.fold(0, (s, r) => s + r.where((c) => c.flag).length);
  int get _minesLeft => max(0, _mines - _flags);

  @override
  void initState() {
    super.initState();
    _newGame();
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
        _rows = 9; _cols = 9; _mines = 10;
        break;
      case _Difficulty.normal:
        _rows = 12; _cols = 12; _mines = 22;
        break;
      case _Difficulty.hard:
        _rows = 16; _cols = 16; _mines = 40;
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
    _generating = false;
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

  // ── 첫 클릭 시 보드 생성(노게스는 Isolate 사용)
  Future<void> _placeMinesForFirstTapAsync(int sr, int sc) async {
    if (_noGuess) {
      setState(() => _generating = true);
      final result = await compute<_GenParams, _GenResult>(
        _generateNoGuessBoard,
        _GenParams(rows: _rows, cols: _cols, mines: _mines, sr: sr, sc: sc),
      );
      for (int r = 0; r < _rows; r++) {
        for (int c = 0; c < _cols; c++) {
          final cell = _board[r][c];
          cell.mine = result.mine[r][c];
          cell.adj  = result.adj[r][c];
        }
      }
      setState(() => _generating = false);
    } else {
      _placeMinesExcludingRandom(sr, sc);
    }
  }

  // 랜덤(첫 클릭 3x3 제외)
  void _placeMinesExcludingRandom(int sr, int sc) {
    final rnd = Random();
    final excluded = _excluded3x3(sr, sc);
    final idx = <int>[];
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        if (!excluded.contains(Point(r, c))) idx.add(r * _cols + c);
      }
    }
    idx.shuffle(rnd);
    for (int i = 0; i < _mines && i < idx.length; i++) {
      final id = idx[i];
      _board[id ~/ _cols][id % _cols].mine = true;
    }
    _recalcAdjAll();
  }

  Set<Point<int>> _excluded3x3(int sr, int sc) {
    final out = <Point<int>>{};
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        final r = sr + dr, c = sc + dc;
        if (_in(r, c)) out.add(Point(r, c));
      }
    }
    return out;
  }

  void _recalcAdjAll() {
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        if (_board[r][c].mine) continue;
        _board[r][c].adj =
            _neighbors(r, c).where((p) => _board[p.x][p.y].mine).length;
      }
    }
  }

  // ── 이웃/범위
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

  // ── 진행 로직(+ 런타임 결정 규칙 & Chord)
  void _toggleFlag(int r, int c) {
    if (!_alive || _win) return;
    final cell = _board[r][c];
    if (cell.open) return;
    setState(() => cell.flag = !cell.flag);
    if (_noGuess) {
      _autoDeterministic();
      _checkWin();
    }
  }

  Future<void> _openCell(int r, int c) async {
    if (!_alive || _win) return;
    final cell = _board[r][c];

    if (cell.open) { _chord(r, c); return; }
    if (cell.flag) { HapticFeedback.selectionClick(); return; }

    if (_firstTap) {
      await _placeMinesForFirstTapAsync(r, c);
      _firstTap = false;
    }

    _startTimerIfNeeded();

    if (cell.mine) {
      setState(() { _alive = false; _revealAllMines(); });
      _timer?.cancel();
      return;
    }

    _floodOpen(r, c);
    if (_noGuess) _autoDeterministic();
    _checkWin();
  }

  // 열린 숫자칸 Chord
  void _chord(int r, int c) {
    final cell = _board[r][c];
    if (!cell.open || cell.adj == 0) {
      HapticFeedback.selectionClick();
      return;
    }
    final nbs = _neighbors(r, c).toList();
    final flags = nbs.where((p) => _board[p.x][p.y].flag).length;

    if (flags == cell.adj) {
      bool hit = false;
      for (final nb in nbs) {
        final n = _board[nb.x][nb.y];
        if (!n.open && !n.flag) {
          if (n.mine) { hit = true; break; }
          _floodOpen(nb.x, nb.y);
        }
      }
      if (hit) {
        setState(() { _alive = false; _revealAllMines(); });
        _timer?.cancel();
        return;
      }
      if (_noGuess) _autoDeterministic();
      _checkWin();
    } else {
      HapticFeedback.selectionClick();
    }
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
      if (cell.mine) continue;
      cell.open = true;

      if (cell.adj == 0) {
        for (final nb in _neighbors(r, c)) {
          final n = _board[nb.x][nb.y];
          if (!n.open && !n.flag && !n.mine) q.add(nb);
        }
      }
    }
    setState(() {});
  }

  void _autoDeterministic() {
    bool progress = true;
    while (progress) {
      progress = false;
      for (int r = 0; r < _rows; r++) {
        for (int c = 0; c < _cols; c++) {
          final cell = _board[r][c];
          if (!cell.open || cell.adj == 0) continue;

          final nbs = _neighbors(r, c).toList();
          int flags = 0, unknown = 0;
          final unknownCells = <Point<int>>[];
          for (final nb in nbs) {
            final n = _board[nb.x][nb.y];
            if (n.flag) flags++;
            else if (!n.open) { unknown++; unknownCells.add(nb); }
          }

          // A
          if (flags == cell.adj && unknown > 0) {
            for (final u in unknownCells) {
              final n = _board[u.x][u.y];
              if (!n.open && !n.flag) {
                if (n.mine) {
                  _alive = false; _revealAllMines(); _timer?.cancel(); setState(() {});
                  return;
                }
                _floodOpen(u.x, u.y);
                progress = true;
              }
            }
          }
          // B
          if (flags + unknown == cell.adj && unknown > 0) {
            for (final u in unknownCells) {
              final n = _board[u.x][u.y];
              if (!n.flag && !n.open) { n.flag = true; progress = true; }
            }
          }
        }
      }
    }
    setState(() {});
  }

  void _checkWin() {
    for (final row in _board) {
      for (final cell in row) {
        if (!cell.mine && !cell.open) return;
      }
    }
    setState(() { _win = true; _alive = true; });
    _timer?.cancel();
  }

  @override
  Color _numberColor(int n) {
    switch (n) {
      case 1: return const Color(0xFF1976D2);
      case 2: return const Color(0xFF388E3C);
      case 3: return const Color(0xFFD32F2F);
      case 4: return const Color(0xFF512DA8);
      case 5: return const Color(0xFFF57C00);
      case 6: return const Color(0xFF0097A7);
      case 7: return const Color(0xFF455A64);
      case 8: return const Color(0xFF6D4C41);
      default: return Colors.transparent;
    }
  }
}
