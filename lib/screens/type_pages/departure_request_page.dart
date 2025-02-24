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
  bool _isSorted = true; // 정렬 아이콘 상태 (최신순: true, 오래된순: false)

  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });
  }

  /// 출차 완료 처리
  void _handleDepartureCompleted(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;
    final selectedPlate = plateState.getSelectedPlate('departure_requests', userName);

    if (selectedPlate != null) {
      plateState.setDepartureCompleted(selectedPlate.plateNumber, selectedPlate.area);

      // ✅ 상태 변경 후 선택 해제
      plateState.toggleIsSelected(
        collection: 'departure_requests',
        plateNumber: selectedPlate.plateNumber,
        area: selectedPlate.area,
        userName: userName,
        onError: (errorMessage) {
          debugPrint("toggleIsSelected 실패: $errorMessage"); // 에러 메시지를 콘솔에 출력
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopNavigation(), // 상단 내비게이션
      body: Consumer2<PlateState, AreaState>(
        builder: (context, plateState, areaState, child) {
          final currentArea = areaState.currentArea; // 현재 지역
          var departureRequests = plateState.getPlatesByArea('departure_requests', currentArea);
          final userName = context.read<UserState>().name; // 현재 사용자 이름 가져오기

          // 🔹 정렬 적용 (최신순 or 오래된순)
          departureRequests.sort((a, b) {
            return _isSorted
                ? b.requestTime.compareTo(a.requestTime) // 최신순 정렬
                : a.requestTime.compareTo(b.requestTime); // 오래된순 정렬
          });

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: departureRequests, // 정렬된 출차 요청 데이터
                collection: 'departure_requests',
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
          final selectedPlate = plateState.getSelectedPlate('departure_requests', context.read<UserState>().name);

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
              BottomNavigationBarItem(
                icon: AnimatedRotation(
                  turns: _isSorted ? 0.5 : 0.0, // ✅ 최신순일 때 180도 회전
                  duration: const Duration(milliseconds: 300), // 부드러운 애니메이션
                  child: Transform.scale(
                    scaleX: _isSorted ? -1 : 1, // ✅ 좌우 반전 적용
                    child: Icon(
                      selectedPlate != null && selectedPlate.isSelected
                          ? Icons.arrow_forward // ✅ PlateContainer 선택 시 arrow_forward 아이콘 표시
                          : Icons.sort, // ✅ PlateContainer 미선택 시 sort 아이콘 유지
                    ),
                  ),
                ), // ✅ 콤마 추가하여 오류 수정
                label: selectedPlate != null && selectedPlate.isSelected ? '이동' : '정렬',
              ),
            ],
            onTap: (index) {
              if (index == 1 && selectedPlate != null && selectedPlate.isSelected) {
                _handleDepartureCompleted(context);
              } else if (index == 2) {
                if (selectedPlate == null || !selectedPlate.isSelected) {
                  _toggleSortIcon(); // ✅ PlateContainer 미선택 시에만 실행 (정렬 동작)
                }
              }
            },
          );
        },
      ),
    );
  }
}
