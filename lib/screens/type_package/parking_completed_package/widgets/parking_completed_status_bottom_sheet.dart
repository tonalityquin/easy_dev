import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/plate_model.dart';
import '../../../../screens/modify_package/modify_plate_screen.dart';
import '../../../../screens/log_package/log_viewer_bottom_sheet.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/plate/movement_plate.dart';
import '../../../../states/user/user_state.dart';
import '../../../../enums/plate_type.dart';

// 추가된 의존성
import '../../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../../states/plate/plate_state.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../../widgets/dialog/confirm_cancel_fee_dialog.dart';

Future<void> showParkingCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  required Future<void> Function() onRequestEntry,
  required VoidCallback onDelete,
}) async {
  final plateNumber = plate.plateNumber;
  final division = context.read<UserState>().division;
  final area = context.read<AreaState>().currentArea;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 1, // ✅ 최상단까지
      child: _FullHeightSheet(
        plate: plate,
        plateNumber: plateNumber,
        division: division,
        area: area,
        onRequestEntry: onRequestEntry,
        onDelete: onDelete,
      ),
    ),
  );
}

class _FullHeightSheet extends StatelessWidget {
  const _FullHeightSheet({
    required this.plate,
    required this.plateNumber,
    required this.division,
    required this.area,
    required this.onRequestEntry,
    required this.onDelete,
  });

  final PlateModel plate;
  final String plateNumber;
  final String division;
  final String area;
  final Future<void> Function() onRequestEntry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false, // ✅ 상단까지 차오르게
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ListView(
          children: [
            // 그립바
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
                  '입차 완료 상태 처리',
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
                final userName = context.read<UserState>().name;
                final repo = context.read<PlateRepository>();
                final plateState = context.read<PlateState>();
                final firestore = FirebaseFirestore.instance;

                final billingType = (plate.billingType ?? '').trim();
                if (billingType.isEmpty) {
                  showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
                  return;
                }

                final now = DateTime.now();
                final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;
                final entryTime = plate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;

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

                final updatedPlate = plate.copyWith(
                  isLockedFee: true,
                  lockedAtTimeInSeconds: currentTime,
                  lockedFeeAmount: result.lockedFee,
                  paymentMethod: result.paymentMethod,
                );

                try {
                  await repo.addOrUpdatePlate(plate.id, updatedPlate);
                  await plateState.updatePlateLocally(PlateType.parkingCompleted, updatedPlate);

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

                  if (!context.mounted) return;
                  showSuccessSnackbar(
                    context,
                    '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})',
                  );
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

            // =========================
            // 정산 취소(잠금 해제)
            // =========================
            ElevatedButton.icon(
              icon: const Icon(Icons.lock_open),
              label: const Text("정산 취소"),
              onPressed: () async {
                final userName = context.read<UserState>().name;
                final repo = context.read<PlateRepository>();
                final plateState = context.read<PlateState>();
                final firestore = FirebaseFirestore.instance;

                if (plate.isLockedFee != true) {
                  showFailedSnackbar(context, '현재 사전 정산 상태가 아닙니다.');
                  return;
                }

                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => const ConfirmCancelFeeDialog(),
                );
                if (confirm != true) return;

                final now = DateTime.now();
                final updatedPlate = plate.copyWith(
                  isLockedFee: false,
                  lockedAtTimeInSeconds: null,
                  lockedFeeAmount: null,
                  paymentMethod: null,
                );

                try {
                  await repo.addOrUpdatePlate(plate.id, updatedPlate);
                  await plateState.updatePlateLocally(PlateType.parkingCompleted, updatedPlate);

                  final cancelLog = {
                    'action': '사전 정산 취소',
                    'performedBy': userName,
                    'timestamp': now.toIso8601String(),
                  };
                  await firestore.collection('plates').doc(plate.id).update({
                    'logs': FieldValue.arrayUnion([cancelLog])
                  });

                  if (!context.mounted) return;
                  showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
                } catch (e) {
                  if (!context.mounted) return;
                  showFailedSnackbar(context, '정산 취소 중 오류가 발생했습니다: $e');
                }
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

            const SizedBox(height: 24),

            // =========================
            // 기존 액션들
            // =========================
            ElevatedButton.icon(
              icon: const Icon(Icons.exit_to_app),
              label: const Text("출차 요청으로 이동"),
              onPressed: () async {
                final movementPlate = context.read<MovementPlate>();
                final performedBy = context.read<UserState>().name;

                await movementPlate.setDepartureRequested(
                  plate.plateNumber,
                  plate.area,
                  plate.location,
                  performedBy: performedBy,
                );

                if (!context.mounted) return;
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
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

            const SizedBox(height: 12),

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
                      collectionKey: PlateType.parkingCompleted,
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
              icon: const Icon(Icons.assignment_return),
              label: const Text("입차 요청으로 되돌리기"),
              onPressed: () async {
                final movementPlate = context.read<MovementPlate>();
                final performedBy = context.read<UserState>().name;

                await movementPlate.goBackToParkingRequest(
                  fromType: PlateType.parkingCompleted,
                  plateNumber: plate.plateNumber,
                  area: plate.area,
                  newLocation: "미지정",
                  performedBy: performedBy,
                );

                if (!context.mounted) return;
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.orange.shade400,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 12),

            TextButton.icon(
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text("삭제", style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> handleEntryParkingRequest(BuildContext context, String plateNumber, String area) async {
  final movementPlate = context.read<MovementPlate>();
  final performedBy = context.read<UserState>().name;

  await movementPlate.goBackToParkingRequest(
    fromType: PlateType.parkingCompleted,
    plateNumber: plateNumber,
    area: area,
    newLocation: "미지정",
    performedBy: performedBy,
  );
}
