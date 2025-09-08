import 'package:flutter/material.dart';

class WsopHoldemRulesPage extends StatelessWidget {
  const WsopHoldemRulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('WSOP Hold’em 룰북'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _heroCard(
              context,
              title: '초간단 시작 가이드 (3분 요약)',
              bullets: const [
                '① 각자 2장의 홀카드, 커뮤니티카드 5장으로(플롭3 • 턴1 • 리버1) 베스트 5카드 조합을 만든다.',
                '② 각 스트리트마다 플레이어가 순서대로 액션: 폴드 / 체크·콜 / 레이즈·올인.',
                '③ 쇼다운에서 최고 조합이 팟을 획득 — 중간에 전원이 폴드하면 남은 플레이어가 승리.',
                '④ 블라인드: SB/BB는 강제 베팅. (이 데모는 앤티 없음)',
                '⑤ 최소 레이즈 규칙: 직전 “증가량(갭)” 이상으로만 다시 레이즈 가능(올인으로 갭이 부족하면 레이즈 재개 불가).',
                '⑥ 이 데모는 캐시게임 스타일로 동작(토너먼트 레벨/리엔트리 없음).',
              ],
            ),

            const SizedBox(height: 12),
            _sectionTitle('게임 흐름'),

            _expansion(
              title: '1) 프리플랍',
              children: const [
                _P('딜러가 각 플레이어에게 홀카드 2장을 지급.'),
                _P('SB/BB가 먼저 자동으로 팟에 들어간다(강제 베팅, 앤티 없음).'),
                _P('액션은 빅블라인드 다음 자리(UTG)부터 시작하여 시계방향으로 진행.'),
              ],
            ),
            _expansion(
              title: '2) 플롭 (커뮤니티 3장)',
              children: const [
                _P('딜러가 한 장을 버리고(Burn) 3장을 오픈.'),
                _P('포스트플랍은 딜러 버튼 왼쪽(스몰블라인드 자리)부터 액션 재개.'),
              ],
            ),
            _expansion(
              title: '3) 턴 / 4) 리버',
              children: const [
                _P('각 스트리트마다 한 장 버리고 한 장을 오픈, 액션 순서는 동일.'),
              ],
            ),
            _expansion(
              title: '5) 쇼다운',
              children: const [
                _P('폴드하지 않은 플레이어는 자신의 2장 + 보드 5장 중 베스트 5장을 비교.'),
                _P('동률이면 팟을 균등 분할(남는 1칩은 버튼 왼쪽부터 순서대로 지급).'),
              ],
            ),

            const SizedBox(height: 12),
            _sectionTitle('핸드 랭킹 (강한 순)'),

            _card(
              children: const [
                _Rank('1. 스트레이트 플러시', '같은 무늬로 연속된 5장 (예: A♥ K♥ Q♥ J♥ T♥) — 로열 포함'),
                _Rank('2. 포카드(쿼드)', '같은 숫자 4장 + 다른 카드 1장 (예: 9♣ 9♥ 9♠ 9♦ + Kx)'),
                _Rank('3. 풀 하우스', '트리플 + 페어 (예: K K K + 7 7)'),
                _Rank('4. 플러시', '같은 무늬 5장, 숫자 연속 아님 (예: A♣ J♣ 9♣ 6♣ 2♣)'),
                _Rank('5. 스트레이트', '연속된 5장(무늬 무관). A-2-3-4-5(휠)는 5가 탑'),
                _Rank('6. 트리플(트립스)', '같은 숫자 3장 + 키커 2장'),
                _Rank('7. 투페어', '페어 2개 + 키커 1장 (예: Q Q + 8 8 + Ax)'),
                _Rank('8. 원페어', '같은 숫자 2장 + 키커 3장'),
                _Rank('9. 하이카드', '위 조합 없음 — 가장 큰 카드부터 비교'),
                _Psmall('※ 타이브레이크: 같은 조합이면 주요 랭크 → 남는 카드(키커) 순으로 비교. '
                    '휠 스트레이트(A-5)는 5가 최고로 계산.'),
              ],
            ),

            const SizedBox(height: 12),
            _sectionTitle('베팅 규칙 & 용어'),

            _expansion(
              title: '액션 종류',
              children: const [
                _P('폴드: 이번 핸드 포기.'),
                _P('체크: 현재 콜할 금액(투콜)이 0일 때만 가능, 턴 넘기기.'),
                _P('콜: 현재 최고 베팅까지 맞추기.'),
                _P('레이즈: 현재 최고 베팅보다 더 크게 베팅. 올인은 스택 전부를 걸기.'),
              ],
            ),
            _expansion(
              title: '최소 레이즈(갭) 규칙 – 중요!',
              children: const [
                _P('직전 “증가량(갭)” 이상으로만 다시 레이즈 가능.'),
                _P('예) 누군가 200→500으로 만들었다면 증가량은 +300. 다음 레이즈는 최소 +300 이상 필요.'),
                _P('올인으로 갭이 부족해도 “리오픈”되지 않음 → 그 스트리트에서는 추가 레이즈 불가. '
                    '새 스트리트가 시작되면 갭이 리셋됨.'),
              ],
            ),
            _expansion(
              title: '블라인드(이 데모 기준)',
              children: const [
                _P('SB/BB 강제 베팅. 앤티는 사용하지 않음.'),
                _P('각 스트리트 시작 시 최소 레이즈 기준은 BB 이상(또는 직전 증가량 이상)으로 적용.'),
              ],
            ),

            const SizedBox(height: 12),
            _sectionTitle('올인 & 사이드팟'),

            _card(
              children: const [
                _P('누군가 올인하면, 각자 더 낼 수 있는 한도만큼 팟이 계층(메인/사이드)으로 분리된다.'),
                _P('예) A 1,000 / B 600 올인 / C 1,000 콜:'),
                _Bul('메인팟: 각자 600씩 × 참여자 수(3) = 1,800 (A,B,C 자격)'),
                _Bul('사이드팟: A와 C가 추가로 낸 400씩 × 2 = 800 (A,C만 자격)'),
                _P('쇼다운 시 각 팟마다 해당 자격자 중 최고 핸드가 그 팟만 가져간다.'),
                _P('홀칩(나누고 남은 1칩)은 버튼의 왼쪽부터 순서대로 지급.'),
              ],
            ),

            const SizedBox(height: 12),
            _sectionTitle('이 데모의 모드'),

            _card(
              children: const [
                _P('캐시게임 스타일로 동작(레벨 타이머/블라인드 상승/리엔트리 없음).'),
                _P('스택이 0이 되면 해당 플레이어는 더 이상 참여하지 않음(테이블 리셋 시 초기화).'),
                _P('앱의 DEAL 버튼으로 새 핸드를 시작.'),
              ],
            ),

            const SizedBox(height: 12),
            _sectionTitle('UI 도움말'),

            _card(
              children: const [
                _Bul('보드(커뮤니티 카드): 게임판 하단 중앙 줄에 표시.'),
                _Bul('원형 좌석 카드: 이름/스택/버튼(D)/베팅/상태(FOLDED/ALL-IN).'),
                _Bul('하단 패널: 현재 스트리트, 팟, 투콜 금액, 최소 레이즈, 액션 버튼(FOLD/CHECK·CALL/RAISE).'),
                _Bul('앱바: 테이블 초기화(Reset Table).'),
              ],
            ),

            const SizedBox(height: 24),
            Center(
              child: Text(
                '행운을 빕니다! 🍀',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: cs.primary,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ───────────────────────── Helper UI ─────────────────────────

Widget _sectionTitle(String s) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(s, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
);

Widget _card({required List<Widget> children}) => Card(
  margin: const EdgeInsets.only(bottom: 8),
  child: Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  ),
);

Widget _heroCard(BuildContext context, {required String title, required List<String> bullets}) {
  return Card(
    color: Colors.amber[50],
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          for (final b in bullets) _Bul(b),
        ],
      ),
    ),
  );
}

Widget _expansion({required String title, required List<Widget> children}) {
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: Theme(
      data: ThemeData().copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: children,
      ),
    ),
  );
}

class _P extends StatelessWidget {
  final String text;
  const _P(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: const TextStyle(height: 1.25)),
    );
  }
}

class _Psmall extends StatelessWidget {
  final String text;
  const _Psmall(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.25),
      ),
    );
  }
}

class _Bul extends StatelessWidget {
  final String text;
  const _Bul(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(fontWeight: FontWeight.w900)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _Rank extends StatelessWidget {
  final String title;
  final String desc;
  const _Rank(this.title, this.desc);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(desc),
        ],
      ),
    );
  }
}
