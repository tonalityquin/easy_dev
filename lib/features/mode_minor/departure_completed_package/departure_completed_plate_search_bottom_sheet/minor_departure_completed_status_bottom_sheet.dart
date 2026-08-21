import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/snackbar_helper.dart';
import '../../../../../features/account/applications/user_state.dart';
import '../../../../../features/dev/application/area_state.dart';
import '../../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../../features/payment/widgets/billing_bottom_sheet.dart';
import '../../../../../features/payment/widgets/confirm_cancel_fee_dialog.dart';
import '../../../../../shared/plate/application/minor/minor_plate_state.dart';
import '../../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../../shared/plate/domain/models/plate_log_model.dart';
import '../../../../../shared/plate/domain/models/plate_model.dart';
import '../../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../../../shared/plate/widgets/plate_log_side_dock.dart';
import '../../../../../shared/plate/widgets/parking_completed_status_widgets.dart';

Future<PlateModel?> showMinorDepartureCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
}) async {
  final division = context.read<UserState>().division;
  final area = context.read<AreaState>().currentArea;
  var currentPlate = plate;

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
    '[MinorDepartureSearchStatus] presentation=right_side_dock direction=right_to_left plate=${plate.plateNumber} area=$area',
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
      builder: (_) => _StatusSideDockContent(
        plate: currentPlate,
        plateNumber: currentPlate.plateNumber,
        division: division,
        area: area,
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
        'departure_search_status_billing_handoff sourceDock=parking_status targetDock=plate_billing handoffPolicy=close_then_open overlayStacking=false plate=${requestedBilling.plate.plateNumber}',
        progress: .52,
      );
      final billedPlate = await showPlateBillingSideDock(
        context: context,
        request: requestedBilling,
      );
      if (!context.mounted) return billedPlate;
      currentPlate = billedPlate ?? requestedBilling.plate;
      trace.log(
        'departure_search_status_billing_return targetDock=parking_status result=${billedPlate == null ? "cancelled" : "completed"} plate=${currentPlate.plateNumber} settled=${currentPlate.isLockedFee}',
        progress: .58,
      );
      continue;
    }

    final requestedLog = logRequest;
    if (requestedLog != null && context.mounted) {
      trace.log(
        'departure_search_status_log_handoff sourceDock=parking_status targetDock=plate_log handoffPolicy=close_then_open overlayStacking=false plate=${requestedLog.plateNumber}',
        progress: .94,
      );
      await trace.succeed('출차 완료 검색 상태 처리에서 로그 Side Dock으로 handoff합니다.');
      await showPlateLogSideDock(
        context: context,
        request: requestedLog,
      );
      return result;
    }

    await trace.succeed('출차 완료 검색 상태 처리 세션이 종료되었습니다.');
    if (trace.developerMode && context.mounted) {
      await trace.showStatusDialog(context);
    }
    return result;
  }
  return null;
}

class _StatusSideDockContent extends StatefulWidget {
  const _StatusSideDockContent({
    required this.plate,
    required this.plateNumber,
    required this.division,
    required this.area,
    required this.onLogRequested,
    required this.onBillingRequested,
  });

  final PlateModel plate;
  final String plateNumber;
  final String division;
  final String area;
  final ValueChanged<PlateLogSideDockRequest> onLogRequested;
  final ValueChanged<PlateBillingSideDockRequest> onBillingRequested;

  @override
  State<_StatusSideDockContent> createState() => _StatusSideDockContentState();
}

class _StatusSideDockContentState extends State<_StatusSideDockContent> {
  late PlateModel _plate;

  bool _busy = false;

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

  String _plateDocIdSafe() {
    final id = _plate.id.trim();
    if (id.isNotEmpty) return id;

    final plateNumber = _plate.plateNumber.trim().isNotEmpty
        ? _plate.plateNumber.trim()
        : widget.plateNumber.trim();

    final area =
    _plate.area.trim().isNotEmpty ? _plate.area.trim() : widget.area.trim();

    return '${plateNumber}_$area';
  }

  Future<bool> _autoPreBillFreeIfNeeded() async {
    if (_isLocked) return true;
    if (!_isFreeBilling) return false;

    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final plateState = context.read<MinorPlateState>();

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
      await repo.settlePlateBilling(
        documentId: plateId,
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
        source:
        'departureCompletedStatus.freeAutoPrebill.repo.settlePlateBilling',
        n: 1,
      );

      final refreshedPlate = await repo.getPlate(plateId) ?? updatedPlate;

      await plateState.minorUpdatePlateLocally(
        PlateType.departureCompleted,
        refreshedPlate,
      );

      if (!mounted) return false;

      setState(() => _plate = refreshedPlate);
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
      parkingStatusTraceLog(context, '이미 정산(잠금) 완료된 차량입니다.');
      return;
    }
    if (_isFreeBilling) {
      await _autoPreBillFreeIfNeeded();
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
    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final plateState = context.read<MinorPlateState>();
    final plateId = _plateDocIdSafe();
    final request = PlateBillingSideDockRequest(
      plate: plateSnapshot,
      source: 'minor_departure_search_status',
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
          documentId: plateId,
          lockedAtTimeInSeconds: settledAt,
          lockedFeeAmount: result.lockedFee,
          paymentMethod: result.paymentMethod,
          log: PlateLogModel(
            action: '사전 정산',
            area: plateSnapshot.area,
            billingType: plateSnapshot.billingType,
            from: plateSnapshot.type,
            performedBy: userName,
            plateNumber: plateSnapshot.plateNumber,
            timestamp: now,
            to: plateSnapshot.type,
            type: plateSnapshot.type,
            lockedFee: result.lockedFee,
            paymentMethod: result.paymentMethod,
            reason: result.reason?.trim(),
          ),
        );
        _reportDbSafe(
          area: plateSnapshot.area,
          action: 'write',
          source: 'departureCompletedStatus.prebill.repo.settlePlateBilling',
          n: 1,
        );
        final freshPlate = await repo.getPlate(plateId) ?? fallbackPlate;
        await plateState.minorUpdatePlateLocally(
          PlateType.departureCompleted,
          freshPlate,
        );
        return freshPlate;
      },
    );
    parkingStatusTraceLog(
      context,
      'billing_handoff_requested sourceDock=parking_status targetDock=plate_billing policy=close_then_open overlay=false plate=${plateSnapshot.plateNumber}',
    );
    widget.onBillingRequested(request);
    Navigator.of(context).pop();
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

    final trace = parkingStatusTraceOf(context);
    final cancelledFee = _plate.lockedFeeAmount ?? 0;
    final cancelledPayment = (_plate.paymentMethod ?? '').trim();
    parkingStatusTraceLog(
      context,
      'billing_cancel_review_open plate=${_plate.plateNumber} lockedFee=$cancelledFee payment=${cancelledPayment.isEmpty ? "unrecorded" : cancelledPayment} reviewSeconds=3',
      progress: .24,
    );
    final confirm = await showCommonOverlayDialog<bool>(
      context: context,
      builder: (_) => ConfirmCancelFeeDialog(
        plateNumber: _plate.plateNumber,
        lockedFeeAmount: cancelledFee,
        paymentMethod: cancelledPayment,
        trace: trace,
      ),
    );
    if (confirm != true || !mounted) {
      parkingStatusTraceLog(
        context,
        '정산 취소 중단 reason=user_cancel plate=${_plate.plateNumber}',
        progress: .38,
      );
      return;
    }

    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final plateState = context.read<MinorPlateState>();
    final plateId = _plate.id.trim().isNotEmpty
        ? _plate.id.trim()
        : '${_plate.plateNumber}_${_plate.area}';
    final now = DateTime.now();
    final fallbackPlate = _plate.copyWith(isLockedFee: false);
    parkingStatusTraceLog(
      context,
      'billing_cancel_persist_started plate=${_plate.plateNumber} documentId=$plateId lockedFee=$cancelledFee payment=${cancelledPayment.isEmpty ? "unrecorded" : cancelledPayment}',
      progress: .56,
    );

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
          lockedFee: _plate.lockedFeeAmount,
          paymentMethod: _plate.paymentMethod,
        ),
      );
      _reportDbSafe(
        area: _plate.area,
        action: 'write',
        source: 'departureCompletedStatus.cancelPrebill.repo.cancelPlateBilling',
        n: 1,
      );

      final refreshedPlate = await repo.getPlate(plateId) ?? fallbackPlate;

      await plateState.minorUpdatePlateLocally(
        PlateType.departureCompleted,
        refreshedPlate,
      );

      if (!mounted) return;
      setState(() => _plate = refreshedPlate);
      HapticFeedback.mediumImpact();
      parkingStatusTraceLog(
        context,
        'billing_state_transition from=settled to=unsettled plate=${_plate.plateNumber} animation=status_morph_190_230',
        progress: .86,
      );
      parkingStatusTraceLog(
        context,
        '정산 취소 완료 plate=${_plate.plateNumber} firebaseWrite=true firebaseRead=true previousLockedFee=$cancelledFee previousPayment=${cancelledPayment.isEmpty ? "unrecorded" : cancelledPayment}',
        progress: .92,
      );
      showSuccessSnackbar(
        context,
        '정산이 취소되었습니다. 다음 정산 시 요금이 다시 계산됩니다.',
        useCommonUi: true,
      );
      if (trace?.developerMode == true && mounted) {
        await trace!.showSnapshotStatusDialog(
          context,
          title: '정산 취소 완료',
          description: '정산 취소가 완료되었습니다. debugPrint 로그를 확인하고 클립보드로 복사할 수 있습니다.',
        );
      }
    } catch (error, stackTrace) {
      parkingStatusTraceLog(
        context,
        '정산 취소 실패 plate=${_plate.plateNumber} error=$error',
        progress: .72,
      );
      parkingStatusTraceLog(context, 'billing_cancel_stacktrace $stackTrace');
      if (!mounted) return;
      HapticFeedback.vibrate();
      showFailedSnackbar(
        context,
        '정산 취소에 실패했습니다. 기존 정산은 유지됩니다.',
        useCommonUi: true,
      );
      if (trace?.developerMode == true && mounted) {
        await trace!.showSnapshotStatusDialog(
          context,
          title: '정산 취소 실패',
          description: '정산 취소에 실패해 기존 정산이 유지됩니다. debugPrint 로그를 확인하고 클립보드로 복사할 수 있습니다.',
          failure: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {

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
                        enabled: !_busy,
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
                                if (!mounted) return;
                                final request = PlateLogSideDockRequest(
                                  plateNumber: widget.plateNumber,
                                  area: widget.area,
                                  plateId: _plate.id.trim().isEmpty ? null : _plate.id.trim(),
                                  source: 'minor_departure_search_status',
                                );
                                parkingStatusTraceLog(
                                  context,
                                  'log_handoff_requested sourceDock=parking_status targetDock=plate_log policy=close_then_open overlay=false plate=${widget.plateNumber}',
                                );
                                widget.onLogRequested(request);
                                Navigator.of(context).pop();
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
