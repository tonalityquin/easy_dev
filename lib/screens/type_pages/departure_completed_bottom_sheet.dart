import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../states/calendar/field_calendar_state.dart';
import '../../states/plate/plate_state.dart';
import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';

import 'departure_completed_pages/departure_completed_tab_settled.dart';
import 'departure_completed_pages/departure_completed_tab_unsettled.dart';
import 'departure_completed_pages/departure_completed_control_buttons.dart';
import 'departure_completed_pages/widgets/selected_date_bar.dart';

class DepartureCompletedBottomSheet extends StatefulWidget {
  const DepartureCompletedBottomSheet({super.key});

  @override
  State<DepartureCompletedBottomSheet> createState() => _DepartureCompletedBottomSheetState();
}

class _DepartureCompletedBottomSheetState extends State<DepartureCompletedBottomSheet> {
  final bool _isSorted = true;

  bool _areaEquals(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final plateState = context.watch<PlateState>();
    final userName = context.read<UserState>().name;
    final areaState = context.watch<AreaState>();

    final division = areaState.currentDivision;
    final area = areaState.currentArea.trim();
    final selectedDateRaw = context.watch<FieldSelectedDateState>().selectedDate ?? DateTime.now();
    final selectedDate = DateTime(selectedDateRaw.year, selectedDateRaw.month, selectedDateRaw.day);

    // 날짜(자정~자정) 필터까지 반영된 기본 리스트
    final baseList = plateState.getPlatesByCollection(
      PlateType.departureCompleted,
      selectedDate: selectedDate,
    );

    // 화면단 area 필터만 적용 (검색 제거)
    List<PlateModel> firestorePlates = baseList.where((p) {
      final sameArea = _areaEquals(p.area, area);
      return !p.isLockedFee && sameArea; // 일반 모드: 미정산만
    }).toList();

    // 정렬 (기존 로직 유지: requestTime 기준)
    firestorePlates.sort(
          (a, b) => _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime),
    );

    // 선택된 번호판
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
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Column(
                children: [
                  const SizedBox(height: 12),
                  // 상단 핸들
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
                  // 탭 바 (미정산 / 정산)
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
                  const SelectedDateBar(),

                  const SizedBox(height: 8),
                  // 탭 콘텐츠
                  Expanded(
                    child: TabBarView(
                      children: [
                        // ───── 미정산 탭
                        DepartureCompletedUnsettledTab(
                          firestorePlates: firestorePlates, // 부모에서 이미 필터/정렬된 리스트
                          userName: userName,
                        ),

                        // ───── 정산 탭
                        DepartureCompletedSettledTab(
                          area: area,
                          division: division,
                          selectedDate: selectedDate,
                          plateNumber: plateNumber, // 선택된 번호판(없으면 빈 문자열)
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // 공간 유지: 컨트롤 바는 그대로 렌더하되 입력은 무시
              bottomNavigationBar: IgnorePointer(
                ignoring: true,
                child: DepartureCompletedControlButtons(
                  isSearchMode: false,
                  onResetSearch: () {},        // no-op
                  onShowSearchDialog: () {},   // no-op
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
