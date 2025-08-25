import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/area/area_state.dart';
import '../../../../../../states/user/user_state.dart';
import '../../../../../../utils/snackbar_helper.dart';
import '../../../../../../utils/blocking_dialog.dart';

import '../../../../../repositories/plate/plate_count_service.dart';

import 'end_work_report_content.dart';

int _extractLockedFeeAmount(Map<String, dynamic> data) {
  final top = data['lockedFeeAmount'];
  if (top is num) return top.round();

  final logs = data['logs'];
  if (logs is List) {
    for (int i = logs.length - 1; i >= 0; i--) {
      final item = logs[i];
      if (item is Map<String, dynamic>) {
        final lf = item['lockedFee'];
        if (lf is num) return lf.round();
      }
    }
  }
  return 0;
}

Future<void> showReportDialog(BuildContext context) async {
  // 다이얼로그 열기 전에 현재 지역 읽고 자동 집계값 미리 구하기
  final area = context.read<AreaState>().currentArea;

  int prefilledVehicleOutput = 0; // 출차 차량 수(전체): departure_completed && isLockedFee
  int prefilledVehicleInput  = 0; // 입차 차량 수(전체): parking_completed

  try {
    if (area.isNotEmpty) {
      prefilledVehicleOutput =
      await PlateCountService().getLockedDepartureCountAll(area);
      prefilledVehicleInput =
      await PlateCountService().getParkingCompletedCountAll(area);
    }
  } catch (_) {
    prefilledVehicleOutput = 0;
    prefilledVehicleInput = 0;
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.all(20),
          child: EndWorkReportContent(
            // ✅ 초기값 주입
            initialVehicleInput: prefilledVehicleInput,
            initialVehicleOutput: prefilledVehicleOutput,
            onReport: (type, content) async {
              if (type == 'cancel') {
                if (Navigator.canPop(context)) Navigator.pop(context);
                return;
              }

              await runWithBlockingDialog(
                context: context,
                message: '보고 처리 중입니다. 잠시만 기다려 주세요...',
                task: () async {
                  final area = context.read<AreaState>().currentArea;
                  final division = context.read<AreaState>().currentDivision;
                  final userName = context.read<UserState>().name;

                  if (type == 'end') {
                    Map<String, dynamic> parsed;
                    try {
                      final decoded = jsonDecode(content);
                      if (decoded is Map<String, dynamic>) {
                        parsed = decoded;
                      } else {
                        throw const FormatException('JSON은 객체 형태여야 합니다.');
                      }
                    } on FormatException {
                      if (context.mounted) {
                        showFailedSnackbar(context, '보고 데이터 형식이 올바르지 않습니다.');
                      }
                      return;
                    } catch (_) {
                      if (context.mounted) {
                        showFailedSnackbar(context, '보고 데이터 파싱 중 오류가 발생했습니다.');
                      }
                      return;
                    }

                    // 전체 누적 요약 갱신 (기존 로직 유지)
                    final summaryRef = FirebaseFirestore.instance
                        .collection('fee_summaries')
                        .doc('${division}_${area}_all');

                    final platesSnap = await FirebaseFirestore.instance
                        .collection('plates')
                        .where('type', isEqualTo: 'departure_completed')
                        .where('area', isEqualTo: area)
                        .where('isLockedFee', isEqualTo: true)
                        .get();

                    int total = 0;
                    for (final d in platesSnap.docs) {
                      total += _extractLockedFeeAmount(d.data());
                    }

                    await summaryRef.set({
                      'division': division,
                      'area': area,
                      'scope': 'all',
                      'totalLockedFee': total,
                      'lockedVehicleCount': platesSnap.size,
                      'lastUpdated': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));

                    final latestSnap = await summaryRef.get();
                    final latestData = latestSnap.data();
                    final totalLockedFee =
                    (latestData?['totalLockedFee'] ?? 0) is num
                        ? (latestData?['totalLockedFee'] as num).round()
                        : 0;

                    // 제출 시점에도 최신 개수로 보정하고 싶다면 다시 호출
                    final vehicleOutputAuto =
                    await PlateCountService().getLockedDepartureCountAll(area);

                    final reportLog = {
                      'division': division,
                      'area': area,
                      'vehicleCount': {
                        'vehicleInput':
                        int.tryParse('${parsed['vehicleInput']}') ?? 0,
                        'vehicleOutput': vehicleOutputAuto, // 자동 집계
                      },
                      'totalLockedFee': totalLockedFee,
                      'timestamp': FieldValue.serverTimestamp(),
                    };

                    await uploadEndWorkReportJson(
                      report: reportLog,
                      division: division,
                      area: area,
                      userName: userName,
                    );

                    await deleteLockedDepartureDocs(area);

                    if (context.mounted) {
                      Navigator.pop(context);
                      showSuccessSnackbar(
                        context,
                        "업무 종료 보고 업로드 및 출차 초기화 "
                            "(입차: ${parsed['vehicleInput']}, 출차: $vehicleOutputAuto • 전체집계)",
                      );
                    }
                  } else if (type == 'start') {
                    if (context.mounted) {
                      Navigator.pop(context);
                      showSuccessSnackbar(context, "업무 시작 보고 완료: $content");
                    }
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
                      'createdAt': FieldValue.serverTimestamp(),
                    });

                    if (context.mounted) {
                      Navigator.pop(context);
                      showSuccessSnackbar(context, "보고란 제출 완료: $content");
                    }
                  }
                },
              );
            },
          ),
        ),
      );
    },
  );
}
