import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../../models/plate_model.dart';
import '../../../../../utils/snackbar_helper.dart';
import '../../../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';

/// ✅ 변경점
/// - performedBy(named param) 추가
/// - 반환 타입 Future<PlateModel?> 로 변경 (showModalBottomSheet의 결과를 그대로 반환)
/// - 정산 성공 시 Navigator.pop(context, updatedPlate) 로 상위에 결과 전달
Future<PlateModel?> showDepartureCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  String? performedBy,
}) async {
  final String who = (performedBy ?? '').trim().isEmpty ? '-' : performedBy!.trim();

  return showModalBottomSheet<PlateModel?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LiteDepartureCompletedStatusSheet(
      plate: plate,
      performedBy: who,
    ),
  );
}

class _LiteDepartureCompletedStatusSheet extends StatelessWidget {
  const _LiteDepartureCompletedStatusSheet({
    required this.plate,
    required this.performedBy,
  });

  final PlateModel plate;
  final String performedBy;

  @override
  Widget build(BuildContext context) {
    final bool isLocked = plate.isLockedFee == true;

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                const Icon(Icons.local_shipping_outlined, color: Colors.blueAccent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '출차 완료 처리',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),

            const SizedBox(height: 10),

            _SummaryCard(plate: plate),

            const SizedBox(height: 12),

            // ✅ 미정산이면 정산하기 버튼 활성화
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isLocked
                    ? null
                    : () async {
                  final updated = await _settlePlate(
                    context: context,
                    plate: plate,
                    performedBy: performedBy,
                  );

                  if (!context.mounted) return;

                  if (updated != null) {
                    // ✅ 상위 탭으로 updatedPlate 반환 -> 로컬 리스트 갱신 -> 미정산 목록에서 즉시 제외
                    Navigator.pop(context, updated);
                  }
                },
                icon: const Icon(Icons.lock),
                label: Text(
                  isLocked ? '정산 완료됨' : '정산하기',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // 닫기
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.plate});
  final PlateModel plate;

  @override
  Widget build(BuildContext context) {
    final bool isLocked = plate.isLockedFee == true;
    final String area = (plate.area).trim();
    final String location = (plate.location).trim().isEmpty ? '미지정' : plate.location.trim();
    final String billingType = (plate.billingType ?? '').trim().isEmpty ? '미지정' : (plate.billingType ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plate.plateNumber,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text('지역: $area', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('위치: $location', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('정산 타입: $billingType', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                isLocked ? Icons.check_circle : Icons.error_outline,
                size: 16,
                color: isLocked ? Colors.green.shade700 : Colors.redAccent,
              ),
              const SizedBox(width: 6),
              Text(
                isLocked ? '정산 완료' : '미정산',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: isLocked ? Colors.green.shade700 : Colors.redAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ✅ 출차 완료(departure_completed) 문서를 "정산 잠금" 처리
/// - isLockedFee = true
/// - lockedFeeAmount / paymentMethod / lockedAtTimeInSeconds 저장
/// - logs에 정산 로그 추가
Future<PlateModel?> _settlePlate({
  required BuildContext context,
  required PlateModel plate,
  required String performedBy,
}) async {
  if (plate.isLockedFee == true) {
    showFailedSnackbar(context, '이미 정산 완료된 데이터입니다.');
    return null;
  }

  final bt = (plate.billingType ?? '').trim();
  if (bt.isEmpty) {
    showFailedSnackbar(context, '정산 타입(billingType)이 지정되지 않아 정산할 수 없습니다.');
    return null;
  }

  final now = DateTime.now();
  final int currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;
  final int entryTime = plate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;

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

  if (result == null) return null;

  final updatedPlate = plate.copyWith(
    isLockedFee: true,
    lockedAtTimeInSeconds: currentTime,
    lockedFeeAmount: result.lockedFee,
    paymentMethod: result.paymentMethod,
  );

  try {
    final docRef = FirebaseFirestore.instance.collection('plates').doc(plate.id);

    final log = {
      'action': '사전 정산',
      'performedBy': performedBy,
      'timestamp': now.toIso8601String(),
      'lockedFee': result.lockedFee,
      'paymentMethod': result.paymentMethod,
      if (result.reason != null && result.reason!.trim().isNotEmpty) 'reason': result.reason!.trim(),
    };

    await docRef.update({
      'isLockedFee': true,
      'lockedAtTimeInSeconds': currentTime,
      'lockedFeeAmount': result.lockedFee,
      'paymentMethod': result.paymentMethod,
      'updatedAt': FieldValue.serverTimestamp(),
      'logs': FieldValue.arrayUnion([log]),
    });

    if (!context.mounted) return null;
    showSuccessSnackbar(context, '정산 완료: ₩${result.lockedFee} (${result.paymentMethod})');

    return updatedPlate;
  } catch (e) {
    if (!context.mounted) return null;
    showFailedSnackbar(context, '정산 중 오류가 발생했습니다: $e');
    return null;
  }
}
