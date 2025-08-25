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

/// 잠금 요금 안전 추출
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

/// JSON 인코딩 가능한 값으로 변환(Logs 내부에 Timestamp 등이 있어도 안전하게)
dynamic _jsonSafe(dynamic v) {
  if (v is Timestamp) return v.toDate().toIso8601String();
  if (v is DateTime) return v.toIso8601String();
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), _jsonSafe(val)));
  }
  if (v is List) {
    return v.map(_jsonSafe).toList();
  }
  return v;
}

Future<void> showReportDialog(BuildContext context) async {
  // 다이얼로그 열기 전에 현재 지역 읽고 자동 집계값 미리 구하기
  final area = context.read<AreaState>().currentArea;

  int prefilledVehicleOutput = 0; // 출차(전체): departure_completed && isLockedFee
  int prefilledVehicleInput = 0; // 입차(전체): parking_completed

  try {
    if (area.isNotEmpty) {
      prefilledVehicleOutput = await PlateCountService().getLockedDepartureCountAll(area);
      prefilledVehicleInput = await PlateCountService().getParkingCompletedCountAll(area);
    }
  } catch (_) {
    prefilledVehicleOutput = 0;
    prefilledVehicleInput = 0;
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black54,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                    // 1) 입력 파싱
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

                    // 2) 전체 누적 요약을 갱신하기 위한 스냅샷 확보(이 스냅샷을 logs 추출에도 재사용)
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

                    // 3) 요약 문서 upsert
                    final summaryRef =
                        FirebaseFirestore.instance.collection('fee_summaries').doc('${division}_${area}_all');

                    await summaryRef.set({
                      'division': division,
                      'area': area,
                      'scope': 'all',
                      'totalLockedFee': total,
                      'lockedVehicleCount': platesSnap.size,
                      'lastUpdated': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));

                    // 4) 최신 합계 읽기
                    final latestSnap = await summaryRef.get();
                    final latestData = latestSnap.data();
                    final totalLockedFee = (latestData?['totalLockedFee'] ?? 0) is num
                        ? (latestData?['totalLockedFee'] as num).round()
                        : 0;

                    // 5) 출차 차량 수 자동 집계(전체)로 보정하고 보고 JSON 구성
                    final vehicleOutputAuto = await PlateCountService().getLockedDepartureCountAll(area);

                    final reportLog = {
                      'division': division,
                      'area': area,
                      'vehicleCount': {
                        'vehicleInput': int.tryParse('${parsed['vehicleInput']}') ?? 0,
                        'vehicleOutput': vehicleOutputAuto,
                      },
                      'totalLockedFee': totalLockedFee,
                      'timestamp': FieldValue.serverTimestamp(),
                    };

                    // 6) 보고 JSON 업로드(GCS)
                    await uploadEndWorkReportJson(
                      report: reportLog,
                      division: division,
                      area: area,
                      userName: userName,
                    );

                    // 7) 🔥 logs 집계 JSON 생성 → 업로드(GCS)
                    final List<Map<String, dynamic>> items = [];
                    for (final doc in platesSnap.docs) {
                      final data = doc.data();
                      items.add({
                        'docId': doc.id,
                        'logs': _jsonSafe(data['logs'] ?? []),
                      });
                    }

                    final logsPayload = {
                      'division': division,
                      'area': area,
                      'items': items,
                    };

                    await uploadEndLogJson(
                      report: logsPayload,
                      division: division,
                      area: area,
                      userName: userName,
                    );

                    // 8) 필요 시 문서 삭제(보고·백업 완료 후)
                    // await deleteLockedDepartureDocs(area);

                    // 9) UI 피드백
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

/// 🔧 보고 후 정리: departure_completed & isLockedFee=true 문서 일괄 삭제
Future<void> deleteLockedDepartureDocs(String area) async {
  final firestore = FirebaseFirestore.instance;

  final snap = await firestore
      .collection('plates')
      .where('type', isEqualTo: 'departure_completed')
      .where('area', isEqualTo: area)
      .where('isLockedFee', isEqualTo: true)
      .get();

  if (snap.docs.isEmpty) return;

  final batch = firestore.batch();
  for (final d in snap.docs) {
    batch.delete(d.reference);
  }
  await batch.commit();
}
