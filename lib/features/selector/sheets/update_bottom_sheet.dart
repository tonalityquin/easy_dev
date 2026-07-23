import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';

class UpdateBottomSheet extends StatelessWidget {
  const UpdateBottomSheet({super.key, this.entries});

  final List<UpdateEntry>? entries;

  static final List<UpdateEntry> defaultEntries = <UpdateEntry>[
    const UpdateEntry(
      version: 'v0.1.4',
      highlights: <String>[
        'UI/UX 디자인 및 애니메이션 개선',
        '상기의 업데이트로 다크모드 지원은 일시적으로 제한됩니다.',
        '본사 대시보드 일부 기능 추가 및 개선',
        '일부 과도하게 메모리 사용을 유발하는 기능 개선',
        '일부 본사 관련 기능 사전 UI 업데이트',
      ],
    ),
    const UpdateEntry(
      version: 'v0.1.3',
      highlights: <String>[
        '휴무, 휴게 상세 옵션 설정 기능 추가',
        '정기(월) 주차 관리 기능의 접근성 개선',
        '정기(월) 주차 관리의 상태 메모 시 한글로 작성이 되지 않던 버그 수정',
        '보조 페이지의 관리자 화면 개선',
        '대시보드 및 본사 페이지와 시트 UI 개선',
        '출차 완료 시트의 정산 탭에서 촬영자 정보와 날짜가 뜨지 않던 오류 수정',
        '차량 번호판 검색 시, 일부 기기에서 버튼과 핸드폰 홈 영역이 겹치던 이슈 수정',
      ],
    ),
    const UpdateEntry(
      version: 'v0.1.2',
      highlights: <String>[
        '업무 별 통계 시각화 기능 개선',
        '차량 현황 출력 화면 개선',
        '주차 도면으로 자동 전환 분기점 개선',
        '로그 저장 확장값을 json에서 csv로 변경',
        '본사 메모장 기능을 문서로 확대 개편',
        '출*퇴근 알림 등 로직 개선',
        '앱 첫 설치 후, 권한 설정 화면 다음 순서에 약관 관련 동의 화면 추가',
      ],
    ),
    const UpdateEntry(
      version: 'v0.1.1',
      highlights: <String>[
        '개인정보 보안용 스키마 추가',
        '과거 업무 차량 별 조회 기능 추가',
        '차종 및 제조사 데이터 삽입 기능 추가',
        '차량 상태가 영어로 출력되던 문제 수정',
        '무전기 기능 추가',
      ],
    ),
    const UpdateEntry(
      version: 'v0.1.0',
      highlights: <String>[
        '어플리케이션 릴리즈',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final list = entries ?? defaultEntries;

    return PromptSheetScaffold(
      title: '업데이트',
      icon: Icons.new_releases_rounded,
      onClose: () => Navigator.of(context).pop(),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        itemCount: list.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final delay = Duration(
            milliseconds: math.min(index * 45, 140),
          );
          return PromptAnimatedReveal(
            delay: delay,
            child: _UpdateTile(entry: list[index]),
          );
        },
      ),
    );
  }
}

class UpdateEntry {
  const UpdateEntry({
    required this.version,
    required this.highlights,
  });

  final String version;
  final List<String> highlights;
}

class _UpdateTile extends StatelessWidget {
  const _UpdateTile({required this.entry});

  final UpdateEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        border: Border.all(color: tokens.borderStrong.withOpacity(0.58)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: tokens.accentContainer,
                borderRadius: BorderRadius.circular(PromptUiShapes.pill),
                border: Border.all(color: tokens.accent.withOpacity(0.30)),
              ),
              child: Text(
                entry.version,
                style: text.labelMedium?.copyWith(
                  color: tokens.onAccentContainer,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...entry.highlights.map(
              (highlight) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: tokens.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        highlight,
                        style: text.bodyMedium?.copyWith(
                          color: tokens.textPrimary,
                          height: 1.4,
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
