import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';

import '../../states/area/spot_state.dart';
import '../../states/plate/filter_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/user/user_state.dart';

import '../../utils/snackbar_helper.dart';

import '../../widgets/navigation/top_navigation.dart';
import '../../widgets/dialog/plate_search_dialog.dart';
import '../../widgets/dialog/parking_completed_status_dialog.dart';
import '../../widgets/container/plate_container.dart';

import 'parking_completed_pages/parking_completed_control_buttons.dart';
import 'parking_completed_pages/parking_completed_location_picker.dart';

class ParkingCompletedPage extends StatefulWidget {
  const ParkingCompletedPage({super.key});

  @override
  State<ParkingCompletedPage> createState() => _ParkingCompletedPageState();
}

class _ParkingCompletedPageState extends State<ParkingCompletedPage> {
  bool _isSorted = true;
  bool _isSearchMode = false;
  bool _isParkingAreaMode = true; // ✅ 항상 true로 시작 (주차 구역 선택이 먼저)
  String? _selectedParkingArea;

  @override
  void didUpdateWidget(ParkingCompletedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ✅ 위젯이 트리 안에서 재사용되더라도 상태 초기화
    setState(() {
      _selectedParkingArea = null;
      _isParkingAreaMode = true;
      _isSearchMode = false;
    });
  }

  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });

    context.read<PlateState>().updateSortOrder(
          PlateType.parkingCompleted,
          _isSorted,
        );
  }

  void _showSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return PlateSearchDialog(
          onSearch: (query) {
            if (query.length == 4) {
              context.read<FilterPlate>().setPlateSearchQuery(query);
              setState(() {
                _isSearchMode = true;
              });
            }
          },
        );
      },
    );
  }

  void _resetSearch(BuildContext context) {
    context.read<FilterPlate>().clearPlateSearchQuery();
    setState(() {
      _isSearchMode = false;
    });
  }

  void _resetParkingAreaFilter(BuildContext context) {
    context.read<FilterPlate>().clearLocationSearchQuery();
    setState(() {
      _selectedParkingArea = null; // ✅ 구역 초기화만
    });
  }

  void _handleDepartureRequested(BuildContext context) {
    final movementPlate = context.read<MovementPlate>();
    final userName = context.read<UserState>().name;
    final plateState = context.read<PlateState>();
    final selectedPlate = plateState.getSelectedPlate(PlateType.parkingCompleted, userName);

    if (selectedPlate != null) {
      movementPlate
          .setDepartureRequested(
        selectedPlate.plateNumber,
        selectedPlate.area,
        plateState,
        selectedPlate.location,
      )
          .then((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (context.mounted) {
            Navigator.pop(context);
            showSuccessSnackbar(context, "출차 요청이 완료되었습니다.");
          }
        });
      }).catchError((e) {
        if (context.mounted) {
          showFailedSnackbar(context, "출차 요청 중 오류: $e");
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;

    return WillPopScope(
      onWillPop: () async {
        final selectedPlate = plateState.getSelectedPlate(
          PlateType.parkingCompleted,
          userName,
        );
        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await plateState.toggleIsSelected(
            collection: PlateType.parkingCompleted,
            plateNumber: selectedPlate.plateNumber,
            userName: userName,
            onError: (msg) => debugPrint(msg),
          );
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const TopNavigation(),
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
                  final parkingCompleted = snapshot.data ?? [];
                  return _buildPlateList(parkingCompleted, userName);
                },
              );
            }

            // ✅ 기본이 LocationPicker
            if (_isParkingAreaMode && _selectedParkingArea == null) {
              return ParkingCompletedLocationPicker(
                onLocationSelected: (selectedLocation) {
                  final area = context.read<AreaState>().currentArea;
                  context.read<FilterPlate>().filterByParkingLocation(
                        PlateType.parkingCompleted,
                        area,
                        selectedLocation,
                      );
                  setState(() {
                    _selectedParkingArea = selectedLocation;
                  });
                },
              );
            }

            if (_isParkingAreaMode && _selectedParkingArea != null) {
              return FutureBuilder<List<PlateModel>>(
                future: filterState.fetchPlatesByParkingLocation(
                  type: PlateType.parkingCompleted,
                  location: _selectedParkingArea!,
                ),
                builder: (context, snapshot) {
                  final parkingCompleted = snapshot.data ?? [];

                  // ✅ 정렬 적용
                  parkingCompleted.sort((a, b) =>
                      _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime));

                  return _buildPlateList(parkingCompleted, userName);
                },
              );
            }

            // Fallback: 전체 목록
            final plates = [...plateState.getPlatesByCollection(PlateType.parkingCompleted)];
            plates.sort(
                (a, b) => _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime));
            return _buildPlateList(plates, userName);
          },
        ),
        bottomNavigationBar: ParkingCompletedControlButtons(
          isSearchMode: _isSearchMode,
          isParkingAreaMode: _isParkingAreaMode,
          isSorted: _isSorted,
          showSearchDialog: () => _showSearchDialog(context),
          resetSearch: () => _resetSearch(context),
          resetParkingAreaFilter: () => _resetParkingAreaFilter(context),
          toggleSortIcon: _toggleSortIcon,
          handleEntryParkingRequest: handleEntryParkingRequest,
          handleDepartureRequested: _handleDepartureRequested,
        ),
      ),
    );
  }

  Widget _buildPlateList(List<PlateModel> plates, String userName) {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        PlateContainer(
          data: plates,
          collection: PlateType.parkingCompleted,
          filterCondition: (request) => request.type == PlateType.parkingCompleted.firestoreValue,
          onPlateTap: (plateNumber, area) {
            context.read<PlateState>().toggleIsSelected(
                  collection: PlateType.parkingCompleted,
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
  }
}
