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
import '../../../../shared/plate/application/minor/minor_plate_state.dart';
import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/models/plate_log_model.dart';
import '../../../../shared/plate/domain/models/plate_model.dart';
import '../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../../shared/plate/widgets/plate_log_side_dock.dart';
import '../../../../shared/plate/widgets/parking_completed_common_dialog.dart';
import '../../../../shared/plate/widgets/parking_completed_status_widgets.dart';
import '../../../../shared/real_time_table/real_time_table_spec.dart';
import '../../../../shared/plate/editor/dialogs/plate_parking_picker_dialog.dart';

Future<bool> _showDeleteDialog(BuildContext context, PlateModel plate) async {
  return showParkingCompletedDeleteDialog(context, plate);
}

Future<void> showMinorParkingCompletedStatusSideDockFromRealtime({
  required BuildContext context,
  required RealTimePlateDetailRequest request,
}) async {
  PlateLogSideDockRequest? logRequest;
  PlateBillingSideDockRequest? billingRequest;
  PlateModel? modifyRequest;
  await showParkingStatusLoadingSideDock<bool>(
    context: context,
    mode: '마이너',
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
        await showMinorParkingCompletedStatusBottomSheet(
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

      final requestedModify = modifyRequest;
      if (requestedModify != null && context.mounted) {
        trace.log(
          'realtime_status_modify_handoff sourceDock=parking_status targetDock=modify_plate handoffPolicy=close_then_open overlayStacking=false plate=${requestedModify.plateNumber}',
          progress: .78,
        );
        final modifiedPlate = await showModifyPlateSideDock(
          context: context,
          plate: requestedModify,
          collectionKey: PlateType.parkingCompleted,
          isMinorMode: true,
        );
        if (!context.mounted) return;
        final reopenPlate = modifiedPlate ?? requestedModify;
        trace.log(
          'realtime_status_modify_return targetDock=parking_status saved=${modifiedPlate != null} plate=${reopenPlate.plateNumber}',
          progress: .9,
        );
        await trace.succeed('실시간 상태 처리에서 정보 수정 후 상태 Side Dock을 다시 엽니다.');
        if (!context.mounted) return;
        await showMinorParkingCompletedStatusBottomSheet(
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
    barrierDismissible: false,
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
        onModifyRequested: (value) {
          modifyRequest = value;
        },
      );
    },
  );
}

Future<void> showMinorParkingCompletedStatusBottomSheetFromDialog({
  required BuildContext context,
  required PlateModel plate,
  bool popParentOnDelete = true,
}) async {
  final deleted = await showMinorParkingCompletedStatusBottomSheet(
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

Future<bool?> showMinorParkingCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  required Future<void> Function(MovementPlateTraceLog? traceLog) onRequestEntry,
  required Future<bool> Function() onDelete,
}) async {
  final division = context.read<UserState>().division;
  final area = context.read<AreaState>().currentArea;
  var currentPlate = plate;
  final initialStatusTitle = plate.typeEnum == PlateType.parkingRequests ? '입차 요청 상태 처리' : plate.typeEnum == PlateType.departureRequests ? '출차 요청 상태 처리' : '입차 완료 상태 처리';

  final trace = await traceParkingStatusSectorSummary(
    context: context,
    mode: '마이너',
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
    PlateModel? modifyRequest;
    final currentStatusTitle = currentPlate.typeEnum == PlateType.parkingRequests ? '입차 요청 상태 처리' : currentPlate.typeEnum == PlateType.departureRequests ? '출차 요청 상태 처리' : '입차 완료 상태 처리';
    final result = await showParkingStatusSideDock<bool>(
      trace: trace,
      context: context,
      finalizeTrace: false,
      barrierDismissible: false,
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
        onModifyRequested: (value) {
          modifyRequest = value;
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

    final requestedModify = modifyRequest;
    if (requestedModify != null && context.mounted) {
      trace.log(
        'status_modify_handoff sourceDock=parking_status targetDock=modify_plate handoffPolicy=close_then_open overlayStacking=false plate=${requestedModify.plateNumber} status=$currentStatusTitle',
        progress: .78,
      );
      final modifiedPlate = await showModifyPlateSideDock(
        context: context,
        plate: requestedModify,
        collectionKey: PlateType.parkingCompleted,
        isMinorMode: true,
      );
      if (!context.mounted) return result;
      currentPlate = modifiedPlate ?? requestedModify;
      trace.log(
        'status_modify_return targetDock=parking_status saved=${modifiedPlate != null} plate=${currentPlate.plateNumber}',
        progress: .9,
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
    required this.onModifyRequested,
  });

  final PlateModel plate;
  final String plateNumber;
  final String division;
  final String area;
  final Future<void> Function(MovementPlateTraceLog? traceLog) onRequestEntry;
  final Future<bool> Function() onDelete;
  final ValueChanged<PlateLogSideDockRequest> onLogRequested;
  final ValueChanged<PlateBillingSideDockRequest> onBillingRequested;
  final ValueChanged<PlateModel> onModifyRequested;

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
        'bypass=${_billingState == ParkingCompletedBillingState.notApplicable} monthlyBillingLocked=$_monthlyBillingLocked',
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

  bool get _monthlyBillingLocked =>
      (_plate.billingPlanType ?? '').trim() == '정기';

  bool get _needsBilling =>
      !_monthlyBillingLocked &&
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
        selectedBy.isNotEmpty &&
        userName.isNotEmpty &&
        selectedBy != userName &&
        (t == PlateType.parkingRequests || t == PlateType.departureRequests);
  }

  bool get _drivingLocked => _isMyDriving;


  String _plateDocId() {
    if (_plate.id.trim().isNotEmpty) return _plate.id.trim();
    return '${_plate.plateNumber}_${_plate.area}';
  }

  String get _effectiveLocation =>
      resolveParkingCompletedEffectiveLocation(_plate);

  String get _phaseLabel {
    if (_type == PlateType.parkingRequests) return '입차';
    if (_type == PlateType.departureRequests) return '출차';
    return '입차';
  }

  String get _sheetTitle {
    if (_type == PlateType.parkingRequests) return '입차 요청 상태 처리';
    if (_type == PlateType.departureRequests) return '출차 요청 상태 처리';
    return '입차 완료 상태 처리';
  }

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



  void _tryCloseSheet() {
    if (_drivingLocked) {
      return;
    }
    if (_primaryBusy) return;
    Navigator.of(context).pop();
  }

  Future<bool> _autoPrebillFreeIfNeeded() async {
    if (_monthlyBillingLocked) {
      parkingStatusTraceLog(
        context,
        'billing_action=blocked reason=monthly_parking action=free_auto plate=${_plate.plateNumber}',
      );
      return true;
    }
    if (_plate.isLockedFee == true) return true;
    if (!_isFreeBilling) return false;
    parkingStatusTraceLog(
      context,
      '무료 자동 정산 시작 plate=${_plate.plateNumber} amount=0 firebaseWrite=true',
    );

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

    try {
      await repo.settlePlateBilling(
        documentId: _plate.id,
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

      final refreshedPlate = await repo.getPlate(_plate.id) ?? updatedPlate;

      await plateState.minorUpdatePlateLocally(
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
      '상태 변경 시작 from=${_type?.name ?? "unknown"} to=departureRequests plate=${_plate.plateNumber}',
    );
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
    if (_drivingLocked) {
      return;
    }

    if (_isOtherDriving) {
      return;
    }

    await handleParkingCompletedBackToCompletedRequest(
      context,
      plate: _plate,
      fallbackArea: _resolveAreaForCache(),
      traceLog: (message) => parkingStatusTraceLog(context, message),
    );

    if (!mounted) return;
    parkingStatusTraceLog(
      context,
      '상태 변경 완료 to=parkingCompleted plate=${_plate.plateNumber}',
    );
    Navigator.pop(context);
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
    await repo.appendPlateLog(
      plateId: plateId,
      log: <String, dynamic>{
        'action': '주행 취소',
        'performedBy': userName,
        'timestamp': now.toIso8601String(),
        'phase': phase,
      },
    );
  }

  List<String> _platePreferredParkingAreas() {
    final out = <String>[];
    final seen = <String>{};

    void add(String? raw) {
      final value = (raw ?? '').trim();
      if (value.isEmpty) return;
      if (seen.add(value)) out.add(value);
    }

    add(_plate.parkingPriority1SlotKey);
    add(_plate.parkingPriority2SlotKey);
    add(_plate.parkingPriority3SlotKey);

    return out;
  }

  Future<String?> _pickParkingLocationViaEditor({
    required String area,
    required String source,
  }) async {
    parkingStatusTraceLog(
      context,
      'parking_picker=request source=$source plate=${_plate.plateNumber} area=$area currentLocation=${_plate.location.trim()}',
    );
    try {
      var invalidAreaConfiguration = false;
      final picked = await showPlateParkingPickerDialog(
        context: context,
        currentLocation: _plate.location.trim(),
        preferredParkingAreas: _platePreferredParkingAreas(),
        areaOverride: area,
        onDebug: (message) => parkingStatusTraceLog(context, message),
        onInvalidAreaConfiguration: () {
          invalidAreaConfiguration = true;
          parkingStatusTraceLog(
            context,
            'parking_configuration=invalid source=$source reason=mixed_location_types action=close_status_side_dock plate=${_plate.plateNumber} area=$area',
          );
          if (mounted) {
            Navigator.of(context).pop();
          }
        },
      );
      if (invalidAreaConfiguration) {
        return null;
      }
      if (!mounted) return null;
      if (picked == null || picked.trim().isEmpty) {
        parkingStatusTraceLog(
          context,
          'parking_picker=result source=$source result=cancelled plate=${_plate.plateNumber}',
        );
        return null;
      }
      parkingStatusTraceLog(
        context,
        'parking_picker=result source=$source result=selected plate=${_plate.plateNumber} location=${picked.trim()}',
      );
      return picked.trim();
    } catch (error, stackTrace) {
      parkingStatusTraceLog(
        context,
        'parking_picker=result source=$source result=failed plate=${_plate.plateNumber} error=$error',
      );
      parkingStatusTraceLog(
        context,
        'parking_picker=stack_trace source=$source $stackTrace',
      );
      final trace = parkingStatusTraceOf(context);
      if (trace != null && trace.developerMode && mounted) {
        await trace.showSnapshotStatusDialog(
          context,
          title: '주차 위치 선택 실패',
          description: '주차 위치 선택 과정에서 오류가 발생했습니다.',
          failure: true,
        );
      }
      if (mounted) {
        showFailedSnackbar(
          context,
          '주차 위치를 불러오지 못했습니다.',
          useCommonUi: true,
        );
      }
      return null;
    }
  }

  Future<ParkingStatusDirectionalGearActionResult> _performPrebill({
    bool continueDepartureAfterSuccess = false,
  }) async {
    if (_monthlyBillingLocked) {
      parkingStatusTraceLog(
        context,
        'billing_action=blocked reason=monthly_parking action=settle plate=${_plate.plateNumber}',
      );
      return ParkingStatusDirectionalGearActionResult.blocked;
    }
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
    final plateState = context.read<MinorPlateState>();
    final movementPlate = continueDepartureAfterSuccess
        ? context.read<MovementPlate>()
        : null;
    final effectiveLocation = _effectiveLocation;
    final documentId = plateSnapshot.id.trim().isNotEmpty ? plateSnapshot.id.trim() : resolveParkingCompletedDocId(plateSnapshot);
    final request = PlateBillingSideDockRequest(
      plate: plateSnapshot,
      source: 'minor_parking_completed_status',
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
        await plateState.minorUpdatePlateLocally(
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
    if (_drivingLocked) return;

    await _runPrimary(() async {
      await _performPrebill();
    });
  }

  Future<void> _handleUnlockPrebill() async {
    if (_monthlyBillingLocked) {
      parkingStatusTraceLog(
        context,
        'billing_action=blocked reason=monthly_parking action=cancel plate=${_plate.plateNumber}',
      );
      return;
    }
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

    await _runPrimary(() async {
      final trace = parkingStatusTraceOf(context);
      final userName = context.read<UserState>().name;
      final repo = context.read<PlateRepository>();
      final plateState = context.read<MinorPlateState>();

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
      final documentId = _plate.id;
      final updatedPlate = _plate.copyWith(
        isLockedFee: false,
        lockedAtTimeInSeconds: null,
        lockedFeeAmount: null,
        paymentMethod: null,
      );
      parkingStatusTraceLog(
        context,
        'billing_cancel_persist_started plate=${_plate.plateNumber} documentId=$documentId lockedFee=$cancelledFee payment=${cancelledPayment.isEmpty ? "unrecorded" : cancelledPayment}',
        progress: .56,
      );

      try {
        await repo.cancelPlateBilling(
          documentId: documentId,
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

        final refreshedPlate = await repo.getPlate(documentId) ?? updatedPlate;

        await plateState.minorUpdatePlateLocally(
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
        parkingStatusTraceLog(
          context,
          'billing_cancel_stacktrace $stackTrace',
        );
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
    });
  }

  Future<bool> _engageDriving({
    required PlateType expectedType,
    required String phaseLabel,
  }) async {
    return _runPrimaryBool(() async {
      if (_type != expectedType) {
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
      final plateState = context.read<MinorPlateState>();
      final id = _plateDocId();

      final alreadySelectedByMe =
          (_plate.isSelected == true) && (selectedBy.trim() == userName.trim());

      try {
        if (!alreadySelectedByMe) {
          await repo.recordWhoPlateClick(
            id,
            true,
            selectedBy: userName,
            area: _plate.area,
          );
        }

        final updated = _plate.copyWith(isSelected: true, selectedBy: userName);
        if (!mounted) return false;
        setState(() => _plate = updated);

        try {
          await plateState.minorUpdatePlateLocally(expectedType, updated);
        } catch (_) {}

        return true;
      } catch (_) {
        return false;
      }
    });
  }

  Future<void> _cancelDriving({
    required PlateType expectedType,
    required String phaseLabel,
  }) async {
    await _runPrimary(() async {
      if (_type != expectedType) {
        return;
      }

      final userName = context.read<UserState>().name.trim();
      final selectedBy = (_plate.selectedBy ?? '').trim();
      if (selectedBy != userName || _plate.isSelected != true) {
        return;
      }

      final repo = context.read<PlateRepository>();
      final plateState = context.read<MinorPlateState>();
      final id = _plateDocId();

      try {
        await repo.recordWhoPlateClick(
          id,
          false,
          area: _plate.area,
        );

        await _logDrivingCancel(
          plateId: id,
          phase: phaseLabel,
          userName: userName,
        );

        final updated = _plate.copyWith(isSelected: false, selectedBy: null);
        if (mounted) setState(() => _plate = updated);

        try {
          await plateState.minorUpdatePlateLocally(expectedType, updated);
        } catch (_) {}
      } catch (_) {
        return;
      }
    });
  }

  Future<bool> _engageEntryDriving() async {
    return _engageDriving(
      expectedType: PlateType.parkingRequests,
      phaseLabel: '입차',
    );
  }

  Future<bool> _engageDepartureDriving() async {
    return _engageDriving(
      expectedType: PlateType.departureRequests,
      phaseLabel: '출차',
    );
  }

  Future<void> _cancelEntryDriving() async {
    await _cancelDriving(
      expectedType: PlateType.parkingRequests,
      phaseLabel: '입차',
    );
  }

  Future<void> _cancelDepartureDriving() async {
    await _cancelDriving(
      expectedType: PlateType.departureRequests,
      phaseLabel: '출차',
    );
  }

  String _resolveAreaForCache() {
    final a = _plate.area.trim();
    if (a.isNotEmpty) return a;

    final wa = widget.area.trim();
    if (wa.isNotEmpty) return wa;

    return context.read<AreaState>().currentArea.trim();
  }

  Future<void> _completeEntryDriving() async {
    await _runPrimary(() async {
      if (_type != PlateType.parkingRequests) {
        return;
      }

      final userName = context.read<UserState>().name.trim();
      final selectedBy = (_plate.selectedBy ?? '').trim();
      if (selectedBy != userName || _plate.isSelected != true) {
        return;
      }

      final movementPlate = context.read<MovementPlate>();
      final area = _resolveAreaForCache();

      final picked = await _pickParkingLocationViaEditor(
        area: area,
        source: 'driving_complete',
      );

      if (picked == null || picked.trim().isEmpty) {
        return;
      }

      try {
        parkingStatusTraceLog(
          context,
          '상태 변경 시작 from=parkingRequests to=parkingCompleted plate=${_plate.plateNumber}',
        );
        await movementPlate.setParkingCompleted(
          _plate.plateNumber,
          area,
          picked,
          traceLog: (message) => parkingStatusTraceLog(context, message),
        );
      } catch (error, stackTrace) {
        parkingStatusTraceLog(
          context,
          '상태 변경 실패 from=parkingRequests to=parkingCompleted plate=${_plate.plateNumber} error=$error',
        );
        parkingStatusTraceLog(context, '상태 변경 stack_trace $stackTrace');
        final trace = parkingStatusTraceOf(context);
        if (trace != null && trace.developerMode && mounted) {
          await trace.showSnapshotStatusDialog(
            context,
            title: '입차 완료 실패',
            description: '입차 완료 상태 변경 중 오류가 발생했습니다.',
            failure: true,
          );
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _plate = _plate.copyWith(isSelected: false, selectedBy: null);
      });
      parkingStatusTraceLog(
        context,
        '상태 변경 완료 from=parkingRequests to=parkingCompleted plate=${_plate.plateNumber}',
      );
      await _showCompletionFeedback('입차 완료');
      if (!mounted) return;
      Navigator.pop(context);
    });
  }

  Future<void> _completeDepartureDriving() async {
    await _runPrimary(() async {
      if (_type != PlateType.departureRequests) {
        return;
      }

      final userName = context.read<UserState>().name.trim();
      final selectedBy = (_plate.selectedBy ?? '').trim();
      if (selectedBy != userName || _plate.isSelected != true) {
        return;
      }

      final movementPlate = context.read<MovementPlate>();

      try {
        parkingStatusTraceLog(
          context,
          '상태 변경 시작 from=departureRequests to=departureCompleted plate=${_plate.plateNumber}',
        );
        await movementPlate.setDepartureCompleted(
          _plate,
          traceLog: (message) => parkingStatusTraceLog(context, message),
        );
      } catch (error) {
        parkingStatusTraceLog(
          context,
          '상태 변경 실패 from=departureRequests to=departureCompleted plate=${_plate.plateNumber} error=$error',
        );
        return;
      }

      if (!mounted) return;
      parkingStatusTraceLog(
        context,
        '상태 변경 완료 from=departureRequests to=departureCompleted plate=${_plate.plateNumber}',
      );
      setState(() {
        _plate = _plate.copyWith(isSelected: false, selectedBy: null);
      });
      await _showCompletionFeedback('출차 완료');
      if (!mounted) return;
      Navigator.pop(context);
    });
  }

  Future<void> _skipDepartureDrivingToCompleted() async {
    if (_drivingLocked) {
      return;
    }

    await _runPrimary(() async {
      if (_type != PlateType.departureRequests) {
        return;
      }

      final userName = context.read<UserState>().name.trim();
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

        await _showCompletionFeedback('출차 완료');
        if (!mounted) return;
        Navigator.pop(context);
      } catch (_) {
        return;
      }
    });
  }

  Future<void> _skipEntryDrivingToParkingCompleted() async {
    if (_drivingLocked) {
      return;
    }

    await _runPrimary(() async {
      if (_type != PlateType.parkingRequests) {
        return;
      }

      final userName = context.read<UserState>().name.trim();
      final selectedBy = (_plate.selectedBy ?? '').trim();

      if (_plate.isSelected == true &&
          selectedBy.isNotEmpty &&
          selectedBy != userName) {
        return;
      }

      final movementPlate = context.read<MovementPlate>();

      try {
        final area = _resolveAreaForCache();

        final picked = await _pickParkingLocationViaEditor(
          area: area,
          source: 'direct_complete',
        );

        if (picked == null || picked.trim().isEmpty) {
          return;
        }

        parkingStatusTraceLog(
          context,
          '상태 변경 시작 mode=skip from=parkingRequests to=parkingCompleted plate=${_plate.plateNumber}',
        );
        await movementPlate.setParkingCompleted(
          _plate.plateNumber,
          area,
          picked,
          traceLog: (message) => parkingStatusTraceLog(context, message),
        );

        if (!mounted) return;
        parkingStatusTraceLog(
          context,
          '상태 변경 완료 mode=skip from=parkingRequests to=parkingCompleted plate=${_plate.plateNumber}',
        );

        setState(() {
          _plate = _plate.copyWith(isSelected: false, selectedBy: null);
        });

        await _showCompletionFeedback('입차 완료');
        if (!mounted) return;
        Navigator.pop(context);
      } catch (error, stackTrace) {
        parkingStatusTraceLog(
          context,
          '상태 변경 실패 mode=skip from=parkingRequests to=parkingCompleted plate=${_plate.plateNumber} error=$error',
        );
        parkingStatusTraceLog(context, '상태 변경 stack_trace $stackTrace');
        final trace = parkingStatusTraceOf(context);
        if (trace != null && trace.developerMode && mounted) {
          await trace.showSnapshotStatusDialog(
            context,
            title: '입차 완료 실패',
            description: '입차 완료 상태 변경 중 오류가 발생했습니다.',
            failure: true,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bool otherDriving = _isOtherDriving;
    final String otherSelectedBy = (_plate.selectedBy ?? '').trim();

    Future<ParkingStatusDirectionalGearActionResult> Function()
        primaryOnPressed = () async {
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
            final billingResult = await _performPrebill(
                      continueDepartureAfterSuccess: true,
                    );
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

    final bool isDrivingPrimary = _isDrivingType;
    final bool drivingLatched = _drivingLocked;
    final bool disableOthers = drivingLatched;
    final bool gearBlocked = otherDriving;
    final bool gearEnabled = !_primaryBusy;

    Future<bool> Function()? onDriveEngage;
    Future<void> Function()? onDriveComplete;
    Future<void> Function()? onDriveCancel;

    if (_type == PlateType.parkingRequests) {
      onDriveEngage = _engageEntryDriving;
      onDriveComplete = _completeEntryDriving;
      onDriveCancel = _cancelEntryDriving;
    } else if (_type == PlateType.departureRequests) {
      onDriveEngage = _engageDepartureDriving;
      onDriveComplete = _completeDepartureDriving;
      onDriveCancel = _cancelDepartureDriving;
    }

    ParkingStatusDirectionalGearAction? lowerLeftAction;
    ParkingStatusDirectionalGearAction? lowerRightAction;

    if (_type == PlateType.parkingCompleted) {
      lowerLeftAction = ParkingStatusDirectionalGearAction(
        label: '입차 요청',
        debugAction: 'rollback_parking_request',
        icon: Icons.undo_rounded,
        tone: ParkingStatusDirectionalGearTone.warning,
        onConfirm: () async {
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
    } else if (_type == PlateType.parkingRequests) {
      lowerRightAction = ParkingStatusDirectionalGearAction(
        label: '입차 완료',
        debugAction: 'skip_entry_to_parking_completed',
        icon: Icons.skip_next_rounded,
        onConfirm: _skipEntryDrivingToParkingCompleted,
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

    final upperDownAction = isDrivingPrimary && onDriveCancel != null
        ? ParkingStatusDirectionalGearAction(
            label: '주행 취소',
            debugAction: 'driving_cancel',
            icon: Icons.keyboard_arrow_down_rounded,
            tone: ParkingStatusDirectionalGearTone.warning,
            onConfirm: () async {
              await onDriveCancel!.call();
            },
          )
        : null;
    final upperRightAction = isDrivingPrimary && onDriveComplete != null
        ? ParkingStatusDirectionalGearAction(
            label: '주행 완료',
            debugAction: 'driving_complete',
            icon: Icons.check_rounded,
            onConfirm: () async {
              await onDriveComplete!.call();
            },
          )
        : null;

    final sheet = ParkingStatusSideDockFrame(
      title: widget.plateNumber,
      subtitle: parkingStatusHeaderSubtitle(
        statusTitle: _sheetTitle,
        sectorId: _plate.sectorId,
        sectorName: _plate.sectorName,
      ),
      icon: Icons.directions_car_filled_rounded,
      closeEnabled: !drivingLatched && !_primaryBusy,
      onClose: _tryCloseSheet,
      leadingRail: ParkingStatusManagementRail(
        debugTarget: _sheetTitle,
        actions: [
          ParkingStatusManagementAction(
            icon: Icons.history,
            label: '로그 확인',
            displayLabel: '로그',
            debugAction: 'history',
            enabled: !_primaryBusy && !disableOthers,
            onPressed: () async {
              if (!mounted) return;
              final request = PlateLogSideDockRequest(
                plateNumber: widget.plateNumber,
                area: widget.area,
                plateId: _plate.id.trim().isEmpty ? null : _plate.id.trim(),
                source: 'minor_parking_completed_status',
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
              enabled: !_primaryBusy && !disableOthers && !_monthlyBillingLocked,
              onPressed: () async {
                if (_billingState == ParkingCompletedBillingState.settled) {
                  await _handleUnlockPrebill();
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
            enabled: !_primaryBusy && !disableOthers,
            onPressed: () async {
              parkingStatusTraceLog(
                context,
                '정보 수정 요청 plate=${_plate.plateNumber} handoff=modify_side_dock',
              );
              widget.onModifyRequested(_plate);
              Navigator.of(context).pop();
            },
          ),
          ParkingStatusManagementAction(
            icon: Icons.delete_forever,
            label: '삭제',
            displayLabel: '삭제',
            debugAction: 'delete',
            destructive: true,
            enabled: !_primaryBusy && !disableOthers,
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
        debugTarget: _sheetTitle,
        child: ParkingStatusDirectionalGear(
          debugTarget: _sheetTitle,
          enabled: gearEnabled,
          busy: _primaryBusy,
          driving: drivingLatched,
          blocked: gearBlocked && !drivingLatched,
          blockedBy: otherSelectedBy,
          onStartDriving: isDrivingPrimary ? onDriveEngage : null,
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
        debugTarget: _sheetTitle,
        scrollController: _scrollController,
        leading: [
          if (drivingLatched)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: _DrivingLockBanner(
                cs: cs,
                phase: _phaseLabel,
                selectedBy: otherSelectedBy,
              ),
            ),
          if (!drivingLatched && otherDriving)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: _OtherDrivingBanner(
                cs: cs,
                phase: _phaseLabel,
                selectedBy: otherSelectedBy,
              ),
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
    required this.cs,
    required this.phase,
    required this.selectedBy,
  });

  final ColorScheme cs;
  final String phase;
  final String selectedBy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$phase 주행 모드(락): 다른 기능이 비활성화됩니다.\n'
              '선점자: ${selectedBy.isEmpty ? "—" : selectedBy} · 뒤로가기/닫기 불가',
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtherDrivingBanner extends StatelessWidget {
  const _OtherDrivingBanner({
    required this.cs,
    required this.phase,
    required this.selectedBy,
  });

  final ColorScheme cs;
  final String phase;
  final String selectedBy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withOpacity(0.30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.error.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$phase 주행(타 사용자) 진행 중입니다. 기어 조작이 비활성화됩니다.\n'
              '선점자: ${selectedBy.isEmpty ? "—" : selectedBy}',
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
