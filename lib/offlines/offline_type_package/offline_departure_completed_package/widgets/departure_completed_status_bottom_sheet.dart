import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../models/plate_model.dart';
import '../../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../../screens/log_package/log_viewer_bottom_sheet.dart';
import '../../../../states/plate/plate_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';

// import '../../../../utils/usage_reporter.dart';

Future<void> showDepartureCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
}) async {
  final userState = context.read<UserState>();
  final plateNumber = plate.plateNumber;
  final division = userState.division;
  final area = plate.area;

  // pop 후 push 시 안전한 사용을 위해 최상위 컨텍스트 보관
  final rootContext = context;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // ⬅️ 최상단까지 안전하게 확장
    backgroundColor: Colors.transparent,
    builder: (modalCtx) {
      return FractionallySizedBox(
        heightFactor: 1, // ⬅️ 화면 100%
        child: DraggableScrollableSheet(
          initialChildSize: 1.0, // ⬅️ 시작부터 최대
          minChildSize: 0.3,
          maxChildSize: 1.0,
          builder: (sheetCtx, scrollController) {
            return SafeArea(
              top: false, // ⬅️ 상단 라운딩 유지
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: ListView(
                  controller: scrollController,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const Row(
                      children: [
                        Icon(Icons.settings, color: Colors.blueAccent),
                        SizedBox(width: 8),
                        Text(
                          '출차 완료 상태 처리',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // =========================
                    // 정산(사전 정산)
                    // =========================

                    ElevatedButton.icon(
                      icon: const Icon(Icons.receipt_long),
                      label: const Text("정산(사전 정산)"),
                      onPressed: () async {
                        final userName = rootContext.read<UserState>().name;
                        final repo = rootContext.read<PlateRepository>();
                        final plateState = rootContext.read<PlateState>();
                        final firestore = FirebaseFirestore.instance;

                        // 사전 조건: 정산 타입 확인 (Firebase 아님 → 계측 제외)
                        final billingType = (plate.billingType ?? '').trim();
                        if (billingType.isEmpty) {
                          showFailedSnackbar(rootContext, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
                          return;
                        }

                        final now = DateTime.now();
                        final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;
                        final entryTime = plate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;

                        // 정산 바텀시트 호출 (Firebase 아님 → 계측 제외)
                        final result = await showOnTapBillingBottomSheet(
                          context: rootContext,
                          entryTimeInSeconds: entryTime,
                          currentTimeInSeconds: currentTime,
                          basicStandard: plate.basicStandard ?? 0,
                          basicAmount: plate.basicAmount ?? 0,
                          addStandard: plate.addStandard ?? 0,
                          addAmount: plate.addAmount ?? 0,
                          billingType: plate.billingType ?? '변동',
                          regularAmount: plate.regularAmount,
                          regularDurationHours: plate.regularDurationHours,
                        );
                        if (result == null) {
                          return;
                        }

                        // Plate 업데이트용 데이터
                        final updatedPlate = plate.copyWith(
                          isLockedFee: true,
                          lockedAtTimeInSeconds: currentTime,
                          lockedFeeAmount: result.lockedFee,
                          paymentMethod: result.paymentMethod,
                        );

                        try {
                          await repo.addOrUpdatePlate(plate.id, updatedPlate);
                          /*_reportDbSafe(
                            area: area,
                            action: 'write',
                            source: 'departureCompleted.prebill.repo.addOrUpdatePlate',
                            n: 1,
                          );*/

                          // 로컬 상태 갱신 (Firebase 아님 → 계측 제외)
                          await plateState.updatePlateLocally(PlateType.departureCompleted, updatedPlate);

                          // 🔵 Firestore write: logs 배열에 추가
                          final log = {
                            'action': '사전 정산',
                            'performedBy': userName,
                            'timestamp': now.toIso8601String(),
                            'lockedFee': result.lockedFee,
                            'paymentMethod': result.paymentMethod,
                            if (result.reason != null && result.reason!.trim().isNotEmpty)
                              'reason': result.reason!.trim(),
                          };
                          await firestore.collection('plates').doc(plate.id).update({
                            'logs': FieldValue.arrayUnion([log])
                          });
                          /*_reportDbSafe(
                            area: area,
                            action: 'write',
                            source: 'departureCompleted.prebill.plates.update.logs.arrayUnion',
                            n: 1,
                          );*/

                          if (!rootContext.mounted) return;
                          showSuccessSnackbar(
                            rootContext,
                            '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})',
                          );
                        } catch (e) {
                          if (!rootContext.mounted) return;
                          showFailedSnackbar(rootContext, '사전 정산 중 오류가 발생했습니다: $e');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ===== 로그 확인 (네비게이션만 — Firebase 아님)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.history),
                      label: const Text("로그 확인"),
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        Future.microtask(() {
                          if (!rootContext.mounted) return;
                          Navigator.push(
                            rootContext,
                            MaterialPageRoute(
                              builder: (_) => LogViewerBottomSheet(
                                initialPlateNumber: plateNumber,
                                division: division,
                                area: area,
                                requestTime: plate.requestTime,
                              ),
                            ),
                          );
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        backgroundColor: Colors.grey.shade100,
                        foregroundColor: Colors.black87,
                        elevation: 0,
                        side: const BorderSide(color: Colors.black12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

/*void _reportDbSafe({
  required String area,
  required String action, // 'read' | 'write' | 'delete' 등
  required String source,
  int n = 1,
}) {
  try {
    UsageReporter.instance.report(
      area: area,
      action: action,
      n: n,
      source: source,
    );
  } catch (_) {
    // 계측 실패는 기능에 영향 X
  }
}*/
