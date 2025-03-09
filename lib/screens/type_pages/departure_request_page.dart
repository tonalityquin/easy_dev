import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // 번호판 상태 관리
import '../../states/area_state.dart'; // 지역 상태 관리
import '../../states/user_state.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/dialog/departure_completed_confirm_dialog.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바
import '../../widgets/dialog/plate_search_dialog.dart'; // ✅ PlateSearchDialog 추가
import '../../widgets/dialog/departure_request_status_dialog.dart';
import '../../widgets/dialog/parking_request_delete_dialog.dart';
import '../../utils/show_snackbar.dart';

/// 출차 요청 페이지
/// - 출차 요청된 차량 목록을 표시하고 출차 완료 처리
class DepartureRequestPage extends StatefulWidget {
  const DepartureRequestPage({super.key});

  @override
  State<DepartureRequestPage> createState() => _DepartureRequestPageState();
}

class _DepartureRequestPageState extends State<DepartureRequestPage> {
  bool _isSorted = true; // 정렬 아이콘 상태 (최신순: true, 오래된순: false)
  bool _isSearchMode = false; // 검색 모드 여부
  bool _isParkingAreaMode = false; // ✅ 주차 구역 필터 모드 여부
  String? _selectedParkingArea; // ✅ 선택된 주차 구역
  final TextEditingController _locationController = TextEditingController(); // ✅ 추가

  /// 🔹 정렬 상태 변경
  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });
  }

  /// 🔹 검색 다이얼로그 표시
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
      context.read<PlateState>().setSearchQuery(query);
      setState(() {
        _isSearchMode = true;
      });
    }
  }

  /// 🔹 주차 구역 선택 다이얼로그 표시
  void _showParkingAreaDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => ParkingLocationDialog(
        locationController: _locationController,
        onLocationSelected: (selectedLocation) {
          debugPrint("✅ 선택된 주차 구역: $selectedLocation");

          setState(() {
            _isParkingAreaMode = true;
            _selectedParkingArea = selectedLocation;
          });

          final area = context.read<AreaState>().currentArea; // ✅ 현재 지역 가져오기

          // ✅ 주차 구역 선택 시 출차 요청 차량 목록을 필터링
          setState(() {
            context.read<PlateState>().filterByParkingArea('departure_requests', area, _selectedParkingArea!);
          });
        },
      ),
    );
  }

  /// 🔹 주차 구역 필터링 초기화
  void _resetParkingAreaFilter(BuildContext context) {
    debugPrint("🔄 주차 구역 초기화 실행됨");
    setState(() {
      _isParkingAreaMode = false;
      _selectedParkingArea = null;
    });

    // 🔹 전체 출차 요청 데이터를 다시 불러옴
    context.read<PlateState>().clearLocationSearchQuery();
  }

  /// 🔹 검색 초기화
  void _resetSearch(BuildContext context) {
    context.read<PlateState>().clearPlateSearchQuery();
    setState(() {
      _isSearchMode = false;
    });
  }

  /// 🔹 출차 완료 처리
  void _handleDepartureCompleted(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;
    final selectedPlate = plateState.getSelectedPlate('departure_requests', userName);

    if (selectedPlate != null) {
      try {
        // ✅ 선택 해제를 먼저 실행 (UI 반영 속도 향상)
        plateState.toggleIsSelected(
          collection: 'departure_requests',
          plateNumber: selectedPlate.plateNumber,
          area: selectedPlate.area,
          userName: userName,
          onError: (errorMessage) {
            debugPrint("toggleIsSelected 실패: $errorMessage");
            showSnackbar(context, "선택 해제에 실패했습니다. 다시 시도해주세요."); // ✅ showSnackbar 유틸 적용
          },
        );

        // ✅ 출차 완료 처리
        plateState.setDepartureCompleted(selectedPlate.plateNumber, selectedPlate.area);
        showSnackbar(context, "출차 완료 처리되었습니다."); // ✅ showSnackbar 유틸 적용
      } catch (e) {
        debugPrint("출차 완료 처리 실패: $e");
        showSnackbar(context, "출차 완료 처리 중 오류 발생: $e"); // ✅ showSnackbar 유틸 적용
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

          var departureRequests = _isParkingAreaMode && _selectedParkingArea != null
              ? plateState.filterByParkingArea(
                  'departure_requests', currentArea, _selectedParkingArea!) // ✅ 주차 구역 필터링 적용
              : plateState.getPlatesByArea('departure_requests', currentArea);

          final userName = context.read<UserState>().name;

          // 🔹 정렬 적용 (최신순 or 오래된순)
          departureRequests.sort((a, b) {
            return _isSorted ? b.entryTime.compareTo(a.entryTime) : a.entryTime.compareTo(b.entryTime);
          });

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: departureRequests,
                collection: 'departure_requests',
                filterCondition: (request) => request.type == '출차 요청' || request.type == '출차 중',
                onPlateTap: (plateNumber, area) {
                  plateState.toggleIsSelected(
                    collection: 'departure_requests',
                    plateNumber: plateNumber,
                    area: area,
                    userName: userName,
                    onError: (errorMessage) {
                      showSnackbar(context, errorMessage);
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
          final userName = context.read<UserState>().name;
          final selectedPlate = plateState.getSelectedPlate('departure_requests', userName);
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
                  label: isPlateSelected ? '출차 완료' : (_isParkingAreaMode ? '주차 구역 초기화' : '주차 구역'),
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
                  label: isPlateSelected ? '상태 수정' : (_isSorted ? '최신순' : '오래된순'),
                ),
              ],
              onTap: (index) {
                if (index == 0) {
                  if (_isSearchMode) {
                    _resetSearch(context);
                  } else {
                    _showSearchDialog(context);
                  }
                } else if (index == 1) {
                  if (isPlateSelected) {
                    showDialog(
                      context: context,
                      builder: (context) => DepartureCompletedConfirmDialog(
                        onConfirm: () => _handleDepartureCompleted(context),
                      ),
                    );
                  } else {
                    if (_isParkingAreaMode) {
                      _resetParkingAreaFilter(context);
                    } else {
                      _showParkingAreaDialog(context);
                    }
                  }
                } else if (index == 2) {
                  if (isPlateSelected) {
                    showDialog(
                      context: context,
                      builder: (context) => DepartureRequestStatusDialog(
                        onRequestEntry: () {
                          // ✅ '입차 요청' 상태로 변경 (departure_requests → parking_requests)
                          handleEntryRequestFromDeparture(context, selectedPlate.plateNumber, selectedPlate.area);
                        },
                        onCompleteDeparture: () {
                          // ✅ '입차 완료' 상태로 변경
                          handleParkingCompletedFromDeparture(context, selectedPlate.plateNumber, selectedPlate.area);
                        },
                        onDelete: () {
                          showDialog(
                            context: context,
                            builder: (context) => ParkingRequestDeleteDialog(
                              onConfirm: () {
                                context.read<PlateState>().deletePlateFromDepartureRequest(
                                      selectedPlate.plateNumber,
                                      selectedPlate.area,
                                    );
                                showSnackbar(context, "삭제 완료: ${selectedPlate.plateNumber}");
                              },
                            ),
                          );
                        },
                      ),
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
