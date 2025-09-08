import 'dart:math';
import 'package:flutter/material.dart';

// ▶︎ 플레이 방법 바텀시트/페이지
import 'pelican_sorter_howto.dart';

/// 펠리컨 소터: 논리 카드 추론 게임 (Page)
class PelicanSorterPage extends StatefulWidget {
  const PelicanSorterPage({super.key});
  @override
  State<PelicanSorterPage> createState() => _PelicanSorterPageState();
}

// ==========================
//  데이터 모델
// ==========================

enum Dest { east, west, south, north }
enum Weight { light, normal, heavy, over }
enum WrapColor { red, blue, green, yellow }
enum Priority { p1, p2, p3, p4 }

String destName(Dest d) => switch (d) {
  Dest.east => '동',
  Dest.west => '서',
  Dest.south => '남',
  Dest.north => '북',
};
String weightName(Weight w) => switch (w) {
  Weight.light => '가벼움',
  Weight.normal => '보통',
  Weight.heavy => '무거움',
  Weight.over => '과중',
};
String colorName(WrapColor c) => switch (c) {
  WrapColor.red => '빨강',
  WrapColor.blue => '파랑',
  WrapColor.green => '초록',
  WrapColor.yellow => '노랑',
};
String priorityName(Priority p) => switch (p) {
  Priority.p1 => '1',
  Priority.p2 => '2',
  Priority.p3 => '3',
  Priority.p4 => '4',
};

Color colorValue(WrapColor c) => switch (c) {
  WrapColor.red => const Color(0xFFE53935),
  WrapColor.blue => const Color(0xFF1E88E5),
  WrapColor.green => const Color(0xFF43A047),
  WrapColor.yellow => const Color(0xFFFDD835),
};

@immutable
class PackageCard {
  final int id; // 고유 ID (속성 인코딩)
  final Dest dest;
  final Weight weight;
  final WrapColor color;
  final Priority priority;
  const PackageCard({
    required this.id,
    required this.dest,
    required this.weight,
    required this.color,
    required this.priority,
  });

  @override
  bool operator ==(Object other) => other is PackageCard && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

@immutable
class Cell {
  final int row;
  final int col;
  final PackageCard card;
  const Cell({required this.row, required this.col, required this.card});
}

class Grid {
  final List<List<Cell>> cells; // 4x4
  const Grid(this.cells);

  Iterable<Cell> allCells() => cells.expand((e) => e);

  int countByColor(WrapColor c) => allCells().where((x) => x.card.color == c).length;
  int countByDest(Dest d) => allCells().where((x) => x.card.dest == d).length;
  int countByWeight(Weight w) => allCells().where((x) => x.card.weight == w).length;
  int countByPriority(Priority p) => allCells().where((x) => x.card.priority == p).length;

  int countColorInRow(int r, WrapColor c) => cells[r].where((x) => x.card.color == c).length;
  int countColorInCol(int c, WrapColor col) => cells.map((row) => row[c]).where((x) => x.card.color == col).length;
}

// ==========================
//  힌트 시스템
// ==========================

abstract class Hint {
  String get text;
  bool matches(Cell candidate, Grid grid);
  int get weight;
}

class AttrEqualsHint<T> extends Hint {
  final String _text;
  final T Function(PackageCard) picker;
  final T value;
  final int _weight;
  AttrEqualsHint(this._text, this.picker, this.value, {int w = 6}) : _weight = w;
  @override
  String get text => _text;
  @override
  int get weight => _weight;
  @override
  bool matches(Cell candidate, Grid grid) => picker(candidate.card) == value;
}

class AttrNotEqualsHint<T> extends Hint {
  final String _text;
  final T Function(PackageCard) picker;
  final T value;
  final int _weight;
  AttrNotEqualsHint(this._text, this.picker, this.value, {int w = 4}) : _weight = w;
  @override
  String get text => _text;
  @override
  int get weight => _weight;
  @override
  bool matches(Cell candidate, Grid grid) => picker(candidate.card) != value;
}

class RowMembershipHint extends Hint {
  final int row;
  final bool inRow;
  RowMembershipHint(this.row, this.inRow);
  @override
  String get text => inRow ? '타깃은 ${row + 1}행에 있다.' : '타깃은 ${row + 1}행에 없다.';
  @override
  int get weight => inRow ? 5 : 3;
  @override
  bool matches(Cell candidate, Grid grid) => inRow ? candidate.row == row : candidate.row != row;
}

class ColMembershipHint extends Hint {
  final int col;
  final bool inCol;
  ColMembershipHint(this.col, this.inCol);
  @override
  String get text => inCol ? '타깃은 ${col + 1}열에 있다.' : '타깃은 ${col + 1}열에 없다.';
  @override
  int get weight => inCol ? 5 : 3;
  @override
  bool matches(Cell candidate, Grid grid) => inCol ? candidate.col == col : candidate.col != col;
}

class CountSameAttrHint<T> extends Hint {
  final String _text;
  final int Function(Grid, T) counter;
  final T Function(PackageCard) picker;
  final int expected;
  CountSameAttrHint(this._text, this.counter, this.picker, this.expected);
  @override
  String get text => _text;
  @override
  int get weight => 5;
  @override
  bool matches(Cell candidate, Grid grid) => counter(grid, picker(candidate.card)) == expected;
}

class ParityPriorityHint extends Hint {
  final bool even;
  ParityPriorityHint(this.even);
  @override
  String get text => even ? '타깃의 우선순위(숫자)는 짝수다.' : '타깃의 우선순위(숫자)는 홀수다.';
  @override
  int get weight => 4;
  int _priNumber(Priority p) => switch (p) { Priority.p1 => 1, Priority.p2 => 2, Priority.p3 => 3, Priority.p4 => 4 };
  @override
  bool matches(Cell candidate, Grid grid) => (_priNumber(candidate.card.priority) % 2 == 0) == even;
}

class CornerCenterHint extends Hint {
  final String place; // 'corner' | 'edge' | 'center'
  CornerCenterHint(this.place);
  @override
  String get text => switch (place) {
    'corner' => '타깃은 모서리에 있다.',
    'edge' => '타깃은 테두리(모서리 제외)에 있다.',
    _ => '타깃은 중앙(2×2)에 있다.',
  };
  @override
  int get weight => 4;
  bool _isCorner(Cell c) => (c.row == 0 || c.row == 3) && (c.col == 0 || c.col == 3);
  bool _isCenter(Cell c) => (c.row == 1 || c.row == 2) && (c.col == 1 || c.col == 2);
  bool _isEdge(Cell c) => !(_isCorner(c) || _isCenter(c));
  @override
  bool matches(Cell candidate, Grid grid) => switch (place) {
    'corner' => _isCorner(candidate),
    'center' => _isCenter(candidate),
    _ => _isEdge(candidate),
  };
}

// ==========================
//  퍼즐 생성기 & 솔버
// ==========================

class Puzzle {
  final Grid grid;
  final Cell target;
  final List<Hint> hintPlan;
  Puzzle({required this.grid, required this.target, required this.hintPlan});
}

class PuzzleGenerator {
  final Random rnd;
  PuzzleGenerator([int? seed]) : rnd = Random(seed);

  Grid _generateBoard() {
    final all = <PackageCard>[];
    int id = 0;
    for (final d in Dest.values) {
      for (final w in Weight.values) {
        for (final c in WrapColor.values) {
          for (final p in Priority.values) {
            all.add(PackageCard(id: id++, dest: d, weight: w, color: c, priority: p));
          }
        }
      }
    }
    all.shuffle(rnd);
    final sample = all.take(16).toList();
    final cells = List.generate(4, (r) => List.generate(4, (c) {
      final card = sample[r * 4 + c];
      return Cell(row: r, col: c, card: card);
    }));
    return Grid(cells);
  }

  List<Hint> _generateHints(Grid grid, Cell target) {
    final hints = <Hint>[];

    hints.add(AttrEqualsHint<WrapColor>('타깃의 포장색은 ${colorName(target.card.color)}이다.', (x) => x.color, target.card.color, w: 7));
    hints.add(AttrEqualsHint<Dest>('타깃의 목적지는 ${destName(target.card.dest)}이다.', (x) => x.dest, target.card.dest, w: 7));
    hints.add(AttrEqualsHint<Weight>('타깃의 중량은 ${weightName(target.card.weight)}이다.', (x) => x.weight, target.card.weight, w: 7));
    hints.add(AttrEqualsHint<Priority>('타깃의 우선순위는 ${priorityName(target.card.priority)}이다.', (x) => x.priority, target.card.priority, w: 7));

    for (final c in WrapColor.values) {
      if (c != target.card.color) {
        hints.add(AttrNotEqualsHint<WrapColor>('타깃의 포장색은 ${colorName(c)}이 아니다.', (x) => x.color, c, w: 4));
      }
    }
    for (final d in Dest.values) {
      if (d != target.card.dest) {
        hints.add(AttrNotEqualsHint<Dest>('타깃의 목적지는 ${destName(d)}가 아니다.', (x) => x.dest, d, w: 4));
      }
    }
    for (final w in Weight.values) {
      if (w != target.card.weight) {
        hints.add(AttrNotEqualsHint<Weight>('타깃의 중량은 ${weightName(w)}이 아니다.', (x) => x.weight, w, w: 4));
      }
    }
    for (final p in Priority.values) {
      if (p != target.card.priority) {
        hints.add(AttrNotEqualsHint<Priority>('타깃의 우선순위는 ${priorityName(p)}가 아니다.', (x) => x.priority, p, w: 4));
      }
    }

    hints.add(RowMembershipHint(target.row, true));
    for (int r = 0; r < 4; r++) {
      if (r != target.row) hints.add(RowMembershipHint(r, false));
    }
    hints.add(ColMembershipHint(target.col, true));
    for (int c = 0; c < 4; c++) {
      if (c != target.col) hints.add(ColMembershipHint(c, false));
    }

    final cc = grid.countByColor(target.card.color);
    hints.add(CountSameAttrHint<WrapColor>('타깃과 같은 색의 카드는 총 ${cc}장이다.', (g, v) => g.countByColor(v), (x) => x.color, cc));
    final cd = grid.countByDest(target.card.dest);
    hints.add(CountSameAttrHint<Dest>('타깃과 같은 목적지 카드는 총 ${cd}장이다.', (g, v) => g.countByDest(v), (x) => x.dest, cd));
    final cw = grid.countByWeight(target.card.weight);
    hints.add(CountSameAttrHint<Weight>('타깃과 같은 중량 카드는 총 ${cw}장이다.', (g, v) => g.countByWeight(v), (x) => x.weight, cw));
    final cp = grid.countByPriority(target.card.priority);
    hints.add(CountSameAttrHint<Priority>('타깃과 같은 우선순위 카드는 총 ${cp}장이다.', (g, v) => g.countByPriority(v), (x) => x.priority, cp));

    final pnum = switch (target.card.priority) { Priority.p1 => 1, Priority.p2 => 2, Priority.p3 => 3, Priority.p4 => 4 };
    hints.add(ParityPriorityHint(pnum % 2 == 0));

    final ccHint = CornerCenterHint(_placeOf(target));
    hints.add(ccHint);

    return hints;
  }

  String _placeOf(Cell c) {
    final corner = (c.row == 0 || c.row == 3) && (c.col == 0 || c.col == 3);
    final center = (c.row == 1 || c.row == 2) && (c.col == 1 || c.col == 2);
    if (corner) return 'corner';
    if (center) return 'center';
    return 'edge';
  }

  List<Cell> solve(Grid grid, List<Hint> revealed) {
    return grid.allCells().where((c) => revealed.every((h) => h.matches(c, grid))).toList(growable: false);
  }

  Puzzle createPuzzle({Difficulty diff = Difficulty.normal}) {
    final grid = _generateBoard();
    final target = grid.allCells().toList()[rnd.nextInt(16)];
    final allHints = _generateHints(grid, target);

    final plan = <Hint>[];
    var candidates = grid.allCells().toList();
    final pool = allHints.toList();

    while (candidates.length > 1 && pool.isNotEmpty) {
      Hint? best;
      int bestRemain = 999;
      for (final h in pool) {
        final remain = candidates.where((c) => h.matches(c, grid)).length;
        if (remain < bestRemain || (remain == bestRemain && (best == null || h.weight > best.weight))) {
          best = h;
          bestRemain = remain;
        }
      }
      if (best == null) break;
      plan.add(best);
      pool.remove(best);
      candidates = candidates.where((c) => best!.matches(c, grid)).toList();
    }

    if (candidates.length != 1) {
      final strong = allHints.whereType<AttrEqualsHint>().toList();
      for (final h in strong) {
        if (!plan.contains(h)) {
          plan.add(h);
          candidates = candidates.where((c) => h.matches(c, grid)).toList();
          if (candidates.length == 1) break;
        }
      }
    }
    if (candidates.length != 1) {
      final posHints = allHints.where((h) => h is RowMembershipHint || h is ColMembershipHint).toList();
      for (final h in posHints) {
        if (!plan.contains(h)) {
          plan.add(h);
          candidates = candidates.where((c) => h.matches(c, grid)).toList();
          if (candidates.length == 1) break;
        }
      }
    }
    if (candidates.length != 1) {
      plan.add(RowMembershipHint(target.row, true));
      plan.add(ColMembershipHint(target.col, true));
    }

    return Puzzle(grid: grid, target: target, hintPlan: plan);
  }
}

// ==========================
//  난이도 & 게임 상태
// ==========================

enum Difficulty { easy, normal, hard }

class GameState {
  final Puzzle puzzle;
  final Difficulty difficulty;
  final List<Hint> revealed;
  final List<Hint> deck;
  final Set<int> eliminatedIds;
  final int turn;
  final int ap;
  final int hintsUsed;
  final bool ended;
  final bool? win;

  GameState({
    required this.puzzle,
    required this.difficulty,
    required this.revealed,
    required this.deck,
    required this.eliminatedIds,
    required this.turn,
    required this.ap,
    required this.hintsUsed,
    required this.ended,
    required this.win,
  });

  GameState copyWith({
    List<Hint>? revealed,
    List<Hint>? deck,
    Set<int>? eliminatedIds,
    int? turn,
    int? ap,
    int? hintsUsed,
    bool? ended,
    bool? win,
  }) =>
      GameState(
        puzzle: puzzle,
        difficulty: difficulty,
        revealed: revealed ?? this.revealed,
        deck: deck ?? this.deck,
        eliminatedIds: eliminatedIds ?? this.eliminatedIds,
        turn: turn ?? this.turn,
        ap: ap ?? this.ap,
        hintsUsed: hintsUsed ?? this.hintsUsed,
        ended: ended ?? this.ended,
        win: win ?? this.win,
      );
}

int apPerTurn(Difficulty d) => switch (d) {
  Difficulty.easy => 3,
  Difficulty.normal => 2,
  Difficulty.hard => 2,
};
int initialHints(Difficulty d) => switch (d) {
  Difficulty.easy => 3,
  Difficulty.normal => 2,
  Difficulty.hard => 1,
};

// ==========================
//  페이지 구현
// ==========================

class _PelicanSorterPageState extends State<PelicanSorterPage> {
  Difficulty _diff = Difficulty.normal;
  late PuzzleGenerator _gen;
  GameState? _state;

  // ▶︎ 후보 하이라이트 토글 (기본 끔)
  bool _showCandidates = false;

  @override
  void initState() {
    super.initState();
    _gen = PuzzleGenerator();
    _newGame();
  }

  bool _isStrongHint(Hint h) =>
      h is AttrEqualsHint ||
          (h is RowMembershipHint && h.inRow) ||
          (h is ColMembershipHint && h.inCol);

  void _newGame() {
    final puzzle = _gen.createPuzzle(diff: _diff);
    var deck = puzzle.hintPlan.toList();

    final initCount = initialHints(_diff);
    final revealed = <Hint>[];

    // 1) 초기 힌트는 강한 힌트 제외 우선 선택
    // 2) 후보가 1개가 되면 해당 힌트는 초기 공개에서 제외(덱 뒤로 보냄)
    while (revealed.length < initCount && deck.isNotEmpty) {
      // 가능한 한 약한 힌트를 우선 선택
      int idx = deck.indexWhere((h) => !_isStrongHint(h));
      if (idx == -1) idx = 0; // 어쩔 수 없으면 아무거나

      final cand = deck.removeAt(idx);
      final test = [...revealed, cand];
      final remain = _gen.solve(puzzle.grid, test).length;

      if (remain > 1) {
        revealed.add(cand);
      } else {
        // 너무 강해서 정답이 드러나므로 초기 공개에서 제외하고 덱 뒤로
        deck.add(cand);

        // 더 이상 약한 힌트가 없으면 초기 힌트 추가 중단
        if (deck.every(_isStrongHint)) break;
      }
    }

    // 최종 가드: 혹시나 후보가 1개면 마지막 공개 힌트를 덱 앞으로 되돌림
    if (_gen.solve(puzzle.grid, revealed).length <= 1 && revealed.isNotEmpty) {
      deck.insert(0, revealed.removeLast());
    }

    _state = GameState(
      puzzle: puzzle,
      difficulty: _diff,
      revealed: revealed,
      deck: deck,
      eliminatedIds: <int>{},
      turn: 1,
      ap: apPerTurn(_diff),
      hintsUsed: 0,
      ended: false,
      win: null,
    );

    // 새 게임 시 후보 하이라이트는 끔
    _showCandidates = false;

    setState(() {});
  }

  void _nextTurn() {
    if (_state == null || _state!.ended) return;
    setState(() => _state = _state!.copyWith(turn: _state!.turn + 1, ap: apPerTurn(_diff)));
  }

  void _revealNextHint() {
    final s = _state!;
    if (s.ap < 2 || s.deck.isEmpty || s.ended) return;
    final next = s.deck.first;
    final newDeck = s.deck.sublist(1);
    setState(() => _state = s.copyWith(
      revealed: [...s.revealed, next],
      deck: newDeck,
      ap: s.ap - 2,
      hintsUsed: s.hintsUsed + 1,
    ));
  }

  void _scanDialog() async {
    final s = _state!;
    if (s.ap < 2 || s.ended) return;
    final res = await showDialog<_ScanParams>(
      context: context,
      builder: (_) => _ScanDialog(),
    );
    if (res == null) return;
    final g = s.puzzle.grid;
    int count = 0;
    switch (res.mode) {
      case ScanMode.row:
        switch (res.type) {
          case ScanType.color:
            count = g.countColorInRow(res.index, res.color!);
            break;
          case ScanType.dest:
            count = g.cells[res.index].where((c) => c.card.dest == res.dest!).length;
            break;
          case ScanType.weight:
            count = g.cells[res.index].where((c) => c.card.weight == res.weight!).length;
            break;
          case ScanType.priority:
            count = g.cells[res.index].where((c) => c.card.priority == res.priority!).length;
            break;
        }
        break;
      case ScanMode.col:
        switch (res.type) {
          case ScanType.color:
            count = g.countColorInCol(res.index, res.color!);
            break;
          case ScanType.dest:
            count = g.cells.map((r) => r[res.index]).where((c) => c.card.dest == res.dest!).length;
            break;
          case ScanType.weight:
            count = g.cells.map((r) => r[res.index]).where((c) => c.card.weight == res.weight!).length;
            break;
          case ScanType.priority:
            count = g.cells.map((r) => r[res.index]).where((c) => c.card.priority == res.priority!).length;
            break;
        }
        break;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${res.index + 1}${res.mode == ScanMode.row ? '행' : '열'}에서 ${res.describe()} → $count개'),
      duration: const Duration(seconds: 3),
    ));
    setState(() => _state = s.copyWith(ap: s.ap - 2));
  }

  void _inquireCell(Cell cell) {
    final s = _state!;
    if (s.ap < 1 || s.ended) return;
    final possible = _gen.solve(s.puzzle.grid, s.revealed).any((c) => c.card.id == cell.card.id);
    if (!possible) {
      final newElim = {...s.eliminatedIds}..add(cell.card.id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('배제됨: 이 카드는 타깃일 수 없습니다.')));
      setState(() => _state = s.copyWith(ap: s.ap - 1, eliminatedIds: newElim));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('아직 가능성 있음: 힌트가 더 필요합니다.')));
      setState(() => _state = s.copyWith(ap: s.ap - 1));
    }
  }

  void _declare(Cell cell) {
    final s = _state!;
    if (s.ended) return;
    final win = cell.card.id == s.puzzle.target.card.id;
    setState(() => _state = s.copyWith(ended: true, win: win));
    _showEndDialog(win);
  }

  void _showEndDialog(bool win) {
    final s = _state!;
    final scoreBase = 100 - (s.turn - 1) * 5 - (s.hintsUsed * 3) + s.ap;
    final mult = switch (s.difficulty) { Difficulty.easy => 1.0, Difficulty.normal => 1.2, Difficulty.hard => 1.5 };
    final score = max(0, (scoreBase * mult).round());
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(win ? '정답! 🎉' : '오답 😵'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('점수: $score'),
            const SizedBox(height: 8),
            Text('정답 카드: ${_cardSummary(s.puzzle.target.card)} (${s.puzzle.target.row + 1}행 ${s.puzzle.target.col + 1}열)'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('닫기')),
          FilledButton(onPressed: () { Navigator.of(context).pop(); _newGame(); }, child: const Text('새 게임')),
        ],
      ),
    );
  }

  String _cardSummary(PackageCard c) =>
      '${destName(c.dest)} / ${weightName(c.weight)} / ${colorName(c.color)} / 우선순위 ${priorityName(c.priority)}';

  @override
  Widget build(BuildContext context) {
    final s = _state;
    if (s == null) return const SizedBox();

    final candidates = _gen.solve(s.puzzle.grid, s.revealed).map((e) => e.card.id).toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('펠리컨 소터: 밀수 패키지'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          // ▶︎ 플레이 방법 버튼
          IconButton(
            tooltip: '플레이 방법',
            icon: const Icon(Icons.help_center_outlined),
            onPressed: () => showPelicanSorterHowToSheet(context),
          ),
          // ▶︎ 후보 하이라이트 토글
          IconButton(
            tooltip: _showCandidates ? '후보 하이라이트 끄기' : '후보 하이라이트 켜기',
            icon: Icon(_showCandidates ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _showCandidates = !_showCandidates),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<Difficulty>(
              value: _diff,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _diff = v);
                _newGame();
              },
              items: const [
                DropdownMenuItem(value: Difficulty.easy, child: Text('Easy')),
                DropdownMenuItem(value: Difficulty.normal, child: Text('Normal')),
                DropdownMenuItem(value: Difficulty.hard, child: Text('Hard')),
              ],
            ),
          ),
          IconButton(onPressed: _newGame, tooltip: '새 게임', icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          // 상단 정보바: Row → Wrap (줄바꿈 허용)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _pill(Icons.filter_center_focus, '후보 ${candidates.length}'),
                _pill(Icons.flash_on, 'AP ${s.ap}/${apPerTurn(_diff)}'),
                _pill(Icons.turn_right, '턴 ${s.turn}'),
                if (s.ended && s.win == true)
                  const _StatusChip(text: 'You Win!', color: Colors.green),
                if (s.ended && s.win == false)
                  const _StatusChip(text: 'Game Over', color: Colors.redAccent),
              ],
            ),
          ),

          // 보드
          Expanded(
            child: LayoutBuilder(builder: (context, cons) {
              final side = min(cons.maxWidth, cons.maxHeight);
              return Center(
                child: SizedBox(
                  width: side,
                  height: side,
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 16,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4),
                    itemBuilder: (_, i) {
                      final r = i ~/ 4;
                      final c = i % 4;
                      final cell = s.puzzle.grid.cells[r][c];
                      final eliminated = s.eliminatedIds.contains(cell.card.id);
                      final isCandidate = candidates.contains(cell.card.id);
                      return _CardTile(
                        cell: cell,
                        eliminated: eliminated,
                        // ▶︎ 하이라이트는 사용자가 켠 경우에만 표시
                        candidate: _showCandidates && isCandidate,
                        onInquire: s.ap >= 1 && !s.ended ? () => _inquireCell(cell) : null,
                        onDeclare: !s.ended ? () => _declare(cell) : null,
                      );
                    },
                  ),
                ),
              );
            }),
          ),

          // 힌트 패널 + 컨트롤
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: (s.ap >= 2 && s.deck.isNotEmpty && !s.ended) ? _revealNextHint : null,
                      icon: const Icon(Icons.tips_and_updates),
                      label: const Text('새 힌트(2AP)'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: (s.ap >= 2 && !s.ended) ? _scanDialog : null,
                      icon: const Icon(Icons.search),
                      label: const Text('스캔(2AP)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: !s.ended ? _nextTurn : null,
                      icon: const Icon(Icons.skip_next),
                      label: const Text('다음 턴(AP 리필)'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final h in s.revealed) _hintChip(h.text),
                ]),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _hintChip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.amber.withOpacity(.15),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.amber.withOpacity(.5)),
    ),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusChip({required this.text, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.4)),
      ),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
    );
  }
}

// ==========================
//  카드 타일 (오버플로우 방지형 컴팩트 레이아웃)
// ==========================

class _CardTile extends StatelessWidget {
  final Cell cell;
  final bool eliminated;
  final bool candidate;
  final VoidCallback? onInquire;
  final VoidCallback? onDeclare;
  const _CardTile({
    required this.cell,
    required this.eliminated,
    required this.candidate,
    this.onInquire,
    this.onDeclare,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(6.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showActions(context),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black.withOpacity(.08)),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: _cardBody(context)),
                if (candidate)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Icon(Icons.check_circle, color: cs.primary, size: 18),
                  ),
                if (eliminated)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white.withOpacity(.6),
                      child: const Center(child: Icon(Icons.close_rounded, color: Colors.redAccent, size: 36)),
                    ),
                  ),
                Positioned(
                  left: 4,
                  top: 4,
                  child: Text('${cell.row + 1}-${cell.col + 1}', style: TextStyle(color: Colors.black.withOpacity(.35), fontSize: 10)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardBody(BuildContext context) {
    final c = cell.card;
    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        final h = cons.maxHeight;
        final micro = w < 72 || h < 72;
        final compact = w < 90 || h < 90;

        final pad = EdgeInsets.all(micro ? 4 : (compact ? 6 : 8));
        final titleSize = micro ? 10.0 : (compact ? 11.0 : 12.0);
        final chipTextSize = micro ? 9.0 : 10.0;
        final iconSize = micro ? 16.0 : (compact ? 18.0 : 22.0);

        return Padding(
          padding: pad,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 상단 행: 색상 원, 이름, 우선순위 칩
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _roundIcon(colorValue(c.color), size: iconSize),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      colorName(c.color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: titleSize),
                    ),
                  ),
                  if (!micro)
                    Flexible(
                      fit: FlexFit.loose,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _priorityChip('P${priorityName(c.priority)}', textSize: chipTextSize),
                      ),
                    ),
                ],
              ),
              SizedBox(height: micro ? 4 : 6),

              // 하단 정보: 매우 작은 타일에선 1줄, 그 외 2태그
              if (micro)
                _miniTags(destName(c.dest), weightName(c.weight), textSize: 9)
              else
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _tag(Icons.place_rounded, destName(c.dest), textSize: 10),
                      _tag(Icons.scale_rounded, weightName(c.weight), textSize: 10),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _roundIcon(Color color, {double size = 22}) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));

  Widget _priorityChip(String text, {double textSize = 10}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(.06),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, fontSize: textSize)),
  );

  Widget _tag(IconData icon, String text, {double textSize = 10}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(color: Colors.black.withOpacity(.05), borderRadius: BorderRadius.circular(8)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 12), const SizedBox(width: 4), Text(text, style: TextStyle(fontWeight: FontWeight.w700, fontSize: textSize))],
    ),
  );

  Widget _miniTags(String a, String b, {double textSize = 9}) => Row(
    children: [
      Expanded(child: Text(a, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: textSize))),
      const SizedBox(width: 6),
      Expanded(child: Text(b, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.black87, fontSize: textSize))),
    ],
  );

  void _showActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('선택한 카드', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SizedBox(height: 120, child: _cardBody(context)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: FilledButton.icon(onPressed: onInquire, icon: const Icon(Icons.help_outline), label: const Text('질의(배제 확인) 1AP'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton.tonalIcon(onPressed: onDeclare, icon: const Icon(Icons.check), label: const Text('정답 선언'))),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================
//  스캔 다이얼로그
// ==========================

enum ScanMode { row, col }
enum ScanType { color, dest, weight, priority }

class _ScanParams {
  final ScanMode mode;
  final int index;
  final ScanType type;
  final WrapColor? color;
  final Dest? dest;
  final Weight? weight;
  final Priority? priority;
  _ScanParams({required this.mode, required this.index, required this.type, this.color, this.dest, this.weight, this.priority});
  String describe() {
    final axis = mode == ScanMode.row ? '행' : '열';
    final what = switch (type) {
      ScanType.color => colorName(color!),
      ScanType.dest => destName(dest!),
      ScanType.weight => weightName(weight!),
      ScanType.priority => '우선순위 ${priorityName(priority!)}',
    };
    return '$axis에 ${what}';
  }
}

class _ScanDialog extends StatefulWidget {
  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<_ScanDialog> {
  ScanMode mode = ScanMode.row;
  int index = 0;
  ScanType type = ScanType.color;
  WrapColor color = WrapColor.red;
  Dest dest = Dest.east;
  Weight weight = Weight.light;
  Priority priority = Priority.p1;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('스캔 설정(2AP)'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Text('대상:'),
            const SizedBox(width: 8),
            DropdownButton<ScanMode>(value: mode, onChanged: (v) => setState(() => mode = v!), items: const [
              DropdownMenuItem(value: ScanMode.row, child: Text('행')),
              DropdownMenuItem(value: ScanMode.col, child: Text('열')),
            ]),
            const SizedBox(width: 12),
            const Text('번호:'),
            const SizedBox(width: 8),
            DropdownButton<int>(value: index, onChanged: (v) => setState(() => index = v!), items: const [
              DropdownMenuItem(value: 0, child: Text('1')),
              DropdownMenuItem(value: 1, child: Text('2')),
              DropdownMenuItem(value: 2, child: Text('3')),
              DropdownMenuItem(value: 3, child: Text('4')),
            ]),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Text('속성:'),
            const SizedBox(width: 8),
            DropdownButton<ScanType>(value: type, onChanged: (v) => setState(() => type = v!), items: const [
              DropdownMenuItem(value: ScanType.color, child: Text('색')),
              DropdownMenuItem(value: ScanType.dest, child: Text('목적지')),
              DropdownMenuItem(value: ScanType.weight, child: Text('중량')),
              DropdownMenuItem(value: ScanType.priority, child: Text('우선순위')),
            ]),
            const SizedBox(width: 12),
            Expanded(child: _valuePicker()),
          ]),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
        FilledButton(onPressed: () {
          final params = _ScanParams(mode: mode, index: index, type: type, color: color, dest: dest, weight: weight, priority: priority);
          Navigator.of(context).pop(params);
        }, child: const Text('스캔')),
      ],
    );
  }

  Widget _valuePicker() {
    switch (type) {
      case ScanType.color:
        return DropdownButton<WrapColor>(value: color, isExpanded: true, onChanged: (v) => setState(() => color = v!), items: const [
          DropdownMenuItem(value: WrapColor.red, child: Text('빨강')),
          DropdownMenuItem(value: WrapColor.blue, child: Text('파랑')),
          DropdownMenuItem(value: WrapColor.green, child: Text('초록')),
          DropdownMenuItem(value: WrapColor.yellow, child: Text('노랑')),
        ]);
      case ScanType.dest:
        return DropdownButton<Dest>(value: dest, isExpanded: true, onChanged: (v) => setState(() => dest = v!), items: const [
          DropdownMenuItem(value: Dest.east, child: Text('동')),
          DropdownMenuItem(value: Dest.west, child: Text('서')),
          DropdownMenuItem(value: Dest.south, child: Text('남')),
          DropdownMenuItem(value: Dest.north, child: Text('북')),
        ]);
      case ScanType.weight:
        return DropdownButton<Weight>(value: weight, isExpanded: true, onChanged: (v) => setState(() => weight = v!), items: const [
          DropdownMenuItem(value: Weight.light, child: Text('가벼움')),
          DropdownMenuItem(value: Weight.normal, child: Text('보통')),
          DropdownMenuItem(value: Weight.heavy, child: Text('무거움')),
          DropdownMenuItem(value: Weight.over, child: Text('과중')),
        ]);
      case ScanType.priority:
        return DropdownButton<Priority>(value: priority, isExpanded: true, onChanged: (v) => setState(() => priority = v!), items: const [
          DropdownMenuItem(value: Priority.p1, child: Text('1')),
          DropdownMenuItem(value: Priority.p2, child: Text('2')),
          DropdownMenuItem(value: Priority.p3, child: Text('3')),
          DropdownMenuItem(value: Priority.p4, child: Text('4')),
        ]);
    }
  }
}
