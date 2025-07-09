import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';

import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/user/user_state.dart';

import '../../utils/snackbar_helper.dart';

import '../../widgets/navigation/top_navigation.dart';
import '../../widgets/dialog/parking_location_bottom_sheet.dart';
import '../../widgets/dialog/common_plate_search_bottom_sheet/common_plate_search_bottom_sheet.dart';
import 'departure_request_pages/widgets/departure_request_status_bottom_sheet.dart';
import '../../widgets/container/plate_container.dart';

import 'departure_request_pages/departure_request_control_buttons.dart';

class DepartureRequestPage extends StatefulWidget {
  const DepartureRequestPage({super.key});

  @override
  State<DepartureRequestPage> createState() => _DepartureRequestPageState();
}

class _DepartureRequestPageState extends State<DepartureRequestPage> {
  bool _isSorted = true;
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
    final currentArea = context.read<AreaState>().currentArea;

    showDialog(
      context: context,
      builder: (context) => CommonPlateSearchBottomSheet(
        onSearch: (query) {
          // 🔍 검색 결과는 단순 조회 용도, 상태 변경 없음
        },
        area: currentArea,
      ),
    );
  }

  Future<void> _showParkingAreaDialog(BuildContext context) async {
    final selectedLocation = await showDialog<String>(
      context: context,
      builder: (dialogContext) => ParkingLocationBottomSheet(
        locationController: _locationController,
      ),
    );

    if (selectedLocation != null && selectedLocation.isNotEmpty) {
      debugPrint("✅ 선택된 주차 구역: $selectedLocation");
      setState(() {
        _isParkingAreaMode = true;
        _selectedParkingArea = selectedLocation;
      });
    }
  }

  void _resetParkingAreaFilter(BuildContext context) {
    debugPrint("🔄 주차 구역 초기화 실행됨");
    setState(() {
      _isParkingAreaMode = false;
      _selectedParkingArea = null;
    });
  }

  void _handleDepartureCompleted(BuildContext context) async {
    final movementPlate = context.read<MovementPlate>();
    final plateState = context.read<PlateState>();
    final userState = context.read<UserState>();
    final userName = userState.name;
    final selectedPlate = plateState.getSelectedPlate(PlateType.departureRequests, userName);

    if (selectedPlate == null) return;

    try {
      plateState.togglePlateIsSelected(
        collection: PlateType.departureRequests,
        plateNumber: selectedPlate.plateNumber,
        userName: userName,
        onError: (_) {},
      );

      await movementPlate.setDepartureCompleted(
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

    return WillPopScope(
      onWillPop: () async {
        final selectedPlate = plateState.getSelectedPlate(
          PlateType.departureRequests,
          userName,
        );

        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await plateState.togglePlateIsSelected(
            collection: PlateType.departureRequests,
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
        body: Consumer<PlateState>(
          builder: (context, plateState, child) {
            List<PlateModel> departureRequests = plateState.getPlatesByCollection(PlateType.departureRequests);

            if (_isParkingAreaMode && _selectedParkingArea != null) {
              departureRequests = departureRequests
                  .where((plate) => plate.location == _selectedParkingArea)
                  .toList();

              if (departureRequests.isEmpty) {
                return const Center(child: Text('해당 구역의 출차 요청 차량이 없습니다.'));
              }
            }

            // 정렬
            departureRequests.sort((a, b) {
              final aTime = a.requestTime;
              final bTime = b.requestTime;
              return _isSorted ? bTime.compareTo(aTime) : aTime.compareTo(bTime);
            });

            return ListView(
              padding: const EdgeInsets.all(8.0),
              children: [
                PlateContainer(
                  data: departureRequests,
                  collection: PlateType.departureRequests,
                  filterCondition: (request) => request.type == PlateType.departureRequests.firestoreValue,
                  onPlateTap: (plateNumber, area) {
                    plateState.togglePlateIsSelected(
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
          isParkingAreaMode: _isParkingAreaMode,
          isSorted: _isSorted,
          showSearchDialog: () => _showSearchDialog(context),
          showParkingAreaDialog: () => _showParkingAreaDialog(context),
          resetParkingAreaFilter: () => _resetParkingAreaFilter(context),
          toggleSortIcon: _toggleSortIcon,
          handleDepartureCompleted: (ctx) => _handleDepartureCompleted(ctx),
          handleEntryParkingRequest: (ctx, plateNumber, area) {
            handleEntryParkingRequest(ctx, plateNumber, area);
          },
          handleEntryParkingCompleted: (ctx, plateNumber, area, location) {
            handleEntryParkingCompleted(ctx, plateNumber, area, location);
          },
        ),
      ),
    );
  }
}
