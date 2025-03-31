import 'package:easydev/states/plate/filter_plate.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate/plate_state.dart'; // PlateState 상태 관리
import '../../states/plate/delete_plate.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/area/area_state.dart'; // AreaState 상태 관리
import '../../states/user/user_state.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 데이터를 표시하는 위젯
import '../../widgets/dialog/confirm_cancel_fee_dialog.dart';
import '../../widgets/dialog/parking_request_status_dialog.dart';
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바
import '../../widgets/dialog/plate_search_dialog.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../utils/fee_calculator.dart';

class ParkingRequestPage extends StatefulWidget {
  const ParkingRequestPage({super.key});

  @override
  State<ParkingRequestPage> createState() => _ParkingRequestPageState();
}

class _ParkingRequestPageState extends State<ParkingRequestPage> {
  bool _isSorted = true;
  bool _isSearchMode = false;

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

  void _resetSearch(BuildContext context) {
    context.read<FilterPlate>().clearPlateSearchQuery();
    setState(() {
      _isSearchMode = false;
    });
  }

  void _handlePlateTap(BuildContext context, String plateNumber, String area) {
    final userName = context.read<UserState>().name;
    context.read<PlateState>().toggleIsSelected(
          collection: 'parking_requests',
          plateNumber: plateNumber,
          userName: userName,
          onError: (errorMessage) {
            showFailedSnackbar(context, errorMessage);
          },
        );
  }

  void _handleParkingCompleted(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;
    final selectedPlate = plateState.getSelectedPlate('parking_requests', userName);
    if (selectedPlate != null) {
      final TextEditingController locationController = TextEditingController();
      showDialog(
        context: context,
        builder: (context) {
          return ParkingLocationDialog(
            locationController: locationController,
            onLocationSelected: (String location) {
              if (location.isNotEmpty) {
                _completeParking(
                  context,
                  selectedPlate.plateNumber,
                  selectedPlate.area,
                  location,
                  selectedPlate.region ?? '전국',
                );
              } else {
                showFailedSnackbar(context, '주차 구역을 입력해주세요.');
              }
            },
          );
        },
      );
    }
  }

  void _completeParking(BuildContext context, String plateNumber, String area, String location, String region) {
    final movementPlate = context.read<MovementPlate>(); // ✅ MovementPlate 사용
    final plateState = context.read<PlateState>(); // ✅ PlateState 추가
    final plateRepository = context.read<PlateRepository>();

    try {
      plateRepository.addRequestOrCompleted(
        collection: 'parking_completed',
        plateNumber: plateNumber,
        location: location,
        area: area,
        userName: context.read<UserState>().name,
        type: '입차 완료',
        adjustmentType: null,
        statusList: [],
        basicStandard: 0,
        basicAmount: 0,
        addStandard: 0,
        addAmount: 0,
        region: region,
      );

      movementPlate.setParkingCompleted(plateNumber, area, plateState, location); // ✅ PlateState 추가
      showSuccessSnackbar(context, "입차 완료: $plateNumber ($location)");
    } catch (e) {
      debugPrint("입차 완료 처리 실패: $e");
      showFailedSnackbar(context, "입차 완료 처리 중 오류 발생: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;

    return WillPopScope(
        onWillPop: () async {
          final selectedPlate = plateState.getSelectedPlate('parking_requests', userName);
          if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
            await plateState.toggleIsSelected(
              collection: 'parking_requests',
              plateNumber: selectedPlate.plateNumber,
              userName: userName,
              onError: (msg) => debugPrint(msg),
            );
            return false; // 뒤로가기 취소, 선택만 해제
          }
          return true; // 선택 없으면 정상 뒤로가기
        },
        child: Scaffold(
          appBar: const TopNavigation(),
          body: Consumer2<PlateState, AreaState>(
            builder: (context, plateState, areaState, child) {
              var parkingRequests = plateState.getPlatesByCollection('parking_requests');
              parkingRequests.sort((a, b) {
                return _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime);
              });
              return ListView(
                padding: const EdgeInsets.all(8.0),
                children: [
                  PlateContainer(
                    data: parkingRequests,
                    collection: 'parking_requests',
                    filterCondition: (request) => request.type == '입차 요청' || request.type == '입차 중',
                    onPlateTap: (plateNumber, area) {
                      _handlePlateTap(context, plateNumber, area);
                    },
                  ),
                ],
              );
            },
          ),
          bottomNavigationBar: Consumer<PlateState>(
            builder: (context, plateState, child) {
              final userName = context.read<UserState>().name;
              final selectedPlate = plateState.getSelectedPlate('parking_requests', userName);
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
                      icon: isPlateSelected
                          ? Icon(Icons.check_circle, color: Colors.green)
                          : Image.asset(
                              'assets/icons/icon_belivussnc.PNG',
                              width: 24.0,
                              height: 24.0,
                              fit: BoxFit.contain,
                            ),
                      label: isPlateSelected ? '입차 완료' : 'Belivus S&C',
                    ),
                    BottomNavigationBarItem(
                      icon: AnimatedRotation(
                        turns: _isSorted ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: Transform.scale(
                          scaleX: _isSorted ? -1 : 1,
                          child: Icon(
                            isPlateSelected ? Icons.settings : Icons.sort, // 🔁 상태 수정 아이콘
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

                        if (adjustmentType == null || adjustmentType.trim().isEmpty) {
                          showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
                          return;
                        }

                        final now = DateTime.now();
                        final entryTime = selectedPlate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;
                        final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;

                        // ✅ lockedFee를 미리 선언
                        int lockedFee = 0;

                        if (selectedPlate.isLockedFee) {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => const ConfirmCancelFeeDialog(),
                          );

                          if (confirm != true) return;

                          final updatedPlate = selectedPlate.copyWith(
                            isLockedFee: false,
                            lockedAtTimeInSeconds: null,
                            lockedFeeAmount: null,
                          );

                          await context.read<PlateRepository>().addOrUpdateDocument(
                            'parking_requests',
                            selectedPlate.id,
                            updatedPlate.toMap(),
                          );

                          await context.read<PlateState>().updatePlateLocally('parking_requests', updatedPlate);
                          showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
                          return;
                        }

                        // ✅ 사전 정산 요금 계산 및 적용
                        lockedFee = calculateParkingFee(
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
                          'parking_requests',
                          selectedPlate.id,
                          updatedPlate.toMap(),
                        );

                        await context.read<PlateState>().updatePlateLocally('parking_requests', updatedPlate);
                        showSuccessSnackbar(context, '사전 정산 완료: ₩$lockedFee');
                      } else {
                        _isSearchMode ? _resetSearch(context) : _showSearchDialog(context);
                      }
                    }
                    else if (index == 1 && isPlateSelected) {
                      _handleParkingCompleted(context);
                    } else if (index == 2) {
                      if (isPlateSelected) {
                        final selectedPlate = plateState.getSelectedPlate('parking_requests', userName);
                        if (selectedPlate != null) {
                          showDialog(
                            context: context,
                            builder: (context) {
                              return ParkingRequestStatusDialog(
                                plate: selectedPlate,
                                plateNumber: selectedPlate.plateNumber,
                                area: selectedPlate.area,
                                onCancelEntryRequest: () {
                                  context.read<DeletePlate>().deletePlateFromParkingRequest(
                                        selectedPlate.plateNumber,
                                        selectedPlate.area,
                                      );
                                  showSuccessSnackbar(context, "입차 요청이 취소되었습니다: ${selectedPlate.plateNumber}");
                                },
                                onPrePayment: () {
                                  handleEntryDepartureCompleted(
                                    context,
                                    selectedPlate.plateNumber,
                                    selectedPlate.area,
                                    selectedPlate.location,
                                  );
                                },
                                onDelete: () {}, // ❗삭제는 현재는 사용되지 않지만 인터페이스 유지
                              );
                            },
                          );
                        }
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
