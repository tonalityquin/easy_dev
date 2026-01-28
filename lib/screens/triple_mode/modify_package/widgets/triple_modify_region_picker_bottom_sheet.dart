import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class _Brand {
  static Color border(ColorScheme cs) => cs.outlineVariant.withOpacity(0.85);
}

Future<void> tripleModifyRegionPickerBottomSheet({
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

      final initialIndex = regions.contains(selectedRegion) ? regions.indexOf(selectedRegion) : 0;

      return DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border.all(color: _Brand.border(cs)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withOpacity(0.45),
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
                      brightness: Theme.of(context).brightness,
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
                      },
                      children: regions.map((region) {
                        return Center(child: Text(region));
                      }).toList(),
                    ),
                  ),
                ),
                Divider(height: 1, color: _Brand.border(cs)),
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
