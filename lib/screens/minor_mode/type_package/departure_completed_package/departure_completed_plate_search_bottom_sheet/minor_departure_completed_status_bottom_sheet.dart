import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../models/plate_model.dart';
import '../../../../../states/area/area_state.dart';
import '../../../../../states/plate/minor_plate_state.dart';
import '../../../../../states/user/user_state.dart';
import '../../../../../enums/plate_type.dart';

import '../../../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../../../utils/snackbar_helper.dart';
import '../../../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../../common_package/log_package/log_viewer_bottom_sheet.dart';

Future<PlateModel?> showMinorDepartureCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
}) async {
  final plateNumber = plate.plateNumber;
  final division = context.read<UserState>().division;
  final area = context.read<AreaState>().currentArea;

  return showModalBottomSheet<PlateModel?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 1,
      child: _FullHeightSheet(
        plate: plate,
        plateNumber: plateNumber,
        division: division,
        area: area,
      ),
    ),
  );
}

class _FullHeightSheet extends StatefulWidget {
  const _FullHeightSheet({
    required this.plate,
    required this.plateNumber,
    required this.division,
    required this.area,
  });

  final PlateModel plate;
  final String plateNumber;
  final String division;
  final String area;

  @override
  State<_FullHeightSheet> createState() => _FullHeightSheetState();
}

class _FullHeightSheetState extends State<_FullHeightSheet> {
  late PlateModel _plate;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _plate = widget.plate;
  }

  bool get _isLocked => _plate.isLockedFee == true;

  /// ✅ 무료 판정: basicAmount == 0 && addAmount == 0
  bool get _isFreeBilling =>
      (_plate.basicAmount ?? 0) == 0 && (_plate.addAmount ?? 0) == 0;

  /// ✅ plates docId 안전 처리
  /// - plate.id가 비어있을 수 있는 프로젝트 구조를 고려(다른 파일에서도 동일 패턴 존재)
  /// - 기존 프로젝트에서 널리 쓰는 "{plateNumber}_{area}" 폴백 적용
  String _plateDocIdSafe() {
    final id = _plate.id.trim();
    if (id.isNotEmpty) return id;

    final plateNumber = _plate.plateNumber.trim().isNotEmpty
        ? _plate.plateNumber.trim()
        : widget.plateNumber.trim();

    final area = _plate.area.trim().isNotEmpty
        ? _plate.area.trim()
        : widget.area.trim();

    return '${plateNumber}_$area';
  }

  Future<void> _runGuarded(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessageSafe({required bool success, required String message}) {
    try {
      if (success) {
        showSuccessSnackbar(context, message);
      } else {
        showFailedSnackbar(context, message);
      }
      return;
    } catch (_) {
      // no-op -> ScaffoldMessenger fallback
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final nav = Navigator.of(context, rootNavigator: true);
    final messenger2 = ScaffoldMessenger.maybeOf(nav.context);
    if (messenger2 != null) {
      messenger2.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    showDialog<void>(
      context: nav.context,
      builder: (_) => AlertDialog(
        title: const Text('안내'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(nav.context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  /// ✅ 무료면 자동 “사전정산(0원 잠금)” 처리
  Future<bool> _autoPreBillFreeIfNeeded() async {
    if (_isLocked) return true;
    if (!_isFreeBilling) return false;

    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final plateState = context.read<MinorPlateState>();
    final firestore = FirebaseFirestore.instance;

    final now = DateTime.now();
    final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;

    final updatedPlate = _plate.copyWith(
      isLockedFee: true,
      lockedAtTimeInSeconds: currentTime,
      lockedFeeAmount: 0,
      paymentMethod: '무료',
    );

    final plateId = _plateDocIdSafe();

    try {
      // 1) plates 문서 업데이트(프로젝트 정책대로 repo 사용)
      await repo.addOrUpdatePlate(plateId, updatedPlate);
      _reportDbSafe(
        area: _plate.area,
        action: 'write',
        source: 'departureCompletedStatus.freeAutoPrebill.repo.addOrUpdatePlate',
        n: 1,
      );

      // 2) 출차 완료 탭 로컬 반영
      await plateState.minorUpdatePlateLocally(
        PlateType.departureCompleted,
        updatedPlate,
      );

      // 3) logs append
      final log = {
        'action': '무료 자동 정산',
        'performedBy': userName,
        'timestamp': now.toIso8601String(),
        'lockedFee': 0,
        'paymentMethod': '무료',
      };

      await firestore.collection('plates').doc(plateId).update({
        'logs': FieldValue.arrayUnion([log]),
      });
      _reportDbSafe(
        area: _plate.area,
        action: 'write',
        source: 'departureCompletedStatus.freeAutoPrebill.plates.update.logs.arrayUnion',
        n: 1,
      );

      if (!mounted) return false;

      setState(() => _plate = updatedPlate);
      _showMessageSafe(success: true, message: '무료 정산이 자동 처리되었습니다. (₩0)');
      return true;
    } catch (e) {
      if (!mounted) return false;
      _showMessageSafe(success: false, message: '무료 자동 정산 중 오류가 발생했습니다: $e');
      return false;
    }
  }

  Future<void> _handlePreBill() async {
    await _runGuarded(() async {
      if (_isLocked) {
        _showMessageSafe(success: false, message: '이미 정산(잠금) 완료된 차량입니다.');
        return;
      }

      // ✅ 무료면 자동 처리
      if (_isFreeBilling) {
        await _autoPreBillFreeIfNeeded();
        return;
      }

      final userName = context.read<UserState>().name;
      final repo = context.read<PlateRepository>();
      final plateState = context.read<MinorPlateState>();
      final firestore = FirebaseFirestore.instance;

      final bt = (_plate.billingType ?? '').trim();
      if (bt.isEmpty) {
        _showMessageSafe(success: false, message: '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
        return;
      }

      final now = DateTime.now();
      final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;
      final entryTime = _plate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;

      final result = await showOnTapBillingBottomSheet(
        context: context,
        entryTimeInSeconds: entryTime,
        currentTimeInSeconds: currentTime,
        basicStandard: _plate.basicStandard ?? 0,
        basicAmount: _plate.basicAmount ?? 0,
        addStandard: _plate.addStandard ?? 0,
        addAmount: _plate.addAmount ?? 0,
        billingType: _plate.billingType ?? '변동',
        regularAmount: _plate.regularAmount,
        regularDurationHours: _plate.regularDurationHours,
      );
      if (result == null) return;

      final updatedPlate = _plate.copyWith(
        isLockedFee: true,
        lockedAtTimeInSeconds: currentTime,
        lockedFeeAmount: result.lockedFee,
        paymentMethod: result.paymentMethod,
      );

      final plateId = _plateDocIdSafe();

      try {
        // 1) plates 문서 업데이트
        await repo.addOrUpdatePlate(plateId, updatedPlate);
        _reportDbSafe(
          area: _plate.area,
          action: 'write',
          source: 'departureCompletedStatus.prebill.repo.addOrUpdatePlate',
          n: 1,
        );

        // 2) 로컬 반영
        await plateState.minorUpdatePlateLocally(
          PlateType.departureCompleted,
          updatedPlate,
        );

        // 3) logs append
        final log = {
          'action': '사전 정산',
          'performedBy': userName,
          'timestamp': now.toIso8601String(),
          'lockedFee': result.lockedFee,
          'paymentMethod': result.paymentMethod,
          if (result.reason != null && result.reason!.trim().isNotEmpty)
            'reason': result.reason!.trim(),
        };

        await firestore.collection('plates').doc(plateId).update({
          'logs': FieldValue.arrayUnion([log]),
        });
        _reportDbSafe(
          area: _plate.area,
          action: 'write',
          source: 'departureCompletedStatus.prebill.plates.update.logs.arrayUnion',
          n: 1,
        );

        if (!mounted) return;

        setState(() => _plate = updatedPlate);

        _showMessageSafe(
          success: true,
          message: '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})',
        );
      } catch (e) {
        if (!mounted) return;
        _showMessageSafe(success: false, message: '사전 정산 중 오류가 발생했습니다: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    final lockedFee = _plate.lockedFeeAmount;
    final paymentMethod = (_plate.paymentMethod ?? '').trim();
    final billingType = (_plate.billingType ?? '').trim();
    final location = _plate.location.trim().isEmpty ? '미지정' : _plate.location.trim();

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: cs.outlineVariant.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const _SheetTitleRow(
                    title: '출차 완료 상태 처리',
                    icon: Icons.settings,
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _PlateSummaryCard(
                    plateNumber: widget.plateNumber,
                    area: _plate.area,
                    location: location,
                    billingType: billingType,
                    isLocked: _isLocked,
                    lockedFee: lockedFee,
                    paymentMethod: paymentMethod,
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: '정산',
                    subtitle: '출차 완료 상태에서도 사전 정산을 처리할 수 있습니다.',
                    child: Column(
                      children: [
                        _ActionTileButton(
                          icon: Icons.receipt_long,
                          title: _isLocked ? '정산 완료' : '정산',
                          subtitle: _isLocked
                              ? '이미 사전 정산(잠금) 처리됨'
                              : (_isFreeBilling ? '무료(₩0) 자동 정산 가능' : '사전 정산'),
                          tone: _isLocked ? _ActionTone.neutral : _ActionTone.positive,
                          enabled: !_busy,
                          onTap: _handlePreBill,
                          trailing: _busy
                              ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurface),
                          )
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: '기타',
                    subtitle: '로그 확인 및 닫기',
                    child: Column(
                      children: [
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 2.6,
                          children: [
                            _SecondaryActionButton(
                              icon: Icons.history,
                              label: '로그 확인',
                              onPressed: () {
                                Navigator.pop(context); // 현재 시트 닫고
                                Navigator.push(
                                  rootContext,
                                  MaterialPageRoute(
                                    builder: (_) => LogViewerBottomSheet(
                                      initialPlateNumber: widget.plateNumber,
                                      division: widget.division,
                                      area: widget.area,
                                      requestTime: _plate.requestTime,
                                    ),
                                  ),
                                );
                              },
                            ),
                            _SecondaryActionButton(
                              icon: Icons.close,
                              label: '닫기',
                              onPressed: () => Navigator.pop(context, _plate),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetTitleRow extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SheetTitleRow({
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _PlateSummaryCard extends StatelessWidget {
  final String plateNumber;
  final String area;
  final String location;
  final String billingType;
  final bool isLocked;
  final int? lockedFee;
  final String paymentMethod;

  const _PlateSummaryCard({
    required this.plateNumber,
    required this.area,
    required this.location,
    required this.billingType,
    required this.isLocked,
    required this.lockedFee,
    required this.paymentMethod,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final badgeColor = isLocked ? Colors.green : cs.onSurfaceVariant;
    final badgeText = isLocked ? '사전정산 잠김' : '미정산';

    final feeText = (isLocked && lockedFee != null)
        ? '₩$lockedFee${paymentMethod.isNotEmpty ? " ($paymentMethod)" : ""}'
        : '—';

    final billingText = billingType.isNotEmpty ? billingType : '미지정';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plateNumber,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeColor.withOpacity(0.35)),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _InfoLine(label: '지역', value: area)),
              const SizedBox(width: 12),
              Expanded(child: _InfoLine(label: '위치', value: location)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _InfoLine(label: '정산 타입', value: billingText)),
              const SizedBox(width: 12),
              Expanded(child: _InfoLine(label: '잠금 금액', value: feeText)),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = value.trim().isEmpty ? '—' : value.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          v,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

enum _ActionTone { positive, neutral }

class _ActionTileButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final _ActionTone tone;
  final VoidCallback onTap;
  final bool enabled;
  final Widget? trailing;

  const _ActionTileButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tone,
    required this.onTap,
    required this.enabled,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color base = (tone == _ActionTone.positive) ? Colors.green : cs.onSurfaceVariant;
    final Color bg = (tone == _ActionTone.positive) ? Colors.green.withOpacity(0.08) : cs.surfaceContainerLow;
    final Color border = (tone == _ActionTone.positive) ? Colors.green.withOpacity(0.25) : cs.outlineVariant.withOpacity(0.8);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: base),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: trailing!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _SecondaryActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return OutlinedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800),
        textAlign: TextAlign.center,
      ),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 46),
        foregroundColor: cs.onSurface,
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.8)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: cs.surfaceContainerLow,
      ),
    );
  }
}

/// UsageReporter: 파이어베이스 DB 작업만 계측 (read / write / delete)
void _reportDbSafe({
  required String area,
  required String action, // 'read' | 'write' | 'delete'
  required String source,
  int n = 1,
}) {
  try {
    /*UsageReporter.instance.report(
      area: area.trim(),
      action: action,
      n: n,
      source: source,
    );*/
  } catch (_) {
    // no-op
  }
}
