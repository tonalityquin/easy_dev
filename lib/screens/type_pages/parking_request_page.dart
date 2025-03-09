import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // PlateState 상태 관리
import '../../states/area_state.dart'; // AreaState 상태 관리
import '../../states/user_state.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 데이터를 표시하는 위젯
import '../../widgets/dialog/parking_request_delete_dialog.dart';
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바
import '../../widgets/dialog/plate_search_dialog.dart';
import '../../utils/show_snackbar.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../repositories/plate_repository.dart';

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
    context.read<PlateState>().clearPlateSearchQuery();
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
  /// 🔹 선택된 차량을 입차 완료 처리 (주차 구역 선택 Dialog 적용)
  void _handleParkingCompleted(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;
    final selectedPlate = plateState.getSelectedPlate('parking_requests', userName);

    if (selectedPlate != null) {
      // ✅ 주차 구역 선택 Dialog 표시
      final TextEditingController locationController = TextEditingController();
      showDialog(
        context: context,
        builder: (context) {
          return ParkingLocationDialog(
            locationController: locationController,
            onLocationSelected: (String location) {
              if (location.isNotEmpty) {
                _completeParking(context, selectedPlate.plateNumber, selectedPlate.area, location);
              } else {
                showSnackbar(context, '주차 구역을 입력해주세요.');
              }
            },
          );
        },
      );
    }
  }

  /// 🔹 주차 구역을 반영하여 '입차 완료' 처리
  void _completeParking(BuildContext context, String plateNumber, String area, String location) {
    final plateState = context.read<PlateState>();
    final plateRepository = context.read<PlateRepository>();

    try {
      // ✅ Firestore 업데이트
      plateRepository.addRequestOrCompleted(
        collection: 'parking_completed',
        plateNumber: plateNumber,
        location: location,
        // 선택한 주차 구역 반영
        area: area,
        userName: context.read<UserState>().name,
        type: '입차 완료',
        adjustmentType: null,
        memoList: [],
        basicStandard: 0,
        basicAmount: 0,
        addStandard: 0,
        addAmount: 0,
      );

      // ✅ PlateState에서 '입차 요청' → '입차 완료'로 이동
      plateState.movePlateToCompleted(plateNumber, location);

      showSnackbar(context, "입차 완료: $plateNumber ($location)");
    } catch (e) {
      debugPrint("입차 완료 처리 실패: $e");
      showSnackbar(context, "입차 완료 처리 중 오류 발생: $e");
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
            return _isSorted ? b.entryTime.compareTo(a.entryTime) : a.entryTime.compareTo(b.entryTime);
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
                  icon: isPlateSelected
                      ? Icon(Icons.check_circle, color: Colors.green)
                      : Image.asset(
                    'assets/icons/icon_belivussnc.PNG',  // ✅ 파일 경로 확인
                    width: 24.0,
                    height: 24.0,
                    fit: BoxFit.contain,  // ✅ 이미지 왜곡 방지
                  ),
                  label: isPlateSelected ? '입차 완료' : 'Belivus S&C',
                ),
                BottomNavigationBarItem(
                  icon: AnimatedRotation(
                    turns: _isSorted ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Transform.rotate(
                      angle: 3.1416, // 180도 회전
                      child: Icon(
                        isPlateSelected ? Icons.delete : Icons.sort,
                      ),
                    ),
                  ),
                  label: isPlateSelected ? '입차 취소' : (_isSorted ? '최신순' : '오래된순'),
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
                  _handleParkingCompleted(context); // ✅ 입차 완료 처리
                } else if (index == 2) {
                  if (isPlateSelected) {
                    // ✅ 다이얼로그 표시하여 삭제 여부 확인
                    showDialog(
                      context: context,
                      builder: (context) {
                        return ParkingRequestDeleteDialog(
                          onConfirm: () {
                            context
                                .read<PlateState>()
                                .deletePlateFromParkingRequest(selectedPlate.plateNumber, selectedPlate.area);
                            showSnackbar(context, "삭제 완료: ${selectedPlate.plateNumber}");
                          },
                        );
                      },
                    );
                  } else {
                    _toggleSortIcon();
                  }
                }
              });
        },
      ),
    );
  }
}
