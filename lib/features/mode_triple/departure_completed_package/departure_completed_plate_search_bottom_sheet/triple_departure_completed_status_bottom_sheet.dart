import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../features/account/applications/user_state.dart';
import '../../../../../features/dev/application/area_state.dart';
import '../../../../../features/payment/widgets/billing_bottom_sheet.dart';
import '../../../../../shared/plate/application/triple/triple_plate_state.dart';
import '../../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../../shared/plate/domain/models/plate_log_model.dart';
import '../../../../../shared/plate/domain/models/plate_model.dart';
import '../../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../../../shared/plate/widgets/log_viewer_bottom_sheet.dart';

class _Brand {
  static Color border(ColorScheme cs) => cs.outlineVariant.withOpacity(0.85);

  static Color positive(ColorScheme cs) => cs.primary;

  static Color positiveBg(ColorScheme cs) =>
      cs.primaryContainer.withOpacity(0.45);

  static Color neutralBg(ColorScheme cs) => cs.surfaceContainerLow;
}

Future<PlateModel?> showTripleDepartureCompletedStatusBottomSheet({
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

  @override
  void initState() {
    super.initState();
    _plate = widget.plate;
  }

  bool get _isLocked => _plate.isLockedFee == true;

  bool get _isFreeBilling =>
      (_plate.basicAmount ?? 0) == 0 && (_plate.addAmount ?? 0) == 0;

  Future<bool> _autoPreBillFreeIfNeeded() async {
    if (_isLocked) return true;
    if (!_isFreeBilling) return false;

    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final plateState = context.read<TriplePlateState>();

    final now = DateTime.now();
    final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    final documentId = _plate.id.trim().isNotEmpty
        ? _plate.id.trim()
        : '${_plate.plateNumber}_${_plate.area}';

    final fallbackPlate = _plate.copyWith(
      isLockedFee: true,
      lockedAtTimeInSeconds: currentTime,
      lockedFeeAmount: 0,
      paymentMethod: '무료',
    );

    try {
      await repo.settlePlateBilling(
        documentId: documentId,
        lockedAtTimeInSeconds: currentTime,
        lockedFeeAmount: 0,
        paymentMethod: '무료',
        log: PlateLogModel(
          action: '무료 자동 정산',
          area: _plate.area,
          billingType: _plate.billingType,
          from: _plate.type,
          performedBy: userName,
          plateNumber: _plate.plateNumber,
          timestamp: now,
          to: _plate.type,
          type: _plate.type,
          lockedFee: 0,
          paymentMethod: '무료',
        ),
      );
      _reportDbSafe(
        area: _plate.area,
        action: 'write',
        source: 'departureCompletedStatus.freeAutoPrebill.repo.settlePlateBilling',
        n: 1,
      );

      final freshPlate = await repo.getPlate(documentId) ?? fallbackPlate;

      await plateState.tripleUpdatePlateLocally(
        PlateType.departureCompleted,
        freshPlate,
      );

      if (!mounted) return false;

      setState(() => _plate = freshPlate);
      debugPrint('무료 정산이 자동 처리되었습니다. (₩0)');
      return true;
    } catch (e) {
      if (!mounted) return false;
      debugPrint('무료 자동 정산 중 오류가 발생했습니다: $e');
      return false;
    }
  }

  Future<void> _handlePreBill() async {
    if (_isLocked) {
      debugPrint('이미 정산(잠금) 완료된 차량입니다.');
      return;
    }

    if (_isFreeBilling) {
      await _autoPreBillFreeIfNeeded();
      return;
    }

    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final plateState = context.read<TriplePlateState>();

    final bt = (_plate.billingType ?? '').trim();
    if (bt.isEmpty) {
      debugPrint('정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
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
      regularDurationValue: _plate.regularDurationValue,
    );
    if (result == null) return;

    final documentId = _plate.id.trim().isNotEmpty
        ? _plate.id.trim()
        : '${_plate.plateNumber}_${_plate.area}';

    final fallbackPlate = _plate.copyWith(
      isLockedFee: true,
      lockedAtTimeInSeconds: currentTime,
      lockedFeeAmount: result.lockedFee,
      paymentMethod: result.paymentMethod,
    );

    try {
      await repo.settlePlateBilling(
        documentId: documentId,
        lockedAtTimeInSeconds: currentTime,
        lockedFeeAmount: result.lockedFee,
        paymentMethod: result.paymentMethod,
        log: PlateLogModel(
          action: '사전 정산',
          area: _plate.area,
          billingType: _plate.billingType,
          from: _plate.type,
          performedBy: userName,
          plateNumber: _plate.plateNumber,
          timestamp: now,
          to: _plate.type,
          type: _plate.type,
          lockedFee: result.lockedFee,
          paymentMethod: result.paymentMethod,
          reason: result.reason?.trim(),
        ),
      );
      _reportDbSafe(
        area: _plate.area,
        action: 'write',
        source: 'departureCompletedStatus.prebill.repo.settlePlateBilling',
        n: 1,
      );

      final freshPlate = await repo.getPlate(documentId) ?? fallbackPlate;

      await plateState.tripleUpdatePlateLocally(
        PlateType.departureCompleted,
        freshPlate,
      );

      if (!mounted) return;

      setState(() => _plate = freshPlate);
      debugPrint(
        '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})',
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('사전 정산 중 오류가 발생했습니다: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    final lockedFee = _plate.lockedFeeAmount;
    final paymentMethod = (_plate.paymentMethod ?? '').trim();
    final billingType = (_plate.billingType ?? '').trim();
    final location =
    (_plate.location).trim().isEmpty ? '미지정' : _plate.location.trim();

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: _Brand.border(cs)),
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
                  _SheetTitleRow(
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
                          tone: _isLocked
                              ? _ActionTone.neutral
                              : _ActionTone.positive,
                          onTap: _handlePreBill,
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
                                Navigator.pop(context);
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
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w900, color: cs.onSurface),
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

    final badgeColor = isLocked ? cs.primary : cs.onSurfaceVariant;
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
        border: Border.all(color: _Brand.border(cs)),
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
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeColor.withOpacity(0.35)),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w900,
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
            fontWeight: FontWeight.w800,
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
            fontWeight: FontWeight.w800,
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
        border: Border.all(color: _Brand.border(cs)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: cs.onSurface)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
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

  const _ActionTileButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color base =
    (tone == _ActionTone.positive) ? _Brand.positive(cs) : cs.onSurface;
    final Color bg = (tone == _ActionTone.positive)
        ? _Brand.positiveBg(cs)
        : _Brand.neutralBg(cs);
    final Color border = _Brand.border(cs);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: base),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: cs.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
      icon: Icon(icon, size: 18, color: cs.onSurface),
      label: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
        textAlign: TextAlign.center,
      ),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 46),
        foregroundColor: cs.onSurface,
        side: BorderSide(color: _Brand.border(cs)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: cs.surfaceContainerLow,
      ).copyWith(
        overlayColor: MaterialStateProperty.resolveWith<Color?>(
              (states) => states.contains(MaterialState.pressed)
              ? cs.outlineVariant.withOpacity(0.12)
              : null,
        ),
      ),
    );
  }
}

void _reportDbSafe({
  required String area,
  required String action,
  required String source,
  int n = 1,
}) {
  try {} catch (_) {}
}
