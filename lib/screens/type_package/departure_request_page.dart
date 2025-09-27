// lib/screens/type_package/departure_request_page.dart
import 'package:flutter/foundation.dart';
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
import 'departure_request_package/widgets/departure_request_status_bottom_sheet.dart';
import '../../widgets/container/plate_container.dart';

import 'departure_request_package/departure_request_control_buttons.dart';

class DepartureRequestPage extends StatefulWidget {
  const DepartureRequestPage({super.key});

  @override
  State<DepartureRequestPage> createState() => _DepartureRequestPageState();
}

class _DepartureRequestPageState extends State<DepartureRequestPage> {
  bool _isSorted = true;
  bool _isLocked = false;

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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CommonPlateSearchBottomSheet(
        onSearch: (query) {},
        area: currentArea,
      ),
    );
  }

  Future<void> _handleDepartureCompleted(BuildContext context) async {
    final movementPlate = context.read<MovementPlate>();
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;

    final selectedPlate =
    plateState.getSelectedPlate(PlateType.departureRequests, userName);

    if (selectedPlate == null) return;

    try {
      // 1) 먼저 출차 완료 처리
      await movementPlate.setDepartureCompleted(selectedPlate);

      if (!context.mounted) return;

      // 2) 성공 후 선택 해제 (await 보장)
      await plateState.togglePlateIsSelected(
        collection: PlateType.departureRequests,
        plateNumber: selectedPlate.plateNumber,
        userName: userName,
        onError: (_) {},
      );

      showSuccessSnackbar(context, '출차 완료 처리되었습니다.');
    } catch (e) {
      if (kDebugMode) {
        debugPrint("출차 완료 처리 실패: $e");
      }
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
            List<PlateModel> departureRequests =
            plateState.getPlatesByCollection(PlateType.departureRequests);

            if (kDebugMode) {
              debugPrint('📦 전체 출차 요청 plate 수: ${departureRequests.length}');
              if (departureRequests.isNotEmpty) {
                debugPrint(
                    '🔍 첫 번째 plate: ${departureRequests.first.plateNumber} @ ${departureRequests.first.location}');
              }
            }

            // null-safe 정렬 (requestTime이 null일 가능성 방어)
            departureRequests.sort((a, b) =>
            _isSorted
                ? b.requestTime.compareTo(a.requestTime) // 최신순
                : a.requestTime.compareTo(b.requestTime) // 오래된순
            );

            final isEmpty = departureRequests.isEmpty;

            return Stack(
              children: [
                if (isEmpty)
                  const Center(
                    child: Text(
                      '출차 요청이 없습니다.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ListView(
                    padding: const EdgeInsets.all(8.0),
                    children: [
                      PlateContainer(
                        data: departureRequests,
                        collection: PlateType.departureRequests,
                        filterCondition: (request) =>
                        request.type ==
                            PlateType.departureRequests.firestoreValue,
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
        // ⬇️ FAB: 로컬에서 선택(보류 변경)이 있을 때만 표시, 잠금 시 숨김
        floatingActionButton: Consumer<PlateState>(
          builder: (context, s, _) {
            final showFab = s.hasPendingSelection && !_isLocked;
            if (!showFab) return const SizedBox.shrink();
            return SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FloatingActionButton.extended(
                  onPressed: () async {
                    await s.commitPendingSelection(
                      onError: (msg) {
                        final sc = ScaffoldMessenger.of(context);
                        sc.hideCurrentSnackBar();
                        sc.showSnackBar(SnackBar(content: Text(msg)));
                      },
                    );
                    if (context.mounted) {
                      showSuccessSnackbar(context, '변경 사항을 반영했습니다.');
                    }
                  },
                  icon: const Icon(Icons.directions_car_filled),
                  label: const Text('주행'),
                  backgroundColor: const Color(0xFF0D47A1),
                  foregroundColor: Colors.white,
                ),
              ),
            );
          },
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        bottomNavigationBar: DepartureRequestControlButtons(
          isSorted: _isSorted,
          isLocked: _isLocked,
          showSearchDialog: () => _showSearchDialog(context),
          toggleSortIcon: _toggleSortIcon,
          toggleLock: _toggleLock,
          handleDepartureCompleted: () => _handleDepartureCompleted(context),
          // 불필요한 래핑 제거: 함수 레퍼런스 직접 전달
          handleEntryParkingRequest: handleEntryParkingRequest,
          handleEntryParkingCompleted: handleEntryParkingCompleted,
        ),
      ),
    );
  }
}
