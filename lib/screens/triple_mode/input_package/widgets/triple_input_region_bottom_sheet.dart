import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<void> tripleInputRegionPickerBottomSheet({
  required BuildContext context,
  required String selectedRegion,
  required List<String> regions,
  required Function(String selected) onConfirm,
}) async {
  String tempSelected = selectedRegion;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final cs = Theme.of(context).colorScheme;

      return DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.70)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant.withOpacity(0.85),
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
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                      initialItem: regions.indexOf(selectedRegion).clamp(0, regions.length - 1),
                    ),
                    itemExtent: 48,
                    onSelectedItemChanged: (index) {
                      tempSelected = regions[index];
                    },
                    children: regions.map((region) {
                      return Center(
                        child: Text(
                          region,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant.withOpacity(0.70)),
                const SizedBox(height: 12),

                // ✅ iOS 버튼 유지하되, 색은 브랜드(primary) 느낌으로 맞춤
                CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onConfirm(tempSelected);
                  },
                  child: const Text('확인', style: TextStyle(fontSize: 16)),
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
