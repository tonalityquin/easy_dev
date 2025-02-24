import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // 번호판 상태 관리
import '../../states/area_state.dart'; // 지역 상태 관리
import '../../states/user_state.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바

/// 출차 요청 페이지
/// - 출차 요청된 차량 목록을 표시하고 출차 완료 처리
class DepartureRequestPage extends StatefulWidget {
  const DepartureRequestPage({super.key});

  @override
  State<DepartureRequestPage> createState() => _DepartureRequestPageState();
}

class _DepartureRequestPageState extends State<DepartureRequestPage> {
  bool _isSorted = true; // 정렬 아이콘 상태 (상하 반전 여부)

  /// 메시지를 SnackBar로 출력
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });
  }

  /// 출차 완료 처리
  void _handleDepartureCompleted(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name; // 현재 사용자 이름 가져오기

    // 현재 선택된 번호판 가져오기
    final selectedPlate = plateState.getSelectedPlate('departure_requests', userName);
    if (selectedPlate != null) {
      plateState.setDepartureCompleted(selectedPlate.plateNumber, selectedPlate.area);

      _showSnackBar(context, '출차 완료가 완료되었습니다.');
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
          final departureRequests = plateState.getPlatesByArea('departure_requests', currentArea);
          final userName = context.read<UserState>().name; // 현재 사용자 이름 가져오기

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: departureRequests, // 출차 요청 데이터
                collection: 'departure_requests', // 컬렉션 이름
                filterCondition: (request) => request.type == '출차 요청' || request.type == '출차 중',
                onPlateTap: (plateNumber, area) {
                  plateState.toggleIsSelected(
                    collection: 'departure_requests',
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
          final selectedPlate = plateState.getSelectedPlate('departure_requests', context.read<UserState>().name);

          return BottomNavigationBar(
            items: [
              BottomNavigationBarItem(
                icon: Icon(selectedPlate == null || !selectedPlate.isSelected ? Icons.search : Icons.highlight_alt),
                label: selectedPlate == null || !selectedPlate.isSelected ? '번호판 검색' : '정보 수정',
              ),
              BottomNavigationBarItem(
                icon:
                    Icon(selectedPlate == null || !selectedPlate.isSelected ? Icons.local_parking : Icons.check_circle),
                label: selectedPlate == null || !selectedPlate.isSelected ? '주차 구역' : '출차 완료',
              ),
              BottomNavigationBarItem(
                icon: AnimatedRotation(
                  turns: _isSorted ? 0.5 : 0.0, // 180도 회전 (0.5 턴)
                  duration: const Duration(milliseconds: 300), // 부드러운 애니메이션
                  child: Transform.scale(
                    scaleX: _isSorted ? -1 : 1, // _isSorted = true → 좌우 반전 / false → 정상
                    child: Icon(Icons.sort),
                  ),
                ),
                label: selectedPlate == null || !selectedPlate.isSelected ? '정렬' : '강제 이동',
              ),
            ],
            onTap: (index) {
              if (index == 1 && selectedPlate != null && selectedPlate.isSelected) {
                _handleDepartureCompleted(context); // 출차 완료 처리
              } else if (index == 2) {
                _toggleSortIcon(); // 정렬 아이콘 반전
              }
            },
          );
        },
      ),
    );
  }
}
