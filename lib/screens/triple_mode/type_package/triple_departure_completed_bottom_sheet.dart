import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../models/plate_model.dart';
import '../../../states/calendar/field_calendar_state.dart';
import '../../../states/area/area_state.dart';
import '../../../states/plate/triple_plate_state.dart';
import '../../../states/user/user_state.dart';

import 'departure_completed_package/triple_departure_completed_tab_settled.dart';
import 'departure_completed_package/triple_departure_completed_tab_unsettled.dart';
import 'departure_completed_package/widgets/triple_departure_completed_selected_date_bar.dart';

class TripleDepartureCompletedBottomSheet extends StatefulWidget {
  const TripleDepartureCompletedBottomSheet({super.key});

  @override
  State<TripleDepartureCompletedBottomSheet> createState() =>
      _TripleDepartureCompletedBottomSheetState();
}

class _TripleDepartureCompletedBottomSheetState
    extends State<TripleDepartureCompletedBottomSheet> {
  // 화면 식별 태그(FAQ/에러 리포트 연계용)
  static const String screenTag = 'departure completed';

  // 기존 로직 유지(현재 파일 내에서는 토글 UI 없음)
  final bool _isSorted = true;

  bool _areaEquals(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  // 좌측 상단(11시) 태그 위젯
  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    final style = (base ??
        TextStyle(
          fontSize: 11,
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ))
        .copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );

    return IgnorePointer(
      // 시트 제스처와의 간섭 방지
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

    final plateState = context.watch<TriplePlateState>();
    final userName = context.read<UserState>().name;
    final areaState = context.watch<AreaState>();

    final division = areaState.currentDivision;
    final area = areaState.currentArea.trim();

    final selectedDateRaw =
        context.watch<FieldSelectedDateState>().selectedDate ?? DateTime.now();
    final selectedDate =
    DateTime(selectedDateRaw.year, selectedDateRaw.month, selectedDateRaw.day);

    final baseList = plateState.tripleGetPlatesByCollection(
      PlateType.departureCompleted,
      selectedDate: selectedDate,
    );

    // ✅ 안전하게 bool? 대응: "미정산" 판정은 isLockedFee != true
    List<PlateModel> firestorePlates = baseList.where((p) {
      final sameArea = _areaEquals(p.area, area);
      return (p.isLockedFee != true) && sameArea;
    }).toList();

    firestorePlates.sort(
          (a, b) => _isSorted
          ? b.requestTime.compareTo(a.requestTime)
          : a.requestTime.compareTo(b.requestTime),
    );

    final selectedPlate = plateState.tripleGetSelectedPlate(
      PlateType.departureCompleted,
      userName,
    );
    final plateNumber = selectedPlate?.plateNumber ?? '';

    return WillPopScope(
      onWillPop: () async {
        // ✅ stale 캡처 방지: 뒤로가기 순간에 최신 selectedPlate 다시 조회
        final latestSelected = context.read<TriplePlateState>().tripleGetSelectedPlate(
          PlateType.departureCompleted,
          userName,
        );

        if (latestSelected != null && latestSelected.id.isNotEmpty) {
          await context.read<TriplePlateState>().tripleTogglePlateIsSelected(
            collection: PlateType.departureCompleted,
            plateNumber: latestSelected.plateNumber,
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
                                color: cs.outlineVariant.withOpacity(0.85),
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
                              labelColor: cs.onSurface,
                              unselectedLabelColor: cs.onSurfaceVariant,
                              indicatorColor: cs.primary,
                              dividerColor: Colors.transparent,
                              tabs: const [
                                Tab(text: '미정산'),
                                Tab(text: '정산'),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),

                          // 정산 탭에서는 날짜바 숨김(기존 정책 유지)
                          TripleDepartureCompletedSelectedDateBar(visible: !isSettled),

                          const SizedBox(height: 8),

                          Expanded(
                            child: TabBarView(
                              children: [
                                TripleDepartureCompletedUnsettledTab(
                                  firestorePlates: firestorePlates,
                                  userName: userName,
                                ),
                                TripleDepartureCompletedSettledTab(
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
