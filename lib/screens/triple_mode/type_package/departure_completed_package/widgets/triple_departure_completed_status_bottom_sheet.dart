import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../../models/plate_model.dart';
import '../../../../../utils/snackbar_helper.dart';
import '../../../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../../common_package/log_package/log_viewer_bottom_sheet.dart';

Future<PlateModel?> showTripleDepartureCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  String? performedBy,
}) async {
  final String who = (performedBy ?? '').trim().isEmpty ? '-' : performedBy!.trim();
  final BuildContext hostContext = context;

  return showModalBottomSheet<PlateModel?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 1,
      child: _TripleDepartureCompletedFullHeightSheet(
        hostContext: hostContext,
        plate: plate,
        performedBy: who,
      ),
    ),
  );
}

class _TripleDepartureCompletedFullHeightSheet extends StatelessWidget {
  const _TripleDepartureCompletedFullHeightSheet({
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
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
                  color: cs.outlineVariant.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),

            Row(
              children: [
                Icon(Icons.settings, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '출차 완료 상태 처리',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: cs.onSurface),
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
                elevation: 0,
                backgroundColor: _isLocked ? cs.surfaceContainerLow : cs.primary,
                foregroundColor: _isLocked ? cs.onSurfaceVariant : cs.onPrimary,
                disabledBackgroundColor: cs.surfaceContainerLow,
                disabledForegroundColor: cs.onSurfaceVariant,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ).copyWith(
                overlayColor: MaterialStateProperty.resolveWith<Color?>(
                      (states) =>
                  states.contains(MaterialState.pressed) ? cs.primary.withOpacity(0.10) : null,
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
                elevation: 0,
                backgroundColor: _isLocked ? cs.errorContainer : cs.surfaceContainerLow,
                foregroundColor: _isLocked ? cs.onErrorContainer : cs.onSurfaceVariant,
                disabledBackgroundColor: cs.surfaceContainerLow,
                disabledForegroundColor: cs.onSurfaceVariant,
                side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ).copyWith(
                overlayColor: MaterialStateProperty.resolveWith<Color?>(
                      (states) => states.contains(MaterialState.pressed) ? cs.error.withOpacity(0.10) : null,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 로그 확인
            ElevatedButton.icon(
              icon: const Icon(Icons.history),
              label: const Text('로그 확인'),
              onPressed: () async {
                await LogViewerBottomSheet.show(
                  hostContext,
                  division: '-',
                  area: plate.area,
                  requestTime: plate.requestTime,
                  initialPlateNumber: plate.plateNumber,
                  plateId: plate.id,
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                elevation: 0,
                backgroundColor: cs.surfaceContainerLow,
                foregroundColor: cs.onSurface,
                side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ).copyWith(
                overlayColor: MaterialStateProperty.resolveWith<Color?>(
                      (states) => states.contains(MaterialState.pressed) ? cs.outlineVariant.withOpacity(0.12) : null,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 정보 수정 (비활성)
            ElevatedButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text('정보 수정'),
              onPressed: null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                elevation: 0,
                backgroundColor: cs.surfaceContainerLow,
                foregroundColor: cs.onSurfaceVariant,
                disabledBackgroundColor: cs.surfaceContainerLow,
                disabledForegroundColor: cs.onSurfaceVariant,
                side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 닫기
            TextButton.icon(
              icon: Icon(Icons.close, color: cs.onSurfaceVariant),
              label: Text('닫기', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800)),
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                overlayColor: cs.outlineVariant.withOpacity(0.12),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bool isLocked = plate.isLockedFee == true;

    final String area = plate.area.trim();
    final String location = plate.location.trim().isEmpty ? '미지정' : plate.location.trim();
    final String billingType =
    (plate.billingType ?? '').trim().isEmpty ? '미지정' : (plate.billingType ?? '').trim();

    final badgeColor = isLocked ? cs.tertiary : cs.error;
    final badgeBg = isLocked ? cs.tertiaryContainer : cs.errorContainer;
    final badgeFg = isLocked ? cs.onTertiaryContainer : cs.onErrorContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plate.plateNumber,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),

          Text(
            '지역: $area',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 2),

          Text(
            '위치: $location',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 2),

          Text(
            '정산 타입: $billingType',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeColor.withOpacity(0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isLocked ? Icons.check_circle : Icons.error_outline,
                      size: 16,
                      color: badgeFg,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isLocked ? '정산 완료' : '미정산',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: badgeFg,
                      ),
                    ),
                  ],
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
  final cs = Theme.of(context).colorScheme;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => AlertDialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
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
