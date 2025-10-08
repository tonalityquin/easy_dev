// lib/screens/type_package/common_widgets/dashboard_bottom_sheet/widgets/home_show_report_dialog.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../repositories/plate_repo_services/plate_count_service.dart';
import '../../../../../../states/area/area_state.dart';
import '../../../../../../states/user/user_state.dart';
import '../../../../../../utils/snackbar_helper.dart';
import '../../../../../../utils/blocking_dialog.dart';
// import '../../../../../../utils/usage_reporter.dart';
import '../../../../../../utils/gcs_uploader.dart';
import 'home_end_work_report_content.dart';

int _extractLockedFeeAmountSafe(Map<String, dynamic> data) {
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

dynamic _jsonSafe(dynamic v) {
  if (v is Timestamp) return v.toDate().toIso8601String();
  if (v is DateTime) return v.toIso8601String();
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), _jsonSafe(val)));
  }
  if (v is List) return v.map(_jsonSafe).toList();
  return v;
}

Future<void> showHomeReportDialog(BuildContext context) async {
  final area = context.read<AreaState>().currentArea;
  int prefilledVehicleOutput = 0;
  int prefilledVehicleInput = 0;

  try {
    if (area.isNotEmpty) {
      prefilledVehicleOutput = await PlateCountService().getDepartureCompletedCountAll(area);
      /*await UsageReporter.instance.annotate(
        area: area,
        source: 'showHomeReportDialog.prefetch.departure_completed.aggregate',
        extra: {'value': prefilledVehicleOutput},
      );*/

      prefilledVehicleInput = await PlateCountService().getParkingCompletedCountAll(area);
      /*await UsageReporter.instance.annotate(
        area: area,
        source: 'showHomeReportDialog.prefetch.parking_completed.aggregate',
        extra: {'value': prefilledVehicleInput},
      );*/
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
    builder: (ctx) {
      final bottomInset = MediaQuery.of(ctx).viewInsets.bottom + 16;
      return FractionallySizedBox(
        heightFactor: 1,
        child: SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset),
              child: HomeEndWorkReportContent(
                initialVehicleInput: prefilledVehicleInput,
                initialVehicleOutput: prefilledVehicleOutput,
                onReport: (type, content) async {
                  if (type == 'cancel') {
                    if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                    return;
                  }

                  await runWithBlockingDialog(
                    context: ctx,
                    message: '보고 처리 중입니다. 잠시만 기다려 주세요...',
                    task: () async {
                      final area = ctx.read<AreaState>().currentArea;
                      final division = ctx.read<AreaState>().currentDivision;
                      final userName = ctx.read<UserState>().name;

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
                          if (ctx.mounted) {
                            showFailedSnackbar(ctx, '보고 데이터 형식이 올바르지 않습니다.');
                          }
                          return;
                        } catch (_) {
                          if (ctx.mounted) {
                            showFailedSnackbar(ctx, '보고 데이터 파싱 중 오류가 발생했습니다.');
                          }
                          return;
                        }

                        // 2) plates 단일 조회(잠금요금 출차) → 합계/카운트 계산
                        final firestore = FirebaseFirestore.instance;
                        final platesSnap = await firestore
                            .collection('plates')
                            .where('type', isEqualTo: 'departure_completed')
                            .where('area', isEqualTo: area)
                            .where('isLockedFee', isEqualTo: true)
                            .get();

                        final int p = platesSnap.docs.length;
                        try {
                          /*await UsageReporter.instance.reportSampled(
                            area: area,
                            action: 'read',
                            n: p,
                            source: 'onReport.end.plates.query(departure_completed&lockedFee)',
                            sampleRate: 0.2,
                          );*/
                        } catch (_) {}

                        int totalLockedFee = 0;
                        for (final d in platesSnap.docs) {
                          totalLockedFee += _extractLockedFeeAmountSafe(d.data());
                        }

                        // 3) fee_summaries upsert 1회(중복 방지: get 없음)
                        final summaryRef = firestore.collection('fee_summaries').doc('${division}_${area}_all');
                        await summaryRef.set({
                          'division': division,
                          'area': area,
                          'scope': 'all',
                          'totalLockedFee': totalLockedFee,
                          'lockedVehicleCount': p,
                          'lastUpdated': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                        try {
                          /*await UsageReporter.instance.reportSampled(
                            area: area,
                            action: 'write',
                            n: 1,
                            source: 'onReport.end.fee_summaries.upsert',
                            sampleRate: 0.2,
                          );*/
                        } catch (_) {}

                        // 4) 보고 JSON/GCS 업로드 (Firebase 아님 → 계측 제외)
                        final reportLog = {
                          'division': division,
                          'area': area,
                          'vehicleCount': {
                            'vehicleInput': int.tryParse('${parsed['vehicleInput']}') ?? 0,
                            // ✅ onReport 단일 스냅샷의 문서 수를 그대로 사용해 중복 READ 제거
                            'vehicleOutput': p,
                          },
                          'totalLockedFee': totalLockedFee,
                          'createdAt': DateTime.now().toIso8601String(),
                        };
                        final reportUrl = await uploadEndWorkReportJson(
                          report: reportLog,
                          division: division,
                          area: area,
                          userName: userName,
                        );

                        if (reportUrl == null) {
                          if (ctx.mounted) showFailedSnackbar(ctx, '보고 업로드 실패: 네트워크/권한 확인');
                          return; // 업로드 실패 시 삭제로 진행하지 않음
                        }

                        // 5) 로그 묶음 JSON 업로드 (Firebase 아님 → 계측 제외)
                        final List<Map<String, dynamic>> items = [];
                        for (final doc in platesSnap.docs) {
                          final data = doc.data();
                          items.add({
                            'docId': doc.id,
                            'logs': _jsonSafe(data['logs'] ?? []),
                          });
                        }
                        final logsUrl = await uploadEndLogJson(
                          report: {
                            'division': division,
                            'area': area,
                            'items': items,
                          },
                          division: division,
                          area: area,
                          userName: userName,
                        );

                        if (logsUrl == null) {
                          if (ctx.mounted) showFailedSnackbar(ctx, '로그 업로드 실패: 네트워크/권한 확인');
                          return;
                        }

                        // 6) 동일 스냅샷으로 일괄 삭제 (재조회 없음)
                        final batch = firestore.batch();
                        for (final d in platesSnap.docs) {
                          batch.delete(d.reference);
                        }
                        await batch.commit();
                        try {
                          /*await UsageReporter.instance.reportSampled(
                            area: area,
                            action: 'delete',
                            n: p,
                            source: 'onReport.end.batch.commit(delete locked departures)',
                            sampleRate: 0.2,
                          );*/
                        } catch (_) {}

                        // 7) 흔적만 남기는 annotate(aggregate 숫자)
                        try {
                          /*await UsageReporter.instance.annotate(
                            area: area,
                            source: 'onReport.end.aggregate.departure_completed.count',
                            extra: {'value': p},
                          );*/
                        } catch (_) {}

                        // 8) UI 피드백
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          showSuccessSnackbar(
                            ctx,
                            "업무 종료 보고 업로드 및 출차 초기화 "
                            "(입차: ${parsed['vehicleInput']}, 출차: $p • 전체집계)",
                          );
                        }
                      } else if (type == 'start') {
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          showSuccessSnackbar(ctx, "업무 시작 보고 완료: $content");
                        }
                      } else if (type == 'middle') {
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          showSuccessSnackbar(ctx, "보고란 제출 완료: $content");
                        }
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}
