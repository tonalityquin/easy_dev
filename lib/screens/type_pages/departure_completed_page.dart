import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../states/plate/filter_plate.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';
import '../../widgets/container/plate_container.dart';
import '../../widgets/navigation/top_navigation.dart';
import '../../widgets/dialog/plate_search_dialog.dart';
import '../../utils/show_snackbar.dart';

class DepartureCompletedPage extends StatefulWidget {
  const DepartureCompletedPage({super.key});

  @override
  State<DepartureCompletedPage> createState() => _DepartureCompletedPageState();
}

class _DepartureCompletedPageState extends State<DepartureCompletedPage> {
  bool _isSearchMode = false;

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
      showSnackbar(context, '모든 문서가 삭제되었습니다. 컬렉션은 유지됩니다.');
    } catch (e) {
      showSnackbar(context, '문서 삭제 실패: $e');
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
              collection: 'departure_completed', // 💡 실제 사용하는 컬렉션 이름으로 변경
              plateNumber: selectedPlate.plateNumber,
              userName: userName,
              onError: (msg) => debugPrint(msg),
            );
            return false;
          }
          return true;
        },
        child: Scaffold(
          appBar: AppBar(
            title: const TopNavigation(),
            backgroundColor: Colors.blue,
            actions: [
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () async {
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
                },
              ),
            ],
          ),
          body: Consumer2<PlateState, AreaState>(
            builder: (context, plateState, areaState, child) {
              final departureCompleted = plateState.getPlatesByCollection('departure_completed');
              return ListView(
                padding: const EdgeInsets.all(8.0),
                children: [
                  PlateContainer(
                    data: departureCompleted,
                    collection: 'departure_completed',
                    filterCondition: (_) => true,
                    onPlateTap: (plateNumber, area) {
                      plateState.toggleIsSelected(
                        collection: 'departure_completed',
                        plateNumber: plateNumber,
                        userName: '',
                        onError: (errorMessage) {
                          showSnackbar(context, errorMessage);
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
              final movementPlate = context.read<MovementPlate>(); // ✅ MovementPlate 사용
              final selectedPlate = plateState.getSelectedPlate('departure_completed', '');
              return BottomNavigationBar(
                items: [
                  BottomNavigationBarItem(
                    icon: Icon(
                      selectedPlate == null || !selectedPlate.isSelected
                          ? (_isSearchMode ? Icons.cancel : Icons.search)
                          : Icons.highlight_alt,
                    ),
                    label: selectedPlate == null || !selectedPlate.isSelected
                        ? (_isSearchMode ? '검색 초기화' : '번호판 검색')
                        : '정보 수정',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(
                      selectedPlate == null || !selectedPlate.isSelected ? Icons.local_parking : Icons.check_circle,
                    ),
                    label: selectedPlate == null || !selectedPlate.isSelected ? '주차 구역' : '출차 완료',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.sort),
                    label: '정렬',
                  ),
                ],
                onTap: (index) {
                  if (index == 0) {
                    if (_isSearchMode) {
                      _resetSearch(context);
                    } else {
                      _showSearchDialog(context);
                    }
                  } else if (index == 1 && selectedPlate != null && selectedPlate.isSelected) {
                    showSnackbar(context, '출차 완료가 완료되었습니다.');
                    movementPlate.setDepartureCompleted(
                        selectedPlate.plateNumber, selectedPlate.area, plateState, selectedPlate.location);
                  }
                },
              );
            },
          ),
        ));
  }
}
