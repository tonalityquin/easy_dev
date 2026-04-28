import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../../features/account/applications/user_state.dart';
import '../../../../../features/dev/application/area_state.dart';
import '../../../../../features/payment/widgets/billing_bottom_sheet.dart';
import '../../../../../features/payment/widgets/confirm_cancel_fee_dialog.dart';
import '../../../../../shared/page/modify/pages/modify_plate_screen.dart';
import '../../../../../shared/plate/application/common/movement_plate.dart';
import '../../../../../shared/plate/application/triple/triple_plate_state.dart';
import '../../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../../shared/plate/domain/models/plate_log_model.dart';
import '../../../../../shared/plate/domain/models/plate_model.dart';
import '../../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../../common_package/log_package/log_viewer_bottom_sheet.dart';
import '../../../../common_package/type_page/parking_completed_page/parking_completed_bottom_sheet/parking_completed_status_helpers.dart';
import '../../../../common_package/type_page/parking_completed_page/parking_completed_bottom_sheet/parking_completed_status_widgets.dart';

Future<bool> _showDeleteDialog(BuildContext context, PlateModel plate) async {
  return showParkingCompletedDeleteDialog(context, plate);
}

Future<void> showTripleParkingCompletedStatusBottomSheetFromDialog({
  required BuildContext context,
  required PlateModel plate,
  bool popParentOnDelete = true,
}) async {
  final deleted = await showTripleParkingCompletedStatusBottomSheet(
    context: context,
    plate: plate,
    onRequestEntry: () async {
      final area = context.read<AreaState>().currentArea;
      await handleParkingCompletedEntryRequest(
          context, plate.plateNumber, area);
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
  required Future<void> Function() onRequestEntry,
  required Future<bool> Function() onDelete,
}) async {
  final plateNumber = plate.plateNumber;
  final division = context.read<UserState>().division;
  final area = context.read<AreaState>().currentArea;

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => FractionallySizedBox(
      heightFactor: 1,
      child: _FullHeightSheet(
        plate: plate,
        plateNumber: plateNumber,
        division: division,
        area: area,
        onRequestEntry: onRequestEntry,
        onDelete: onDelete,
      ),
    ),
  );
}

enum _DepartureOverrideChoice { proceed, goBilling, cancel }

class _FullHeightSheet extends StatefulWidget {
  const _FullHeightSheet({
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
  final Future<void> Function() onRequestEntry;
  final Future<bool> Function() onDelete;

  @override
  State<_FullHeightSheet> createState() => _FullHeightSheetState();
}

class _FullHeightSheetState extends State<_FullHeightSheet>
    with SingleTickerProviderStateMixin {
  late PlateModel _plate;

  final ScrollController _scrollController = ScrollController();

  late final AnimationController _attentionCtrl;
  late final Animation<double> _attentionPulse;

  bool _departureOverrideArmed = false;
  DateTime? _departureOverrideArmedAt;
  static const Duration _overrideWindow = Duration(seconds: 12);

  bool _primaryBusy = false;

  final GlobalKey _billingTileKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _plate = widget.plate;

    _attentionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );

    _attentionPulse = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 55,
      ),
    ]).animate(_attentionCtrl);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _attentionCtrl.dispose();
    super.dispose();
  }

  PlateType? get _type => _plate.typeEnum;

  bool get _isDrivingType =>
      _type == PlateType.parkingRequests ||
      _type == PlateType.departureRequests;

  bool get _needsBilling =>
      (_type == PlateType.parkingCompleted) && (_plate.isLockedFee != true);

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

  bool get _overrideActive {
    if (!_departureOverrideArmed || _departureOverrideArmedAt == null) {
      return false;
    }
    return DateTime.now().difference(_departureOverrideArmedAt!) <=
        _overrideWindow;
  }

  void _resetOverride() {
    _departureOverrideArmed = false;
    _departureOverrideArmedAt = null;
  }

  void _armOverride() {
    _departureOverrideArmed = true;
    _departureOverrideArmedAt = DateTime.now();
  }

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

  Future<void> _triggerBillingRequiredAttention() async {
    final ctx = _billingTileKey.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        alignment: 0.12,
      );
    } else if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    }

    _attentionCtrl.forward(from: 0);
  }

  Future<bool> _autoPrebillFreeIfNeeded() async {
    if (_plate.isLockedFee == true) return true;
    if (!_isFreeBilling) return false;

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

      _resetOverride();
      return true;
    } catch (_) {
      if (!mounted) return false;
      return false;
    }
  }

  Future<_DepartureOverrideChoice?> _showDepartureOverrideDialog() async {
    final cs = Theme.of(context).colorScheme;

    return showDialog<_DepartureOverrideChoice>(
      context: context,
      barrierDismissible: true,
      barrierColor: cs.scrim.withOpacity(0.45),
      builder: (_) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: cs.errorContainer.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.error.withOpacity(0.28)),
                      ),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: cs.error,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '정산 없이 출차 요청',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: cs.outlineVariant.withOpacity(0.85)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '현재 사전 정산이 되어있지 않습니다.',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '그래도 출차 요청으로 이동하시겠습니까?',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.error.withOpacity(0.30)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.directions_car_filled,
                                size: 16, color: cs.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '차량: ${_plate.plateNumber}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.error,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(
                          context, _DepartureOverrideChoice.cancel),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.onSurface,
                        side: BorderSide(
                            color: cs.outlineVariant.withOpacity(0.85)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        '취소',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(
                          context, _DepartureOverrideChoice.goBilling),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.primary,
                        side: BorderSide(color: cs.primary.withOpacity(0.35)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        backgroundColor: cs.primaryContainer.withOpacity(0.35),
                      ),
                      child: const Text(
                        '정산하기',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () => Navigator.pop(
                          context, _DepartureOverrideChoice.proceed),
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.error,
                        foregroundColor: cs.onError,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        '그래도 출차 요청',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _goDepartureRequested() async {
    if (_drivingLocked) return;

    if (_isOtherDriving) {
      return;
    }

    final movementPlate = context.read<MovementPlate>();

    await movementPlate.setDepartureRequested(
      _plate.plateNumber,
      _plate.area,
      _effectiveLocation,
    );

    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _goBackToParkingCompleted() async {
    if (_drivingLocked) return;
    if (_isOtherDriving) return;

    await handleParkingCompletedBackToCompletedRequest(
      context,
      plate: _plate,
      fallbackArea: widget.area,
    );

    if (!mounted) return;
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
        await movementPlate.setDepartureCompleted(_plate);

        if (!mounted) return;

        setState(() {
          _plate = _plate.copyWith(isSelected: false, selectedBy: null);
        });

        Navigator.pop(context);
      } catch (_) {
        return;
      }
    });
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

      final repo = context.read<PlateRepository>();
      final movementPlate = context.read<MovementPlate>();
      final id = _plateDocId();

      try {
        if (_type == PlateType.parkingRequests) {
          await movementPlate.setParkingCompleted(
            _plate.plateNumber,
            _plate.area,
            _effectiveLocation,
          );
        } else if (_type == PlateType.departureRequests) {
          await movementPlate.setDepartureCompleted(_plate);
        }

        try {
          await repo.recordWhoPlateClick(id, false, area: _plate.area);
        } catch (_) {}

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

  Future<void> _handlePrebill() async {
    if (_drivingLocked) return;

    if (_isOtherDriving) {
      return;
    }

    await _runPrimary(() async {
      final userName = context.read<UserState>().name;
      final repo = context.read<PlateRepository>();
      final plateState = context.read<TriplePlateState>();

      final bt = (_plate.billingType ?? '').trim();
      if (bt.isEmpty) {
        return;
      }

      final now = DateTime.now();
      final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;
      final entryTime =
          _plate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;

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

        if (!mounted) return;

        setState(() => _plate = freshPlate);
        _resetOverride();
      } catch (_) {
        if (!mounted) return;
        return;
      }
    });
  }

  Future<void> _handleCancelPrebill() async {
    if (_drivingLocked) return;

    if (_isOtherDriving) {
      return;
    }

    await _runPrimary(() async {
      final userName = context.read<UserState>().name;
      final repo = context.read<PlateRepository>();
      final plateState = context.read<TriplePlateState>();

      if (_plate.isLockedFee != true) {
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => const ConfirmCancelFeeDialog(),
      );
      if (confirm != true) return;

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
        _resetOverride();
      } catch (_) {
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

    final isLocked = _plate.isLockedFee == true;
    final lockedFee = _plate.lockedFeeAmount;
    final paymentMethod = (_plate.paymentMethod ?? '').trim();
    final billingType = (_plate.billingType ?? '').trim();
    final location =
        (_plate.location).trim().isEmpty ? '미지정' : _plate.location.trim();

    final statusMemo = resolveParkingCompletedStatusMemo(_plate);

    IconData primaryIcon = Icons.local_shipping_outlined;
    String primaryTitle = '출차 요청으로 이동';
    String primarySubtitle = '차량을 출차 요청 상태로 전환합니다.';

    Future<void> Function() primaryOnPressed = () async {
      if (_drivingLocked) return;

      if (_isOtherDriving) {
        return;
      }

      await _runPrimary(() async {
        if (_needsBilling) {
          if (_isFreeBilling) {
            final ok = await _autoPrebillFreeIfNeeded();
            if (!ok) return;
            await _goDepartureRequested();
            return;
          }

          if (_overrideActive) {
            _resetOverride();

            final choice = await _showDepartureOverrideDialog();
            if (!mounted) return;

            if (choice == _DepartureOverrideChoice.proceed) {
              await _goDepartureRequested();
              return;
            }

            if (choice == _DepartureOverrideChoice.goBilling) {
              await _triggerBillingRequiredAttention();
              return;
            }

            return;
          }

          _armOverride();
          await _triggerBillingRequiredAttention();
          return;
        }

        _resetOverride();
        await _goDepartureRequested();
      });
    };

    final bool isDrivingPrimary = (_type == PlateType.parkingRequests ||
        _type == PlateType.departureRequests);

    if (_type == PlateType.parkingRequests) {
      primaryIcon = Icons.play_circle_fill;
      primaryTitle = _isMyDriving ? '입차 주행 계속' : '입차 주행 시작';
      primarySubtitle = _isMyDriving
          ? '이전에 시작된 주행 상태가 유지되었습니다. 완료 또는 취소로 정리하세요.'
          : '기어를 위로 올려 주행을 시작합니다. (주행 중에는 뒤로가기가 잠깁니다)';
    } else if (_type == PlateType.departureRequests) {
      primaryIcon = Icons.play_circle_fill;
      primaryTitle = _isMyDriving ? '출차 주행 계속' : '출차 주행 시작';
      primarySubtitle = _isMyDriving
          ? '이전에 시작된 주행 상태가 유지되었습니다. 완료 또는 취소로 정리하세요.'
          : '기어를 위로 올려 주행을 시작합니다. (주행 중에는 뒤로가기가 잠깁니다)';
    }

    final bool disableOthers = _drivingLocked;

    final String sheetTitle = () {
      if (_type == PlateType.parkingRequests) return '입차 요청 상태 처리';
      if (_type == PlateType.departureRequests) return '출차 요청 상태 처리';
      return '입차 완료 상태 처리';
    }();

    return PopScope(
      canPop: !_drivingLocked,
      onPopInvoked: (didPop) {},
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
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
                    ParkingCompletedSheetTitleRow(
                      title: sheetTitle,
                      icon: Icons.settings,
                      onClose: _tryClose,
                      closeEnabled: !disableOthers,
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: _attentionPulse,
                  builder: (context, _) {
                    final attention = _attentionPulse.value;

                    final shakeDx =
                        math.sin(_attentionCtrl.value * math.pi * 10) *
                            (1 - _attentionCtrl.value) *
                            6;
                    final scale = 1 + (attention * 0.012);

                    return ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        if (_drivingLocked) ...[
                          _DrivingLockBanner(
                            selectedBy: (_plate.selectedBy ?? '').trim(),
                            phase: (_type == PlateType.parkingRequests)
                                ? '입차'
                                : '출차',
                          ),
                          const SizedBox(height: 12),
                        ] else if (_isOtherDriving) ...[
                          _OtherDrivingBanner(
                            selectedBy: (_plate.selectedBy ?? '').trim(),
                            phase: (_type == PlateType.parkingRequests)
                                ? '입차'
                                : '출차',
                          ),
                          const SizedBox(height: 12),
                        ],
                        Transform.translate(
                          offset: Offset(_needsBilling ? shakeDx : 0, 0),
                          child: Transform.scale(
                            scale: _needsBilling ? scale : 1,
                            child: ParkingCompletedPlateSummaryCard(
                              plateNumber: widget.plateNumber,
                              area: _plate.area,
                              location: location,
                              billingType: billingType,
                              isLocked: isLocked,
                              lockedFee: lockedFee,
                              paymentMethod: paymentMethod,
                              statusMemo: statusMemo,
                              attention: _needsBilling ? attention : 0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ParkingCompletedSectionCard(
                          title: '핵심 작업',
                          subtitle: '자주 사용하는 기능을 상단에 배치했습니다.',
                          child: Column(
                            children: [
                              if (isDrivingPrimary)
                                _GearShiftDrivingControl(
                                  cs: cs,
                                  icon: primaryIcon,
                                  title: primaryTitle,
                                  subtitle: primarySubtitle,
                                  locked: _drivingLocked,
                                  enabled: !_primaryBusy && !_isOtherDriving,
                                  onEngage: _engageDrivingByGear,
                                  onComplete: _completeDrivingByGear,
                                  onCancel: _cancelDrivingByGear,
                                  upThreshold: 0.86,
                                  downThreshold: 0.14,
                                ),
                              if (!isDrivingPrimary)
                                ParkingCompletedPrimaryCtaButton(
                                  icon: primaryIcon,
                                  title: primaryTitle,
                                  subtitle: primarySubtitle,
                                  enabled: !_primaryBusy && !disableOthers,
                                  onPressed: primaryOnPressed,
                                ),
                              if (_type == PlateType.departureRequests) ...[
                                const SizedBox(height: 10),
                                ParkingCompletedPrimaryCtaButton(
                                  icon: Icons.skip_next_rounded,
                                  title: '주행 스킵 후 출차 완료',
                                  subtitle: '주행 과정을 생략하고 바로 출차 완료로 변경합니다.',
                                  enabled: !_primaryBusy &&
                                      !disableOthers &&
                                      !_isOtherDriving,
                                  onPressed: _skipDepartureDrivingToCompleted,
                                  backgroundColor: cs.tertiary,
                                  foregroundColor: cs.onTertiary,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        AbsorbPointer(
                          absorbing: disableOthers,
                          child: Opacity(
                            opacity: disableOthers ? 0.55 : 1.0,
                            child: ParkingCompletedSectionCard(
                              title: '기타',
                              subtitle: disableOthers
                                  ? '주행 중에는 다른 기능을 사용할 수 없습니다.'
                                  : (_isOtherDriving
                                      ? '타 사용자가 주행 중입니다. 변경 기능은 제한될 수 있습니다.'
                                      : '로그 확인, 정보 수정, 정산/취소, 삭제 등'),
                              child: Column(
                                children: [
                                  Builder(
                                    builder: (_) {
                                      final bool blockMutations =
                                          _isOtherDriving;

                                      final tiles = <Widget>[
                                        ParkingCompletedSecondaryActionButton(
                                          icon: Icons.history,
                                          label: '로그 확인',
                                          enabled: !_primaryBusy,
                                          onPressed: () async {
                                            Navigator.pop(context);
                                            Navigator.push(
                                              rootContext,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    LogViewerBottomSheet(
                                                  initialPlateNumber:
                                                      widget.plateNumber,
                                                  division: widget.division,
                                                  area: widget.area,
                                                  requestTime:
                                                      _plate.requestTime,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        ParkingCompletedSecondaryActionButton(
                                          icon: Icons.edit_note_outlined,
                                          label: '정보 수정',
                                          enabled:
                                              !_primaryBusy && !blockMutations,
                                          onPressed: () async {
                                            if (blockMutations) {
                                              return;
                                            }
                                            Navigator.pop(context);
                                            Navigator.push(
                                              rootContext,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    ModifyPlateScreen(
                                                  plate: _plate,
                                                  collectionKey: PlateType
                                                      .parkingCompleted,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        KeyedSubtree(
                                          key: _billingTileKey,
                                          child:
                                              ParkingCompletedSecondaryActionButton(
                                            icon: Icons.receipt_long,
                                            label: '정산',
                                            enabled: !_primaryBusy &&
                                                !blockMutations,
                                            badgeText:
                                                _needsBilling ? '필수' : null,
                                            attention:
                                                _needsBilling ? attention : 0,
                                            backgroundColor: _needsBilling
                                                ? cs.errorContainer
                                                    .withOpacity(0.35)
                                                : cs.surfaceContainerLow,
                                            borderColor: _needsBilling
                                                ? cs.error.withOpacity(0.45)
                                                : cs.outlineVariant
                                                    .withOpacity(0.85),
                                            foregroundColor: _needsBilling
                                                ? cs.error
                                                : cs.onSurface,
                                            onPressed: _handlePrebill,
                                          ),
                                        ),
                                        ParkingCompletedSecondaryActionButton(
                                          icon: Icons.lock_open,
                                          label: '정산 취소',
                                          enabled:
                                              !_primaryBusy && !blockMutations,
                                          badgeText: isLocked ? '잠김' : '비잠김',
                                          backgroundColor: isLocked
                                              ? cs.tertiaryContainer
                                                  .withOpacity(0.45)
                                              : cs.surfaceContainerLow,
                                          borderColor: isLocked
                                              ? cs.tertiary.withOpacity(0.35)
                                              : cs.outlineVariant
                                                  .withOpacity(0.85),
                                          foregroundColor: isLocked
                                              ? cs.tertiary
                                              : cs.onSurface,
                                          onPressed: _handleCancelPrebill,
                                        ),
                                        if (_type == PlateType.parkingCompleted)
                                          ParkingCompletedSecondaryActionButton(
                                            icon: Icons.undo_rounded,
                                            label: '입차 요청으로',
                                            enabled: !_primaryBusy &&
                                                !blockMutations,
                                            onPressed: () async {
                                              if (blockMutations) {
                                                return;
                                              }
                                              Navigator.pop(context);
                                              await widget.onRequestEntry();
                                            },
                                          ),
                                        if (_type ==
                                            PlateType.departureRequests)
                                          ParkingCompletedSecondaryActionButton(
                                            icon: Icons.undo_rounded,
                                            label: '입차 완료로',
                                            enabled: !_primaryBusy &&
                                                !blockMutations,
                                            onPressed: () async {
                                              if (blockMutations) {
                                                return;
                                              }
                                              await _goBackToParkingCompleted();
                                            },
                                          ),
                                      ];

                                      if (tiles.length.isOdd) {
                                        tiles.add(const SizedBox.shrink());
                                      }

                                      return GridView.count(
                                        crossAxisCount: 2,
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                        childAspectRatio: 2.6,
                                        children: tiles,
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  ParkingCompletedDangerActionButton(
                                    icon: Icons.delete_forever,
                                    label: '삭제',
                                    enabled: !_primaryBusy && !_isOtherDriving,
                                    onPressed: () async {
                                      if (_isOtherDriving) {
                                        return;
                                      }
                                      final deleted = await widget.onDelete();
                                      if (!mounted) return;
                                      if (deleted) {
                                        Navigator.of(context).pop(true);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    );
                  },
                ),
              ),
            ],
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
                  '선점자: $who · 뒤로가기/닫기 불가\n아래 버튼으로 “주행 완료/취소”를 선택하세요.',
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

class _GearShiftDrivingControl extends StatefulWidget {
  const _GearShiftDrivingControl({
    required this.cs,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.locked,
    required this.enabled,
    required this.onEngage,
    required this.onComplete,
    required this.onCancel,
    this.upThreshold = 0.86,
    this.downThreshold = 0.14,
  });

  final ColorScheme cs;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool locked;
  final bool enabled;
  final Future<bool> Function() onEngage;
  final Future<void> Function() onComplete;
  final Future<void> Function() onCancel;
  final double upThreshold;
  final double downThreshold;

  @override
  State<_GearShiftDrivingControl> createState() =>
      _GearShiftDrivingControlState();
}

class _GearShiftDrivingControlState extends State<_GearShiftDrivingControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  bool _armedHapticSent = false;
  bool _busyInternal = false;

  static const double _trackHeight = 132;
  static const double _trackWidth = 92;
  static const double _handleHeight = 48;
  static const double _pad = 12;
  static const double _slotWidth = 32;

  double get _travel => _trackHeight - (_pad * 2) - _handleHeight;

  double get _slotHeight => _trackHeight - (_pad * 2);

  bool get _canInteract => widget.enabled && !_busyInternal;

  bool get _armedUp => _ctrl.value >= widget.upThreshold;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
      value: widget.locked ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(covariant _GearShiftDrivingControl oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.locked != widget.locked) {
      _armedHapticSent = false;
      _animateTo(widget.locked ? 1 : 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _animateTo(double v) async {
    try {
      await _ctrl.animateTo(
        v.clamp(0.0, 1.0).toDouble(),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  void _onDragStart(DragStartDetails d) {
    if (!_canInteract) return;
    if (widget.locked) return;
    _armedHapticSent = false;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_canInteract) return;
    if (widget.locked) return;

    final delta = (-d.delta.dy) / _travel;
    final next = (_ctrl.value + delta).clamp(0.0, 1.0).toDouble();
    _ctrl.value = next;

    if (_armedUp && !_armedHapticSent) {
      _armedHapticSent = true;
      try {
        HapticFeedback.selectionClick();
      } catch (_) {}
    }

    if (!_armedUp) {
      _armedHapticSent = false;
    }
  }

  Future<void> _onDragEnd(DragEndDetails d) async {
    if (!_canInteract) return;
    if (widget.locked) return;

    if (_armedUp) {
      setState(() => _busyInternal = true);
      try {
        try {
          HapticFeedback.mediumImpact();
        } catch (_) {}

        await _animateTo(1);
        final ok = await widget.onEngage();

        if (!ok && mounted) {
          await _animateTo(0);
        }
      } finally {
        if (mounted) setState(() => _busyInternal = false);
      }
      return;
    }

    await _animateTo(0);
  }

  Future<void> _runAction(Future<void> Function() fn) async {
    if (!_canInteract) return;
    setState(() => _busyInternal = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busyInternal = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final p = _ctrl.value.clamp(0.0, 1.0).toDouble();

        final active = widget.locked || _armedUp;

        final bg = Color.lerp(
          cs.primary.withOpacity(0.10),
          cs.primary.withOpacity(0.18),
          active ? 1 : 0,
        )!;
        final border = Color.lerp(
          cs.primary.withOpacity(0.28),
          cs.primary.withOpacity(0.48),
          active ? 1 : 0,
        )!;

        final hint = _busyInternal
            ? '처리 중...'
            : (widget.locked
                ? '주행 중: 아래 버튼으로 완료/취소'
                : (_armedUp ? '놓으면 주행 시작' : '기어를 위로 올려 START'));

        final handleTop = _pad + ((1 - p) * _travel);
        final fillH = (_slotHeight * p).clamp(0.0, _slotHeight).toDouble();
        final slotLeft = (_trackWidth - _slotWidth) / 2;

        final bool dragEnabled = _canInteract && !widget.locked;

        return Opacity(
          opacity: widget.enabled ? 1 : 0.55,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 1.2),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(widget.icon, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.subtitle,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    width: _trackWidth,
                    height: _trackHeight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: dragEnabled ? _onDragStart : null,
                      onVerticalDragUpdate: dragEnabled ? _onDragUpdate : null,
                      onVerticalDragEnd: dragEnabled ? _onDragEnd : null,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                color: cs.surfaceContainerLow,
                                border: Border.all(
                                  color: cs.outlineVariant.withOpacity(0.85),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: cs.shadow.withOpacity(0.12),
                                    blurRadius: 18,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: cs.surface,
                                  border: Border.all(
                                    color: cs.outlineVariant.withOpacity(0.50),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: slotLeft,
                            right: slotLeft,
                            top: _pad,
                            bottom: _pad,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: cs.surfaceContainerHigh,
                                border: Border.all(
                                  color: cs.outlineVariant.withOpacity(0.55),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: slotLeft + 2,
                            right: slotLeft + 2,
                            bottom: _pad + 2,
                            height: (fillH - 4).clamp(0.0, _slotHeight),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: cs.primary.withOpacity(0.18),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Text(
                                widget.locked ? 'LOCKED' : 'START',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                  color:
                                      active ? cs.primary : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 8,
                            right: 8,
                            top: handleTop,
                            height: _handleHeight,
                            child: _ShifterHandle(
                              cs: cs,
                              active: active,
                              busy: _busyInternal,
                              locked: widget.locked,
                            ),
                          ),
                          if (_busyInternal)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cs.scrim.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.locked
                          ? Icons.directions_car_filled
                          : Icons.keyboard_arrow_up,
                      size: 18,
                      color: active ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        hint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: active ? cs.primary : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.locked) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _canInteract
                              ? () => _runAction(widget.onCancel)
                              : null,
                          style: OutlinedButton.styleFrom(
                            backgroundColor:
                                cs.errorContainer.withOpacity(0.35),
                            foregroundColor: cs.error,
                            side: BorderSide(color: cs.error.withOpacity(0.45)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            _busyInternal ? '처리 중...' : '주행 취소',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: cs.error,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _canInteract
                              ? () => _runAction(widget.onComplete)
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            _busyInternal ? '처리 중...' : '주행 완료',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ShifterHandle extends StatelessWidget {
  const _ShifterHandle({
    required this.cs,
    required this.active,
    required this.busy,
    required this.locked,
  });

  final ColorScheme cs;
  final bool active;
  final bool busy;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final base = active ? cs.primary : cs.surfaceContainerHigh;
    final hi = active ? cs.primary.withOpacity(0.92) : cs.surface;
    final lo = active ? cs.primary.withOpacity(0.82) : cs.surfaceContainerLow;

    final border = active
        ? cs.primary.withOpacity(0.55)
        : cs.outlineVariant.withOpacity(0.60);

    final fg = active ? cs.onPrimary : cs.onSurfaceVariant;

    final icon = busy
        ? Icons.more_horiz
        : (locked ? Icons.lock_open : Icons.drag_handle_rounded);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [hi, base, lo],
          stops: const [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(active ? 0.22 : 0.14),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: (active ? cs.onPrimary : cs.surface).withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: (active ? cs.onPrimary : cs.onSurfaceVariant)
                    .withOpacity(0.22),
              ),
            ),
            child: Icon(icon, size: 18, color: fg),
          ),
        ),
      ),
    );
  }
}
