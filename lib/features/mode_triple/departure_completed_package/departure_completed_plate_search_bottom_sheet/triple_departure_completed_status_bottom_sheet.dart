import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../features/account/applications/user_state.dart';
import '../../../../../features/dev/application/area_state.dart';
import '../../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../../features/payment/widgets/billing_bottom_sheet.dart';
import '../../../../../features/payment/widgets/confirm_cancel_fee_dialog.dart';
import '../../../../../shared/plate/application/triple/triple_plate_state.dart';
import '../../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../../shared/plate/domain/models/plate_log_model.dart';
import '../../../../../shared/plate/domain/models/plate_model.dart';
import '../../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../../../shared/plate/widgets/log_viewer_bottom_sheet.dart';
import '../../../../../shared/plate/widgets/parking_completed_status_widgets.dart';

Future<PlateModel?> showTripleDepartureCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
}) async {
  final plateNumber = plate.plateNumber;
  final division = context.read<UserState>().division;
  final area = context.read<AreaState>().currentArea;

  final trace = await traceParkingStatusSectorSummary(
    context: context,
    mode: '트리플',
    statusTitle: '출차 완료 상태 처리',
    plateNumber: plateNumber,
    area: plate.area,
    sectorId: plate.sectorId ?? '',
    sectorName: plate.sectorName ?? '',
  );
  if (!context.mounted) return null;

  trace.log(
    '[TripleDepartureSearchStatus] presentation=right_side_dock direction=right_to_left plate=$plateNumber area=$area',
    progress: .16,
  );
  return showParkingStatusSideDock<PlateModel>(
    trace: trace,
    context: context,
    barrierDismissible: true,
    builder: (_) => _StatusSideDockContent(
      plate: plate,
      plateNumber: plateNumber,
      division: division,
      area: area,
    ),
  );
}

class _StatusSideDockContent extends StatefulWidget {
  const _StatusSideDockContent({
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
  State<_StatusSideDockContent> createState() => _StatusSideDockContentState();
}

class _StatusSideDockContentState extends State<_StatusSideDockContent> {
  late PlateModel _plate;

  @override
  void initState() {
    super.initState();
    _plate = widget.plate;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      parkingStatusTraceLog(
        context,
        'billing_state=${parkingCompletedBillingStateDebugName(_billingState)} '
        'billingType=${_billingApplicable ? (_plate.billingType ?? '').trim() : "none"} '
        'bypass=${_billingState == ParkingCompletedBillingState.notApplicable}',
      );
    });
  }

  bool get _isLocked => _plate.isLockedFee == true;

  ParkingCompletedBillingState get _billingState =>
      resolveParkingCompletedBillingState(
        billingType: _plate.billingType,
        isLocked: _isLocked,
      );

  bool get _billingApplicable =>
      _billingState != ParkingCompletedBillingState.notApplicable;

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
      parkingStatusTraceLog(
        context,
        'billing_state_transition from=unsettled to=settled plate=${_plate.plateNumber}',
      );
      parkingStatusTraceLog(context,'무료 정산이 자동 처리되었습니다. (₩0)');
      return true;
    } catch (e) {
      if (!mounted) return false;
      parkingStatusTraceLog(context,'무료 자동 정산 중 오류가 발생했습니다: $e');
      return false;
    }
  }

  Future<void> _handlePreBill() async {
    if (!_billingApplicable) {
      parkingStatusTraceLog(
        context,
        'billing_action=blocked reason=not_applicable plate=${_plate.plateNumber}',
      );
      return;
    }
    if (_isLocked) {
      parkingStatusTraceLog(context,'이미 정산(잠금) 완료된 차량입니다.');
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
      parkingStatusTraceLog(context,'정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
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
      traceLog: (message) => parkingStatusTraceLog(context, message),
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
      parkingStatusTraceLog(
        context,
        'billing_state_transition from=unsettled to=settled plate=${_plate.plateNumber}',
      );
      parkingStatusTraceLog(context,
        '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})',
      );
    } catch (e) {
      if (!mounted) return;
      parkingStatusTraceLog(context,'사전 정산 중 오류가 발생했습니다: $e');
    }
  }

  Future<void> _handleCancelPrebill() async {
    if (!_billingApplicable) {
      parkingStatusTraceLog(
        context,
        'billing_action=blocked reason=not_applicable plate=${_plate.plateNumber}',
      );
      return;
    }
    if (!_isLocked) {
      parkingStatusTraceLog(context, '정산 완료된 데이터만 취소할 수 있습니다.');
      return;
    }

    final confirm = await showCommonOverlayDialog<bool>(
      context: context,
      builder: (_) => const ConfirmCancelFeeDialog(),
    );
    if (confirm != true || !mounted) return;

    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final plateState = context.read<TriplePlateState>();
    final plateId = _plate.id.trim().isNotEmpty
        ? _plate.id.trim()
        : '${_plate.plateNumber}_${_plate.area}';
    final now = DateTime.now();

    try {
      await repo.cancelPlateBilling(
        documentId: plateId,
        log: PlateLogModel(
          action: '정산 취소',
          area: _plate.area,
          billingType: _plate.billingType,
          from: _plate.type,
          performedBy: userName,
          plateNumber: _plate.plateNumber,
          timestamp: now,
          to: _plate.type,
          type: _plate.type,
        ),
      );
      _reportDbSafe(
        area: _plate.area,
        action: 'write',
        source: 'departureCompletedStatus.cancelPrebill.repo.cancelPlateBilling',
        n: 1,
      );

      final refreshedPlate = await repo.getPlate(plateId) ??
          _plate.copyWith(isLockedFee: false);

      await plateState.tripleUpdatePlateLocally(
        PlateType.departureCompleted,
        refreshedPlate,
      );

      if (!mounted) return;
      setState(() => _plate = refreshedPlate);
      parkingStatusTraceLog(
        context,
        'billing_state_transition from=settled to=unsettled plate=${_plate.plateNumber}',
      );
      parkingStatusTraceLog(context, '정산이 취소되었습니다.');
    } catch (error) {
      if (!mounted) return;
      parkingStatusTraceLog(context, '정산 취소 중 오류가 발생했습니다: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    return ParkingStatusSideDockFrame(
      title: widget.plateNumber,
      subtitle: parkingStatusHeaderSubtitle(
        statusTitle: '출차 완료 상태 처리',
        sectorId: _plate.sectorId,
        sectorName: _plate.sectorName,
      ),
      icon: Icons.task_alt_rounded,
      onClose: () => Navigator.pop(context),
      child: ListView(
                padding: const EdgeInsets.fromLTRB(2, 2, 2, 12),
                children: [
                  ParkingStatusVehicleLocationCard(
                    plate: _plate,
                    area: widget.area,
                  ),
                  if (_billingApplicable) ...[
                    const SizedBox(height: 14),
                    _SectionCard(
                      title: '정산 관리',
                      subtitle: '현재 차량의 사전 정산 상태를 관리합니다.',
                      child: ParkingCompletedBillingActionButton(
                        billingState: _billingState,
                        enabled: true,
                        onSettle: _handlePreBill,
                        onCancel: _handleCancelPrebill,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: '빠른 실행',
                    subtitle: '현재 차량의 관련 기능을 바로 실행합니다.',
                    child: Column(
                      children: [
                        ParkingCompletedActionList(
                          children: [
                            ParkingCompletedSecondaryActionButton(
                              icon: Icons.history,
                              label: '로그 확인',
                              onPressed: () async {
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
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ParkingCompletedSectionCard(
      title: title,
      subtitle: subtitle,
      child: child,
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
