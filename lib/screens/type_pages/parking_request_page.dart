import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';

import '../../repositories/plate/plate_repository.dart';

import '../../states/plate/filter_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';

import '../../utils/snackbar_helper.dart';

import '../../widgets/navigation/top_navigation.dart';
import '../../widgets/dialog/plate_search_dialog.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
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
    final plateRepository = context.read<PlateRepository>();
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
            return ParkingLocationDialog(
              locationController: locationController,
            );
          },
        );

        if (selectedLocation == null) {
          // 유저가 닫았을 경우 종료
          break;
        } else if (selectedLocation == 'refresh') {
          // 갱신 요청 → 루프 계속
          continue;
        } else if (selectedLocation.isNotEmpty) {
          // 선택된 경우 처리 후 종료
          _completeParking(
            movementPlate: movementPlate,
            plateState: plateState,
            plateRepository: plateRepository,
            userName: userName,
            plateNumber: selectedPlate.plateNumber,
            area: selectedPlate.area,
            location: selectedLocation,
            region: selectedPlate.region ?? '전국',
          );
          break;
        } else {
          showFailedSnackbar(context, '주차 구역을 입력해주세요.');
          // 루프를 계속 돌려 다시 다이얼로그 띄우기
        }
      }
    }
  }

  void _completeParking({
    required MovementPlate movementPlate,
    required PlateState plateState,
    required PlateRepository plateRepository,
    required String userName,
    required String plateNumber,
    required String area,
    required String location,
    required String region,
  }) {
    try {
      plateRepository.addRequestOrCompleted(
        plateNumber: plateNumber,
        location: location,
        area: area,
        userName: userName,
        plateType: PlateType.parkingCompleted,
        billingType: null,
        statusList: [],
        basicStandard: 0,
        basicAmount: 0,
        addStandard: 0,
        addAmount: 0,
        region: region,
      );

      movementPlate.setParkingCompleted(
        plateNumber,
        area,
        plateState,
        location,
      );

      // ✅ showSuccessSnackbar 호출
      showSuccessSnackbar(context, "입차 완료: $plateNumber ($location)");
    } catch (e) {
      debugPrint('입차 완료 처리 실패: $e');

      // ✅ showFailedSnackbar 호출
      showFailedSnackbar(context, "입차 완료 처리 중 오류 발생: $e");
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

        // 조건에 따라 선택 해제 또는 리포트 닫기
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
            Consumer2<PlateState, AreaState>(
              builder: (context, plateState, areaState, child) {
                if (_isSearchMode) {
                  return FutureBuilder<List<PlateModel>>(
                    future: context.read<FilterPlate>().fetchPlatesCountsBySearchQuery(),
                    builder: (context, snapshot) {
                      final searchResults = snapshot.data ?? [];
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
                    },
                  );
                } else {
                  final plates = [...plateState.getPlatesByCollection(PlateType.parkingRequests)];

                  // ✅ 정렬 적용
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
