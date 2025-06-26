import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';

import '../../repositories/plate/plate_repository.dart';

import '../../states/plate/filter_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/area/spot_state.dart';
import '../../states/user/user_state.dart';

import '../../utils/snackbar_helper.dart';

import '../../widgets/navigation/top_navigation.dart';
import '../../widgets/dialog/plate_search_dialog.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../widgets/container/plate_container.dart';

import 'parking_requests_pages/report_dialog.dart';
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

  Future<void> updateLockedFeeSummary(String division, String area) async {
    final firestore = FirebaseFirestore.instance;
    final date = DateTime.now();
    final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

    final snapshot = await firestore
        .collection('plates')
        .where('type', isEqualTo: 'departure_completed')
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: true)
        .get();

    int total = 0;
    int count = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final fee = data['lockedFeeAmount'];
      if (fee is int) {
        total += fee;
        count++;
      } else if (fee is double) {
        total += fee.round();
        count++;
      }
    }

    final summaryRef = firestore.collection('fee_summaries').doc('${division}_$area\_$dateStr');
    await summaryRef.set({
      'division': division,
      'area': area,
      'date': dateStr,
      'totalLockedFee': total,
      'vehicleCount': count,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
  }

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
    context.read<PlateState>().toggleIsSelected(
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
          await plateState.toggleIsSelected(
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
                            final parsed = jsonDecode(content);

                            final dateStr = DateTime.now().toIso8601String().split('T').first;
                            final summaryRef = FirebaseFirestore.instance
                                .collection('fee_summaries')
                                .doc('${division}_$area\_$dateStr');

                            final doc = await summaryRef.get();
                            if (!doc.exists) {
                              await updateLockedFeeSummary(division, area);
                            }

                            final latest = await summaryRef.get();
                            final totalLockedFee = latest['totalLockedFee'] ?? 0;

                            final reportLog = {
                              'division': division,
                              'area': area,
                              'vehicleCount': {
                                'vehicleInput': int.tryParse(parsed['vehicleInput'].toString()) ?? 0,
                                'vehicleOutput': int.tryParse(parsed['vehicleOutput'].toString()) ?? 0,
                              },
                              'totalLockedFee': totalLockedFee,
                              'timestamp': DateTime.now().toIso8601String(),
                            };

                            await uploadEndWorkReportJson(
                              report: reportLog,
                              division: division,
                              area: area,
                              userName: userName,
                            );

                            await deleteLockedDepartureDocs(area);

                            showSuccessSnackbar(
                              context,
                              "업무 종료 보고 업로드 및 출차 초기화 "
                              "(입차: ${parsed['vehicleInput']}, 출차: ${parsed['vehicleOutput']}, 금액: ₩$totalLockedFee)",
                            );
                          } else if (type == 'start') {
                            showSuccessSnackbar(context, "업무 시작 보고 완료: $content");
                          } else if (type == 'middle') {
                            final user = context.read<UserState>().user;

                            if (user == null || user.divisions.isEmpty) {
                              showFailedSnackbar(context, '사용자 정보가 없어 보고를 저장할 수 없습니다.');
                              return;
                            }

                            await FirebaseFirestore.instance.collection('tasks').add({
                              'creator': user.id,
                              'division': user.divisions.first,
                              'answer': content,
                              'createdAt': DateTime.now().toIso8601String(),
                            });

                            showSuccessSnackbar(context, "보고란 제출 완료: $content");
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
