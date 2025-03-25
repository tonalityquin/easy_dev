import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate/filter_plate.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/plate/plate_state.dart'; // 번호판 상태 관리
import '../../states/plate/delete_plate.dart';
import '../../states/area/area_state.dart'; // 지역 상태 관리
import '../../states/user/user_state.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/dialog/departure_completed_confirm_dialog.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바
import '../../widgets/dialog/plate_search_dialog.dart'; // ✅ PlateSearchDialog 추가
import '../../widgets/dialog/departure_request_status_dialog.dart';
import '../../widgets/dialog/parking_request_delete_dialog.dart';
import '../../utils/show_snackbar.dart';
import '../input_pages/modify_plate_info.dart';

class DepartureRequestPage extends StatefulWidget {
  const DepartureRequestPage({super.key});

  @override
  State<DepartureRequestPage> createState() => _DepartureRequestPageState();
}

class _DepartureRequestPageState extends State<DepartureRequestPage> {
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
      context.read<FilterPlate>().setPlateSearchQuery(query);
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
            context.read<FilterPlate>().filterByParkingLocation('departure_requests', area, _selectedParkingArea!);
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
    context.read<FilterPlate>().clearLocationSearchQuery();
  }

  void _resetSearch(BuildContext context) {
    context.read<FilterPlate>().clearPlateSearchQuery();
    setState(() {
      _isSearchMode = false;
    });
  }

  void _handleDepartureCompleted(BuildContext context) {
    final movementPlate = context.read<MovementPlate>(); // ✅ MovementPlate 사용
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;
    final selectedPlate = plateState.getSelectedPlate('departure_requests', userName);
    if (selectedPlate != null) {
      try {
        plateState.toggleIsSelected(
          collection: 'departure_requests',
          plateNumber: selectedPlate.plateNumber,
          userName: userName,
          onError: (errorMessage) {
            debugPrint("toggleIsSelected 실패: $errorMessage");
            showSnackbar(context, "선택 해제에 실패했습니다. 다시 시도해주세요.");
          },
        );
        movementPlate.setDepartureCompleted(
            selectedPlate.plateNumber, selectedPlate.area, plateState, selectedPlate.location);
        showSnackbar(context, "출차 완료 처리되었습니다.");
      } catch (e) {
        debugPrint("출차 완료 처리 실패: $e");
        showSnackbar(context, "출차 완료 처리 중 오류 발생: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;

    return WillPopScope(
        onWillPop: () async {
          final selectedPlate = plateState.getSelectedPlate('departure_requests', userName);
          if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
            await plateState.toggleIsSelected(
              collection: 'departure_requests',
              plateNumber: selectedPlate.plateNumber,
              userName: userName,
              onError: (msg) => debugPrint(msg),
            );
            return false;
          }
          return true;
        },
        child: Scaffold(
          appBar: const TopNavigation(),
          body: Consumer2<PlateState, AreaState>(
            builder: (context, plateState, areaState, child) {
              final currentArea = areaState.currentArea;
              final filterState = context.read<FilterPlate>(); // 🔹 FilterState 가져오기
              var departureRequests = _isParkingAreaMode && _selectedParkingArea != null
                  ? filterState.filterByParkingLocation('departure_requests', currentArea, _selectedParkingArea!)
                  : plateState.getPlatesByCollection('departure_requests');
              final userName = context.read<UserState>().name;
              departureRequests.sort((a, b) {
                return _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime);
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
                        color: isPlateSelected ? Colors.green : Colors.grey,
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
                      if (isPlateSelected) {
                        // 👉 선택된 plate 정보를 수정 페이지로 넘겨줌
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ModifyPlateInfo(
                              plate: selectedPlate,
                              collectionKey: 'departure_requests', // 또는 'parking_requests' 등 상황에 맞게
                            ),
                          ),
                        );
                      } else {
                        if (_isSearchMode) {
                          _resetSearch(context);
                        } else {
                          _showSearchDialog(context);
                        }
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
                              handleEntryParkingRequest(context, selectedPlate.plateNumber, selectedPlate.area);
                            },
                            onCompleteDeparture: () {
                              handleEntryParkingCompleted(
                                  context, selectedPlate.plateNumber, selectedPlate.area, selectedPlate.location);
                            },
                            onDelete: () {
                              showDialog(
                                context: context,
                                builder: (context) => ParkingRequestDeleteDialog(
                                  onConfirm: () {
                                    context.read<DeletePlate>().deletePlateFromDepartureRequest(
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
        ));
  }
}
