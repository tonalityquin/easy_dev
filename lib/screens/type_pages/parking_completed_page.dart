import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';

import '../../states/area/area_state.dart';
import '../../states/plate/filter_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/user/user_state.dart';

import '../../utils/snackbar_helper.dart';

import 'parking_completed_pages/widgets/parking_completed_location_dialog.dart';
import '../../widgets/navigation/top_navigation.dart';
import '../../widgets/dialog/plate_search_dialog.dart';
import '../../widgets/dialog/parking_completed_status_dialog.dart';
import '../../widgets/container/plate_container.dart';

import 'parking_completed_pages/parking_completed_control_buttons.dart';

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

  void _showParkingAreaDialog(BuildContext parentContext) {
    showDialog(
      context: parentContext,
      builder: (context) => ParkingCompletedLocationDialog(
        locationController: _locationController,
        onLocationSelected: (selectedLocation) {
          debugPrint("✅ 선택된 주차 구역: $selectedLocation");
          setState(() {
            _isParkingAreaMode = true;
            _selectedParkingArea = selectedLocation;
          });

          final area = Provider.of<AreaState>(parentContext, listen: false).currentArea;
          Provider.of<FilterPlate>(parentContext, listen: false)
              .filterByParkingLocation(PlateType.parkingCompleted, area, selectedLocation);
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

  void _handleDepartureRequested(BuildContext context) {
    final movementPlate = context.read<MovementPlate>();
    final userState = context.read<UserState>();
    final userName = userState.name;
    final plateState = context.read<PlateState>();
    final selectedPlate = plateState.getSelectedPlate(PlateType.parkingCompleted, userName);

    if (selectedPlate != null) {
      try {
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
        });
      } catch (e) {
        debugPrint("출차 요청 처리 실패: $e");
        if (context.mounted) {
          showFailedSnackbar(context, "출차 요청 처리 중 오류 발생: $e");
        }
      }
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

            if (_isParkingAreaMode && _selectedParkingArea != null) {
              return FutureBuilder<List<PlateModel>>(
                future: filterState.fetchPlatesByParkingLocation(
                  type: PlateType.parkingCompleted,
                  location: _selectedParkingArea!,
                ),
                builder: (context, snapshot) {
                  final parkingCompleted = snapshot.data ?? [];
                  return _buildPlateList(parkingCompleted, userName);
                },
              );
            }

            final plates = [...plateState.getPlatesByCollection(PlateType.parkingCompleted)];

            // ✅ 정렬 적용
            plates.sort((a, b) {
              final aTime = a.requestTime;
              final bTime = b.requestTime;

              return _isSorted ? bTime.compareTo(aTime) : aTime.compareTo(bTime);
            });
            return _buildPlateList(plates, userName);
          },
        ),
        bottomNavigationBar: ParkingCompletedControlButtons(
          isSearchMode: _isSearchMode,
          isParkingAreaMode: _isParkingAreaMode,
          isSorted: _isSorted,
          showSearchDialog: () => _showSearchDialog(context),
          resetSearch: () => _resetSearch(context),
          showParkingAreaDialog: () => _showParkingAreaDialog(context),
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
