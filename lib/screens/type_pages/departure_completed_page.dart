import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../screens/logs/plate_log_viewer_page.dart';
import '../../states/plate/filter_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';
import '../../widgets/container/plate_container.dart';
import '../../widgets/navigation/top_navigation.dart';
import '../../widgets/dialog/plate_search_dialog.dart';
import '../../widgets/dialog/adjustment_completed_confirm_dialog.dart';
import '../../utils/snackbar_helper.dart';
import '../input_pages/modify_plate_info.dart';
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
                ? context.read<FilterPlate>().filterByParkingLocation('departure_completed', areaState.currentArea, _selectedParkingArea!)
                : plateState.getPlatesByCollection('departure_completed');

            departureCompleted.sort((a, b) => _isSorted
                ? b.requestTime.compareTo(a.requestTime)
                : a.requestTime.compareTo(b.requestTime));

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
                        ? const Icon(Icons.highlight_alt, key: ValueKey('highlight'), color: Colors.indigo)
                        : Icon(
                      _isSearchMode ? Icons.cancel : Icons.search,
                      key: ValueKey(_isSearchMode),
                      color: _isSearchMode ? Colors.orange : Colors.grey,
                    ),
                  ),
                  label: isPlateSelected ? '정보 수정' : (_isSearchMode ? '검색 초기화' : '번호판 검색'),
                ),
                BottomNavigationBarItem(
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
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
                        ? const Icon(Icons.menu_book, key: ValueKey('log'))
                        : const Icon(Icons.calendar_today, key: ValueKey('calendar'), color: Colors.grey),
                  ),
                  label: isPlateSelected ? '로그 확인' : '달력 열기',
                ),
              ],
              onTap: (index) async {
                if (index == 0) {
                  if (isPlateSelected) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ModifyPlateInfo(
                          plate: selectedPlate,
                          collectionKey: 'departure_completed',
                        ),
                      ),
                    );
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
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlateLogViewerPage(initialPlateNumber: selectedPlate.plateNumber),
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