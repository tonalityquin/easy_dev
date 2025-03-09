import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // PlateState 상태 관리
import '../../states/area_state.dart'; // AreaState 상태 관리
import '../../states/user_state.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/dialog/departure_request_confirmation_dialog.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바
import '../../widgets/dialog/plate_search_dialog.dart'; // ✅ PlateSearchDialog 추가
import '../../widgets/dialog/parking_completed_status_dialog.dart';
import '../../widgets/dialog/parking_request_delete_dialog.dart';
import '../../utils/show_snackbar.dart';

/// 입차 완료 리스트를 표시하는 화면
class ParkingCompletedPage extends StatefulWidget {
  const ParkingCompletedPage({super.key});

  @override
  State<ParkingCompletedPage> createState() => _ParkingCompletedPageState();
}

class _ParkingCompletedPageState extends State<ParkingCompletedPage> {
  bool _isSorted = true; // 정렬 아이콘 상태 (최신순: true, 오래된순: false)
  bool _isSearchMode = false; // 검색 모드 여부
  bool _isParkingAreaMode = false; // 주차 구역 모드 여부
  String? _selectedParkingArea; // 선택된 주차 구역
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

          final area = context.read<AreaState>().currentArea; // ✅ 지역 가져오기

          // ✅ `filterByParkingArea()` 호출 시 `area`를 함께 전달하여 필터링 정확도 개선
          setState(() {
            context.read<PlateState>().filterByParkingArea('parking_completed', area, _selectedParkingArea!);
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

    // 🔹 번호판 검색 초기화 방식과 동일하게 전체 데이터를 다시 불러옴
    context.read<PlateState>().clearLocationSearchQuery();
  }

  /// 🔹 검색 초기화
  void _resetPlateSearch(BuildContext context) {
    context.read<PlateState>().clearPlateSearchQuery();
    setState(() {
      _isSearchMode = false;
    });
  }

  /// 🔹 출차 요청 처리
  void _handleDepartureRequested(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;
    final selectedPlate = plateState.getSelectedPlate('parking_completed', userName);

    if (selectedPlate != null) {
      try {
        // ✅ 먼저 출차 요청 상태로 변경 (Firestore 업데이트)
        plateState.setDepartureRequested(selectedPlate.plateNumber, selectedPlate.area).then((_) {
          // ✅ Firestore 업데이트 후 UI 안정화
          Future.delayed(Duration(milliseconds: 300), () {
            if (context.mounted) {
              Navigator.pop(context); // ✅ UI가 안정화된 후 다이얼로그 닫기
              showSnackbar(context, "출차 요청이 완료되었습니다.");
            }
          });
        });
      } catch (e) {
        debugPrint("출차 요청 처리 실패: $e");

        if (context.mounted) {
          showSnackbar(context, "출차 요청 처리 중 오류 발생: $e");
        }
      }
    }
  }

  void handleEntryRequest(BuildContext context, String plateNumber, String area) {
    final plateState = context.read<PlateState>();

    // 🔹 'parking_completed'에서 'parking_requests'로 plate 이동
    plateState.updatePlateStatus(
      plateNumber: plateNumber,
      area: area,
      fromCollection: 'parking_completed',
      toCollection: 'parking_requests',
      newType: '입차 요청',
    );

    // ✅ location을 `null`로 설정하여 기본값 "미지정"이 자동 적용되도록 함
    plateState.goBackToParkingRequest(plateNumber, null);

    // ✅ 완료 메시지 표시
    showSnackbar(context, "입차 요청이 완료되었습니다.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopNavigation(),
      body: Consumer2<PlateState, AreaState>(
        builder: (context, plateState, areaState, child) {
          final currentArea = areaState.currentArea;

          var parkingCompleted = _isParkingAreaMode && _selectedParkingArea != null
              ? plateState.filterByParkingArea('parking_completed', currentArea, _selectedParkingArea!) // ✅ `area` 반영
              : plateState.getPlatesByArea('parking_completed', currentArea);

          final userName = context.read<UserState>().name;

          parkingCompleted.sort((a, b) {
            return _isSorted ? b.entryTime.compareTo(a.entryTime) : a.entryTime.compareTo(b.entryTime);
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
          final selectedPlate = plateState.getSelectedPlate('parking_completed', userName);
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
                  label: isPlateSelected ? '출차 요청' : (_isParkingAreaMode ? '주차 구역 초기화' : '주차 구역'),
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
                    _resetPlateSearch(context);
                  } else {
                    _showSearchDialog(context);
                  }
                } else if (index == 1) {
                  if (isPlateSelected) {
                    showDialog(
                      context: context,
                      builder: (context) => DepartureRequestConfirmDialog(
                        onConfirm: () => _handleDepartureRequested(context),
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
                      builder: (context) => ParkingCompletedStatusDialog(
                        plateNumber: selectedPlate.plateNumber,
                        // ✅ plateNumber 전달
                        area: selectedPlate.area,
                        // ✅ 지역 정보 추가
                        onRequestEntry: () {
                          handleEntryRequest(context, selectedPlate.plateNumber, selectedPlate.area);
                        },
                        onCompleteDeparture: () {
                          // ✅ 출차 완료 로직 유지
                          _handleDepartureRequested(context);
                        },
                        onDelete: () {
                          showDialog(
                            context: context,
                            builder: (context) => ParkingRequestDeleteDialog(
                              onConfirm: () {
                                context.read<PlateState>().deletePlateFromParkingCompleted(
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
