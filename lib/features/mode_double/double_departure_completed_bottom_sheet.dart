import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../shared/plate/application/double/double_plate_state.dart';
import '../../shared/plate/domain/enums/plate_type.dart';
import '../account/applications/user_state.dart';
import '../dev/application/area_state.dart';
import '../dev/application/field_calendar_state.dart';
import 'departure_completed_package/double_departure_completed_tab_settled.dart';
import 'departure_completed_package/double_departure_completed_tab_unsettled.dart';
import 'departure_completed_package/widgets/double_departure_completed_selected_date_bar.dart';

class DoubleDepartureCompletedBottomSheet extends StatefulWidget {
  const DoubleDepartureCompletedBottomSheet({super.key});

  @override
  State<DoubleDepartureCompletedBottomSheet> createState() => _DoubleDepartureCompletedBottomSheetState();
}

class _DoubleDepartureCompletedBottomSheetState extends State<DoubleDepartureCompletedBottomSheet> {
  static const String _screenTag = 'departure completed';
  final bool _isSorted = true;

  bool _areaEquals(String a, String b) {
    return a.trim().toLowerCase() == b.trim().toLowerCase();
  }

  Future<bool> _handleWillPop(String userName) async {
    final plateState = context.read<DoublePlateState>();
    final selected = plateState.doubleGetSelectedPlate(
      PlateType.departureCompleted,
      userName,
    );
    if (selected == null || selected.id.isEmpty) return true;
    await plateState.doubleTogglePlateIsSelected(
      collection: PlateType.departureCompleted,
      plateNumber: selected.plateNumber,
      userName: userName,
      onError: (message) => debugPrint(message),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final plateState = context.watch<DoublePlateState>();
    final userName = context.read<UserState>().name;
    final areaState = context.watch<AreaState>();
    final division = areaState.currentDivision;
    final area = areaState.currentArea.trim();
    final selectedDateRaw =
        context.watch<FieldSelectedDateState>().selectedDate ?? DateTime.now();
    final selectedDate = DateTime(
      selectedDateRaw.year,
      selectedDateRaw.month,
      selectedDateRaw.day,
    );
    final baseList = plateState.doubleGetPlatesByCollection(
      PlateType.departureCompleted,
      selectedDate: selectedDate,
    );
    final firestorePlates = baseList.where((plate) {
      return !plate.isLockedFee && _areaEquals(plate.area, area);
    }).toList()
      ..sort(
        (a, b) => _isSorted
            ? b.requestTime.compareTo(a.requestTime)
            : a.requestTime.compareTo(b.requestTime),
      );
    final selectedPlate = plateState.doubleGetSelectedPlate(
      PlateType.departureCompleted,
      userName,
    );
    final plateNumber = selectedPlate?.plateNumber ?? '';

    return WillPopScope(
      onWillPop: () => _handleWillPop(userName),
      child: FractionallySizedBox(
        heightFactor: 0.95,
        child: PromptSheetScaffold(
          title: '출차 완료',
          icon: Icons.directions_car_filled_rounded,
          onClose: () => Navigator.of(context).maybePop(),
          body: DefaultTabController(
            length: 2,
            child: Builder(
              builder: (context) {
                final tabController = DefaultTabController.of(context);
                return AnimatedBuilder(
                  animation: tabController,
                  builder: (context, _) {
                    final isSettled = tabController.index == 1;
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Row(
                            children: [
                              Semantics(
                                label: 'screen_tag: $_screenTag',
                                child: Text(
                                  _screenTag,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: tokens.textSecondary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              AnimatedSwitcher(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : PromptUiMotion.selection,
                                child: Container(
                                  key: ValueKey<bool>(isSettled),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSettled
                                        ? tokens.successContainer
                                        : tokens.warningContainer,
                                    borderRadius: BorderRadius.circular(
                                      PromptUiShapes.pill,
                                    ),
                                  ),
                                  child: Text(
                                    isSettled ? '정산' : '미정산',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: isSettled
                                          ? tokens.onSuccessContainer
                                          : tokens.onWarningContainer,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: tokens.surfaceOverlay,
                              borderRadius: BorderRadius.circular(
                                PromptUiShapes.control,
                              ),
                              border: Border.all(color: tokens.borderSubtle),
                            ),
                            child: TabBar(
                              labelColor: tokens.onAccentContainer,
                              unselectedLabelColor: tokens.textSecondary,
                              indicator: BoxDecoration(
                                color: tokens.accentContainer,
                                borderRadius: BorderRadius.circular(
                                  PromptUiShapes.control,
                                ),
                                border: Border.all(color: tokens.accent),
                              ),
                              indicatorSize: TabBarIndicatorSize.tab,
                              dividerColor: tokens.transparent,
                              tabs: const [
                                Tab(text: '미정산'),
                                Tab(text: '정산'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        AnimatedSize(
                          duration: reduceMotion
                              ? Duration.zero
                              : PromptUiMotion.layout,
                          curve: PromptUiMotion.standard,
                          child: DoubleDepartureCompletedSelectedDateBar(visible: !isSettled),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TabBarView(
                            children: [
                              DoubleDepartureCompletedUnsettledTab(
                                firestorePlates: firestorePlates,
                                userName: userName,
                              ),
                              DoubleDepartureCompletedSettledTab(
                                area: area,
                                division: division,
                                selectedDate: selectedDate,
                                plateNumber: plateNumber,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
