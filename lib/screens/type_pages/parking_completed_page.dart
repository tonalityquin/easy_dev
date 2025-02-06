import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // PlateState 상태 관리
import '../../states/area_state.dart'; // AreaState 상태 관리
import '../../states/user_state.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바

/// 입차 완료 리스트를 표시하는 화면
class ParkingCompletedPage extends StatelessWidget {
  const ParkingCompletedPage({super.key});

  /// SnackBar로 메시지 출력
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 출차 요청 처리
  void _handleDepartureRequested(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name; // 현재 사용자 이름 가져오기

    // 현재 선택된 번호판 가져오기
    final selectedPlate = plateState.getSelectedPlate('parking_completed', userName);
    if (selectedPlate != null) {
      plateState.setDepartureRequested(selectedPlate.plateNumber, selectedPlate.area);
      _showSnackBar(context, '출차 요청이 완료되었습니다.');
    } else {
      _showSnackBar(context, '먼저 차량을 선택하세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopNavigation(), // 상단 내비게이션
      body: Consumer2<PlateState, AreaState>(
        builder: (context, plateState, areaState, child) {
          final currentArea = areaState.currentArea; // 현재 지역
          final parkingCompleted = plateState.getPlatesByArea('parking_completed', currentArea);
          final userName = context.read<UserState>().name; // 현재 사용자 이름 가져오기

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: parkingCompleted, // 입차 완료 데이터
                collection: 'parking_completed', // 컬렉션 이름
                filterCondition: (_) => true, // 필터 조건
                onPlateTap: (plateNumber, area) {
                  plateState.toggleIsSelected(
                    collection: 'parking_completed',
                    plateNumber: plateNumber,
                    area: area,
                    userName: userName,
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
          // 현재 선택된 번호판 가져오기
          final selectedPlate = plateState.getSelectedPlate('parking_completed', context.read<UserState>().name);

          return BottomNavigationBar(
            items: [
              BottomNavigationBarItem(
                icon: Icon(selectedPlate == null || !selectedPlate.isSelected ? Icons.search : Icons.highlight_alt),
                label: selectedPlate == null || !selectedPlate.isSelected ? '번호판 검색' : '정보 수정',
              ),
              BottomNavigationBarItem(
                icon:
                    Icon(selectedPlate == null || !selectedPlate.isSelected ? Icons.local_parking : Icons.check_circle),
                label: selectedPlate == null || !selectedPlate.isSelected ? '주차 구역' : '출차 요청',
              ),
              BottomNavigationBarItem(
                icon: Icon(selectedPlate == null || !selectedPlate.isSelected ? Icons.sort : Icons.sort_by_alpha),
                label: selectedPlate == null || !selectedPlate.isSelected ? '정렬' : '정렬 완료',
              ),
            ],
            onTap: (index) {
              if (index == 1 && selectedPlate != null && selectedPlate.isSelected) {
                _handleDepartureRequested(context); // 출차 요청 처리
              }
            },
          );
        },
      ),
    );
  }
}
