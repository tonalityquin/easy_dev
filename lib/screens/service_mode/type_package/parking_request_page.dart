import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../states/area/area_state.dart';
import '../../../states/plate/plate_state.dart';
import '../../../states/plate/movement_plate.dart';
import '../../../states/user/user_state.dart';

import '../../../utils/snackbar_helper.dart';

import '../../../widgets/container/plate_container.dart';
import '../../../widgets/dialog/common_plate_search_bottom_sheet/common_plate_search_bottom_sheet.dart';
import '../../../widgets/dialog/parking_location_bottom_sheet.dart';
import '../../../widgets/navigation/top_navigation.dart';

import 'parking_request_package/parking_request_control_buttons.dart';

class ParkingRequestPage extends StatefulWidget {
  const ParkingRequestPage({super.key});

  @override
  State<ParkingRequestPage> createState() => _ParkingRequestPageState();
}

class _ParkingRequestPageState extends State<ParkingRequestPage> {
  // 화면 식별 태그(FAQ/에러 리포트 연계용)
  static const String screenTag = 'parking request';

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

  // 좌측 상단(11시 방향) 화면 태그 위젯
  Widget _buildScreenTag(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ??
        const TextStyle(
          fontSize: 11,
          color: Colors.black54,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return SafeArea(
      child: IgnorePointer( // 제스처 간섭 방지
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Semantics(
              label: 'screen_tag: $screenTag',
              child: Text(screenTag, style: style),
            ),
          ),
        ),
      ),
    );
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

          // ⬇️ 좌측 상단(11시 방향)에 'parking request' 텍스트 고정
          flexibleSpace: _buildScreenTag(context),
        ),
        body: Consumer<PlateState>(
          builder: (context, plateState, child) {
            final plates = [...plateState.getPlatesByCollection(PlateType.parkingRequests)];

            if (kDebugMode) {
              debugPrint('📦 PlateState: parkingRequests 총 개수 → ${plates.length}');
              final selectedPlate = plateState.getSelectedPlate(PlateType.parkingRequests, userName);
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
                        if (_isLocked) return;
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
        // ⬇️ FAB: 보류가 존재 + 여전히 의미가 있을 때만 표시(잠금 시 숨김)
        floatingActionButton: Consumer<PlateState>(
          builder: (context, s, _) {
            final showFab =
                s.hasPendingSelection && s.pendingStillValidFor(PlateType.parkingRequests) && !_isLocked;

            // 동적 FAB 라벨/아이콘/색상: 보류가 선택(true)이면 '주행', 해제(false)이면 '해제'
            final isSelecting = s.pendingIsSelected ?? true;
            final fabLabel = isSelecting ? '주행' : '해제';
            final fabIcon = isSelecting ? Icons.directions_car_filled : Icons.undo;
            final fabBg = isSelecting ? const Color(0xFF0D47A1) : Colors.grey;

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
                  icon: Icon(fabIcon),
                  label: Text(fabLabel),
                  backgroundColor: fabBg,
                  foregroundColor: Colors.white,
                ),
              ),
            );
          },
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
