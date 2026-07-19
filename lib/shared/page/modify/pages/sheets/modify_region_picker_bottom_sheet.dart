import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';

Future<void> modifyRegionPickerBottomSheet({
  required BuildContext context,
  required String selectedRegion,
  required List<String> regions,
  required Function(String selected) onConfirm,
}) async {
  if (regions.isEmpty) return;
  var tempSelected = regions.contains(selectedRegion)
      ? selectedRegion
      : regions.first;
  final initialIndex = regions.indexOf(tempSelected);

  await showPromptOverlayBottomSheet<void>(
    context: context,
    useSafeArea: false,
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: .52,
      minChildSize: .4,
      maxChildSize: .9,
      builder: (sheetContext, _) {
        final tokens = PromptUiTheme.of(sheetContext);
        return PromptSheetScaffold(
          title: '지역 선택',
          icon: Icons.public_rounded,
          onClose: () => Navigator.of(sheetContext).pop(),
          body: Column(
            children: [
              Expanded(
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    primaryColor: tokens.accent,
                    brightness: tokens.brightness,
                    textTheme: CupertinoTextThemeData(
                      pickerTextStyle: Theme.of(sheetContext)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
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
                    children: regions
                        .map(
                          (region) => Center(
                            child: Text(
                              region,
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              Divider(height: 1, color: tokens.borderSubtle),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: PromptButton(
                  label: '확인',
                  icon: Icons.check_rounded,
                  expand: true,
                  haptic: PromptHaptic.selection,
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    onConfirm(tempSelected);
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
