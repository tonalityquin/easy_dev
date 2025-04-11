import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../utils/fee_calculator.dart';
import '../../states/plate/plate_state.dart'; // PlateState 상태 관리
import '../../states/plate/delete_plate.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/area/area_state.dart'; // AreaState 상태 관리
import '../../states/user/user_state.dart';
import '../../states/plate/filter_plate.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/dialog/confirm_cancel_fee_dialog.dart';
import '../../widgets/dialog/departure_request_confirmation_dialog.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바
import '../../widgets/dialog/plate_search_dialog.dart'; // ✅ PlateSearchDialog 추가
import '../../widgets/dialog/parking_completed_status_dialog.dart';
import '../../widgets/dialog/parking_request_delete_dialog.dart';
import '../../utils/snackbar_helper.dart';
import '../../enums/plate_type.dart';

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

  void _showParkingAreaDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => ParkingLocationDialog(
        locationController: _locationController,
        onLocationSelected: (selectedLocation) {
          debugPrint("✅ 선택된 주차 구역: $selectedLocation");
          setState(() {
            _isParkingAreaMode = true;
            _selectedParkingArea = selectedLocation;
          });
          final area = context.read<AreaState>().currentArea;
          setState(() {
            context
                .read<FilterPlate>()
                .filterByParkingLocation(PlateType.parkingCompleted, area, _selectedParkingArea!);
          });
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
    final movementPlate = context.read<MovementPlate>(); // ✅ MovementPlate 사용
    final userName = context.read<UserState>().name;
    final plateState = context.read<PlateState>();
    final selectedPlate = plateState.getSelectedPlate(PlateType.parkingCompleted, userName);

    if (selectedPlate != null) {
      try {
        movementPlate
            .setDepartureRequested(selectedPlate.plateNumber, selectedPlate.area, plateState, selectedPlate.location)
            .then((_) {
          // ✅ MovementPlate에서 호출
          Future.delayed(Duration(milliseconds: 300), () {
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

  void handleEntryRequest(BuildContext context, String plateNumber, String area) {
    final movementPlate = context.read<MovementPlate>();
    final plateState = context.read<PlateState>();

    movementPlate.goBackToParkingRequest(
      fromType: PlateType.parkingCompleted,
      // 🔄 수정: enum으로 전달
      plateNumber: plateNumber,
      area: area,
      newLocation: "미지정",
      plateState: plateState,
    );

    showSuccessSnackbar(context, "입차 요청이 완료되었습니다.");
  }

  @override
  Widget build(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;

    return PopScope(
        canPop: true,
        // ignore: deprecated_member_use
        onPopInvoked: (didPop) async {
          if (!didPop) return;

          final selectedPlate = plateState.getSelectedPlate(PlateType.parkingCompleted, userName);
          if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
            await plateState.toggleIsSelected(
              collection: PlateType.parkingCompleted,
              plateNumber: selectedPlate.plateNumber,
              userName: userName,
              onError: (msg) => debugPrint(msg),
            );
          }
        },
        child: Scaffold(
          appBar: const TopNavigation(),
          body: Consumer2<PlateState, AreaState>(
            builder: (context, plateState, areaState, child) {
              final currentArea = areaState.currentArea;
              final filterState = context.read<FilterPlate>();
              var parkingCompleted = _isParkingAreaMode && _selectedParkingArea != null
                  ? filterState.filterByParkingLocation(PlateType.parkingCompleted, currentArea, _selectedParkingArea!)
                  : plateState.getPlatesByCollection(PlateType.parkingCompleted);
              final userName = context.read<UserState>().name;
              parkingCompleted.sort((a, b) {
                return _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime);
              });
              return ListView(
                padding: const EdgeInsets.all(8.0),
                children: [
                  PlateContainer(
                    data: parkingCompleted,
                    collection: PlateType.parkingCompleted,
                    filterCondition: (request) => request.type == PlateType.parkingCompleted.firestoreValue,
                    onPlateTap: (plateNumber, area) {
                      plateState.toggleIsSelected(
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
            },
          ),
          bottomNavigationBar: Consumer<PlateState>(
            builder: (context, plateState, child) {
              final userName = context.read<UserState>().name;
              final selectedPlate = plateState.getSelectedPlate(PlateType.parkingCompleted, userName);
              final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;
              return BottomNavigationBar(
                  items: [
                    BottomNavigationBarItem(
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                        child: isPlateSelected
                            ? (selectedPlate.isLockedFee
                                ? const Icon(Icons.lock_open, key: ValueKey('unlock'), color: Colors.grey)
                                : const Icon(Icons.lock, key: ValueKey('lock'), color: Colors.grey))
                            : Icon(
                                _isSearchMode ? Icons.cancel : Icons.search,
                                key: ValueKey(_isSearchMode),
                                color: _isSearchMode ? Colors.orange : Colors.grey,
                              ),
                      ),
                      label: isPlateSelected
                          ? (selectedPlate.isLockedFee ? '정산 취소' : '사전 정산')
                          : (_isSearchMode ? '검색 초기화' : '번호판 검색'),
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(
                        isPlateSelected ? Icons.check_circle : Icons.local_parking,
                        color: isPlateSelected ? Colors.green : Colors.grey,
                      ),
                      label: isPlateSelected ? '출차 요청' : (_isParkingAreaMode ? '주차 구역 초기화' : '주차 구역'),
                    ),
                    BottomNavigationBarItem(
                      icon: AnimatedRotation(
                        turns: _isSorted ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: Transform.scale(
                          scaleX: _isSorted ? -1 : 1,
                          child: Icon(
                            isPlateSelected ? Icons.settings : Icons.sort,
                          ),
                        ),
                      ),
                      label: isPlateSelected ? '상태 수정' : (_isSorted ? '최신순' : '오래된순'),
                    ),
                  ],
                  onTap: (index) async {
                    if (index == 0) {
                      if (isPlateSelected) {
                        final adjustmentType = selectedPlate.adjustmentType;

                        // ✅ 정산 타입이 없는 경우 → 사전 정산 불가
                        if (adjustmentType == null || adjustmentType.trim().isEmpty) {
                          showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
                          return;
                        }

                        final now = DateTime.now();
                        final entryTime = selectedPlate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;
                        final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;

                        // ✅ 정산 취소 시 확인 다이얼로그
                        if (selectedPlate.isLockedFee) {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => const ConfirmCancelFeeDialog(),
                          );

                          if (confirm == true) {
                            final updatedPlate = selectedPlate.copyWith(
                              isLockedFee: false,
                              lockedAtTimeInSeconds: null,
                              lockedFeeAmount: null,
                            );

                            if (!context.mounted) return;

                            await context.read<PlateRepository>().addOrUpdatePlate(
                                  selectedPlate.id,
                                  updatedPlate,
                                );

                            if (!context.mounted) return;

                            await context
                                .read<PlateState>()
                                .updatePlateLocally(PlateType.parkingCompleted, updatedPlate);

                            if (!context.mounted) return;

                            showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
                          }

                          return;
                        }

                        // ✅ 사전 정산 수행
                        final lockedFee = calculateParkingFee(
                          entryTimeInSeconds: entryTime,
                          currentTimeInSeconds: currentTime,
                          basicStandard: selectedPlate.basicStandard ?? 0,
                          basicAmount: selectedPlate.basicAmount ?? 0,
                          addStandard: selectedPlate.addStandard ?? 0,
                          addAmount: selectedPlate.addAmount ?? 0,
                        ).round();

                        final updatedPlate = selectedPlate.copyWith(
                          isLockedFee: true,
                          lockedAtTimeInSeconds: currentTime,
                          lockedFeeAmount: lockedFee, // ✅ 사전 정산 금액 저장
                        );

                        await context.read<PlateRepository>().addOrUpdatePlate(
                              selectedPlate.id,
                              updatedPlate,
                            );

                        if (!context.mounted) return;

                        await context.read<PlateState>().updatePlateLocally(PlateType.parkingCompleted, updatedPlate);

                        if (!context.mounted) return;

                        showSuccessSnackbar(context, '사전 정산 완료: ₩$lockedFee');
                      } else {
                        _isSearchMode ? _resetSearch(context) : _showSearchDialog(context);
                      }
                    } else if (index == 1) {
                      if (isPlateSelected) {
                        showDialog(
                          context: context,
                          builder: (context) => DepartureRequestConfirmDialog(
                            onConfirm: () => _handleDepartureRequested(context),
                          ),
                        );
                      } else {
                        if (_isParkingAreaMode) {
                          _resetParkingAreaFilter(context);
                        } else {
                          _showParkingAreaDialog(context);
                        }
                      }
                    } else if (index == 2) {
                      if (isPlateSelected) {
                        showDialog(
                          context: context,
                          builder: (context) => ParkingCompletedStatusDialog(
                            plate: selectedPlate,
                            plateNumber: selectedPlate.plateNumber,
                            area: selectedPlate.area,
                            onRequestEntry: () {
                              handleEntryParkingRequest(context, selectedPlate.plateNumber, selectedPlate.area);
                            },
                            onDelete: () {
                              showDialog(
                                context: context,
                                builder: (context) => ParkingRequestDeleteDialog(
                                  onConfirm: () {
                                    context.read<DeletePlate>().deleteFromParkingCompleted(
                                          selectedPlate.plateNumber,
                                          selectedPlate.area,
                                        );
                                    showSuccessSnackbar(context, "삭제 완료: ${selectedPlate.plateNumber}");
                                  },
                                ),
                              );
                            },
                          ),
                        );
                      } else {
                        _toggleSortIcon();
                      }
                    }
                  });
            },
          ),
        ));
  }
}
