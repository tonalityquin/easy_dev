import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate/plate_state.dart'; // PlateState 상태 관리
import '../../states/plate/delete_plate.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/area/area_state.dart'; // AreaState 상태 관리
import '../../states/user/user_state.dart';
import '../../states/plate/filter_state.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/dialog/departure_request_confirmation_dialog.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바
import '../../widgets/dialog/plate_search_dialog.dart'; // ✅ PlateSearchDialog 추가
import '../../widgets/dialog/parking_completed_status_dialog.dart';
import '../../widgets/dialog/parking_request_delete_dialog.dart';
import '../../utils/show_snackbar.dart';

class ParkingCompletedPage extends StatefulWidget {
  const ParkingCompletedPage({super.key});

  @override
  State<ParkingCompletedPage> createState() => _ParkingCompletedPageState();
}

class _ParkingCompletedPageState extends State<ParkingCompletedPage> {
  bool _isSorted = true;
  bool _isSearchMode = false;
  bool _isParkingAreaMode = false;
  String? _selectedParkingArea;
  final TextEditingController _locationController = TextEditingController();

  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });
  }

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

  void _filterPlatesByNumber(BuildContext context, String query) {
    if (query.length == 4) {
      context.read<FilterState>().setPlateSearchQuery(query);
      setState(() {
        _isSearchMode = true;
      });
    }
  }

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
          final area = context.read<AreaState>().currentArea;
          setState(() {
            context.read<FilterState>().filterByParkingLocation('parking_completed', area, _selectedParkingArea!);
          });
        },
      ),
    );
  }

  void _resetParkingAreaFilter(BuildContext context) {
    debugPrint("🔄 주차 구역 초기화 실행됨");
    setState(() {
      _isParkingAreaMode = false;
      _selectedParkingArea = null;
    });
    context.read<FilterState>().clearLocationSearchQuery();
  }

  void _resetPlateSearch(BuildContext context) {
    context.read<FilterState>().clearPlateSearchQuery();
    setState(() {
      _isSearchMode = false;
    });
  }

  void _handleDepartureRequested(BuildContext context) {
    final movementPlate = context.read<MovementPlate>(); // ✅ MovementPlate 사용
    final userName = context.read<UserState>().name;
    final plateState = context.read<PlateState>();
    final selectedPlate = plateState.getSelectedPlate('parking_completed', userName);

    if (selectedPlate != null) {
      try {
        movementPlate.setDepartureRequested(selectedPlate.plateNumber, selectedPlate.area).then((_) {
          // ✅ MovementPlate에서 호출
          Future.delayed(Duration(milliseconds: 300), () {
            if (context.mounted) {
              Navigator.pop(context);
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
    final movementPlate = context.read<MovementPlate>(); // ✅ MovementPlate 사용

    movementPlate.goBackToParkingRequest(
      fromCollection: 'parking_completed', // 🔥 fromCollection을 명시적으로 지정
      plateNumber: plateNumber,
      area: area,
      newLocation: "미지정", // ❓ 선택적으로 위치 변경 가능
    );

    showSnackbar(context, "입차 요청이 완료되었습니다.");
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopNavigation(),
      body: Consumer2<PlateState, AreaState>(
        builder: (context, plateState, areaState, child) {
          final currentArea = areaState.currentArea;
          final filterState = context.read<FilterState>();
          var parkingCompleted = _isParkingAreaMode && _selectedParkingArea != null
              ? filterState.filterByParkingLocation('parking_completed', currentArea, _selectedParkingArea!)
              : plateState.getPlatesByArea('parking_completed', currentArea);
          final userName = context.read<UserState>().name;
          parkingCompleted.sort((a, b) {
            return _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime);
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
                    color: isPlateSelected ? Colors.green : Colors.grey,
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
                        // ✅ 추가
                        area: selectedPlate.area,
                        // ✅ 추가
                        onRequestEntry: () {
                          handleEntryParkingRequest(context, selectedPlate.plateNumber, selectedPlate.area);
                        },
                        onCompleteDeparture: () {
                          handleEntryDepartureCompleted(context, selectedPlate.plateNumber, selectedPlate.area);
                        },
                        onDelete: () {
                          showDialog(
                            context: context,
                            builder: (context) => ParkingRequestDeleteDialog(
                              onConfirm: () {
                                context.read<DeletePlate>().deletePlateFromParkingCompleted(
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
