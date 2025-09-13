import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mine_package/mine_models.dart';
import 'mine_package/mine_gen.dart';
import 'mine_package/mine_state.dart';
import 'mine_package/mine_ui.dart';

class Minesweeper extends StatefulWidget {
  const Minesweeper({super.key});

  @override
  State<Minesweeper> createState() => _MinesweeperState();
}

class _MinesweeperState extends State<Minesweeper> with WidgetsBindingObserver {
  // ── 설정
  Difficulty _diff = Difficulties.intermediate;
  bool _fairPuzzle = true; // 공정 퍼즐(노게스) 생성
  bool _assist = false;    // 자동 추론 보조
  int? _seed;              // 시드(선택)

  // ── 진행
  GameStatus _status = GameStatus.ready;
  bool _generating = false;
  late BoardLogic _board;

  // ── 타이머/통계
  final Stopwatch _watch = Stopwatch();
  Timer? _ticker;
  int get _elapsed => _watch.elapsed.inSeconds;

  String get _bestKey => 'ms.best.${_diff.key}';
  String get _winsKey => 'ms.wins.${_diff.key}';
  String get _lossKey => 'ms.loss.${_diff.key}';

  int? _bestTime;
  int _wins = 0;
  int _loss = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _board = BoardLogic(rows: _diff.rows, cols: _diff.cols, mines: _diff.mines);
    _loadStats();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _ticker?.cancel();
    } else if (_status == GameStatus.playing) {
      _startTicker();
    }
  }

  Future<void> _loadStats() async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _bestTime = sp.getInt(_bestKey);
      _wins = sp.getInt(_winsKey) ?? 0;
      _loss = sp.getInt(_lossKey) ?? 0;
    });
  }

  Future<void> _saveBestIfNeeded() async {
    final sp = await SharedPreferences.getInstance();
    if (_status == GameStatus.won) {
      if (_bestTime == null || _elapsed < _bestTime!) {
        _bestTime = _elapsed;
        await sp.setInt(_bestKey, _elapsed);
      }
      _wins += 1;
      await sp.setInt(_winsKey, _wins);
    } else if (_status == GameStatus.lost) {
      _loss += 1;
      await sp.setInt(_lossKey, _loss);
    }
    if (mounted) setState(() {});
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopTicker() => _ticker?.cancel();

  void _newGame({Difficulty? diff}) {
    if (diff != null) _diff = diff;
    _watch.reset();
    _stopTicker();
    _status = GameStatus.ready;
    _generating = false;
    _board = BoardLogic(rows: _diff.rows, cols: _diff.cols, mines: _diff.mines);
    setState(() {});
  }

  // 첫 입력 시 보드 생성 (첫칸 3×3 보호, 공정 퍼즐/시드/타임아웃 적용)
  Future<void> _placeMinesForFirstTap(int r, int c) async {
    if (_board.hasMines) return;
    setState(() {
      _generating = true;
      _status = GameStatus.generating;
    });
    try {
      final res = await generateBoardMap({
        'rows': _diff.rows,
        'cols': _diff.cols,
        'mines': _diff.mines,
        'sr': r,
        'sc': c,
        'fair': _fairPuzzle,
        'seed': _seed,
        'maxAttempts': 400,
        'timeoutMs': 800,
      });
      final mine = (res['mine'] as List).map((row) => List<bool>.from(row)).toList();
      final adj  = (res['adj']  as List).map((row) => List<int>.from(row)).toList();
      _board.inject(mine: mine, adj: adj);
    } catch (_) {
      _board.placeRandomMinesExcluding3x3(r, c, seed: _seed);
    } finally {
      setState(() {
        _generating = false;
        _status = GameStatus.playing;
      });
      _watch.start();
      _startTicker();

      _board.openCell(r, c);
      if (_assist) _board.runDeterministicAssistLoop();
      _checkEnd();
      setState(() {});
    }
  }

  void _onTap(int r, int c) {
    if (_generating || _status == GameStatus.won || _status == GameStatus.lost) return;
    if (!_board.hasMines) {
      _placeMinesForFirstTap(r, c);
      return;
    }
    if (_status == GameStatus.ready) {
      _status = GameStatus.playing;
      _watch.start();
      _startTicker();
    }
    if (_board.cell(r, c).flagged) return;

    _board.openCell(r, c);
    if (_assist) _board.runDeterministicAssistLoop();
    _checkEnd();
    setState(() {});
  }

  void _onLongPressOrRightClick(int r, int c) {
    if (_generating || _status == GameStatus.won || _status == GameStatus.lost) return;
    if (!_board.hasMines) {
      _placeMinesForFirstTap(r, c);
      return;
    }
    _board.toggleFlag(r, c);
    if (_assist) _board.runDeterministicAssistLoop();
    _checkEnd();
    setState(() {});
  }

  void _onChord(int r, int c) {
    if (_generating || !_board.hasMines) return;
    _board.chordOpen(r, c);
    if (_assist) _board.runDeterministicAssistLoop();
    _checkEnd();
    setState(() {});
  }

  void _checkEnd() async {
    if (_board.exploded) {
      _status = GameStatus.lost;
      _watch.stop();
      _stopTicker();
      await _saveBestIfNeeded();
    } else if (_board.allSafeOpened) {
      _status = GameStatus.won;
      _watch.stop();
      _stopTicker();
      await _saveBestIfNeeded();
    }
  }

  Future<void> _pickSeedDialog() async {
    final ctrl = TextEditingController(text: _seed?.toString() ?? '');
    final v = await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('시드(선택)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '예: 12345'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('취소')),
          TextButton(
            onPressed: () {
              final s = int.tryParse(ctrl.text.trim());
              Navigator.pop(context, s);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
    setState(() => _seed = v);
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _board.mines - _board.flagCount;

    return Scaffold(
      // AppBar는 슬림하게
      appBar: AppBar(
        title: const Text('지뢰찾기'),
        centerTitle: false,
      ),

      body: Stack(
        children: [
          Column(
            children: [
              // ── 게임기 콘솔 패널 (스크롤 없음, Wrap으로 줄바꿈)
              ConsolePanel(
                remainingMines: remaining,
                elapsedSeconds: _elapsed,
                bestTime: _bestTime,
                wins: _wins,
                loss: _loss,
                diff: _diff,
                onSelectDiff: (d) => _newGame(diff: d),
                fair: _fairPuzzle,
                onToggleFair: (v) => setState(() => _fairPuzzle = v),
                assist: _assist,
                onToggleAssist: (v) => setState(() => _assist = v),
                seed: _seed,
                onPickSeed: _pickSeedDialog,
                onClearSeed: () => setState(() => _seed = null),
                onNewGame: () => _newGame(),
              ),

              // ── 보드
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _diff.cols / _diff.rows,
                    child: MineBoardView(
                      board: _board,
                      onTap: _onTap,
                      onLongPressOrRightClick: _onLongPressOrRightClick,
                      onChord: _onChord,
                      revealMines: _status == GameStatus.lost || _status == GameStatus.won,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── 생성 오버레이
          if (_generating)
            Container(
              color: Colors.black.withOpacity(0.25),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('퍼즐 생성 중...', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 콘솔 패널: 모든 메뉴/상태가 한 화면에 항상 노출 (Wrap 사용)
// ──────────────────────────────────────────────────────────────
class ConsolePanel extends StatelessWidget {
  final int remainingMines;
  final int elapsedSeconds;
  final int? bestTime;
  final int wins;
  final int loss;

  final Difficulty diff;
  final ValueChanged<Difficulty> onSelectDiff;
  final bool fair;
  final ValueChanged<bool> onToggleFair;
  final bool assist;
  final ValueChanged<bool> onToggleAssist;
  final int? seed;
  final Future<void> Function() onPickSeed;
  final VoidCallback onClearSeed;
  final VoidCallback onNewGame;

  const ConsolePanel({
    super.key,
    required this.remainingMines,
    required this.elapsedSeconds,
    required this.bestTime,
    required this.wins,
    required this.loss,
    required this.diff,
    required this.onSelectDiff,
    required this.fair,
    required this.onToggleFair,
    required this.assist,
    required this.onToggleAssist,
    required this.seed,
    required this.onPickSeed,
    required this.onClearSeed,
    required this.onNewGame,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.surfaceVariant],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _ScrewPainter()))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 상태 뱃지 영역 (Wrap)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniBadge(icon: Icons.flag, label: '남은 지뢰: $remainingMines'),
                  _MiniBadge(icon: Icons.timer, label: '시간: ${_formatTime(elapsedSeconds)}'),
                  if (bestTime != null) _MiniBadge(icon: Icons.star, label: '베스트: ${_formatTime(bestTime!)}'),
                  _MiniBadge(icon: Icons.emoji_events, label: '승/패: $wins/$loss'),
                ],
              ),
              const SizedBox(height: 10),

              // ── 컨트롤 영역 (Wrap: 줄바꿈, 스크롤 없음)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // 난이도(세그먼트풍 ChoiceChip) - 짧은 라벨로 공간 절약
                  _ChoiceGroup(
                    current: diff,
                    onSelect: onSelectDiff,
                  ),

                  // 공정 / 자동
                  _SettingChip(
                    label: '공정',
                    value: fair,
                    onChanged: onToggleFair,
                    iconOn: Icons.check_circle,
                    iconOff: Icons.radio_button_unchecked,
                  ),
                  _SettingChip(
                    label: '오토',
                    value: assist,
                    onChanged: onToggleAssist,
                    iconOn: Icons.auto_fix_high,
                    iconOff: Icons.auto_fix_off,
                  ),

                  // 시드
                  _SeedChipButton(
                    seedText: seed?.toString(),
                    onPick: onPickSeed,
                    onClear: onClearSeed,
                  ),

                  // 새 게임
                  ElevatedButton.icon(
                    onPressed: onNewGame,
                    icon: const Icon(Icons.refresh),
                    label: const Text('새 게임'),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      foregroundColor: cs.onPrimaryContainer,
                      backgroundColor: cs.primaryContainer.withOpacity(0.9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatTime(int s) {
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }
}

// ── 난이도 선택(짧은 라벨 ChoiceChip 3개: B/I/E)
class _ChoiceGroup extends StatelessWidget {
  final Difficulty current;
  final ValueChanged<Difficulty> onSelect;
  const _ChoiceGroup({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final items = [
      Difficulties.beginner,
      Difficulties.intermediate,
      Difficulties.expert,
    ];
    String shortLabel(Difficulty d) {
      if (d == Difficulties.beginner) return 'B (9×9,10)';
      if (d == Difficulties.intermediate) return 'I (16×16,40)';
      return 'E (16×30,99)';
    }

    return Wrap(
      spacing: 6,
      children: [
        for (final d in items)
          ChoiceChip(
            label: Text(shortLabel(d)),
            selected: current.key == d.key,
            onSelected: (v) { if (v) onSelect(d); },
          ),
      ],
    );
  }
}

// ── 장식: 나사
class _ScrewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.10);
    final screws = [
      const Offset(14, 12),
      Offset(size.width - 14, 12),
      Offset(14, size.height - 14),
      Offset(size.width - 14, size.height - 14),
    ];
    for (final o in screws) {
      canvas.drawCircle(o, 4, paint);
      final p2 = Paint()
        ..color = Colors.black.withOpacity(0.20)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(o.dx - 3, o.dy), Offset(o.dx + 3, o.dy), p2);
      canvas.drawLine(Offset(o.dx, o.dy - 3), Offset(o.dx, o.dy + 3), p2);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── 상태/설정 UI 부품들
class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MiniBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SettingChip extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData iconOn;
  final IconData iconOff;

  const _SettingChip({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.iconOn,
    required this.iconOff,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value;
    return FilterChip(
      selected: selected,
      label: Text(label),
      avatar: Icon(selected ? iconOn : iconOff, size: 18),
      onSelected: onChanged,
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      showCheckmark: false,
    );
  }
}

class _SeedChipButton extends StatelessWidget {
  final String? seedText;
  final Future<void> Function() onPick;
  final VoidCallback onClear;
  const _SeedChipButton({required this.seedText, required this.onPick, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final hasSeed = seedText != null && seedText!.isNotEmpty;
    return InputChip(
      label: Text(hasSeed ? '시드: $seedText' : '시드 설정'),
      avatar: const Icon(Icons.numbers, size: 18),
      onPressed: onPick,
      onDeleted: hasSeed ? onClear : null,
    );
  }
}
