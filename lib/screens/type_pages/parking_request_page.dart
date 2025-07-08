import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../enums/plate_type.dart';

import '../../states/area/area_state.dart';
import '../../states/plate/filter_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/user/user_state.dart';

import '../../utils/snackbar_helper.dart';

import '../../widgets/navigation/top_navigation.dart';
import '../../widgets/dialog/plate_search_bottom_sheet/plate_search_bottom_sheet.dart';
import '../../widgets/dialog/parking_location_bottom_sheet.dart';
import '../../widgets/container/plate_container.dart';

import 'parking_requests_pages/parking_request_control_buttons.dart';

class ParkingRequestPage extends StatefulWidget {
  const ParkingRequestPage({super.key});

  @override
  State<ParkingRequestPage> createState() => _ParkingRequestPageState();
}

class _ParkingRequestPageState extends State<ParkingRequestPage> {
  bool _isSorted = true;
  bool _isSearchMode = false;
  bool _showReportDialog = false;

  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });

    context.read<PlateState>().updateSortOrder(
          PlateType.parkingRequests,
          _isSorted,
        );
  }

  void _showSearchDialog(BuildContext context) {
    final currentArea = context.read<AreaState>().currentArea;

    showDialog(
      context: context,
      builder: (context) {
        return PlateSearchBottomSheet(
          onSearch: (query) {
            _filterPlatesByNumber(context, query);
          },
          area: currentArea,
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

  void _resetSearch(BuildContext context) {
    context.read<FilterPlate>().clearPlateSearchQuery();
    setState(() {
      _isSearchMode = false;
    });
  }

  void _handlePlateTap(BuildContext context, String plateNumber, String area) {
    final userName = context.read<UserState>().name;
    context.read<PlateState>().togglePlateIsSelected(
          collection: PlateType.parkingRequests,
          plateNumber: plateNumber,
          userName: userName,
          onError: (errorMessage) {
            showFailedSnackbar(context, errorMessage);
          },
        );
  }

  Future<void> _handleParkingCompleted(BuildContext context) async {
    final plateState = context.read<PlateState>();
    final movementPlate = context.read<MovementPlate>();
    final userName = context.read<UserState>().name;

    final selectedPlate = plateState.getSelectedPlate(
      PlateType.parkingRequests,
      userName,
    );

    if (selectedPlate != null) {
      final TextEditingController locationController = TextEditingController();

      while (true) {
        final selectedLocation = await showDialog<String>(
          context: context,
          builder: (dialogContext) {
            return ParkingLocationBottomSheet(
              locationController: locationController,
            );
          },
        );

        if (selectedLocation == null) {
          break;
        } else if (selectedLocation == 'refresh') {
          continue;
        } else if (selectedLocation.isNotEmpty) {
          await _completeParking(
            movementPlate: movementPlate,
            plateState: plateState,
            plateNumber: selectedPlate.plateNumber,
            area: selectedPlate.area,
            location: selectedLocation,
          );
          break;
        } else {
          showFailedSnackbar(context, '주차 구역을 입력해주세요.');
        }
      }
    }
  }

  Future<void> _completeParking({
    required MovementPlate movementPlate,
    required PlateState plateState,
    required String plateNumber,
    required String area,
    required String location,
  }) async {
    try {
      await movementPlate.setParkingCompleted(
        plateNumber,
        area,
        plateState,
        location,
      );

      if (mounted) {
        showSuccessSnackbar(context, "입차 완료: $plateNumber ($location)");
      }
    } catch (e) {
      debugPrint('입차 완료 처리 실패: $e');
      if (mounted) {
        showFailedSnackbar(context, "입차 완료 처리 중 오류 발생: $e");
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
          PlateType.parkingRequests,
          userName,
        );

        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await plateState.togglePlateIsSelected(
            collection: PlateType.parkingRequests,
            plateNumber: selectedPlate.plateNumber,
            userName: userName,
            onError: (msg) => debugPrint(msg),
          );
          return false;
        }

        if (_showReportDialog) {
          setState(() => _showReportDialog = false);
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
        body: Stack(
          children: [
            Consumer2<PlateState, FilterPlate>(
              builder: (context, plateState, filterPlate, child) {
                if (_isSearchMode) {
                  final searchResults = filterPlate.filterPlatesByFourDigit(
                    filterPlate.searchQuery,
                  );

                  return ListView(
                    padding: const EdgeInsets.all(8.0),
                    children: [
                      PlateContainer(
                        data: searchResults,
                        collection: PlateType.parkingRequests,
                        filterCondition: (request) => request.type == PlateType.parkingRequests.firestoreValue,
                        onPlateTap: (plateNumber, area) {
                          _handlePlateTap(context, plateNumber, area);
                        },
                      ),
                    ],
                  );
                } else {
                  final plates = [...plateState.getPlatesByCollection(PlateType.parkingRequests)];

                  plates.sort((a, b) {
                    final aTime = a.requestTime;
                    final bTime = b.requestTime;
                    return _isSorted ? bTime.compareTo(aTime) : aTime.compareTo(bTime);
                  });

                  return ListView(
                    padding: const EdgeInsets.all(8.0),
                    children: [
                      PlateContainer(
                        data: plates,
                        collection: PlateType.parkingRequests,
                        filterCondition: (request) => request.type == PlateType.parkingRequests.firestoreValue,
                        onPlateTap: (plateNumber, area) {
                          _handlePlateTap(context, plateNumber, area);
                        },
                      ),
                    ],
                  );
                }
              },
            ),
          ],
        ),
        bottomNavigationBar: ParkingRequestControlButtons(
          isSorted: _isSorted,
          isSearchMode: _isSearchMode,
          onSearchToggle: () {
            _isSearchMode ? _resetSearch(context) : _showSearchDialog(context);
          },
          onSortToggle: _toggleSortIcon,
          onParkingCompleted: () => _handleParkingCompleted(context),
          onToggleReportDialog: () {
            setState(() => _showReportDialog = !_showReportDialog);
          },
        ),
      ),
    );
  }
}
