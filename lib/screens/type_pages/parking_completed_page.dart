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

import '../../widgets/dialog/signature_plate_search_bottom_sheet/signature_plate_search_bottom_sheet.dart';
import '../../widgets/navigation/top_navigation.dart';
import 'parking_completed_pages/widgets/parking_completed_status_bottom_sheet.dart';
import '../../widgets/container/plate_container.dart';

import 'parking_completed_pages/parking_completed_control_buttons.dart';
import 'parking_completed_pages/parking_completed_location_picker.dart';

class ParkingCompletedPage extends StatefulWidget {
  const ParkingCompletedPage({super.key});

  static void reset(GlobalKey key) {
    (key.currentState as _ParkingCompletedPageState?)?._resetInternalState();
  }

  @override
  State<ParkingCompletedPage> createState() => _ParkingCompletedPageState();
}

class _ParkingCompletedPageState extends State<ParkingCompletedPage> {
  bool _isSorted = true;
  bool _isParkingAreaMode = true;
  String? _selectedParkingArea;

  void _resetInternalState() {
    setState(() {
      _selectedParkingArea = null;
      _isParkingAreaMode = true;
      _isSorted = true;
    });
  }

  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });
  }

  void _showSearchDialog(BuildContext context) {
    final currentArea = context.read<AreaState>().currentArea;

    showDialog(
      context: context,
      builder: (context) {
        return SignaturePlateSearchBottomSheet(
          onSearch: (query) {
            if (query.length == 4) {
              context.read<FilterPlate>().setPlateSearchQuery(query);
              // ✅ 렌더링 상태 변경 없음
            }
          },
          area: currentArea,
        );
      },
    );
  }

  void _resetParkingAreaFilter(BuildContext context) {
    context.read<FilterPlate>().clearLocationSearchQuery();
    setState(() {
      _selectedParkingArea = null;
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
    return WillPopScope(
      onWillPop: () async {
        final plateState = context.read<PlateState>();
        final userName = context.read<UserState>().name;
        final selectedPlate = plateState.getSelectedPlate(
          PlateType.parkingCompleted,
          userName,
        );
        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await plateState.togglePlateIsSelected(
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
            final userName = context.read<UserState>().name;
            List<PlateModel> plates = plateState.getPlatesByCollection(PlateType.parkingCompleted);

            // 구역 필터 모드
            if (_isParkingAreaMode && _selectedParkingArea != null) {
              plates = plates.where((p) => p.location == _selectedParkingArea).toList();
            }

            // 정렬
            plates.sort(
                  (a, b) => _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime),
            );

            // 구역 선택 화면
            if (_isParkingAreaMode && _selectedParkingArea == null) {
              return ParkingCompletedLocationPicker(
                onLocationSelected: (selectedLocation) {
                  setState(() {
                    _selectedParkingArea = selectedLocation;
                  });
                },
              );
            }

            return _buildPlateList(plates, userName);
          },
        ),
        bottomNavigationBar: ParkingCompletedControlButtons(
          isParkingAreaMode: _isParkingAreaMode,
          isSorted: _isSorted,
          showSearchDialog: () => _showSearchDialog(context),
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
            context.read<PlateState>().togglePlateIsSelected(
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
