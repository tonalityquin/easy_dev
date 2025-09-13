import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'mine_state.dart';
import 'mine_models.dart';

class MineBoardView extends StatelessWidget {
  final BoardLogic board;
  final void Function(int r, int c) onTap;
  final void Function(int r, int c) onLongPressOrRightClick;
  final void Function(int r, int c) onChord;
  final bool revealMines;

  const MineBoardView({
    super.key,
    required this.board,
    required this.onTap,
    required this.onLongPressOrRightClick,
    required this.onChord,
    required this.revealMines,
  });

  @override
  Widget build(BuildContext context) {
    final rows = board.rows;
    final cols = board.cols;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
      ),
      itemCount: rows * cols,
      itemBuilder: (context, idx) {
        final r = idx ~/ cols;
        final c = idx % cols;
        final s = board.cell(r, c);
        return _MineTile(
          r: r,
          c: c,
          s: s,
          onTap: onTap,
          onLongPressOrRightClick: onLongPressOrRightClick,
          onChord: onChord,
          revealMines: revealMines,
        );
      },
    );
  }
}

class _MineTile extends StatelessWidget {
  final int r, c;
  final Cell s;
  final void Function(int r, int c) onTap;
  final void Function(int r, int c) onLongPressOrRightClick;
  final void Function(int r, int c) onChord;
  final bool revealMines;

  const _MineTile({
    required this.r,
    required this.c,
    required this.s,
    required this.onTap,
    required this.onLongPressOrRightClick,
    required this.onChord,
    required this.revealMines,
  });

  @override
  Widget build(BuildContext context) {
    final isOpen = s.open || (revealMines && s.mine);
    final bg = _tileBg(context, isOpen, s.exploded);
    final border = Border.all(color: Colors.black.withOpacity(0.08));
    final child = _content();

    final tile = Container(
      decoration: BoxDecoration(color: bg, border: border),
      child: Center(child: child),
    );

    // 데스크톱/웹: 우클릭=깃발, 모바일: 롱프레스=깃발, 더블탭=Chord
    return Listener(
      onPointerDown: (ev) {
        if (ev.kind == PointerDeviceKind.mouse && ev.buttons == kSecondaryMouseButton) {
          onLongPressOrRightClick(r, c);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(r, c),
        onLongPress: () => onLongPressOrRightClick(r, c),
        onDoubleTap: () => onChord(r, c),
        child: tile,
      ),
    );
  }

  Color _tileBg(BuildContext ctx, bool isOpen, bool exploded) {
    final cs = Theme.of(ctx).colorScheme;
    if (exploded) return Colors.red.withOpacity(0.45);
    if (isOpen) return cs.surfaceVariant.withOpacity(0.6);
    return cs.surface;
  }

  Widget _content() {
    if (s.open) {
      if (s.mine) {
        return const Icon(Icons.circle, size: 14);
      }
      if (s.adj > 0) {
        return Text(
          '${s.adj}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: _numColor(s.adj),
          ),
        );
      }
      return const SizedBox.shrink();
    } else {
      if (s.flagged) {
        return const Icon(Icons.flag, size: 16, color: Colors.deepOrange);
      }
      if (revealMines && s.mine) {
        return const Icon(Icons.circle, size: 14);
      }
      return const SizedBox.shrink();
    }
  }

  Color _numColor(int n) {
    switch (n) {
      case 1: return const Color(0xFF1976D2);
      case 2: return const Color(0xFF388E3C);
      case 3: return const Color(0xFFD32F2F);
      case 4: return const Color(0xFF7B1FA2);
      case 5: return const Color(0xFFF57C00);
      case 6: return const Color(0xFF0097A7);
      case 7: return const Color(0xFF5D4037);
      case 8: return const Color(0xFF455A64);
      default: return Colors.black87;
    }
  }
}
