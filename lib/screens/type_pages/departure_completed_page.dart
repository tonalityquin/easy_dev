import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/plate_repository.dart';
import '../../states/plate_state.dart';
import '../../states/area_state.dart';
import '../../states/user_state.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바

/// 출차 완료 페이지
/// - 출차 완료된 차량 데이터를 관리
/// - 로그아웃 및 데이터 삭제 기능 포함
class DepartureCompletedPage extends StatelessWidget {
  const DepartureCompletedPage({super.key});

  /// 메시지를 SnackBar로 출력
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 모든 데이터 삭제
  Future<void> _deleteAllData(BuildContext context) async {
    final plateRepository = Provider.of<PlateRepository>(context, listen: false);
    try {
      await plateRepository.deleteAllData();
      _showSnackBar(context, '모든 문서가 삭제되었습니다. 컬렉션은 유지됩니다.');
    } catch (e) {
      _showSnackBar(context, '문서 삭제 실패: $e');
    }
  }

  /// 로그아웃 처리
  Future<void> _logout(BuildContext context) async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);
      await userState.clearUser();

      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login'); // 로그인 페이지로 이동
      }
    } catch (e) {
      _showSnackBar(context, '로그아웃 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const TopNavigation(), // 상단 내비게이션
        backgroundColor: Colors.blue,
        actions: [
          // 로그아웃 버튼
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
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
          final currentArea = areaState.currentArea; // 현재 지역
          final departureCompleted = plateState.getPlatesByArea('departure_completed', currentArea);
          final userName = context.read<UserState>().name; // 현재 사용자 이름 가져오기

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: departureCompleted, // 출차 완료된 차량 데이터
                collection: 'departure_completed', // 컬렉션 이름
                filterCondition: (_) => true, // 필터 조건
                onPlateTap: (plateNumber, area) {
                  plateState.toggleIsSelected(
                    collection: 'departure_completed',
                    plateNumber: plateNumber,
                    area: area,
                    userName: userName, // userName 전달
                  );
                },
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Consumer<PlateState>(
        builder: (context, plateState, child) {
          // 현재 선택된 번호판 가져오기
          final selectedPlate = plateState.getSelectedPlate('departure_completed', context.read<UserState>().name);

          return BottomNavigationBar(
            items: [
              BottomNavigationBarItem(
                icon: Icon(selectedPlate == null || !selectedPlate.isSelected ? Icons.search : Icons.highlight_alt),
                label: selectedPlate == null || !selectedPlate.isSelected ? '번호판 검색' : '정보 수정',
              ),
              BottomNavigationBarItem(
                icon: Icon(selectedPlate == null || !selectedPlate.isSelected ? Icons.local_parking : Icons.check_circle),
                label: selectedPlate == null || !selectedPlate.isSelected ? '주차 구역' : '출차 완료',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.sort),
                label: '정렬',
              ),
            ],
            onTap: (index) {
              if (index == 1 && selectedPlate != null && selectedPlate.isSelected) {
                // 출차 완료 처리
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
