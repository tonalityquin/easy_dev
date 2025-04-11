import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../states/calendar/field_selected_date_state.dart';
import '../../states/plate/filter_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';
import '../../utils/fee_calculator.dart';
import '../../widgets/container/plate_container.dart';
import '../../widgets/dialog/departure_completed_status_dialog.dart';
import '../../widgets/navigation/top_navigation.dart';
import '../../widgets/dialog/plate_search_dialog.dart';
import '../../widgets/dialog/adjustment_completed_confirm_dialog.dart';
import '../../utils/snackbar_helper.dart';
import '../mini_calendars/field_calendar.dart';
import '../../enums/plate_type.dart';

class DepartureCompletedPage extends StatefulWidget {
  const DepartureCompletedPage({super.key});

  @override
  State<DepartureCompletedPage> createState() => _DepartureCompletedPageState();
}

class _DepartureCompletedPageState extends State<DepartureCompletedPage> {
  final bool _isSorted = true;
  final bool _isLoading = false;
  bool _isSearchMode = false;

  bool _hasCalendarBeenReset = false;

  void _showSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return PlateSearchDialog(
          onSearch: (query) {
            _filterPlatesByNumber(context, query);
          },
        );
      },
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

  Future<void> _deleteAllData(BuildContext context) async {
    final plateRepository = Provider.of<PlateRepository>(context, listen: false);
    try {
      await plateRepository.deleteAllData();

      if (!context.mounted) return;
      showSuccessSnackbar(context, '모든 문서가 삭제되었습니다. 컬렉션은 유지됩니다.');
    } catch (e) {
      if (!context.mounted) return;
      showFailedSnackbar(context, '문서 삭제 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;

    return PopScope(
      canPop: true,
      // ignore: deprecated_member_use
      onPopInvoked: (didPop) async {
        if (!didPop) return;
        final selectedPlate = plateState.getSelectedPlate(PlateType.departureCompleted, userName);
        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await plateState.toggleIsSelected(
            collection: PlateType.departureCompleted,
            plateNumber: selectedPlate.plateNumber,
            userName: userName,
            onError: (msg) => debugPrint(msg),
          );
        }
      },
      child: Scaffold(
        appBar: const TopNavigation(),
        body: Consumer3<PlateState, AreaState, FieldSelectedDateState>(
          builder: (context, plateState, areaState, selectedDateState, child) {
            final selectedDate = selectedDateState.selectedDate ?? DateTime.now();
            final area = areaState.currentArea;

            // 🔍 날짜 & 지역 기준으로 출차 완료 Plate 필터링
            final departureCompleted = plateState.getPlatesByCollection(PlateType.departureCompleted).where((p) {
              final endTime = p.endTime;
              return p.type == '출차 완료' &&
                  endTime != null &&
                  p.area == area &&
                  endTime.year == selectedDate.year &&
                  endTime.month == selectedDate.month &&
                  endTime.day == selectedDate.day;
            }).toList();

            // ✅ 정렬 처리
            departureCompleted.sort(
              (a, b) => _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime),
            );

            return _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(8.0),
                    children: [
                      PlateContainer(
                        data: departureCompleted,
                        collection: PlateType.departureCompleted,
                        filterCondition: (_) => true, // 이미 위에서 필터링 완료됨
                        onPlateTap: (plateNumber, area) {
                          plateState.toggleIsSelected(
                            collection: PlateType.departureCompleted,
                            plateNumber: plateNumber,
                            userName: context.read<UserState>().name,
                            onError: (errorMessage) {
                              showFailedSnackbar(context, errorMessage);
                            },
                          );
                        },
                      ),
                    ],
                  );
          },
        ),
        bottomNavigationBar: Consumer<PlateState>(
          builder: (context, plateState, child) {
            final selectedPlate = plateState.getSelectedPlate(PlateType.departureCompleted, userName);
            final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;
            final selectedDate = context.watch<FieldSelectedDateState>().selectedDate ?? DateTime.now(); // ← null 대비
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
                    child: isPlateSelected
                        ? const Icon(
                            Icons.check_circle,
                            key: ValueKey('selected'),
                            color: Colors.green,
                          )
                        : const Icon(
                            Icons.delete_forever,
                            key: ValueKey('delete'),
                            color: Colors.redAccent,
                          ),
                  ),
                  label: isPlateSelected ? '요금 정산' : '전체 삭제',
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
                    final now = DateTime.now();
                    final entryTime = selectedPlate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;
                    final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;

                    if (selectedPlate.isLockedFee) {
                      // ❌ 정산 취소 불가능 (departure_completed는 정산 완료 상태로 간주)
                      showFailedSnackbar(context, '정산 완료된 항목은 취소할 수 없습니다.');
                      return;
                    }

                    // ✅ 사전 정산 수행
                    final lockedFee = calculateParkingFee(
                      entryTimeInSeconds: entryTime,
                      currentTimeInSeconds: currentTime,
                      basicStandard: selectedPlate.basicStandard ?? 0,
                      basicAmount: selectedPlate.basicAmount ?? 0,
                      addStandard: selectedPlate.addStandard ?? 0,
                      addAmount: selectedPlate.addAmount ?? 0,
                    ).round();

                    final updatedPlate = selectedPlate.copyWith(
                      isLockedFee: true,
                      lockedAtTimeInSeconds: currentTime,
                      lockedFeeAmount: lockedFee,
                    );

                    await context.read<PlateRepository>().addOrUpdateDocument(
                          'departure_completed',
                          selectedPlate.id,
                          updatedPlate.toMap(),
                        );

                    if (!context.mounted) return;
                    await context.read<PlateState>().updatePlateLocally(PlateType.departureCompleted, updatedPlate);

                    if (!context.mounted) return;
                    showSuccessSnackbar(context, '사전 정산 완료: ₩$lockedFee');
                  } else {
                    _isSearchMode ? _resetSearch(context) : _showSearchDialog(context);
                  }
                } else if (index == 1) {
                  if (isPlateSelected) {
                    showDialog(
                      context: context,
                      builder: (context) => AdjustmentCompletedConfirmDialog(
                        onConfirm: () {
                          showSuccessSnackbar(context, "정산 완료 처리가 실행되었습니다."); // 이후 실제 처리 로직 연결
                        },
                      ),
                    );
                  } else {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: const Text('모든 데이터 삭제'),
                          content: const Text('정말로 모든 데이터를 삭제하시겠습니까?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('취소'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('확인'),
                            ),
                          ],
                        );
                      },
                    );
                    if (confirm == true) {
                      if (!context.mounted) return;
                      await _deleteAllData(context);
                    }
                  }
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
                      // ✅ 첫 클릭: 오늘 날짜로 리셋만 함
                      context.read<FieldSelectedDateState>().setSelectedDate(DateTime.now());
                      setState(() {
                        _hasCalendarBeenReset = true;
                      });
                    } else {
                      // ✅ 두 번째 클릭: 달력 페이지 이동
                      setState(() {
                        _hasCalendarBeenReset = false; // 초기화
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
      ),
    );
  }
}
