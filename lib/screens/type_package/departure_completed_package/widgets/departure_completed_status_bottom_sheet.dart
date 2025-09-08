import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../models/plate_model.dart';
import '../../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../../states/plate/plate_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../log_package/log_viewer_bottom_sheet.dart';
import '../../../modify_package/modify_plate_screen.dart';

Future<void> showDepartureCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
}) async {
  final userState = context.read<UserState>();
  final plateNumber = plate.plateNumber;
  final division = userState.division;
  final area = plate.area;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      return DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return Container(
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
                // [추가] 정산(사전 정산) 버튼
                // =========================
                ElevatedButton.icon(
                  icon: const Icon(Icons.receipt_long),
                  label: const Text("정산(사전 정산)"),
                  onPressed: () async {
                    final userName = context.read<UserState>().name;
                    final repo = context.read<PlateRepository>();

                    final plateState = context.read<PlateState>();
                    final firestore = FirebaseFirestore.instance;

                    // 사전 조건: 정산 타입 확인
                    final billingType = (plate.billingType ?? '').trim();
                    if (billingType.isEmpty) {
                      showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
                      return;
                    }

                    final now = DateTime.now();
                    final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;
                    final entryTime = plate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;

                    // 정산 바텀시트 호출 → 사용자 선택 결과 수집
                    final result = await showOnTapBillingBottomSheet(
                      context: context,
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
                    if (result == null) return;

                    // Plate 업데이트(잠금/금액/결제수단)
                    final updatedPlate = plate.copyWith(
                      isLockedFee: true,
                      lockedAtTimeInSeconds: currentTime,
                      lockedFeeAmount: result.lockedFee,
                      paymentMethod: result.paymentMethod,
                    );

                    try {
                      await repo.addOrUpdatePlate(plate.id, updatedPlate);
                      // 출차 완료 컬렉션에 맞게 로컬 상태 갱신
                      await plateState.updatePlateLocally(PlateType.departureCompleted, updatedPlate);

                      // 로그 기록
                      final log = {
                        'action': '사전 정산',
                        'performedBy': userName,
                        'timestamp': now.toIso8601String(),
                        'lockedFee': result.lockedFee,
                        'paymentMethod': result.paymentMethod,
                        if (result.reason != null && result.reason!.trim().isNotEmpty)
                          'reason': result.reason!.trim(), // ★ 사유 저장
                      };
                      await firestore.collection('plates').doc(plate.id).update({
                        'logs': FieldValue.arrayUnion([log])
                      });

                      if (!context.mounted) return;
                      showSuccessSnackbar(context, '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})');
                    } catch (e) {
                      if (!context.mounted) return;
                      showFailedSnackbar(context, '사전 정산 중 오류가 발생했습니다: $e');
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

                // ===== 기존 버튼들 =====
                ElevatedButton.icon(
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text("정보 수정"),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ModifyPlateScreen(
                          plate: plate,
                          collectionKey: PlateType.departureCompleted,
                        ),
                      ),
                    );
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

                const SizedBox(height: 12),

                ElevatedButton.icon(
                  icon: const Icon(Icons.history),
                  label: const Text("로그 확인"),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LogViewerBottomSheet(
                          initialPlateNumber: plateNumber,
                          division: division,
                          area: area,
                          requestTime: plate.requestTime,
                        ),
                      ),
                    );
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
          );
        },
      );
    },
  );
}
