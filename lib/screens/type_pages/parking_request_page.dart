import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // PlateState 상태 관리
import '../../states/area_state.dart'; // AreaState 상태 관리
import '../../states/user_state.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 데이터를 표시하는 위젯
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바

/// 입차 요청 데이터를 표시하는 화면
class ParkingRequestPage extends StatefulWidget {
  const ParkingRequestPage({super.key});

  @override
  State<ParkingRequestPage> createState() => _ParkingRequestPageState();
}

class _ParkingRequestPageState extends State<ParkingRequestPage> {
  bool _isSorted = true; // 정렬 아이콘 상태 (상하 반전 여부)

  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });
  }

  /// 차량 번호판 클릭 시 선택 상태 변경
  void _handlePlateTap(BuildContext context, String plateNumber, String area) {
    final userName = context.read<UserState>().name; // UserState에서 사용자 이름 가져오기
    context.read<PlateState>().toggleIsSelected(
          collection: 'parking_requests',
          plateNumber: plateNumber,
          area: area,
          userName: userName,
          onError: (errorMessage) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errorMessage)), // 🚀 Firestore 요청 실패 시 UI 알림 추가
            );
          },
        );
  }

  /// 선택된 차량 번호판을 입차 완료 상태로 업데이트
  void _handleParkingCompleted(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;
    final selectedPlate = plateState.getSelectedPlate('parking_requests', userName);

    if (selectedPlate != null) {
      plateState.setParkingCompleted(selectedPlate.plateNumber, selectedPlate.area);

      // ✅ 상태 변경 후 선택 해제
      plateState.toggleIsSelected(
        collection: 'parking_requests',
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
          final currentArea = areaState.currentArea; // 현재 선택된 지역
          // 현재 지역의 입차 요청 데이터 가져오기
          var parkingRequests = plateState.getPlatesByArea('parking_requests', currentArea);

          // 🔹 정렬 적용 (최신순 or 오래된순)
          parkingRequests.sort((a, b) {
            return _isSorted
                ? b.requestTime.compareTo(a.requestTime) // 최신순 정렬
                : a.requestTime.compareTo(b.requestTime); // 오래된순 정렬
          });

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
                  icon: Icon(
                      selectedPlate == null || !selectedPlate.isSelected ? Icons.local_parking : Icons.check_circle),
                  label: selectedPlate == null || !selectedPlate.isSelected ? '구역별 검색' : '입차 완료',
                ),
                BottomNavigationBarItem(
                  icon: AnimatedRotation(
                    turns: _isSorted ? 0.5 : 0.0, // ✅ 최신순일 때 180도 회전
                    duration: const Duration(milliseconds: 300),
                    child: Transform.scale(
                      scaleX: _isSorted ? -1 : 1, // ✅ 좌우 반전 적용
                      child: Icon(
                        selectedPlate != null && selectedPlate.isSelected
                            ? Icons.arrow_forward // ✅ PlateContainer 선택 시 arrow_forward 아이콘 표시
                            : Icons.sort, // ✅ PlateContainer 미선택 시 sort 아이콘 유지
                      ),
                    ),
                  ),
                  label: selectedPlate != null && selectedPlate.isSelected ? '이동' : '정렬',
                ),
              ],
              onTap: (index) {
                if (index == 1 && selectedPlate != null && selectedPlate.isSelected) {
                  _handleParkingCompleted(context);
                } else if (index == 2) {
                  if (selectedPlate == null || !selectedPlate.isSelected) {
                    _toggleSortIcon(); // ✅ PlateContainer 미선택 시에만 실행 (정렬 동작)
                  }
                }
              });
        },
      ),
    );
  }
}
