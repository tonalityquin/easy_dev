import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../features/payment/widgets/billing_bottom_sheet.dart';
import '../../../../shared/plate/domain/models/plate_log_model.dart';
import '../../../../shared/plate/domain/models/plate_model.dart';
import '../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../../shared/plate/widgets/plate_log_side_dock.dart';
import '../../../../shared/plate/widgets/parking_completed_status_widgets.dart';

Future<PlateModel?> showMinorDepartureCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  String? performedBy,
}) async {
  final normalizedPerformedBy = (performedBy ?? '').trim();
  final who = normalizedPerformedBy.isEmpty ? '-' : normalizedPerformedBy;
  var currentPlate = plate;
  var latestPlate = plate;
  var changed = false;

  final trace = await traceParkingStatusSectorSummary(
    context: context,
    mode: '마이너',
    statusTitle: '출차 완료 상태 처리',
    plateNumber: plate.plateNumber,
    area: plate.area,
    sectorId: plate.sectorId ?? '',
    sectorName: plate.sectorName ?? '',
  );
  if (!context.mounted) return null;

  trace.log(
    '[MinorDepartureStatus] presentation=right_side_dock direction=right_to_left plate=${plate.plateNumber} area=${plate.area}',
    progress: .16,
  );

  while (context.mounted) {
    PlateLogSideDockRequest? logRequest;
    PlateBillingSideDockRequest? billingRequest;
    final result = await showParkingStatusSideDock<PlateModel>(
      trace: trace,
      context: context,
      finalizeTrace: false,
      barrierDismissible: true,
      builder: (_) => _MinorDepartureCompletedStatusDock(
        plate: currentPlate,
        performedBy: who,
        onChanged: (updated) {
          latestPlate = updated;
          changed = true;
        },
        onLogRequested: (request) {
          logRequest = request;
        },
        onBillingRequested: (request) {
          billingRequest = request;
        },
      ),
    );

    final requestedBilling = billingRequest;
    if (requestedBilling != null && context.mounted) {
      trace.log(
        'departure_status_billing_handoff sourceDock=parking_status targetDock=plate_billing handoffPolicy=close_then_open overlayStacking=false plate=${requestedBilling.plate.plateNumber}',
        progress: .52,
      );
      final billedPlate = await showPlateBillingSideDock(
        context: context,
        request: requestedBilling,
      );
      if (!context.mounted) return billedPlate ?? (changed ? latestPlate : null);
      currentPlate = billedPlate ?? requestedBilling.plate;
      if (billedPlate != null) {
        latestPlate = billedPlate;
        changed = true;
      }
      trace.log(
        'departure_status_billing_return targetDock=parking_status result=${billedPlate == null ? "cancelled" : "completed"} plate=${currentPlate.plateNumber} settled=${currentPlate.isLockedFee}',
        progress: .58,
      );
      continue;
    }

    final requestedLog = logRequest;
    if (requestedLog != null && context.mounted) {
      trace.log(
        'departure_status_log_handoff sourceDock=parking_status targetDock=plate_log handoffPolicy=close_then_open overlayStacking=false plate=${requestedLog.plateNumber}',
        progress: .94,
      );
      await trace.succeed('출차 완료 상태 처리에서 로그 Side Dock으로 handoff합니다.');
      await showPlateLogSideDock(
        context: context,
        request: requestedLog,
      );
      return result ?? (changed ? latestPlate : null);
    }

    await trace.succeed('출차 완료 상태 처리 세션이 종료되었습니다.');
    if (trace.developerMode && context.mounted) {
      await trace.showStatusDialog(context);
    }
    return result ?? (changed ? latestPlate : null);
  }
  return null;
}

class _MinorDepartureCompletedStatusDock extends StatefulWidget {
  const _MinorDepartureCompletedStatusDock({
    required this.plate,
    required this.performedBy,
    required this.onChanged,
    required this.onLogRequested,
    required this.onBillingRequested,
  });

  final PlateModel plate;
  final String performedBy;
  final ValueChanged<PlateModel> onChanged;
  final ValueChanged<PlateLogSideDockRequest> onLogRequested;
  final ValueChanged<PlateBillingSideDockRequest> onBillingRequested;

  @override
  State<_MinorDepartureCompletedStatusDock> createState() =>
      _MinorDepartureCompletedStatusDockState();
}

class _MinorDepartureCompletedStatusDockState
    extends State<_MinorDepartureCompletedStatusDock> {
  late PlateModel _plate;
  bool _changed = false;

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

  void _applyUpdate(PlateModel updated, {required bool settled}) {
    if (!mounted) return;
    setState(() {
      _plate = updated;
      _changed = true;
    });
    widget.onChanged(updated);
    parkingStatusTraceLog(
      context,
      settled
          ? 'billing_state_transition from=unsettled to=settled plate=${updated.plateNumber}'
          : 'billing_state_transition from=settled to=unsettled plate=${updated.plateNumber}',
    );
  }

  Future<void> _handleSettle() async {
    if (!_billingApplicable) {
      parkingStatusTraceLog(
        context,
        'billing_action=blocked reason=not_applicable plate=${_plate.plateNumber}',
      );
      return;
    }
    if (_plate.isLockedFee == true) {
      parkingStatusTraceLog(context, '이미 정산 완료된 데이터입니다.');
      return;
    }
    if ((_plate.billingType ?? '').trim().isEmpty) {
      parkingStatusTraceLog(
        context,
        'billing_action=blocked reason=billingType_empty plate=${_plate.plateNumber}',
      );
      return;
    }

    final plateSnapshot = _plate;
    final repo = context.read<PlateRepository>();
    final performedBy = widget.performedBy;
    final documentId = plateSnapshot.id;
    final request = PlateBillingSideDockRequest(
      plate: plateSnapshot,
      source: 'minor_departure_completed_status',
      onSubmit: (result) async {
        final now = DateTime.now();
        final settledAt = now.toUtc().millisecondsSinceEpoch ~/ 1000;
        final fallbackPlate = plateSnapshot.copyWith(
          isLockedFee: true,
          lockedAtTimeInSeconds: settledAt,
          lockedFeeAmount: result.lockedFee,
          paymentMethod: result.paymentMethod,
        );
        await repo.settlePlateBilling(
          documentId: documentId,
          lockedAtTimeInSeconds: settledAt,
          lockedFeeAmount: result.lockedFee,
          paymentMethod: result.paymentMethod,
          log: PlateLogModel(
            action: '사전 정산',
            area: plateSnapshot.area,
            billingType: plateSnapshot.billingType,
            from: plateSnapshot.type,
            performedBy: performedBy,
            plateNumber: plateSnapshot.plateNumber,
            timestamp: now,
            to: plateSnapshot.type,
            type: plateSnapshot.type,
            lockedFee: result.lockedFee,
            paymentMethod: result.paymentMethod,
            reason: result.reason?.trim(),
          ),
        );
        return await repo.getPlate(documentId) ?? fallbackPlate;
      },
    );
    parkingStatusTraceLog(
      context,
      'billing_handoff_requested sourceDock=parking_status targetDock=plate_billing policy=close_then_open overlay=false plate=${plateSnapshot.plateNumber}',
    );
    widget.onBillingRequested(request);
    Navigator.of(context).pop(_changed ? _plate : null);
  }

  Future<void> _handleCancel() async {
    if (!_billingApplicable) {
      parkingStatusTraceLog(
        context,
        'billing_action=blocked reason=not_applicable plate=${_plate.plateNumber}',
      );
      return;
    }
    final ok = await _confirmCancelSettlement(context);
    if (!ok || !mounted) return;
    final updated = await _cancelSettlement(
      context: context,
      plate: _plate,
      performedBy: widget.performedBy,
    );
    if (updated == null) return;
    _applyUpdate(updated, settled: false);
  }

  void _close() {
    Navigator.pop(context, _changed ? _plate : null);
  }

  Future<void> _requestLog() async {
    if (!mounted) return;
    final request = PlateLogSideDockRequest(
      plateNumber: _plate.plateNumber,
      area: _plate.area,
      plateId: _plate.id.trim().isEmpty ? null : _plate.id.trim(),
      source: 'minor_departure_completed_status',
    );
    parkingStatusTraceLog(
      context,
      'log_handoff_requested sourceDock=parking_status targetDock=plate_log policy=close_then_open overlay=false plate=${_plate.plateNumber}',
    );
    widget.onLogRequested(request);
    Navigator.of(context).pop(_changed ? _plate : null);
  }

  @override
  Widget build(BuildContext context) {
    final actions = <ParkingStatusManagementAction>[
      ParkingStatusManagementAction(
        icon: Icons.history_rounded,
        label: '로그',
        displayLabel: '로그',
        onPressed: _requestLog,
        debugAction: 'log',
      ),
      if (_billingApplicable)
        ParkingStatusManagementAction(
          icon: _isLocked ? Icons.undo_rounded : Icons.receipt_long_rounded,
          label: _isLocked ? '취소' : '정산',
          displayLabel: _isLocked ? '취소' : '정산',
          onPressed: _isLocked ? _handleCancel : _handleSettle,
          destructive: _isLocked,
          emphasized: !_isLocked,
          debugAction: _isLocked ? 'billing_cancel' : 'billing_settle',
          linkedGroup: 'billing',
          linkedReverse: _isLocked,
        ),
      ParkingStatusManagementAction(
        icon: Icons.edit_note_rounded,
        label: '수정',
        displayLabel: '수정',
        onPressed: () async {},
        enabled: false,
        debugAction: 'edit_disabled',
      ),
    ];
    parkingStatusTraceLog(
      context,
      'departure_status_layout=left_management_rail actions=${actions.map((e) => e.visualLabel).join("/")} billingState=${parkingCompletedBillingStateDebugName(_billingState)}',
    );
    return ParkingStatusSideDockFrame(
      title: _plate.plateNumber,
      subtitle: parkingStatusHeaderSubtitle(
        statusTitle: '출차 완료 상태 처리',
        sectorId: _plate.sectorId,
        sectorName: _plate.sectorName,
      ),
      icon: Icons.task_alt_rounded,
      onClose: _close,
      leadingRail: ParkingStatusManagementRail(
        actions: actions,
        title: '차량',
        debugTarget: 'minor_departure_completed_status',
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 12),
        children: [
          ParkingStatusVehicleLocationCard(
            plate: _plate,
            area: _plate.area,
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

Future<PlateModel?> _cancelSettlement({
  required BuildContext context,
  required PlateModel plate,
  required String performedBy,
}) async {
  if (plate.isLockedFee != true) {
    parkingStatusTraceLog(context,'정산 완료된 데이터만 취소할 수 있습니다.');
    return null;
  }

  final now = DateTime.now();

  try {
    final repo = context.read<PlateRepository>();

    await repo.cancelPlateBilling(
      documentId: plate.id,
      log: PlateLogModel(
        action: '정산 취소',
        area: plate.area,
        billingType: plate.billingType,
        from: plate.type,
        performedBy: performedBy,
        plateNumber: plate.plateNumber,
        timestamp: now,
        to: plate.type,
        type: plate.type,
      ),
    );

    if (!context.mounted) return null;
    parkingStatusTraceLog(context,'정산이 취소되었습니다.');

    return await repo.getPlate(plate.id) ?? plate.copyWith(isLockedFee: false);
  } catch (e) {
    if (!context.mounted) return null;
    parkingStatusTraceLog(context,'정산 취소 중 오류가 발생했습니다: $e');
    return null;
  }
}
