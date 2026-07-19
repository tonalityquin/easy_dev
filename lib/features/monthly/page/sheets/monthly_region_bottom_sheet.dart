import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';

Future<void> monthlyRegionPickerBottomSheet({
  required BuildContext context,
  required String selectedRegion,
  required List<String> regions,
  required ValueChanged<String> onConfirm,
}) async {
  if (regions.isEmpty) {
    await showPromptOverlayBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      transparentBackground: true,
      builder: (sheetContext) {
        final tokens = PromptUiTheme.of(sheetContext);
        final textTheme = Theme.of(sheetContext).textTheme;
        return Material(
          color: tokens.surfaceRaised,
          surfaceTintColor: tokens.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(PromptUiShapes.sheet),
            ),
            side: BorderSide(color: tokens.borderSubtle),
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.warningContainer,
                    borderRadius: BorderRadius.circular(PromptUiShapes.control),
                  ),
                  child: Icon(
                    Icons.info_outline_rounded,
                    color: tokens.onWarningContainer,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '선택 가능한 지역이 없습니다.',
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                PromptButton(
                  label: '닫기',
                  expand: true,
                  haptic: PromptHaptic.selection,
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
    return;
  }

  var selected = selectedRegion;
  final currentIndex = regions.indexOf(selectedRegion);
  final initialIndex = currentIndex >= 0 ? currentIndex : 0;

  await showPromptOverlayBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    transparentBackground: true,
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        initialChildSize: 0.58,
        minChildSize: 0.48,
        maxChildSize: 0.88,
        builder: (context, scrollController) {
          final tokens = PromptUiTheme.of(context);
          final textTheme = Theme.of(context).textTheme;
          return Material(
            color: tokens.surfaceRaised,
            surfaceTintColor: tokens.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(PromptUiShapes.sheet),
              ),
              side: BorderSide(color: tokens.borderSubtle),
            ),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: tokens.handle,
                        borderRadius:
                            BorderRadius.circular(PromptUiShapes.pill),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tokens.accentContainer,
                          borderRadius:
                              BorderRadius.circular(PromptUiShapes.control),
                          border: Border.all(
                            color: tokens.accent.withOpacity(
                              tokens.isDark ? 0.56 : 0.34,
                            ),
                          ),
                        ),
                        child: Icon(
                          Icons.place_outlined,
                          color: tokens.onAccentContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '번호판 지역 선택',
                              style: textTheme.titleMedium?.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '차량번호 앞 지역 표기를 선택합니다.',
                              style: textTheme.bodySmall?.copyWith(
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PromptIconButton(
                        icon: Icons.close_rounded,
                        tooltip: '닫기',
                        haptic: PromptHaptic.selection,
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: tokens.surfaceOverlay,
                      borderRadius:
                          BorderRadius.circular(PromptUiShapes.control),
                      border: Border.all(color: tokens.borderSubtle),
                    ),
                    child: Text(
                      '현재 선택: $selectedRegion',
                      style: textTheme.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: tokens.surfaceOverlay,
                      borderRadius: BorderRadius.circular(PromptUiShapes.card),
                      border: Border.all(color: tokens.borderSubtle),
                    ),
                    child: CupertinoTheme(
                      data: CupertinoThemeData(
                        brightness: tokens.brightness,
                        primaryColor: tokens.accent,
                        textTheme: CupertinoTextThemeData(
                          pickerTextStyle: textTheme.titleMedium!.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: initialIndex,
                        ),
                        itemExtent: 48,
                        onSelectedItemChanged: (index) {
                          selected = regions[index];
                          HapticFeedback.selectionClick();
                        },
                        selectionOverlay:
                            CupertinoPickerDefaultSelectionOverlay(
                          background: tokens.surfaceSelected,
                        ),
                        children: [
                          for (final region in regions)
                            Center(
                              child: Text(
                                region,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: PromptButton(
                          label: '취소',
                          variant: PromptButtonVariant.tertiary,
                          haptic: PromptHaptic.selection,
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PromptButton(
                          label: '확인',
                          icon: Icons.check_rounded,
                          haptic: PromptHaptic.medium,
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            onConfirm(selected);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
