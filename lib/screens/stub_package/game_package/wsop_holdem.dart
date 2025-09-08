// lib/screens/stub_package/game_package/wsop_holdem.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class WsopHoldemPage extends StatefulWidget {
  const WsopHoldemPage({super.key});

  @override
  State<WsopHoldemPage> createState() => _WsopHoldemPageState();
}

/* ─────────────────────────────────────────────────────────────────────────────
   모델/유틸 (경량)
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

  bool inHand = true;
  bool folded = false;
  bool allIn = false;
  List<CardX> hole = [];
  int betThisStreet = 0;
  int committed = 0;

  Player({required this.name, required this.stack, required this.isHero});
}

class HandRank {
  // 카테고리 높을수록 강함 (StraightFlush=8 ... HighCard=0)
  final int cat;

  // 타이브레이커 내림차순
  final List<int> tiebreak;

  HandRank(this.cat, this.tiebreak);

  int compareTo(HandRank other) {
    final lim = (tiebreak.length < other.tiebreak.length) ? tiebreak.length : other.tiebreak.length;
    if (cat != other.cat) return cat.compareTo(other.cat);
    for (int i = 0; i < lim; i++) {
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
  final Set<int> eligible = {};
}

/* ─────────────────────────────────────────────────────────────────────────────
   핸드 평가(7장 중 베스트 5)
   ───────────────────────────────────────────────────────────────────────────── */

HandRank evaluateBest7(List<CardX> seven) {
  assert(seven.length == 7);
  HandRank? best;
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
      if (u[0] == 2 && u[1] == 3 && u[2] == 4 && u[3] == 5 && u[4] == 14) return true; // A-5
      return u.last - u.first == 4;
    }

    int straightHigh(List<int> r) {
      final u = r.toSet().toList()..sort();
      if (u[0] == 2 && u[1] == 3 && u[2] == 4 && u[3] == 5 && u[4] == 14) return 5;
      return u.last;
    }

    final st = isStraight(ranks);
    final Map<int, int> cnt = {};
    for (final r in ranks) cnt[r] = (cnt[r] ?? 0) + 1;
    final byCountThenRankDesc = cnt.entries.toList()
      ..sort((a, b) {
        if (a.value != b.value) return b.value.compareTo(a.value);
        return b.key.compareTo(a.key);
      });

    if (isFlush && st) return HandRank(8, [straightHigh(ranks)]);
    if (byCountThenRankDesc.first.value == 4) {
      final quad = byCountThenRankDesc.first.key;
      final tmp = List<int>.from(ranks)..removeWhere((e) => e == quad);
      return HandRank(7, [quad, tmp.first]);
    }
    if (byCountThenRankDesc[0].value == 3 && byCountThenRankDesc[1].value == 2) {
      return HandRank(6, [byCountThenRankDesc[0].key, byCountThenRankDesc[1].key]);
    }
    if (isFlush) return HandRank(5, List<int>.from(ranks));
    if (st) return HandRank(4, [straightHigh(ranks)]);
    if (byCountThenRankDesc[0].value == 3) {
      final trips = byCountThenRankDesc[0].key;
      final tmp = List<int>.from(ranks)..removeWhere((e) => e == trips);
      return HandRank(3, [trips, ...tmp.take(2)]);
    }
    if (byCountThenRankDesc[0].value == 2 && byCountThenRankDesc[1].value == 2) {
      final k0 = byCountThenRankDesc[0].key;
      final k1 = byCountThenRankDesc[1].key;
      final int hi = k0 > k1 ? k0 : k1;
      final int lo = k0 > k1 ? k1 : k0;
      final tmp = List<int>.from(ranks)..removeWhere((e) => e == hi || e == lo);
      return HandRank(2, [hi, lo, tmp.first]);
    }
    if (byCountThenRankDesc[0].value == 2) {
      final pair = byCountThenRankDesc[0].key;
      final tmp = List<int>.from(ranks)..removeWhere((e) => e == pair);
      return HandRank(1, [pair, ...tmp.take(3)]);
    }
    return HandRank(0, List<int>.from(ranks));
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
   경량 라운드 엔진 (캐시게임 스타일)
   ───────────────────────────────────────────────────────────────────────────── */

class _WsopHoldemPageState extends State<WsopHoldemPage> {
  // 구조
  static const int _sb = 50;
  static const int _bb = 100;
  int playerCount = 6;
  int startingStack = 5000;

  // 플레이어/버튼
  final List<Player> players = [];
  int dealer = 0;
  int heroSeat = 0;

  // 딜/베팅 상태
  Deck? deck;
  Street street = Street.preflop;
  List<CardX> board = [];
  int toAct = 0;
  int firstToAct = 0; // 각 스트리트 첫 액터
  int currentBet = 0;
  int minRaise = _bb; // 최소 레이즈 갭
  int lastAggressor = -1;
  bool handRunning = false;

  // 사이드팟
  List<PotSlice> pots = [];

  // 메시지
  String msg = 'Tap DEAL to start a hand';

  // AI
  int aiSamples = 24;

  @override
  void initState() {
    super.initState();
    _newTable();
  }

  void _newTable() {
    players.clear();
    final int n = playerCount.clamp(2, 6);
    players.add(Player(name: 'YOU', stack: startingStack, isHero: true));
    for (int i = 1; i < n; i++) {
      players.add(Player(name: 'BOT $i', stack: startingStack, isHero: false));
    }
    heroSeat = 0;
    dealer = Random().nextInt(players.length);
    msg = 'Ready. Blinds $_sb/$_bb';
    setState(() {});
  }

  /* ───────────────────────────────────────────────────────────────────────────
     핸드 진행
     ─────────────────────────────────────────────────────────────────────────── */

  void _newHand() {
    // 상태 초기화
    for (final p in players) {
      p.inHand = p.seated && p.stack > 0;
      p.folded = false;
      p.allIn = false;
      p.hole = [];
      p.betThisStreet = 0;
      p.committed = 0;
    }

    if (!players.any((p) => p.inHand)) {
      _newTable();
      return;
    }

    board = [];
    pots = [];
    street = Street.preflop;
    deck = Deck();
    currentBet = 0;
    minRaise = _bb;
    lastAggressor = -1;
    handRunning = true;

    // 버튼 이동
    do {
      dealer = (dealer + 1) % players.length;
    } while (!players[dealer].seated);

    // 블라인드
    final sbSeat = _nextSeated(dealer, 1);
    final bbSeat = _nextSeated(dealer, 2);
    _post(sbSeat, players[sbSeat].stack < _sb ? players[sbSeat].stack : _sb, label: 'posts SB');
    _post(bbSeat, players[bbSeat].stack < _bb ? players[bbSeat].stack : _bb, label: 'posts BB');

    // 딜
    for (int r = 0; r < 2; r++) {
      int s = _nextSeated(dealer, 1);
      for (int i = 0; i < players.length; i++) {
        if (!players[s].seated) {
          s = _nextSeated(s, 1);
          continue;
        }
        if (players[s].inHand) {
          players[s].hole.add(deck!.draw());
        }
        s = _nextSeated(s, 1);
      }
    }

    // 액션 시작: BB 다음
    toAct = _nextToAct(bbSeat);
    firstToAct = toAct;
    currentBet = players[bbSeat].betThisStreet;
    minRaise = _bb;
    lastAggressor = bbSeat;

    msg = 'New hand. Blinds $_sb/$_bb';
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

  int? _nextToActOrNull(int from) {
    int s = from;
    for (int i = 0; i < players.length; i++) {
      s = _nextSeated(s, 1);
      final p = players[s];
      if (p.inHand && !p.folded && !p.allIn) return s;
    }
    return null; // 전원 올인/폴드
  }

  int _nextToAct(int from) => _nextToActOrNull(from) ?? from;

  int? _nextEligibleAfter(int seat) => _nextToActOrNull(seat);

  void _post(int seat, int amt, {String label = 'posts'}) {
    final p = players[seat];
    final int pay = p.stack < amt ? p.stack : amt;
    p.stack -= pay;
    p.betThisStreet += pay;
    p.committed += pay;
  }

  bool _roundShouldEnd() {
    for (final p in players) {
      if (!p.inHand || p.folded || p.allIn) continue;
      if (p.betThisStreet != currentBet) return false;
    }
    final next = _nextToActOrNull(toAct);
    if (next == null) return true; // 전원 올인/폴드
    if (lastAggressor >= 0) {
      final closeSeat = _nextEligibleAfter(lastAggressor);
      return closeSeat != null && next == closeSeat;
    } else {
      return next == firstToAct; // 체크로만 돌아올 때
    }
  }

  void _endStreet() {
    for (final p in players) {
      p.betThisStreet = 0;
    }
    currentBet = 0;
    minRaise = _bb;
    lastAggressor = -1;

    if (street == Street.preflop) {
      deck!.burn();
      board.addAll([deck!.draw(), deck!.draw(), deck!.draw()]);
      street = Street.flop;
    } else if (street == Street.flop) {
      deck!.burn();
      board.add(deck!.draw());
      street = Street.turn;
    } else if (street == Street.turn) {
      deck!.burn();
      board.add(deck!.draw());
      street = Street.river;
    } else {
      street = Street.showdown;
      _showdownAndPayout();
      return;
    }

    final nxt = _nextToActOrNull(dealer);
    if (nxt == null) {
      // 전원 올인 → 자동 런아웃
      while (street != Street.showdown) {
        if (street == Street.flop) {
          deck!.burn();
          board.add(deck!.draw());
          street = Street.turn;
        } else if (street == Street.turn) {
          deck!.burn();
          board.add(deck!.draw());
          street = Street.river;
        } else {
          street = Street.showdown;
        }
      }
      setState(() {});
      _showdownAndPayout();
      return;
    }
    toAct = nxt;
    firstToAct = toAct;
    msg = street.name.toUpperCase();
    setState(() {});
    _maybeBotAct();
  }

  void _collectSidePots() {
    final contribs = <int>[];
    for (final p in players) {
      if (p.committed > 0) contribs.add(p.committed);
    }
    if (contribs.isEmpty) return;

    final lvls = (contribs.toSet().toList()..sort());
    int prev = 0;
    pots.clear();

    for (final lv in lvls) {
      final slice = PotSlice();

      int contributors = 0;
      for (int i = 0; i < players.length; i++) {
        if (players[i].committed >= lv) contributors++;
      }
      for (int i = 0; i < players.length; i++) {
        final p = players[i];
        if (p.committed >= lv && p.inHand && !p.folded) {
          slice.eligible.add(i);
        }
      }

      final chunk = (lv - prev) * contributors;
      if (chunk > 0) {
        slice.amount = chunk;
        pots.add(slice);
      }
      prev = lv;
    }
  }

  void _showdownAndPayout() {
    final alive = <int>[];
    for (int i = 0; i < players.length; i++) {
      final p = players[i];
      if (p.inHand && !p.folded) alive.add(i);
    }
    final totalPot = players.fold<int>(0, (s, p) => s + p.committed);

    if (alive.length == 1) {
      final w = alive.first;
      players[w].stack += totalPot;
      msg = '${players[w].name} wins ${_fmt(totalPot)} (no showdown)';
      _finishHand();
      return;
    }

    _collectSidePots();

    final ranks = <int, HandRank>{};
    for (final i in alive) {
      ranks[i] = evaluateBest7([...players[i].hole, ...board]);
    }

    int awarded = 0;
    for (final pot in pots) {
      final contenders = pot.eligible.where((i) => players[i].inHand && !players[i].folded).toList();
      if (contenders.isEmpty || pot.amount == 0) continue;

      contenders.sort((a, b) => ranks[b]!.compareTo(ranks[a]!));
      final best = ranks[contenders.first]!;
      final winners = contenders.where((i) => ranks[i]!.compareTo(best) == 0).toList();

      final share = pot.amount ~/ winners.length;
      final rem = pot.amount - share * winners.length;

      for (final w in winners) {
        players[w].stack += share;
        awarded += share;
      }

      // 홀칩: 버튼 왼쪽부터
      int pos = dealer;
      int r = rem;
      while (r > 0) {
        pos = _nextSeated(pos, 1);
        if (winners.contains(pos)) {
          players[pos].stack += 1;
          awarded += 1;
          r--;
        }
      }
    }

    msg = 'Showdown. Pot ${_fmt(awarded)} awarded.';
    _finishHand();
  }

  void _finishHand() {
    handRunning = false;
    for (final p in players) {
      p.betThisStreet = 0;
      p.committed = 0;
      if (p.stack <= 0) p.inHand = false;
    }
    setState(() {});
  }

  /* ───────────────────────────────────────────────────────────────────────────
     액션 처리
     ─────────────────────────────────────────────────────────────────────────── */

  void _fold(int seat) {
    final p = players[seat];
    if (!p.inHand || p.folded) return;
    p.folded = true;
    _advanceAfterAction();
  }

  void _checkOrCall(int seat) {
    final p = players[seat];
    int toCall = currentBet - p.betThisStreet;
    if (toCall < 0) toCall = 0;
    final int pay = p.stack < toCall ? p.stack : toCall;
    p.stack -= pay;
    p.betThisStreet += pay;
    p.committed += pay;
    if (p.stack == 0) p.allIn = true;
    _advanceAfterAction();
  }

  void _raiseTo(int seat, int raiseTo) {
    final p = players[seat];

    int add = raiseTo - p.betThisStreet;
    if (add < 0) add = 0;
    if (add > p.stack) add = p.stack;
    int newBet = p.betThisStreet + add;

    final int fullRaiseNeeded = (minRaise > _bb ? minRaise : _bb);
    final int gap = newBet - currentBet;
    final bool isAllIn = add == p.stack;

    if (!isAllIn && gap < fullRaiseNeeded) {
      final int needTo = currentBet + fullRaiseNeeded;
      int add2 = needTo - p.betThisStreet;
      if (add2 > p.stack) add2 = p.stack;
      if (add2 < 0) add2 = 0;
      add = add2;
      newBet = p.betThisStreet + add;
    }

    p.stack -= add;
    p.betThisStreet += add;
    p.committed += add;

    final prevBet = currentBet;
    if (p.betThisStreet > currentBet) currentBet = p.betThisStreet;
    final increased = currentBet - prevBet;

    final madeFullRaise = increased >= fullRaiseNeeded;
    if (madeFullRaise) {
      minRaise = increased;
      lastAggressor = seat;
    }
    if (p.stack == 0) p.allIn = true;

    _advanceAfterAction();
  }

  void _advanceAfterAction() {
    if (_roundShouldEnd()) {
      _endStreet();
      return;
    }
    final nxt = _nextToActOrNull(toAct);
    if (nxt == null) {
      _endStreet();
      return;
    }
    toAct = nxt;
    setState(() {});
    _maybeBotAct();
  }

  /* ───────────────────────────────────────────────────────────────────────────
     봇(간단)
     ─────────────────────────────────────────────────────────────────────────── */

  void _maybeBotAct() {
    if (!mounted) return;
    if (!handRunning) return;
    if (players[toAct].isHero) return;

    Future.delayed(const Duration(milliseconds: 450), () {
      if (!mounted || !handRunning) return;
      _botAct(toAct);
    });
  }

  int _preflopScore(List<CardX> hole) {
    final a = hole[0], b = hole[1];
    final high = (a.rank > b.rank) ? a.rank : b.rank;
    final low = (a.rank > b.rank) ? b.rank : a.rank;
    final pair = a.rank == b.rank;
    final suited = a.suit == b.suit;
    final connected = (high - low == 1);
    int score = 0;

    if (pair) {
      if (high >= 13)
        score = 95;
      else if (high == 12)
        score = 88;
      else if (high == 11)
        score = 80;
      else if (high == 10)
        score = 72;
      else
        score = 55 + (high - 2) * 2;
    } else {
      if (high == 14 && low >= 10)
        score = suited ? 85 : 78;
      else if (high >= 13 && low >= 10)
        score = suited ? 76 : 68;
      else if (connected && high >= 10)
        score = suited ? 70 : 62;
      else if (suited && connected && high >= 7)
        score = 58;
      else if (high >= 12)
        score = suited ? 60 : 52;
      else
        score = suited ? 48 : 42;
    }
    return score.clamp(0, 100);
  }

  double _estimateWinProb(int seat) {
    final me = players[seat];
    final activeSeats = <int>[];
    for (int i = 0; i < players.length; i++) {
      if (i == seat) continue;
      final p = players[i];
      if (p.inHand && !p.folded && !p.allIn) activeSeats.add(i);
    }
    if (activeSeats.isEmpty) return 1.0;

    final int samples = (aiSamples > 12 ? aiSamples : 12);
    int wins = 0, ties = 0;

    for (int s = 0; s < samples; s++) {
      final d = Deck();
      d.removeMany(me.hole);
      d.removeMany(board);

      final oppHoles = <List<CardX>>[];
      for (final _ in activeSeats) {
        final c1 = d.draw();
        final c2 = d.draw();
        oppHoles.add([c1, c2]);
      }

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

      if (bestOpp == null)
        wins++;
      else {
        final cmp = myRank.compareTo(bestOpp);
        if (cmp > 0)
          wins++;
        else if (cmp == 0) ties++;
      }
    }
    final denom = samples <= 0 ? 1 : samples;
    return (wins + ties * 0.5) / denom;
  }

  void _botAct(int seat) {
    final p = players[seat];
    if (!p.inHand || p.folded || p.allIn) {
      _advanceAfterAction();
      return;
    }

    int need = currentBet - p.betThisStreet;
    if (need < 0) need = 0;
    final pot = players.fold<int>(0, (s, q) => s + q.committed);
    final stackBehind = p.stack;
    final denom = pot + need;
    final potOdds = need == 0 ? 0.0 : need / (denom <= 0 ? 1 : denom).toDouble();

    if (street == Street.preflop) {
      final score = _preflopScore(p.hole);
      if (need == 0) {
        if (score >= 75 && stackBehind > _bb * 3) {
          final int bump = (minRaise > _bb * 3 ? minRaise : _bb * 3);
          final int to = currentBet + bump;
          _raiseTo(seat, to);
        } else {
          _checkOrCall(seat);
        }
      } else {
        final wantCall = score >= 55 || potOdds < 0.22;
        if (wantCall && stackBehind >= need) {
          if (score >= 82 && stackBehind > need + _bb * 5) {
            final int bump = (minRaise > _bb * 3 ? minRaise : _bb * 3);
            final int to = currentBet + bump;
            _raiseTo(seat, to);
          } else {
            _checkOrCall(seat);
          }
        } else {
          _fold(seat);
        }
      }
    } else {
      final ehs = _estimateWinProb(seat);
      final strong = ehs >= 0.66;
      final marginal = ehs >= 0.46;

      if (need == 0) {
        if (strong && stackBehind > _bb * 2) {
          final int bump = (minRaise > _bb * 2 ? minRaise : _bb * 2);
          _raiseTo(seat, currentBet + bump);
        } else {
          _checkOrCall(seat);
        }
      } else {
        final breakeven = potOdds;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Texas Hold’em • Light'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Reset Table',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () {
              if (handRunning) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('마지막 핸드 종료 후 초기화됩니다.')));
                return;
              }
              _newTable();
            },
          ),
        ],
      ),
      backgroundColor: Colors.green[700],
      body: Column(
        children: [
          // HUD
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(color: Colors.white),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 6,
              children: [
                Text('Blinds: $_sb/$_bb', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
                Wrap(
                  spacing: 8,
                  children: [
                    _hudPill(Icons.people_alt_rounded, 'Players: ${players.where((p) => p.seated).length}'),
                    _hudPill(Icons.account_circle, 'Hero: ₵ ${_fmt(players[heroSeat].stack)}'),
                    _hudPill(Icons.paid, 'Pot: ${_fmt(players.fold<int>(0, (s, p) => s + p.committed))}'),
                  ],
                ),
              ],
            ),
          ),
          // 테이블
          Expanded(
            child: LayoutBuilder(
              builder: (context, cons) {
                final w = cons.maxWidth;
                final h = cons.maxHeight;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ..._seatWidgets(w, h),
                    Positioned(
                      bottom: 8, // ★ 커뮤니티 카드 하단 배치
                      left: 0,
                      right: 0,
                      child: IgnorePointer(child: Center(child: _boardView())),
                    ),
                  ],
                );
              },
            ),
          ),
          // 액션
          _actionPanel(cs),
        ],
      ),
      floatingActionButton: handRunning
          ? null
          : FloatingActionButton.extended(
        onPressed: _newHand,
        label: const Text('DEAL'),
        icon: const Icon(Icons.casino),
      ),
    );
  }

  List<Widget> _seatWidgets(double w, double h) {
    const seatW = 180.0, seatH = 84.0;
    const topPad = 8.0, bottomPad = 8.0;
    final centerX = w / 2;
    final centerY = h * .47;
    final baseRadius = min(w, h) * .36;

    final safeRadiusY = min(centerY - topPad - seatH / 2, (h - bottomPad - seatH / 2) - centerY);
    final safeRadiusX = (w - seatW) / 2;
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
                    Text('₵ ${_fmt(p.stack)}',
                        style: TextStyle(fontWeight: FontWeight.w800, color: p.isHero ? Colors.black : Colors.black87)),
                    if (p.betThisStreet > 0) const SizedBox(height: 1),
                    if (p.betThisStreet > 0) Text('Bet ${_fmt(p.betThisStreet)}', style: const TextStyle(fontSize: 12)),
                    if (!p.seated) const Text('OUT', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    if (p.folded) const Text('FOLDED', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    if (p.allIn) const Text('ALL-IN', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
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
        final compact = h <= 78;
        final pad = compact ? 4.0 : 6.0;

        double clampFont(double want, double byHeightFrac) {
          final byH = h * byHeightFrac;
          return want.clamp(8.0, byH);
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
              style: TextStyle(fontWeight: FontWeight.w900, color: c.suitColor, fontSize: rankSize, height: 1.0),
            ),
            Text(
              c.suitIcon,
              textHeightBehavior:
              const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
              style: TextStyle(color: c.suitColor, fontSize: suitSize, height: 1.0),
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
                style: TextStyle(fontWeight: FontWeight.w900, color: c.suitColor, fontSize: rankSize, height: 1.0),
              ),
              Text(
                c.suitIcon,
                textHeightBehavior:
                const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                style: TextStyle(color: c.suitColor, fontSize: suitSize, height: 1.0),
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
                Align(alignment: Alignment.topLeft, child: FittedBox(fit: BoxFit.scaleDown, child: topLeft)),
                if (!compact)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: FittedBox(fit: BoxFit.scaleDown, child: bottomRight),
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
    int toCall = currentBet - hero.betThisStreet;
    if (toCall < 0) toCall = 0;
    final canCheck = toCall == 0;
    final int minRaiseToShow = (minRaise > _bb ? minRaise : _bb);

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
              _pill('Pot: ${_fmt(players.fold<int>(0, (s, p) => s + p.committed))}'),
              _pill('To call: ${_fmt(toCall)}'),
              _pill('Min raise: ${_fmt(minRaiseToShow)}'),
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
                child: Text(canCheck ? 'CHECK' : 'CALL ${_fmt(toCall)}',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
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
      decoration: BoxDecoration(color: Colors.black.withOpacity(.06), borderRadius: BorderRadius.circular(999)),
      child: Text(s, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  void _openRaiseSheet(int seat) {
    final p = players[seat];
    final int minTo = currentBet + ((minRaise > _bb) ? minRaise : _bb);
    final int maxTo = p.betThisStreet + p.stack; // 올인 한도
    int slider = (minTo <= maxTo) ? minTo : maxTo;

    final double maxVal = (maxTo >= minTo + 1 ? maxTo.toDouble() : (minTo + 1).toDouble());
    final double minVal = minTo.toDouble().clamp(0.0, maxVal);
    final int divisions = (maxTo - minTo) > 0 ? (maxTo - minTo) : 1;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSt) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Choose Raise To', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(_fmt(slider), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  Slider(
                    value: (slider.toDouble().clamp(minVal, maxVal)),
                    min: minVal,
                    max: maxVal,
                    divisions: divisions,
                    label: _fmt(slider),
                    onChanged: (v) => setSt(() => slider = v.round()),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
     유틸
     ─────────────────────────────────────────────────────────────────────────── */

  String _fmt(int n) {
    final s = n.toString();
    final out = StringBuffer();
    int cnt = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      out.write(s[i]);
      cnt++;
      if (i > 0 && cnt % 3 == 0) out.write(',');
    }
    return out.toString().split('').reversed.join();
  }
}

/* 공용 HUD Pill 위젯(경량) */
Widget _hudPill(IconData ico, String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: Colors.black.withOpacity(.06), borderRadius: BorderRadius.circular(999)),
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
