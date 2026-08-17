import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/common_ui/common_ui_overlays.dart';

import '../../../account/applications/user_state.dart';
import '../../../dev/application/area_state.dart';
import '../../../payment/widgets/billing_bottom_sheet.dart';
import '../../../payment/widgets/confirm_cancel_fee_dialog.dart';
import '../../../../shared/page/modify/pages/modify_plate_screen.dart';
import '../../../../shared/plate/application/common/movement_plate.dart';
import '../../../../shared/plate/application/common/parking_completed_status_helpers.dart';
import '../../../../shared/plate/application/triple/triple_plate_state.dart';
import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/models/plate_log_model.dart';
import '../../../../shared/plate/domain/models/plate_model.dart';
import '../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../../shared/plate/widgets/log_viewer_bottom_sheet.dart';
import '../../../../shared/plate/widgets/parking_completed_common_dialog.dart';
import '../../../../shared/plate/widgets/parking_completed_status_widgets.dart';
import '../../../../shared/real_time_table/real_time_table_spec.dart';

Future<bool> _showDeleteDialog(BuildContext context, PlateModel plate) async {
  return showParkingCompletedDeleteDialog(context, plate);
}

Future<void> showTripleParkingCompletedStatusSideDockFromRealtime({
  required BuildContext context,
  required RealTimePlateDetailRequest request,
}) async {
  await showParkingStatusLoadingSideDock<bool>(
    context: context,
    mode: '트리플',
    statusTitle: request.statusTitle,
    plateId: request.plateId,
    plateNumber: request.plateNumber,
    area: request.area,
    location: request.location,
    cachedPlate: request.cachedPlate,
    loadPlate: request.loadPlate,
    barrierDismissible: false,
    loadedBuilder: (dockContext, plate) {
      final division = dockContext.read<UserState>().division;
      final area = dockContext.read<AreaState>().currentArea;
      return _StatusSideDockContent(
        plate: plate,
        plateNumber: plate.plateNumber,
        division: division,
        area: area,
        onRequestEntry: (traceLog) async {
          await handleParkingCompletedEntryRequest(
            dockContext,
            plate.plateNumber,
            area,
            traceLog: traceLog,
          );
        },
        onDelete: () => _showDeleteDialog(dockContext, plate),
      );
    },
  );
}

Future<void> showTripleParkingCompletedStatusBottomSheetFromDialog({
  required BuildContext context,
  required PlateModel plate,
  bool popParentOnDelete = true,
}) async {
  final deleted = await showTripleParkingCompletedStatusBottomSheet(
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

Future<bool?> showTripleParkingCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  required Future<void> Function(MovementPlateTraceLog? traceLog) onRequestEntry,
  required Future<bool> Function() onDelete,
}) async {
  final plateNumber = plate.plateNumber;
  final division = context.read<UserState>().division;
  final area = context.read<AreaState>().currentArea;
  final plateType = plate.typeEnum;
  final statusTitle = plateType == PlateType.parkingRequests
      ? '입차 요청 상태 처리'
      : plateType == PlateType.departureRequests
          ? '출차 요청 상태 처리'
          : '입차 완료 상태 처리';

  final trace = await traceParkingStatusSectorSummary(
    context: context,
    mode: '트리플',
    statusTitle: statusTitle,
    plateNumber: plateNumber,
    area: plate.area,
    sectorId: plate.sectorId ?? '',
    sectorName: plate.sectorName ?? '',
  );
  if (!context.mounted) return null;

  trace.log(
    'presentation=right_side_dock direction=right_to_left management=left_rail footer=status_change_only plate=$plateNumber area=$area status=$statusTitle',
    progress: .16,
  );

  return showParkingStatusSideDock<bool>(
    trace: trace,
    context: context,
    barrierDismissible: false,
    builder: (_) => _StatusSideDockContent(
      plate: plate,
      plateNumber: plateNumber,
      division: division,
      area: area,
      onRequestEntry: onRequestEntry,
      onDelete: onDelete,
    ),
  );
}

class _StatusSideDockContent extends StatefulWidget {
  const _StatusSideDockContent({
    required this.plate,
    required this.plateNumber,
    required this.division,
    required this.area,
    required this.onRequestEntry,
    required this.onDelete,
  });

  final PlateModel plate;
  final String plateNumber;
  final String division;
  final String area;
  final Future<void> Function(MovementPlateTraceLog? traceLog) onRequestEntry;
  final Future<bool> Function() onDelete;

  @override
  State<_StatusSideDockContent> createState() => _StatusSideDockContentState();
}

class _StatusSideDockContentState extends State<_StatusSideDockContent> {
  late PlateModel _plate;

  final ScrollController _scrollController = ScrollController();



  bool _primaryBusy = false;
  String? _completionMessage;


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

  PlateType? get _type => _plate.typeEnum;

  bool get _isDrivingType =>
      _type == PlateType.parkingRequests ||
      _type == PlateType.departureRequests;

  ParkingCompletedBillingState get _billingState =>
      resolveParkingCompletedBillingState(
        billingType: _plate.billingType,
        isLocked: _plate.isLockedFee == true,
      );

  bool get _billingApplicable =>
      _billingState != ParkingCompletedBillingState.notApplicable;

  bool get _needsBilling =>
      (_type == PlateType.parkingCompleted) &&
      _billingState == ParkingCompletedBillingState.unsettled;

  bool get _isFreeBilling =>
      (_plate.basicAmount ?? 0) == 0 && (_plate.addAmount ?? 0) == 0;

  bool get _isMyDriving {
    final userName = (context.read<UserState>().name).trim();
    final selectedBy = (_plate.selectedBy ?? '').trim();
    final t = _type;

    return _plate.isSelected == true &&
        userName.isNotEmpty &&
        selectedBy.isNotEmpty &&
        selectedBy == userName &&
        (t == PlateType.parkingRequests || t == PlateType.departureRequests);
  }

  bool get _isOtherDriving {
    final userName = (context.read<UserState>().name).trim();
    final selectedBy = (_plate.selectedBy ?? '').trim();
    final t = _type;

    return _plate.isSelected == true &&
        userName.isNotEmpty &&
        selectedBy.isNotEmpty &&
        selectedBy != userName &&
        (t == PlateType.parkingRequests || t == PlateType.departureRequests);
  }

  bool get _drivingLocked => _isMyDriving;


  String _plateDocId() {
    return resolveParkingCompletedDocId(_plate);
  }

  String get _effectiveLocation =>
      resolveParkingCompletedEffectiveLocation(_plate);

  Future<void> _runPrimary(Future<void> Function() fn) async {
    if (_primaryBusy) return;
    setState(() => _primaryBusy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _primaryBusy = false);
    }
  }

  Future<bool> _runPrimaryBool(Future<bool> Function() fn) async {
    if (_primaryBusy) return false;
    setState(() => _primaryBusy = true);
    try {
      return await fn();
    } finally {
      if (mounted) setState(() => _primaryBusy = false);
    }
  }



  Future<bool> _autoPrebillFreeIfNeeded() async {
    if (_plate.isLockedFee == true) return true;
    if (!_isFreeBilling) return false;
    parkingStatusTraceLog(
      context,
      '무료 자동 정산 시작 plate=${_plate.plateNumber} amount=0 firebaseWrite=true',
    );

    if (_drivingLocked || _isOtherDriving) {
      return false;
    }

    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final plateState = context.read<TriplePlateState>();

    final now = DateTime.now();
    final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    final id = _plateDocId();

    final fallbackPlate = _plate.copyWith(
      isLockedFee: true,
      lockedAtTimeInSeconds: currentTime,
      lockedFeeAmount: 0,
      paymentMethod: '무료',
    );

    try {
      await repo.settlePlateBilling(
        documentId: id,
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

      final freshPlate = await repo.getPlate(id) ?? fallbackPlate;

      await plateState.tripleUpdatePlateLocally(
        PlateType.parkingCompleted,
        freshPlate,
      );

      if (!mounted) return false;
      setState(() => _plate = freshPlate);

      parkingStatusTraceLog(
        context,
        '무료 자동 정산 완료 plate=${_plate.plateNumber} amount=0 firebaseWrite=true firebaseRead=true',
      );
      return true;
    } catch (error) {
      parkingStatusTraceLog(
        context,
        '무료 자동 정산 실패 plate=${_plate.plateNumber} error=$error',
      );
      if (!mounted) return false;
      return false;
    }
  }

  Future<ParkingCompletedOverrideChoice?>
      _showDepartureOverrideDialog() async {
    return showParkingCompletedOverrideDialog(
      context: context,
      destinationLabel: '출차 요청',
    );
  }

  Future<void> _goDepartureRequested() async {
    parkingStatusTraceLog(
      context,
      '상태 변경 요청 from=${_type?.name ?? "unknown"} to=departureRequests plate=${_plate.plateNumber}',
    );
    if (_drivingLocked) return;

    if (_isOtherDriving) {
      return;
    }

    final movementPlate = context.read<MovementPlate>();

    await movementPlate.setDepartureRequested(
      _plate.plateNumber,
      _plate.area,
      _effectiveLocation,
      traceLog: (message) => parkingStatusTraceLog(context, message),
    );

    if (!mounted) return;
    parkingStatusTraceLog(
      context,
      '상태 변경 완료 to=departureRequests plate=${_plate.plateNumber}',
    );
    Navigator.pop(context);
  }

  Future<void> _goBackToParkingCompleted() async {
    parkingStatusTraceLog(
      context,
      '상태 변경 요청 to=parkingCompleted plate=${_plate.plateNumber}',
    );
    if (_drivingLocked) return;
    if (_isOtherDriving) return;

    await handleParkingCompletedBackToCompletedRequest(
      context,
      plate: _plate,
      fallbackArea: widget.area,
      traceLog: (message) => parkingStatusTraceLog(context, message),
    );

    if (!mounted) return;
    parkingStatusTraceLog(
      context,
      '상태 변경 완료 to=parkingCompleted plate=${_plate.plateNumber}',
    );
    Navigator.pop(context);
  }

  Future<void> _skipDepartureDrivingToCompleted() async {
    if (_drivingLocked) return;
    await _runPrimary(() async {
      if (_type != PlateType.departureRequests) {
        return;
      }

      final userName = context.read<UserState>().name;
      final selectedBy = (_plate.selectedBy ?? '').trim();

      if (_plate.isSelected == true &&
          selectedBy.isNotEmpty &&
          selectedBy != userName) {
        return;
      }

      final movementPlate = context.read<MovementPlate>();

      try {
        parkingStatusTraceLog(
          context,
          '상태 변경 시작 mode=skip from=departureRequests to=departureCompleted plate=${_plate.plateNumber}',
        );
        await movementPlate.setDepartureCompleted(
          _plate,
          traceLog: (message) => parkingStatusTraceLog(context, message),
        );

        if (!mounted) return;
        parkingStatusTraceLog(
          context,
          '상태 변경 완료 mode=skip from=departureRequests to=departureCompleted plate=${_plate.plateNumber}',
        );

        setState(() {
          _plate = _plate.copyWith(isSelected: false, selectedBy: null);
        });

        Navigator.pop(context);
      } catch (_) {
        return;
      }
    });
  }

  Future<void> _showCompletionFeedback(String message) async {
    if (!mounted) return;

    setState(() {
      _completionMessage = message;
    });

    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduceMotion) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }
  }

  Future<void> _logDrivingCancel({
    required String plateId,
    required String phase,
    required String userName,
  }) async {
    final repo = context.read<PlateRepository>();
    final now = DateTime.now();
    final cancelLog = {
      'action': '주행 취소',
      'performedBy': userName,
      'timestamp': now.toIso8601String(),
      'phase': phase,
    };

    await repo.appendPlateLog(
      plateId: plateId,
      log: cancelLog,
    );
  }

  Future<bool> _engageDrivingByGear() async {
    return _runPrimaryBool(() async {
      final t = _type;
      if (t != PlateType.parkingRequests && t != PlateType.departureRequests) {
        return false;
      }

      final userName = context.read<UserState>().name.trim();
      final selectedBy = (_plate.selectedBy ?? '').trim();

      if (_plate.isSelected == true &&
          selectedBy.isNotEmpty &&
          selectedBy != userName) {
        return false;
      }

      final repo = context.read<PlateRepository>();
      final id = _plateDocId();

      final alreadySelectedByMe =
          (_plate.isSelected == true) && (selectedBy == userName);

      try {
        if (!alreadySelectedByMe) {
          await repo.recordWhoPlateClick(
            id,
            true,
            selectedBy: userName,
            area: _plate.area,
          );
        }

        if (!mounted) return false;

        setState(() {
          _plate = _plate.copyWith(isSelected: true, selectedBy: userName);
        });

        try {
          HapticFeedback.mediumImpact();
        } catch (_) {}

        return true;
      } catch (_) {
        return false;
      }
    });
  }

  Future<void> _completeDrivingByGear() async {
    await _runPrimary(() async {
      if (!_drivingLocked || !_isDrivingType) {
        return;
      }

      final movementPlate = context.read<MovementPlate>();
      final isEntry = _type == PlateType.parkingRequests;

      try {
        parkingStatusTraceLog(
          context,
          '상태 변경 시작 driving=true from=${_type?.name ?? "unknown"} plate=${_plate.plateNumber}',
        );
        if (isEntry) {
          await movementPlate.setParkingCompleted(
            _plate.plateNumber,
            _plate.area,
            _effectiveLocation,
            traceLog: (message) => parkingStatusTraceLog(context, message),
          );
        } else if (_type == PlateType.departureRequests) {
          await movementPlate.setDepartureCompleted(
          _plate,
          traceLog: (message) => parkingStatusTraceLog(context, message),
        );
        }

        if (!mounted) return;
        parkingStatusTraceLog(
          context,
          '상태 변경 완료 driving=true to=${isEntry ? "parkingCompleted" : "departureCompleted"} plate=${_plate.plateNumber}',
        );
        await _showCompletionFeedback(isEntry ? '입차 완료' : '출차 완료');
        if (!mounted) return;
        Navigator.pop(context);
      } catch (_) {
        return;
      }
    });
  }

  Future<void> _cancelDrivingByGear() async {
    await _runPrimary(() async {
      if (!_drivingLocked || !_isDrivingType) {
        return;
      }

      final userName = context.read<UserState>().name.trim();
      final currentSelectedBy = (_plate.selectedBy ?? '').trim();
      if (currentSelectedBy != userName) {
        return;
      }

      final repo = context.read<PlateRepository>();
      final plateState = context.read<TriplePlateState>();
      final id = _plateDocId();

      try {
        await repo.recordWhoPlateClick(
          id,
          false,
          area: _plate.area,
        );

        await _logDrivingCancel(
          plateId: id,
          phase: (_type == PlateType.parkingRequests) ? '입차' : '출차',
          userName: userName,
        );

        final updated = _plate.copyWith(isSelected: false, selectedBy: null);
        if (mounted) {
          setState(() {
            _plate = updated;
          });
        }

        try {
          await plateState.tripleUpdatePlateLocally(
            _type!,
            updated,
          );
        } catch (_) {}

        try {
          HapticFeedback.selectionClick();
        } catch (_) {}
      } catch (_) {
        return;
      }
    });
  }

  Future<ParkingStatusDirectionalGearActionResult> _performPrebill() async {
    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final plateState = context.read<TriplePlateState>();

    final bt = (_plate.billingType ?? '').trim();
    if (bt.isEmpty) {
      parkingStatusTraceLog(
        context,
        '사전 정산 중단 reason=billingType_empty plate=${_plate.plateNumber}',
      );
      return ParkingStatusDirectionalGearActionResult.blocked;
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
    if (result == null) {
      parkingStatusTraceLog(
        context,
        '사전 정산 취소 reason=user_cancel plate=${_plate.plateNumber}',
      );
      return ParkingStatusDirectionalGearActionResult.cancelled;
    }

    final id = _plateDocId();
    final fallbackPlate = _plate.copyWith(
      isLockedFee: true,
      lockedAtTimeInSeconds: currentTime,
      lockedFeeAmount: result.lockedFee,
      paymentMethod: result.paymentMethod,
    );

    try {
      await repo.settlePlateBilling(
        documentId: id,
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
      reportParkingCompletedDbSafe(
        area: _plate.area,
        action: 'write',
        source: 'parkingCompletedStatus.prebill.repo.settlePlateBilling',
        n: 1,
      );

      final freshPlate = await repo.getPlate(id) ?? fallbackPlate;

      await plateState.tripleUpdatePlateLocally(
        PlateType.parkingCompleted,
        freshPlate,
      );

      if (!mounted) {
        return ParkingStatusDirectionalGearActionResult.completed;
      }
      setState(() => _plate = freshPlate);
      parkingStatusTraceLog(
        context,
        'billing_state_transition from=unsettled to=settled plate=${freshPlate.plateNumber}',
      );
      parkingStatusTraceLog(
        context,
        '사전 정산 완료 plate=${freshPlate.plateNumber} amount=${result.lockedFee} payment=${result.paymentMethod} firebaseWrite=true firebaseRead=true',
      );
      return ParkingStatusDirectionalGearActionResult.completed;
    } catch (error) {
      parkingStatusTraceLog(
        context,
        '사전 정산 실패 plate=${_plate.plateNumber} error=$error',
      );
      return ParkingStatusDirectionalGearActionResult.failed;
    }
  }

  Future<void> _handlePrebill() async {
    if (!_billingApplicable) {
      parkingStatusTraceLog(
        context,
        'billing_action=blocked reason=not_applicable plate=${_plate.plateNumber}',
      );
      return;
    }
    parkingStatusTraceLog(
      context,
      '사전 정산 요청 plate=${_plate.plateNumber}',
    );
    if (_drivingLocked || _isOtherDriving) return;

    await _runPrimary(() async {
      await _performPrebill();
    });
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
      '사전 정산 취소 요청 plate=${_plate.plateNumber}',
    );
    if (_drivingLocked) return;

    if (_isOtherDriving) {
      return;
    }

    await _runPrimary(() async {
      final userName = context.read<UserState>().name;
      final repo = context.read<PlateRepository>();
      final plateState = context.read<TriplePlateState>();

      if (_plate.isLockedFee != true) {
        parkingStatusTraceLog(
          context,
          '사전 정산 취소 중단 reason=not_locked plate=${_plate.plateNumber}',
        );
        return;
      }

      final confirm = await showCommonOverlayDialog<bool>(
        context: context,
        builder: (_) => const ConfirmCancelFeeDialog(),
      );
      if (confirm != true) {
        parkingStatusTraceLog(
          context,
          '사전 정산 취소 중단 reason=user_cancel plate=${_plate.plateNumber}',
        );
        return;
      }

      final now = DateTime.now();
      final id = _plateDocId();
      final fallbackPlate = _plate.copyWith(
        isLockedFee: false,
        lockedAtTimeInSeconds: null,
        lockedFeeAmount: null,
        paymentMethod: null,
      );

      try {
        await repo.cancelPlateBilling(
          documentId: id,
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
          ),
        );
        reportParkingCompletedDbSafe(
          area: _plate.area,
          action: 'write',
          source: 'parkingCompletedStatus.unlock.repo.cancelPlateBilling',
          n: 1,
        );

        final freshPlate = await repo.getPlate(id) ?? fallbackPlate;

        await plateState.tripleUpdatePlateLocally(
          PlateType.parkingCompleted,
          freshPlate,
        );

        if (!mounted) return;

        setState(() => _plate = freshPlate);
          parkingStatusTraceLog(
          context,
          'billing_state_transition from=settled to=unsettled plate=${_plate.plateNumber}',
        );
        parkingStatusTraceLog(
          context,
          '사전 정산 취소 완료 plate=${_plate.plateNumber} firebaseWrite=true firebaseRead=true',
        );
      } catch (error) {
        parkingStatusTraceLog(
          context,
          '사전 정산 취소 실패 plate=${_plate.plateNumber} error=$error',
        );
        if (!mounted) return;
        return;
      }
    });
  }

  void _tryClose() {
    if (_drivingLocked) {
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    Future<ParkingStatusDirectionalGearActionResult> Function()
        primaryOnPressed = () async {
      if (_drivingLocked || _isOtherDriving) {
        parkingStatusTraceLog(
          context,
          'departure_request_gate=blocked_driving plate=${_plate.plateNumber}',
        );
        return ParkingStatusDirectionalGearActionResult.blocked;
      }

      var result = ParkingStatusDirectionalGearActionResult.blocked;
      await _runPrimary(() async {
        if (_needsBilling) {
          if (_isFreeBilling) {
            parkingStatusTraceLog(
              context,
              'departure_request_gate=billing_free_auto plate=${_plate.plateNumber}',
            );
            final ok = await _autoPrebillFreeIfNeeded();
            if (!ok) {
              parkingStatusTraceLog(
                context,
                'departure_request_gate=billing_free_auto_result success=false plate=${_plate.plateNumber}',
              );
              result = ParkingStatusDirectionalGearActionResult.blocked;
              return;
            }
            parkingStatusTraceLog(
              context,
              'departure_request_gate=billing_free_auto_result success=true plate=${_plate.plateNumber}',
            );
            await _goDepartureRequested();
            result = ParkingStatusDirectionalGearActionResult.completed;
            return;
          }

          parkingStatusTraceLog(
            context,
            'departure_request_gate=billing_unsettled dialog=shown plate=${_plate.plateNumber}',
          );
          final choice = await _showDepartureOverrideDialog();
          if (!mounted) {
            result = ParkingStatusDirectionalGearActionResult.cancelled;
            return;
          }

          if (choice == ParkingCompletedOverrideChoice.proceed) {
            parkingStatusTraceLog(
              context,
              'departure_request_gate=override_choice choice=proceed plate=${_plate.plateNumber}',
            );
            await _goDepartureRequested();
            result = ParkingStatusDirectionalGearActionResult.completed;
            return;
          }

          if (choice == ParkingCompletedOverrideChoice.goBilling) {
            parkingStatusTraceLog(
              context,
              'departure_request_gate=override_choice choice=go_billing plate=${_plate.plateNumber}',
            );
            parkingStatusTraceLog(
              context,
              'departure_request_gate=billing_open source=override plate=${_plate.plateNumber}',
            );
            final billingResult = await _performPrebill();
            if (!mounted) {
              result = ParkingStatusDirectionalGearActionResult.cancelled;
              return;
            }
            parkingStatusTraceLog(
              context,
              'departure_request_gate=billing_result result=${billingResult.name} plate=${_plate.plateNumber}',
            );
            if (billingResult ==
                ParkingStatusDirectionalGearActionResult.completed) {
              parkingStatusTraceLog(
                context,
                'departure_request_gate=billing_continue target=departure_requests plate=${_plate.plateNumber}',
              );
              await _goDepartureRequested();
              result = ParkingStatusDirectionalGearActionResult.completed;
              return;
            }
            result = billingResult;
            return;
          }

          parkingStatusTraceLog(
            context,
            'departure_request_gate=override_choice choice=cancel plate=${_plate.plateNumber}',
          );
          result = ParkingStatusDirectionalGearActionResult.cancelled;
          return;
        }

        parkingStatusTraceLog(
          context,
          'departure_request_gate=billing_ready plate=${_plate.plateNumber}',
        );
        await _goDepartureRequested();
        result = ParkingStatusDirectionalGearActionResult.completed;
      });
      return result;
    };

    final bool isDrivingPrimary = (_type == PlateType.parkingRequests ||
        _type == PlateType.departureRequests);
    final bool disableOthers = _drivingLocked;

    ParkingStatusDirectionalGearAction? lowerLeftAction;
    ParkingStatusDirectionalGearAction? lowerRightAction;

    if (_type == PlateType.parkingCompleted) {
      lowerLeftAction = ParkingStatusDirectionalGearAction(
        label: '입차 요청',
        debugAction: 'rollback_parking_request',
        icon: Icons.undo_rounded,
        tone: ParkingStatusDirectionalGearTone.warning,
        onConfirm: () async {
          if (_isOtherDriving) return;
          parkingStatusTraceLog(
            context,
            '상태 변경 요청 to=parkingRequests plate=${_plate.plateNumber}',
          );
          try {
            await widget.onRequestEntry(
              (message) => parkingStatusTraceLog(context, message),
            );
            if (!mounted) return;
            parkingStatusTraceLog(
              context,
              '상태 변경 완료 to=parkingRequests plate=${_plate.plateNumber}',
            );
            Navigator.pop(context);
          } catch (error) {
            parkingStatusTraceLog(
              context,
              '상태 변경 실패 to=parkingRequests plate=${_plate.plateNumber} error=$error',
            );
          }
        },
      );
      lowerRightAction = ParkingStatusDirectionalGearAction(
        label: '출차 요청',
        debugAction: 'advance_departure_request',
        icon: Icons.local_shipping_outlined,
        onConfirmResult: primaryOnPressed,
      );
    } else if (_type == PlateType.departureRequests) {
      lowerLeftAction = ParkingStatusDirectionalGearAction(
        label: '입차 완료',
        debugAction: 'rollback_parking_completed',
        icon: Icons.undo_rounded,
        tone: ParkingStatusDirectionalGearTone.warning,
        onConfirm: _goBackToParkingCompleted,
      );
      lowerRightAction = ParkingStatusDirectionalGearAction(
        label: '출차 완료',
        debugAction: 'skip_departure_to_completed',
        icon: Icons.skip_next_rounded,
        onConfirm: _skipDepartureDrivingToCompleted,
      );
    }

    final upperDownAction = isDrivingPrimary
        ? ParkingStatusDirectionalGearAction(
            label: '주행 취소',
            debugAction: 'driving_cancel',
            icon: Icons.keyboard_arrow_down_rounded,
            tone: ParkingStatusDirectionalGearTone.warning,
            onConfirm: _cancelDrivingByGear,
          )
        : null;
    final upperRightAction = isDrivingPrimary
        ? ParkingStatusDirectionalGearAction(
            label: '주행 완료',
            debugAction: 'driving_complete',
            icon: Icons.check_rounded,
            onConfirm: _completeDrivingByGear,
          )
        : null;

    final String sheetTitle = () {
      if (_type == PlateType.parkingRequests) return '입차 요청 상태 처리';
      if (_type == PlateType.departureRequests) return '출차 요청 상태 처리';
      return '입차 완료 상태 처리';
    }();

    final sheet = ParkingStatusSideDockFrame(
      title: widget.plateNumber,
      subtitle: parkingStatusHeaderSubtitle(
        statusTitle: sheetTitle,
        sectorId: _plate.sectorId,
        sectorName: _plate.sectorName,
      ),
      icon: Icons.directions_car_filled_rounded,
      closeEnabled: !disableOthers,
      onClose: _tryClose,
      leadingRail: ParkingStatusManagementRail(
        debugTarget: sheetTitle,
        actions: [
          ParkingStatusManagementAction(
            icon: Icons.history,
            label: '로그 확인',
            displayLabel: '로그',
            debugAction: 'history',
            enabled: !_primaryBusy && !disableOthers,
            onPressed: () async {
              await LogViewerBottomSheet.show(
                context,
                initialPlateNumber: widget.plateNumber,
                division: widget.division,
                area: widget.area,
                requestTime: _plate.requestTime,
                plateId: _plate.id.trim().isEmpty ? null : _plate.id.trim(),
              );
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
              enabled: !_primaryBusy && !disableOthers && !_isOtherDriving,
              onPressed: () async {
                if (_billingState == ParkingCompletedBillingState.settled) {
                  await _handleCancelPrebill();
                  return;
                }
                await _handlePrebill();
              },
            ),
          ParkingStatusManagementAction(
            icon: Icons.edit_note_outlined,
            label: '정보 수정',
            displayLabel: '수정',
            debugAction: 'edit',
            enabled: !_primaryBusy && !disableOthers && !_isOtherDriving,
            onPressed: () async {
              if (_isOtherDriving) return;
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
            enabled: !_primaryBusy && !disableOthers && !_isOtherDriving,
            onPressed: () async {
              if (_isOtherDriving) return;
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
        debugTarget: sheetTitle,
        child: ParkingStatusDirectionalGear(
          debugTarget: sheetTitle,
          enabled: !_primaryBusy && !_isOtherDriving,
          busy: _primaryBusy,
          driving: _drivingLocked,
          blocked: _isOtherDriving && !_drivingLocked,
          blockedBy: (_plate.selectedBy ?? '').trim(),
          onStartDriving: isDrivingPrimary ? _engageDrivingByGear : null,
          lowerLeft: lowerLeftAction,
          lowerRight: lowerRightAction,
          upperDown: upperDownAction,
          upperRight: upperRightAction,
          startLabel: _type == PlateType.departureRequests ? '출차 주행' : '입차 주행',
        ),
      ),
      child: ParkingStatusAdaptiveRequestBody(
        plate: _plate,
        area: widget.area,
        debugTarget: sheetTitle,
        scrollController: _scrollController,
        leading: [
          if (_drivingLocked)
            _DrivingLockBanner(
              selectedBy: (_plate.selectedBy ?? '').trim(),
              phase: (_type == PlateType.parkingRequests) ? '입차' : '출차',
            )
          else if (_isOtherDriving)
            _OtherDrivingBanner(
              selectedBy: (_plate.selectedBy ?? '').trim(),
              phase: (_type == PlateType.parkingRequests) ? '입차' : '출차',
            ),
        ],
      ),
    );

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Stack(
      alignment: Alignment.center,
      children: [
        sheet,
        Positioned.fill(
          child: AbsorbPointer(
            absorbing: _completionMessage != null,
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              reverseDuration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final scale = Tween<double>(begin: 0.94, end: 1).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                );
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: scale, child: child),
                );
              },
              child: _completionMessage == null
                  ? const SizedBox.shrink(
                      key: ValueKey<String>('completion-empty'),
                    )
                  : _DrivingCompletionOverlay(
                      key: ValueKey<String>(_completionMessage!),
                      colorScheme: cs,
                      message: _completionMessage!,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DrivingCompletionOverlay extends StatelessWidget {
  const _DrivingCompletionOverlay({
    super.key,
    required this.colorScheme,
    required this.message,
  });

  final ColorScheme colorScheme;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colorScheme.scrim.withOpacity(0.34),
      child: Center(
        child: Semantics(
          liveRegion: true,
          label: message,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.primary.withOpacity(0.36),
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    color: colorScheme.onPrimaryContainer,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '상태 변경이 완료되었습니다.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrivingLockBanner extends StatelessWidget {
  const _DrivingLockBanner({
    required this.selectedBy,
    required this.phase,
  });

  final String selectedBy;
  final String phase;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final who = selectedBy.isEmpty ? '나' : selectedBy;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primary.withOpacity(0.22)),
            ),
            child: Icon(Icons.lock, size: 20, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$phase 주행 중 · 화면 잠금',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '선점자: $who · 뒤로가기/닫기 불가\n상태 변경 기어에서 아래로 취소, 오른쪽으로 완료를 선택합니다.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OtherDrivingBanner extends StatelessWidget {
  const _OtherDrivingBanner({
    required this.selectedBy,
    required this.phase,
  });

  final String selectedBy;
  final String phase;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final who = selectedBy.isEmpty ? '알 수 없음' : selectedBy;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
            ),
            child: Icon(Icons.directions_car_filled,
                size: 20, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$phase 주행 진행 중(타 사용자)',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '선점자: $who · 주행 시작 제스처가 비활성화됩니다.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
