import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<void> doubleModifyRegionPickerBottomSheet({
  required BuildContext context,
  required String selectedRegion,
  required List<String> regions,
  required Function(String selected) onConfirm,
}) async {
  String tempSelected = selectedRegion;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final cs = Theme.of(context).colorScheme;

      return DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, scrollController) {
          final initialIndex = regions.indexOf(selectedRegion).clamp(0, regions.isEmpty ? 0 : regions.length - 1);

          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  '지역 선택',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 16),

                Expanded(
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      // ✅ CupertinoPicker 텍스트/강조 색을 Material 테마에 맞춰 통일
                      primaryColor: cs.primary,
                      brightness: cs.brightness,
                      textTheme: CupertinoTextThemeData(
                        pickerTextStyle: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                        initialItem: initialIndex,
                      ),
                      itemExtent: 48,
                      onSelectedItemChanged: (index) {
                        tempSelected = regions[index];
                      },
                      children: regions.map((region) {
                        return Center(
                          child: Text(
                            region,
                            // pickerTextStyle이 적용되지만, 안전하게 동일 스타일 유지
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                Divider(height: 1, color: cs.outlineVariant.withOpacity(0.85)),
                const SizedBox(height: 12),

                // ✅ CupertinoButton.filled 기본 스타일이 iOS 블루로 고정되기 쉬워서,
                //    테마 프리셋을 정확히 따르도록 Material FilledButton으로 교체
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      onConfirm(tempSelected);
                    },
                    child: const Text('확인'),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          );
        },
      );
    },
  );
}
