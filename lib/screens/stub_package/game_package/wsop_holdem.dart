// lib/screens/stub_package/game_package/wsop_holdem.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'wsop_rules.dart';

class WsopHoldemPage extends StatefulWidget {
  const WsopHoldemPage({super.key});

  @override
  State<WsopHoldemPage> createState() => _WsopHoldemPageState();
}

/* ─────────────────────────────────────────────────────────────────────────────
   모델/유틸
   - 카드는 2..14(A), 슈트 4종
   - 플롭/턴/리버 7카드 중 베스트5 핸드 평가
   - TDA/WSOP 준수 흐름(딜러버튼, SB/BB, BB Ante, 최소레이지, 올인/사이드팟)
   - 커스터마이즈: 플레이어 수/시작 스택/레벨표/리엔트리/AI 샘플
   ───────────────────────────────────────────────────────────────────────────── */

enum Suit { spade, heart, diamond, club }

class CardX {
  final Suit suit;
  final int rank; // 2..14 (A=14)
  const CardX(this.suit, this.rank);

  @override
  bool operator ==(Object o) => o is CardX && o.suit == suit && o.rank == rank;

  @override
  int get hashCode => Object.hash(suit, rank);

  String get rankStr {
    if (rank <= 10) return '$rank';
    switch (rank) {
      case 11:
        return 'J';
      case 12:
        return 'Q';
      case 13:
        return 'K';
      default:
        return 'A';
    }
  }

  Color get suitColor => (suit == Suit.heart || suit == Suit.diamond) ? const Color(0xFFE53935) : Colors.black;

  String get suitIcon {
    switch (suit) {
      case Suit.heart:
        return '♥';
      case Suit.diamond:
        return '♦';
      case Suit.spade:
        return '♠';
      case Suit.club:
        return '♣';
    }
  }
}

class Deck {
  final _rng = Random();
  final List<CardX> _cards = [];

  Deck() {
    for (final s in Suit.values) {
      for (int r = 2; r <= 14; r++) {
        _cards.add(CardX(s, r));
      }
    }
    _cards.shuffle(_rng);
  }

  CardX draw() => _cards.removeLast();

  void burn() {
    if (_cards.isNotEmpty) _cards.removeLast();
  }

  List<CardX> remaining() => List<CardX>.from(_cards);

  void remove(CardX c) {
    final i = _cards.indexWhere((x) => x == c);
    if (i >= 0) _cards.removeAt(i);
  }

  void removeMany(Iterable<CardX> cs) {
    for (final c in cs) {
      remove(c);
    }
  }
}

enum Street { preflop, flop, turn, river, showdown }

class Player {
  final String name;
  final bool isHero;
  int stack;
  bool seated = true;

  // 핸드 내 상태
  bool inHand = true;
  bool folded = false;
  bool allIn = false;
  List<CardX> hole = [];
  int betThisStreet = 0; // 현재 스트리트에 앞에 둔 금액
  int committed = 0; // 핸드 전체 기여(사이드팟 계산용)

  Player({required this.name, required this.stack, required this.isHero});
}

/* ─ 토너먼트 설정 ─ */
class TournamentConfig {
  int playerCount;
  int startingStack;
  List<_Level> levels;
  bool reentryEnabled;
  int reentryCutoffLevel; // 이 레벨 인덱스(포함)까지 리엔트리 허용
  int aiSamples; // EHS 추정용 몬테카를로 샘플 수
  int buyIn; // 프라이즈풀 계산용 (가상 화폐)
  List<double> payoutPercents; // ITM 분배(합 1.0 권장)

  TournamentConfig({
    this.playerCount = 6,
    this.startingStack = 10000,
    List<_Level>? levels,
    this.reentryEnabled = true,
    this.reentryCutoffLevel = 2,
    this.aiSamples = 40,
    this.buyIn = 100,
    List<double>? payoutPercents,
  })  : levels = levels ??
      const [
        _Level(sb: 100, bb: 200, bbAnte: true, secs: 180),
        _Level(sb: 200, bb: 400, bbAnte: true, secs: 180),
        _Level(sb: 300, bb: 600, bbAnte: true, secs: 180),
        _Level(sb: 500, bb: 1000, bbAnte: true, secs: 180),
        _Level(sb: 1000, bb: 2000, bbAnte: true, secs: 180),
      ],
        payoutPercents = payoutPercents ?? [0.5, 0.3, 0.2];

  TournamentConfig copyWith({
    int? playerCount,
    int? startingStack,
    List<_Level>? levels,
    bool? reentryEnabled,
    int? reentryCutoffLevel,
    int? aiSamples,
    int? buyIn,
    List<double>? payoutPercents,
  }) {
    return TournamentConfig(
      playerCount: playerCount ?? this.playerCount,
      startingStack: startingStack ?? this.startingStack,
      levels: levels ?? this.levels,
      reentryEnabled: reentryEnabled ?? this.reentryEnabled,
      reentryCutoffLevel: reentryCutoffLevel ?? this.reentryCutoffLevel,
      aiSamples: aiSamples ?? this.aiSamples,
      buyIn: buyIn ?? this.buyIn,
      payoutPercents: payoutPercents ?? this.payoutPercents,
    );
  }
}

class HandRank {
  // 카테고리 높을수록 강함 (StraightFlush=8 ... HighCard=0)
  final int cat;

  // 타이브레이커: 내림차순
  final List<int> tiebreak;

  HandRank(this.cat, this.tiebreak);

  int compareTo(HandRank other) {
    if (cat != other.cat) return cat.compareTo(other.cat);
    for (int i = 0; i < min(tiebreak.length, other.tiebreak.length); i++) {
      if (tiebreak[i] != other.tiebreak[i]) return tiebreak[i].compareTo(other.tiebreak[i]);
    }
    return 0;
  }

  @override
  String toString() {
    const names = [
      'High',
      'Pair',
      'TwoPair',
      'Trips',
      'Straight',
      'Flush',
      'FullHouse',
      'Quads',
      'StraightFlush',
    ];
    return names[cat];
  }
}

class PotSlice {
  int amount = 0;

  // 이 팟에 대한 자격(해당 팟에서 경쟁하는 플레이어 인덱스)
  final Set<int> eligible = {};
}

/* ─────────────────────────────────────────────────────────────────────────────
   핸드 평가(7장 중 베스트 5)
   카테고리: 8 SF, 7 Quads, 6 Full, 5 Flush, 4 Straight, 3 Trips, 2 TwoPair, 1 Pair, 0 High
   ───────────────────────────────────────────────────────────────────────────── */
HandRank evaluateBest7(List<CardX> seven) {
  assert(seven.length == 7);
  HandRank? best;
  // 7C5 = 21개 조합
  final idx = [0, 1, 2, 3, 4];
  bool next() {
    for (int i = 4; i >= 0; i--) {
      if (idx[i] != i + (7 - 5)) {
        idx[i]++;
        for (int j = i + 1; j < 5; j++) {
          idx[j] = idx[j - 1] + 1;
        }
        return true;
      }
    }
    return false;
  }

  HandRank eval5(List<CardX> five) {
    final ranks = five.map((c) => c.rank).toList()..sort((a, b) => b.compareTo(a));
    final suits = five.map((c) => c.suit).toList();
    final isFlush = suits.toSet().length == 1;

    bool isStraight(List<int> r) {
      final u = r.toSet().toList()..sort();
      if (u.length != 5) return false;
      // A-2-3-4-5
      if (u[0] == 2 && u[1] == 3 && u[2] == 4 && u[3] == 5 && u[4] == 14) return true;
      return u.last - u.first == 4;
    }

    // 스트레이트의 최고랭크 계산(휠 스트레이트는 5로 처리)
    int straightHigh(List<int> r) {
      final u = r.toSet().toList()..sort();
      if (u[0] == 2 && u[1] == 3 && u[2] == 4 && u[3] == 5 && u[4] == 14) return 5;
      return u.last;
    }

    final st = isStraight(ranks);
    // 카운트
    final Map<int, int> cnt = {};
    for (final r in ranks) cnt[r] = (cnt[r] ?? 0) + 1;
    final byCountThenRankDesc = cnt.entries.toList()
      ..sort((a, b) {
        if (a.value != b.value) return b.value.compareTo(a.value);
        return b.key.compareTo(a.key);
      });

    if (isFlush && st) {
      final hi = straightHigh(ranks);
      return HandRank(8, [hi]); // Straight Flush
    }
    if (byCountThenRankDesc.first.value == 4) {
      final quad = byCountThenRankDesc.first.key;
      final kicker = (ranks..removeWhere((e) => e == quad)).first;
      return HandRank(7, [quad, kicker]);
    }
    if (byCountThenRankDesc[0].value == 3 && byCountThenRankDesc[1].value == 2) {
      return HandRank(6, [byCountThenRankDesc[0].key, byCountThenRankDesc[1].key]); // Full House
    }
    if (isFlush) {
      return HandRank(5, List<int>.from(ranks));
    }
    if (st) {
      return HandRank(4, [straightHigh(ranks)]);
    }
    if (byCountThenRankDesc[0].value == 3) {
      final trips = byCountThenRankDesc[0].key;
      final kickers = (ranks..removeWhere((e) => e == trips)).take(2).toList();
      return HandRank(3, [trips, ...kickers]);
    }
    if (byCountThenRankDesc[0].value == 2 && byCountThenRankDesc[1].value == 2) {
      final hiPair = max(byCountThenRankDesc[0].key, byCountThenRankDesc[1].key);
      final loPair = min(byCountThenRankDesc[0].key, byCountThenRankDesc[1].key);
      final kicker = (ranks..removeWhere((e) => e == hiPair || e == loPair)).first;
      return HandRank(2, [hiPair, loPair, kicker]);
    }
    if (byCountThenRankDesc[0].value == 2) {
      final pair = byCountThenRankDesc[0].key;
      final kickers = (ranks..removeWhere((e) => e == pair)).take(3).toList();
      return HandRank(1, [pair, ...kickers]);
    }
    return HandRank(0, List<int>.from(ranks)); // High card
  }

  List<CardX> pick() => [for (final i in idx) seven[i]];

  best = eval5(pick());
  while (next()) {
    final r = eval5(pick());
    if (r.compareTo(best!) > 0) best = r;
  }
  return best!;
}

/* ─────────────────────────────────────────────────────────────────────────────
   히스토리 & 리플레이
   ───────────────────────────────────────────────────────────────────────────── */

class HandHistory {
  final int handNo;
  final int dealerSeat;
  final _Level level;
  final List<String> log = [];
  final List<CardX> boardAtEnd = [];
  final Map<int, List<CardX>> holeShownAtSD = {};
  final List<_ReplayStep> replay = [];

  HandHistory(this.handNo, this.dealerSeat, this.level);

  void add(String s) => log.add(s);
}

enum _ReplayType { info, deal, flop, turn, river, action, showdown, award }

class _ReplayStep {
  final _ReplayType type;
  final String text;
  final List<CardX> board;
  final Map<int, List<CardX>> showHoles; // 공개용
  _ReplayStep(this.type, this.text, {this.board = const [], this.showHoles = const {}});
}

/* ─────────────────────────────────────────────────────────────────────────────
   테이블 상태 & 라운드 엔진
   - N-Max (Hero + 봇들)
   - 블라인드 레벨 & 타이머, BB Ante(일반 WSOP 방식)
   - 봇 의사결정(프리플랍 차트 + 플롭/턴 EHS)
   - 리엔트리/ITM 분배
   - 히스토리/리플레이
   ───────────────────────────────────────────────────────────────────────────── */

class _WsopHoldemPageState extends State<WsopHoldemPage> {
  // 설정(커스터마이즈 가능)
  TournamentConfig cfg = TournamentConfig();

  // 구조/레벨
  int levelIndex = 0;
  Timer? _levelTimer;
  int levelRemain = 0;

  // 플레이어
  final List<Player> players = [];
  int dealer = 0; // 버튼 위치
  int heroSeat = 0;

  // 딜/베팅 상태
  Deck? deck;
  Street street = Street.preflop;
  List<CardX> board = [];
  int toAct = 0; // 액션 차례 인덱스
  int currentBet = 0; // 이 스트리트에서 콜해야 하는 금액
  int minRaise = 0; // 최소 레이즈 갭
  int lastAggressor = -1; // 마지막 레이즈한 사람 (라운드 종료 판정)
  bool handRunning = false;
  bool tourRunning = false;

  // 사이드팟
  List<PotSlice> pots = [];

  // 메시지/HUD
  String msg = 'Tap START to run WSOP demo';
  bool autoAdvance = true;

  // 엔트리/프라이즈
  int entries = 0; // 엔트리(리엔트리 포함)
  List<HandHistory> history = [];
  int handCounter = 0;

  @override
  void initState() {
    super.initState();
    _newTable();
  }

  @override
  void dispose() {
    _levelTimer?.cancel();
    super.dispose();
  }

  _Level get _lv => cfg.levels[levelIndex];

  void _newTable() {
    players.clear();
    // N-Max: Hero + (N-1) bots
    cfg.playerCount = cfg.playerCount.clamp(2, 9);
    players.add(Player(name: 'YOU', stack: cfg.startingStack, isHero: true));
    for (int i = 1; i < cfg.playerCount; i++) {
      players.add(Player(name: 'BOT $i', stack: cfg.startingStack, isHero: false));
    }
    heroSeat = 0;
    dealer = Random().nextInt(players.length); // 임의 버튼
    entries = players.length; // 초기 엔트리
    _gotoLevel(0, startTimer: false);
    msg = 'Ready. Level ${levelIndex + 1} • ${_lv.desc}';
    setState(() {});
  }

  void _gotoLevel(int idx, {required bool startTimer}) {
    _levelTimer?.cancel();
    levelIndex = idx.clamp(0, cfg.levels.length - 1);
    levelRemain = _lv.secs;
    if (tourRunning && startTimer) {
      _levelTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (levelRemain <= 0) {
          if (levelIndex < cfg.levels.length - 1) {
            _gotoLevel(levelIndex + 1, startTimer: true);
            setState(() {});
          } else {
            // 레벨 종료 = 토너먼트 종료(데모)
            _endTournament();
          }
        } else {
          setState(() => levelRemain--);
        }
      });
    }
  }

  void _startTournament() {
    if (tourRunning) return;
    tourRunning = true;
    _gotoLevel(levelIndex, startTimer: true); // 타이머 스타트
    msg = 'Tournament running. Good luck!';
    setState(() {});
  }

  void _endTournament() {
    _levelTimer?.cancel();
    tourRunning = false;
    // 순위: 스택 정렬
    final finalOrder = (List<Player>.from(players)..sort((a, b) => b.stack.compareTo(a.stack)));
    // ITM 분배
    final prizePool = entries * cfg.buyIn;
    final winners = min(cfg.payoutPercents.length, finalOrder.length);
    final payouts = <String>[];
    int paid = 0;
    for (int i = 0; i < winners; i++) {
      final amt = (prizePool * cfg.payoutPercents[i]).round();
      paid += amt;
      payouts.add('${i + 1}. ${finalOrder[i].name}  +$amt');
    }
    if (paid < prizePool && winners > 0) {
      // 남는 잔돈은 1위 보정
      final diff = prizePool - paid;
      payouts[0] = payouts[0].replaceFirst('+', '+${(prizePool * cfg.payoutPercents[0]).round() + diff}');
    }

    final rank = finalOrder.asMap().entries.map((e) => '${e.key + 1}. ${e.value.name} – ₵ ${e.value.stack}').join('\n');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tournament Over'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Final stacks:\n$rank'),
              const SizedBox(height: 12),
              Text('Entries: $entries   Prize Pool: ${prizePool}'),
              const SizedBox(height: 6),
              const Text('Payouts (ITM)'),
              Text(payouts.join('\n')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
    msg = 'Tournament paused.';
    setState(() {});
  }

  /* ───────────────────────────────────────────────────────────────────────────
     핸드 진행
     ─────────────────────────────────────────────────────────────────────────── */

  void _newHand() {
    // 빈사/탈락 정리(리엔트리)
    for (final p in players) {
      if (p.stack <= 0) {
        if (cfg.reentryEnabled && levelIndex <= cfg.reentryCutoffLevel) {
          // 리엔트리 즉시 발동(데모): 스택 재충전 & 엔트리 증가
          p.stack = cfg.startingStack;
          entries += 1;
          _toast('${p.name} re-entered.');
        } else {
          p.seated = false;
        }
      } else {
        p.seated = true;
      }
      p.inHand = p.seated;
      p.folded = false;
      p.allIn = false;
      p.hole = [];
      p.betThisStreet = 0;
      p.committed = 0;
    }

    // 모두 탈락했으면 테이블 리셋
    if (!players.any((p) => p.seated)) {
      _endTournament();
      return;
    }

    board = [];
    pots = [];
    street = Street.preflop;
    deck = Deck();
    currentBet = 0;
    minRaise = _lv.bb; // 프리플랍 최소레이즈 보통 BB 기준
    lastAggressor = -1;
    handRunning = true;

    // 버튼 이동(WSOP 규정: 버튼은 항상 시계방향으로 다음 자리)
    do {
      dealer = (dealer + 1) % players.length;
    } while (!players[dealer].seated);

    // 히스토리 생성
    final hh = HandHistory(++handCounter, dealer, _lv);
    history.add(hh);
    hh.add('=== Hand #${hh.handNo}  Level ${levelIndex + 1} ${_lv.desc} ===');
    hh.replay.add(_ReplayStep(_ReplayType.info, 'New hand • ${_lv.desc}'));

    // 앤티: WSOP 메인/많은 이벤트에서 BB Ante
    if (_lv.bbAnte) {
      final bbSeat0 = _nextSeated(dealer, 2); // 버튼 다음 SB, 그다음 BB
      _post(bbSeat0, min(players[bbSeat0].stack, _lv.bb), log: hh, label: 'posts BB Ante');
    }

    // 스몰/빅블라인드
    final sbSeat = _nextSeated(dealer, 1);
    final bbSeat = _nextSeated(dealer, 2);
    _post(sbSeat, min(players[sbSeat].stack, _lv.sb), log: hh, label: 'posts SB');
    _post(bbSeat, min(players[bbSeat].stack, _lv.bb), log: hh, label: 'posts BB');

    // 딜: 2장씩
    for (int r = 0; r < 2; r++) {
      int s = _nextSeated(dealer, 1); // SB부터
      for (int i = 0; i < players.length; i++) {
        if (!players[s].seated) {
          s = _nextSeated(s, 1);
          continue;
        }
        if (players[s].inHand) {
          final c = deck!.draw();
          players[s].hole.add(c);
        }
        s = _nextSeated(s, 1);
      }
    }
    hh.add('Dealt hole cards (hero shown below).');
    hh.replay.add(_ReplayStep(_ReplayType.deal, 'Hole cards dealt'));

    // 프리플랍 액션: BB 다음(UTG)부터
    toAct = _nextToAct(bbSeat);
    currentBet = players[bbSeat].betThisStreet;
    minRaise = _lv.bb;
    lastAggressor = bbSeat;

    msg = 'New hand. Blinds ${_lv.sb}/${_lv.bb}${_lv.bbAnte ? " (BB Ante)" : ""}';
    setState(() {});
    _maybeBotAct();
  }

  int _nextSeated(int from, int step) {
    int s = from;
    for (int i = 0; i < step; i++) {
      do {
        s = (s + 1) % players.length;
      } while (!players[s].seated);
    }
    return s;
  }

  int _nextToAct(int from) {
    int s = from;
    while (true) {
      s = _nextSeated(s, 1);
      if (players[s].inHand && !players[s].folded && !players[s].allIn) return s;
    }
  }

  void _post(int seat, int amt, {HandHistory? log, String label = 'posts'}) {
    final p = players[seat];
    final pay = min(p.stack, amt);
    p.stack -= pay;
    p.betThisStreet += pay;
    p.committed += pay;
    log?.add('${p.name} $label $pay');
  }

  // 라운드 종료 체크: “모든 활성 플레이어가 콜(=최고치와 같음)했거나 올인했고
  // everyone matched → 종료(단순화)
  bool _roundShouldEnd() {
    for (int i = 0; i < players.length; i++) {
      final p = players[i];
      if (!p.inHand || p.folded || p.allIn) continue;
      if (p.betThisStreet != currentBet) return false;
    }
    return true;
  }

  void _endStreet() {
    final hh = history.last;
    // 스트리트 칩을 메인 풀로 이동(사이드팟 계산용: committed는 누적이므로 유지)
    for (final p in players) {
      p.betThisStreet = 0;
    }
    currentBet = 0;
    minRaise = _lv.bb;
    lastAggressor = -1;

    // 다음 스트리트
    if (street == Street.preflop) {
      deck!.burn();
      board.add(deck!.draw());
      board.add(deck!.draw());
      board.add(deck!.draw());
      street = Street.flop;
      toAct = _nextToAct(dealer);
      msg = 'Flop';
      hh.add('Flop: ${_cardsStr(board)}');
      hh.replay.add(_ReplayStep(_ReplayType.flop, 'Flop', board: List<CardX>.from(board)));
    } else if (street == Street.flop) {
      deck!.burn();
      board.add(deck!.draw());
      street = Street.turn;
      toAct = _nextToAct(dealer);
      msg = 'Turn';
      hh.add('Turn: ${_cardsStr(board)}');
      hh.replay.add(_ReplayStep(_ReplayType.turn, 'Turn', board: List<CardX>.from(board)));
    } else if (street == Street.turn) {
      deck!.burn();
      board.add(deck!.draw());
      street = Street.river;
      toAct = _nextToAct(dealer);
      msg = 'River';
      hh.add('River: ${_cardsStr(board)}');
      hh.replay.add(_ReplayStep(_ReplayType.river, 'River', board: List<CardX>.from(board)));
    } else {
      // 쇼다운
      street = Street.showdown;
      _showdownAndPayout();
      return;
    }
    setState(() {});
    _maybeBotAct();
  }

  void _collectSidePots() {
    final contribs = <int>[];
    for (int i = 0; i < players.length; i++) {
      final p = players[i];
      if (p.committed > 0 && p.inHand) contribs.add(p.committed);
    }
    if (contribs.isEmpty) return;

    final lvls = (contribs.toSet().toList()..sort());
    int prev = 0;
    pots.clear();
    for (final lv in lvls) {
      final slice = PotSlice();
      // 이 레벨 이상 커밋한 사람 수
      int eligibleCount = 0;
      for (int i = 0; i < players.length; i++) {
        if (players[i].committed >= lv && players[i].inHand) {
          eligibleCount++;
          slice.eligible.add(i);
        }
      }
      final chunk = (lv - prev) * eligibleCount;
      if (chunk > 0) {
        slice.amount = chunk;
        pots.add(slice);
      }
      prev = lv;
    }
  }

  void _showdownAndPayout() {
    final hh = history.last;
    // 남은 사람 없으면(모두 폴드) 마지막 남은 사람에게 모든 칩
    final alive = <int>[];
    for (int i = 0; i < players.length; i++) {
      final p = players[i];
      if (p.inHand && !p.folded) alive.add(i);
    }
    final totalPot = players.fold<int>(0, (s, p) => s + p.committed);

    if (alive.length == 1) {
      final winner = alive.first;
      players[winner].stack += totalPot;
      msg = '${players[winner].name} wins $totalPot (no showdown)';
      hh.add('No showdown. ${players[winner].name} wins $totalPot');
      hh.replay.add(_ReplayStep(_ReplayType.award, '${players[winner].name} wins $totalPot'));
      _finishHand();
      return;
    }

    // 쇼다운: committed로 팟 분리
    _collectSidePots();

    // 보드/핸드 평가
    final ranks = <int, HandRank>{};
    for (final i in alive) {
      ranks[i] = evaluateBest7([...board, ...players[i].hole]);
    }

    // 각 사이드팟마다 우승자 결정(동률 분할)
    int totalAward = 0;
    for (final pot in pots) {
      final contenders = pot.eligible.where((i) => players[i].inHand && !players[i].folded).toList();
      if (contenders.isEmpty || pot.amount == 0) continue;
      contenders.sort((a, b) => ranks[b]!.compareTo(ranks[a]!));
      final bestRank = ranks[contenders.first]!;
      final winners = contenders.where((i) => ranks[i]!.compareTo(bestRank) == 0).toList();
      final share = pot.amount ~/ max(1, winners.length);
      for (final w in winners) {
        players[w].stack += share;
        totalAward += share;
      }
    }

    // 쇼우 카드 로깅
    for (final i in alive) {
      hh.add('${players[i].name} shows ${_cardsStr(players[i].hole)}  (${ranks[i]})');
      hh.holeShownAtSD[i] = List<CardX>.from(players[i].hole);
    }
    hh.add('Board: ${_cardsStr(board)}');
    hh.replay.add(_ReplayStep(_ReplayType.showdown, 'Showdown',
        board: List<CardX>.from(board), showHoles: Map<int, List<CardX>>.from(hh.holeShownAtSD)));

    msg = 'Showdown. Pot $totalAward awarded.';
    hh.add('Pot $totalAward awarded.');
    _finishHand();
  }

  void _finishHand() {
    final hh = history.last;
    hh.boardAtEnd.addAll(board);

    handRunning = false;
    // 핸드 정리: 커밋 초기화
    for (final p in players) {
      p.betThisStreet = 0;
      p.committed = 0;
      // 파산 표시
      if (p.stack == 0) {
        hh.add('${p.name} is out of chips.');
      }
    }
    setState(() {});
    // 자동 다음 핸드
    if (autoAdvance && tourRunning) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && tourRunning) _newHand();
      });
    }
  }

  /* ───────────────────────────────────────────────────────────────────────────
     액션 처리 (Fold/Check-Call/Raise-AllIn)
     ─────────────────────────────────────────────────────────────────────────── */

  void _fold(int seat) {
    final p = players[seat];
    if (!p.inHand || p.folded) return;
    p.folded = true;
    history.last.add('${p.name} folds');
    history.last.replay.add(_ReplayStep(_ReplayType.action, '${p.name} folds'));
    _advanceAfterAction();
  }

  void _checkOrCall(int seat) {
    final p = players[seat];
    final int toCall = max(0, currentBet - p.betThisStreet).toInt();
    final int pay = min(p.stack, toCall).toInt();
    p.stack -= pay;
    p.betThisStreet += pay;
    p.committed += pay;
    if (p.stack == 0) p.allIn = true;
    history.last.add('${p.name} ${toCall == 0 ? "checks" : "calls $pay"}');
    history.last.replay.add(_ReplayStep(_ReplayType.action, '${p.name} ${toCall == 0 ? "checks" : "calls $pay"}'));
    _advanceAfterAction();
  }

  void _raiseTo(int seat, int raiseTo) {
    final p = players[seat];

    // 증액 계산
    var add = raiseTo - p.betThisStreet; // int
    add = min(add, p.stack).toInt(); // ensure int
    var newBet = p.betThisStreet + add; // int

    // TDA: 최소 레이즈(갭) 규칙. 올인이 아닌 경우 갭을 충족해야 함.
    final int gapNeeded = max(minRaise, _lv.bb).toInt();
    final int gap = newBet - currentBet;
    final bool isAllIn = add == p.stack;
    if (!isAllIn && gap < gapNeeded) {
      final int needTo = currentBet + gapNeeded;
      add = min(p.stack, needTo - p.betThisStreet).toInt();
      newBet = p.betThisStreet + add;
    }

    p.stack -= add;
    p.betThisStreet += add;
    p.committed += add;

    final prevBet = currentBet;
    currentBet = max(currentBet, p.betThisStreet).toInt();
    final gap2 = currentBet - prevBet;
    if (gap2 > 0) {
      minRaise = gap2; // 마지막 레이즈 갭을 다음 최소레이즈로
      lastAggressor = seat;
    }
    if (p.stack == 0) p.allIn = true;

    final kind = isAllIn ? 'raises all-in to' : 'raises to';
    history.last.add('${p.name} $kind $newBet');
    history.last.replay.add(_ReplayStep(_ReplayType.action, '${p.name} $kind $newBet'));

    _advanceAfterAction();
  }

  void _advanceAfterAction() {
    // 라운드 종료?
    if (_roundShouldEnd()) {
      _endStreet();
      return;
    }
    // 다음 액터
    toAct = _nextToAct(toAct);
    setState(() {});
    _maybeBotAct();
  }

  /* ───────────────────────────────────────────────────────────────────────────
     봇(프리플랍 차트 + 플롭/턴 EHS)
     ─────────────────────────────────────────────────────────────────────────── */

  void _maybeBotAct() {
    if (!mounted) return;
    if (!handRunning) return;
    if (players[toAct].isHero) return;

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted || !handRunning) return;
      _botAct(toAct);
    });
  }

  // 프리플랍 간이 점수 (상대적 등급 0..100)
  int _preflopScore(List<CardX> hole) {
    final a = hole[0], b = hole[1];
    final high = max(a.rank, b.rank);
    final low = min(a.rank, b.rank);
    final pair = a.rank == b.rank;
    final suited = a.suit == b.suit;
    final connected = (high - low == 1);
    int score = 0;

    if (pair) {
      if (high >= 13)
        score = 95; // AA/KK
      else if (high == 12)
        score = 88; // QQ
      else if (high == 11)
        score = 80; // JJ
      else if (high == 10)
        score = 72; // TT
      else
        score = 55 + (high - 2) * 2; // 22..99
    } else {
      if ((high == 14 && low >= 10))
        score = suited ? 85 : 78; // AK, AQ, AJ
      else if (high >= 13 && low >= 10)
        score = suited ? 76 : 68; // KQ, KJ, QJ
      else if (connected && high >= 10)
        score = suited ? 70 : 62;
      else if (suited && connected && high >= 7)
        score = 58;
      else if (high >= 12)
        score = suited ? 60 : 52;
      else
        score = suited ? 48 : 42;
    }
    // 버튼/포지션 보정은 생략(간단)
    return score.clamp(0, 100);
  }

  // 남은 덱에서 EHS 추정(플롭/턴): 샘플 수 cfg.aiSamples
  double _estimateWinProb(int seat) {
    final me = players[seat];
    final activeSeats = <int>[];
    for (int i = 0; i < players.length; i++) {
      if (i == seat) continue;
      final p = players[i];
      if (p.inHand && !p.folded && !p.allIn) activeSeats.add(i);
    }
    if (activeSeats.isEmpty) return 1.0;

    final int samples = max(10, cfg.aiSamples).toInt();
    int wins = 0, ties = 0;

    for (int s = 0; s < samples; s++) {
      // 새 덱 구성
      final d = Deck();
      d.removeMany(me.hole);
      d.removeMany(board);

      // 상대 홀
      final oppHoles = <List<CardX>>[];
      for (final _ in activeSeats) {
        final c1 = d.draw();
        final c2 = d.draw();
        oppHoles.add([c1, c2]);
      }

      // 남은 보드
      final addBoard = <CardX>[];
      for (int i = 0; i < 5 - board.length; i++) {
        addBoard.add(d.draw());
      }

      final myRank = evaluateBest7([...me.hole, ...board, ...addBoard]);
      HandRank? bestOpp;
      for (final cards in oppHoles) {
        final r = evaluateBest7([...cards, ...board, ...addBoard]);
        if (bestOpp == null || r.compareTo(bestOpp) > 0) bestOpp = r;
      }

      if (bestOpp == null) {
        wins++;
      } else {
        final cmp = myRank.compareTo(bestOpp);
        if (cmp > 0)
          wins++;
        else if (cmp == 0) ties++;
      }
    }

    final total = samples;
    final wp = (wins + ties * 0.5) / max(1, total);
    return wp;
  }

  void _botAct(int seat) {
    final p = players[seat];
    if (!p.inHand || p.folded || p.allIn) {
      _advanceAfterAction();
      return;
    }

    // 현재 콜액/팟오즈
    final int need = max(0, currentBet - p.betThisStreet).toInt();
    final pot = players.fold<int>(0, (s, q) => s + q.committed);
    final stackBehind = p.stack;
    final potOdds = need == 0 ? 0.0 : need / max(1, pot + need);

    if (street == Street.preflop) {
      final score = _preflopScore(p.hole);
      if (need == 0) {
        if (score >= 75 && stackBehind > _lv.bb * 3) {
          // 오픈레이즈 2.5~3bb
          final int to = max(currentBet + max(minRaise, (_lv.bb * 3)).toInt(), p.betThisStreet + _lv.bb * 3).toInt();
          _raiseTo(seat, to);
        } else {
          _checkOrCall(seat);
        }
      } else {
        // 콜 기준: 프리플랍 점수 & 팟오즈
        final wantCall = score >= 55 || potOdds < 0.2;
        if (wantCall && stackBehind >= need) {
          // 3bet 조건
          if (score >= 80 && stackBehind > need + _lv.bb * 5) {
            final int to = currentBet + max(minRaise, _lv.bb * 3).toInt();
            _raiseTo(seat, to);
          } else {
            _checkOrCall(seat);
          }
        } else {
          _fold(seat);
        }
      }
    } else {
      // 플롭/턴: EHS 추정
      final ehs = _estimateWinProb(seat); // 0..1
      final strong = ehs >= 0.65;
      final marginal = ehs >= 0.45;
      if (need == 0) {
        if (strong && stackBehind > _lv.bb * 2) {
          _raiseTo(seat, currentBet + max(minRaise, _lv.bb * 2).toInt());
        } else {
          _checkOrCall(seat);
        }
      } else {
        // 콜 임계: EHS vs pot odds
        final breakeven = potOdds; // 간이 판단
        if (ehs >= breakeven || marginal) {
          _checkOrCall(seat);
        } else {
          _fold(seat);
        }
      }
    }
  }

  /* ───────────────────────────────────────────────────────────────────────────
     UI
     ─────────────────────────────────────────────────────────────────────────── */

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final levelStr = 'Level ${levelIndex + 1}: ${_lv.sb}/${_lv.bb}${_lv.bbAnte ? " (BB Ante)" : ""}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('WSOP Hold’em (Demo)'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Rulebook',
            icon: const Icon(Icons.menu_book_rounded),
            onPressed: _openRulebook,
          ),
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history_rounded),
            onPressed: _openHistory,
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openSettings,
          ),
          if (tourRunning)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  '$levelStr  •  ${_formatMMSS(levelRemain)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
      backgroundColor: Colors.green[700],
      body: Column(
        children: [
          // 상단 메시지/HUD
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(color: Colors.white),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 6,
              children: [
                Text(levelStr, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
                Wrap(
                  spacing: 8,
                  children: [
                    _hudPill(Icons.emoji_events, tourRunning ? 'Running' : 'Paused'),
                    _hudPill(Icons.people_alt_rounded,
                        'Players: ${players.where((p) => p.seated).length}/${players.length}'),
                    _hudPill(Icons.account_circle, 'Hero: ${players[heroSeat].stack}'),
                    _hudPill(Icons.confirmation_num_outlined, 'Entries: $entries'),
                  ],
                ),
              ],
            ),
          ),

          // 테이블 뷰
          Expanded(
            child: LayoutBuilder(
              builder: (context, cons) {
                final w = cons.maxWidth;
                final h = cons.maxHeight;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 좌석(원형 배치) 먼저: 아래 층
                    ..._seatWidgets(w, h),

                    // 보드(커뮤니티 카드) 나중에: 위 층
                    Positioned(
                      top: h * .22,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Center(child: _boardView()),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // 액션 패널
          _actionPanel(cs),
        ],
      ),
      floatingActionButton: _fab(),
    );
  }

  Widget _fab() {
    if (!tourRunning) {
      return FloatingActionButton.extended(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        onPressed: _startTournament,
        label: const Text('START'),
        icon: const Icon(Icons.play_arrow),
      );
    }
    if (!handRunning) {
      return FloatingActionButton.extended(
        onPressed: _newHand,
        label: const Text('DEAL'),
        icon: const Icon(Icons.casino),
      );
    }
    return const SizedBox.shrink();
  }

  List<Widget> _seatWidgets(double w, double h) {
    // 좌석 카드 가로/세로 (이 파일에서 사용 중인 값)
    const seatW = 180.0;
    const seatH = 84.0;

    // 화면 여백
    const topPad = 8.0;
    const bottomPad = 8.0;

    // 원 중심을 더 아래로 (기존 0.30h → 0.47h)
    final centerX = w / 2;
    final centerY = h * .47;

    // 기본 반경
    final baseRadius = min(w, h) * .36;

    // 화면에 절대 안 잘리도록 하는 “안전 반경” 계산
    final safeRadiusY = min(
      centerY - topPad - seatH / 2, // 위쪽 여백
      (h - bottomPad - seatH / 2) - centerY, // 아래쪽 여백
    );

    final safeRadiusX = (w - seatW) / 2; // 좌/우 여백

    final radius = max(0.0, min(baseRadius, min(safeRadiusY, safeRadiusX)));
    final seated = players.length;
    final angleStep = 2 * pi / seated;

    final list = <Widget>[];
    for (int i = 0; i < seated; i++) {
      final angle = -pi / 2 + i * angleStep;
      final x = centerX + radius * cos(angle);
      final y = centerY + radius * sin(angle);

      final isBtn = i == dealer;
      final actor = i == toAct && handRunning;
      list.add(Positioned(
        left: x - seatW / 2,
        top: y - seatH / 2,
        width: seatW,
        height: seatH,
        child: _seatCard(i, isBtn: isBtn, toAct: actor),
      ));
    }
    return list;
  }

  Widget _seatCard(int seat, {required bool isBtn, required bool toAct}) {
    final p = players[seat];
    final alive = p.inHand && !p.folded;
    return AnimatedOpacity(
      opacity: p.seated ? 1.0 : .35,
      duration: const Duration(milliseconds: 150),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(alive ? .95 : .70),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: toAct ? Colors.amber : Colors.black12, width: toAct ? 2 : 1),
        ),
        child: Row(
          children: [
            if (isBtn)
              Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.black54),
                ),
                child: const Center(child: Text('D', style: TextStyle(fontWeight: FontWeight.w900))),
              ),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('₵ ${p.stack}',
                        style: TextStyle(fontWeight: FontWeight.w800, color: p.isHero ? Colors.black : Colors.black87)),
                    if (p.betThisStreet > 0) const SizedBox(height: 1),
                    if (p.betThisStreet > 0) Text('Bet ${p.betThisStreet}', style: const TextStyle(fontSize: 12)),
                    if (!p.seated) const Text('OUT', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    if (p.folded) const Text('FOLDED', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    if (p.allIn) const Text('ALL-IN', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            // 홀카드(히어로만 공개)
            p.isHero
                ? Row(children: p.hole.map((c) => _miniCard(c)).toList())
                : Row(children: p.hole.map((_) => _miniBack()).toList()),
          ],
        ),
      ),
    );
  }

  Widget _miniCard(CardX c) {
    return Container(
      width: 26,
      height: 34,
      margin: const EdgeInsets.only(left: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 3)],
      ),
      child: Center(
        child: FittedBox(
          child: Text('${c.rankStr}${c.suitIcon}', style: TextStyle(fontWeight: FontWeight.w900, color: c.suitColor)),
        ),
      ),
    );
  }

  Widget _miniBack() {
    return Container(
      width: 26,
      height: 34,
      margin: const EdgeInsets.only(left: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.black87, Colors.black54]),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _boardView() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: 58,
              height: 82,
              child: i < board.length ? _bigCard(board[i]) : _cardBack(),
            ),
          ),
      ],
    );
  }

  Widget _bigCard(CardX c) {
    return LayoutBuilder(
      builder: (context, cons) {
        final h = cons.maxHeight;

        final compact = h <= 78; // 작은 카드: 하단 대칭 생략
        final pad = compact ? 4.0 : 6.0;

        // 카드 높이에 따른 안전 폰트 사이즈 클램프
        // (작은 카드에서도 절대 오버플로우 안 나게)
        double clampFont(double want, double byHeightFrac) {
          final byH = h * byHeightFrac;
          return want.clamp(8.0, byH); // 최솟값 8 보장
        }

        final rankSize = clampFont(compact ? 14 : 18, 0.22);
        final suitSize = clampFont(compact ? 12 : 16, 0.18);

        final topLeft = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.rankStr,
              textHeightBehavior:
              const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: c.suitColor,
                fontSize: rankSize,
                height: 1.0,
              ),
            ),
            Text(
              c.suitIcon,
              textHeightBehavior:
              const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
              style: TextStyle(
                color: c.suitColor,
                fontSize: suitSize,
                height: 1.0,
              ),
            ),
          ],
        );

        final bottomRight = Transform.rotate(
          angle: pi,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.rankStr,
                textHeightBehavior:
                const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: c.suitColor,
                  fontSize: rankSize,
                  height: 1.0,
                ),
              ),
              Text(
                c.suitIcon,
                textHeightBehavior:
                const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                style: TextStyle(
                  color: c.suitColor,
                  fontSize: suitSize,
                  height: 1.0,
                ),
              ),
            ],
          ),
        );

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black26),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.12), blurRadius: 6)],
          ),
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 좌상단
                Align(
                  alignment: Alignment.topLeft,
                  child: FittedBox(
                    // 아주 작은 카드에서 자동 축소
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: topLeft,
                  ),
                ),
                if (!compact)
                // 우하단(대칭 인쇄) — 작은 카드에서는 생략
                  Align(
                    alignment: Alignment.bottomRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomRight,
                      child: bottomRight,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cardBack() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.black87, Colors.black54]),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.12), blurRadius: 6)],
      ),
    );
  }

  Widget _actionPanel(ColorScheme cs) {
    final hero = players[heroSeat];
    final myTurn = handRunning && toAct == heroSeat && hero.inHand && !hero.folded && !hero.allIn;
    final int toCall = max(0, currentBet - hero.betThisStreet).toInt();
    final canCheck = toCall == 0;

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              _pill('Street: ${street.name.toUpperCase()}'),
              _pill('Pot: ${players.fold<int>(0, (s, p) => s + p.committed)}'),
              _pill('To call: $toCall'),
              _pill('Min raise: ${max(minRaise, _lv.bb)}'),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: myTurn ? () => _fold(heroSeat) : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[900], foregroundColor: Colors.white),
                child: const Text('FOLD', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
              ElevatedButton(
                onPressed: myTurn ? () => _checkOrCall(heroSeat) : null,
                child: Text(canCheck ? 'CHECK' : 'CALL $toCall', style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              ElevatedButton(
                onPressed: myTurn ? () => _openRaiseSheet(heroSeat) : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[700], foregroundColor: Colors.black),
                child: const Text('RAISE', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _pill(String s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(s, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  void _openRaiseSheet(int seat) {
    final p = players[seat];
    final int minTo = max(currentBet + max(minRaise, _lv.bb).toInt(), p.betThisStreet + _lv.bb);
    final int maxTo = p.betThisStreet + p.stack; // 올인까지
    int slider = minTo; // 초기값: 최소 레이즈(굳이 clamp 불필요)

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSt) {
            final double minVal = minTo.toDouble().clamp(0.0, maxTo.toDouble());
            final double maxVal = (maxTo >= minTo + 1 ? maxTo.toDouble() : (minTo + 1).toDouble());

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Choose Raise To', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('$slider', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  Slider(
                    value: slider.toDouble(),
                    min: minVal,
                    max: maxVal,
                    divisions: max(1, (maxTo - minTo)).toInt(),
                    label: '$slider',
                    onChanged: (v) => setSt(() => slider = v.round()),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _raiseTo(seat, slider);
                        },
                        child: const Text('Confirm'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _raiseTo(seat, p.betThisStreet + p.stack); // 올인
                        },
                        style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                        child: const Text('ALL-IN'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /* ───────────────────────────────────────────────────────────────────────────
     Settings / History / Replay
     ─────────────────────────────────────────────────────────────────────────── */

  void _openSettings() {
    if (tourRunning || handRunning) {
      _toast('진행 중에는 설정을 변경할 수 없습니다.');
      return;
    }
    int playerCount = cfg.playerCount;
    int startingStack = cfg.startingStack;
    int buyIn = cfg.buyIn;
    bool reentry = cfg.reentryEnabled;
    int cutoff = cfg.reentryCutoffLevel;
    int aiSamples = cfg.aiSamples;
    int levelPreset = 0; // 0: 기본, 1: 타이트(짧음), 2: 롱(느림)
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        return StatefulBuilder(builder: (context, setSt) {
          return Padding(
            padding:
            EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 12 + MediaQuery.of(context).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Tournament Settings', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  _settingRow(
                    'Players',
                    Slider(
                      value: playerCount.toDouble(),
                      min: 2,
                      max: 9,
                      divisions: 7,
                      label: '$playerCount',
                      onChanged: (v) => setSt(() => playerCount = v.round()),
                    ),
                    trailing: Text('$playerCount'),
                  ),
                  _settingRow(
                    'Starting Stack',
                    Slider(
                      value: startingStack.toDouble(),
                      min: 2000,
                      max: 50000,
                      divisions: 48,
                      label: '$startingStack',
                      onChanged: (v) => setSt(() => startingStack = (v ~/ 100) * 100),
                    ),
                    trailing: Text('₵ $startingStack'),
                  ),
                  _settingRow(
                    'Buy-in (prize pool)',
                    Slider(
                      value: buyIn.toDouble(),
                      min: 10,
                      max: 1000,
                      divisions: 99,
                      label: '$buyIn',
                      onChanged: (v) => setSt(() => buyIn = v.round()),
                    ),
                    trailing: Text('$buyIn'),
                  ),
                  _settingRow(
                    'AI Samples',
                    Slider(
                      value: aiSamples.toDouble(),
                      min: 10,
                      max: 120,
                      divisions: 22,
                      label: '$aiSamples',
                      onChanged: (v) => setSt(() => aiSamples = v.round()),
                    ),
                    trailing: Text('$aiSamples'),
                  ),
                  SwitchListTile.adaptive(
                    value: reentry,
                    onChanged: (v) => setSt(() => reentry = v),
                    title: const Text('Re-entry enabled'),
                    subtitle: const Text('컷오프 레벨 전까지 재입장 허용'),
                  ),
                  _settingRow(
                    'Re-entry Cutoff Level',
                    Slider(
                      value: cutoff.toDouble(),
                      min: 0,
                      max: 4,
                      divisions: 4,
                      label: '${cutoff + 1}',
                      onChanged: reentry ? (v) => setSt(() => cutoff = v.round()) : null,
                    ),
                    trailing: Text('≤ Level ${cutoff + 1}'),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text('Levels preset:', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: levelPreset,
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Default (180s x 5)')),
                          DropdownMenuItem(value: 1, child: Text('Turbo (90s x 6)')),
                          DropdownMenuItem(value: 2, child: Text('Deep (240s x 6)')),
                        ],
                        onChanged: (v) => setSt(() => levelPreset = v ?? 0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final presets = <int, List<_Level>>{
                            0: const [
                              _Level(sb: 100, bb: 200, bbAnte: true, secs: 180),
                              _Level(sb: 200, bb: 400, bbAnte: true, secs: 180),
                              _Level(sb: 300, bb: 600, bbAnte: true, secs: 180),
                              _Level(sb: 500, bb: 1000, bbAnte: true, secs: 180),
                              _Level(sb: 1000, bb: 2000, bbAnte: true, secs: 180),
                            ],
                            1: const [
                              _Level(sb: 100, bb: 200, bbAnte: true, secs: 90),
                              _Level(sb: 200, bb: 400, bbAnte: true, secs: 90),
                              _Level(sb: 300, bb: 600, bbAnte: true, secs: 90),
                              _Level(sb: 400, bb: 800, bbAnte: true, secs: 90),
                              _Level(sb: 600, bb: 1200, bbAnte: true, secs: 90),
                              _Level(sb: 1000, bb: 2000, bbAnte: true, secs: 90),
                            ],
                            2: const [
                              _Level(sb: 100, bb: 200, bbAnte: true, secs: 240),
                              _Level(sb: 200, bb: 400, bbAnte: true, secs: 240),
                              _Level(sb: 300, bb: 600, bbAnte: true, secs: 240),
                              _Level(sb: 500, bb: 1000, bbAnte: true, secs: 240),
                              _Level(sb: 800, bb: 1600, bbAnte: true, secs: 240),
                              _Level(sb: 1200, bb: 2400, bbAnte: true, secs: 240),
                            ],
                          };
                          cfg = cfg.copyWith(
                            playerCount: playerCount,
                            startingStack: startingStack,
                            reentryEnabled: reentry,
                            reentryCutoffLevel: cutoff,
                            aiSamples: aiSamples,
                            levels: presets[levelPreset],
                            buyIn: buyIn,
                          );
                          Navigator.pop(context);
                          _newTable();
                        },
                        child: const Text('Apply'),
                      ),
                    ],
                  )
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _settingRow(String title, Widget control, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(flex: 3, child: control),
          if (trailing != null) ...[const SizedBox(width: 8), trailing]
        ],
      ),
    );
  }

  void _openHistory() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('Hand History', style: TextStyle(fontWeight: FontWeight.w900)),
                    const Spacer(),
                    if (history.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => _openReplay(history.last),
                        icon: const Icon(Icons.play_circle_fill),
                        label: const Text('Replay last hand'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: history.length,
                    itemBuilder: (_, i) {
                      final h = history[history.length - 1 - i];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ExpansionTile(
                          title: Text('Hand #${h.handNo} • Btn ${h.dealerSeat} • ${h.level.desc}'),
                          childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(h.log.join('\n')),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _copyToClipboard(h.log.join('\n')),
                                  icon: const Icon(Icons.copy),
                                  label: const Text('Copy'),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () => _openReplay(h),
                                  icon: const Icon(Icons.play_circle_fill),
                                  label: const Text('Replay'),
                                ),
                              ],
                            )
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openReplay(HandHistory h) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        int step = 0;
        Timer? auto;
        void cancel() {
          auto?.cancel();
          auto = null;
        }

        return StatefulBuilder(
          builder: (context, setSt) {
            final s = h.replay;
            final cur = s.isEmpty ? null : s[step];
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text('Replay • Hand #${h.handNo}', style: const TextStyle(fontWeight: FontWeight.w900)),
                        const Spacer(),
                        IconButton(
                          icon: Icon(auto == null ? Icons.play_arrow : Icons.pause),
                          onPressed: () {
                            if (auto == null) {
                              auto = Timer.periodic(const Duration(seconds: 1), (_) {
                                if (step < s.length - 1) {
                                  setSt(() => step++);
                                } else {
                                  cancel();
                                }
                              });
                            } else {
                              cancel();
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next),
                          onPressed: () {
                            if (step < s.length - 1) setSt(() => step++);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (cur != null)
                      Column(
                        children: [
                          Text(cur.text, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (int i = 0; i < 5; i++)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 3),
                                  child: SizedBox(
                                    width: 44,
                                    height: 62,
                                    child: i < cur.board.length ? _bigCard(cur.board[i]) : _cardBack(),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (cur.showHoles.isNotEmpty)
                            Wrap(
                              spacing: 10,
                              runSpacing: 6,
                              alignment: WrapAlignment.center,
                              children: cur.showHoles.entries.map((e) {
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('P${e.key}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                                    for (final c in e.value) _miniCard(c),
                                  ],
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /* ───────────────────────────────────────────────────────────────────────────
     유틸
     ─────────────────────────────────────────────────────────────────────────── */

  void _openRulebook() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WsopHoldemRulesPage()),
    );
  }

  String _cardsStr(List<CardX> cs) => cs.map((c) => '${c.rankStr}${c.suitIcon}').join(' ');

  void _toast(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _copyToClipboard(String t) async {
    await Clipboard.setData(ClipboardData(text: t));
    _toast('Copied.');
  }

  String _formatMMSS(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }
}

/* 블라인드 레벨 */
class _Level {
  final int sb, bb;
  final bool bbAnte; // WSOP에서 일반화된 BB Ante
  final int secs;

  const _Level({required this.sb, required this.bb, required this.bbAnte, required this.secs});

  String get desc => '$sb/$bb${bbAnte ? " BBAnte" : ""} • ${secs}s';
}

Widget _hudPill(IconData ico, String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(.06),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ico, size: 14),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

