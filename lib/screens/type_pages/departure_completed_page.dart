import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/plate_repository.dart';
import '../../states/plate_state.dart';
import '../../states/area_state.dart';
import '../../widgets/container/plate_container.dart';
import '../../widgets/navigation/top_navigation.dart';
import '../../widgets/dialog/plate_search_dialog.dart';
import '../../utils/show_snackbar.dart'; // ✅ showSnackbar 유틸 추가

/// 출차 완료 페이지
class DepartureCompletedPage extends StatefulWidget {
  const DepartureCompletedPage({super.key});

  @override
  State<DepartureCompletedPage> createState() => _DepartureCompletedPageState();
}

class _DepartureCompletedPageState extends State<DepartureCompletedPage> {
  bool _isSearchMode = false; // 검색 모드 여부

  /// 🔹 검색 다이얼로그 표시
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

  /// 🔹 plate_number에서 마지막 4자리 필터링
  void _filterPlatesByNumber(BuildContext context, String query) {
    if (query.length == 4) {
      context.read<PlateState>().setSearchQuery(query);
      setState(() {
        _isSearchMode = true;
      });
    }
  }

  /// 🔹 검색 초기화
  void _resetSearch(BuildContext context) {
    context.read<PlateState>().clearPlateSearchQuery();
    setState(() {
      _isSearchMode = false;
    });
  }

  /// 🔹 모든 데이터 삭제
  Future<void> _deleteAllData(BuildContext context) async {
    final plateRepository = Provider.of<PlateRepository>(context, listen: false);
    try {
      await plateRepository.deleteAllData();
      showSnackbar(context, '모든 문서가 삭제되었습니다. 컬렉션은 유지됩니다.'); // ✅ showSnackbar 유틸 적용
    } catch (e) {
      showSnackbar(context, '문서 삭제 실패: $e'); // ✅ showSnackbar 유틸 적용
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          final currentArea = areaState.currentArea;
          final departureCompleted = plateState.getPlatesByArea('departure_completed', currentArea);

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
                    area: area,
                    userName: '',
                    onError: (errorMessage) {
                      showSnackbar(context, errorMessage); // ✅ showSnackbar 유틸 적용
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
                  _resetSearch(context); // ✅ 검색 초기화
                } else {
                  _showSearchDialog(context); // ✅ 검색 다이얼로그 표시
                }
              } else if (index == 1 && selectedPlate != null && selectedPlate.isSelected) {
                showSnackbar(context, '출차 완료가 완료되었습니다.'); // ✅ showSnackbar 유틸 적용
                plateState.setDepartureCompleted(selectedPlate.plateNumber, selectedPlate.area);
              }
            },
          );
        },
      ),
    );
  }
}
