import 'dart:convert';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../repositories/plate_repo_services/plate_count_service.dart';
import '../../../../../../states/area/area_state.dart';
import '../../../../../../states/user/user_state.dart';
import '../../../../../../utils/snackbar_helper.dart';
import '../../../../../../utils/blocking_dialog.dart';
import '../../../../../../utils/gcs_uploader.dart';
import '../../../../../../utils/end_work_report_sheets_uploader.dart';
import 'home_end_work_report_content.dart';

/// 🔧 Firestore 특수 타입까지 JSON-safe하게 변환
dynamic _jsonSafe(dynamic v) {
  if (v == null) return null;

  // Firestore Timestamp → ISO8601
  if (v is Timestamp) return v.toDate().toIso8601String();

  // DateTime → ISO8601
  if (v is DateTime) return v.toIso8601String();

  // GeoPoint → 명시적 구조
  if (v is GeoPoint) {
    return {
      '_type': 'GeoPoint',
      'lat': v.latitude,
      'lng': v.longitude,
    };
  }

  // DocumentReference → 경로만 보존
  if (v is DocumentReference) {
    return {
      '_type': 'DocumentReference',
      'path': v.path,
    };
  }

  // 기본 스칼라
  if (v is num || v is String || v is bool) return v;

  // 리스트/맵 재귀 처리
  if (v is List) return v.map(_jsonSafe).toList();
  if (v is Map) {
    return v.map((key, value) => MapEntry(key.toString(), _jsonSafe(value)));
  }

  // 그 외 알 수 없는 객체는 문자열화(최후의 안전장치)
  return v.toString();
}

/// 풀스크린 BottomSheet로 업무 종료 보고 다이얼로그 열기
Future<void> showHomeReportDialog(BuildContext context) async {
  final area = context.read<AreaState>().currentArea;

  int prefilledVehicleOutput = 0;
  int prefilledVehicleInput = 0;

  try {
    if (area.isNotEmpty) {
      prefilledVehicleOutput = await PlateCountService()
          .getDepartureCompletedCountAll(area)
          .timeout(const Duration(seconds: 10));
      prefilledVehicleInput = await PlateCountService()
          .getParkingCompletedCountAll(area)
          .timeout(const Duration(seconds: 10));
    }
  } catch (_) {
    prefilledVehicleOutput = 0;
    prefilledVehicleInput = 0;
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final height = MediaQuery.sizeOf(ctx).height;
      final cs = Theme.of(ctx).colorScheme;

      return SizedBox(
        height: height,
        child: Container(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(0)),
            ),
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
                    try {
                      final areaState = ctx.read<AreaState>();
                      final userState = ctx.read<UserState>();
                      final area = areaState.currentArea;
                      final division = areaState.currentDivision;
                      final userName = userState.name;

                      dev.log('[END] start', name: 'report');

                      if (type != 'end') {
                        dev.log('[END] not end -> $type', name: 'report');
                        if (ctx.mounted) Navigator.pop(ctx);
                        return;
                      }

                      // 1) 입력 파싱(JSON 문자열)
                      Map<String, dynamic> parsed;
                      try {
                        dev.log('[END] parse input', name: 'report');
                        final decoded = jsonDecode(content);
                        if (decoded is Map<String, dynamic>) {
                          parsed = decoded;
                        } else {
                          throw const FormatException('JSON은 객체 형태여야 합니다.');
                        }
                      } catch (e, st) {
                        dev.log('[END] parse failed', error: e, stackTrace: st, name: 'report');
                        if (ctx.mounted) showFailedSnackbar(ctx, '보고 데이터 형식 오류: $e');
                        return;
                      }

                      // 2) plates 스냅샷(출차 완료 + 잠금요금 true)
                      final firestore = FirebaseFirestore.instance;
                      QuerySnapshot<Map<String, dynamic>> platesSnap;
                      try {
                        dev.log('[END] query plates...', name: 'report');
                        platesSnap = await firestore
                            .collection('plates')
                            .where('type', isEqualTo: 'departure_completed')
                            .where('area', isEqualTo: area)
                            .where('isLockedFee', isEqualTo: true)
                            .get();
                      } catch (e, st) {
                        dev.log('[END] plates query failed', error: e, stackTrace: st, name: 'report');
                        if (ctx.mounted) showFailedSnackbar(ctx, '출차 스냅샷 조회 실패: $e');
                        return;
                      }

                      final int snapshotLockedVehicleCount = platesSnap.docs.length;

                      // 3) 잠금요금 합계 계산(스냅샷 기준)
                      num snapshotTotalLockedFee = 0;
                      try {
                        for (final d in platesSnap.docs) {
                          final data = d.data();
                          num? fee = (data['lockedFeeAmount'] is num)
                              ? data['lockedFeeAmount'] as num
                              : null;
                          if (fee == null) {
                            final logs = data['logs'];
                            if (logs is List) {
                              for (final log in logs) {
                                if (log is Map && log['lockedFee'] is num) {
                                  fee = log['lockedFee'] as num;
                                }
                              }
                            }
                          }
                          snapshotTotalLockedFee += (fee ?? 0);
                        }
                      } catch (e, st) {
                        dev.log('[END] fee sum failed', error: e, stackTrace: st, name: 'report');
                        if (ctx.mounted) showFailedSnackbar(ctx, '요금 합계 계산 실패: $e');
                        return;
                      }

                      // 4) 사용자 입력 반영(없으면 스냅샷/0)
                      final int vehicleInputCount =
                          int.tryParse('${parsed['vehicleInput']}') ?? 0;
                      final int vehicleOutputManual =
                          int.tryParse('${parsed['vehicleOutput']}') ??
                              snapshotLockedVehicleCount;

                      // 5) 보고 JSON
                      final reportLog = {
                        'division': division,
                        'area': area,
                        'vehicleCount': {
                          'vehicleInput': vehicleInputCount,
                          'vehicleOutput': vehicleOutputManual,
                        },
                        'metrics': {
                          'snapshot_lockedVehicleCount': snapshotLockedVehicleCount,
                          'snapshot_totalLockedFee': snapshotTotalLockedFee,
                          'snapshot_source':
                          "plates[type=departure_completed, isLockedFee=true, area=$area]",
                          'summary_collection': 'fee_summaries',
                          'summary_docId': '${division}_${area}_all',
                        },
                        'createdAt': DateTime.now().toIso8601String(),
                        'uploadedBy': userName,
                      };

                      // 6) 보고 업로드
                      String? reportUrl;
                      try {
                        dev.log('[END] upload report...', name: 'report');
                        reportUrl = await uploadEndWorkReportJson(
                          report: reportLog,
                          division: division,
                          area: area,
                          userName: userName,
                        );
                      } catch (e, st) {
                        dev.log('[END] upload report exception', error: e, stackTrace: st, name: 'report');
                        if (ctx.mounted) showFailedSnackbar(ctx, '보고 파일 업로드 예외: $e');
                        return;
                      }
                      if (reportUrl == null) {
                        dev.log('[END] upload report null', name: 'report');
                        if (ctx.mounted) showFailedSnackbar(ctx, '보고 파일 업로드 실패(반환값 null)');
                        return;
                      }

                      // 7) 로그 업로드 (⚠️ 여기서 Timestamp 때문에 깨졌었음 → _jsonSafe로 방어)
                      String? logsUrl;
                      try {
                        dev.log('[END] upload logs...', name: 'report');
                        final items = <Map<String, dynamic>>[
                          for (final d in platesSnap.docs)
                            {
                              'docId': d.id,
                              'data': _jsonSafe(d.data()), // ✅ 모든 값 JSON-safe 변환
                            }
                        ];
                        logsUrl = await uploadEndLogJson(
                          report: {'division': division, 'area': area, 'items': items},
                          division: division,
                          area: area,
                          userName: userName,
                        );
                      } catch (e, st) {
                        dev.log('[END] upload logs exception', error: e, stackTrace: st, name: 'report');
                        if (ctx.mounted) showFailedSnackbar(ctx, '로그 파일 업로드 예외: $e');
                        return;
                      }
                      if (logsUrl == null) {
                        dev.log('[END] upload logs null', name: 'report');
                        if (ctx.mounted) showFailedSnackbar(ctx, '로그 파일 업로드 실패(반환값 null)');
                        return;
                      }

                      // 8) 구글 시트 Append — 실패해도 워크플로우 계속
                      try {
                        dev.log('[END] sheets append...', name: 'report');
                        final ok = await EndWorkReportSheetsUploader.appendRow(
                          reportJson: reportLog,
                        );
                        if (!ok && ctx.mounted) {
                          showFailedSnackbar(ctx, '스프레드시트 업로드 실패(보고는 저장됨)');
                        }
                      } catch (e, st) {
                        dev.log('[END] sheets exception', error: e, stackTrace: st, name: 'report');
                        if (ctx.mounted) showFailedSnackbar(ctx, '스프레드시트 업로드 예외(보고는 저장됨): $e');
                      }

                      // 9) 요약 업서트(fee_summaries)
                      try {
                        dev.log('[END] upsert fee_summaries...', name: 'report');
                        final summaryRef = firestore
                            .collection('fee_summaries')
                            .doc('${division}_${area}_all');
                        await summaryRef.set({
                          'division': division,
                          'area': area,
                          'scope': 'all',
                          'totalLockedFee': snapshotTotalLockedFee,
                          'lockedVehicleCount': snapshotLockedVehicleCount,
                          'lastUpdated': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                      } catch (e, st) {
                        dev.log('[END] summary upsert failed', error: e, stackTrace: st, name: 'report');
                        if (ctx.mounted) showFailedSnackbar(ctx, '요약 문서 업서트 실패: $e');
                        return;
                      }

                      // 10) plates 스냅샷 정리
                      bool cleanupOk = true;
                      try {
                        dev.log('[END] cleanup plates...', name: 'report');
                        final batch = firestore.batch();
                        for (final d in platesSnap.docs) {
                          batch.delete(d.reference);
                        }
                        await batch.commit();
                      } catch (e, st) {
                        cleanupOk = false;
                        dev.log('[END] cleanup failed', error: e, stackTrace: st, name: 'report');
                        if (ctx.mounted) {
                          showFailedSnackbar(ctx, '출차 스냅샷 초기화 실패: $e');
                        }
                      }

                      // 11) 성공 스낵바
                      dev.log('[END] success', name: 'report');
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        showSuccessSnackbar(
                          ctx,
                          [
                            "업무 종료 보고 완료",
                            "• 사용자 입력 출차 수: $vehicleOutputManual",
                            "• 스냅샷(plates: 정산 문서 수/합계요금): "
                                "$snapshotLockedVehicleCount / $snapshotTotalLockedFee",
                            if (!cleanupOk)
                              "• 주의: 스냅샷 일부가 삭제되지 않았습니다. 관리자에게 문의하세요.",
                          ].join("\n"),
                        );
                      }
                    } catch (e, st) {
                      dev.log('[END] FATAL', error: e, stackTrace: st, name: 'report');
                      if (ctx.mounted) {
                        showFailedSnackbar(ctx, '예기치 못한 오류: $e');
                      }
                    }
                  },
                );
              },
            ),
          ),
        ),
      );
    },
  );
}
