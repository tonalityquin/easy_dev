import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../states/calendar/field_selected_date_state.dart';
import '../../states/plate/filter_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';
import '../../utils/gcs_uploader.dart';
import '../../widgets/container/plate_container.dart';
import '../../widgets/dialog/adjustment_type_confirm_dialog.dart';
import '../../widgets/dialog/departure_completed_status_dialog.dart';
import '../../widgets/dialog/plate_search_dialog.dart';
import '../../widgets/navigation/top_navigation.dart';
import '../../utils/snackbar_helper.dart';
import '../mini_calendars/field_calendar.dart';
import '../../enums/plate_type.dart';
import 'departure_completed_pages/departure_completed_page_merge_log.dart';

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
        .where((p) => !p.isLockedFee && p.area.trim() == area)
        .toList();

    final firestorePlates = context.watch<FilterPlate>().filterPlatesByQuery(rawPlates);

    firestorePlates
        .sort((a, b) => _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime));

    return Scaffold(
      appBar: AppBar(
        title: const TopNavigation(), // ✅ title로만 사용
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
                  plateState.toggleIsSelected(
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
                future: GCSUploader().fetchMergedLogsForArea(division, area, filterDate: selectedDate),
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
                        child: Align(
                          alignment: Alignment.centerRight,
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: MergedLogSection(mergedLogs: mergedLogs),
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
      bottomNavigationBar: Consumer<PlateState>(
        builder: (context, plateState, child) {
          final selectedPlate = plateState.getSelectedPlate(PlateType.departureCompleted, userName);
          final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;
          final selectedDate = context.watch<FieldSelectedDateState>().selectedDate ?? DateTime.now();
          final formattedDate =
              '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';

          return BottomNavigationBar(
            items: [
              BottomNavigationBarItem(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                  child: isPlateSelected
                      ? (selectedPlate.isLockedFee
                          ? const Icon(Icons.lock_open, key: ValueKey('unlock'), color: Colors.grey)
                          : const Icon(Icons.lock, key: ValueKey('lock'), color: Colors.grey))
                      : Icon(
                          _isSearchMode ? Icons.cancel : Icons.search,
                          key: ValueKey(_isSearchMode),
                          color: _isSearchMode ? Colors.orange : Colors.grey,
                        ),
                ),
                label: isPlateSelected
                    ? (selectedPlate.isLockedFee ? '정산 취소' : '사전 정산')
                    : (_isSearchMode ? '검색 초기화' : '번호판 검색'),
              ),
              BottomNavigationBarItem(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    _showMergedLog ? Icons.expand_more : Icons.list_alt,
                    key: ValueKey(_showMergedLog),
                    color: Colors.grey,
                  ),
                ),
                label: _showMergedLog ? '감추기' : '병합 로그',
              ),
              BottomNavigationBarItem(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                  child: isPlateSelected
                      ? const Icon(Icons.settings, key: ValueKey('setting'))
                      : const Icon(Icons.calendar_today, key: ValueKey('calendar'), color: Colors.grey),
                ),
                label: isPlateSelected ? '상태 수정' : formattedDate,
              ),
            ],
            onTap: (index) async {
              if (index == 0) {
                if (isPlateSelected) {
                  final adjustmentType = selectedPlate.adjustmentType;

                  // ✅ 정산 타입 필수 확인
                  if (adjustmentType == null || adjustmentType.trim().isEmpty) {
                    showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
                    return;
                  }

                  final now = DateTime.now();
                  final entryTime = selectedPlate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;
                  final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;

                  if (selectedPlate.isLockedFee) {
                    showFailedSnackbar(context, '정산 완료된 항목은 취소할 수 없습니다.');
                    return;
                  }

                  // ✅ 정산 다이얼로그 호출
                  final result = await showAdjustmentTypeConfirmDialog(
                    context: context,
                    entryTimeInSeconds: entryTime,
                    currentTimeInSeconds: currentTime,
                    basicStandard: selectedPlate.basicStandard ?? 0,
                    basicAmount: selectedPlate.basicAmount ?? 0,
                    addStandard: selectedPlate.addStandard ?? 0,
                    addAmount: selectedPlate.addAmount ?? 0,
                  );

                  if (result == null) return;

                  final updatedPlate = selectedPlate.copyWith(
                    isLockedFee: true,
                    lockedAtTimeInSeconds: currentTime,
                    lockedFeeAmount: result.lockedFee,
                    paymentMethod: result.paymentMethod,
                  );

                  await context.read<PlateRepository>().addOrUpdatePlate(
                    selectedPlate.id,
                    updatedPlate,
                  );

                  if (!context.mounted) return;
                  await context.read<PlateState>().updatePlateLocally(PlateType.departureCompleted, updatedPlate);

                  if (!context.mounted) return;
                  showSuccessSnackbar(context, '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})');
                } else {
                  _isSearchMode ? _resetSearch(context) : _showSearchDialog(context);
                }
              } else if (index == 1) {
                // 🔁 병합 로그 toggle
                setState(() {
                  _showMergedLog = !_showMergedLog;
                });
              } else if (index == 2) {
                if (isPlateSelected) {
                  showDialog(
                    context: context,
                    builder: (context) => DepartureCompletedStatusDialog(
                      plate: selectedPlate,
                      plateNumber: selectedPlate.plateNumber,
                      area: selectedPlate.area,
                      onDelete: () {},
                    ),
                  );
                } else {
                  if (!_hasCalendarBeenReset) {
                    context.read<FieldSelectedDateState>().setSelectedDate(DateTime.now());
                    setState(() {
                      _hasCalendarBeenReset = true;
                    });
                  } else {
                    setState(() {
                      _hasCalendarBeenReset = false;
                    });
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const FieldCalendarPage()),
                    );
                  }
                }
              }
            },
          );
        },
      ),
    );
  }
}
