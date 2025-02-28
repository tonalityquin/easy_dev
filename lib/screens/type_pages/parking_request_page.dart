import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // PlateState 상태 관리
import '../../states/area_state.dart'; // AreaState 상태 관리
import '../../states/user_state.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 데이터를 표시하는 위젯
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바
import '../../widgets/dialog/plate_search_dialog.dart';
import '../../utils/show_snackbar.dart';

class ParkingRequestPage extends StatefulWidget {
  const ParkingRequestPage({super.key});

  @override
  State<ParkingRequestPage> createState() => _ParkingRequestPageState();
}

class _ParkingRequestPageState extends State<ParkingRequestPage> {
  bool _isSorted = true; // 정렬 아이콘 상태 (최신순: true, 오래된순: false)
  bool _isSearchMode = false; // 검색 모드 여부

  /// 🔹 정렬 상태 변경 (최신순 <-> 오래된순)
  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });
  }

  /// 🔹 검색 다이얼로그 표시 (NumKeypad 적용)
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
      context.read<PlateState>().setSearchQuery(query); // ✅ `filterByLastFourDigits()` → `setSearchQuery()` 변경
      setState(() {
        _isSearchMode = true;
      });
    }
  }

  /// 🔹 검색 초기화
  void _resetSearch(BuildContext context) {
    context.read<PlateState>().clearSearchQuery();
    setState(() {
      _isSearchMode = false;
    });
  }

  /// 🔹 차량 번호판 클릭 시 선택 상태 변경
  void _handlePlateTap(BuildContext context, String plateNumber, String area) {
    final userName = context.read<UserState>().name;
    context.read<PlateState>().toggleIsSelected(
          collection: 'parking_requests',
          plateNumber: plateNumber,
          area: area,
          userName: userName,
          onError: (errorMessage) {
            showSnackbar(context, errorMessage);
          },
        );
  }

  /// 🔹 선택된 차량 번호판을 입차 완료 상태로 업데이트
  void _handleParkingCompleted(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;
    final selectedPlate = plateState.getSelectedPlate('parking_requests', userName);

    if (selectedPlate != null) {
      try {
        // ✅ 선택 해제 먼저 실행
        plateState.toggleIsSelected(
          collection: 'parking_requests',
          plateNumber: selectedPlate.plateNumber,
          area: selectedPlate.area,
          userName: userName,
          onError: (errorMessage) {
            debugPrint("toggleIsSelected 실패: $errorMessage");
            showSnackbar(context, "선택 해제에 실패했습니다. 다시 시도해주세요.");
          },
        );

        // ✅ 입차 완료 처리
        plateState.setParkingCompleted(selectedPlate.plateNumber, selectedPlate.area);
        showSnackbar(context, "입차 완료 처리되었습니다."); // ✅ showSnackbar 적용
      } catch (e) {
        debugPrint("입차 완료 처리 실패: $e");
        showSnackbar(context, "입차 완료 처리 중 오류 발생: $e"); // ✅ showSnackbar 적용
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopNavigation(),
      body: Consumer2<PlateState, AreaState>(
        builder: (context, plateState, areaState, child) {
          final currentArea = areaState.currentArea;
          var parkingRequests = plateState.getPlatesByArea('parking_requests', currentArea);

          // 🔹 정렬 적용 (최신순 or 오래된순)
          parkingRequests.sort((a, b) {
            return _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime);
          });

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: parkingRequests,
                collection: 'parking_requests',
                filterCondition: (request) => request.type == '입차 요청' || request.type == '입차 중',
                onPlateTap: (plateNumber, area) {
                  _handlePlateTap(context, plateNumber, area);
                },
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Consumer<PlateState>(
        builder: (context, plateState, child) {
          final userName = context.read<UserState>().name;
          final selectedPlate = plateState.getSelectedPlate('parking_requests', userName);
          final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;

          return BottomNavigationBar(
            items: [
              BottomNavigationBarItem(
                icon: Icon(
                  isPlateSelected ? Icons.highlight_alt : (_isSearchMode ? Icons.cancel : Icons.search),
                ),
                label: isPlateSelected ? '정보 수정' : (_isSearchMode ? '검색 초기화' : '번호판 검색'),
              ),
              BottomNavigationBarItem(
                icon: Icon(
                  isPlateSelected ? Icons.check_circle : Icons.local_parking,
                  color: isPlateSelected ? Colors.green : Colors.grey, // ✅ 비활성화 색상 적용
                ),
                label: isPlateSelected ? '입차 완료' : '구역별 검색',
              ),
              BottomNavigationBarItem(
                icon: AnimatedRotation(
                  turns: _isSorted ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Transform.scale(
                    scaleX: _isSorted ? -1 : 1,
                    child: Icon(
                      isPlateSelected ? Icons.arrow_forward : Icons.sort,
                    ),
                  ),
                ),
                label: isPlateSelected ? '이동' : (_isSorted ? '최신순' : '오래된순'),
              ),
            ],
            onTap: (index) {
              if (index == 0) {
                if (_isSearchMode) {
                  _resetSearch(context);
                } else {
                  _showSearchDialog(context);
                }
              } else if (index == 1 && isPlateSelected) {
                _handleParkingCompleted(context);
              } else if (index == 2) {
                if (!isPlateSelected) {
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
