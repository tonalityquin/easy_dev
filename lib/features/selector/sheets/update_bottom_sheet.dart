import 'package:flutter/material.dart';

@immutable
class _UpdateSheetTokens {
  const _UpdateSheetTokens({
    required this.sheetBg,
    required this.handle,
    required this.divider,
    required this.headerIcon,
    required this.tileBg,
    required this.tileBorder,
    required this.badgeBg,
    required this.badgeFg,
    required this.bulletFg,
  });

  final Color sheetBg;
  final Color handle;
  final Color divider;

  final Color headerIcon;

  final Color tileBg;
  final Color tileBorder;

  final Color badgeBg;
  final Color badgeFg;

  final Color bulletFg;

  factory _UpdateSheetTokens.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _UpdateSheetTokens(
      sheetBg: cs.surface,
      handle: cs.onSurface.withOpacity(0.20),
      divider: cs.outlineVariant.withOpacity(0.50),
      headerIcon: cs.primary,
      tileBg: cs.surfaceContainerHighest.withOpacity(.60),
      tileBorder: cs.outlineVariant.withOpacity(.40),
      badgeBg: cs.primary.withOpacity(.12),
      badgeFg: cs.primary,
      bulletFg: cs.onSurface,
    );
  }
}

class UpdateBottomSheet extends StatelessWidget {
  const UpdateBottomSheet({super.key, this.entries});

  final List<UpdateEntry>? entries;

  static final List<UpdateEntry> defaultEntries = [
    UpdateEntry(
      version: 'v0.1.2',
      highlights: [
        '업무 별 통계 시각화 기능 개선',
        '차량 현황 출력 화면 개선',
        '주차 도면으로 자동 전환 분기점 개선',
        '로그 저장 확장값을 json에서 csv로 변경',
        '본사 메모장 기능을 문서로 확대 개편',
        '출*퇴근 알림 등 로직 개선',
        '앱 첫 설치 후, 권한 설정 화면 다음 순서에 약관 관련 동의 화면 추가'
      ],
    ),
    UpdateEntry(
      version: 'v0.1.1',
      highlights: [
        '개인정보 보안용 스키마 추가',
        '과거 업무 차량 별 조회 기능 추가',
        '차종 및 제조사 데이터 삽입 기능 추가',
        '차량 상태가 영어로 출력되던 문제 수정',
        '무전기 기능 추가',
      ],
    ),
    UpdateEntry(
      version: 'v0.1.0',
      highlights: [
        '어플리케이션 릴리즈',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = _UpdateSheetTokens.of(context);
    final text = Theme.of(context).textTheme;

    final list = entries ?? defaultEntries;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: t.sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.handle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.new_releases_rounded, color: t.headerIcon),
                  const SizedBox(width: 8),
                  Text(
                    '업데이트',
                    style:
                        text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: t.divider),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 24, color: t.divider.withOpacity(.6)),
                itemBuilder: (context, i) => _UpdateTile(entry: list[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UpdateEntry {
  final String version;
  final List<String> highlights;

  const UpdateEntry({
    required this.version,
    required this.highlights,
  });
}

class _UpdateTile extends StatelessWidget {
  const _UpdateTile({required this.entry});

  final UpdateEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = _UpdateSheetTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: t.tileBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.tileBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: t.badgeBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.version,
                    style: text.labelMedium?.copyWith(
                      color: t.badgeFg,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...entry.highlights.map(
              (h) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ',
                        style: text.bodyMedium?.copyWith(color: t.bulletFg)),
                    Expanded(
                      child: Text(
                        h,
                        style: text.bodyMedium?.copyWith(
                          color: t.bulletFg,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
