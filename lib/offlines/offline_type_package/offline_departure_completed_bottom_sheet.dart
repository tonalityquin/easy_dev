// lib/offlines/offline_type_package/offline_departure_completed_bottom_sheet.dart
//
// 리팩터링 요약
// - Provider 의존 제거(OfflineFieldSelectedDateState/CalendarState 사용 안 함)
// - division/area 는 SQLite(offline_auth_db/offline_auth_service)에서 로드
// - 선택 날짜(selectedDate)는 호출부에서 주입 받아 내부 상태로 관리(+/- 버튼으로 변경)
// - 날짜 바 위젯도 Provider 미사용 버전으로 교체 및 selectedDate 직접 전달

import 'package:flutter/material.dart';

// ▼ 탭/상단 위젯 (변경 없음)
import 'offline_departure_completed_package/offline_departure_completed_tab_settled.dart';
import 'offline_departure_completed_package/offline_departure_completed_tab_unsettled.dart';
import 'offline_departure_completed_package/widgets/offline_departure_completed_selected_date_bar.dart';

// ▼ SQLite / 세션
import '../sql/offline_auth_db.dart';
import '../sql/offline_auth_service.dart';

class OfflineDepartureCompletedBottomSheet extends StatefulWidget {
  const OfflineDepartureCompletedBottomSheet({
    super.key,
    required this.selectedDate,
  });

  /// 호출부에서 주입하는 선택 날짜(yyyy-MM-dd 기준)
  final DateTime selectedDate;

  @override
  State<OfflineDepartureCompletedBottomSheet> createState() =>
      _OfflineDepartureCompletedBottomSheetState();
}

class _OfflineDepartureCompletedBottomSheetState
    extends State<OfflineDepartureCompletedBottomSheet> {
  late DateTime _date; // 내부 표시/쿼리용 날짜 상태

  @override
  void initState() {
    super.initState();
    _date = DateTime(widget.selectedDate.year, widget.selectedDate.month, widget.selectedDate.day);
  }

  Future<(String division, String area)> _loadDivisionAndArea() async {
    final db = await OfflineAuthDb.instance.database;
    final s = await OfflineAuthService.instance.currentSession();
    final uid = (s?.userId ?? '').trim();

    String division = '';
    String area = '';

    // 1) 현재 사용자 우선
    if (uid.isNotEmpty) {
      final r1 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['division', 'currentArea', 'selectedArea'],
        where: 'userId = ?',
        whereArgs: [uid],
        limit: 1,
      );
      if (r1.isNotEmpty) {
        final row = r1.first;
        division = ((row['division'] as String?) ?? '').trim();
        area = ((row['currentArea'] as String?) ?? (row['selectedArea'] as String?) ?? '').trim();
      }
    }

    // 2) 없으면 isSelected=1 폴백
    if (division.isEmpty || area.isEmpty) {
      final r2 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['division', 'currentArea', 'selectedArea'],
        where: 'isSelected = 1',
        limit: 1,
      );
      if (r2.isNotEmpty) {
        final row = r2.first;
        division = division.isNotEmpty ? division : (((row['division'] as String?) ?? '').trim());
        if (area.isEmpty) {
          area = ((row['currentArea'] as String?) ?? (row['selectedArea'] as String?) ?? '').trim();
        }
      }
    }

    return (division, area);
  }

  DateTime _stripDate(DateTime d) => DateTime(d.year, d.month, d.day);

  void _goPrevDay() => setState(() => _date = _stripDate(_date.subtract(const Duration(days: 1))));
  void _goNextDay() => setState(() => _date = _stripDate(_date.add(const Duration(days: 1))));

  @override
  Widget build(BuildContext context) {
    const plateNumber = ''; // Settled 탭 라벨 용(실제 SQLite엔 불필요)

    return FutureBuilder<(String division, String area)>(
      future: _loadDivisionAndArea(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 320,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snap.hasData) {
          return const SizedBox(
            height: 200,
            child: Center(child: Text('계정 영역 정보를 불러올 수 없습니다.')),
          );
        }

        final division = snap.data!.$1;
        final area = snap.data!.$2;

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
                          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            // 날짜 바 (표시 전용 + 이전/다음 이동)
                            OfflineDepartureCompletedSelectedDateBar(
                              visible: !isSettled,
                              selectedDate: _date,
                              onPrev: _goPrevDay,
                              onNext: _goNextDay,
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  OfflineDepartureCompletedTabUnsettled(
                                    area: area,
                                    selectedDate: _date,
                                  ),
                                  OfflineDepartureCompletedTabSettled(
                                    area: area,
                                    division: division,
                                    selectedDate: _date,
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
      },
    );
  }
}
