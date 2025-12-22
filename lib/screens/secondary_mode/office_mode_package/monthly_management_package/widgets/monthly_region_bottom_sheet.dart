import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ✅ AppCardPalette 사용 (프로젝트 경로에 맞게 수정)
// 예: import 'package:easydev/theme/app_card_palette.dart';
import '../../../../../theme.dart';

Future<void> monthlyRegionPickerBottomSheet({
  required BuildContext context,
  required String selectedRegion,
  required List<String> regions,
  required ValueChanged<String> onConfirm,
}) async {
  // 빈 목록 가드 (로직 유지)
  if (regions.isEmpty) {
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final palette = AppCardPalette.of(ctx);

        return SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: cs.outlineVariant.withOpacity(.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.08),
                  blurRadius: 14,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: cs.outlineVariant.withOpacity(.6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.info_outline, color: palette.serviceDark),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '선택 가능한 지역이 없습니다.',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: palette.serviceDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.serviceBase,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: const Text('닫기'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return;
  }

  String tempSelected = selectedRegion;
  final idx = regions.indexOf(selectedRegion);
  final initialIndex = (idx >= 0 && idx < regions.length) ? idx : 0;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      final cs = Theme.of(sheetCtx).colorScheme;
      final palette = AppCardPalette.of(sheetCtx);

      return DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.45,
        maxChildSize: 0.90,
        builder: (ctx, scrollController) {
          return SafeArea(
            top: false,
            bottom: true,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(.55))),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.08),
                    blurRadius: 14,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: cs.outlineVariant.withOpacity(.6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),

                  // 헤더(아이콘+제목+닫기)
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: palette.serviceLight.withOpacity(.18),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: palette.serviceLight.withOpacity(.40)),
                        ),
                        child: Icon(Icons.place_outlined, color: palette.serviceDark),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '지역 선택',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: palette.serviceDark,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                        icon: const Icon(Icons.close),
                        color: palette.serviceDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: palette.serviceLight.withOpacity(.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: palette.serviceLight.withOpacity(.25)),
                    ),
                    child: Text(
                      '현재 선택: $selectedRegion',
                      style: TextStyle(
                        color: palette.serviceDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Picker
                  SizedBox(
                    height: 216,
                    child: CupertinoTheme(
                      data: CupertinoThemeData(
                        primaryColor: palette.serviceBase,
                        textTheme: CupertinoTextThemeData(
                          pickerTextStyle: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(initialItem: initialIndex),
                        itemExtent: 48,
                        onSelectedItemChanged: (index) {
                          tempSelected = regions[index];
                          HapticFeedback.selectionClick();
                        },
                        selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                          background: palette.serviceLight.withOpacity(.10),
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

                  const SizedBox(height: 10),
                  Divider(color: cs.outlineVariant.withOpacity(.45), height: 24),

                  // 취소/확인
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: palette.serviceDark,
                            side: BorderSide(color: palette.serviceLight.withOpacity(.75)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () => Navigator.of(sheetCtx).pop(),
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: palette.serviceBase,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ),
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            onConfirm(tempSelected);
                          },
                          child: const Text('확인'),
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
