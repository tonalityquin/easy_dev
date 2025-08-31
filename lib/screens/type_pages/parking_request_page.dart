import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../enums/plate_type.dart';
import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/user/user_state.dart';

import '../../utils/snackbar_helper.dart';

import '../../widgets/container/plate_container.dart';
import '../../widgets/dialog/common_plate_search_bottom_sheet/common_plate_search_bottom_sheet.dart';
import '../../widgets/dialog/parking_location_bottom_sheet.dart';
import '../../widgets/navigation/top_navigation.dart';

import 'parking_requests_pages/parking_request_control_buttons.dart';

class ParkingRequestPage extends StatefulWidget {
  const ParkingRequestPage({super.key});

  @override
  State<ParkingRequestPage> createState() => _ParkingRequestPageState();
}

class _ParkingRequestPageState extends State<ParkingRequestPage> {
  bool _isSorted = true; // 최신순(true) / 오래된순(false)
  bool _isLocked = false; // 화면 잠금

  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });
    // 간단 패치: 로컬 정렬만 사용 (PlateState.updateSortOrder 호출 제거)
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
    });
  }

  void _showSearchDialog(BuildContext context) {
    final currentArea = context.read<AreaState>().currentArea.trim();

    showDialog(
      context: context,
      builder: (context) {
        return CommonPlateSearchBottomSheet(
          onSearch: (query) {},
          area: currentArea,
        );
      },
    );
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

        if (selectedLocation == null) break; // 닫힘
        if (selectedLocation == 'refresh') continue;

        if (selectedLocation.isNotEmpty) {
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
      await movementPlate.setParkingCompleted(plateNumber, area, location);
      if (mounted) {
        showSuccessSnackbar(context, "입차 완료: $plateNumber ($location)");
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('입차 완료 처리 실패: $e');
      }
      if (mounted) {
        showFailedSnackbar(context, "입차 완료 처리 중 오류 발생: 다시 시도해 주세요.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userName = context.read<UserState>().name;

    return WillPopScope(
      onWillPop: () async {
        final selectedPlate = context
            .read<PlateState>()
            .getSelectedPlate(PlateType.parkingRequests, userName);

        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await context.read<PlateState>().togglePlateIsSelected(
            collection: PlateType.parkingRequests,
            plateNumber: selectedPlate.plateNumber,
            userName: userName,
            onError: (msg) {
              if (kDebugMode) debugPrint(msg);
            },
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
            final plates = [
              ...plateState.getPlatesByCollection(PlateType.parkingRequests)
            ];

            if (kDebugMode) {
              debugPrint('📦 PlateState: parkingRequests 총 개수 → ${plates.length}');
              final selectedPlate =
              plateState.getSelectedPlate(PlateType.parkingRequests, userName);
              debugPrint('✅ 선택된 Plate → ${selectedPlate?.plateNumber ?? "없음"}');
            }

            if (plates.isEmpty) {
              return const Center(
                child: Text('입차 요청 내역이 없습니다.'),
              );
            }

            plates.sort((a, b) {
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
                      data: plates,
                      collection: PlateType.parkingRequests,
                      filterCondition: (request) =>
                      request.type == PlateType.parkingRequests.firestoreValue,
                      onPlateTap: (plateNumber, area) {
                        _handlePlateTap(context, plateNumber, area);
                      },
                    ),
                  ],
                ),
                if (_isLocked)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        showSelectedSnackbar(context, '화면이 잠금 상태입니다.');
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            );
          },
        ),
        bottomNavigationBar: ParkingRequestControlButtons(
          isSorted: _isSorted,
          isLocked: _isLocked,
          onToggleLock: _toggleLock,
          onSearchPressed: () => _showSearchDialog(context),
          onSortToggle: _toggleSortIcon,
          onParkingCompleted: () => _handleParkingCompleted(context),
        ),
      ),
    );
  }
}
