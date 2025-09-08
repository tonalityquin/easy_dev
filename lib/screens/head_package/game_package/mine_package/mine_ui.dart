part of '../minesweeper.dart';

// UI를 제공하는 믹스인. State<Minesweeper>에만 적용.
mixin _MinesweeperUI on State<Minesweeper> {
  // ── mixin이 요구하는 상태/메서드(타입 명확히 → double→int 오류 방지)
  // 상태
  int get _rows;
  int get _cols;
  int get _secs;
  int get _minesLeft;
  bool get _alive;
  bool get _win;
  bool get _noGuess;
  set _noGuess(bool v);
  bool get _generating;
  _Difficulty get _diff;
  List<List<_Cell>> get _board;

  // 동작
  void _newGame({_Difficulty? diff});
  Future<void> _openCell(int r, int c);
  void _toggleFlag(int r, int c);
  Color _numberColor(int n);

  // ── UI
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final content = Column(
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
              // No-guess 토글
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No-guess', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Switch.adaptive(
                    value: _noGuess,
                    onChanged: (v) { setState(() => _noGuess = v); _newGame(); },
                  ),
                ],
              ),
              const Spacer(),
              if (!_alive)
                Text('Game Over', style: text.titleMedium?.copyWith(
                    color: Colors.redAccent, fontWeight: FontWeight.w800)),
              if (_win)
                Text('You Win!', style: text.titleMedium?.copyWith(
                    color: Colors.green, fontWeight: FontWeight.w800)),
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
                        crossAxisCount: _cols,          // int
                        childAspectRatio: 1.0,          // double
                      ),
                      itemCount: _rows * _cols,
                      itemBuilder: (_, i) {
                        final r = i ~/ _cols;
                        final c = i % _cols;
                        final cell = _board[r][c];
                        return _tile(context, r, c, cell);
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );

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
            onChanged: (v) { if (v != null) _newGame(diff: v); },
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
      body: Stack(
        children: [
          content,
          if (_generating)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  color: Colors.black.withOpacity(0.1),
                  child: const Center(child: _GeneratingOverlay()),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 작은 배지
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

  // 셀 타일
  Widget _tile(BuildContext context, int r, int c, _Cell cell) {
    final isZeroOpen = cell.open && !cell.mine && cell.adj == 0;

    final bg = !cell.open
        ? const Color(0xFFEEEEEE)
        : (cell.mine ? const Color(0xFFFFEBEE)
        : (isZeroOpen ? const Color(0xFFFFFFFF) : const Color(0xFFF5F5F5)));

    final border = Border.all(
      color: cell.open ? Colors.black.withOpacity(.06) : Colors.black.withOpacity(.18),
    );

    Widget content;
    if (cell.open) {
      if (cell.mine) {
        content = const Icon(Icons.brightness_1, color: Colors.redAccent, size: 18);
      } else if (cell.adj > 0) {
        content = Text(
          '${cell.adj}',
          style: TextStyle(fontWeight: FontWeight.w900, color: _numberColor(cell.adj), fontSize: 16),
        );
      } else {
        content = const Icon(Icons.circle, size: 6, color: Color(0x22000000));
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
          onTap: () => _openCell(r, c),
          onLongPress: () => cell.open ? HapticFeedback.selectionClick() : _toggleFlag(r, c),
          child: const SizedBox.expand(child: Center(child: SizedBox())),
        ),
      ),
    ).copyWith(child: Center(child: content));
  }
}

// 로딩 오버레이
class _GeneratingOverlay extends StatelessWidget {
  const _GeneratingOverlay();
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.1), blurRadius: 12)],
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
            SizedBox(width: 12),
            Text('노게스 보드 생성 중…', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// Ink에 child를 덧씌우기 위한 간단 확장
extension on Widget {
  Widget copyWith({Widget? child}) => Stack(children: [this, if (child != null) Positioned.fill(child: child)]);
}
