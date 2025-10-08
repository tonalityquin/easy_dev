import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/area/area_state.dart';
import '../../states/calendar/field_calendar_state.dart';

import 'offline_departure_completed_package/departure_completed_tab_settled.dart';
import 'offline_departure_completed_package/departure_completed_tab_unsettled.dart';
import 'offline_departure_completed_package/widgets/departure_completed_selected_date_bar.dart';

/// SQLite 전용 BottomSheet
/// - PlateState/PlateType/PlateModel 의존 제거
/// - Unsettled/Settled 탭에 area/selectedDate만 전달 (각 탭 내부가 SQLite 직접 질의)
class OfflineDepartureCompletedBottomSheet extends StatefulWidget {
  const OfflineDepartureCompletedBottomSheet({super.key});

  @override
  State<OfflineDepartureCompletedBottomSheet> createState() => _OfflineDepartureCompletedBottomSheetState();
}

class _OfflineDepartureCompletedBottomSheetState extends State<OfflineDepartureCompletedBottomSheet> {

  @override
  Widget build(BuildContext context) {
    final areaState = context.watch<AreaState>();
    final division = areaState.currentDivision;
    final area = areaState.currentArea.trim();

    final selectedDateRaw = context.watch<FieldSelectedDateState>().selectedDate ?? DateTime.now();
    final selectedDate = DateTime(selectedDateRaw.year, selectedDateRaw.month, selectedDateRaw.day);

    // Settled 탭에서 사용할(선택 차량 레이블 용도) — 실제 SQLite에서는 필요치 않음이라 빈 문자열 전달
    final plateNumber = '';

    return SizedBox(
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
                        const SizedBox(height: 16),
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
                                area: area,
                                selectedDate: selectedDate,
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
    );
  }
}
