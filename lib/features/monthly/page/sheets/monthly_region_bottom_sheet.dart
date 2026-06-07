import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _regionInk = Color(0xFF101828);
const _regionMuted = Color(0xFF667085);
const _regionCanvas = Color(0xFFF3F6FA);
const _regionPanel = Color(0xFFFFFFFF);
const _regionLine = Color(0xFFD8DEE8);
const _regionBlue = Color(0xFF2563EB);

Future<void> monthlyRegionPickerBottomSheet({
  required BuildContext context,
  required String selectedRegion,
  required List<String> regions,
  required ValueChanged<String> onConfirm,
}) async {
  if (regions.isEmpty) {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: _regionPanel,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              border: Border(top: BorderSide(color: _regionLine)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, color: _regionMuted, size: 34),
                const SizedBox(height: 10),
                const Text(
                  '선택 가능한 지역이 없습니다.',
                  style: TextStyle(color: _regionInk, fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: _regionInk,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
  final initialIndex = idx >= 0 && idx < regions.length ? idx : 0;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.56,
        minChildSize: 0.46,
        maxChildSize: 0.88,
        builder: (ctx, scrollController) {
          return SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                color: _regionCanvas,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(color: _regionLine)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _regionBlue,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.place_outlined, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '번호판 지역 선택',
                              style: TextStyle(color: _regionInk, fontWeight: FontWeight.w900, fontSize: 20),
                            ),
                            SizedBox(height: 3),
                            Text(
                              '차량번호 앞 지역 표기를 선택합니다.',
                              style: TextStyle(color: _regionMuted, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                        icon: const Icon(Icons.close, color: _regionMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: _regionPanel,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _regionLine),
                    ),
                    child: Text(
                      '현재 선택: $selectedRegion',
                      style: const TextStyle(color: _regionInk, fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: _regionPanel,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _regionLine),
                    ),
                    child: CupertinoTheme(
                      data: const CupertinoThemeData(
                        primaryColor: _regionBlue,
                        textTheme: CupertinoTextThemeData(
                          pickerTextStyle: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: _regionInk,
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
                          background: _regionBlue.withOpacity(.10),
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
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetCtx).pop(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            onConfirm(tempSelected);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: _regionInk,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
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
