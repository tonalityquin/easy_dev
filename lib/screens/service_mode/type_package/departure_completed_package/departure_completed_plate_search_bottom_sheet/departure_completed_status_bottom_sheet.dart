import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../../models/plate_model.dart';
import '../../../../../utils/snackbar_helper.dart';
import '../../../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';

// ✅ 로그 뷰어 import (서비스 모드)
import '../../../../common_package/log_package/log_viewer_bottom_sheet.dart';

Future<PlateModel?> showDepartureCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  String? performedBy,
}) async {
  final String who = (performedBy ?? '').trim().isEmpty ? '-' : performedBy!.trim();

  // ✅ LogViewerBottomSheet.show()는 pop 후 show 방식이라,
  //    바텀시트 context가 아닌 "호출자(상위) context"를 넘겨야 안전합니다.
  final BuildContext hostContext = context;

  return showModalBottomSheet<PlateModel?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 1,
      child: _DepartureCompletedFullHeightSheet(
        hostContext: hostContext,
        plate: plate,
        performedBy: who,
      ),
    ),
  );
}

class _DepartureCompletedFullHeightSheet extends StatelessWidget {
  const _DepartureCompletedFullHeightSheet({
    required this.hostContext,
    required this.plate,
    required this.performedBy,
  });

  final BuildContext hostContext;
  final PlateModel plate;
  final String performedBy;

  bool get _isLocked => plate.isLockedFee == true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ListView(
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
            Row(
              children: [
                const Icon(Icons.settings, color: Colors.blueAccent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '출차 완료 상태 처리',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _SummaryCard(plate: plate),

            const SizedBox(height: 24),

            // 정산(사전 정산)
            ElevatedButton.icon(
              icon: const Icon(Icons.receipt_long),
              label: Text(_isLocked ? '정산 완료됨' : '정산(사전 정산)'),
              onPressed: _isLocked
                  ? null
                  : () async {
                      final updated = await _settlePlate(
                        context: context,
                        plate: plate,
                        performedBy: performedBy,
                      );

                      if (!context.mounted) return;

                      if (updated != null) {
                        Navigator.pop(context, updated);
                      }
                    },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: _isLocked ? Colors.grey.shade200 : Colors.blueAccent,
                foregroundColor: _isLocked ? Colors.grey.shade600 : Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 정산 취소
            ElevatedButton.icon(
              icon: const Icon(Icons.lock_open),
              label: const Text('정산 취소'),
              onPressed: !_isLocked
                  ? null
                  : () async {
                      final bool ok = await _confirmCancelSettlement(context);
                      if (!ok) return;

                      final updated = await _cancelSettlement(
                        context: context,
                        plate: plate,
                        performedBy: performedBy,
                      );

                      if (!context.mounted) return;

                      if (updated != null) {
                        Navigator.pop(context, updated);
                      }
                    },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: _isLocked ? Colors.orange.shade400 : Colors.grey.shade100,
                foregroundColor: _isLocked ? Colors.white : Colors.black38,
                elevation: 0,
                side: _isLocked ? null : const BorderSide(color: Colors.black12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ✅ 로그 확인 -> LogViewerBottomSheet.show() 사용
            ElevatedButton.icon(
              icon: const Icon(Icons.history),
              label: const Text('로그 확인'),
              onPressed: () async {
                await LogViewerBottomSheet.show(
                  hostContext,
                  division: '-',
                  // LogViewerBottomSheet는 조회에 사용하지 않지만 required
                  area: plate.area,
                  requestTime: plate.requestTime,
                  initialPlateNumber: plate.plateNumber,
                  plateId: plate.id, // ✅ 가능하면 docId 직접 전달 (가장 정확)
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

            // 정보 수정 (비활성 유지)
            ElevatedButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text('정보 수정'),
              onPressed: null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.grey.shade100,
                foregroundColor: Colors.black38,
                elevation: 0,
                side: const BorderSide(color: Colors.black12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 닫기
            TextButton.icon(
              icon: const Icon(Icons.close, color: Colors.black54),
              label: const Text('닫기', style: TextStyle(color: Colors.black54)),
              onPressed: () => Navigator.pop(context),
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

Future<bool> _confirmCancelSettlement(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => AlertDialog(
      title: const Text('정산 취소'),
      content: const Text('정산 정보를 취소(해제)하시겠습니까?\n이 작업은 로그에 기록됩니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('아니오'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('예'),
        ),
      ],
    ),
  );
  return result == true;
}

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

Future<PlateModel?> _cancelSettlement({
  required BuildContext context,
  required PlateModel plate,
  required String performedBy,
}) async {
  if (plate.isLockedFee != true) {
    showFailedSnackbar(context, '정산 완료된 데이터만 취소할 수 있습니다.');
    return null;
  }

  final now = DateTime.now();

  try {
    final docRef = FirebaseFirestore.instance.collection('plates').doc(plate.id);

    final log = {
      'action': '정산 취소',
      'performedBy': performedBy,
      'timestamp': now.toIso8601String(),
    };

    await docRef.update({
      'isLockedFee': false,
      'lockedAtTimeInSeconds': FieldValue.delete(),
      'lockedFeeAmount': FieldValue.delete(),
      'paymentMethod': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
      'logs': FieldValue.arrayUnion([log]),
    });

    if (!context.mounted) return null;
    showSuccessSnackbar(context, '정산이 취소되었습니다.');

    return plate.copyWith(isLockedFee: false);
  } catch (e) {
    if (!context.mounted) return null;
    showFailedSnackbar(context, '정산 취소 중 오류가 발생했습니다: $e');
    return null;
  }
}
