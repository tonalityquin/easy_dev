import 'package:flutter/material.dart';

/// Pelican Sorter 플레이 방법 (BottomSheet + Page 공용 콘텐츠)
///
/// 사용법 예시)
/// 1) 바텀시트로 열기:
///    showPelicanSorterHowToSheet(context);
///
/// 2) 독립 페이지로 push:
///    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PelicanSorterHowToPage()));
///
/// 3) 게임 화면 AppBar에 버튼 추가 예시:
///    IconButton(
///      tooltip: '플레이 방법',
///      icon: const Icon(Icons.help_center_outlined),
///      onPressed: () => showPelicanSorterHowToSheet(context),
///    ),
Future<void> showPelicanSorterHowToSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PelicanSorterHowToSheet(),
  );
}

/// 독립 페이지 버전
class PelicanSorterHowToPage extends StatelessWidget {
  const PelicanSorterHowToPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '플레이 방법',
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: _HowToContent(cs: cs, text: text),
        ),
      ),
    );
  }
}

/// 바텀시트 버전
class _PelicanSorterHowToSheet extends StatelessWidget {
  const _PelicanSorterHowToSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // drag handle
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.help_center_outlined, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    '펠리컨 소터 · 플레이 방법',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(child: _HowToContent(cs: cs, text: text)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 실제 콘텐츠 위젯 (시트/페이지 공용)
class _HowToContent extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme text;

  const _HowToContent({required this.cs, required this.text});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, cons) {
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Banner(cs: cs, text: text),
              const SizedBox(height: 12),
              _Section(
                title: '게임 목표',
                icon: Icons.flag_circle_rounded,
                children: const [
                  '4×4 카드 중 “타깃 카드”를 찾아내면 승리합니다.',
                  '초기에 공개되는 힌트 + 행동(AP)으로 얻는 추가 정보로 후보를 좁혀가세요.',
                ],
              ),
              _Section(
                title: '행동(AP) 시스템',
                icon: Icons.flash_on,
                trailing: _Badge(text: '턴마다 리필'),
                children: const [
                  '턴 시작 시 AP가 채워집니다. 난이도에 따라 AP 양이 달라집니다.',
                  'AP 1: 카드 “질의” — 선택 카드가 현재 힌트들과 모순이면 즉시 배제 표시.',
                  'AP 2: “새 힌트” 공개 — 덱에서 힌트를 1장 더 엽니다.',
                  'AP 2: “스캔” — 특정 행/열에 대해 (색/목적지/중량/우선순위) 개수를 알려줍니다.',
                  'AP 0: “정답 선언” — 남은 AP와 힌트 사용량에 따라 최종 점수에 반영됩니다.',
                ],
              ),
              _Section(
                title: '조작 방법',
                icon: Icons.touch_app_rounded,
                children: const [
                  '카드를 탭하면 액션 시트가 열립니다.',
                  '“질의(1AP)”로 배제 여부를 확인하고, 확신이 들면 “정답 선언”을 사용하세요.',
                  '아래 패널의 버튼으로 “새 힌트(2AP)”, “스캔(2AP)”, “다음 턴”을 사용할 수 있습니다.',
                ],
              ),
              _Section(
                title: '힌트 종류 예시',
                icon: Icons.tips_and_updates,
                children: const [
                  '속성 일치/불일치: “포장색은 빨강이다 / 파랑이 아니다”',
                  '위치: “2행에 있다 / 4열에 없다 / 모서리 / 중앙 / 테두리”',
                  '개수: “타깃과 같은 색은 총 3장”',
                  '우선순위 성질: “우선순위 번호는 짝수”',
                ],
              ),
              _Section(
                title: '승패/점수',
                icon: Icons.emoji_events_rounded,
                children: const [
                  '정답 선언에 성공하면 승리! 실패하면 즉시 게임 종료입니다.',
                  '점수 = 기본점수 – (소요 턴 × 5) – (추가 힌트 × 3) + 남은 AP, 난이도 보정 적용.',
                ],
              ),
              _Section(
                title: '전략 팁',
                icon: Icons.psychology,
                children: const [
                  '개수/위치 힌트는 후보군을 빠르게 절반 수준으로 잘라낼 수 있습니다.',
                  '질의(1AP)로 모순 카드를 배제해 “시각적 정리”를 하면 의사결정이 빨라집니다.',
                  '후보 카드 수가 1~2장일 때 “정답 선언” 타이밍을 노리세요.',
                ],
              ),
              const SizedBox(height: 12),
              _QuickLegend(cs: cs, text: text),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  '즐거운 수사 되세요! 🕵️‍♀️🕵️‍♂️',
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// 상단 배너
class _Banner extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme text;
  const _Banner({required this.cs, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.75),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.onPrimaryContainer.withOpacity(.08),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.inventory_2_rounded, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '밀수 패키지의 정체를 추론하세요.\n힌트를 열고, 스캔하고, 모순 카드를 배제해 타깃을 찾아내는 게임!',
              style: text.bodyMedium?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 섹션 박스
class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;
  final List<String> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: cs.primary,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 8),
            for (final line in children)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(
                      child: Text(
                        line,
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 라벨/배지
class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

/// 빠른 전설(아이콘 의미)
class _QuickLegend extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme text;
  const _QuickLegend({required this.cs, required this.text});

  @override
  Widget build(BuildContext context) {
    final items = const [
      (_Legend(Icons.tips_and_updates, '새 힌트(2AP)')),
      (_Legend(Icons.search, '스캔(2AP)')),
      (_Legend(Icons.help_outline, '질의(1AP)')),
      (_Legend(Icons.check, '정답 선언')),
      (_Legend(Icons.skip_next, '다음 턴')),
      (_Legend(Icons.flash_on, '남은 AP')),
    ];

    return Card(
      color: Colors.white,
      elevation: 1,
      surfaceTintColor: cs.primary,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.legend_toggle_rounded, color: cs.primary),
              const SizedBox(width: 8),
              Text('아이콘 빠른 전설', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final it in items)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.04),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(it.icon, size: 18),
                        const SizedBox(width: 6),
                        Text(it.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend {
  final IconData icon;
  final String label;
  const _Legend(this.icon, this.label);
}
