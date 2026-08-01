import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/models/capability.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../account/applications/user_state.dart';
import '../../dev/application/area_state.dart';
import '../../dashboard/widgets/productivity_sheet.dart';
import '../../../shared/page/application/common/type_auto_transition_guard.dart';
import '../minor_departure_completed_bottom_sheet.dart';

class MinorParkingCompletedControlButtons extends StatelessWidget {
  const MinorParkingCompletedControlButtons({
    super.key,
    required this.showSearchDialog,
  });

  final Future<void> Function() showSearchDialog;

  Future<void> _openDepartureCompleted(BuildContext context) async {
    final guard = context.read<TypeAutoTransitionGuard>();
    await guard.runBlocked<void>(
      '출차 완료',
      () async {
        await showCommonOverlayBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          transparentBackground: true,
          builder: (_) => const MinorDepartureCompletedBottomSheet(),
        );
      },
    );
  }

  Future<void> _openMonthly(BuildContext context) async {
    final guard = context.read<TypeAutoTransitionGuard>();
    await guard.runBlocked<void>(
      '정기 주차',
      ProductivitySheet.togglePanel,
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    final guard = context.read<TypeAutoTransitionGuard>();
    await guard.runBlocked<void>(
      '검색',
      showSearchDialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
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
              child: CommonButton(
                label: '정기 주차',
                icon: Icons.dashboard_customize_rounded,
                onPressed: canUseMonthly
                    ? () => _openMonthly(context)
                    : null,
                variant: CommonButtonVariant.secondary,
                expand: true,
                minHeight: 50,
                haptic: CommonHaptic.selection,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CommonButton(
                label: '검색',
                icon: Icons.manage_search_rounded,
                onPressed: () => _openSearch(context),
                variant: CommonButtonVariant.secondary,
                expand: true,
                minHeight: 50,
                haptic: CommonHaptic.selection,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CommonButton(
                label: '출차 완료',
                icon: Icons.directions_car_filled_rounded,
                onPressed: () => _openDepartureCompleted(context),
                expand: true,
                minHeight: 50,
                haptic: CommonHaptic.selection,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
