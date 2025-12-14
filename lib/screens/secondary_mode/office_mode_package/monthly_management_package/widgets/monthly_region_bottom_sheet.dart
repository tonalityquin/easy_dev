import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 서비스 로그인 카드(Deep Blue 팔레트)와 톤을 맞춘 보조 팔레트
class _SvcColors {
  static const base  = Color(0xFF0D47A1);
  static const light = Color(0xFF5472D3);
}

/// 지역 선택 바텀시트 (CupertinoPicker)
/// - 앱 테마의 ColorScheme + 서비스 팔레트에 맞춰 색 반영
/// - 드래그 핸들/테두리/배경 톤 정리
Future<void> monthlyRegionPickerBottomSheet({
  required BuildContext context,
  required String selectedRegion,
  required List<String> regions,
  required ValueChanged<String> onConfirm,
}) async {
  // 빈 목록 가드
  if (regions.isEmpty) {
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          child: const Text('선택 가능한 지역이 없습니다.'),
        ),
      ),
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
        initialChildSize: 0.5,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) {
          return SafeArea(
            top: false,
            bottom: true,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(.5))),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.06),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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

                  Text(
                    '지역 선택',
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: .2,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 픽커(고정 높이)
                  SizedBox(
                    height: 216,
                    child: CupertinoTheme(
                      data: CupertinoThemeData(
                        primaryColor: _SvcColors.base, // 버튼/하이라이트 컬러
                        textTheme: CupertinoTextThemeData(
                          pickerTextStyle: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
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
                          background: _SvcColors.light.withOpacity(.08),
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
                  Divider(color: cs.outlineVariant.withOpacity(.4), height: 24),

                  // 확인/취소 버튼
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: cs.onSurface,
                              side: BorderSide(color: cs.outlineVariant),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('취소'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CupertinoTheme(
                            data: CupertinoThemeData(primaryColor: _SvcColors.base),
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                              color: _SvcColors.base, // 서비스 팔레트 적용
                              onPressed: () {
                                Navigator.of(context).pop();
                                onConfirm(tempSelected);
                              },
                              child: const Text('확인', style: TextStyle(fontSize: 16)),
                            ),
                          ),
                        ),
                      ],
                    ),
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
