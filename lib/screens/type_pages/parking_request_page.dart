import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // PlateState 상태 관리
import '../../states/area_state.dart'; // AreaState 상태 관리
import '../../states/user_state.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 데이터를 표시하는 위젯
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바

/// 입차 요청 데이터를 표시하는 화면
class ParkingRequestPage extends StatelessWidget {
  const ParkingRequestPage({super.key});

  /// SnackBar로 메시지 출력
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 차량 번호판 클릭 시 선택 상태 변경
  void _handlePlateTap(BuildContext context, String plateNumber, String area) {
    final userName = context.read<UserState>().name; // UserState에서 사용자 이름 가져오기
    context.read<PlateState>().toggleIsSelected(
          collection: 'parking_requests',
          plateNumber: plateNumber,
          area: area,
          userName: userName, // userName 전달
        );
  }

  /// 선택된 차량 번호판을 입차 완료 상태로 업데이트
  void _handleParkingCompleted(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name; // 현재 사용자 이름 가져오기

    // 현재 선택된 번호판 가져오기
    final selectedPlate = plateState.getSelectedPlate('parking_requests', userName);
    if (selectedPlate != null) {
      plateState.setParkingCompleted(selectedPlate.plateNumber, selectedPlate.area);
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
          final currentArea = areaState.currentArea; // 현재 선택된 지역
          // 현재 지역의 입차 요청 데이터 가져오기
          final parkingRequests = plateState.getPlatesByArea('parking_requests', currentArea);

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: parkingRequests, // 입차 요청 데이터
                collection: 'parking_requests', // 컬렉션 이름
                filterCondition: (request) => request.type == '입차 요청' || request.type == '입차 중',
                onPlateTap: (plateNumber, area) {
                  _handlePlateTap(context, plateNumber, area); // 번호판 클릭 처리
                },
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Consumer<PlateState>(
        builder: (context, plateState, child) {
          // 현재 사용자 이름 가져오기
          final userName = context.read<UserState>().name;

          // 현재 선택된 번호판 가져오기
          final selectedPlate = plateState.getSelectedPlate('parking_requests', userName);

          return BottomNavigationBar(
            items: [
              BottomNavigationBarItem(
                icon: Icon(selectedPlate == null || !selectedPlate.isSelected ? Icons.search : Icons.highlight_alt),
                label: selectedPlate == null || !selectedPlate.isSelected ? '번호판 검색' : '정보 수정',
              ),
              BottomNavigationBarItem(
                icon:
                    Icon(selectedPlate == null || !selectedPlate.isSelected ? Icons.local_parking : Icons.check_circle),
                label: selectedPlate == null || !selectedPlate.isSelected ? '구역별 검색' : '입차 완료',
              ),
              BottomNavigationBarItem(
                icon: Icon(selectedPlate == null || !selectedPlate.isSelected ? Icons.sort : Icons.sort_by_alpha),
                label: selectedPlate == null || !selectedPlate.isSelected ? '정렬' : '정렬 완료',
              ),
            ],
            onTap: (index) {
              if (index == 1 && selectedPlate != null && selectedPlate.isSelected) {
                _handleParkingCompleted(context); // 입차 완료 처리
              }
            },
          );
        },
      ),
    );
  }
}
