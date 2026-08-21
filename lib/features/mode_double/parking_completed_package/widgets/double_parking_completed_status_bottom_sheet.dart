import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../app/utils/snackbar_helper.dart';

import '../../../account/applications/user_state.dart';
import '../../../dev/application/area_state.dart';
import '../../../payment/widgets/billing_bottom_sheet.dart';
import '../../../payment/widgets/confirm_cancel_fee_dialog.dart';
import '../../../../shared/page/modify/pages/modify_plate_screen.dart';
import '../../../../shared/plate/application/common/movement_plate.dart';
import '../../../../shared/plate/application/common/parking_completed_status_helpers.dart';
import '../../../../shared/plate/application/double/double_plate_state.dart';
import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/models/plate_log_model.dart';
import '../../../../shared/plate/domain/models/plate_model.dart';
import '../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../../shared/plate/widgets/plate_log_side_dock.dart';
import '../../../../shared/plate/widgets/parking_completed_common_dialog.dart';
import '../../../../shared/plate/widgets/parking_completed_status_widgets.dart';
import '../../../../shared/real_time_table/real_time_table_spec.dart';

Future<bool> _showDeleteDialog(BuildContext context, PlateModel plate) async {
  return showParkingCompletedDeleteDialog(context, plate);
}

Future<void> showDoubleParkingCompletedStatusSideDockFromRealtime({
  required BuildContext context,
  required RealTimePlateDetailRequest request,
}) async {
  PlateLogSideDockRequest? logRequest;
  PlateBillingSideDockRequest? billingRequest;
  await showParkingStatusLoadingSideDock<bool>(
    context: context,
    mode: '더블',
    statusTitle: request.statusTitle,
    plateId: request.plateId,
    plateNumber: request.plateNumber,
    area: request.area,
    location: request.location,
    cachedPlate: request.cachedPlate,
    loadPlate: request.loadPlate,
    finalizeTrace: false,
    onClosed: (trace, _) async {
      final requestedBilling = billingRequest;
      if (requestedBilling != null && context.mounted) {
        trace.log(
          'realtime_status_billing_handoff sourceDock=parking_status targetDock=plate_billing handoffPolicy=close_then_open overlayStacking=false plate=${requestedBilling.plate.plateNumber}',
          progress: .52,
        );
        final billedPlate = await showPlateBillingSideDock(
          context: context,
          request: requestedBilling,
        );
        if (!context.mounted) return;
        if (billedPlate != null && requestedBilling.onAfterSuccess != null) {
          try {
            await requestedBilling.onAfterSuccess!(billedPlate);
            if (!requestedBilling.reopenStatusAfterSuccess) {
              await trace.succeed('실시간 상태 처리에서 정산 후 요청된 상태 변경까지 완료했습니다.');
              return;
            }
          } catch (error) {
            trace.log(
              'realtime_status_billing_after_success_failed plate=${billedPlate.plateNumber} error=$error reopenStatus=true',
              progress: .66,
            );
          }
        }
        final reopenPlate = billedPlate ?? requestedBilling.plate;
        await trace.succeed('실시간 상태 처리에서 정산 후 상태 Side Dock을 다시 엽니다.');
        if (!context.mounted) return;
        await showDoubleParkingCompletedStatusBottomSheet(
          context: context,
          plate: reopenPlate,
          onRequestEntry: (traceLog) async {
            final activeArea = context.read<AreaState>().currentArea;
            await handleParkingCompletedEntryRequest(
              context,
              reopenPlate.plateNumber,
              activeArea,
              traceLog: traceLog,
            );
          },
          onDelete: () => _showDeleteDialog(context, reopenPlate),
        );
        return;
      }

      final requestedLog = logRequest;
      if (requestedLog != null && context.mounted) {
        trace.log(
          'realtime_status_log_handoff sourceDock=parking_status targetDock=plate_log handoffPolicy=close_then_open overlayStacking=false plate=${requestedLog.plateNumber}',
          progress: .94,
        );
        await trace.succeed('실시간 상태 처리에서 로그 Side Dock으로 handoff합니다.');
        await showPlateLogSideDock(
          context: context,
          request: requestedLog,
        );
      } else {
        await trace.succeed('실시간 상태 처리 세션이 종료되었습니다.');
        if (trace.developerMode && context.mounted) {
          await trace.showStatusDialog(context);
        }
      }
    },
    barrierDismissible: true,
    loadedBuilder: (dockContext, loadedPlate) {
      final division = dockContext.read<UserState>().division;
      final area = dockContext.read<AreaState>().currentArea;
      return _StatusSideDockContent(
        plate: loadedPlate,
        plateNumber: loadedPlate.plateNumber,
        division: division,
        area: area,
        onRequestEntry: (traceLog) async {
          await handleParkingCompletedEntryRequest(
            dockContext,
            loadedPlate.plateNumber,
            area,
            traceLog: traceLog,
          );
        },
        onDelete: () => _showDeleteDialog(dockContext, loadedPlate),
        onLogRequested: (value) {
          logRequest = value;
        },
        onBillingRequested: (value) {
          billingRequest = value;
        },
      );
    },
  );
}

Future<void> showDoubleParkingCompletedStatusBottomSheetFromDialog({
  required BuildContext context,
  required PlateModel plate,
  bool popParentOnDelete = true,
}) async {
  final deleted = await showDoubleParkingCompletedStatusBottomSheet(
    context: context,
    plate: plate,
    onRequestEntry: (traceLog) async {
      final area = context.read<AreaState>().currentArea;
      await handleParkingCompletedEntryRequest(
        context,
        plate.plateNumber,
        area,
        traceLog: traceLog,
      );
    },
    onDelete: () async {
      return await _showDeleteDialog(context, plate);
    },
  );

  if (deleted == true && popParentOnDelete) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    }
  }
}

Future<bool?> showDoubleParkingCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  required Future<void> Function(MovementPlateTraceLog? traceLog) onRequestEntry,
  required Future<bool> Function() onDelete,
}) async {
  final division = context.read<UserState>().division;
  final area = context.read<AreaState>().currentArea;
  var currentPlate = plate;
  final initialStatusTitle = '입차 완료 상태 처리';

  final trace = await traceParkingStatusSectorSummary(
    context: context,
    mode: '더블',
    statusTitle: initialStatusTitle,
    plateNumber: plate.plateNumber,
    area: plate.area,
    sectorId: plate.sectorId ?? '',
    sectorName: plate.sectorName ?? '',
  );
  if (!context.mounted) return null;

  trace.log(
    'presentation=right_side_dock direction=right_to_left management=left_rail footer=status_change_only plate=${plate.plateNumber} area=$area status=$initialStatusTitle',
    progress: .16,
  );

  while (context.mounted) {
    PlateLogSideDockRequest? logRequest;
    PlateBillingSideDockRequest? billingRequest;
    final currentStatusTitle = '입차 완료 상태 처리';
    final result = await showParkingStatusSideDock<bool>(
      trace: trace,
      context: context,
      finalizeTrace: false,
      barrierDismissible: true,
      builder: (_) => _StatusSideDockContent(
        plate: currentPlate,
        plateNumber: currentPlate.plateNumber,
        division: division,
        area: area,
        onRequestEntry: onRequestEntry,
        onDelete: onDelete,
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
        'status_billing_handoff sourceDock=parking_status targetDock=plate_billing handoffPolicy=close_then_open overlayStacking=false plate=${requestedBilling.plate.plateNumber} status=$currentStatusTitle',
        progress: .52,
      );
      final billedPlate = await showPlateBillingSideDock(
        context: context,
        request: requestedBilling,
      );
      if (!context.mounted) return result;
      if (billedPlate != null && requestedBilling.onAfterSuccess != null) {
        try {
          trace.log(
            'status_billing_after_success_started plate=${billedPlate.plateNumber} reopenStatus=${requestedBilling.reopenStatusAfterSuccess}',
            progress: .6,
          );
          await requestedBilling.onAfterSuccess!(billedPlate);
          trace.log(
            'status_billing_after_success_completed plate=${billedPlate.plateNumber}',
            progress: .68,
          );
          if (!requestedBilling.reopenStatusAfterSuccess) {
            await trace.succeed('정산 완료 후 요청된 상태 변경까지 완료했습니다.');
            return result;
          }
        } catch (error) {
          trace.log(
            'status_billing_after_success_failed plate=${billedPlate.plateNumber} error=$error reopenStatus=true',
            progress: .66,
          );
        }
      }
      currentPlate = billedPlate ?? requestedBilling.plate;
      trace.log(
        'status_billing_return targetDock=parking_status result=${billedPlate == null ? "cancelled" : "completed"} plate=${currentPlate.plateNumber} settled=${currentPlate.isLockedFee}',
        progress: .7,
      );
      continue;
    }

    final requestedLog = logRequest;
    if (requestedLog != null && context.mounted) {
      trace.log(
        'status_log_handoff sourceDock=parking_status targetDock=plate_log handoffPolicy=close_then_open overlayStacking=false plate=${requestedLog.plateNumber}',
        progress: .94,
      );
      await trace.succeed('상태 처리에서 로그 Side Dock으로 handoff합니다.');
      await showPlateLogSideDock(
        context: context,
        request: requestedLog,
      );
      return result;
    }

    await trace.succeed('상태 처리 세션이 종료되었습니다.');
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
    required this.onRequestEntry,
    required this.onDelete,
    required this.onLogRequested,
    required this.onBillingRequested,
  });

  final PlateModel plate;
  final String plateNumber;
  final String division;
  final String area;
  final Future<void> Function(MovementPlateTraceLog? traceLog) onRequestEntry;
  final Future<bool> Function() onDelete;
  final ValueChanged<PlateLogSideDockRequest> onLogRequested;
  final ValueChanged<PlateBillingSideDockRequest> onBillingRequested;

  @override
  State<_StatusSideDockContent> createState() => _StatusSideDockContentState();
}

class _StatusSideDockContentState extends State<_StatusSideDockContent> {
  late PlateModel _plate;

  final ScrollController _scrollController = ScrollController();




  bool _primaryBusy = false;

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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  ParkingCompletedBillingState get _billingState =>
      resolveParkingCompletedBillingState(
        billingType: _plate.billingType,
        isLocked: _plate.isLockedFee == true,
      );

  bool get _billingApplicable =>
      _billingState != ParkingCompletedBillingState.notApplicable;

  bool get _needsBilling =>
      _billingState == ParkingCompletedBillingState.unsettled;

  bool get _isFreeBilling =>
      (_plate.basicAmount ?? 0) == 0 && (_plate.addAmount ?? 0) == 0;


  String get _effectiveLocation =>
      resolveParkingCompletedEffectiveLocation(_plate);

  String get _plateDocId => resolveParkingCompletedDocId(_plate);

  Future<void> _runPrimary(Future<void> Function() fn) async {
    if (_primaryBusy) return;
    setState(() => _primaryBusy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _primaryBusy = false);
    }
  }


  Future<bool> _autoPreBillFreeIfNeeded() async {
    if (_plate.isLockedFee == true) return true;
    if (!_isFreeBilling) return false;
    parkingStatusTraceLog(
      context,
      '무료 자동 정산 시작 plate=${_plate.plateNumber} amount=0 firebaseWrite=true',
    );

    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final plateState = context.read<DoublePlateState>();

    final now = DateTime.now();
    final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;

    final updatedPlate = _plate.copyWith(
      isLockedFee: true,
      lockedAtTimeInSeconds: currentTime,
      lockedFeeAmount: 0,
      paymentMethod: '무료',
    );

    try {
      await repo.settlePlateBilling(
        documentId: _plateDocId,
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
      reportParkingCompletedDbSafe(
        area: _plate.area,
        action: 'write',
        source:
            'parkingCompletedStatus.freeAutoPrebill.repo.settlePlateBilling',
        n: 1,
      );

      final refreshedPlate = await repo.getPlate(_plateDocId) ?? updatedPlate;

      await plateState.doubleUpdatePlateLocally(
        PlateType.parkingCompleted,
        refreshedPlate,
      );

      if (!mounted) return false;
      setState(() => _plate = refreshedPlate);

      parkingStatusTraceLog(
        context,
        '무료 자동 정산 완료 plate=${_plate.plateNumber} amount=0 firebaseWrite=true firebaseRead=true',
      );
      return true;
    } catch (e) {
      parkingStatusTraceLog(
        context,
        '무료 자동 정산 실패 plate=${_plate.plateNumber} error=$e',
      );
      if (!mounted) return false;
      return false;
    }
  }

  Future<ParkingCompletedOverrideChoice?>
      _showDepartureOverrideDialog() async {
    return showParkingCompletedOverrideDialog(
      context: context,
      destinationLabel: '출차 완료',
    );
  }

  Future<void> _goDepartureCompleted() async {
    parkingStatusTraceLog(
      context,
      '상태 변경 시작 from=입차 완료 to=출차 완료 plate=${_plate.plateNumber}',
    );
    final movementPlate = context.read<MovementPlate>();
    await movementPlate.setDepartureCompletedDirectFromParkingCompleted(
      _plate.plateNumber,
      _plate.area,
      _effectiveLocation,
      traceLog: (message) => parkingStatusTraceLog(context, message),
    );

    if (!mounted) return;
    parkingStatusTraceLog(
      context,
      '상태 변경 완료 from=입차 완료 to=출차 완료 plate=${_plate.plateNumber}',
    );
    Navigator.pop(context);
  }

  Future<ParkingStatusDirectionalGearActionResult> _performPrebill({
    bool continueDepartureAfterSuccess = false,
  }) async {
    if (!_billingApplicable) {
      parkingStatusTraceLog(
        context,
        'billing_action=blocked reason=not_applicable plate=${_plate.plateNumber}',
      );
      return ParkingStatusDirectionalGearActionResult.blocked;
    }
    if ((_plate.billingType ?? '').trim().isEmpty) {
      parkingStatusTraceLog(
        context,
        'billing_action=blocked reason=billingType_empty plate=${_plate.plateNumber}',
      );
      return ParkingStatusDirectionalGearActionResult.blocked;
    }

    final plateSnapshot = _plate;
    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final plateState = context.read<DoublePlateState>();
    final movementPlate = continueDepartureAfterSuccess
        ? context.read<MovementPlate>()
        : null;
    final effectiveLocation = _effectiveLocation;
    final documentId = plateSnapshot.id.trim().isNotEmpty ? plateSnapshot.id.trim() : resolveParkingCompletedDocId(plateSnapshot);
    final request = PlateBillingSideDockRequest(
      plate: plateSnapshot,
      source: 'double_parking_completed_status',
      reopenStatusAfterSuccess: !continueDepartureAfterSuccess,
      onAfterSuccess: continueDepartureAfterSuccess
          ? (updatedPlate) async {
              await movementPlate!.setDepartureCompletedDirectFromParkingCompleted(
                updatedPlate.plateNumber,
                updatedPlate.area,
                effectiveLocation,
              );
            }
          : null,
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
        reportParkingCompletedDbSafe(
          area: plateSnapshot.area,
          action: 'write',
          source: 'parkingCompletedStatus.prebill.repo.settlePlateBilling',
          n: 1,
        );
        final refreshedPlate = await repo.getPlate(documentId) ?? fallbackPlate;
        await plateState.doubleUpdatePlateLocally(
          PlateType.parkingCompleted,
          refreshedPlate,
        );
        return refreshedPlate;
      },
    );
    parkingStatusTraceLog(
      context,
      'billing_handoff_requested sourceDock=parking_status targetDock=plate_billing policy=close_then_open overlay=false continueDepartureAfterSuccess=$continueDepartureAfterSuccess plate=${plateSnapshot.plateNumber}',
    );
    widget.onBillingRequested(request);
    Navigator.of(context).pop();
    return ParkingStatusDirectionalGearActionResult.cancelled;
  }

  Future<void> _handlePrebill() async {
    await _performPrebill();
  }

  Future<void> _handleCancelPrebill() async {
    if (!_billingApplicable) {
      parkingStatusTraceLog(
        context,
        'billing_action=blocked reason=not_applicable plate=${_plate.plateNumber}',
      );
      return;
    }
    parkingStatusTraceLog(
      context,
      '사전 정산 취소 시작 plate=${_plate.plateNumber}',
    );
    final trace = parkingStatusTraceOf(context);
    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final plateState = context.read<DoublePlateState>();

    if (_plate.isLockedFee != true) {
      parkingStatusTraceLog(
        context,
        '사전 정산 취소 중단 reason=not_locked plate=${_plate.plateNumber}',
      );
      return;
    }

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
    if (confirm != true) {
      parkingStatusTraceLog(
        context,
        '사전 정산 취소 중단 reason=user_cancel plate=${_plate.plateNumber}',
        progress: .38,
      );
      return;
    }

    final now = DateTime.now();
    final updatedPlate = _plate.copyWith(
      isLockedFee: false,
      lockedAtTimeInSeconds: null,
      lockedFeeAmount: null,
      paymentMethod: null,
    );
    parkingStatusTraceLog(
      context,
      'billing_cancel_persist_started plate=${_plate.plateNumber} documentId=$_plateDocId lockedFee=$cancelledFee payment=${cancelledPayment.isEmpty ? "unrecorded" : cancelledPayment}',
      progress: .56,
    );

    try {
      await repo.cancelPlateBilling(
        documentId: _plateDocId,
        log: PlateLogModel(
          action: '사전 정산 취소',
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
      reportParkingCompletedDbSafe(
        area: _plate.area,
        action: 'write',
        source: 'parkingCompletedStatus.unlock.repo.cancelPlateBilling',
        n: 1,
      );

      final refreshedPlate = await repo.getPlate(_plateDocId) ?? updatedPlate;

      await plateState.doubleUpdatePlateLocally(
        PlateType.parkingCompleted,
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
        '사전 정산 취소 완료 plate=${_plate.plateNumber} firebaseWrite=true firebaseRead=true previousLockedFee=$cancelledFee previousPayment=${cancelledPayment.isEmpty ? "unrecorded" : cancelledPayment}',
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
        '사전 정산 취소 실패 plate=${_plate.plateNumber} error=$error',
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
    final rootContext = Navigator.of(context, rootNavigator: true).context;


    return ParkingStatusSideDockFrame(
      title: widget.plateNumber,
      subtitle: parkingStatusHeaderSubtitle(
        statusTitle: '입차 완료 상태 처리',
        sectorId: _plate.sectorId,
        sectorName: _plate.sectorName,
      ),
      icon: Icons.directions_car_filled_rounded,
      closeEnabled: !_primaryBusy,
      onClose: () => Navigator.of(context).pop(),
      leadingRail: ParkingStatusManagementRail(
        debugTarget: 'departure_completed',
        actions: [
          ParkingStatusManagementAction(
            icon: Icons.history,
            label: '로그 확인',
            displayLabel: '로그',
            debugAction: 'history',
            enabled: !_primaryBusy,
            onPressed: () async {
              if (!mounted) return;
              final request = PlateLogSideDockRequest(
                plateNumber: widget.plateNumber,
                area: widget.area,
                plateId: _plate.id.trim().isEmpty ? null : _plate.id.trim(),
                source: 'double_parking_completed_status',
              );
              parkingStatusTraceLog(
                context,
                'log_handoff_requested sourceDock=parking_status targetDock=plate_log policy=close_then_open overlay=false plate=${widget.plateNumber}',
              );
              widget.onLogRequested(request);
              Navigator.of(context).pop();
            },
          ),
          if (_billingApplicable)
            ParkingStatusManagementAction(
              icon: _billingState == ParkingCompletedBillingState.settled
                  ? Icons.undo_rounded
                  : Icons.payments_rounded,
              label: _billingState == ParkingCompletedBillingState.settled
                  ? '정산 취소'
                  : '정산',
              displayLabel:
                  _billingState == ParkingCompletedBillingState.settled
                      ? '취소'
                      : '정산',
              debugAction: _billingState == ParkingCompletedBillingState.settled
                  ? 'billing_cancel'
                  : 'billing_settle',
              linkedGroup: 'settlement',
              linkedReverse:
                  _billingState == ParkingCompletedBillingState.settled,
              emphasized: _needsBilling,
              enabled: !_primaryBusy,
              onPressed: () async {
                if (_billingState == ParkingCompletedBillingState.settled) {
                  await _runPrimary(_handleCancelPrebill);
                  return;
                }
                await _runPrimary(_handlePrebill);
              },
            ),
          ParkingStatusManagementAction(
            icon: Icons.edit_note_outlined,
            label: '정보 수정',
            displayLabel: '수정',
            debugAction: 'edit',
            enabled: !_primaryBusy,
            onPressed: () async {
              Navigator.pop(context);
              Navigator.push(
                rootContext,
                MaterialPageRoute(
                  builder: (_) => ModifyPlateScreen(
                    plate: _plate,
                    collectionKey: PlateType.parkingCompleted,
                  ),
                ),
              );
            },
          ),
          ParkingStatusManagementAction(
            icon: Icons.delete_forever,
            label: '삭제',
            displayLabel: '삭제',
            debugAction: 'delete',
            destructive: true,
            enabled: !_primaryBusy,
            onPressed: () async {
              parkingStatusTraceLog(
                context,
                '삭제 요청 plate=${_plate.plateNumber}',
              );
              final deleted = await widget.onDelete();
              if (!mounted) return;
              parkingStatusTraceLog(
                context,
                '삭제 결과 plate=${_plate.plateNumber} deleted=$deleted',
              );
              if (deleted) {
                Navigator.of(context).pop(true);
              }
            },
          ),
        ],
      ),
      footer: ParkingStatusPrimaryFooter(
        debugTarget: 'departure_completed',
        child: ParkingStatusDirectionalGear(
          debugTarget: 'departure_completed',
          enabled: !_primaryBusy,
          busy: _primaryBusy,
          driving: false,
          lowerRight: ParkingStatusDirectionalGearAction(
            label: '출차 완료',
            debugAction: 'advance_departure_completed',
            icon: Icons.exit_to_app,
            onConfirmResult: () async {
              var result = ParkingStatusDirectionalGearActionResult.blocked;
              await _runPrimary(() async {
                if (_needsBilling) {
                  if (_isFreeBilling) {
                    parkingStatusTraceLog(
                      context,
                      'departure_completed_gate=billing_free_auto plate=${_plate.plateNumber}',
                    );
                    final ok = await _autoPreBillFreeIfNeeded();
                    if (!ok) {
                      parkingStatusTraceLog(
                        context,
                        'departure_completed_gate=billing_free_auto_result success=false plate=${_plate.plateNumber}',
                      );
                      result = ParkingStatusDirectionalGearActionResult.blocked;
                      return;
                    }
                    parkingStatusTraceLog(
                      context,
                      'departure_completed_gate=billing_free_auto_result success=true plate=${_plate.plateNumber}',
                    );
                    await _goDepartureCompleted();
                    result = ParkingStatusDirectionalGearActionResult.completed;
                    return;
                  }

                  parkingStatusTraceLog(
                    context,
                    'departure_completed_gate=billing_unsettled dialog=shown plate=${_plate.plateNumber}',
                  );
                  final choice = await _showDepartureOverrideDialog();
                  if (!mounted) {
                    result = ParkingStatusDirectionalGearActionResult.cancelled;
                    return;
                  }

                  if (choice == ParkingCompletedOverrideChoice.proceed) {
                    parkingStatusTraceLog(
                      context,
                      'departure_completed_gate=override_choice choice=proceed plate=${_plate.plateNumber}',
                    );
                    await _goDepartureCompleted();
                    result = ParkingStatusDirectionalGearActionResult.completed;
                    return;
                  }

                  if (choice == ParkingCompletedOverrideChoice.goBilling) {
                    parkingStatusTraceLog(
                      context,
                      'departure_completed_gate=override_choice choice=go_billing plate=${_plate.plateNumber}',
                    );
                    parkingStatusTraceLog(
                      context,
                      'departure_completed_gate=billing_open source=override plate=${_plate.plateNumber}',
                    );
                    final billingResult = await _performPrebill(
                      continueDepartureAfterSuccess: true,
                    );
                    if (!mounted) {
                      result = ParkingStatusDirectionalGearActionResult.cancelled;
                      return;
                    }
                    parkingStatusTraceLog(
                      context,
                      'departure_completed_gate=billing_result result=${billingResult.name} plate=${_plate.plateNumber}',
                    );
                    if (billingResult ==
                        ParkingStatusDirectionalGearActionResult.completed) {
                      parkingStatusTraceLog(
                        context,
                        'departure_completed_gate=billing_continue target=departure_completed plate=${_plate.plateNumber}',
                      );
                      await _goDepartureCompleted();
                      result = ParkingStatusDirectionalGearActionResult.completed;
                      return;
                    }
                    result = billingResult;
                    return;
                  }

                  parkingStatusTraceLog(
                    context,
                    'departure_completed_gate=override_choice choice=cancel plate=${_plate.plateNumber}',
                  );
                  result = ParkingStatusDirectionalGearActionResult.cancelled;
                  return;
                }

                parkingStatusTraceLog(
                  context,
                  'departure_completed_gate=billing_ready plate=${_plate.plateNumber}',
                );
                await _goDepartureCompleted();
                result = ParkingStatusDirectionalGearActionResult.completed;
              });
              return result;
            },
          ),
        ),
      ),
      child: ParkingStatusAdaptiveRequestBody(
        plate: _plate,
        area: widget.area,
        debugTarget: '입차 완료 상태 처리',
        scrollController: _scrollController,
      ),
    );
  }
}
