import 'package:easydev/utils/gcs_json_uploader.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../enums/plate_type.dart';

import '../../states/plate/filter_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';
import '../../states/calendar/field_selected_date_state.dart';

import '../../utils/snackbar_helper.dart';

import '../../widgets/navigation/top_navigation.dart';
import '../../widgets/container/plate_container.dart';
import '../../widgets/dialog/plate_search_dialog.dart';
import 'departure_completed_pages/field_calendar.dart';

import 'departure_completed_pages/widgets/departure_completed_page_merge_log.dart';
import 'departure_completed_pages/departure_completed_control_buttons.dart';

class DepartureCompletedPage extends StatefulWidget {
  const DepartureCompletedPage({super.key});

  @override
  State<DepartureCompletedPage> createState() => _DepartureCompletedPageState();
}

class _DepartureCompletedPageState extends State<DepartureCompletedPage> {
  final bool _isSorted = true;
  bool _isSearchMode = false;
  bool _hasCalendarBeenReset = false;
  bool _showMergedLog = false;

  void _showSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => PlateSearchDialog(
        onSearch: (query) => _filterPlatesByNumber(context, query),
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

  @override
  Widget build(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;
    final areaState = context.watch<AreaState>();

    final division = areaState.currentDivision;
    final area = areaState.currentArea.trim();
    final selectedDateRaw = context.watch<FieldSelectedDateState>().selectedDate ?? DateTime.now();
    final selectedDate = DateTime(selectedDateRaw.year, selectedDateRaw.month, selectedDateRaw.day);

    final rawPlates = context
        .watch<PlateState>()
        .getPlatesByCollection(PlateType.departureCompleted, selectedDate: selectedDate)
        .where((p) {
      final isSearching = context.read<FilterPlate>().searchQuery.length == 4;
      if (isSearching) {
        return p.area.trim() == area; // 검색 중엔 잠금 무시
      } else {
        return !p.isLockedFee && p.area.trim() == area; // 기본 필터
      }
    }).toList();

    final firestorePlates = context.watch<FilterPlate>().filterPlateCountByQuery(rawPlates);

    firestorePlates.sort((a, b) =>
    _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime));

    return WillPopScope(
      onWillPop: () async {
        if (_showMergedLog) {
          setState(() => _showMergedLog = false);
          return false;
        }

        final selectedPlate = plateState.getSelectedPlate(
          PlateType.departureCompleted,
          userName,
        );

        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await plateState.togglePlateIsSelected(
            collection: PlateType.departureCompleted,
            plateNumber: selectedPlate.plateNumber,
            userName: userName,
            onError: (msg) => debugPrint(msg),
          );
          return false;
        }

        return false; // 기본적으로 뒤로가기 비허용
      },
      child: Scaffold(
        appBar: AppBar(
          title: const TopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(8.0),
              children: [
                PlateContainer(
                  data: firestorePlates,
                  collection: PlateType.departureCompleted,
                  filterCondition: (_) => true,
                  onPlateTap: (plateNumber, area) {
                    plateState.togglePlateIsSelected(
                      collection: PlateType.departureCompleted,
                      plateNumber: plateNumber,
                      userName: userName,
                      onError: (msg) => showFailedSnackbar(context, msg),
                    );
                  },
                ),
              ],
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              bottom: _showMergedLog ? 0 : -600,
              left: 0,
              right: 0,
              height: 400,
              child: Container(
                color: Colors.white,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: GcsJsonUploader().showMergedLogsToDepartureCompletedMergeLog(division, area, filterDate: selectedDate),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Center(child: Text("병합 로그 로딩 실패"));
                    }

                    final mergedLogs = snapshot.data ?? [];

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Align(alignment: Alignment.centerRight),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            child: MergedLogSection(
                              mergedLogs: mergedLogs,
                              division: division,
                              area: area,
                              selectedDate: selectedDate,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: DepartureCompletedControlButtons(
          isSearchMode: _isSearchMode,
          isSorted: _isSorted,
          showMergedLog: _showMergedLog,
          hasCalendarBeenReset: _hasCalendarBeenReset,
          onResetSearch: () => _resetSearch(context),
          onShowSearchDialog: () => _showSearchDialog(context),
          onToggleMergedLog: () => setState(() => _showMergedLog = !_showMergedLog),
          onToggleCalendar: () {
            if (!_hasCalendarBeenReset) {
              context.read<FieldSelectedDateState>().setSelectedDate(DateTime.now());
              setState(() => _hasCalendarBeenReset = true);
            } else {
              setState(() => _hasCalendarBeenReset = false);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FieldCalendarPage()),
              );
            }
          },
        ),
      ),
    );
  }
}