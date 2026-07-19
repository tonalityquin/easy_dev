import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';

Future<void> inputRegionPickerBottomSheet({
  required BuildContext context,
  required String selectedRegion,
  required List<String> regions,
  required Function(String selected) onConfirm,
  bool usePromptUi = false,
}) async {
  var tempSelected = selectedRegion;

  Widget builder(BuildContext sheetContext) {
    final tokens = PromptUiTheme.of(sheetContext);
    final initialIndex = regions.isEmpty
        ? 0
        : regions.indexOf(selectedRegion).clamp(0, regions.length - 1);
    return SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * .58,
      child: PromptSheetScaffold(
        title: '지역 선택',
        icon: Icons.location_on_rounded,
        onClose: () => Navigator.of(sheetContext).pop(),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            children: [
              Expanded(
                child: regions.isEmpty
                    ? Center(
                        child: Text(
                          '선택할 수 있는 지역이 없습니다.',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: tokens.textSecondary),
                        ),
                      )
                    : CupertinoTheme(
                        data: CupertinoThemeData(
                          primaryColor: tokens.accent,
                          brightness: tokens.brightness,
                          textTheme: CupertinoTextThemeData(
                            pickerTextStyle: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
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
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: tokens.textPrimary,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              PromptButton(
                label: '확인',
                icon: Icons.check_rounded,
                expand: true,
                onPressed: regions.isEmpty
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        onConfirm(tempSelected);
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  if (usePromptUi) {
    await showPromptOverlayBottomSheet<void>(
      context: context,
      useSafeArea: false,
      builder: builder,
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: builder,
  );
}
