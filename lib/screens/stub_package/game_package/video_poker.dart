import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VideoPokerPlusPage extends StatefulWidget {
  const VideoPokerPlusPage({super.key});

  @override
  State<VideoPokerPlusPage> createState() => _VideoPokerPlusPageState();
}

// ─────────────────────────────────────────────────
// 모델/유틸
// ─────────────────────────────────────────────────
enum Suit { spade, heart, diamond, club }

class PlayingCard {
  final Suit suit;
  final int rank; // 2..14 (J=11,Q=12,K=13,A=14)
  const PlayingCard(this.suit, this.rank);

  @override
  bool operator ==(Object other) => other is PlayingCard && other.suit == suit && other.rank == rank;

  @override
  int get hashCode => Object.hash(suit, rank);
}

class _Deck {
  final _rng = Random();
  final List<PlayingCard> _cards = [];

  _Deck() {
    for (final s in Suit.values) {
      for (int r = 2; r <= 14; r++) {
        _cards.add(PlayingCard(s, r));
      }
    }
    _cards.shuffle(_rng);
  }

  PlayingCard draw() => _cards.removeLast();

  void remove(PlayingCard c) {
    final i = _cards.indexWhere((x) => x == c);
    if (i >= 0) _cards.removeAt(i);
  }
}

// 족보
enum HandCat {
  royalFlush,
  straightFlush,
  fourKind,
  fullHouse,
  flush,
  straight,
  threeKind,
  twoPair,
  jacksOrBetter,
  none,
}

String _handLabel(HandCat cat) {
  switch (cat) {
    case HandCat.royalFlush:
      return 'Royal Flush!';
    case HandCat.straightFlush:
      return 'Straight Flush';
    case HandCat.fourKind:
      return 'Four of a Kind';
    case HandCat.fullHouse:
      return 'Full House';
    case HandCat.flush:
      return 'Flush';
    case HandCat.straight:
      return 'Straight';
    case HandCat.threeKind:
      return 'Three of a Kind';
    case HandCat.twoPair:
      return 'Two Pair';
    case HandCat.jacksOrBetter:
      return 'Jacks or Better';
    case HandCat.none:
      return 'No Win';
  }
}

int _payout(HandCat cat, int bet) {
  // 9/6 Jacks or Better
  switch (cat) {
    case HandCat.royalFlush:
      return bet == 5 ? 4000 : 250 * bet; // 맥스베팅 보너스
    case HandCat.straightFlush:
      return 50 * bet;
    case HandCat.fourKind:
      return 25 * bet;
    case HandCat.fullHouse:
      return 9 * bet;
    case HandCat.flush:
      return 6 * bet;
    case HandCat.straight:
      return 4 * bet;
    case HandCat.threeKind:
      return 3 * bet;
    case HandCat.twoPair:
      return 2 * bet;
    case HandCat.jacksOrBetter:
      return 1 * bet;
    case HandCat.none:
      return 0;
  }
}

HandCat _evaluate(List<PlayingCard> cards) {
  final ranks = cards.map((c) => c.rank).toList()..sort();
  final suits = cards.map((c) => c.suit).toList();
  final isFlush = suits.toSet().length == 1;

  bool isStraight(List<int> r) {
    final u = r.toSet().toList()..sort();
    if (u.length != 5) return false;
    // A-2-3-4-5
    if (u[0] == 2 && u[1] == 3 && u[2] == 4 && u[3] == 5 && u[4] == 14) return true;
    return u.last - u.first == 4;
  }

  final straight = isStraight(ranks);

  // 카운팅
  final Map<int, int> cnt = {};
  for (final r in ranks) cnt[r] = (cnt[r] ?? 0) + 1;
  final countsDesc = (cnt.values.toList()..sort((a, b) => b.compareTo(a)));

  if (isFlush && straight) {
    final isRoyal = ranks.toSet().containsAll({10, 11, 12, 13, 14});
    return isRoyal ? HandCat.royalFlush : HandCat.straightFlush;
  }
  if (countsDesc.first == 4) return HandCat.fourKind;
  if (countsDesc.length == 2 && countsDesc.contains(3) && countsDesc.contains(2)) {
    return HandCat.fullHouse;
  }
  if (isFlush) return HandCat.flush;
  if (straight) return HandCat.straight;
  if (countsDesc.first == 3) return HandCat.threeKind;
  if (countsDesc.where((e) => e == 2).length == 2) return HandCat.twoPair;
  if (countsDesc.first == 2) {
    final pairRank = cnt.entries.firstWhere((e) => e.value == 2).key;
    if (pairRank >= 11) return HandCat.jacksOrBetter;
  }
  return HandCat.none;
}

// ─────────────────────────────────────────────────
// 상태
// ─────────────────────────────────────────────────
class _VideoPokerPlusPageState extends State<VideoPokerPlusPage> {
  // 크레딧/베팅
  int credits = 100;
  int betPerHand = 1;

  // 멀티핸드
  final List<int> _handsOptions = [1, 3, 5];
  int handsCount = 1;

  // 라운드 상태
  bool inDealPhase = true; // true면 Deal, false면 Draw 대기
  late _Deck deckForInitial;
  List<PlayingCard> baseHand = [];
  List<bool> holds = List<bool>.filled(5, false);
  bool autoHold = false;

  // 드로우 결과(멀티핸드)
  List<List<PlayingCard>> resultHands = [];

  // UI 표시
  String lastMessage = 'Welcome!';
  int lastWinTotal = 0;

  // 더블업(도박)
  bool inDouble = false;
  PlayingCard? dealerCard;
  List<PlayingCard> doubleChoices = [];
  PlayingCard? pickedCard;
  String doubleMessage = '카드를 선택하면 딜러와 비교합니다.';

  // ─ Tournament 모드(실제 비디오 포커 대회 룰) ─
  bool tournamentMode = false;      // 스위치: 토너먼트 규칙 사용 여부
  bool tournamentRunning = false;   // 진행 중인지
  int tournamentSeconds = 120;      // 제한시간(초)
  int remainingSeconds = 0;         // 남은 시간
  Timer? _tourTimer;
  int tourScore = 0;                // 점수(총 당첨액 합산)
  int handsPlayed = 0;              // 플레이한 핸드 수(통계)

  @override
  void initState() {
    super.initState();
    _resetRound(keepCredits: true);
  }

  @override
  void dispose() {
    _tourTimer?.cancel();
    super.dispose();
  }

  void _resetRound({bool keepCredits = true}) {
    deckForInitial = _Deck();
    inDealPhase = true;
    baseHand = [];
    holds = List<bool>.filled(5, false);
    resultHands = [];
    pickedCard = null;
    inDouble = false;
    dealerCard = null;
    doubleChoices = [];
    if (!keepCredits) credits = 100;
    lastWinTotal = 0;
    lastMessage = 'Welcome!';
    setState(() {});
  }

  // 토너먼트 타이머
  void _startTournament() {
    if (tournamentRunning) return;
    // 실제 대회 규칙: Max Bet(5), 더블업 금지, 점수제, (보통 1핸드) 강제
    setState(() {
      tournamentRunning = true;
      remainingSeconds = tournamentSeconds;
      tourScore = 0;
      handsPlayed = 0;
      betPerHand = 5;  // Max Bet 고정
      handsCount = 1;  // 1-Hand 고정
      lastMessage = 'Tournament started! Max Bet(5), Double 금지';
    });
    _tourTimer?.cancel();
    _tourTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (remainingSeconds <= 0) {
        _endTournament();
      } else {
        setState(() => remainingSeconds--);
      }
    });
  }

  void _endTournament() {
    _tourTimer?.cancel();
    _tourTimer = null;
    setState(() {
      tournamentRunning = false;
      lastMessage = 'Tournament ended. Score: $tourScore';
    });
    // 간단 요약 다이얼로그
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tournament Result'),
        content: Text('Score: $tourScore\nHands Played: $handsPlayed'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  String _formatMMSS(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  // ─────────────────────────────────────────────────
  // 게임 플로우
  // ─────────────────────────────────────────────────
  void _deal() {
    if (!inDealPhase) return;

    // 토너먼트 진행 중이면: 크레딧 차감/부족 체크 없음, 강제 Max Bet/1-Hand
    if (!tournamentRunning) {
      final need = betPerHand * handsCount;
      if (credits < need) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('크레딧이 부족합니다. (필요: $need)')),
        );
        return;
      }
      credits -= need;
    } else {
      // 강제 규칙 적용
      betPerHand = 5;
      handsCount = 1;
    }

    deckForInitial = _Deck();
    baseHand = List.generate(5, (_) => deckForInitial.draw());
    holds = List<bool>.filled(5, false);
    inDealPhase = false;
    resultHands = [];
    lastWinTotal = 0;
    lastMessage = tournamentRunning ? '토너먼트: HOLD 선택 후 DRAW' : '보류(HOLD)할 카드를 선택하세요.';
    if (autoHold) {
      holds = _autoHold(baseHand);
      lastMessage += ' (오토홀드 적용됨)';
    }
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _draw() {
    if (inDealPhase) return;

    // 각 핸드는 독립 덱(멀티핸드 머신과 동일) — held 카드는 덱에서 제거
    resultHands = [];
    int total = 0;
    for (int h = 0; h < handsCount; h++) {
      final d = _Deck();
      // held 제거
      for (int i = 0; i < 5; i++) {
        if (holds[i]) d.remove(baseHand[i]);
      }
      // 결과 손 완성
      final out = List<PlayingCard>.from(baseHand);
      for (int i = 0; i < 5; i++) {
        if (!holds[i]) out[i] = d.draw();
      }
      resultHands.add(out);
      final cat = _evaluate(out);
      total += _payout(cat, betPerHand);
    }

    // 토너먼트면 점수 적립, 일반 모드면 크레딧 적립
    if (tournamentRunning) {
      tourScore += total;
      handsPlayed++;
      lastMessage = total > 0 ? 'Win +$total  |  Score: $tourScore' : 'Miss  |  Score: $tourScore';
    } else {
      credits += total;
      lastMessage = total > 0 ? '총 당첨 +$total' : '꽝';
    }

    lastWinTotal = total;
    inDealPhase = true;
    HapticFeedback.selectionClick();
    setState(() {});
  }

  // ─────────────────────────────────────────────────
  // 오토홀드(간단 전략)
  // ─────────────────────────────────────────────────
  List<bool> _autoHold(List<PlayingCard> h) {
    final holds = List<bool>.filled(5, false);

    HandCat cat = _evaluate(h);
    bool isPat = {
      HandCat.straight,
      HandCat.flush,
      HandCat.fullHouse,
      HandCat.straightFlush,
      HandCat.royalFlush,
      HandCat.fourKind,
    }.contains(cat);

    if (isPat) {
      for (int i = 0; i < 5; i++) holds[i] = true;
      return holds;
    }

    // 카운트/그룹
    Map<int, List<int>> idxByRank = {};
    for (int i = 0; i < 5; i++) {
      idxByRank.putIfAbsent(h[i].rank, () => []).add(i);
    }
    // J 이상 페어
    List<int> highPair = [];
    for (final e in idxByRank.entries) {
      if (e.value.length == 2 && e.key >= 11) highPair = e.value;
    }
    if (highPair.isNotEmpty) {
      for (final i in highPair) holds[i] = true;
      return holds;
    }
    // 트리플/쿼드
    for (final e in idxByRank.entries) {
      if (e.value.length >= 3) {
        for (final i in e.value) holds[i] = true;
      }
    }
    if (holds.contains(true)) return holds;

    // 로열 후보
    List<int> royalRanks = [10, 11, 12, 13, 14];
    for (final s in Suit.values) {
      final idxs = <int>[];
      for (int i = 0; i < 5; i++) {
        if (h[i].suit == s && royalRanks.contains(h[i].rank)) idxs.add(i);
      }
      if (idxs.length >= 4) {
        for (final i in idxs) holds[i] = true;
        return holds;
      }
    }
    // 3 to Royal
    for (final s in Suit.values) {
      final idxs = <int>[];
      for (int i = 0; i < 5; i++) {
        if (h[i].suit == s && royalRanks.contains(h[i].rank)) idxs.add(i);
      }
      if (idxs.length == 3) {
        for (final i in idxs) holds[i] = true;
        return holds;
      }
    }

    // 4 to Flush
    for (final s in Suit.values) {
      final idxs = <int>[];
      for (int i = 0; i < 5; i++) if (h[i].suit == s) idxs.add(i);
      if (idxs.length == 4) {
        for (final i in idxs) holds[i] = true;
        return holds;
      }
    }

    // 같은 무늬의 높은 두 장 (J 이상)
    for (final s in Suit.values) {
      final idxs = <int>[];
      for (int i = 0; i < 5; i++) {
        if (h[i].suit == s && h[i].rank >= 11) idxs.add(i);
      }
      if (idxs.length >= 2) {
        for (final i in idxs.take(2)) holds[i] = true;
        return holds;
      }
    }

    // 높은 한 장
    int hi = -1, hiRank = -1;
    for (int i = 0; i < 5; i++) {
      if (h[i].rank >= 11 && h[i].rank > hiRank) {
        hiRank = h[i].rank;
        hi = i;
      }
    }
    if (hi >= 0) {
      holds[hi] = true;
    }
    return holds;
  }

  // ─────────────────────────────────────────────────
  // 더블업(도박) — 토너먼트에서는 금지
  // ─────────────────────────────────────────────────
  void _startDouble() {
    if (tournamentRunning) return; // 금지
    if (lastWinTotal <= 0 || inDouble) return;
    inDouble = true;
    pickedCard = null;

    final d = _Deck();
    dealerCard = d.draw();
    doubleChoices = List.generate(4, (_) => d.draw());
    doubleMessage = '딜러보다 높은 카드를 고르세요.';
    setState(() {});
  }

  void _pickDouble(int idx) {
    if (!inDouble || pickedCard != null) return;
    pickedCard = doubleChoices[idx];

    final stake = lastWinTotal;
    if (pickedCard!.rank > dealerCard!.rank) {
      credits += stake;
      lastWinTotal *= 2;
      doubleMessage = '성공! 스테이크 x2 (${lastWinTotal}). 계속하시겠습니까?';
    } else if (pickedCard!.rank < dealerCard!.rank) {
      credits -= stake;
      lastWinTotal = 0;
      doubleMessage = '실패… 당첨액을 잃었습니다.';
    } else {
      // 무승부: 다시 시도(스테이크 변동 없음)
      doubleMessage = '무승부! 다시 시도하세요.';
    }
    setState(() {});
  }

  void _doubleAgainOrRedeal() {
    if (lastWinTotal <= 0) {
      inDouble = false;
      dealerCard = null;
      doubleChoices = [];
      pickedCard = null;
      setState(() {});
      return;
    }
    pickedCard = null;
    final d = _Deck();
    dealerCard = d.draw();
    doubleChoices = List.generate(4, (_) => d.draw());
    doubleMessage = '딜러보다 높은 카드를 고르세요.';
    setState(() {});
  }

  void _doubleTakeWin() {
    inDouble = false;
    dealerCard = null;
    doubleChoices = [];
    pickedCard = null;
    doubleMessage = '수령 완료';
    lastMessage = '도박 종료. 최종 당첨: $lastWinTotal';
    setState(() {});
  }

  // ─────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isTour = tournamentMode;
    final isRunning = tournamentRunning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Poker+'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // 토너먼트 모드 스위치
          Row(
            children: [
              const Text('Tourney', style: TextStyle(fontWeight: FontWeight.w700)),
              Switch.adaptive(
                value: isTour,
                onChanged: (v) {
                  if (isRunning) return; // 진행중엔 토글 불가
                  setState(() => tournamentMode = v);
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
      backgroundColor: Colors.grey[100],
      body: Stack(
        children: [
          Column(
            children: [
              // 상단 HUD
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 8, offset: const Offset(0, 2))
                  ],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (!isRunning) _pill(Icons.monetization_on, 'Credits: $credits'),
                      if (isRunning) _pill(Icons.emoji_events, 'Score: $tourScore'),
                      const SizedBox(width: 8),
                      _pill(Icons.stacked_line_chart, 'Bet/Hand: ${isTour ? 5 : betPerHand}'),
                      const SizedBox(width: 8),
                      _pill(Icons.view_module, 'Hands: ${isTour ? 1 : handsCount}'),
                      if (isRunning) ...[
                        const SizedBox(width: 8),
                        _pill(Icons.timer, _formatMMSS(remainingSeconds)),
                      ],
                      const SizedBox(width: 12),
                      // 메시지는 길면 말줄임
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 0, maxWidth: 600),
                        child: Text(
                          lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 베팅/모드 컨트롤
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    // 오토홀드
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Auto-Hold', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 6),
                        Switch.adaptive(
                          value: autoHold,
                          onChanged: (!isRunning && inDealPhase) ? (v) => setState(() => autoHold = v) : null,
                        ),
                      ],
                    ),
                    // 토너먼트면 비활성화
                    Opacity(
                      opacity: isTour ? 0.4 : 1,
                      child: IgnorePointer(
                        ignoring: isTour,
                        child: _handsPicker(),
                      ),
                    ),
                    Opacity(
                      opacity: isTour ? 0.4 : 1,
                      child: IgnorePointer(
                        ignoring: isTour,
                        child: _betStepper(),
                      ),
                    ),
                  ],
                ),
              ),

              // 카드 영역
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: inDealPhase ? _resultHandsView() : _holdView(), // 딜 전: 결과 / 딜 후: 홀드 선택
                ),
              ),

              // 페이테이블 + 버튼들
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    _paytableCard(),
                    const SizedBox(height: 12),
                    // 버튼 영역 — Wrap
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        // DEAL / DRAW
                        _actionBtn(
                          label: inDealPhase ? 'DEAL' : 'DRAW',
                          onTap: () {
                            if (isTour && !isRunning) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('토너먼트를 시작하세요. (Start Tourney)')),
                              );
                              return;
                            }
                            return inDealPhase ? _deal() : _draw();
                          },
                          primary: true,
                        ),
                        // MAX BET (토너먼트면 Max 고정이므로 비활성화)
                        _actionBtn(label: 'MAX BET', onTap: (!isTour && inDealPhase) ? _maxBet : null),
                        // DOUBLE (토너먼트 금지)
                        if (inDealPhase && lastWinTotal > 0 && !isTour)
                          _actionBtn(
                            label: 'DOUBLE',
                            onTap: _startDouble,
                          ),
                        _actionBtn(label: 'RESET', onTap: () => _resetRound(keepCredits: false)),
                        // 토너먼트 시작/종료
                        if (isTour)
                          _actionBtn(
                            label: isRunning ? 'STOP TOURNEY' : 'START TOURNEY',
                            onTap: isRunning ? _endTournament : _startTournament,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 더블업 오버레이
          if (inDouble) Positioned.fill(child: _doubleOverlay()),
        ],
      ),
    );
  }

  // ─ UI helpers ─
  Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _actionBtn({required String label, VoidCallback? onTap, bool primary = false}) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        backgroundColor: primary ? Colors.black : Colors.white,
        foregroundColor: primary ? Colors.white : Colors.black,
        side: BorderSide(color: Colors.black.withOpacity(.15)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: primary ? 2 : 0,
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  Widget _betStepper() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: inDealPhase && betPerHand > 1 ? () => setState(() => betPerHand--) : null,
            icon: const Icon(Icons.remove),
          ),
          Text('BET $betPerHand', style: const TextStyle(fontWeight: FontWeight.w900)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: inDealPhase && betPerHand < 5 ? () => setState(() => betPerHand++) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _handsPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButton<int>(
        value: handsCount,
        underline: const SizedBox.shrink(),
        items: _handsOptions
            .map((e) => DropdownMenuItem(
            value: e, child: Text('$e Hands', style: const TextStyle(fontWeight: FontWeight.w800))))
            .toList(),
        onChanged: inDealPhase ? (v) => setState(() => handsCount = v ?? 1) : null,
      ),
    );
  }

  Widget _paytableCard() {
    final titles = [
      'Royal Flush',
      'Straight Flush',
      'Four of a Kind',
      'Full House',
      'Flush',
      'Straight',
      'Three of a Kind',
      'Two Pair',
      'Jacks or Better',
    ];
    final pays = [
      [250, 500, 750, 1000, 4000],
      [50, 100, 150, 200, 250],
      [25, 50, 75, 100, 125],
      [9, 18, 27, 36, 45],
      [6, 12, 18, 24, 30],
      [4, 8, 12, 16, 20],
      [3, 6, 9, 12, 15],
      [2, 4, 6, 8, 10],
      [1, 2, 3, 4, 5],
    ];

    Widget _cellText(String s, {bool bold = true}) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Text(
          s,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
        ),
      );
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, cons) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: cons.maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pay Table (per hand)', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Table(
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(),
                        2: FlexColumnWidth(),
                        3: FlexColumnWidth(),
                        4: FlexColumnWidth(),
                        5: FlexColumnWidth(),
                      },
                      children: [
                        TableRow(children: [
                          const SizedBox.shrink(),
                          for (int b = 1; b <= 5; b++)
                            Center(child: _cellText('$b', bold: true)),
                        ]),
                        for (int r = 0; r < titles.length; r++)
                          TableRow(children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    titles[r],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ),
                            for (int i = 0; i < 5; i++)
                              Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '${pays[r][i]}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: betPerHand == i + 1 ? Colors.black : Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                          ]),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // 홀드 선택(딜 이후)
  Widget _holdView() {
    return LayoutBuilder(
      builder: (_, cons) {
        final cardWidth = min(120.0, (cons.maxWidth - 32) / 5);
        final cardHeight = cardWidth * 1.45;
        return Center(
          child: SizedBox(
            width: min(cons.maxWidth, cardWidth * 5 + 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(5, (i) {
                final c = baseHand[i];
                final held = holds[i];
                return _cardView(
                  card: c,
                  held: held,
                  width: cardWidth,
                  height: cardHeight,
                  onTap: () => setState(() => holds[i] = !held),
                  enabled: true,
                );
              }),
            ),
          ),
        );
      },
    );
  }

  // 결과(드로우 이후 / 또는 딜 전 직전 라운드 결과 표시)
  Widget _resultHandsView() {
    if (resultHands.isEmpty) {
      return const Center(child: Text('딜(DEAL)하여 게임을 시작하세요.'));
    }
    return LayoutBuilder(
      builder: (_, cons) {
        final rows = resultHands.length;
        final maxCardWidth = (cons.maxWidth - 32) / 5;
        final rowHeight = min(160.0, maxCardWidth * 1.45 + 24);
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          itemCount: rows,
          itemBuilder: (_, r) {
            final hand = resultHands[r];
            final cat = _evaluate(hand);
            final win = _payout(cat, betPerHand);
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              height: rowHeight,
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(5, (i) {
                        final cw = min(110.0, maxCardWidth);
                        final ch = cw * 1.45;
                        return _cardView(
                          card: hand[i],
                          held: false,
                          width: cw,
                          height: ch,
                          onTap: () {},
                          enabled: false,
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_handLabel(cat), style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text('+$win', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _cardView({
    required PlayingCard card,
    required bool held,
    required double width,
    required double height,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: held ? Colors.amber : Colors.black12, width: held ? 2 : 1),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: _frontFace(card, held),
      ),
    );
  }

  Widget _frontFace(PlayingCard c, bool held) {
    final suitChar = switch (c.suit) {
      Suit.heart => '♥',
      Suit.diamond => '♦',
      Suit.spade => '♠',
      Suit.club => '♣',
    };
    final suitColor = (c.suit == Suit.heart || c.suit == Suit.diamond) ? const Color(0xFFe53935) : Colors.black;

    String rankStr;
    switch (c.rank) {
      case 11:
        rankStr = 'J';
        break;
      case 12:
        rankStr = 'Q';
        break;
      case 13:
        rankStr = 'K';
        break;
      case 14:
        rankStr = 'A';
        break;
      default:
        rankStr = '${c.rank}';
    }

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rankStr, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: suitColor)),
              Text(suitChar, style: TextStyle(fontSize: 20, color: suitColor)),
              const Spacer(),
              Align(
                alignment: Alignment.bottomRight,
                child: Transform.rotate(
                  angle: pi,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rankStr, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: suitColor)),
                      Text(suitChar, style: TextStyle(fontSize: 20, color: suitColor)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (held)
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(.95),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber[800]!),
              ),
              child: const Center(child: Text('HOLD', style: TextStyle(fontWeight: FontWeight.w900))),
            ),
          ),
      ],
    );
  }

  void _maxBet() {
    if (!inDealPhase) return;
    setState(() => betPerHand = 5);
    _deal();
  }

  // ─ 더블업 오버레이 ─
  Widget _doubleOverlay() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: Colors.black.withOpacity(.25),
      child: Center(
        child: Container(
          width: min(MediaQuery.of(context).size.width * 0.9, 520),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.2), blurRadius: 18)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Double Up', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text('Stake: $lastWinTotal', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              // 딜러 카드 + 선택 카드들
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _doubleCard(dealerCard, revealed: true),
                    const SizedBox(width: 10),
                    Text('vs', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 10),
                    Wrap(
                      spacing: 8,
                      children: List.generate(4, (i) {
                        final selected = pickedCard != null && identical(pickedCard, doubleChoices[i]);
                        final reveal = pickedCard != null;
                        return GestureDetector(
                          onTap: pickedCard == null ? () => _pickDouble(i) : null,
                          child: _doubleCard(doubleChoices[i], revealed: reveal, highlight: selected),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(doubleMessage, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (pickedCard != null && lastWinTotal > 0)
                    _actionBtn(label: 'Double Again', onTap: _doubleAgainOrRedeal, primary: true),
                  _actionBtn(label: 'Take Win', onTap: _doubleTakeWin),
                  if (pickedCard != null && lastWinTotal <= 0) _actionBtn(label: 'Close', onTap: _doubleTakeWin),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _doubleCard(PlayingCard? c, {required bool revealed, bool highlight = false}) {
    final w = 70.0, h = 100.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: highlight ? Colors.amber : Colors.black12, width: highlight ? 2 : 1),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.08), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: revealed ? _frontFace(c!, false) : _backFace(),
    );
  }

  Widget _backFace() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.black87, Colors.black54]),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(child: Icon(Icons.casino, color: Colors.white70, size: 28)),
    );
  }
}
