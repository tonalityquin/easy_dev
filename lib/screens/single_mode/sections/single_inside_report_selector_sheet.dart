import 'package:flutter/material.dart';

import 'widgets/single_inside_report_bottom_sheet.dart';
import 'widgets/single_inside_work_bottom_sheet.dart';

enum _SingleReportSheetResult {
  workStart,
  workEnd,
}

Future<void> openSingleInsideReportSelectorSheet(
    BuildContext context,
    ) async {
  final rootContext = context;

  final _SingleReportSheetResult? result =
  await showModalBottomSheet<_SingleReportSheetResult>(
    context: context,
    useRootNavigator: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _SingleReportSelectorSheet(),
  );

  if (result == null) return;

  switch (result) {
    case _SingleReportSheetResult.workStart:
      showSingleInsideWorkFullScreenBottomSheet(rootContext);
      break;
    case _SingleReportSheetResult.workEnd:
      showSingleInsideReportFullScreenBottomSheet(rootContext);
      break;
  }
}

class _SingleReportSelectorSheet extends StatelessWidget {
  const _SingleReportSelectorSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (ctx, scrollController) {
        final textTheme = Theme.of(context).textTheme;

        final options = <_ReportOption>[
          _ReportOption(
            result: _SingleReportSheetResult.workStart,
            title: '업무 시작 보고서',
            subtitle: '근무 시작 시 작성하는 보고서',
            tagLabel: '업무 시작 보고',
            // ✅ 옵션 accent는 의미상 유지(단, 시트 전체 틴트는 ColorScheme 기반)
            accentColor: cs.primary,
            iconData: Icons.wb_sunny_outlined,
          ),
          _ReportOption(
            result: _SingleReportSheetResult.workEnd,
            title: '업무 종료 보고서',
            subtitle: '근무 종료 시 작성하는 보고서',
            tagLabel: '업무 종료 보고',
            accentColor: cs.error,
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
                    // ✅ 시트 배경: 중립 표면 컨테이너
                    color: cs.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [
                      BoxShadow(
                        color: cs.shadow.withOpacity(0.10),
                        blurRadius: 12,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const _BinderSpine(),
                      VerticalDivider(
                        width: 0,
                        thickness: 0.8,
                        color: cs.outlineVariant.withOpacity(0.8),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            const _SheetHeader(),
                            Divider(
                              height: 1,
                              thickness: 0.8,
                              color: cs.outlineVariant.withOpacity(0.8),
                            ),
                            Expanded(
                              child: ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                itemCount: options.length,
                                itemBuilder: (context, index) {
                                  final option = options[index];
                                  return _SingleReportListItem(
                                    option: option,
                                    textTheme: textTheme,
                                    onTap: () {
                                      Navigator.of(context).pop(option.result);
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

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        width: 64,
        height: 6,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: cs.outlineVariant.withOpacity(0.9),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _BinderSpine extends StatelessWidget {
  const _BinderSpine();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: 32,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24)),
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
                color: cs.outlineVariant.withOpacity(0.9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withOpacity(0.15),
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

class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.75),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.assignment_outlined,
              size: 22,
              color: cs.onPrimaryContainer,
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
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '업무 시작/종료 보고서를 선택해 작성하세요.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '닫기',
            icon: Icon(
              Icons.close,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _ReportOption {
  final _SingleReportSheetResult result;
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

class _SingleReportListItem extends StatelessWidget {
  final _ReportOption option;
  final TextTheme? textTheme;
  final VoidCallback onTap;

  const _SingleReportListItem({
    required this.option,
    required this.textTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accentColor = option.accentColor;
    final theme = textTheme ?? Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 80,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: accentColor.withOpacity(0.16),
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
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              option.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: accentColor.withOpacity(0.16),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    option.tagLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.labelSmall?.copyWith(
                                      color: accentColor,
                                      fontWeight: FontWeight.w700,
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
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: cs.onSurfaceVariant.withOpacity(0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
