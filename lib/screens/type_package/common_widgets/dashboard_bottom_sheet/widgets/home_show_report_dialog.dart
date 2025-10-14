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
import '../../../../../../utils/end_work_report_sheets_uploader.dart';
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
                      final areaState = ctx.read<AreaState>();
                      final userState = ctx.read<UserState>();
                      final area = areaState.currentArea;
                      final division = areaState.currentDivision;
                      final userName = userState.name;

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

                        // 2) plates 단일 스냅샷 조회(출차 완료 + 잠금요금 true)
                        final firestore = FirebaseFirestore.instance;
                        final platesSnap = await firestore
                            .collection('plates')
                            .where('type', isEqualTo: 'departure_completed')
                            .where('area', isEqualTo: area)
                            .where('isLockedFee', isEqualTo: true)
                            .get();

                        final int p = platesSnap.docs.length;

                        // 3) 잠금요금 합계 계산
                        int totalLockedFee = 0;
                        for (final d in platesSnap.docs) {
                          totalLockedFee += _extractLockedFeeAmountSafe(d.data());
                        }

                        // ✅ 사용자 입력 확정(없으면 기본값/스냅샷으로 대체)
                        final int vehicleInputCount =
                            int.tryParse('${parsed['vehicleInput']}') ?? 0;
                        final int vehicleOutputManual =
                            int.tryParse('${parsed['vehicleOutput']}') ?? p;

                        // 4) 보고 JSON 구성 — 보고/시트에는 '사용자 입력 출차 수'를 반영
                        final reportLog = {
                          'division': division,
                          'area': area,
                          'vehicleCount': {
                            'vehicleInput': vehicleInputCount,
                            'vehicleOutput': vehicleOutputManual, // 👈 사용자 수정값 반영
                          },
                          'totalLockedFee': totalLockedFee,
                          'createdAt': DateTime.now().toIso8601String(),
                          'uploadedBy': userName,
                        };

                        // 5) GCS 보고 업로드
                        final reportUrl = await uploadEndWorkReportJson(
                          report: reportLog,
                          division: division,
                          area: area,
                          userName: userName,
                        );
                        if (reportUrl == null) {
                          if (ctx.mounted) showFailedSnackbar(ctx, '보고 업로드 실패: 네트워크/권한 확인');
                          return;
                        }

                        // 6) GCS 로그 묶음 업로드
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

                        // 7) Google Sheets에 행 추가 (A~G만 기록)
                        final ok = await EndWorkReportSheetsUploader.appendRow(
                          reportJson: reportLog,
                          // sheetName: '업무종료보고', // 필요 시 원하는 탭명으로 지정
                        );
                        if (!ok) {
                          if (ctx.mounted) {
                            showFailedSnackbar(ctx, '스프레드시트 업로드 실패: 시트 ID/권한/탭명 확인');
                          }
                          return;
                        }

                        // 8) fee_summaries 업서트 — 무결성 위해 스냅샷 기반 p/totalLockedFee 사용
                        final summaryRef =
                        firestore.collection('fee_summaries').doc('${division}_${area}_all');
                        await summaryRef.set({
                          'division': division,
                          'area': area,
                          'scope': 'all',
                          'totalLockedFee': totalLockedFee,
                          'lockedVehicleCount': p,
                          'lastUpdated': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));

                        // 9) 동일 스냅샷으로 plates 일괄 삭제
                        final batch = firestore.batch();
                        for (final d in platesSnap.docs) {
                          batch.delete(d.reference);
                        }
                        await batch.commit();

                        // 10) UI 피드백 — 사용자값과 스냅샷 수를 함께 표기(혼동 방지)
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          showSuccessSnackbar(
                            ctx,
                            "업무 종료 보고 업로드 및 출차 초기화 "
                                "(입차: $vehicleInputCount, 출차: $vehicleOutputManual (스냅샷: $p) • 전체집계)",
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
