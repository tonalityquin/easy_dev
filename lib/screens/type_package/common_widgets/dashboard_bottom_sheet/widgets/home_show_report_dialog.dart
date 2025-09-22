import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/area/area_state.dart';
import '../../../../../../states/user/user_state.dart';
import '../../../../../../utils/snackbar_helper.dart';
import '../../../../../../utils/blocking_dialog.dart';
// ✅ UsageReporter — 파이어베이스가 실제로 발생하는 로직(READ/WRITE/DELETE)만 계측
import '../../../../../../utils/usage_reporter.dart';

import '../../../../../repositories/plate_repo_services/plate_count_service.dart';
import 'home_end_work_report_content.dart';

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

/// 바텀시트(최상단까지)로 업무 보고 열기
Future<void> showHomeReportDialog(BuildContext context) async {
  // 다이얼로그 열기 전에 현재 지역 읽고 자동 집계값 미리 구하기
  final area = context.read<AreaState>().currentArea;

  int prefilledVehicleOutput = 0; // 출차(전체): departure_completed && isLockedFee
  int prefilledVehicleInput = 0;  // 입차(전체): parking_completed

  try {
    if (area.isNotEmpty) {
      prefilledVehicleOutput =
      await PlateCountService().getDepartureCompletedCountAll(area);
      // ✅ Firestore READ: departure_completed 전체 COUNT 사전 조회
      try {
        await UsageReporter.instance.report(
          area: area,
          action: 'read',
          n: prefilledVehicleOutput,
          source:
          'showHomeReportDialog.prefetch.departure_completed.aggregate',
        );
      } catch (_) {}

      prefilledVehicleInput =
      await PlateCountService().getParkingCompletedCountAll(area);
      // ✅ Firestore READ: parking_completed 전체 COUNT 사전 조회
      try {
        await UsageReporter.instance.report(
          area: area,
          action: 'read',
          n: prefilledVehicleInput,
          source: 'showHomeReportDialog.prefetch.parking_completed.aggregate',
        );
      } catch (_) {}
    }
  } catch (_) {
    prefilledVehicleOutput = 0;
    prefilledVehicleInput = 0;
  }

  // ⚠️ 바텀시트 open/close 같은 UX 이벤트는 Firebase가 아니므로 계측하지 않음

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black54,
    backgroundColor: Colors.transparent, // 외곽은 투명
    builder: (ctx) {
      // 키보드 높이만큼 패딩을 더해, 입력 시에도 콘텐츠가 가려지지 않게
      final bottomInset = MediaQuery.of(ctx).viewInsets.bottom + 16;

      return FractionallySizedBox(
        heightFactor: 1, // ✅ 화면 최상단까지
        child: SafeArea(
          top: false, // 노치 상단까지 확장
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white, // ✅ 시트 내부 배경은 흰색
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            // 내부 스크롤 확보(키보드가 올라와도 스크롤 가능)
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset),
              child: HomeEndWorkReportContent(
                // ✅ 초기값 주입
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

                        // 2) 전체 누적 요약을 갱신하기 위한 스냅샷 확보(이 스냅샷을 logs 추출에도 재사용)
                        final platesSnap = await FirebaseFirestore.instance
                            .collection('plates')
                            .where('type',
                            isEqualTo: 'departure_completed')
                            .where('area', isEqualTo: area)
                            .where('isLockedFee', isEqualTo: true)
                            .get();

                        // ✅ Firestore READ: plates 조회
                        try {
                          await UsageReporter.instance.report(
                            area: area,
                            action: 'read',
                            n: platesSnap.docs.length,
                            source:
                            'showHomeReportDialog.onReport.end.query.departure_completed&lockedFee',
                          );
                        } catch (_) {}

                        int total = 0;
                        for (final d in platesSnap.docs) {
                          total += _extractLockedFeeAmount(d.data());
                        }

                        // 3) 요약 문서 upsert
                        final summaryRef = FirebaseFirestore.instance
                            .collection('fee_summaries')
                            .doc('${division}_${area}_all');

                        await summaryRef.set({
                          'division': division,
                          'area': area,
                          'scope': 'all',
                          'totalLockedFee': total,
                          'lockedVehicleCount': platesSnap.size,
                          'lastUpdated': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));

                        // ✅ Firestore WRITE: fee_summaries upsert
                        try {
                          await UsageReporter.instance.report(
                            area: area,
                            action: 'write',
                            n: 1,
                            source:
                            'showHomeReportDialog.onReport.end.fee_summaries.upsert',
                          );
                        } catch (_) {}

                        // 4) 최신 합계 읽기
                        final latestSnap = await summaryRef.get();

                        // ✅ Firestore READ: fee_summaries doc 1건 get
                        try {
                          await UsageReporter.instance.report(
                            area: area,
                            action: 'read',
                            n: 1,
                            source:
                            'showHomeReportDialog.onReport.end.fee_summaries.get',
                          );
                        } catch (_) {}

                        final latestData = latestSnap.data();
                        final totalLockedFee =
                        (latestData?['totalLockedFee'] ?? 0) is num
                            ? (latestData?['totalLockedFee'] as num)
                            .round()
                            : 0;

                        // 5) 출차 차량 수 자동 집계(전체)로 보정하고 보고 JSON 구성
                        final vehicleOutputAuto =
                        await PlateCountService()
                            .getDepartureCompletedCountAll(area);

                        // ✅ Firestore READ: departure_completed 전체 COUNT 재조회
                        try {
                          await UsageReporter.instance.report(
                            area: area,
                            action: 'read',
                            n: vehicleOutputAuto,
                            source:
                            'showHomeReportDialog.onReport.end.aggregate.departure_completed.count',
                          );
                        } catch (_) {}

                        final reportLog = {
                          'division': division,
                          'area': area,
                          'vehicleCount': {
                            'vehicleInput':
                            int.tryParse('${parsed['vehicleInput']}') ?? 0,
                            'vehicleOutput': vehicleOutputAuto,
                          },
                          'totalLockedFee': totalLockedFee,
                          'timestamp': FieldValue.serverTimestamp(),
                        };

                        // 6) 보고 JSON 업로드(GCS) — Firebase 아님 → 계측 제외
                        await uploadEndWorkReportJson(
                          report: reportLog,
                          division: division,
                          area: area,
                          userName: userName,
                        );

                        // 7) 🔥 logs 집계 JSON 생성 → 업로드(GCS) — Firebase 아님 → 계측 제외
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
                        await deleteLockedDepartureDocs(area);

                        // 9) UI 피드백
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          showSuccessSnackbar(
                            ctx,
                            "업무 종료 보고 업로드 및 출차 초기화 "
                                "(입차: ${parsed['vehicleInput']}, 출차: $vehicleOutputAuto • 전체집계)",
                          );
                        }
                      } else if (type == 'start') {
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          showSuccessSnackbar(ctx, "업무 시작 보고 완료: $content");
                        }
                      } else if (type == 'middle') {
                        final user = ctx.read<UserState>().user;
                        if (user == null || user.divisions.isEmpty) {
                          showFailedSnackbar(ctx, '사용자 정보가 없어 보고를 저장할 수 없습니다.');
                          return;
                        }

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

/// 🔧 보고 후 정리: departure_completed & isLockedFee=true 문서 일괄 삭제
Future<void> deleteLockedDepartureDocs(String area) async {
  final firestore = FirebaseFirestore.instance;

  final snap = await firestore
      .collection('plates')
      .where('type', isEqualTo: 'departure_completed')
      .where('area', isEqualTo: area)
      .where('isLockedFee', isEqualTo: true)
      .get();

  // ✅ Firestore READ: 삭제 대상 조회
  try {
    await UsageReporter.instance.report(
      area: area,
      action: 'read',
      n: snap.docs.length,
      source: 'deleteLockedDepartureDocs.query.toDelete',
    );
  } catch (_) {}

  if (snap.docs.isEmpty) return;

  final batch = firestore.batch();
  for (final d in snap.docs) {
    batch.delete(d.reference);
  }
  await batch.commit();

  // ✅ Firestore DELETE: 일괄 삭제 커밋
  try {
    await UsageReporter.instance.report(
      area: area,
      action: 'delete',
      n: snap.docs.length,
      source: 'deleteLockedDepartureDocs.batch.commit',
    );
  } catch (_) {}
}
