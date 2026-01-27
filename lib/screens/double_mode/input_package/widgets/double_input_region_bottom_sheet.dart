import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<void> doubleInputRegionPickerBottomSheet({
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
                      scrollController: FixedExtentScrollController(initialItem: initialIndex),
                      itemExtent: 48,
                      onSelectedItemChanged: (index) {
                        tempSelected = regions[index];
                      },
                      children: regions
                          .map(
                            (region) => Center(
                          child: Text(
                            region,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      )
                          .toList(),
                    ),
                  ),
                ),

                Divider(height: 1, color: cs.outlineVariant.withOpacity(0.85)),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onConfirm(tempSelected);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
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
