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
  bool _isLocked = false; // 🔐 잠금 상태 추가

  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });

    context.read<PlateState>().updateSortOrder(
          PlateType.departureRequests,
          _isSorted,
        );
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
    });
  }

  void _showSearchDialog(BuildContext context) {
    final currentArea = context.read<AreaState>().currentArea;

    showDialog(
      context: context,
      builder: (context) => CommonPlateSearchBottomSheet(
        onSearch: (query) {},
        area: currentArea,
      ),
    );
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

      await movementPlate.setDepartureCompleted(selectedPlate);

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
            List<PlateModel> departureRequests =
            plateState.getPlatesByCollection(PlateType.departureRequests);

            debugPrint('📦 전체 출차 요청 plate 수: ${departureRequests.length}');
            if (departureRequests.isNotEmpty) {
              debugPrint('🔍 첫 번째 plate: ${departureRequests.first.plateNumber} @ ${departureRequests.first.location}');
            }

            departureRequests.sort((a, b) {
              final aTime = a.requestTime;
              final bTime = b.requestTime;
              return _isSorted ? bTime.compareTo(aTime) : aTime.compareTo(bTime);
            });

            return Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(8.0),
                  children: [
                    PlateContainer(
                      data: departureRequests,
                      collection: PlateType.departureRequests,
                      filterCondition: (request) => request.type == PlateType.departureRequests.firestoreValue,
                      onPlateTap: (plateNumber, area) {
                        if (_isLocked) return;

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
                ),
                if (_isLocked)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {}, // 터치 차단용
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            );
          },
        ),
        bottomNavigationBar: DepartureRequestControlButtons(
          isSorted: _isSorted,
          isLocked: _isLocked,
          showSearchDialog: () => _showSearchDialog(context),
          toggleSortIcon: _toggleSortIcon,
          toggleLock: _toggleLock,
          handleDepartureCompleted: () => _handleDepartureCompleted(context),
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
