import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';

import '../../states/plate/filter_plate.dart';
import '../../states/plate/plate_state.dart'; // 번호판 상태 관리
import '../../states/plate/movement_plate.dart';
import '../../states/user/user_state.dart';

import '../../utils/snackbar_helper.dart';

import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../widgets/dialog/plate_search_dialog/plate_search_dialog.dart'; // ✅ PlateSearchDialog 추가
import 'departure_request_pages/widgets/departure_request_status_dialog.dart';
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

  Future<void> _showParkingAreaDialog(BuildContext context) async {
    final selectedLocation = await showDialog<String>(
      context: context,
      builder: (dialogContext) => ParkingLocationDialog(
        locationController: _locationController,
      ),
    );

    if (selectedLocation != null && selectedLocation.isNotEmpty) {
      debugPrint("✅ 선택된 주차 구역: $selectedLocation");
      setState(() {
        _isParkingAreaMode = true;
        _selectedParkingArea = selectedLocation;
      });

      context.read<FilterPlate>().filterByParkingLocation(
            PlateType.departureRequests,
            _selectedParkingArea!,
          );
    }
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
          return false; // 선택 해제 후 뒤로가기 차단
        }

        return true; // 선택된 plate 없을 경우 뒤로가기 허용
      },
      child: Scaffold(
        appBar: AppBar(
          title: const TopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: Consumer2<PlateState, FilterPlate>(
          builder: (context, plateState, filterState, child) {
            final userName = context.read<UserState>().name;

            List<PlateModel> departureRequests;

            // 1) 검색 모드
            if (_isSearchMode) {
              departureRequests = filterState
                  .getPlates(PlateType.departureRequests)
                  .where((plate) => plate.plateNumber.contains(filterState.searchQuery))
                  .toList();

              if (departureRequests.isEmpty) {
                return const Center(child: Text('검색 결과가 없습니다.'));
              }
            }
            // 2) 주차 구역 모드
            else if (_isParkingAreaMode && _selectedParkingArea != null) {
              departureRequests = filterState.filterByParkingLocation(
                PlateType.departureRequests,
                _selectedParkingArea!,
              );

              if (departureRequests.isEmpty) {
                return const Center(child: Text('해당 구역의 출차 요청 차량이 없습니다.'));
              }
            }
            // 3) 기본 모드
            else {
              departureRequests = plateState.getPlatesByCollection(PlateType.departureRequests);

              if (departureRequests.isEmpty) {
                return const Center(child: Text('출차 요청 차량이 없습니다.'));
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
          isSearchMode: _isSearchMode,
          isParkingAreaMode: _isParkingAreaMode,
          isSorted: _isSorted,
          showSearchDialog: () => _showSearchDialog(context),
          resetSearch: () => _resetSearch(context),
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
