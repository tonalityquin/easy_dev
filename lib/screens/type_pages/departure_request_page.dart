import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';

import '../../states/plate/filter_plate.dart';
import '../../states/plate/plate_state.dart'; // 번호판 상태 관리
import '../../states/plate/movement_plate.dart';
import '../../states/area/area_state.dart'; // 지역 상태 관리
import '../../states/user/user_state.dart';

import '../../utils/snackbar_helper.dart';

import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../widgets/dialog/plate_search_dialog.dart'; // ✅ PlateSearchDialog 추가
import '../../widgets/dialog/departure_request_status_dialog.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯

import 'departure_request_pages/departure_request_control_buttons.dart';

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

    context.read<PlateState>().updateSortOrder(
          PlateType.departureRequests,
          _isSorted,
        );
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
            context
                .read<FilterPlate>()
                .filterByParkingLocation(PlateType.departureRequests, area, _selectedParkingArea!);
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

  void _handleDepartureCompleted(BuildContext context) async {
    final movementPlate = context.read<MovementPlate>();
    final plateState = context.read<PlateState>();
    final userState = context.read<UserState>();
    final userName = userState.name;
    final selectedPlate = plateState.getSelectedPlate(PlateType.departureRequests, userName);

    if (selectedPlate == null) return;

    // ✅ 정산 상태와 관계없이 그대로 출차 완료
    try {
      plateState.toggleIsSelected(
        collection: PlateType.departureRequests,
        plateNumber: selectedPlate.plateNumber,
        userName: userName,
        onError: (_) {},
      );

      await movementPlate.setDepartureCompletedWithPlate(
        selectedPlate,
        plateState,
      );

      if (!context.mounted) return;
      showSuccessSnackbar(context, '출차 완료 처리되었습니다.');
    } catch (e) {
      debugPrint("출차 완료 처리 실패: $e");
      if (context.mounted) {
        showFailedSnackbar(context, "출차 완료 중 오류 발생: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;

    return PopScope(
        canPop: false, // ✅ 화면 닫힘 방지
        onPopInvoked: (didPop) async {
          // ✅ 번호판 선택 해제만 처리
          final selectedPlate = plateState.getSelectedPlate(PlateType.departureRequests, userName);
          if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
            await plateState.toggleIsSelected(
              collection: PlateType.departureRequests,
              plateNumber: selectedPlate.plateNumber,
              userName: userName,
              onError: (msg) => debugPrint(msg),
            );
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: const TopNavigation(),
            // ✅ title로만 사용
            centerTitle: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
          ),
          body: Consumer2<PlateState, AreaState>(
            builder: (context, plateState, areaState, child) {
              final filterState = context.read<FilterPlate>();
              final userName = context.read<UserState>().name;

              if (_isSearchMode) {
                return FutureBuilder<List<PlateModel>>(
                  future: filterState.fetchPlatesBySearchQuery(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final departureRequests = snapshot.data ?? [];
                    if (departureRequests.isEmpty) {
                      return const Center(child: Text('검색 결과가 없습니다.'));
                    }

                    return ListView(
                      padding: const EdgeInsets.all(8.0),
                      children: [
                        PlateContainer(
                          data: departureRequests,
                          collection: PlateType.departureRequests,
                          filterCondition: (request) => request.type == PlateType.departureRequests.firestoreValue,
                          onPlateTap: (plateNumber, area) {
                            plateState.toggleIsSelected(
                              collection: PlateType.departureRequests,
                              plateNumber: plateNumber,
                              userName: userName,
                              onError: (errorMessage) {
                                showFailedSnackbar(context, errorMessage);
                              },
                            );
                          },
                        ),
                      ],
                    );
                  },
                );
              }

              if (_isParkingAreaMode && _selectedParkingArea != null) {
                return FutureBuilder<List<PlateModel>>(
                  future: filterState.fetchPlatesByParkingLocation(
                    type: PlateType.departureRequests,
                    location: _selectedParkingArea!,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final departureRequests = snapshot.data ?? [];
                    if (departureRequests.isEmpty) {
                      return const Center(child: Text('해당 구역의 출차 요청 차량이 없습니다.'));
                    }

                    return ListView(
                      padding: const EdgeInsets.all(8.0),
                      children: [
                        PlateContainer(
                          data: departureRequests,
                          collection: PlateType.departureRequests,
                          filterCondition: (request) => request.type == PlateType.departureRequests.firestoreValue,
                          onPlateTap: (plateNumber, area) {
                            plateState.toggleIsSelected(
                              collection: PlateType.departureRequests,
                              plateNumber: plateNumber,
                              userName: userName,
                              onError: (errorMessage) {
                                showFailedSnackbar(context, errorMessage);
                              },
                            );
                          },
                        ),
                      ],
                    );
                  },
                );
              }

              final plates = plateState.getPlatesByCollection(PlateType.departureRequests);
              if (plates.isEmpty) {
                return const Center(child: Text('출차 요청 차량이 없습니다.'));
              }

              return ListView(
                padding: const EdgeInsets.all(8.0),
                children: [
                  PlateContainer(
                    data: plates,
                    collection: PlateType.departureRequests,
                    filterCondition: (request) => request.type == PlateType.departureRequests.firestoreValue,
                    onPlateTap: (plateNumber, area) {
                      plateState.toggleIsSelected(
                        collection: PlateType.departureRequests,
                        plateNumber: plateNumber,
                        userName: userName,
                        onError: (errorMessage) {
                          showFailedSnackbar(context, errorMessage);
                        },
                      );
                    },
                  ),
                ],
              );
            },
          ),
          bottomNavigationBar: DepartureRequestControlButtons(
            isSorted: _isSorted,
            isSearchMode: _isSearchMode,
            isParkingAreaMode: _isParkingAreaMode,
            onSortToggle: _toggleSortIcon,
            onSearch: () => _showSearchDialog(context),
            onResetSearch: () => _resetSearch(context),
            onParkingAreaToggle: () => _showParkingAreaDialog(context),
            onResetParkingAreaFilter: () => _resetParkingAreaFilter(context),
            onDepartureCompleted: () => _handleDepartureCompleted(context),
            onRequestEntry: () {
              final plate = context.read<PlateState>().getSelectedPlate(
                    PlateType.departureRequests,
                    context.read<UserState>().name,
                  );
              if (plate != null) {
                handleEntryParkingRequest(context, plate.plateNumber, plate.area);
              }
            },
            onCompleteEntry: () {
              final plate = context.read<PlateState>().getSelectedPlate(
                    PlateType.departureRequests,
                    context.read<UserState>().name,
                  );
              if (plate != null) {
                handleEntryParkingCompleted(
                  context,
                  plate.plateNumber,
                  plate.area,
                  plate.location,
                );
              }
            },
          ),
        ));
  }
}
