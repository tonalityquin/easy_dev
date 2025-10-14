import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../states/calendar/field_calendar_state.dart';
import '../../states/plate/plate_state.dart';
import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';

import 'departure_completed_package/departure_completed_tab_settled.dart';
import 'departure_completed_package/departure_completed_tab_unsettled.dart';
import 'departure_completed_package/widgets/departure_completed_selected_date_bar.dart';

class DepartureCompletedBottomSheet extends StatefulWidget {
  const DepartureCompletedBottomSheet({super.key});

  @override
  State<DepartureCompletedBottomSheet> createState() => _DepartureCompletedBottomSheetState();
}

class _DepartureCompletedBottomSheetState extends State<DepartureCompletedBottomSheet> {
  // 화면 식별 태그(FAQ/에러 리포트 연계용)
  static const String screenTag = 'departure completed';

  final bool _isSorted = true;

  bool _areaEquals(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

  // 좌측 상단(11시) 태그 위젯
  Widget _buildScreenTag(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ??
        const TextStyle(
          fontSize: 11,
          color: Colors.black54,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return IgnorePointer( // 시트 제스처와의 간섭 방지
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
    final plateState = context.watch<PlateState>();
    final userName = context.read<UserState>().name;
    final areaState = context.watch<AreaState>();

    final division = areaState.currentDivision;
    final area = areaState.currentArea.trim();
    final selectedDateRaw = context.watch<FieldSelectedDateState>().selectedDate ?? DateTime.now();
    final selectedDate = DateTime(selectedDateRaw.year, selectedDateRaw.month, selectedDateRaw.day);

    final baseList = plateState.getPlatesByCollection(
      PlateType.departureCompleted,
      selectedDate: selectedDate,
    );

    List<PlateModel> firestorePlates = baseList.where((p) {
      final sameArea = _areaEquals(p.area, area);
      return !p.isLockedFee && sameArea; // 일반 모드: 미정산만
    }).toList();

    firestorePlates.sort(
          (a, b) => _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime),
    );

    final selectedPlate = plateState.getSelectedPlate(PlateType.departureCompleted, userName);
    final plateNumber = selectedPlate?.plateNumber ?? '';

    return WillPopScope(
      onWillPop: () async {
        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await plateState.togglePlateIsSelected(
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
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                          // ⬇️ 좌측 상단(11시) 화면 태그
                          _buildScreenTag(context),

                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: TabBar(
                              labelColor: Colors.black87,
                              unselectedLabelColor: Colors.grey[600],
                              indicatorColor: Theme.of(context).primaryColor,
                              tabs: const [
                                Tab(text: '미정산'),
                                Tab(text: '정산'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          DepartureCompletedSelectedDateBar(visible: !isSettled),
                          const SizedBox(height: 8),
                          Expanded(
                            child: TabBarView(
                              children: [
                                DepartureCompletedUnsettledTab(
                                  firestorePlates: firestorePlates,
                                  userName: userName,
                                ),
                                DepartureCompletedSettledTab(
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
