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
import '../../states/area/area_state.dart';
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
                              final parsed = jsonDecode(content); // content는 JSON string

                              final dateStr = DateTime.now().toIso8601String().split('T').first;
                              final summaryRef = FirebaseFirestore.instance
                                  .collection('fee_summaries')
                                  .doc('${division}_$area\_$dateStr');

                              // ✅ 요약 문서 없으면 생성
                              final doc = await summaryRef.get();
                              if (!doc.exists) {
                                await updateLockedFeeSummary(division, area);
                              }

                              // ✅ 정산 금액 읽기
                              final latest = await summaryRef.get();
                              final totalLockedFee = latest['totalLockedFee'] ?? 0;

                              // ✅ 보고 데이터 구성
                              final reportLog = {
                                'division': division,
                                'area': area,
                                'vehicleCount': {
                                  'vehicleInput': int.tryParse(parsed['vehicleInput'].toString()) ?? 0,
                                  'vehicleOutput': int.tryParse(parsed['vehicleOutput'].toString()) ?? 0,
                                },
                                'totalLockedFee': totalLockedFee, // 🔥 추가된 부분
                                'timestamp': DateTime.now().toIso8601String(),
                              };

                              // ✅ 종료 보고 업로드
                              await uploadEndWorkReportJson(
                                report: reportLog,
                                division: division,
                                area: area,
                                userName: userName,
                              );

                              // ✅ plates 문서 초기화
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
