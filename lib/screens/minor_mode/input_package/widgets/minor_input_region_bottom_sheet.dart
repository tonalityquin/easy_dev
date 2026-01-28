import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<void> minorInputRegionPickerBottomSheet({
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
      final tt = Theme.of(context).textTheme;

      final cupertinoTheme = CupertinoThemeData(
        brightness: Theme.of(context).brightness,
        primaryColor: cs.primary,
        scaffoldBackgroundColor: cs.surface,
        barBackgroundColor: cs.surface,
        textTheme: CupertinoTextThemeData(
          textStyle: TextStyle(color: cs.onSurface),
          pickerTextStyle: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      return CupertinoTheme(
        data: cupertinoTheme,
        child: DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.8))),
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
                    style: (tt.titleLarge ?? const TextStyle(fontSize: 20)).copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                        initialItem: regions.indexOf(selectedRegion),
                      ),
                      itemExtent: 48,
                      backgroundColor: cs.surface,
                      selectionOverlay: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: cs.outlineVariant.withOpacity(0.9)),
                            bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.9)),
                          ),
                        ),
                      ),
                      onSelectedItemChanged: (index) {
                        tempSelected = regions[index];
                      },
                      children: regions.map((region) {
                        return Center(
                          child: Text(
                            region,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  Divider(height: 1, color: cs.outlineVariant.withOpacity(0.9)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(12),
                      onPressed: () {
                        Navigator.of(context).pop();
                        onConfirm(tempSelected);
                      },
                      child: Text(
                        '확인',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: cs.onPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}
