import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../states/plate/filter_plate.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/plate/plate_state.dart'; // 번호판 상태 관리
import '../../states/plate/delete_plate.dart';
import '../../states/area/area_state.dart'; // 지역 상태 관리
import '../../states/user/user_state.dart';
import '../../utils/fee_calculator.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/dialog/confirm_cancel_fee_dialog.dart';
import '../../widgets/dialog/departure_completed_confirm_dialog.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바
import '../../widgets/dialog/plate_search_dialog.dart'; // ✅ PlateSearchDialog 추가
import '../../widgets/dialog/departure_request_status_dialog.dart';
import '../../widgets/dialog/parking_request_delete_dialog.dart';
import '../../utils/snackbar_helper.dart';

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
            context.read<FilterPlate>().filterByParkingLocation('departure_requests', area, _selectedParkingArea!);
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

  void _handleDepartureCompleted(BuildContext context) {
    final movementPlate = context.read<MovementPlate>(); // ✅ MovementPlate 사용
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;
    final selectedPlate = plateState.getSelectedPlate('departure_requests', userName);
    if (selectedPlate != null) {
      try {
        plateState.toggleIsSelected(
          collection: 'departure_requests',
          plateNumber: selectedPlate.plateNumber,
          userName: userName,
          onError: (errorMessage) {
          },
        );
        movementPlate.setDepartureCompleted(
            selectedPlate.plateNumber, selectedPlate.area, plateState, selectedPlate.location);
        showSuccessSnackbar(context, "출차 완료 처리되었습니다.");
      } catch (e) {
        debugPrint("출차 완료 처리 실패: $e");
        showFailedSnackbar(context, "출차 완료 처리 중 오류 발생: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;

    return WillPopScope(
        onWillPop: () async {
          final selectedPlate = plateState.getSelectedPlate('departure_requests', userName);
          if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
            await plateState.toggleIsSelected(
              collection: 'departure_requests',
              plateNumber: selectedPlate.plateNumber,
              userName: userName,
              onError: (msg) => debugPrint(msg),
            );
            return false;
          }
          return true;
        },
        child: Scaffold(
          appBar: const TopNavigation(),
          body: Consumer2<PlateState, AreaState>(
            builder: (context, plateState, areaState, child) {
              final currentArea = areaState.currentArea;
              final filterState = context.read<FilterPlate>(); // 🔹 FilterState 가져오기
              var departureRequests = _isParkingAreaMode && _selectedParkingArea != null
                  ? filterState.filterByParkingLocation('departure_requests', currentArea, _selectedParkingArea!)
                  : plateState.getPlatesByCollection('departure_requests');
              final userName = context.read<UserState>().name;
              departureRequests.sort((a, b) {
                return _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime);
              });
              return ListView(
                padding: const EdgeInsets.all(8.0),
                children: [
                  PlateContainer(
                    data: departureRequests,
                    collection: 'departure_requests',
                    filterCondition: (request) => request.type == '출차 요청' || request.type == '출차 중',
                    onPlateTap: (plateNumber, area) {
                      plateState.toggleIsSelected(
                        collection: 'departure_requests',
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
              final selectedPlate = plateState.getSelectedPlate('departure_requests', userName);
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
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                        child: isPlateSelected
                            ? const Icon(Icons.check_circle, key: ValueKey('selected'), color: Colors.green)
                            : Icon(
                                _isParkingAreaMode ? Icons.clear : Icons.local_parking,
                                key: ValueKey(_isParkingAreaMode),
                                color: _isParkingAreaMode ? Colors.orange : Colors.grey,
                              ),
                      ),
                      label: isPlateSelected ? '출차 완료' : (_isParkingAreaMode ? '주차 구역 초기화' : '주차 구역'),
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

                        if (selectedPlate.isLockedFee) {
                          // ✅ 정산 취소 전 확인 다이얼로그
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => const ConfirmCancelFeeDialog(), // ✅ 별도 다이얼로그로 분리 필요
                          );

                          if (confirm != true) return;

                          final updatedPlate = selectedPlate.copyWith(
                            isLockedFee: false,
                            lockedAtTimeInSeconds: null,
                            lockedFeeAmount: null,

                          );

                          await context.read<PlateRepository>().addOrUpdateDocument(
                            'departure_requests',
                            selectedPlate.id,
                            updatedPlate.toMap(),
                          );

                          await context.read<PlateState>().updatePlateLocally('departure_requests', updatedPlate);

                          showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
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

                        await context.read<PlateRepository>().addOrUpdateDocument(
                          'departure_requests',
                          selectedPlate.id,
                          updatedPlate.toMap(),
                        );

                        await context.read<PlateState>().updatePlateLocally('departure_requests', updatedPlate);

                        showSuccessSnackbar(context, '사전 정산 완료: ₩$lockedFee');
                      } else {
                        _isSearchMode ? _resetSearch(context) : _showSearchDialog(context);
                      }
                    }
                    else if (index == 1) {
                      if (isPlateSelected) {
                        showDialog(
                          context: context,
                          builder: (context) => DepartureCompletedConfirmDialog(
                            onConfirm: () => _handleDepartureCompleted(context),
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
                          builder: (context) => DepartureRequestStatusDialog(
                            plate: selectedPlate,
                            plateNumber: selectedPlate.plateNumber,
                            area: selectedPlate.area,
                            onRequestEntry: () {
                              handleEntryParkingRequest(
                                context,
                                selectedPlate.plateNumber,
                                selectedPlate.area,
                              );
                            },
                            onCompleteEntry: () {
                              handleEntryParkingCompleted(
                                context,
                                selectedPlate.plateNumber,
                                selectedPlate.area,
                                selectedPlate.location,
                              );
                            },
                            onDelete: () {
                              showDialog(
                                context: context,
                                builder: (context) => ParkingRequestDeleteDialog(
                                  onConfirm: () {
                                    context.read<DeletePlate>().deletePlateFromDepartureRequest(
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
