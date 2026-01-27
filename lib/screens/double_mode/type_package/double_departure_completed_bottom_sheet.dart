import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../models/plate_model.dart';
import '../../../states/calendar/field_calendar_state.dart';
import '../../../states/area/area_state.dart';
import '../../../states/plate/double_plate_state.dart';
import '../../../states/user/user_state.dart';

import 'departure_completed_package/double_departure_completed_tab_settled.dart';
import 'departure_completed_package/double_departure_completed_tab_unsettled.dart';
import 'departure_completed_package/widgets/double_departure_completed_selected_date_bar.dart';

class DoubleDepartureCompletedBottomSheet extends StatefulWidget {
  const DoubleDepartureCompletedBottomSheet({super.key});

  @override
  State<DoubleDepartureCompletedBottomSheet> createState() => _DoubleDepartureCompletedBottomSheetState();
}

class _DoubleDepartureCompletedBottomSheetState extends State<DoubleDepartureCompletedBottomSheet> {
  static const String screenTag = 'departure completed';

  final bool _isSorted = true;

  bool _areaEquals(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ??
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 6),
          child: Semantics(
            label: 'screen_tag: $screenTag',
            child: Text(screenTag, style: style),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final plateState = context.watch<DoublePlateState>();
    final userName = context.read<UserState>().name;
    final areaState = context.watch<AreaState>();

    final division = areaState.currentDivision;
    final area = areaState.currentArea.trim();

    final selectedDateRaw = context.watch<FieldSelectedDateState>().selectedDate ?? DateTime.now();
    final selectedDate = DateTime(selectedDateRaw.year, selectedDateRaw.month, selectedDateRaw.day);

    final baseList = plateState.doubleGetPlatesByCollection(
      PlateType.departureCompleted,
      selectedDate: selectedDate,
    );

    List<PlateModel> firestorePlates = baseList.where((p) {
      final sameArea = _areaEquals(p.area, area);
      return !p.isLockedFee && sameArea; // 미정산만
    }).toList();

    firestorePlates.sort(
          (a, b) => _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime),
    );

    final selectedPlate = plateState.doubleGetSelectedPlate(PlateType.departureCompleted, userName);
    final plateNumber = selectedPlate?.plateNumber ?? '';

    return WillPopScope(
      onWillPop: () async {
        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await plateState.doubleTogglePlateIsSelected(
            collection: PlateType.departureCompleted,
            plateNumber: selectedPlate.plateNumber,
            userName: userName,
            onError: (msg) => debugPrint(msg),
          );
          return false;
        }
        return true;
      },
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.95,
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
          ),
          child: DefaultTabController(
            length: 2,
            child: Builder(
              builder: (context) {
                final tabController = DefaultTabController.of(context);
                return AnimatedBuilder(
                  animation: tabController,
                  builder: (context, _) {
                    final isSettled = tabController.index == 1;

                    return Scaffold(
                      backgroundColor: Colors.transparent,
                      body: Column(
                        children: [
                          const SizedBox(height: 12),

                          // 상단 드래그 핸들
                          Center(
                            child: Container(
                              width: 60,
                              height: 6,
                              decoration: BoxDecoration(
                                color: cs.outlineVariant.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),

                          // 좌측 상단(11시) 화면 태그
                          _buildScreenTag(context),

                          const SizedBox(height: 8),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: TabBar(
                              labelColor: cs.onSurface,
                              unselectedLabelColor: cs.onSurfaceVariant,
                              indicatorColor: cs.primary,
                              dividerColor: cs.outlineVariant.withOpacity(0.85),
                              tabs: const [
                                Tab(text: '미정산'),
                                Tab(text: '정산'),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),

                          DoubleDepartureCompletedSelectedDateBar(visible: !isSettled),

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
                      ),
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
