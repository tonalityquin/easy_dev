import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/plate/plate_repository.dart';
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

class DepartureCompletedPage extends StatefulWidget {
  const DepartureCompletedPage({super.key});

  @override
  State<DepartureCompletedPage> createState() => _DepartureCompletedPageState();
}

class _DepartureCompletedPageState extends State<DepartureCompletedPage> {
  bool _isSearchMode = false;
  bool _isSorted = true;
  bool _isLoading = false;
  bool _isParkingAreaMode = false;
  String? _selectedParkingArea;

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
      showSuccessSnackbar(context, '모든 문서가 삭제되었습니다. 컬렉션은 유지됩니다.');
    } catch (e) {
      showFailedSnackbar(context, '문서 삭제 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;

    return WillPopScope(
      onWillPop: () async {
        final selectedPlate = plateState.getSelectedPlate('departure_completed', userName);
        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await plateState.toggleIsSelected(
            collection: 'departure_completed',
            plateNumber: selectedPlate.plateNumber,
            userName: userName,
            onError: (msg) => debugPrint(msg),
          );
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: const TopNavigation(),
        body: Consumer2<PlateState, AreaState>(
          builder: (context, plateState, areaState, child) {
            var departureCompleted = _isParkingAreaMode && _selectedParkingArea != null
                ? context
                    .read<FilterPlate>()
                    .filterByParkingLocation('departure_completed', areaState.currentArea, _selectedParkingArea!)
                : plateState.getPlatesByCollection('departure_completed');

            departureCompleted.sort(
                (a, b) => _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime));

            return _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(8.0),
                    children: [
                      PlateContainer(
                        data: departureCompleted,
                        collection: 'departure_completed',
                        filterCondition: (p) => p.type == '출차 완료',
                        onPlateTap: (plateNumber, area) {
                          plateState.toggleIsSelected(
                            collection: 'departure_completed',
                            plateNumber: plateNumber,
                            userName: userName,
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
            final selectedPlate = plateState.getSelectedPlate('departure_completed', userName);
            final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;

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
                  label: isPlateSelected ? '상태 수정' : '달력 열기',
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
                    );

                    await context.read<PlateRepository>().addOrUpdateDocument(
                          'departure_completed',
                          selectedPlate.id,
                          updatedPlate.toMap(),
                        );

                    await context.read<PlateState>().updatePlateLocally('departure_completed', updatedPlate);

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
                        onDelete: () {
                          // 삭제 다이얼로그 등 필요한 처리
                        },
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FieldCalendarPage(),
                      ),
                    );
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
