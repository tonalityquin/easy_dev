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

  // 첫 클릭 시 안전영역(해당 칸+8방향) 제외하고 지뢰 배치
  void _placeMinesExcluding(int sr, int sc) {
    final rnd = Random();
    final excluded = <Point<int>>{};
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        final r = sr + dr, c = sc + dc;
        if (_in(r, c)) excluded.add(Point(r, c));
      }
    }

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

    // 인접 카운트 계산
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        if (_board[r][c].mine) continue;
        _board[r][c].adj = _neighbors(r, c).where((p) => _board[p.x][p.y].mine).length;
      }
    }
  }

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
      _placeMinesExcluding(r, c);
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

  // 0인 영역 자동 확장
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minesweeper'),
        backgroundColor: Colors.white,
        // ← 배경 하얀색
        foregroundColor: Colors.black87,
        // ← 텍스트/아이콘 색
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        // ← M3 틴트 제거
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark, // 안드로이드 아이콘 어둡게
          statusBarBrightness: Brightness.light, // iOS 상태바 대비
        ),
        actions: [
          DropdownButton<_Difficulty>(
            value: _diff,
            underline: const SizedBox.shrink(),
            // (선택) 드롭다운 텍스트/아이콘도 검정 유지
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
                // 🔧 여기서 폭탄 아이콘은 기존 아이콘을 직접 사용
                _pill(Icons.brightness_5, '$_minesLeft'),
                const SizedBox(width: 10),
                _pill(Icons.timer, '$_secs s'),
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
                // 정사각형 셀 유지
                final cellSize = (min(cons.maxWidth, cons.maxHeight) / max(_rows, _cols)).floorToDouble();
                final gridW = cellSize * _cols;
                final gridH = cellSize * _rows;
                return Center(
                  child: SizedBox(
                    width: gridW,
                    height: gridH,
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
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

    Widget child;
    if (cell.open) {
      if (cell.mine) {
        child = const Icon(Icons.brightness_1, color: Colors.redAccent, size: 18); // 지뢰 점
      } else if (cell.adj > 0) {
        child = Text(
          '${cell.adj}',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: _numberColor(cell.adj),
            fontSize: 16,
          ),
        );
      } else {
        child = const SizedBox.shrink(); // 0칸: 비움
      }
    } else if (cell.flag) {
      child = const Icon(Icons.flag, color: Colors.deepOrange, size: 20);
    } else {
      child = const SizedBox.shrink();
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openCell(r, c),
      onLongPress: () => _toggleFlag(r, c),
      child: Container(
        decoration: BoxDecoration(color: bg, border: border),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
