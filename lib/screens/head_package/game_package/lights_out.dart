import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LightsOut extends StatefulWidget {
  const LightsOut({super.key});

  @override
  State<LightsOut> createState() => _LightsOutState();
}

enum _Difficulty { easy, normal, hard }

class _LightsOutState extends State<LightsOut> {
  _Difficulty _diff = _Difficulty.easy;
  int _n = 5; // 보드 한 변 (5/6/7)
  late List<bool> _board; // true=켜짐, false=꺼짐
  bool _won = false;

  // UX
  int _moves = 0;
  Timer? _timer;
  int _secs = 0;

  // Undo
  final List<int> _pressHistory = [];

  // 힌트(추천 칸)
  int? _hintIndex;

  // ─────────────────────────────────────
  // 라이프사이클
  // ─────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _newGame(); // Easy 기본 시작
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────
  // 퍼즐 생성 / 난이도
  // ─────────────────────────────────────
  void _applyDifficulty(_Difficulty d) {
    _diff = d;
    switch (d) {
      case _Difficulty.easy:   _n = 5; break;
      case _Difficulty.normal: _n = 6; break;
      case _Difficulty.hard:   _n = 7; break;
    }
  }

  void _newGame({_Difficulty? diff}) {
    if (diff != null) _applyDifficulty(diff);

    _timer?.cancel();
    _secs = 0;
    _moves = 0;
    _won = false;
    _hintIndex = null;
    _pressHistory.clear();

    // 항상 해답이 존재하도록: '모두 끈' 상태에서 랜덤으로 버튼을 누르며 섞음
    _board = List.filled(_n * _n, false);
    final rnd = Random();
    final shufflePresses = max(8, _n * _n ~/ 2); // 충분히 섞기
    for (int k = 0; k < shufflePresses; k++) {
      final idx = rnd.nextInt(_n * _n);
      _applyPress(idx); // 기록/카운트 없이 내부 적용
    }

    setState(() {});
  }

  void _startTimerIfNeeded() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_won) { _timer?.cancel(); _timer = null; return; }
      setState(() => _secs++);
    });
  }

  // ─────────────────────────────────────
  // 보드 조작
  // ─────────────────────────────────────
  bool _inRC(int r, int c) => r >= 0 && r < _n && c >= 0 && c < _n;
  int _idx(int r, int c) => r * _n + c;

  void _toggle(int r, int c) {
    if (!_inRC(r, c)) return;
    final i = _idx(r, c);
    _board[i] = !_board[i];
  }

  // 실제 게임에서 누르기(이력/승리체크 포함)
  void _press(int i) {
    if (_won) return;
    _startTimerIfNeeded();
    _hintIndex = null;

    _applyPress(i);
    _pressHistory.add(i);
    _moves++;

    _checkWin();
    setState(() {});
  }

  // 내부에서만 사용하는 토글(이력/카운트 X)
  void _applyPress(int i) {
    final r = i ~/ _n;
    final c = i % _n;
    _toggle(r, c);
    _toggle(r - 1, c);
    _toggle(r + 1, c);
    _toggle(r, c - 1);
    _toggle(r, c + 1);
  }

  void _checkWin() {
    _won = !_board.contains(true);
    if (_won) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _undo() {
    if (_pressHistory.isEmpty || _won) return;
    final i = _pressHistory.removeLast();
    _applyPress(i); // 다시 누르면 되돌림
    _moves = max(0, _moves - 1);
    _hintIndex = null;
    _checkWin();
    setState(() {});
  }

  // ─────────────────────────────────────
  // 솔버(가우스-조단, GF(2))
  // A x = b (mod 2) 해결. A: (n^2 x n^2) 토글 행렬
  // 현재 b(켜짐=1)를 0으로 만드는 x(누를 칸 벡터) 구함
  // ─────────────────────────────────────
  List<int>? _solveExact() {
    final N2 = _n * _n;

    // A: N2xN2, b: N2x1
    final A = List.generate(N2, (_) => List<int>.filled(N2, 0));
    for (int r = 0; r < _n; r++) {
      for (int c = 0; c < _n; c++) {
        final i = _idx(r, c);
        // 버튼 i를 누르면 (r,c), (r±1,c), (r,c±1) 토글
        A[i][i] = 1;
        if (_inRC(r - 1, c)) A[i][_idx(r - 1, c)] = 1;
        if (_inRC(r + 1, c)) A[i][_idx(r + 1, c)] = 1;
        if (_inRC(r, c - 1)) A[i][_idx(r, c - 1)] = 1;
        if (_inRC(r, c + 1)) A[i][_idx(r, c + 1)] = 1;
      }
    }

    final b = _board.map((on) => on ? 1 : 0).toList();

    // 가우스-조단 소거 (mod 2)
    int row = 0;
    final colPivot = List<int>.filled(N2, -1); // pivot row for each col (or -1)

    for (int col = 0; col < N2 && row < N2; col++) {
      int sel = -1;
      for (int i = row; i < N2; i++) {
        if (A[i][col] == 1) { sel = i; break; }
      }
      if (sel == -1) continue;

      // swap rows
      if (sel != row) {
        final tmp = A[sel]; A[sel] = A[row]; A[row] = tmp;
        final tb = b[sel]; b[sel] = b[row]; b[row] = tb;
      }
      colPivot[col] = row;

      // eliminate other rows (mod 2)
      for (int i = 0; i < N2; i++) {
        if (i != row && A[i][col] == 1) {
          for (int j = col; j < N2; j++) {
            A[i][j] ^= A[row][j];
          }
          b[i] ^= b[row];
        }
      }
      row++;
    }

    // 해 존재성 검사: 0=...=0 == b(1) 인 모순 검사
    for (int i = row; i < N2; i++) {
      bool allZero = true;
      for (int j = 0; j < N2; j++) {
        if (A[i][j] != 0) { allZero = false; break; }
      }
      if (allZero && b[i] == 1) {
        return null; // 불가능(이론상 발생X: 생성시 항상 가능)
      }
    }

    // 해 복원: 자유변수는 0으로 두고, pivot 열에서 값 결정
    final x = List<int>.filled(N2, 0);
    for (int col = N2 - 1; col >= 0; col--) {
      final r = colPivot[col];
      if (r == -1) { x[col] = 0; continue; }
      int sum = b[r];
      for (int j = col + 1; j < N2; j++) {
        if (A[r][j] == 1) sum ^= x[j];
      }
      x[col] = sum; // mod 2
    }
    return x;
  }

  void _hint() {
    if (_won) return;
    final x = _solveExact();
    if (x == null) return;
    // 아직 켜져 있고(혹은 영향 큰) 칸 중 하나 추천: 그냥 첫 1 인덱스를 사용
    final i = x.indexWhere((v) => v == 1);
    if (i >= 0) {
      setState(() => _hintIndex = i);
      // 힌트 강조는 잠깐만
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && _hintIndex == i) setState(() => _hintIndex = null);
      });
    }
  }

  void _solveAll() async {
    if (_won) return;
    final x = _solveExact();
    if (x == null) return;

    _startTimerIfNeeded();
    _hintIndex = null;

    // 애니메이션처럼 순차로 누르기(빠르게)
    for (int i = 0; i < x.length; i++) {
      if (x[i] == 1) {
        _applyPress(i);
        _pressHistory.add(i);
        _moves++;
        _checkWin();
        if (!mounted) return;
        setState(() {});
        await Future.delayed(const Duration(milliseconds: 40));
      }
    }
  }

  // ─────────────────────────────────────
  // UI
  // ─────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Lights Out'),
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
            onChanged: (v) { if (v != null) _newGame(diff: v); },
            items: const [
              DropdownMenuItem(value: _Difficulty.easy,   child: Text('Easy 5×5')),
              DropdownMenuItem(value: _Difficulty.normal, child: Text('Normal 6×6')),
              DropdownMenuItem(value: _Difficulty.hard,   child: Text('Hard 7×7')),
            ],
          ),
          IconButton(
            tooltip: '새 퍼즐',
            onPressed: () => _newGame(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // 상단 정보 바
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                _pill(Icons.flash_on, 'Moves: $_moves'),
                const SizedBox(width: 10),
                _pill(Icons.timer, '$_secs s'),
                const Spacer(),
                if (_won)
                  Text('CLEARED!', style: text.titleMedium?.copyWith(
                      color: Colors.green, fontWeight: FontWeight.w800)),
              ],
            ),
          ),

          // 보드
          Expanded(
            child: LayoutBuilder(
              builder: (context, cons) {
                final size = min(cons.maxWidth, cons.maxHeight);
                final cell = (size / _n).floorToDouble();
                final boardW = cell * _n;
                return Center(
                  child: SizedBox(
                    width: boardW,
                    height: boardW,
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _n,
                        childAspectRatio: 1,
                      ),
                      itemCount: _n * _n,
                      itemBuilder: (_, i) => _tile(i, cell),
                    ),
                  ),
                );
              },
            ),
          ),

          // 하단 액션
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _undo,
                    icon: const Icon(Icons.undo),
                    label: const Text('Undo'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _hint,
                    icon: const Icon(Icons.lightbulb),
                    label: const Text('Hint'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _solveAll,
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Solve'),
                  ),
                ),
              ],
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

  Widget _tile(int i, double cell) {
    final on = _board[i];
    final isHint = _hintIndex == i;

    final bg = on ? const Color(0xFFFFF176) : const Color(0xFFEEEEEE);
    final border = Border.all(color: Colors.black.withOpacity(.08));
    final halo = isHint ? BoxShadow(color: Colors.orange.withOpacity(.5), blurRadius: 16) : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _press(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: bg,
          border: border,
          boxShadow: halo == null ? null : [halo],
        ),
        alignment: Alignment.center,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: on ? 1 : 0.4,
          child: Icon(
            on ? Icons.lightbulb : Icons.lightbulb_outline,
            size: min(24.0, cell * .45),
            color: on ? Colors.amber.shade800 : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}
