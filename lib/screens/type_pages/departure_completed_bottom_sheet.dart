import 'package:easydev/utils/gcs_json_uploader.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../states/plate/filter_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';
import '../../states/calendar/field_selected_date_state.dart';

import '../../utils/snackbar_helper.dart';

import '../../widgets/container/plate_container.dart';
import '../../widgets/dialog/common_plate_search_bottom_sheet/common_plate_search_bottom_sheet.dart';
import 'departure_completed_pages/field_calendar.dart';
import 'departure_completed_pages/widgets/departure_completed_page_merge_log.dart';
import 'departure_completed_pages/departure_completed_control_buttons.dart';
import 'departure_completed_pages/widgets/departure_completed_page_today_log.dart';

// ✅ 상태 수정 바텀시트 import 추가
import 'departure_completed_pages/widgets/departure_completed_status_bottom_sheet.dart';

class DepartureCompletedBottomSheet extends StatefulWidget {
  const DepartureCompletedBottomSheet({super.key});

  @override
  State<DepartureCompletedBottomSheet> createState() => _DepartureCompletedBottomSheetState();
}

class _DepartureCompletedBottomSheetState extends State<DepartureCompletedBottomSheet> {
  final bool _isSorted = true;
  bool _isSearchMode = false;

  @override
  void initState() {
    super.initState();
  }

  void _showSearchDialog(BuildContext context) {
    final currentArea = context.read<AreaState>().currentArea;

    showDialog(
      context: context,
      builder: (context) => CommonPlateSearchBottomSheet(
        onSearch: (query) => _filterPlatesByNumber(context, query),
        area: currentArea,
      ),
    );
  }

  void _filterPlatesByNumber(BuildContext context, String query) {
    if (query.length == 4) {
      context.read<FilterPlate>().setPlateSearchQuery(query);
      setState(() {
        _isSearchMode = true;
      });
    }
  }

  void _resetSearch(BuildContext context) {
    context.read<FilterPlate>().clearPlateSearchQuery();
    setState(() {
      _isSearchMode = false;
    });
  }

  bool _areaEquals(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final plateState = context.watch<PlateState>();
    final userName = context.read<UserState>().name;
    final areaState = context.watch<AreaState>();
    final filterState = context.watch<FilterPlate>();

    final division = areaState.currentDivision;
    final area = areaState.currentArea.trim();
    final selectedDateRaw = context.watch<FieldSelectedDateState>().selectedDate ?? DateTime.now();
    final selectedDate = DateTime(selectedDateRaw.year, selectedDateRaw.month, selectedDateRaw.day);

    // 날짜(자정~자정) 필터까지 반영된 기본 리스트
    final baseList = plateState.getPlatesByCollection(
      PlateType.departureCompleted,
      selectedDate: selectedDate,
    );

    // 화면단 area/검색 필터
    final isSearching = filterState.searchQuery.isNotEmpty && filterState.searchQuery.length == 4;
    List<PlateModel> firestorePlates = baseList.where((p) {
      final sameArea = _areaEquals(p.area, area);
      if (isSearching) {
        return sameArea; // 검색 중엔 잠금 무시
      } else {
        return !p.isLockedFee && sameArea; // 일반 모드: 미정산만
      }
    }).toList();

    if (isSearching) {
      firestorePlates = firestorePlates.where((p) => p.plateFourDigit == filterState.searchQuery).toList();
    }

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
                  // 탭 콘텐츠
                  Expanded(
                    child: TabBarView(
                      children: [
                        // ───── 미정산 탭: 달력(고정) + 리스트(스크롤) ─────
                        Column(
                          children: [
                            // ✅ 상단 달력은 스크롤에서 제외(고정)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8.0),
                              child: FieldCalendarInline(),
                            ),
                            const SizedBox(height: 12),
                            // ✅ 달력 아래 영역만 스크롤
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.all(8.0),
                                children: [
                                  PlateContainer(
                                    data: firestorePlates,
                                    collection: PlateType.departureCompleted,
                                    filterCondition: (_) => true,
                                    onPlateTap: (plateNumber, area) async {
                                      // ✅ 선택 토글
                                      await plateState.togglePlateIsSelected(
                                        collection: PlateType.departureCompleted,
                                        plateNumber: plateNumber,
                                        userName: userName,
                                        onError: (msg) => showFailedSnackbar(context, msg),
                                      );
                                      // ✅ 토글 이후 현 선택 상태 확인
                                      final currentSelected = plateState.getSelectedPlate(
                                        PlateType.departureCompleted,
                                        userName,
                                      );
                                      // ✅ 선택되어 있으면 즉시 바텀시트 표시
                                      if (currentSelected != null &&
                                          currentSelected.isSelected &&
                                          currentSelected.plateNumber == plateNumber) {
                                        await showDepartureCompletedStatusBottomSheet(
                                          context: context,
                                          plate: currentSelected,
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // ───── 정산 탭: 상/하 1:1 영역 (각 스크롤) ─────
                        Builder(
                          builder: (context) {
                            // baseList: 이미 날짜(자정~자정) 필터 적용됨
                            final todayPlates = baseList.where((p) => _areaEquals(p.area, area)).toList();

                            // Firestore 문서 → TodayLogSection이 기대하는 맵 형태로 변환
                            final todayMergedItems = todayPlates.map<Map<String, dynamic>>((p) {
                              final List<dynamic> logsDyn = (p.logs as List?) ?? const <dynamic>[];

                              // mergedAt 후보: 로그 최신 timestamp → 없으면 endTime → updatedAt → requestTime
                              DateTime? newestFromLogs;
                              for (final l in logsDyn.whereType<Map<String, dynamic>>()) {
                                final ts = DateTime.tryParse((l['timestamp'] ?? '').toString());
                                if (ts != null && (newestFromLogs == null || ts.isAfter(newestFromLogs))) {
                                  newestFromLogs = ts;
                                }
                              }
                              final mergedAt = (newestFromLogs ?? p.endTime ?? p.updatedAt ?? p.requestTime);

                              return {
                                'plateNumber': p.plateNumber,
                                'mergedAt': mergedAt.toIso8601String(),
                                'logs': logsDyn,
                              };
                            }).toList()
                              ..sort((a, b) {
                                final aT =
                                    DateTime.tryParse(a['mergedAt'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
                                final bT =
                                    DateTime.tryParse(b['mergedAt'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
                                return bT.compareTo(aT);
                              });

                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                children: [
                                  // ⬆️ 상단 1/2: TodayLogSection (항상 렌더링)
                                  Expanded(
                                    child: ClipRect(
                                      child: Scrollbar(
                                        child: SingleChildScrollView(
                                          child: TodayLogSection(
                                            mergedLogs: todayMergedItems,
                                            division: division,
                                            area: area,
                                            selectedDate: selectedDate,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // ⬇️ 하단 1/2: MergedLogSection (항상 렌더링)
                                  Expanded(
                                    child: FutureBuilder<List<Map<String, dynamic>>>(
                                      future: plateNumber.isEmpty
                                          ? Future.value(<Map<String, dynamic>>[]) // 번호판 미선택: 빈 리스트
                                          : GcsJsonUploader().loadPlateLogs(
                                              plateNumber: plateNumber,
                                              division: division,
                                              area: area,
                                              date: selectedDate,
                                            ),
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState == ConnectionState.waiting) {
                                          return const Center(child: CircularProgressIndicator());
                                        }
                                        if (snapshot.hasError) {
                                          return const Center(child: Text("병합 로그 로딩 실패"));
                                        }
                                        final mergedLogs = snapshot.data ?? [];
                                        return ClipRect(
                                          child: Scrollbar(
                                            child: SingleChildScrollView(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  if (plateNumber.isEmpty)
                                                    const Padding(
                                                      padding: EdgeInsets.only(bottom: 8.0),
                                                      child: Center(
                                                        child: Text('번호판을 선택하면 상세 병합 로그를 불러옵니다.'),
                                                      ),
                                                    ),
                                                  MergedLogSection(
                                                    mergedLogs: mergedLogs,
                                                    division: division,
                                                    area: area,
                                                    selectedDate: selectedDate,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: DepartureCompletedControlButtons(
                isSearchMode: _isSearchMode,
                onResetSearch: () => _resetSearch(context),
                onShowSearchDialog: () => _showSearchDialog(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
