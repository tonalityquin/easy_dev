import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<void> minorModifyRegionPickerBottomSheet({
  required BuildContext context,
  required String selectedRegion,
  required List<String> regions,
  required Function(String selected) onConfirm,
}) async {
  final list = List<String>.from(regions);

  // ✅ 선택값이 리스트에 없을 경우 안전 폴백
  final int initialIndexRaw = list.indexOf(selectedRegion);
  final int initialIndex = (initialIndexRaw >= 0) ? initialIndexRaw : 0;

  String tempSelected = list.isNotEmpty ? list[initialIndex] : selectedRegion;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final cs = Theme.of(sheetContext).colorScheme;

      if (list.isEmpty) {
        return SafeArea(
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 34),
                    const SizedBox(height: 10),
                    const Text(
                      '지역 목록이 비어있습니다.',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => Navigator.of(sheetContext).maybePop(),
                      child: const Text('닫기'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.40,
        maxChildSize: 0.90,
        builder: (_, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Column(
              children: [
                // Handle + Close
                Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => Navigator.of(sheetContext).maybePop(),
                      icon: Icon(Icons.close, color: cs.onSurface.withOpacity(0.75)),
                    ),
                  ],
                ),

                const SizedBox(height: 2),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '지역 선택',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                      initialItem: initialIndex,
                    ),
                    itemExtent: 48,
                    onSelectedItemChanged: (index) {
                      // ✅ index 안전
                      if (index < 0 || index >= list.length) return;
                      tempSelected = list[index];
                    },
                    children: list.map((region) {
                      return Center(
                        child: Text(
                          region,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const Divider(height: 1),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    onPressed: () {
                      // ✅ pop 먼저 + 콜백 호출(중복 pop/locked 방지)
                      Navigator.of(sheetContext).maybePop();
                      onConfirm(tempSelected);
                    },
                    child: const Text(
                      '확인',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),

                const SizedBox(height: 10),
              ],
            ),
          );
        },
      );
    },
  );
}
