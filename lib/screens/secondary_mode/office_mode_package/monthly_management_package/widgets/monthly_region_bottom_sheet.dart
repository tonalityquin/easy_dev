import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

        return SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: cs.outlineVariant.withOpacity(.50)),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withOpacity(.10),
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
                      color: cs.outlineVariant.withOpacity(.60),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.info_outline, color: cs.onSurface),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '선택 가능한 지역이 없습니다.',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
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
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
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
                    color: cs.shadow.withOpacity(.10),
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
                        color: cs.outlineVariant.withOpacity(.60),
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
                          color: cs.primaryContainer.withOpacity(.65),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                        ),
                        child: Icon(Icons.place_outlined, color: cs.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '지역 선택',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                        icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outlineVariant.withOpacity(.65)),
                    ),
                    child: Text(
                      '현재 선택: $selectedRegion',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Picker
                  SizedBox(
                    height: 216,
                    child: CupertinoTheme(
                      data: CupertinoThemeData(
                        primaryColor: cs.primary,
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
                          background: cs.primaryContainer.withOpacity(.35),
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
                            foregroundColor: cs.onSurface,
                            side: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
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
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
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
