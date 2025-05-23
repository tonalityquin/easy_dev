import 'package:easydev/screens/type_pages/parking_requests_pages/report_dialog.dart';
import 'package:easydev/states/plate/filter_plate.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/plate_model.dart';
import '../../states/plate/plate_state.dart';
import '../../states/plate/delete_plate.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';
import '../../utils/gcs_uploader.dart';
import '../../widgets/container/plate_container.dart';
import '../../widgets/dialog/adjustment_type_confirm_dialog.dart';
import '../../widgets/dialog/confirm_cancel_fee_dialog.dart';
import '../../widgets/dialog/parking_request_status_dialog.dart';
import '../../widgets/navigation/top_navigation.dart';
import '../../widgets/dialog/plate_search_dialog.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../enums/plate_type.dart';

class ParkingRequestPage extends StatefulWidget {
  const ParkingRequestPage({super.key});

  @override
  State<ParkingRequestPage> createState() => _ParkingRequestPageState();
}

class _ParkingRequestPageState extends State<ParkingRequestPage> {
  bool _isSorted = true;
  bool _isSearchMode = false;
  bool _showReportDialog = false; // 👈 추가

  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });

    context.read<PlateState>().updateSortOrder(
          PlateType.parkingRequests,
          _isSorted, // true: 최신순, false: 오래된순
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
    context.read<PlateState>().toggleIsSelected(
          collection: PlateType.parkingRequests,
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
    final selectedPlate = plateState.getSelectedPlate(PlateType.parkingRequests, userName);
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
    final movementPlate = context.read<MovementPlate>();
    final plateState = context.read<PlateState>();
    final plateRepository = context.read<PlateRepository>();

    try {
      plateRepository.addRequestOrCompleted(
        plateNumber: plateNumber,
        location: location,
        area: area,
        userName: context.read<UserState>().name,
        plateType: PlateType.parkingCompleted,
        // ✅ 수정된 부분
        adjustmentType: null,
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

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        final selectedPlate = plateState.getSelectedPlate(
          PlateType.parkingRequests,
          userName,
        );
        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await plateState.toggleIsSelected(
            collection: PlateType.parkingRequests,
            plateNumber: selectedPlate.plateNumber,
            userName: userName,
            onError: (msg) => debugPrint(msg),
          );
        }

        if (_showReportDialog) {
          setState(() => _showReportDialog = false);
        }
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
                    future: context.read<FilterPlate>().fetchPlatesBySearchQuery(),
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
                  final plates = plateState.getPlatesByCollection(PlateType.parkingRequests);
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
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              bottom: _showReportDialog ? 0 : -600,
              left: 0,
              right: 0,
              child: Material(
                elevation: 8,
                color: Colors.white,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                      left: 16,
                      right: 16,
                      top: 16,
                    ),
                    child: SingleChildScrollView(
                        child: ParkingReportContent(
                          onReport: (type, content) async {
                            if (type == 'cancel') {
                              setState(() => _showReportDialog = false);
                              return;
                            }

                            final area = context.read<AreaState>().currentArea;
                            final division = context.read<AreaState>().currentDivision;
                            final userName = context.read<UserState>().name;

                            if (type == 'end') {
                              final reportLog = {
                                'division': division,
                                'area': area,
                                'vehicleCount': content,
                                'timestamp': DateTime.now().toIso8601String(),
                              };

                              await uploadEndWorkReportJson(
                                report: reportLog,
                                division: division,
                                area: area,
                                userName: userName,
                              );

                              await deleteLockedDepartureDocs(area);

                              showSuccessSnackbar(context, "업무 종료 보고 업로드 및 출차 초기화 (차량 수: \$content)");
                            } else if (type == 'start') {
                              showSuccessSnackbar(context, "업무 시작 보고 완료: \$content");
                            } else if (type == 'middle') {
                              showSuccessSnackbar(context, "보고란 제출 완료: \$content");
                            }

                            setState(() => _showReportDialog = false);
                          },
                        ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: Consumer<PlateState>(
          builder: (context, plateState, child) {
            final userName = context.read<UserState>().name;
            final selectedPlate = plateState.getSelectedPlate(PlateType.parkingRequests, userName);
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

                    if (adjustmentType == null || adjustmentType.trim().isEmpty) {
                      showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
                      return;
                    }

                    final now = DateTime.now();
                    final entryTime = selectedPlate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;
                    final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;

                    // ✅ 로그 저장용
                    final uploader = GCSUploader();
                    final division = context.read<AreaState>().currentDivision;
                    final area = context.read<AreaState>().currentArea.trim();
                    final userName = context.read<UserState>().name;

                    // ✅ 사전 정산 이미 된 경우 → 취소 처리
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
                        paymentMethod: null,
                      );

                      if (!context.mounted) return;
                      await context.read<PlateRepository>().addOrUpdatePlate(
                            selectedPlate.id,
                            updatedPlate,
                          );

                      if (!context.mounted) return;
                      await context.read<PlateState>().updatePlateLocally(
                            PlateType.parkingRequests,
                            updatedPlate,
                          );

                      if (!context.mounted) return;

                      // ✅ 사전 정산 취소 로그
                      final cancelLog = {
                        'plateNumber': selectedPlate.plateNumber,
                        'action': '사전 정산 취소',
                        'performedBy': userName,
                        'timestamp': DateTime.now().toIso8601String(),
                      };
                      if (adjustmentType.trim().isNotEmpty) {
                        cancelLog['adjustmentType'] = adjustmentType;
                      }

                      await uploader.uploadLogJson(
                        cancelLog,
                        selectedPlate.plateNumber,
                        division,
                        area,
                        adjustmentType: adjustmentType,
                      );

                      showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
                      return;
                    }

                    // ✅ 사전 정산 처리
                    final result = await showAdjustmentTypeConfirmDialog(
                      context: context,
                      entryTimeInSeconds: entryTime,
                      currentTimeInSeconds: currentTime,
                      basicStandard: selectedPlate.basicStandard ?? 0,
                      basicAmount: selectedPlate.basicAmount ?? 0,
                      addStandard: selectedPlate.addStandard ?? 0,
                      addAmount: selectedPlate.addAmount ?? 0,
                    );

                    if (result == null) return;

                    final updatedPlate = selectedPlate.copyWith(
                      isLockedFee: true,
                      lockedAtTimeInSeconds: currentTime,
                      lockedFeeAmount: result.lockedFee,
                      paymentMethod: result.paymentMethod,
                    );

                    await context.read<PlateRepository>().addOrUpdatePlate(
                          selectedPlate.id,
                          updatedPlate,
                        );

                    if (!context.mounted) return;
                    await context.read<PlateState>().updatePlateLocally(
                          PlateType.parkingRequests,
                          updatedPlate,
                        );

                    if (!context.mounted) return;

                    // ✅ 사전 정산 완료 로그
                    final log = {
                      'plateNumber': selectedPlate.plateNumber,
                      'action': '사전 정산',
                      'performedBy': userName,
                      'timestamp': DateTime.now().toIso8601String(),
                      'lockedFee': result.lockedFee,
                      'paymentMethod': result.paymentMethod,
                    };
                    if (adjustmentType.trim().isNotEmpty) {
                      log['adjustmentType'] = adjustmentType;
                    }

                    await uploader.uploadLogJson(
                      log,
                      selectedPlate.plateNumber,
                      division,
                      area,
                      adjustmentType: adjustmentType,
                    );

                    showSuccessSnackbar(context, '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})');
                  } else {
                    _isSearchMode ? _resetSearch(context) : _showSearchDialog(context);
                  }
                } else if (index == 1) {
                  if (isPlateSelected) {
                    _handleParkingCompleted(context);
                  } else {
                    setState(() {
                      _showReportDialog = !_showReportDialog; // ✅ 이미 열려있으면 닫히게!
                    });
                  }
                } else if (index == 2) {
                  if (isPlateSelected) {
                    final selectedPlate = plateState.getSelectedPlate(PlateType.parkingRequests, userName);
                    if (selectedPlate != null) {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return ParkingRequestStatusDialog(
                            plate: selectedPlate,
                            plateNumber: selectedPlate.plateNumber,
                            area: selectedPlate.area,
                            onCancelEntryRequest: () {
                              context.read<DeletePlate>().deleteFromParkingRequest(
                                    selectedPlate.plateNumber,
                                    selectedPlate.area,
                                  );
                              showSuccessSnackbar(context, "입차 요청이 취소되었습니다: ${selectedPlate.plateNumber}");
                            },
                            onDelete: () {},
                          );
                        },
                      );
                    }
                  } else {
                    _toggleSortIcon();
                  }
                }
              },
            );
          },
        ),
      ),
    );
  }
}
