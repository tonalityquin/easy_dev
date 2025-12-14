// lib/screens/stub_package/game_package/tetris_package/tetris_state.dart
part of '../tetris.dart';

class _TetrisState extends _TetrisBase with TetrisUIDelegate, TetrisInputDelegate {
  // 보드 크기 및 설정
  static const int rows = 22, visibleRows = 20, cols = 10, _lockDelayMs = 500;

  // 내부 보드/피스 상태
  late List<List<Color?>> board;
  _Piece? cur, hold;
  bool holdUsed = false;
  final List<_Piece> _bag = [], nextQueue = [];

  // 스코어/레벨
  int score = 0, highScore = 0, level = 1, lines = 0;

  // 타이머/플래그
  Timer? _gravityTimer, _lockTimer;
  bool isPaused = false, gameOver = false, _softDropping = false;

  // 속도/포커스/랜덤
  double _speed = 1.0;
  final FocusNode _focus = FocusNode();
  final Random _rand = Random();

  // 템플릿
  late final Map<_Tetromino, _PieceTemplate> _templates = _makeTemplates();

  // ─────────────── _TetrisBase 구현 (getter/명령/헬퍼) ───────────────
  @override double get speed => _speed;
  @override int get kCols => cols;
  @override int get kVisibleRows => visibleRows;
  @override FocusNode get focusNode => _focus;

  @override void togglePause() => _togglePause();
  @override void startGame() => _startGame();
  @override void moveH(int d) => _moveH(d);
  @override void rotateCW() => _rotateCW();
  @override void rotateCCW() => _rotateCCW();
  @override void softStart() => _softStart();
  @override void softEnd() => _softEnd();
  @override void hardDrop() => _hardDrop();
  @override void holdSwap() => _holdSwap();
  @override void speedUp() => _speedUp();
  @override void speedDown() => _speedDown();
  @override List<Point<int>> ghostCells() => _ghostCells();

  // 입력 핸들러는 믹스인(TetrisInputDelegate)이 제공 → 여기서 override 불필요

  // ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _initPrefs();
    _startGame();
  }

  @override
  void dispose() {
    _gravityTimer?.cancel();
    _lockTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  // 저장소
  Future<void> _initPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => highScore = p.getInt('tetris_high_score') ?? 0);
  }

  Future<void> _saveHigh() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('tetris_high_score', highScore);
  }

  // 시작/재시작
  void _startGame() {
    board = List.generate(rows, (_) => List<Color?>.filled(cols, null));
    score = 0; level = 1; lines = 0;
    gameOver = false; isPaused = false;

    hold = null; holdUsed = false; _bag.clear();
    nextQueue..clear()..addAll(List.generate(5, (_) => _drawFromBag()));

    cur = _spawnNext();
    _restartGravity();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focus.hasFocus) {
        FocusScope.of(context).requestFocus(_focus);
      }
    });

    setState(() {});
  }

  void _togglePause() {
    if (gameOver) return;
    setState(() => isPaused = !isPaused);
    if (isPaused) {
      _gravityTimer?.cancel();
      _lockTimer?.cancel();
    } else {
      _restartGravity();
    }
  }

  // 7-bag
  _Piece _drawFromBag() {
    if (_bag.isEmpty) {
      final all = _templates.keys.toList()..shuffle(_rand);
      for (final t in all) {
        _bag.add(_Piece.fromTemplate(_templates[t]!, const Point(-1, 4)));
      }
    }
    final p = _bag.removeLast();
    return p.reset(const Point(-1, 4));
  }

  _Piece? _spawnNext() {
    if (nextQueue.isEmpty) nextQueue.add(_drawFromBag());
    final piece = nextQueue.removeAt(0);
    nextQueue.add(_drawFromBag());
    final s = piece.reset(const Point(-1, 4));
    if (_canPlace(s)) {
      holdUsed = false;
      _cancelLock();
      return s;
    }
    _onGameOver();
    return null;
  }

  // 중력/락
  int _gravityMs() {
    final base = max(80, 700 - (level - 1) * 60);
    int ms = max(50, (base / _speed).round());
    return _softDropping ? max(40, ms ~/ 3) : ms;
  }

  void _restartGravity() {
    _gravityTimer?.cancel();
    _gravityTimer = Timer.periodic(Duration(milliseconds: _gravityMs()), (_) {
      if (!mounted || isPaused || gameOver) return;
      _tickDown();
    });
  }

  void _tickDown() {
    if (cur == null) return;
    final n = cur!.moved(const Point(1, 0));
    if (_canPlace(n)) {
      _apply(cur = n);
      _cancelLock();
      if (_softDropping) _sfx(_Sfx.soft);
    } else {
      _ensureLock();
    }
  }

  void _ensureLock() {
    _lockTimer ??= Timer(const Duration(milliseconds: _lockDelayMs), _fixCurrent);
  }

  void _cancelLock() {
    _lockTimer?.cancel();
    _lockTimer = null;
  }

  void _fixCurrent() {
    if (cur == null) return;
    bool top = false;
    for (final p in cur!.cells) {
      final r = cur!.pos.x + p.x, c = cur!.pos.y + p.y;
      if (r < 0) top = true;
      if (_inside(r, c)) board[r][c] = cur!.color;
    }
    if (top) {
      _onGameOver();
      return;
    }
    _cancelLock();
    _clearLines();
    cur = _spawnNext();
    _sfx(_Sfx.lock);
    setState(() {});
  }

  void _onGameOver() {
    gameOver = true;
    isPaused = true;
    _gravityTimer?.cancel();
    _cancelLock();
    _sfx(_Sfx.gameover);
    if (score > highScore) {
      highScore = score;
      _saveHigh();
    }
    setState(() {});
  }

  // 라인/점수/레벨
  void _clearLines() {
    final full = <int>[];
    for (int r = rows - 1; r >= rows - visibleRows; r--) {
      if (board[r].every((c) => c != null)) full.add(r);
    }
    if (full.isEmpty) return;

    for (final r in full) {
      board.removeAt(r);
      board.insert(0, List<Color?>.filled(cols, null));
    }

    final map = {1: 100, 2: 300, 3: 500, 4: 800};
    _addScore((map[full.length] ?? full.length * 100) * level);
    lines += full.length;
    final nl = 1 + (lines ~/ 10);
    if (nl != level) {
      level = nl;
      _restartGravity();
    }
    _sfx(_Sfx.line);
  }

  void _addScore(int v) {
    score += v;
    if (score > highScore) {
      highScore = score;
      _saveHigh();
    }
  }

  // 이동/회전/드랍/홀드
  void _moveH(int d) {
    if (isPaused || gameOver || cur == null) return;
    final n = cur!.moved(Point(0, d));
    if (_canPlace(n)) {
      _apply(cur = n);
      _cancelLock();
      _sfx(_Sfx.move);
    }
  }

  void _rotateCW() => _rotate(_Rot.cw);
  void _rotateCCW() => _rotate(_Rot.ccw);

  void _rotate(_Rot r) {
    if (isPaused || gameOver || cur == null) return;
    final tpl = _templates[cur!.kind]!, from = cur!.rot;
    final to = r == _Rot.cw
        ? (from + 1) % tpl.shapes.length
        : (from + tpl.shapes.length - 1) % tpl.shapes.length;

    for (final k in tpl.kicksFor(from, to)) {
      final cand = cur!.rotateTo(to).moved(Point(k.dy, k.dx));
      if (_canPlace(cand)) {
        _apply(cur = cand);
        _cancelLock();
        _sfx(_Sfx.rotate);
        return;
      }
    }
  }

  void _softStart() {
    _softDropping = true;
    _restartGravity();
  }

  void _softEnd() {
    _softDropping = false;
    _restartGravity();
  }

  void _hardDrop() {
    if (isPaused || gameOver || cur == null) return;
    int cells = 0;
    var p = cur!;
    while (true) {
      final n = p.moved(const Point(1, 0));
      if (_canPlace(n)) {
        p = n;
        cells++;
      } else {
        break;
      }
    }
    _apply(cur = p);
    _addScore(cells * 2);
    _sfx(_Sfx.hard);
    _fixCurrent();
  }

  void _holdSwap() {
    if (isPaused || gameOver || cur == null || holdUsed) return;
    if (hold == null) {
      hold = cur!.reset(const Point(-1, 4));
      cur = _spawnNext();
    } else {
      final t = hold!;
      hold = cur!.reset(const Point(-1, 4));
      final c = t.reset(const Point(-1, 4));
      cur = _canPlace(c) ? c : null;
      if (cur == null) _onGameOver();
    }
    holdUsed = true;
    _cancelLock();
    _sfx(_Sfx.hold);
    setState(() {});
  }

  // 속도
  void _speedUp() {
    setState(() => _speed = (_speed + 0.25).clamp(0.5, 3.0).toDouble());
    _restartGravity();
    _sfx(_Sfx.move);
  }

  void _speedDown() {
    setState(() => _speed = (_speed - 0.25).clamp(0.5, 3.0).toDouble());
    _restartGravity();
    _sfx(_Sfx.move);
  }

  // 충돌/유틸
  bool _inside(int r, int c) => (r >= 0 && r < rows && c >= 0 && c < cols);

  bool _emptyAt(int r, int c) {
    if (c < 0 || c >= cols) return false;
    if (r < 0) return true;
    if (r >= rows) return false;
    return board[r][c] == null;
  }

  bool _canPlace(_Piece p) {
    for (final cell in p.cells) {
      final r = p.pos.x + cell.x, c = p.pos.y + cell.y;
      if (!_emptyAt(r, c)) return false;
    }
    return true;
  }

  List<Point<int>> _ghostCells() {
    if (cur == null) return const [];
    var g = cur!;
    while (true) {
      final n = g.moved(const Point(1, 0));
      if (_canPlace(n)) {
        g = n;
      } else {
        break;
      }
    }
    return g.cells.map((p) => Point(g.pos.x + p.x, g.pos.y + p.y)).toList();
  }

  void _apply(_Piece? _) {
    if (!mounted) return;
    setState(() {});
  }

  void _sfx(_Sfx s) {
    SystemSound.play(SystemSoundType.click);
  }
}
