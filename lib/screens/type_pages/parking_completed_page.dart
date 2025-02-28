import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // PlateState 상태 관리
import '../../states/area_state.dart'; // AreaState 상태 관리
import '../../states/user_state.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바

/// 입차 완료 리스트를 표시하는 화면
class ParkingCompletedPage extends StatefulWidget {
  const ParkingCompletedPage({super.key});

  @override
  State<ParkingCompletedPage> createState() => _ParkingCompletedPageState();
}

class _ParkingCompletedPageState extends State<ParkingCompletedPage> {
  bool _isSorted = true; // 정렬 아이콘 상태 (최신순: true, 오래된순: false)
  bool _isSearchMode = false; // 검색 모드 여부

  /// 🔹 정렬 상태 변경
  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });
  }

  /// 🔹 검색 아이콘 상태 변경
  void _toggleSearchIcon() {
    setState(() {
      _isSearchMode = !_isSearchMode;
    });
  }

  /// 🔹 출차 요청 처리
  void _handleDepartureRequested(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;
    final selectedPlate = plateState.getSelectedPlate('parking_completed', userName);

    if (selectedPlate != null) {
      plateState.setDepartureRequested(selectedPlate.plateNumber, selectedPlate.area);

      // ✅ 상태 변경 후 선택 해제
      plateState.toggleIsSelected(
        collection: 'parking_completed',
        plateNumber: selectedPlate.plateNumber,
        area: selectedPlate.area,
        userName: userName,
        onError: (errorMessage) {
          debugPrint("toggleIsSelected 실패: $errorMessage");
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopNavigation(),
      body: Consumer2<PlateState, AreaState>(
        builder: (context, plateState, areaState, child) {
          final currentArea = areaState.currentArea;
          var parkingCompleted = plateState.getPlatesByArea('parking_completed', currentArea);
          final userName = context.read<UserState>().name;

          // 🔹 정렬 적용 (최신순 or 오래된순)
          parkingCompleted.sort((a, b) {
            return _isSorted
                ? b.requestTime.compareTo(a.requestTime)
                : a.requestTime.compareTo(b.requestTime);
          });

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: parkingCompleted,
                collection: 'parking_completed',
                filterCondition: (request) => request.type == '입차 완료',
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
          final selectedPlate = plateState.getSelectedPlate('parking_completed', context.read<UserState>().name);

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
                  selectedPlate == null || !selectedPlate.isSelected
                      ? Icons.local_parking
                      : Icons.check_circle,
                ),
                label: selectedPlate == null || !selectedPlate.isSelected ? '주차 구역' : '출차 요청',
              ),
              BottomNavigationBarItem(
                icon: AnimatedRotation(
                  turns: _isSorted ? 0.5 : 0.0, // ✅ 최신순일 때 180도 회전
                  duration: const Duration(milliseconds: 300),
                  child: Transform.scale(
                    scaleX: _isSorted ? -1 : 1, // ✅ 좌우 반전
                    child: Icon(
                      selectedPlate != null && selectedPlate.isSelected ? Icons.arrow_forward : Icons.sort,
                    ),
                  ),
                ),
                label: selectedPlate != null && selectedPlate.isSelected
                    ? '이동'
                    : (_isSorted ? '최신순' : '오래된순'), // ✅ 최신순/오래된순 표시
              ),
            ],
            onTap: (index) {
              if (index == 0) {
                if (selectedPlate == null || !selectedPlate.isSelected) {
                  _toggleSearchIcon(); // 🔹 검색 상태 토글
                }
              } else if (index == 1 && selectedPlate != null && selectedPlate.isSelected) {
                _handleDepartureRequested(context);
              } else if (index == 2) {
                if (selectedPlate == null || !selectedPlate.isSelected) {
                  _toggleSortIcon();
                }
              }
            },
          );
        },
      ),
    );
  }
}
