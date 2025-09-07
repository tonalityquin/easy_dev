import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> monthlyRegionPickerBottomSheet({
  required BuildContext context,
  required String selectedRegion,
  required List<String> regions,
  required ValueChanged<String> onConfirm, // ✅ 명확한 콜백 타입
}) async {
  // ✅ 빈 목록 가드
  if (regions.isEmpty) {
    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
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
  final initialIndex = (idx >= 0 && idx < regions.length) ? idx : 0; // ✅ 안전한 초기 인덱스

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      final cs = Theme.of(context).colorScheme;

      return DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, scrollController) {
          return SafeArea(
            top: false,
            bottom: true, // ✅ 홈 인디케이터/노치 고려
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: ListView(
                controller: scrollController, // ✅ 시트 드래그와 스크롤 연동
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  const Text(
                    '지역 선택',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // ✅ 픽커는 고정 높이로 배치하여 시트 제스처 간섭 최소화
                  SizedBox(
                    height: 216,
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: initialIndex),
                      itemExtent: 48,
                      onSelectedItemChanged: (index) {
                        tempSelected = regions[index];
                        HapticFeedback.selectionClick(); // 선택 햅틱(선택 사항)
                      },
                      children: [
                        for (final region in regions)
                          Center(
                            child: Text(
                              region,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const Divider(height: 24),

                  // 확인 버튼
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 24),
                    child: CupertinoButton.filled(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                      onPressed: () {
                        Navigator.of(context).pop();
                        onConfirm(tempSelected);
                      },
                      child: const Text('확인', style: TextStyle(fontSize: 16)),
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
