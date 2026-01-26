import 'package:flutter/material.dart';

class UpdateBottomSheet extends StatelessWidget {
  const UpdateBottomSheet({super.key, this.entries});

  final List<UpdateEntry>? entries;

  static final List<UpdateEntry> defaultEntries = [
    UpdateEntry(
      version: 'v1.1.1',
      highlights: [
        'API 에러 로그 화면 추가',
        '출퇴근, 휴게시간 로직 개선',
        '업무 종료 보고 로직 개선',
        '자동 퇴근 로직 추가',
        '테이블 시스템 개편',
        '지역 별 주의사항 카드 영역 개선',
        '업무 중 앱 최소화 시 플로팅 버블 기능 추가',
        '약식 로그인 모드 추가',
        '지역 별 근무자 출퇴근 현황 기능 추가',
        '지역 별 통계 카드 기능 개선',
        '사진 전송 기능 추가',
      ],
    ),
    UpdateEntry(
      version: 'v1.0.0+10',
      highlights: [
        '구글 계정 인증 추가',
        '오프라인 모드 튜토리얼 개선',
        '본사 카드 내 1차 앱 사용 설명서 삽입',
        '직원용 플로팅 버블 및 Gmail 발신 기능 개선',
        '본사용 플로팅 버블 개선 및 본사 대표 Gmail로의 발신 기능 추가',
        '첫 진입 12시 방향 아이콘 내 스프레드 시트 및 직원용 지정 담당자 Gmail 입력 기능 추가'
      ],
    ),
    UpdateEntry(
      version: 'v1.0.0+9',
      highlights: [
        'OCR 인식 기능 개선',
        '삽입한 번호판 부분 수정 기능 추가',
        '일일 업무 로그 저장 스프레드 시트 추가',
        '태블릿 모드 개선',
        '입차 완료 상태 관련 주차 중인 차량에 대한 열람 경로 확대',
        '본사용 플로팅 버블 기능 개선',
        '직원용 플로팅 버블 기능 추가',
        '경위서 양식 작성 및 사인 기능 추가',
        'Gmail을 통해 txt, pdf 파일 발신 기능 추가',
        '메인 페이지에서 필수 설정 경로 및 앱 종료 기능 제공',
      ],
    ),
    UpdateEntry(
      version: 'v1.0.0+8',
      highlights: [
        '서비스 카드 내 본사 기능 "본사 카드" 내부로 이관(일부 기능 미비)',
        '기능 일부 최적화',
        '로그아웃 기능 개선',
        '번호판 입력 페이지 개선',
        '번호판 입력 OCR 추가',
        '뒤로 가기로 인한 앱 종료 수정',
        '로드맵  수정',
      ],
    ),
    UpdateEntry(
      version: 'v1.0.0+6',
      highlights: [
        '서비스 카드 시그니처 컬러 추가',
        '서비스 카드 내 본사 출/퇴근 관리 달력 개선',
        '기능 일부 최적화',
        '로드맵  수정',
        'TTS 채팅 개선',
        'TTS 채팅 다시 듣기 기능 추가',
        '입차 요청, 홈, 출차 요청의 중단 네비게이션 아이템 색 추가',
        '대시보드 아이콘 숨기기 기능 추가',
        '대시보드 백엔드 세팅 기능 추가',
      ],
    ),
    UpdateEntry(
      version: 'v1.0.0+4',
      highlights: [
        '개발 랩 카드 추가',
      ],
    ),
    UpdateEntry(
      version: 'v1.0.0+1',
      highlights: [
        '내부 테스트 앱 릴리즈',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final list = entries ?? defaultEntries;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.new_releases_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    '업데이트',
                    style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
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
            Divider(height: 1, color: cs.outlineVariant.withOpacity(.5)),

            // Content
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => Divider(height: 24, color: cs.outlineVariant.withOpacity(.3)),
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
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Version (date 제거)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.version,
                    style: text.labelMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Highlights
            ...entry.highlights.map(
                  (h) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(
                      child: Text(
                        h,
                        style: text.bodyMedium?.copyWith(
                          color: cs.onSurface,
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
