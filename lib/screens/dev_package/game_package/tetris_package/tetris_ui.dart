// lib/screens/stub_package/game_package/tetris_package/tetris_ui.dart
part of '../tetris.dart';

mixin TetrisUIDelegate on _TetrisBase {
  // State.build 제공
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
          IconButton(icon: Icon(isPaused ? Icons.play_arrow : Icons.pause), onPressed: togglePause),
          IconButton(icon: const Icon(Icons.refresh), onPressed: startGame),
        ],
      ),
      body: RawKeyboardListener(
        focusNode: focusNode,
        onKey: handleKey,
        child: OrientationBuilder(
          builder: (context, o) => o == Orientation.landscape ? _landscape() : _portrait(),
        ),
      ),
    );
  }

  // 세로/가로 레이아웃
  Widget _portrait() => Column(
    children: [
      const SizedBox(height: 6),
      Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _boardMaximized())),
      const SizedBox(height: 6),
      if (!gameOver) _controls(),
      if (gameOver) Padding(padding: const EdgeInsets.only(bottom: 12), child: _gameOverPanel()),
    ],
  );

  Widget _landscape() => Row(
    children: [
      Expanded(flex: 3, child: Padding(padding: const EdgeInsets.all(12), child: _infoPanel())),
      Expanded(flex: 6, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: _boardMaximized())),
      Expanded(flex: 4, child: Center(child: gameOver ? _gameOverPanel() : _controls())),
    ],
  );

  // 큰 보드 + HUD
  Widget _boardMaximized() {
    final ghost = ghostCells();
    return LayoutBuilder(
      builder: (context, c) {
        final cell = min(c.maxWidth / kCols, c.maxHeight / kVisibleRows);
        final size = Size(cell * kCols, cell * kVisibleRows);
        return Center(
          child: GestureDetector(
            onTap: rotateCW,
            onDoubleTap: hardDrop,
            onPanUpdate: (d) {
              if (d.delta.dx.abs() > d.delta.dy.abs()) {
                if (d.delta.dx > 0) moveH(1);
                if (d.delta.dx < 0) moveH(-1);
              } else if (d.delta.dy > 0) {
                softStart();
              }
            },
            onPanEnd: (_) => softEnd(),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                children: [
                  CustomPaint(
                    size: size,
                    painter: _BoardPainter(
                      rows: kVisibleRows,
                      cols: kCols,
                      board: board,
                      current: cur,
                      ghostCells: ghost,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: IgnorePointer(child: _buildCompactHud(maxWidth: size.width)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 오버레이 HUD
  Widget _buildCompactHud({required double maxWidth}) {
    Widget chip(String k, String v) => Container(
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

    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Flexible(child: metrics),
      right,
    ]);
  }

  // 컨트롤 버튼
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
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 3))],
            border: Border.all(color: Colors.black12),
          ),
          child: Icon(icon, size: 28),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          btn(Icons.keyboard_double_arrow_left, () => moveH(-1)),
          btn(Icons.rotate_right, rotateCW),
          btn(Icons.keyboard_double_arrow_right, () => moveH(1)),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          btn(Icons.arrow_downward, () {
            softStart();
            Future.delayed(const Duration(milliseconds: 140), softEnd);
          }),
          btn(Icons.keyboard_double_arrow_down, hardDrop),
          btn(Icons.change_circle_outlined, holdSwap),
        ]),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            btn(Icons.remove, speedDown),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Text('속도 x${speed.toStringAsFixed(speed % 1 == 0 ? 0 : 2)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            btn(Icons.add, speedUp),
          ],
        ),
      ],
    );
  }

  Widget _gameOverPanel() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('Game Over', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.redAccent)),
      const SizedBox(height: 12),
      ElevatedButton(
        onPressed: startGame,
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
        child: const Text('다시 시작', style: TextStyle(fontSize: 18)),
      ),
    ],
  );

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
                child: hold == null ? Center(child: Text('—', style: TextStyle(color: Colors.grey[400]))) : _preview(hold!, size: 80),
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

  Widget _kvCol(Map<String, String> items) => Column(
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

  Widget _preview(_Piece b, {double size = 80}) => SizedBox(
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
