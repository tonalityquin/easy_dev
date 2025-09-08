// lib/screens/community_package/game_package/sokoban.dart
// Flutter Sokoban (소코반) - 단일 파일 완성본 (raw 문자열로 레벨 정의 수정)
// 특징
// - 스와이프/버튼 조작, 부드러운 이동 애니메이션
// - UNDO/리셋/레벨 선택/다음·이전 레벨
// - 이동/푸시 카운트, 클리어 판정, 코너 데드락 감지(빨간 하이라이트)
// - 키보드 방향키(웹/데스크탑) 대응

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SokobanPage extends StatefulWidget {
  const SokobanPage({super.key});
  @override
  State<SokobanPage> createState() => _SokobanPageState();
}

class _SokobanPageState extends State<SokobanPage> {
  // ───────────────────────────────────────────────────────────
  // 레벨 데이터(간단 오리지널 12개) — ※ $가 포함되어 raw 문자열 r''' ... ''' 사용
  // ───────────────────────────────────────────────────────────
  static const List<String> _levels = [
    // 1 — 튜토용(한 박스)
    r'''
#######
#  .  #
#  $  #
#  @  #
#######
''',
    // 2 — 두 박스 직선
    r'''
########
# .  . #
# $$   #
#  @   #
########
''',
    // 3 — 꺾인 길
    r'''
#########
#   # . #
# $   $ #
#   #   #
# .   @ #
#########
''',
    // 4 — 기본 코너 경고 테스트
    r'''
#########
# .   . #
#  ##   #
#  $$   #
#   @   #
#########
''',
    // 5 — 통로형
    r'''
##########
# .   .  #
#   ##   #
# $$  $  #
#   @    #
##########
''',
    // 6 — 작은 창고
    r'''
########
# .  . #
# $$ $ #
#  ##  #
#  @   #
########
''',
    // 7 — 중형
    r'''
###########
# . .     #
#   ###   #
# $$  $   #
#   @     #
###########
''',
    // 8 — 분기
    r'''
#########
# . .   #
#     $ #
#  $$   #
#   # @ #
#########
''',
    // 9 — 넓은 홀
    r'''
############
# .  .  .  #
#    ##    #
# $$   $$  #
#   @      #
############
''',
    // 10 — 중앙 섬
    r'''
#############
# .   #   . #
#  $  #  $  #
#     #     #
#  $     $  #
#   ###@### #
#############
''',
    // 11 — 목표 모서리
    r'''
##########
# .   .  #
#  $$    #
#  # #   #
#   @    #
##########
''',
    // 12 — 라스트(소형 난이도)
    r'''
#########
# . . . #
# $ $ $ #
#   @   #
#########
''',
  ];

  // ───────────────────────────────────────────────────────────
  // 상태
  // ───────────────────────────────────────────────────────────
  int levelIndex = 0;

  late int width;
  late int height;

  late List<bool> walls;   // true = 벽
  late List<bool> goals;   // true = 목표지점
  late Set<int> boxes;     // 박스 위치
  late int player;         // 플레이어 위치(0..w*h-1)

  int moves = 0;           // 이동 횟수
  int pushes = 0;          // 박스 푸시 횟수

  // Undo 스택
  final List<_UndoRec> _undo = [];

  // 스와이프 감지용
  Offset _dragStart = Offset.zero;

  // 키보드 포커스
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _load(levelIndex);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────
  // 레벨 파서/로드
  // ───────────────────────────────────────────────────────────
  void _load(int idx) {
    final raw = _levels[idx].trimRight().split('\n');
    height = raw.length;
    width = raw.map((e) => e.length).fold<int>(0, (m, n) => max(m, n));

    walls = List<bool>.filled(width * height, false);
    goals = List<bool>.filled(width * height, false);
    boxes = <int>{};
    player = 0;
    moves = 0;
    pushes = 0;
    _undo.clear();

    for (int r = 0; r < height; r++) {
      final line = raw[r].padRight(width, ' ');
      for (int f = 0; f < width; f++) {
        final ch = line[f];
        final idx = _rf(r, f);
        switch (ch) {
          case '#':
            walls[idx] = true;
            break;
          case '.':
            goals[idx] = true;
            break;
          case '@':
            player = idx;
            break;
          case '+':
            player = idx;
            goals[idx] = true;
            break;
          case r'$':
            boxes.add(idx);
            break;
          case '*':
            boxes.add(idx);
            goals[idx] = true;
            break;
          default:
          // ' ' 바닥
        }
      }
    }
    setState(() {});
  }

  // ───────────────────────────────────────────────────────────
  // 좌표/보조
  // ───────────────────────────────────────────────────────────
  int _rf(int r, int f) => r * width + f;
  int _rOf(int idx) => idx ~/ width;
  int _fOf(int idx) => idx % width;
  bool _onBoard(int r, int f) => r >= 0 && r < height && f >= 0 && f < width;

  bool _isBlockedCell(int idx) => walls[idx];

  // (미사용이던 _isOccupied는 제거)
  bool _isSolved() {
    for (final b in boxes) {
      if (!goals[b]) return false;
    }
    return true;
  }

  // 코너 데드락: 벽-벽 코너에 박스가 있고, 그 자리가 goal이 아니면 빨간 경고
  bool _isBoxDead(int b) {
    if (goals[b]) return false;
    final r = _rOf(b), f = _fOf(b);
    bool wUp = r > 0 && walls[_rf(r - 1, f)];
    bool wDown = r < height - 1 && walls[_rf(r + 1, f)];
    bool wLeft = f > 0 && walls[_rf(r, f - 1)];
    bool wRight = f < width - 1 && walls[_rf(r, f + 1)];
    // 코너(상하 중 하나) + (좌우 중 하나)
    return (wUp || wDown) && (wLeft || wRight);
  }

  // ───────────────────────────────────────────────────────────
  // 이동/UNDO
  // ───────────────────────────────────────────────────────────
  void _tryMove(int dr, int df) {
    HapticFeedback.selectionClick();
    final pR = _rOf(player), pF = _fOf(player);
    final nR = pR + dr, nF = pF + df;
    if (!_onBoard(nR, nF)) return;
    final next = _rf(nR, nF);

    if (_isBlockedCell(next)) return;

    // 박스가 있나?
    if (boxes.contains(next)) {
      final nnR = nR + dr, nnF = nF + df;
      if (!_onBoard(nnR, nnF)) return;
      final beyond = _rf(nnR, nnF);
      if (_isBlockedCell(beyond) || boxes.contains(beyond)) return;

      // push!
      setState(() {
        _undo.add(_UndoRec(player: player, boxFrom: next, boxTo: beyond));
        boxes.remove(next);
        boxes.add(beyond);
        player = next;
        moves += 1;
        pushes += 1;
      });
      _maybeClear();
    } else {
      // 그냥 이동
      setState(() {
        _undo.add(_UndoRec(player: player));
        player = next;
        moves += 1;
      });
      _maybeClear();
    }
  }

  void _maybeClear() {
    if (_isSolved()) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        HapticFeedback.heavyImpact();
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('클리어!'),
            content: Text('이동 $moves, 푸시 $pushes\n다음 레벨로 진행할까요?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('머물기')),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _nextLevel();
                },
                child: const Text('다음 레벨'),
              ),
            ],
          ),
        );
      });
    }
  }

  void _undoMove() {
    if (_undo.isEmpty) return;
    HapticFeedback.lightImpact();
    final last = _undo.removeLast();
    setState(() {
      player = last.player;
      if (last.boxFrom != null && last.boxTo != null) {
        boxes.remove(last.boxTo);
        boxes.add(last.boxFrom!);
        pushes = max(0, pushes - 1);
      }
      moves = max(0, moves - 1);
    });
  }

  void _resetLevel() {
    HapticFeedback.lightImpact();
    _load(levelIndex);
  }

  void _nextLevel() {
    levelIndex = (levelIndex + 1) % _levels.length;
    _load(levelIndex);
  }

  void _prevLevel() {
    levelIndex = (levelIndex - 1 + _levels.length) % _levels.length;
    _load(levelIndex);
  }

  // ───────────────────────────────────────────────────────────
  // 입력 처리(스와이프/버튼/키보드)
  // ───────────────────────────────────────────────────────────
  void _onPanStart(DragStartDetails d) {
    _dragStart = d.localPosition;
  }

  void _onPanEnd(DragEndDetails d, Offset end) {
    final delta = end - _dragStart;
    const th = 24.0; // 스와이프 임계치
    if (delta.distance < th) return;
    if (delta.dx.abs() > delta.dy.abs()) {
      if (delta.dx > 0) {
        _tryMove(0, 1); // →
      } else {
        _tryMove(0, -1); // ←
      }
    } else {
      if (delta.dy > 0) {
        _tryMove(1, 0); // ↓
      } else {
        _tryMove(-1, 0); // ↑
      }
    }
  }

  void _onKey(RawKeyEvent e) {
    if (e is! RawKeyDownEvent) return;
    switch (e.logicalKey.keyLabel) {
      case 'Arrow Up':
        _tryMove(-1, 0);
        break;
      case 'Arrow Down':
        _tryMove(1, 0);
        break;
      case 'Arrow Left':
        _tryMove(0, -1);
        break;
      case 'Arrow Right':
        _tryMove(0, 1);
        break;
      case 'z':
        _undoMove();
        break;
      case 'r':
        _resetLevel();
        break;
    }
  }

  // ───────────────────────────────────────────────────────────
  // 빌드
  // ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 키보드 포커스 유지
    return RawKeyboardListener(
      focusNode: _focus..requestFocus(),
      onKey: _onKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sokoban • 모바일 퍼즐'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: '이전 레벨',
              onPressed: _prevLevel,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: '다음 레벨',
              onPressed: _nextLevel,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF121212),
        body: LayoutBuilder(
          builder: (context, cons) {
            // 하단 컨트롤 여유 높이
            const reserved = 170.0;
            final side = min(cons.maxWidth, max(200.0, cons.maxHeight - reserved));

            return Column(
              children: [
                _hudBar(cs),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      onPanStart: _onPanStart,
                      onPanUpdate: (d) {},
                      onPanEnd: (d) => _onPanEnd(d, d.velocity.pixelsPerSecond),
                      onTap: () {}, // 탭 무시(스와이프만)
                      child: SizedBox(
                        width: side,
                        height: side * (height / width),
                        child: _board(side),
                      ),
                    ),
                  ),
                ),
                _controlBar(cs),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _hudBar(ColorScheme cs) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          _pill(Icons.flag_rounded, '레벨 ${levelIndex + 1}/${_levels.length}'),
          _pill(Icons.directions_walk_rounded, '이동 $moves'),
          _pill(Icons.archive_rounded, '푸시 $pushes'),
          if (_isSolved())
            _pill(Icons.celebration_rounded, '클리어!'),
        ],
      ),
    );
  }

  Widget _controlBar(ColorScheme cs) {
    final btnStyle = ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1D1D1D),
        border: const Border(top: BorderSide(color: Colors.black12)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.2), blurRadius: 8)],
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          // 조작 버튼
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 56),
              _dirBtn(Icons.keyboard_arrow_up, () => _tryMove(-1, 0)),
              const SizedBox(width: 56),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _dirBtn(Icons.keyboard_arrow_left, () => _tryMove(0, -1)),
              const SizedBox(width: 12),
              _dirBtn(Icons.stop_circle_outlined, () {}),
              const SizedBox(width: 12),
              _dirBtn(Icons.keyboard_arrow_right, () => _tryMove(0, 1)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 56),
              _dirBtn(Icons.keyboard_arrow_down, () => _tryMove(1, 0)),
              const SizedBox(width: 56),
            ],
          ),
          const SizedBox(height: 10),
          // 유틸
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _undo.isEmpty ? null : _undoMove,
                icon: const Icon(Icons.undo),
                label: const Text('되돌리기'),
                style: btnStyle,
              ),
              ElevatedButton.icon(
                onPressed: _resetLevel,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('리셋'),
                style: btnStyle,
              ),
              ElevatedButton.icon(
                onPressed: _prevLevel,
                icon: const Icon(Icons.skip_previous_rounded),
                label: const Text('이전'),
                style: btnStyle,
              ),
              ElevatedButton.icon(
                onPressed: _nextLevel,
                icon: const Icon(Icons.skip_next_rounded),
                label: const Text('다음'),
                style: btnStyle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dirBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(.25), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Icon(icon, size: 32),
      ),
    );
  }

  Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }

  // ───────────────────────────────────────────────────────────
  // 보드 렌더
  // ───────────────────────────────────────────────────────────
  Widget _board(double widthPixels) {
    final cell = widthPixels / width;

    return RepaintBoundary(
      child: Stack(
        children: [
          // 타일 배경
          Positioned.fill(
            child: CustomPaint(
              painter: _BoardPainter(
                width: width,
                height: height,
                walls: walls,
                goals: goals,
                cell: cell,
              ),
            ),
          ),
          // 박스
          ...boxes.map((b) {
            final r = _rOf(b).toDouble();
            final f = _fOf(b).toDouble();
            final dead = _isBoxDead(b);
            return AnimatedPositioned(
              key: ValueKey('box_$b'),
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              left: f * cell,
              top: r * cell,
              width: cell,
              height: cell,
              child: _boxWidget(cell, dead: dead, onGoal: goals[b]),
            );
          }),
          // 플레이어
          AnimatedPositioned(
            key: ValueKey('player_$player'),
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            left: _fOf(player) * cell,
            top: _rOf(player) * cell,
            width: cell,
            height: cell,
            child: _playerWidget(cell),
          ),
          // 테두리(미세 그림자)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(.25), blurRadius: 10)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _boxWidget(double cell, {required bool dead, required bool onGoal}) {
    final base = onGoal ? const Color(0xFF4CAF50) : const Color(0xFF8D6E63);
    final deco = BoxDecoration(
      color: base,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.black.withOpacity(.2), width: 1.5),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(.35), blurRadius: 6, offset: const Offset(0, 2)),
      ],
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [base.withOpacity(.95), base.withOpacity(.75)],
      ),
    );

    return Stack(
      children: [
        Container(decoration: deco),
        if (dead)
          Center(
            child: Icon(Icons.block, size: cell * 0.5, color: Colors.redAccent.withOpacity(.85)),
          ),
        // 귀퉁이 나사표
        Positioned(top: 4, left: 4, child: _screwDot()),
        Positioned(top: 4, right: 4, child: _screwDot()),
        Positioned(bottom: 4, left: 4, child: _screwDot()),
        Positioned(bottom: 4, right: 4, child: _screwDot()),
      ],
    );
  }

  Widget _screwDot() => Container(
    width: 6,
    height: 6,
    decoration: const BoxDecoration(
      color: Colors.black54,
      shape: BoxShape.circle,
    ),
  );

  Widget _playerWidget(double cell) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF42A5F5),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.35), blurRadius: 6, offset: const Offset(0, 2))],
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF64B5F6), Color(0xFF1E88E5)],
          ),
        ),
        child: Stack(
          children: [
            // 눈
            Align(
              alignment: Alignment(0.3, -0.1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _eyeDot(),
                  const SizedBox(width: 6),
                  _eyeDot(),
                ],
              ),
            ),
            // 하이라이트
            Align(
              alignment: const Alignment(-0.4, -0.4),
              child: Container(
                width: cell * 0.25,
                height: cell * 0.25,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.25),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eyeDot() => Container(
    width: 8, height: 8,
    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
  );
}

// ───────────────────────────────────────────────────────────
// 보드 바닥/벽/목표 렌더링용 커스텀 페인터
// ───────────────────────────────────────────────────────────
class _BoardPainter extends CustomPainter {
  final int width;
  final int height;
  final List<bool> walls;
  final List<bool> goals;
  final double cell;

  _BoardPainter({
    required this.width,
    required this.height,
    required this.walls,
    required this.goals,
    required this.cell,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()..color = const Color(0xFFd6d6bd);
    final dark = Paint()..color = const Color(0xFFb9b98f);
    final wall = Paint()..color = const Color(0xFF424242);

    // 바닥 체스무늬
    for (int r = 0; r < height; r++) {
      for (int f = 0; f < width; f++) {
        final rect = Rect.fromLTWH(f * cell, r * cell, cell, cell);
        final even = ((r + f) % 2 == 0);
        canvas.drawRect(rect, even ? light : dark);
      }
    }

    // 목표 동그라미
    final goalPaint = Paint()..color = const Color(0xFF43A047).withOpacity(.85);
    for (int i = 0; i < width * height; i++) {
      if (!goals[i]) continue;
      final r = i ~/ width;
      final f = i % width;
      final center = Offset((f + .5) * cell, (r + .5) * cell);
      canvas.drawCircle(center, cell * 0.18, goalPaint);
    }

    // 벽
    for (int i = 0; i < width * height; i++) {
      if (!walls[i]) continue;
      final r = i ~/ width;
      final f = i % width;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(f * cell, r * cell, cell, cell),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, wall);
      // 헤어라인
      final hr = Paint()
        ..color = Colors.black.withOpacity(.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawRRect(rect, hr);
    }

    // 외곽 그림자 느낌
    final outer = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width * cell, height * cell),
      const Radius.circular(8),
    );
    final border = Paint()
      ..color = Colors.black.withOpacity(.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(outer, border);
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) {
    return old.walls != walls || old.goals != goals || old.cell != cell || old.width != width || old.height != height;
  }
}

// ───────────────────────────────────────────────────────────
// Undo 기록
// ───────────────────────────────────────────────────────────
class _UndoRec {
  final int player;
  final int? boxFrom;
  final int? boxTo;
  const _UndoRec({required this.player, this.boxFrom, this.boxTo});
}
