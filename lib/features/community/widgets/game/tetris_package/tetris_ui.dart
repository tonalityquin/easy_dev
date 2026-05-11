import 'dart:math';

import 'package:flutter/material.dart';

import 'tetris_base.dart';
import 'tetris_models.dart';
import 'tetris_painter.dart';

mixin TetrisUIDelegate<T extends StatefulWidget> on TetrisBase<T> {
  double _dragX = 0;
  bool _dragSoftActive = false;

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: KeyboardListener(
        focusNode: focusNode,
        autofocus: true,
        onKeyEvent: handleKey,
        child: OrientationBuilder(
          builder: (context, o) => o == Orientation.landscape ? _landscape() : _portrait(),
        ),
      ),
    );

    if (embedded) {
      return Material(
        color: Colors.transparent,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('테트리스'),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(tooltip: isPaused ? '재개' : '일시정지', icon: Icon(isPaused ? Icons.play_arrow : Icons.pause), onPressed: togglePause),
          IconButton(tooltip: '다시 시작', icon: const Icon(Icons.refresh), onPressed: startGame),
        ],
      ),
      body: body,
    );
  }

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

  Widget _boardMaximized() {
    final ghost = ghostCells();
    return LayoutBuilder(
      builder: (context, c) {
        final cell = min(c.maxWidth / kCols, c.maxHeight / kVisibleRows);
        final size = Size(cell * kCols, cell * kVisibleRows);
        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: rotateCW,
            onDoubleTap: hardDrop,
            onPanStart: (_) => _resetDrag(),
            onPanUpdate: (d) => _handleBoardPan(d, cell),
            onPanEnd: (_) => _endBoardPan(),
            onPanCancel: _endBoardPan,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                children: [
                  CustomPaint(
                    size: size,
                    painter: TetrisBoardPainter(
                      rows: kVisibleRows,
                      cols: kCols,
                      board: board,
                      current: cur,
                      ghostCells: ghost,
                      boardVersion: boardVersion,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: IgnorePointer(child: _buildCompactHud(maxWidth: size.width)),
                  ),
                  if (isPaused && !gameOver)
                    Positioned.fill(
                      child: Container(
                        alignment: Alignment.center,
                        color: Colors.black.withOpacity(0.08),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.70),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text('PAUSED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: togglePause,
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('재개'),
                            ),
                          ],
                        ),
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

  void _resetDrag() {
    _dragX = 0;
    _dragSoftActive = false;
  }

  void _handleBoardPan(DragUpdateDetails d, double cell) {
    final threshold = max(12.0, cell * 0.55);
    if (d.delta.dx.abs() >= d.delta.dy.abs()) {
      _dragX += d.delta.dx;
      while (_dragX.abs() >= threshold) {
        final dir = _dragX > 0 ? 1 : -1;
        moveH(dir);
        _dragX -= threshold * dir;
      }
    } else if (d.delta.dy > threshold * 0.35 && !_dragSoftActive) {
      _dragSoftActive = true;
      softStart();
    }
  }

  void _endBoardPan() {
    _dragX = 0;
    if (_dragSoftActive) {
      _dragSoftActive = false;
      softEnd();
    }
  }

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
        if (combo > 1) chip('Combo', 'x$combo'),
        if (backToBack) chip('B2B', 'ON'),
      ],
    );

    final small = maxWidth < 320;
    final nextCount = small ? 2 : 3;
    final nexts = nextQueue.take(nextCount).toList();
    final holdSize = small ? 32.0 : 40.0;
    final nextSize = small ? 28.0 : 32.0;

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
            child: hold == null ? Center(child: Text('—', style: TextStyle(fontSize: small ? 12 : 14, color: Colors.grey))) : _preview(hold!, size: holdSize),
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

  Widget _controls() {
    final size = MediaQuery.of(context).size;
    final compact = size.height < 740 || size.width < 360;
    final buttonSize = compact ? 52.0 : 64.0;
    final iconSize = compact ? 24.0 : 28.0;
    final horizontalMargin = compact ? 5.0 : 10.0;
    final verticalMargin = compact ? 3.0 : 4.0;
    final rowGap = compact ? 4.0 : 8.0;

    Widget btn({
      required IconData icon,
      required String label,
      VoidCallback? onTap,
      VoidCallback? onPressStart,
      VoidCallback? onPressEnd,
    }) {
      return Semantics(
        label: label,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          onTapDown: onPressStart == null ? null : (_) => onPressStart(),
          onTapUp: onPressEnd == null ? null : (_) => onPressEnd(),
          onTapCancel: onPressEnd,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: buttonSize,
              height: buttonSize,
              margin: EdgeInsets.symmetric(horizontal: horizontalMargin, vertical: verticalMargin),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 3))],
                border: Border.all(color: Colors.black12),
              ),
              child: Icon(icon, size: iconSize),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          btn(icon: Icons.keyboard_double_arrow_left, label: '왼쪽으로 이동', onTap: () => moveH(-1)),
          btn(icon: Icons.rotate_right, label: '시계 방향 회전', onTap: rotateCW),
          btn(icon: Icons.keyboard_double_arrow_right, label: '오른쪽으로 이동', onTap: () => moveH(1)),
        ]),
        SizedBox(height: rowGap),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          btn(icon: Icons.arrow_downward, label: '소프트 드롭', onPressStart: softStart, onPressEnd: softEnd),
          btn(icon: Icons.keyboard_double_arrow_down, label: '하드 드롭', onTap: hardDrop),
          btn(icon: Icons.change_circle_outlined, label: '홀드', onTap: holdSwap),
        ]),
        SizedBox(height: rowGap),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            btn(icon: Icons.remove, label: '속도 감소', onTap: speedDown),
            Container(
              margin: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
              padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 7 : 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Text('속도 x${speed.toStringAsFixed(speed % 1 == 0 ? 0 : 2)}', style: TextStyle(fontSize: compact ? 14 : 16, fontWeight: FontWeight.w700)),
            ),
            btn(icon: Icons.add, label: '속도 증가', onTap: speedUp),
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
          if (combo > 1) '콤보': 'x$combo',
          if (backToBack) 'B2B': 'ON',
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
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Flexible(child: scoreCol),
                  const SizedBox(width: 8),
                  Flexible(child: holdCol),
                  const SizedBox(width: 8),
                  Flexible(child: nextCol),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    scoreCol,
                    const Divider(height: 16),
                    holdCol,
                    const SizedBox(height: 12),
                    nextCol,
                  ],
                ),
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

  Widget _preview(TetrisPiece b, {double size = 80}) => SizedBox(
        width: size,
        height: size,
        child: GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          children: List.generate(16, (i) {
            final r = i ~/ 4;
            final c = i % 4;
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
