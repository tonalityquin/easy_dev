// lib/screens/simple_package/sections3/widgets/simple_inside_report_selector_sheet.dart
import 'package:flutter/material.dart';

import '../../sections3/widgets/simple_inside_report_bottom_sheet.dart';
import '../../sections3/widgets/simple_inside_work_bottom_sheet.dart';


/// 내부에서만 사용하는 선택 결과 enum
enum _SimpleReportSheetResult {
  workStart,
  workEnd,
}

/// SimpleInsideReportButtonSection 에서 호출하는 공개 함수
/// - 문서철 스타일의 선택 시트를 띄운 뒤
/// - 선택 결과에 따라 업무 시작/종료 보고서 풀스크린 바텀시트를 연다.
Future<void> openSimpleInsideReportSelectorSheet(
    BuildContext context,
    ) async {
  // 풀스크린 바텀시트를 띄울 때 사용할 상위 context
  final rootContext = context;

  final _SimpleReportSheetResult? result =
  await showModalBottomSheet<_SimpleReportSheetResult>(
    context: context,
    useRootNavigator: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _SimpleReportSelectorSheet(),
  );

  if (result == null) {
    // 유저가 그냥 닫은 경우
    return;
  }

  // 선택 결과에 따라 기존 풀스크린 바텀시트 헬퍼 호출
  switch (result) {
    case _SimpleReportSheetResult.workStart:
    // ✅ 업무 시작 보고서 폼 (SimpleInsideWorkFormPage)
      showSimpleInsideWorkFullScreenBottomSheet(rootContext);
      break;
    case _SimpleReportSheetResult.workEnd:
    // ✅ 업무 종료 보고서 폼 (SimpleInsideReportFormPage)
      showSimpleInsideReportFullScreenBottomSheet(rootContext);
      break;
  }
}

/// 문서철 스타일의 "업무 보고 선택" 시트
class _SimpleReportSelectorSheet extends StatelessWidget {
  const _SimpleReportSelectorSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (ctx, scrollController) {
        final textTheme = Theme.of(context).textTheme;

        // 선택 가능한 옵션 2개 (업무 시작 / 업무 종료)
        final options = <_ReportOption>[
          _ReportOption(
            result: _SimpleReportSheetResult.workStart,
            title: '업무 시작 보고서',
            subtitle: '근무 시작 시 작성하는 보고서',
            tagLabel: '업무 시작 보고',
            accentColor: const Color(0xFF4F9A94), // 문서철과 동일한 청록톤
            iconData: Icons.wb_sunny_outlined,
          ),
          _ReportOption(
            result: _SimpleReportSheetResult.workEnd,
            title: '업무 종료 보고서',
            subtitle: '근무 종료 시 작성하는 보고서',
            tagLabel: '업무 종료 보고',
            accentColor: const Color(0xFFD84315), // 종료 보고서용 진한 레드톤
            iconData: Icons.nights_stay_outlined,
          ),
        ];

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            children: [
              const _SheetHandle(),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F5EB),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const _BinderSpine(),
                      const VerticalDivider(
                        width: 0,
                        thickness: 0.6,
                        color: Color(0xFFE0D7C5),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            const _SheetHeader(),
                            const Divider(
                              height: 1,
                              thickness: 0.8,
                              color: Color(0xFFE5DFD0),
                            ),
                            Expanded(
                              child: ListView.builder(
                                controller: scrollController,
                                padding:
                                const EdgeInsets.symmetric(vertical: 12),
                                itemCount: options.length,
                                itemBuilder: (context, index) {
                                  final option = options[index];
                                  return _SimpleReportListItem(
                                    option: option,
                                    textTheme: textTheme,
                                    onTap: () {
                                      // 선택 시, 해당 enum을 넘기며 시트 닫기
                                      Navigator.of(context)
                                          .pop(option.result);
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 상단 드래그 핸들 (문서철과 동일 디자인)
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 64,
        height: 6,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.brown.withOpacity(0.25),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// 문서철 왼쪽 스파인(바인더 느낌) – 문서철과 동일 디자인
class _BinderSpine extends StatelessWidget {
  const _BinderSpine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      decoration: const BoxDecoration(
        color: Color(0xFFE0D7C5),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          5,
              (index) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.brown[200],
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 상단 헤더(문서철 제목/설명) – 텍스트만 "업무 보고"에 맞게 수정
class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.brown.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.assignment_outlined,
              size: 22,
              color: Colors.brown,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '업무 보고',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF4A3A28),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '업무 시작/종료 보고서를 선택해 작성하세요.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8A7A65),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '닫기',
            icon: const Icon(
              Icons.close,
              size: 20,
              color: Color(0xFF7A6A55),
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// 선택 가능한 옵션 1개를 표현하는 내부 모델
class _ReportOption {
  final _SimpleReportSheetResult result;
  final String title;
  final String subtitle;
  final String tagLabel;
  final Color accentColor;
  final IconData iconData;

  const _ReportOption({
    required this.result,
    required this.title,
    required this.subtitle,
    required this.tagLabel,
    required this.accentColor,
    required this.iconData,
  });
}

/// 각각의 옵션을 카드 형태로 보여주는 위젯
/// (simple_document_box_sheet 의 _DocumentListItem 과 동일한 레이아웃/스타일)
class _SimpleReportListItem extends StatelessWidget {
  final _ReportOption option;
  final TextTheme? textTheme;
  final VoidCallback onTap;

  const _SimpleReportListItem({
    required this.option,
    required this.textTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = option.accentColor;
    final theme = textTheme ?? Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 좌측 컬러 인덱스 바
              Container(
                width: 6,
                height: 80,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: accentColor.withOpacity(0.15),
                        child: Icon(
                          option.iconData,
                          color: accentColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF3C342A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              option.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodySmall?.copyWith(
                                color: const Color(0xFF7A6F63),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentColor.withOpacity(0.14),
                                    borderRadius:
                                    BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    option.tagLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.labelSmall?.copyWith(
                                      color: accentColor.darken(0.1),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: Color(0xFF9A8C7A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Color 확장: 약간 어둡게 (문서철 코드와 동일)
extension _ColorShadeExtension on Color {
  Color darken(double amount) {
    assert(amount >= 0 && amount <= 1);
    final f = 1 - amount;
    return Color.fromARGB(
      alpha,
      (red * f).round(),
      (green * f).round(),
      (blue * f).round(),
    );
  }
}
