import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../features/payment/widgets/billing_bottom_sheet.dart';
import '../../../../../shared/plate/domain/models/plate_log_model.dart';
import '../../../../../shared/plate/domain/models/plate_model.dart';
import '../../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../../../shared/plate/widgets/log_viewer_bottom_sheet.dart';
import '../../../../../shared/plate/widgets/parking_completed_status_widgets.dart';

Future<PlateModel?> showMinorDepartureCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  String? performedBy,
}) async {
  final String who =
      (performedBy ?? '').trim().isEmpty ? '-' : performedBy!.trim();
  final BuildContext hostContext = context;
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
  final result = await showParkingStatusSideDock<PlateModel>(
    trace: trace,
    context: context,
    barrierDismissible: true,
    builder: (_) => _MinorDepartureCompletedStatusDock(
      hostContext: hostContext,
      plate: plate,
      performedBy: who,
      onChanged: (updated) {
        latestPlate = updated;
        changed = true;
      },
    ),
  );
  return result ?? (changed ? latestPlate : null);
}

class _MinorDepartureCompletedStatusDock extends StatefulWidget {
  const _MinorDepartureCompletedStatusDock({
    required this.hostContext,
    required this.plate,
    required this.performedBy,
    required this.onChanged,
  });

  final BuildContext hostContext;
  final PlateModel plate;
  final String performedBy;
  final ValueChanged<PlateModel> onChanged;

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
    final updated = await _settlePlate(
      context: context,
      plate: _plate,
      performedBy: widget.performedBy,
    );
    if (updated == null) return;
    _applyUpdate(updated, settled: true);
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

  @override
  Widget build(BuildContext context) {
    return ParkingStatusSideDockFrame(
      title: _plate.plateNumber,
      subtitle: parkingStatusHeaderSubtitle(
        statusTitle: '출차 완료 상태 처리',
        sectorId: _plate.sectorId,
        sectorName: _plate.sectorName,
      ),
      icon: Icons.task_alt_rounded,
      onClose: _close,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 12),
        children: [
          ParkingStatusVehicleLocationCard(
            plate: _plate,
            area: _plate.area,
          ),
          if (_billingApplicable) ...[
            const SizedBox(height: 14),
            ParkingCompletedSectionCard(
              title: '정산 관리',
              subtitle: '현재 차량의 사전 정산 상태를 관리합니다.',
              child: ParkingCompletedBillingActionButton(
                billingState: _billingState,
                onSettle: _handleSettle,
                onCancel: _handleCancel,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ParkingCompletedSectionCard(
            title: '빠른 실행',
            subtitle: '현재 차량의 관련 기능을 바로 실행합니다.',
            child: ParkingCompletedActionList(
              children: [
                ParkingCompletedSecondaryActionButton(
                  icon: Icons.history_rounded,
                  label: '로그 확인',
                  onPressed: () async {
                    await LogViewerBottomSheet.show(
                      widget.hostContext,
                      division: '-',
                      area: _plate.area,
                      requestTime: _plate.requestTime,
                      initialPlateNumber: _plate.plateNumber,
                      plateId: _plate.id,
                    );
                  },
                ),
                ParkingCompletedSecondaryActionButton(
                  icon: Icons.edit_note_rounded,
                  label: '정보 수정',
                  enabled: false,
                  onPressed: () async {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
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
    parkingStatusTraceLog(context,'이미 정산 완료된 데이터입니다.');
    return null;
  }

  final bt = (plate.billingType ?? '').trim();
  if (bt.isEmpty) {
    parkingStatusTraceLog(context,'정산 타입(billingType)이 지정되지 않아 정산할 수 없습니다.');
    return null;
  }

  final now = DateTime.now();
  final int currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;
  final int entryTime =
      plate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;

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
    regularDurationValue: plate.regularDurationValue,
    traceLog: (message) => parkingStatusTraceLog(context, message),
  );

  if (result == null) return null;

  final updatedPlate = plate.copyWith(
    isLockedFee: true,
    lockedAtTimeInSeconds: currentTime,
    lockedFeeAmount: result.lockedFee,
    paymentMethod: result.paymentMethod,
  );

  try {
    final repo = context.read<PlateRepository>();

    await repo.settlePlateBilling(
      documentId: plate.id,
      lockedAtTimeInSeconds: currentTime,
      lockedFeeAmount: result.lockedFee,
      paymentMethod: result.paymentMethod,
      log: PlateLogModel(
        action: '사전 정산',
        area: plate.area,
        billingType: plate.billingType,
        from: plate.type,
        performedBy: performedBy,
        plateNumber: plate.plateNumber,
        timestamp: now,
        to: plate.type,
        type: plate.type,
        lockedFee: result.lockedFee,
        paymentMethod: result.paymentMethod,
        reason: result.reason,
      ),
    );

    if (!context.mounted) return null;
    parkingStatusTraceLog(context,'정산 완료: ₩${result.lockedFee} (${result.paymentMethod})');

    return await repo.getPlate(plate.id) ?? updatedPlate;
  } catch (e) {
    if (!context.mounted) return null;
    parkingStatusTraceLog(context,'정산 중 오류가 발생했습니다: $e');
    return null;
  }
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
