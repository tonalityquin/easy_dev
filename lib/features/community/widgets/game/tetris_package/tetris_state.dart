import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tetris_bag.dart';
import 'tetris_base.dart';
import 'tetris_input.dart';
import 'tetris_models.dart';
import 'tetris_templates.dart';
import 'tetris_ui.dart';

class Tetris extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onClose;
  final bool resumeOnOpen;

  const Tetris({super.key})
      : embedded = false,
        onClose = null,
        resumeOnOpen = false;

  const Tetris.embedded({super.key, this.onClose, this.resumeOnOpen = true}) : embedded = true;

  @override
  State<Tetris> createState() => _TetrisState();
}

class TetrisGameSession {
  TetrisGameSession._();

  static _TetrisSnapshot? _snapshot;
  static _TetrisState? _activeState;
  static bool _terminating = false;

  static bool get hasPausedSession => _snapshot != null && _snapshot!.cur != null && !_snapshot!.gameOver;

  static bool get hasSession => _snapshot != null;

  static void pauseSession() {
    _activeState?._pauseForExternalClose();
  }

  static void resumeSession() {
    _activeState?._resumeForExternalOpen();
  }

  static void terminate() {
    _terminating = true;
    _activeState?._terminateCompletely();
    _snapshot = null;
    _terminating = false;
  }
}

class _TetrisSnapshot {
  final List<List<Color?>> board;
  final TetrisPiece? cur;
  final TetrisPiece? hold;
  final bool holdUsed;
  final List<TetrisPiece> nextQueue;
  final List<Tetromino> bagState;
  final int score;
  final int highScore;
  final int level;
  final int lines;
  final int combo;
  final bool backToBack;
  final bool gameOver;
  final double speed;
  final int bestLines;
  final int bestLevel;
  final int boardVersion;

  const _TetrisSnapshot({
    required this.board,
    required this.cur,
    required this.hold,
    required this.holdUsed,
    required this.nextQueue,
    required this.bagState,
    required this.score,
    required this.highScore,
    required this.level,
    required this.lines,
    required this.combo,
    required this.backToBack,
    required this.gameOver,
    required this.speed,
    required this.bestLines,
    required this.bestLevel,
    required this.boardVersion,
  });
}

class _TetrisState extends TetrisBase<Tetris> with WidgetsBindingObserver, TetrisUIDelegate<Tetris>, TetrisInputDelegate<Tetris> {
  static const int rows = 22;
  static const int visibleRows = 20;
  static const int cols = 10;
  static const int _lockDelayMs = 500;
  static const int _maxLockResets = 15;
  static const String _highScoreKey = 'tetris_high_score';
  static const String _bestLinesKey = 'tetris_best_lines';
  static const String _bestLevelKey = 'tetris_best_level';
  static const String _speedKey = 'tetris_speed';
  static const String _totalGamesKey = 'tetris_total_games';

  late List<List<Color?>> board;
  TetrisPiece? cur;
  TetrisPiece? hold;
  bool holdUsed = false;
  final TetrisBag _bag = TetrisBag();
  final List<TetrisPiece> nextQueue = [];

  int score = 0;
  int highScore = 0;
  int level = 1;
  int lines = 0;
  int combo = 0;
  int _bestLines = 0;
  int _bestLevel = 1;
  int _boardVersion = 0;
  bool backToBack = false;

  Timer? _gravityTimer;
  Timer? _lockTimer;
  bool isPaused = false;
  bool gameOver = false;
  bool _softDropping = false;
  int _lockResetCount = 0;
  bool _skipSnapshotOnDispose = false;

  double _speed = 1.0;
  final FocusNode _focus = FocusNode();
  late final Map<Tetromino, TetrisPieceTemplate> _templates = makeTetrisTemplates();

  @override
  bool get embedded => widget.embedded;

  @override
  VoidCallback? get closeHandler => widget.onClose;

  @override
  double get speed => _speed;

  @override
  int get kCols => cols;

  @override
  int get kVisibleRows => visibleRows;

  @override
  FocusNode get focusNode => _focus;

  @override
  int get boardVersion => _boardVersion;

  @override
  void togglePause() => _togglePause();

  @override
  void startGame() => _startGame();

  @override
  void moveH(int d) => _moveH(d);

  @override
  void rotateCW() => _rotateCW();

  @override
  void rotateCCW() => _rotateCCW();

  @override
  void softStart() => _softStart();

  @override
  void softEnd() => _softEnd();

  @override
  void hardDrop() => _hardDrop();

  @override
  void holdSwap() => _holdSwap();

  @override
  void speedUp() => _speedUp();

  @override
  void speedDown() => _speedDown();

  @override
  List<Point<int>> ghostCells() => _ghostCells();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TetrisGameSession._activeState = this;
    _initPrefs();
    _restoreOrStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (TetrisGameSession._activeState == this) TetrisGameSession._activeState = null;
    if (!_skipSnapshotOnDispose && !TetrisGameSession._terminating) {
      _pauseForExternalClose();
      _saveSnapshot();
    }
    cancelInputTimers();
    _gravityTimer?.cancel();
    _lockTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) && !gameOver && !isPaused) {
      _pauseForExternalClose();
    }
  }

  Future<void> _initPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    final snapshot = TetrisGameSession._snapshot;
    setState(() {
      highScore = p.getInt(_highScoreKey) ?? highScore;
      _bestLines = p.getInt(_bestLinesKey) ?? _bestLines;
      _bestLevel = p.getInt(_bestLevelKey) ?? _bestLevel;
      if (snapshot == null) {
        _speed = (p.getDouble(_speedKey) ?? _speed).clamp(0.5, 3.0).toDouble();
      }
    });
    if (!isPaused && !gameOver) _restartGravity();
  }

  Future<void> _saveHighScore() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_highScoreKey, highScore);
  }

  Future<void> _saveBestProgress() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_bestLinesKey, _bestLines);
    await p.setInt(_bestLevelKey, _bestLevel);
  }

  Future<void> _saveSpeed() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_speedKey, _speed);
  }

  Future<void> _increaseTotalGames() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_totalGamesKey, (p.getInt(_totalGamesKey) ?? 0) + 1);
  }

  void _restoreOrStart() {
    final snapshot = TetrisGameSession._snapshot;
    if (snapshot == null) {
      _startGame();
      return;
    }

    board = _cloneBoard(snapshot.board);
    cur = snapshot.cur;
    hold = snapshot.hold;
    holdUsed = snapshot.holdUsed;
    nextQueue
      ..clear()
      ..addAll(snapshot.nextQueue);
    _bag.restore(snapshot.bagState);
    score = snapshot.score;
    highScore = snapshot.highScore;
    level = snapshot.level;
    lines = snapshot.lines;
    combo = snapshot.combo;
    backToBack = snapshot.backToBack;
    gameOver = snapshot.gameOver;
    _speed = snapshot.speed;
    _bestLines = snapshot.bestLines;
    _bestLevel = snapshot.bestLevel;
    _boardVersion = snapshot.boardVersion + 1;
    isPaused = true;
    _softDropping = false;
    _lockResetCount = 0;
    _gravityTimer?.cancel();
    _cancelLock();
    _focusAfterFrame();
    _refresh();
    if (widget.embedded && widget.resumeOnOpen && !gameOver && cur != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && TetrisGameSession._activeState == this && isPaused && !gameOver) {
          _resumeForExternalOpen();
        }
      });
    }
  }

  void _startGame() {
    cancelInputTimers();
    _gravityTimer?.cancel();
    _cancelLock();
    board = List.generate(rows, (_) => List<Color?>.filled(cols, null));
    _boardVersion++;
    score = 0;
    level = 1;
    lines = 0;
    combo = 0;
    backToBack = false;
    gameOver = false;
    isPaused = false;
    _softDropping = false;
    _lockResetCount = 0;
    hold = null;
    holdUsed = false;
    _bag.clear();
    nextQueue
      ..clear()
      ..addAll(List.generate(5, (_) => _drawFromBag()));
    cur = _spawnNext();
    TetrisGameSession._snapshot = null;
    _increaseTotalGames();
    _restartGravity();
    _focusAfterFrame();
    _refresh();
  }

  void _focusAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focus.hasFocus) {
        FocusScope.of(context).requestFocus(_focus);
      }
    });
  }

  void _pauseForExternalClose() {
    isPaused = true;
    _softDropping = false;
    cancelInputTimers();
    _gravityTimer?.cancel();
    _lockTimer?.cancel();
    _lockTimer = null;
    if (mounted) _refresh();
  }

  void _resumeForExternalOpen() {
    if (gameOver || cur == null) return;
    isPaused = false;
    _softDropping = false;
    cancelInputTimers();
    _restartGravity();
    if (_isTouchingGround()) _ensureLock();
    if (mounted) _refresh();
    _saveSnapshot();
  }

  void _terminateCompletely() {
    _skipSnapshotOnDispose = true;
    cancelInputTimers();
    _gravityTimer?.cancel();
    _cancelLock();
    TetrisGameSession._snapshot = null;
    gameOver = true;
    isPaused = true;
  }

  void _saveSnapshot() {
    if (!mounted && board.isEmpty) return;
    TetrisGameSession._snapshot = _TetrisSnapshot(
      board: _cloneBoard(board),
      cur: cur,
      hold: hold,
      holdUsed: holdUsed,
      nextQueue: List<TetrisPiece>.of(nextQueue),
      bagState: _bag.snapshot(),
      score: score,
      highScore: highScore,
      level: level,
      lines: lines,
      combo: combo,
      backToBack: backToBack,
      gameOver: gameOver,
      speed: _speed,
      bestLines: _bestLines,
      bestLevel: _bestLevel,
      boardVersion: _boardVersion,
    );
  }

  List<List<Color?>> _cloneBoard(List<List<Color?>> source) => [for (final row in source) List<Color?>.of(row)];

  void _togglePause() {
    if (gameOver) return;
    setState(() => isPaused = !isPaused);
    if (isPaused) {
      cancelInputTimers();
      _gravityTimer?.cancel();
      _lockTimer?.cancel();
    } else {
      _restartGravity();
      if (_isTouchingGround()) _ensureLock();
    }
    _saveSnapshot();
  }

  TetrisPiece _drawFromBag() {
    final kind = _bag.draw();
    return TetrisPiece.fromTemplate(_templates[kind]!);
  }

  TetrisPiece? _spawnNext() {
    if (nextQueue.isEmpty) nextQueue.add(_drawFromBag());
    final piece = nextQueue.removeAt(0).reset();
    nextQueue.add(_drawFromBag());
    if (_canPlace(piece)) {
      holdUsed = false;
      _lockResetCount = 0;
      _cancelLock();
      return piece;
    }
    _onGameOver();
    return null;
  }

  int _gravityMs() {
    const gravityByLevel = [700, 620, 540, 470, 400, 330, 270, 220, 180, 150, 120, 100, 85, 70, 60, 50];
    final base = level <= gravityByLevel.length ? gravityByLevel[level - 1] : 45;
    final ms = max(35, (base / _speed).round());
    return _softDropping ? max(25, ms ~/ 4) : ms;
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
      cur = n;
      _cancelLock();
      _lockResetCount = 0;
      if (_softDropping) {
        _addScore(1);
        _sfx(TetrisSfx.soft);
      }
      _refresh();
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

  void _resetLockAfterManualMove() {
    if (!_isTouchingGround()) {
      _cancelLock();
      return;
    }
    if (_lockResetCount < _maxLockResets) {
      _lockResetCount++;
      _cancelLock();
    }
    _ensureLock();
  }

  void _fixCurrent() {
    if (cur == null) return;
    bool top = false;
    for (final p in cur!.cells) {
      final r = cur!.pos.x + p.x;
      final c = cur!.pos.y + p.y;
      if (r < 0) top = true;
      if (_inside(r, c)) board[r][c] = cur!.color;
    }
    _boardVersion++;
    if (top) {
      _onGameOver();
      return;
    }
    _cancelLock();
    _clearLines();
    cur = _spawnNext();
    _sfx(TetrisSfx.lock);
    _refresh();
    _saveSnapshot();
  }

  void _onGameOver() {
    gameOver = true;
    isPaused = true;
    cancelInputTimers();
    _gravityTimer?.cancel();
    _cancelLock();
    _sfx(TetrisSfx.gameover);
    _updateRecords();
    _refresh();
    _saveSnapshot();
  }

  void _clearLines() {
    final full = <int>[];
    for (int r = rows - 1; r >= rows - visibleRows; r--) {
      if (board[r].every((c) => c != null)) full.add(r);
    }
    if (full.isEmpty) {
      combo = 0;
      return;
    }

    final fullSet = full.toSet();
    final remaining = <List<Color?>>[
      for (int r = 0; r < rows; r++)
        if (!fullSet.contains(r)) board[r],
    ];

    board = <List<Color?>>[
      ...List.generate(full.length, (_) => List<Color?>.filled(cols, null)),
      ...remaining,
    ];
    _boardVersion++;

    final cleared = full.length;
    final baseScore = const {1: 100, 2: 300, 3: 500, 4: 800};
    final isTetris = cleared == 4;
    var gained = (baseScore[cleared] ?? cleared * 100) * level;
    if (isTetris && backToBack) gained = (gained * 3) ~/ 2;
    combo++;
    if (combo > 1) gained += (combo - 1) * 50 * level;
    if (_isPerfectClear()) gained += 2000 * level;
    _addScore(gained);
    lines += cleared;
    backToBack = isTetris;
    final nextLevel = 1 + (lines ~/ 10);
    if (nextLevel != level) {
      level = nextLevel;
      _restartGravity();
    }
    _sfx(TetrisSfx.line);
  }

  void _addScore(int v) {
    score += v;
    if (score > highScore) {
      highScore = score;
      _saveHighScore();
    }
  }

  void _updateRecords() {
    var changed = false;
    if (score > highScore) {
      highScore = score;
      _saveHighScore();
    }
    if (lines > _bestLines) {
      _bestLines = lines;
      changed = true;
    }
    if (level > _bestLevel) {
      _bestLevel = level;
      changed = true;
    }
    if (changed) _saveBestProgress();
  }

  void _moveH(int d) {
    if (isPaused || gameOver || cur == null) return;
    final n = cur!.moved(Point(0, d));
    if (_canPlace(n)) {
      cur = n;
      _resetLockAfterManualMove();
      _sfx(TetrisSfx.move);
      _refresh();
    }
  }

  void _rotateCW() => _rotate(TetrisRotation.cw);

  void _rotateCCW() => _rotate(TetrisRotation.ccw);

  void _rotate(TetrisRotation r) {
    if (isPaused || gameOver || cur == null || cur!.template.shapes.length == 1) return;
    final template = cur!.template;
    final from = cur!.rot;
    final to = r == TetrisRotation.cw ? (from + 1) % template.shapes.length : (from + template.shapes.length - 1) % template.shapes.length;

    for (final k in template.kicksFor(from, to)) {
      final cand = cur!.rotateTo(to).moved(Point(k.dy, k.dx));
      if (_canPlace(cand)) {
        cur = cand;
        _resetLockAfterManualMove();
        _sfx(TetrisSfx.rotate);
        _refresh();
        return;
      }
    }
  }

  void _softStart() {
    if (isPaused || gameOver || cur == null) return;
    _softDropping = true;
    _restartGravity();
  }

  void _softEnd() {
    if (gameOver) return;
    _softDropping = false;
    if (!isPaused) _restartGravity();
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
    cur = p;
    _addScore(cells * 2);
    _sfx(TetrisSfx.hard);
    _fixCurrent();
  }

  void _holdSwap() {
    if (isPaused || gameOver || cur == null || holdUsed) return;
    if (hold == null) {
      hold = cur!.reset();
      cur = _spawnNext();
    } else {
      final t = hold!;
      hold = cur!.reset();
      final c = t.reset();
      cur = _canPlace(c) ? c : null;
      if (cur == null) _onGameOver();
    }
    holdUsed = true;
    _lockResetCount = 0;
    _cancelLock();
    _sfx(TetrisSfx.hold);
    _refresh();
    _saveSnapshot();
  }

  void _speedUp() {
    setState(() => _speed = (_speed + 0.25).clamp(0.5, 3.0).toDouble());
    _saveSpeed();
    if (!isPaused && !gameOver) _restartGravity();
    _sfx(TetrisSfx.move);
    _saveSnapshot();
  }

  void _speedDown() {
    setState(() => _speed = (_speed - 0.25).clamp(0.5, 3.0).toDouble());
    _saveSpeed();
    if (!isPaused && !gameOver) _restartGravity();
    _sfx(TetrisSfx.move);
    _saveSnapshot();
  }

  bool _inside(int r, int c) => r >= 0 && r < rows && c >= 0 && c < cols;

  bool _emptyAt(int r, int c) {
    if (c < 0 || c >= cols) return false;
    if (r < 0) return true;
    if (r >= rows) return false;
    return board[r][c] == null;
  }

  bool _canPlace(TetrisPiece p) {
    for (final cell in p.cells) {
      final r = p.pos.x + cell.x;
      final c = p.pos.y + cell.y;
      if (!_emptyAt(r, c)) return false;
    }
    return true;
  }

  bool _isTouchingGround() {
    if (cur == null) return false;
    return !_canPlace(cur!.moved(const Point(1, 0)));
  }

  bool _isPerfectClear() {
    for (int r = rows - visibleRows; r < rows; r++) {
      if (board[r].any((c) => c != null)) return false;
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

  void _refresh() {
    if (!mounted) return;
    setState(() {});
  }

  void _sfx(TetrisSfx s) {
    switch (s) {
      case TetrisSfx.hard:
      case TetrisSfx.line:
      case TetrisSfx.gameover:
        HapticFeedback.mediumImpact();
        break;
      case TetrisSfx.hold:
      case TetrisSfx.rotate:
        HapticFeedback.selectionClick();
        break;
      case TetrisSfx.move:
      case TetrisSfx.soft:
      case TetrisSfx.lock:
        SystemSound.play(SystemSoundType.click);
        break;
    }
  }
}
