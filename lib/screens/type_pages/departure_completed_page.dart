import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/plate_repository.dart';
import '../../states/plate_state.dart';
import '../../states/area_state.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바

/// 출차 완료 페이지
/// - 출차 완료된 차량 데이터를 관리
/// - 데이터 삭제 기능 포함
class DepartureCompletedPage extends StatefulWidget {
  const DepartureCompletedPage({super.key});

  @override
  State<DepartureCompletedPage> createState() => _DepartureCompletedPageState();
}

class _DepartureCompletedPageState extends State<DepartureCompletedPage> {
  bool _isSearchMode = false; // 검색 모드 여부

  /// 🔹 검색 아이콘 상태 변경
  void _toggleSearchIcon() {
    setState(() {
      _isSearchMode = !_isSearchMode;
    });
  }

  /// 🔹 메시지를 SnackBar로 출력
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 🔹 모든 데이터 삭제
  Future<void> _deleteAllData(BuildContext context) async {
    final plateRepository = Provider.of<PlateRepository>(context, listen: false);
    try {
      await plateRepository.deleteAllData();
      _showSnackBar(context, '모든 문서가 삭제되었습니다. 컬렉션은 유지됩니다.');
    } catch (e) {
      _showSnackBar(context, '문서 삭제 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const TopNavigation(), // 상단 내비게이션
        backgroundColor: Colors.blue,
        actions: [
          // 데이터 삭제 버튼
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(errorMessage)),
                      );
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
                if (selectedPlate == null || !selectedPlate.isSelected) {
                  _toggleSearchIcon(); // 🔹 검색 상태 토글
                }
              } else if (index == 1 && selectedPlate != null && selectedPlate.isSelected) {
                _showSnackBar(context, '출차 완료가 완료되었습니다.');
                plateState.setDepartureCompleted(selectedPlate.plateNumber, selectedPlate.area);
              }
            },
          );
        },
      ),
    );
  }
}
