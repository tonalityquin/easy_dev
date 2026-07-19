import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/models/capability.dart';
import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../account/applications/user_state.dart';
import '../../dev/application/area_state.dart';
import '../../dashboard/widgets/productivity_sheet.dart';
import '../double_departure_completed_bottom_sheet.dart';

class DoubleParkingCompletedControlButtons extends StatelessWidget {
  const DoubleParkingCompletedControlButtons({
    super.key,
    required this.showSearchDialog,
  });

  final VoidCallback showSearchDialog;

  Future<void> _openDepartureCompleted(BuildContext context) async {
    await showPromptOverlayBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      transparentBackground: true,
      builder: (_) => const DoubleDepartureCompletedBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final hasMonthlyCapability = context.select<AreaState, bool>(
      (state) => state.capabilitiesOfCurrentArea.contains(Capability.monthly),
    );
    final isFieldCommon = context.select<UserState, bool>(
      (state) => state.role.trim() == 'fieldCommon',
    );
    final canUseMonthly = hasMonthlyCapability && !isFieldCommon;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
        child: Row(
          children: [
            Expanded(
              child: PromptButton(
                label: '정기 주차',
                icon: Icons.dashboard_customize_rounded,
                onPressed: canUseMonthly
                    ? () => ProductivitySheet.togglePanel()
                    : null,
                variant: PromptButtonVariant.secondary,
                expand: true,
                minHeight: 50,
                haptic: PromptHaptic.selection,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PromptButton(
                label: '검색',
                icon: Icons.manage_search_rounded,
                onPressed: showSearchDialog,
                variant: PromptButtonVariant.secondary,
                expand: true,
                minHeight: 50,
                haptic: PromptHaptic.selection,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PromptButton(
                label: '출차 완료',
                icon: Icons.directions_car_filled_rounded,
                onPressed: () => _openDepartureCompleted(context),
                expand: true,
                minHeight: 50,
                haptic: PromptHaptic.selection,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
