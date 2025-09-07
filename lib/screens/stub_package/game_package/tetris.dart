// lib/screens/stub_package/tetris.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // SystemSound
import 'package:shared_preferences/shared_preferences.dart';

/// 완전 신규 테트리스
/// - 클래스명: Tetris
/// - 포함: 정식 SRS 킥테이블, 7-백 랜덤, 레벨/중력 가속, 락 딜레이,
///        홀드 & 다음 5, 고스트 피스, 제스처(탭/더블탭/드래그),
///        웹/데스크톱 키보드 입력, CustomPainter 렌더링,
///        큰 보드(가용 공간 최대로 확장), 기본 사운드(click)
///
/// ※ 진짜 효과음 사용 원하면 아래 '실제 SFX 에셋 연동' 가이드 참고.

class Tetris extends StatefulWidget {
  const Tetris({super.key});

  @override
  State<Tetris> createState() => _TetrisState();
}

class _TetrisState extends State<Tetris> {
  // 보드 크기
  static const int rows = 22; // 상단 숨김 2줄 포함
  static const int visibleRows = 20;
  static const int cols = 10;

  // 보드 (실제 충돌/고정에 사용)
  late List<List<Color?>> board;

  // 현재/홀드/다음
  _Piece? cur;
  _Piece? hold;
  bool holdUsed = false;
  final List<_Piece> _bag = [];
  final List<_Piece> nextQueue = [];

  // 점수/레벨
  int score = 0;
  int highScore = 0;
  int level = 1;
  int lines = 0;

  // 상태/타이머
  Timer? _gravityTimer;
  Timer? _lockTimer;
  bool isPaused = false;
  bool gameOver = false;
  bool _softDropping = false;

  // ✅ 사용자 조절 속도(배수): 0.5x ~ 3.0x
  double _speed = 1.0;

  // 포커스(키보드 입력)
  final FocusNode _focus = FocusNode();

  // 설정값
  static const int _lockDelayMs = 500;
  final Random _rand = Random();

  // 템플릿/SRS
  late final Map<_Tetromino, _PieceTemplate> _templates = _makeTemplates();

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

  // ───────────────────────────────────────────────────────
  // 저장소
  Future<void> _initPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      highScore = p.getInt('tetris_high_score') ?? 0;
    });
  }

  Future<void> _saveHigh() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('tetris_high_score', highScore);
  }

  // ───────────────────────────────────────────────────────
  // 게임 시작/재시작
  void _startGame() {
    board = List.generate(rows, (_) => List<Color?>.filled(cols, null));
    score = 0;
    level = 1;
    lines = 0;
    gameOver = false;
    isPaused = false;

    hold = null;
    holdUsed = false;
    _bag.clear();
    nextQueue
      ..clear()
      ..addAll(List.generate(5, (_) => _drawFromBag()));

    cur = _spawnNext();
    _restartGravity();

    // 키보드 포커스
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

  // ───────────────────────────────────────────────────────
  // 7-백 랜덤
  _Piece _drawFromBag() {
    if (_bag.isEmpty) {
      final all = _templates.keys.toList()..shuffle(_rand);
      for (final t in all) {
        _bag.add(_Piece.fromTemplate(_templates[t]!, const Point(-1, 4))); // 중앙 스폰
      }
    }
    final p = _bag.removeLast();
    return p.reset(const Point(-1, 4));
  }

  _Piece? _spawnNext() {
    if (nextQueue.isEmpty) nextQueue.add(_drawFromBag());
    final piece = nextQueue.removeAt(0);
    nextQueue.add(_drawFromBag());

    final spawn = piece.reset(const Point(-1, 4));
    if (_canPlace(spawn)) {
      holdUsed = false;
      _cancelLock();
      return spawn;
    }
    _onGameOver();
    return null;
  }

  // ───────────────────────────────────────────────────────
  // 중력/락 딜레이
  int _gravityMs() {
    // 레벨 1: 700ms, 레벨당 -60ms, 소프트드랍이면 1/3
    final base = max(80, 700 - (level - 1) * 60);
    // 사용자 속도 배수 적용 (너무 빠른 타이머 방지용 하한 50ms)
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
    final next = cur!.moved(const Point(1, 0));
    if (_canPlace(next)) {
      _apply(cur = next);
      _cancelLock();
      if (_softDropping) _sfx(_Sfx.soft);
    } else {
      _ensureLock();
    }
  }

  void _ensureLock() {
    _lockTimer ??= Timer(Duration(milliseconds: _lockDelayMs), _fixCurrent);
  }

  void _cancelLock() {
    _lockTimer?.cancel();
    _lockTimer = null;
  }

  void _fixCurrent() {
    if (cur == null) return;
    bool topOut = false;
    for (final p in cur!.cells) {
      final r = cur!.pos.x + p.x;
      final c = cur!.pos.y + p.y;
      if (r < 0) topOut = true;
      if (_inside(r, c)) board[r][c] = cur!.color;
    }
    if (topOut) {
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

  // ───────────────────────────────────────────────────────
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
    final newLevel = 1 + (lines ~/ 10);
    if (newLevel != level) {
      level = newLevel;
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

  // ───────────────────────────────────────────────────────
  // 이동/회전/드랍/홀드 (SRS)
  void _moveH(int dir) {
    if (isPaused || gameOver || cur == null) return;
    final next = cur!.moved(Point(0, dir));
    if (_canPlace(next)) {
      _apply(cur = next);
      _cancelLock();
      _sfx(_Sfx.move);
    }
  }

  void _rotateCW() => _rotate(_Rot.cw);
  void _rotateCCW() => _rotate(_Rot.ccw);

  void _rotate(_Rot r) {
    if (isPaused || gameOver || cur == null) return;
    final tpl = _templates[cur!.kind]!;
    final from = cur!.rot;
    final to = r == _Rot.cw ? (from + 1) % tpl.shapes.length : (from + tpl.shapes.length - 1) % tpl.shapes.length;

    // SRS 킥 오프셋 (행=row, 열=col 좌표로 변환 필요)
    final kicks = tpl.kicksFor(from, to);

    for (final k in kicks) {
      // (dx,dy)는 (col,row)이므로 pos(row,col)에 (dy,dx) 적용
      final candidate = cur!.rotateTo(to).moved(Point(k.dy, k.dx));
      if (_canPlace(candidate)) {
        _apply(cur = candidate);
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
    var piece = cur!;
    while (true) {
      final next = piece.moved(const Point(1, 0));
      if (_canPlace(next)) {
        piece = next;
        cells++;
      } else {
        break;
      }
    }
    _apply(cur = piece);
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
      final tmp = hold!;
      hold = cur!.reset(const Point(-1, 4));
      final cand = tmp.reset(const Point(-1, 4));
      cur = _canPlace(cand) ? cand : null;
      if (cur == null) _onGameOver();
    }
    holdUsed = true;
    _cancelLock();
    _sfx(_Sfx.hold);
    setState(() {});
  }

  // ✅ 속도 조절
  void _speedUp() {
    setState(() {
      _speed = (_speed + 0.25).clamp(0.5, 3.0).toDouble();
    });
    _restartGravity();
    _sfx(_Sfx.move);
  }

  void _speedDown() {
    setState(() {
      _speed = (_speed - 0.25).clamp(0.5, 3.0).toDouble();
    });
    _restartGravity();
    _sfx(_Sfx.move);
  }

  // ───────────────────────────────────────────────────────
  // 충돌/유틸
  bool _inside(int r, int c) => (r >= 0 && r < rows && c >= 0 && c < cols);

  bool _emptyAt(int r, int c) {
    if (c < 0 || c >= cols) return false;
    if (r < 0) return true; // 상단 숨김 영역
    if (r >= rows) return false;
    return board[r][c] == null;
  }

  bool _canPlace(_Piece p) {
    for (final cell in p.cells) {
      final r = p.pos.x + cell.x;
      final c = p.pos.y + cell.y;
      if (!_emptyAt(r, c)) return false;
    }
    return true;
  }

  List<Point<int>> _ghostCells() {
    if (cur == null) return const [];
    var ghost = cur!;
    while (true) {
      final next = ghost.moved(const Point(1, 0));
      if (_canPlace(next)) {
        ghost = next;
      } else {
        break;
      }
    }
    return ghost.cells.map((p) => Point(ghost.pos.x + p.x, ghost.pos.y + p.y)).toList();
  }

  void _apply(_Piece? _) {
    if (!mounted) return;
    setState(() {});
  }

  // ───────────────────────────────────────────────────────
  // 사운드 (기본: 시스템 클릭, 에셋 추가시 교체 가능)
  void _sfx(_Sfx s) {
    // 기본: 시스템 클릭
    switch (s) {
      case _Sfx.move:
      case _Sfx.rotate:
      case _Sfx.soft:
      case _Sfx.hard:
      case _Sfx.hold:
      case _Sfx.line:
      case _Sfx.lock:
      case _Sfx.gameover:
        SystemSound.play(SystemSoundType.click);
        break;
    }
  }

  // ───────────────────────────────────────────────────────
  // UI: 큰 보드 + CustomPainter + 키보드 + 제스처
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('테트리스'),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(icon: Icon(isPaused ? Icons.play_arrow : Icons.pause), onPressed: _togglePause),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _startGame),
        ],
      ),
      body: RawKeyboardListener(
        focusNode: _focus,
        onKey: _onKey,
        child: OrientationBuilder(
          builder: (context, o) {
            final isLand = o == Orientation.landscape;
            return isLand ? _landscape() : _portrait();
          },
        ),
      ),
    );
  }

  // 키보드 입력 (웹/데스크톱)
  void _onKey(RawKeyEvent e) {
    if (e is! RawKeyDownEvent) return;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _hardDrop();
    } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      _moveH(-1);
    } else if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyD) {
      _moveH(1);
    } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) {
      _softStart();
      Future.delayed(const Duration(milliseconds: 120), _softEnd);
    } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyX) {
      _rotateCW();
    } else if (key == LogicalKeyboardKey.keyZ) {
      _rotateCCW();
    } else if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.keyC) {
      _holdSwap();
    }
  }

  Widget _portrait() {
    // infoPanel 제거하고 보드만 크게 + 컨트롤
    return Column(
      children: [
        const SizedBox(height: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _boardMaximized(),
          ),
        ),
        const SizedBox(height: 6),
        if (!gameOver) _controls(),
        if (gameOver) Padding(padding: const EdgeInsets.only(bottom: 12), child: _gameOverPanel()),
      ],
    );
  }

  Widget _landscape() {
    return Row(
      children: [
        Expanded(flex: 3, child: Padding(padding: const EdgeInsets.all(12), child: _infoPanel())),
        Expanded(flex: 6, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: _boardMaximized())),
        Expanded(flex: 4, child: Center(child: gameOver ? _gameOverPanel() : _controls())),
      ],
    );
  }

  // 화면을 꽉 채우는 큰 보드 (CustomPainter) + HUD 오버레이
  Widget _boardMaximized() {
    final ghost = _ghostCells();
    return LayoutBuilder(
      builder: (context, c) {
        // 셀 크기 = 해당 영역에서 가능한 한 크게
        final cell = min(c.maxWidth / cols, c.maxHeight / visibleRows);
        final size = Size(cell * cols, cell * visibleRows);
        return Center(
          child: GestureDetector(
            onTap: _rotateCW,
            onDoubleTap: _hardDrop,
            onPanUpdate: (d) {
              if (d.delta.dx.abs() > d.delta.dy.abs()) {
                if (d.delta.dx > 0) _moveH(1);
                if (d.delta.dx < 0) _moveH(-1);
              } else if (d.delta.dy > 0) {
                _softStart();
              }
            },
            onPanEnd: (_) => _softEnd(),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                children: [
                  // 보드
                  CustomPaint(
                    size: size,
                    painter: _BoardPainter(
                      rows: visibleRows,
                      cols: cols,
                      board: board,
                      current: cur,
                      ghostCells: ghost,
                    ),
                  ),
                  // 가벼운 오버레이 HUD (터치 무시)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: IgnorePointer(
                      child: _buildCompactHud(maxWidth: size.width),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 오버레이 HUD (세로 모드에서만 눈에 띄도록 가볍고 작게)
  Widget _buildCompactHud({required double maxWidth}) {
    // 작은 칩
    Widget chip(String k, String v) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        margin: const EdgeInsets.only(right: 6, bottom: 4),
        decoration: BoxDecoration(
          color: Colors.white70,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(k, style: const TextStyle(fontSize: 11, color: Colors.black87)),
            const SizedBox(width: 6),
            Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    // 메트릭 칩들
    final metrics = Wrap(
      spacing: 0,
      runSpacing: 0,
      children: [
        chip('Lv', '$level'),
        chip('Lines', '$lines'),
        chip('Score', '$score'),
        chip('Best', '$highScore'),
      ],
    );

    // 폭이 좁으면 더 작고, 다음 개수도 줄임
    final bool small = maxWidth < 320;
    final int nextCount = small ? 2 : 3;
    final nexts = nextQueue.take(nextCount).toList();

    final double holdSize = small ? 32 : 40;
    final double nextSize = small ? 28 : 32;

    final right = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white70,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: holdSize,
            height: holdSize,
            child: hold == null
                ? Center(child: Text('—', style: TextStyle(fontSize: small ? 12 : 14, color: Colors.grey)))
                : _preview(hold!, size: holdSize),
          ),
          const SizedBox(width: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: nexts
                .map((b) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _preview(b, size: nextSize),
            ))
                .toList(),
          ),
        ],
      ),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: metrics),
        right,
      ],
    );
  }

  Widget _controls() {
    Widget btn(IconData icon, VoidCallback onTap) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 64,
          height: 64,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 3))
            ],
            border: Border.all(color: Colors.black12),
          ),
          child: Icon(icon, size: 28),
        ),
      ),
    );

    // 👇 맨 밑열에 속도 조절 버튼 추가
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          btn(Icons.keyboard_double_arrow_left, () => _moveH(-1)),
          btn(Icons.rotate_right, _rotateCW),
          btn(Icons.keyboard_double_arrow_right, () => _moveH(1)),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          btn(Icons.arrow_downward, () {
            _softStart();
            Future.delayed(const Duration(milliseconds: 140), _softEnd);
          }),
          btn(Icons.keyboard_double_arrow_down, _hardDrop),
          btn(Icons.change_circle_outlined, _holdSwap),
        ]),
        const SizedBox(height: 8),
        // ▶︎ Speed Row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            btn(Icons.remove, _speedDown),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Text(
                '속도 x${_speed.toStringAsFixed(_speed % 1 == 0 ? 0 : 2)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            btn(Icons.add, _speedUp),
          ],
        ),
      ],
    );
  }

  Widget _gameOverPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Game Over', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.redAccent)),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _startGame,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          child: const Text('다시 시작', style: TextStyle(fontSize: 18)),
        ),
      ],
    );
  }

  Widget _infoPanel() {
    return LayoutBuilder(
      builder: (_, c) {
        final w = c.maxWidth;
        final isRow = w >= 420;
        final nextCount = w < 360 ? 3 : 5;
        final itemSize = w < 360 ? 44.0 : (w < 500 ? 52.0 : 60.0);
        final nexts = nextQueue.take(nextCount).toList();

        final scoreCol = _kvCol({
          '레벨': '$level',
          '라인': '$lines',
          '점수': '$score',
          '최고': '$highScore',
        });

        final holdCol = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('홀드', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(border: Border.all(color: Colors.black12), color: Colors.white),
              child: SizedBox(
                width: 84,
                height: 84,
                child: hold == null
                    ? Center(child: Text('—', style: TextStyle(color: Colors.grey[400])))
                    : _preview(hold!, size: 80),
              ),
            ),
          ],
        );

        final nextCol = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('다음', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 4),
            SizedBox(
              height: itemSize + 8,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: nexts
                      .map((b) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _preview(b, size: itemSize),
                  ))
                      .toList(),
                ),
              ),
            ),
          ],
        );

        final content = isRow
            ? Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Flexible(child: scoreCol),
            const SizedBox(width: 8),
            Flexible(child: holdCol),
            const SizedBox(width: 8),
            Flexible(flex: 2, child: nextCol),
          ],
        )
            : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            scoreCol,
            const SizedBox(height: 12),
            holdCol,
            const SizedBox(height: 12),
            nextCol,
          ],
        );

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(padding: const EdgeInsets.all(12), child: content),
        );
      },
    );
  }

  Widget _kvCol(Map<String, String> items) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: items.entries
          .map((e) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          children: [
            Text(e.key, style: const TextStyle(fontSize: 14, color: Colors.grey)),
            Text(e.value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ],
        ),
      ))
          .toList(),
    );
  }

  Widget _preview(_Piece b, {double size = 80}) {
    // 4x4 프리뷰
    return SizedBox(
      width: size,
      height: size,
      child: GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 4,
        children: List.generate(16, (i) {
          final r = i ~/ 4, c = i % 4;
          final on = b.template.shapes[0].any((p) => p.x == r && p.y == c);
          return Container(
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: on ? b.color : Colors.grey[300],
              border: Border.all(color: Colors.black12),
            ),
          );
        }),
      ),
    );
  }

  // ───────────────────────────────────────────────────────
  // 템플릿/SRS 데이터

  Map<_Tetromino, _PieceTemplate> _makeTemplates() {
    // 각 도형의 회전 상태(0,R,2,L)와 정식 SRS 킥 테이블
    // 좌표계: Point<int>(row, col) — row는 아래로 +, col은 오른쪽으로 +
    // 킥 테이블의 (dx, dy)는 (col, row)이므로 적용 시 (dy, dx)를 pos에 더합니다.

    List<List<Point<int>>> T = [
      [const Point(0, 1), const Point(1, 0), const Point(1, 1), const Point(1, 2)],
      [const Point(0, 1), const Point(1, 1), const Point(2, 1), const Point(1, 2)],
      [const Point(1, 0), const Point(1, 1), const Point(1, 2), const Point(2, 1)],
      [const Point(0, 1), const Point(1, 1), const Point(2, 1), const Point(1, 0)],
    ];
    List<List<Point<int>>> J = [
      [const Point(0, 0), const Point(1, 0), const Point(2, 0), const Point(2, 1)],
      [const Point(1, 0), const Point(1, 1), const Point(1, 2), const Point(0, 2)],
      [const Point(0, 0), const Point(0, 1), const Point(1, 1), const Point(2, 1)],
      [const Point(1, 0), const Point(1, 1), const Point(1, 2), const Point(2, 0)],
    ];
    List<List<Point<int>>> L = [
      [const Point(0, 1), const Point(1, 1), const Point(2, 1), const Point(2, 0)],
      [const Point(1, 0), const Point(1, 1), const Point(1, 2), const Point(2, 2)],
      [const Point(0, 0), const Point(0, 1), const Point(1, 0), const Point(2, 0)],
      [const Point(0, 0), const Point(1, 0), const Point(1, 1), const Point(1, 2)],
    ];
    List<List<Point<int>>> S = [
      [const Point(0, 1), const Point(0, 2), const Point(1, 0), const Point(1, 1)],
      [const Point(0, 0), const Point(1, 0), const Point(1, 1), const Point(2, 1)],
    ];
    List<List<Point<int>>> Z = [
      [const Point(0, 0), const Point(0, 1), const Point(1, 1), const Point(1, 2)],
      [const Point(0, 1), const Point(1, 0), const Point(1, 1), const Point(2, 0)],
    ];
    List<List<Point<int>>> O = [
      [const Point(0, 0), const Point(0, 1), const Point(1, 0), const Point(1, 1)],
    ];
    List<List<Point<int>>> I = [
      [const Point(0, 0), const Point(0, 1), const Point(0, 2), const Point(0, 3)],
      [const Point(0, 1), const Point(1, 1), const Point(2, 1), const Point(3, 1)],
    ];

    // 정식 SRS 킥 오프셋 (dx, dy) — JLSTZ
    final Map<_RotPair, List<_Kick>> jlstzKicks = {
      const _RotPair(0, 1): [_Kick(0, 0), _Kick(-1, 0), _Kick(-1, -1), _Kick(0, 2), _Kick(-1, 2)],
      const _RotPair(1, 0): [_Kick(0, 0), _Kick(1, 0), _Kick(1, 1), _Kick(0, -2), _Kick(1, -2)],
      const _RotPair(1, 2): [_Kick(0, 0), _Kick(1, 0), _Kick(1, 1), _Kick(0, -2), _Kick(1, -2)],
      const _RotPair(2, 1): [_Kick(0, 0), _Kick(-1, 0), _Kick(-1, -1), _Kick(0, 2), _Kick(-1, 2)],
      const _RotPair(2, 3): [_Kick(0, 0), _Kick(1, 0), _Kick(1, -1), _Kick(0, 2), _Kick(1, 2)],
      const _RotPair(3, 2): [_Kick(0, 0), _Kick(-1, 0), _Kick(-1, 1), _Kick(0, -2), _Kick(-1, -2)],
      const _RotPair(3, 0): [_Kick(0, 0), _Kick(-1, 0), _Kick(-1, 1), _Kick(0, -2), _Kick(-1, -2)],
      const _RotPair(0, 3): [_Kick(0, 0), _Kick(1, 0), _Kick(1, -1), _Kick(0, 2), _Kick(1, 2)],
    };

    // 정식 SRS 킥 오프셋 (dx, dy) — I 전용
    final Map<_RotPair, List<_Kick>> iKicks = {
      const _RotPair(0, 1): [_Kick(0, 0), _Kick(-2, 0), _Kick(1, 0), _Kick(-2, -1), _Kick(1, 2)],
      const _RotPair(1, 0): [_Kick(0, 0), _Kick(2, 0), _Kick(-1, 0), _Kick(2, 1), _Kick(-1, -2)],
      const _RotPair(1, 2): [_Kick(0, 0), _Kick(-1, 0), _Kick(2, 0), _Kick(-1, 2), _Kick(2, -1)],
      const _RotPair(2, 1): [_Kick(0, 0), _Kick(1, 0), _Kick(-2, 0), _Kick(1, -2), _Kick(-2, 1)],
      const _RotPair(2, 3): [_Kick(0, 0), _Kick(2, 0), _Kick(-1, 0), _Kick(2, 1), _Kick(-1, -2)],
      const _RotPair(3, 2): [_Kick(0, 0), _Kick(-2, 0), _Kick(1, 0), _Kick(-2, -1), _Kick(1, 2)],
      const _RotPair(3, 0): [_Kick(0, 0), _Kick(1, 0), _Kick(-2, 0), _Kick(1, -2), _Kick(-2, 1)],
      const _RotPair(0, 3): [_Kick(0, 0), _Kick(-1, 0), _Kick(2, 0), _Kick(-1, 2), _Kick(2, -1)],
    };

    return {
      _Tetromino.T: _PieceTemplate(
        kind: _Tetromino.T,
        color: Colors.purple,
        shapes: T,
        kicks: jlstzKicks,
      ),
      _Tetromino.J: _PieceTemplate(
        kind: _Tetromino.J,
        color: Colors.blue,
        shapes: J,
        kicks: jlstzKicks,
      ),
      _Tetromino.L: _PieceTemplate(
        kind: _Tetromino.L,
        color: Colors.orange,
        shapes: L,
        kicks: jlstzKicks,
      ),
      _Tetromino.S: _PieceTemplate(
        kind: _Tetromino.S,
        color: Colors.green,
        shapes: S,
        kicks: jlstzKicks,
      ),
      _Tetromino.Z: _PieceTemplate(
        kind: _Tetromino.Z,
        color: Colors.red,
        shapes: Z,
        kicks: jlstzKicks,
      ),
      _Tetromino.O: _PieceTemplate(
        kind: _Tetromino.O,
        color: Colors.yellow,
        shapes: O,
        // O는 킥이 사실상 (0,0)만 사용
        kicks: {
          const _RotPair(0, 1): [ _Kick(0, 0) ],
          const _RotPair(1, 2): [ _Kick(0, 0) ],
          const _RotPair(2, 3): [ _Kick(0, 0) ],
          const _RotPair(3, 0): [ _Kick(0, 0) ],
          const _RotPair(1, 0): [ _Kick(0, 0) ],
          const _RotPair(2, 1): [ _Kick(0, 0) ],
          const _RotPair(3, 2): [ _Kick(0, 0) ],
          const _RotPair(0, 3): [ _Kick(0, 0) ],
        },
      ),
      _Tetromino.I: _PieceTemplate(
        kind: _Tetromino.I,
        color: Colors.cyan,
        shapes: I,
        kicks: iKicks,
      ),
    };
  }
}

// ─────────────────────────────────────────────────────────
// 데이터/모델

enum _Tetromino { I, O, T, S, Z, J, L }

class _Kick {
  final int dx; // +오른쪽
  final int dy; // +아래
  const _Kick(this.dx, this.dy);
}

class _RotPair {
  final int from;
  final int to;

  const _RotPair(this.from, this.to);

  @override
  bool operator ==(Object other) => other is _RotPair && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

class _PieceTemplate {
  final _Tetromino kind;
  final Color color;
  final List<List<Point<int>>> shapes; // 회전 상태별 셀
  final Map<_RotPair, List<_Kick>> kicks;

  const _PieceTemplate({
    required this.kind,
    required this.color,
    required this.shapes,
    required this.kicks,
  });

  List<Point<int>> shapeAt(int rot) => shapes[rot % shapes.length];

  List<_Kick> kicksFor(int from, int to) => kicks[_RotPair(from, to)] ?? const [_Kick(0, 0)];
}

class _Piece {
  final _PieceTemplate template;
  final int rot; // 0,R,2,L
  final Point<int> pos; // (row, col)

  _Piece({required this.template, required this.rot, required this.pos});

  factory _Piece.fromTemplate(_PieceTemplate t, Point<int> pos) => _Piece(template: t, rot: 0, pos: pos);

  _Piece reset(Point<int> p) => _Piece(template: template, rot: 0, pos: p);

  _Piece moved(Point<int> d) => _Piece(template: template, rot: rot, pos: Point(pos.x + d.x, pos.y + d.y));

  _Piece rotateTo(int r) => _Piece(template: template, rot: r, pos: pos);

  _Tetromino get kind => template.kind;

  Color get color => template.color;

  List<Point<int>> get cells => template.shapeAt(rot);
}

// ─────────────────────────────────────────────────────────
// 페인터(빠르고 또렷한 그리기)

class _BoardPainter extends CustomPainter {
  final int rows;
  final int cols;
  final List<List<Color?>> board;
  final _Piece? current;
  final List<Point<int>> ghostCells;

  _BoardPainter({
    required this.rows,
    required this.cols,
    required this.board,
    required this.current,
    required this.ghostCells,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    final cell = min(cellW, cellH);

    final gridPaint = Paint()
      ..color = const Color(0x11000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // 배경
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bg);

    // 고정 블록
    for (int r = board.length - rows; r < board.length; r++) {
      final vr = r - (board.length - rows); // 보이는 영역의 행
      for (int c = 0; c < cols; c++) {
        final color = board[r][c];
        if (color != null) {
          _drawCell(canvas, vr, c, cell, color);
        }
      }
    }

    // 고스트 (연한 회색)
    for (final p in ghostCells) {
      final r = p.x - (board.length - rows);
      final c = p.y;
      if (r >= 0 && r < rows && c >= 0 && c < cols) {
        _drawCell(canvas, r, c, cell, Colors.black.withOpacity(0.06));
      }
    }

    // 현재 피스
    if (current != null) {
      for (final p in current!.cells) {
        final r = current!.pos.x + p.x - (board.length - rows);
        final c = current!.pos.y + p.y;
        if (r >= 0 && r < rows && c >= 0 && c < cols) {
          _drawCell(canvas, r, c, cell, current!.color);
        }
      }
    }

    // 격자선
    for (int r = 0; r <= rows; r++) {
      final y = r * cell;
      canvas.drawLine(Offset(0, y), Offset(cols * cell, y), gridPaint);
    }
    for (int c = 0; c <= cols; c++) {
      final x = c * cell;
      canvas.drawLine(Offset(x, 0), Offset(x, rows * cell), gridPaint);
    }

    // 테두리
    canvas.drawRect(Rect.fromLTWH(0, 0, cols * cell, rows * cell), borderPaint);
  }

  void _drawCell(Canvas canvas, int r, int c, double cell, Color color) {
    final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
    final paint = Paint()..color = color;
    canvas.drawRect(rect.deflate(0.5), paint);
    // 약한 하이라이트
    final hl = Paint()..color = Colors.white.withOpacity(0.12);
    canvas.drawRect(rect.deflate(cell * 0.2), hl);
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) =>
      old.board != board || old.current != current || old.ghostCells != ghostCells;
}

// ─────────────────────────────────────────────────────────
// 보조 enum

enum _Rot { cw, ccw }

enum _Sfx { move, rotate, soft, hard, hold, line, lock, gameover }
