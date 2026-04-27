import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../../features/account/applications/user_state.dart';
import '../../../../../features/dev/application/area_state.dart';
import '../../../../../features/plate/application/common/movement_plate.dart';
import '../../../../../features/plate/application/minor/minor_plate_state.dart';
import '../../../../../features/plate/domain/enums/plate_type.dart';
import '../../../../../features/plate/domain/models/plate_log_model.dart';
import '../../../../../features/plate/domain/models/plate_model.dart';
import '../../../../../features/plate/domain/repositories/plate_repository.dart';
import '../../../../../shared/page/modify/pages/modify_plate_screen.dart';
import '../../../../../widgets/bottom_sheet/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../../../widgets/dialog/confirm_cancel_fee_dialog.dart';
import 'input_location_bottom_sheet.dart';
import '../../../../common_package/log_package/log_viewer_bottom_sheet.dart';
import '../../../../common_package/type_page/parking_completed_page/parking_completed_bottom_sheet/parking_completed_status_helpers.dart';
import '../../../../common_package/type_page/parking_completed_page/parking_completed_bottom_sheet/parking_completed_status_widgets.dart';

class _BrandTone {
  static Color border(ColorScheme cs) => cs.outlineVariant.withOpacity(0.85);

  static Color softBorder(ColorScheme cs) =>
      cs.outlineVariant.withOpacity(0.55);

  static Color ok(ColorScheme cs) => cs.tertiary;

  static Color okBg(ColorScheme cs) => cs.tertiaryContainer;

  static Color warning(ColorScheme cs) => cs.secondary;

  static Color warningBg(ColorScheme cs) => cs.secondaryContainer;

  static Color warningFg(ColorScheme cs) => cs.onSecondaryContainer;
}

Future<bool> _showDeleteDialog(BuildContext context, PlateModel plate) async {
  return showParkingCompletedDeleteDialog(context, plate);
}

Future<void> showMinorParkingCompletedStatusBottomSheetFromDialog({
  required BuildContext context,
  required PlateModel plate,
  bool popParentOnDelete = true,
}) async {
  final deleted = await showMinorParkingCompletedStatusBottomSheet(
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

Future<bool?> showMinorParkingCompletedStatusBottomSheet({
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
        selectedBy.isNotEmpty &&
        userName.isNotEmpty &&
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

  void _tryCloseSheet() {
    if (_drivingLocked) {
      return;
    }
    if (_primaryBusy) return;
    Navigator.of(context).pop();
  }

  Future<bool> _autoPrebillFreeIfNeeded() async {
    if (_plate.isLockedFee == true) return true;
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
        source: 'parkingCompletedStatus.freeAutoPrebill.repo.settlePlateBilling',
        n: 1,
      );

      final refreshedPlate = await repo.getPlate(_plate.id) ?? updatedPlate;

      await plateState.minorUpdatePlateLocally(
        PlateType.parkingCompleted,
        refreshedPlate,
      );

      if (!mounted) return false;
      setState(() => _plate = refreshedPlate);

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
      barrierColor: cs.scrim.withOpacity(0.55),
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
              border: Border.all(color: _BrandTone.border(cs)),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withOpacity(0.18),
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
                        color: _BrandTone.warningBg(cs).withOpacity(0.55),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _BrandTone.warning(cs).withOpacity(0.30),
                        ),
                      ),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: _BrandTone.warning(cs),
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
                    border: Border.all(color: _BrandTone.softBorder(cs)),
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
                          color: _BrandTone.warningBg(cs).withOpacity(0.55),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _BrandTone.warning(cs).withOpacity(0.30),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.directions_car_filled,
                                size: 16, color: _BrandTone.warning(cs)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '차량: ${_plate.plateNumber}',
                                style: TextStyle(
                                  color: _BrandTone.warningFg(cs),
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
                        side: BorderSide(color: _BrandTone.border(cs)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
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
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        backgroundColor: cs.primary.withOpacity(0.06),
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
                        backgroundColor: _BrandTone.warning(cs),
                        foregroundColor: _BrandTone.warningFg(cs),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
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
    );

    if (!mounted) return;
    Navigator.pop(context);
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

  Future<String?> _pickParkingLocationViaInputBottomSheet({
    required String plateNumber,
    required String area,
  }) async {
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    final initial = _plate.location.trim();
    final controller = TextEditingController(text: initial);
    String? picked;

    try {
      await InputLocationBottomSheet.show(
        rootContext,
        controller,
        (v) => picked = v,
      );
    } catch (_) {
      return null;
    } finally {
      controller.dispose();
    }

    final v = (picked ?? '').trim();
    if (v.isEmpty) return null;

    String normalize(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalize(v) == normalize(initial)) return null;

    return v;
  }

  Future<void> _handlePrebill() async {
    if (_drivingLocked) {
      return;
    }

    await _runPrimary(() async {
      final userName = context.read<UserState>().name;
      final repo = context.read<PlateRepository>();
      final plateState = context.read<MinorPlateState>();

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

      final updatedPlate = _plate.copyWith(
        isLockedFee: true,
        lockedAtTimeInSeconds: currentTime,
        lockedFeeAmount: result.lockedFee,
        paymentMethod: result.paymentMethod,
      );

      try {
        await repo.settlePlateBilling(
          documentId: _plate.id,
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
            reason: result.reason,
          ),
        );
        reportParkingCompletedDbSafe(
          area: _plate.area,
          action: 'write',
          source: 'parkingCompletedStatus.prebill.repo.settlePlateBilling',
          n: 1,
        );

        final refreshedPlate = await repo.getPlate(_plate.id) ?? updatedPlate;

        await plateState.minorUpdatePlateLocally(
          PlateType.parkingCompleted,
          refreshedPlate,
        );

        if (!mounted) return;

        setState(() => _plate = refreshedPlate);
        _resetOverride();
      } catch (_) {
        if (!mounted) return;
        return;
      }
    });
  }

  Future<void> _handleUnlockPrebill() async {
    if (_drivingLocked) {
      return;
    }

    await _runPrimary(() async {
      final userName = context.read<UserState>().name;
      final repo = context.read<PlateRepository>();
      final plateState = context.read<MinorPlateState>();

      if (_plate.isLockedFee != true) {
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => const ConfirmCancelFeeDialog(),
      );
      if (confirm != true) return;

      final now = DateTime.now();
      final updatedPlate = _plate.copyWith(
        isLockedFee: false,
        lockedAtTimeInSeconds: null,
        lockedFeeAmount: null,
        paymentMethod: null,
      );

      try {
        await repo.cancelPlateBilling(
          documentId: _plate.id,
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

        final refreshedPlate = await repo.getPlate(_plate.id) ?? updatedPlate;

        await plateState.minorUpdatePlateLocally(
          PlateType.parkingCompleted,
          refreshedPlate,
        );

        if (!mounted) return;

        setState(() => _plate = refreshedPlate);
        _resetOverride();
      } catch (_) {
        if (!mounted) return;
        return;
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

      final repo = context.read<PlateRepository>();
      final plateState = context.read<MinorPlateState>();
      final movementPlate = context.read<MovementPlate>();
      final id = _plateDocId();

      final area = _resolveAreaForCache();

      final picked = await _pickParkingLocationViaInputBottomSheet(
        plateNumber: _plate.plateNumber,
        area: area,
      );

      if (picked == null || picked.trim().isEmpty) {
        return;
      }

      try {
        await movementPlate.setParkingCompleted(
          _plate.plateNumber,
          area,
          picked,
        );
      } catch (_) {
        return;
      }

      try {
        await repo.recordWhoPlateClick(id, false, area: _plate.area);
      } catch (_) {}

      final updated = _plate.copyWith(isSelected: false, selectedBy: null);
      if (mounted) setState(() => _plate = updated);
      try {
        await plateState.minorUpdatePlateLocally(
          PlateType.parkingRequests,
          updated,
        );
      } catch (_) {}

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

      final repo = context.read<PlateRepository>();
      final plateState = context.read<MinorPlateState>();
      final movementPlate = context.read<MovementPlate>();
      final id = _plateDocId();

      await movementPlate.setDepartureCompleted(_plate);

      try {
        await repo.recordWhoPlateClick(id, false, area: _plate.area);
      } catch (_) {}

      final updated = _plate.copyWith(isSelected: false, selectedBy: null);
      if (mounted) setState(() => _plate = updated);
      try {
        await plateState.minorUpdatePlateLocally(
          PlateType.departureRequests,
          updated,
        );
      } catch (_) {}

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

      final repo = context.read<PlateRepository>();
      final movementPlate = context.read<MovementPlate>();

      try {
        final area = _resolveAreaForCache();

        final picked = await _pickParkingLocationViaInputBottomSheet(
          plateNumber: _plate.plateNumber,
          area: area,
        );

        if (picked == null || picked.trim().isEmpty) {
          return;
        }

        await movementPlate.setParkingCompleted(
          _plate.plateNumber,
          area,
          picked,
        );

        try {
          await repo.recordWhoPlateClick(
            _plateDocId(),
            false,
            area: _plate.area,
          );
        } catch (_) {}

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

    final bool otherDriving = _isOtherDriving;
    final String otherSelectedBy = (_plate.selectedBy ?? '').trim();

    IconData primaryIcon = Icons.local_shipping_outlined;
    String primaryTitle = '출차 요청으로 이동';
    String primarySubtitle = '차량을 출차 요청 상태로 전환합니다.';

    Future<void> Function() primaryOnPressed = () async {
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

    final bool isDrivingPrimary = _isDrivingType;

    final bool drivingLatched = _drivingLocked;
    final bool disableOthers = drivingLatched;

    final bool gearBlocked = otherDriving;
    final bool gearEnabled = !_primaryBusy;

    Future<bool> Function()? onDriveEngage;
    Future<void> Function()? onDriveComplete;
    Future<void> Function()? onDriveCancel;

    if (_type == PlateType.parkingRequests) {
      primaryIcon = Icons.play_circle_fill;
      primaryTitle =
          drivingLatched ? '입차 주행 중' : (_isMyDriving ? '입차 주행 계속' : '입차 주행 시작');
      primarySubtitle = drivingLatched
          ? '주행 모드입니다. 완료 또는 취소를 선택하세요.'
          : (gearBlocked
              ? '다른 사용자가 주행 중입니다. (기어 비활성)'
              : '기어를 올려 주행 모드로 전환합니다. (주행 중 뒤로가기 잠김)');
      onDriveEngage = _engageEntryDriving;
      onDriveComplete = _completeEntryDriving;
      onDriveCancel = _cancelEntryDriving;
    } else if (_type == PlateType.departureRequests) {
      primaryIcon = Icons.play_circle_fill;
      primaryTitle =
          drivingLatched ? '출차 주행 중' : (_isMyDriving ? '출차 주행 계속' : '출차 주행 시작');
      primarySubtitle = drivingLatched
          ? '주행 모드입니다. 완료 또는 취소를 선택하세요.'
          : (gearBlocked
              ? '다른 사용자가 주행 중입니다. (기어 비활성)'
              : '기어를 올려 주행 모드로 전환합니다. (주행 중 뒤로가기 잠김)');
      onDriveEngage = _engageDepartureDriving;
      onDriveComplete = _completeDepartureDriving;
      onDriveCancel = _cancelDepartureDriving;
    }

    return PopScope(
      canPop: !drivingLatched,
      onPopInvoked: (didPop) {},
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: _BrandTone.border(cs)),
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
                          color: cs.outlineVariant.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    ParkingCompletedSheetTitleRow(
                      title: _sheetTitle,
                      icon: Icons.settings,
                      colorScheme: cs,
                      onClose: _tryCloseSheet,
                      closeEnabled: !drivingLatched && !_primaryBusy,
                    ),
                    if (drivingLatched) ...[
                      const SizedBox(height: 10),
                      _DrivingLockBanner(
                        cs: cs,
                        phase: _phaseLabel,
                        selectedBy: otherSelectedBy,
                      ),
                    ],
                    if (!drivingLatched && otherDriving) ...[
                      const SizedBox(height: 10),
                      _OtherDrivingBanner(
                        cs: cs,
                        phase: _phaseLabel,
                        selectedBy: otherSelectedBy,
                      ),
                    ],
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

                    final tiles = <Widget>[
                      ParkingCompletedSecondaryActionButton(
                        colorScheme: cs,
                        icon: Icons.history,
                        label: '로그 확인',
                        enabled: !_primaryBusy,
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
                      ParkingCompletedSecondaryActionButton(
                        colorScheme: cs,
                        icon: Icons.edit_note_outlined,
                        label: '정보 수정',
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
                      KeyedSubtree(
                        key: _billingTileKey,
                        child: ParkingCompletedSecondaryActionButton(
                          colorScheme: cs,
                          icon: Icons.receipt_long,
                          label: '정산',
                          enabled: !_primaryBusy,
                          badgeText: _needsBilling ? '필수' : null,
                          badgeColor: cs.error,
                          iconColor: _needsBilling ? cs.error : null,
                          baseBackgroundColor: _needsBilling
                              ? cs.errorContainer.withOpacity(0.22)
                              : cs.surfaceContainerLow,
                          baseBorderColor: _needsBilling
                              ? cs.error.withOpacity(0.55)
                              : _BrandTone.border(cs),
                          attention: _needsBilling ? attention : 0,
                          onPressed: _handlePrebill,
                        ),
                      ),
                      ParkingCompletedSecondaryActionButton(
                        colorScheme: cs,
                        icon: Icons.lock_open,
                        label: '정산 취소',
                        enabled: !_primaryBusy,
                        badgeText: isLocked ? '잠김' : '비잠김',
                        badgeColor:
                            isLocked ? _BrandTone.ok(cs) : cs.onSurfaceVariant,
                        iconColor: isLocked ? _BrandTone.ok(cs) : null,
                        baseBackgroundColor: isLocked
                            ? _BrandTone.okBg(cs).withOpacity(0.45)
                            : cs.surfaceContainerLow,
                        baseBorderColor: isLocked
                            ? _BrandTone.ok(cs).withOpacity(0.35)
                            : _BrandTone.border(cs),
                        onPressed: _handleUnlockPrebill,
                      ),
                      if (_type == PlateType.parkingCompleted)
                        ParkingCompletedSecondaryActionButton(
                          colorScheme: cs,
                          icon: Icons.undo,
                          label: '입차 요청으로',
                          enabled: !_primaryBusy,
                          onPressed: () async {
                            try {
                              await widget.onRequestEntry();
                              if (!mounted) return;
                              Navigator.pop(context);
                            } catch (_) {
                              if (!mounted) return;
                              return;
                            }
                          },
                        ),
                      if (_type == PlateType.departureRequests)
                        ParkingCompletedSecondaryActionButton(
                          colorScheme: cs,
                          icon: Icons.undo,
                          label: '입차 완료로',
                          enabled: !_primaryBusy && !_isOtherDriving,
                          onPressed: () async {
                            try {
                              await _goBackToParkingCompleted();
                            } catch (_) {
                              if (!mounted) return;
                              return;
                            }
                          },
                        ),
                    ];

                    if (tiles.length.isOdd) {
                      tiles.add(const SizedBox.shrink());
                    }

                    return ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        Transform.translate(
                          offset: Offset(_needsBilling ? shakeDx : 0, 0),
                          child: Transform.scale(
                            scale: _needsBilling ? scale : 1,
                            child: ParkingCompletedPlateSummaryCard(
                              colorScheme: cs,
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
                          colorScheme: cs,
                          title: '핵심 작업',
                          subtitle: '상태 전환(주행/출차요청/스킵)을 빠르게 수행합니다.',
                          child: Column(
                            children: [
                              if (isDrivingPrimary)
                                _GearShiftStartControl(
                                  cs: cs,
                                  icon: primaryIcon,
                                  title: primaryTitle,
                                  subtitle: primarySubtitle,
                                  enabled: gearEnabled,
                                  busy: _primaryBusy,
                                  latched: drivingLatched,
                                  blocked: gearBlocked,
                                  blockedBy: otherSelectedBy,
                                  threshold:
                                      _GearShiftStartControl.kDefaultThreshold,
                                  onEngage: onDriveEngage!,
                                  onComplete: onDriveComplete,
                                  onCancel: onDriveCancel,
                                ),
                              if (!isDrivingPrimary)
                                ParkingCompletedPrimaryCtaButton(
                                  colorScheme: cs,
                                  icon: primaryIcon,
                                  title: primaryTitle,
                                  subtitle: primarySubtitle,
                                  enabled: !_primaryBusy && !disableOthers,
                                  onPressed: primaryOnPressed,
                                ),
                              if (_type == PlateType.departureRequests) ...[
                                const SizedBox(height: 10),
                                ParkingCompletedPrimaryCtaButton(
                                  colorScheme: cs,
                                  icon: Icons.skip_next_rounded,
                                  title: '주행 스킵 후 출차 완료',
                                  subtitle: '주행 과정을 생략하고 바로 출차 완료로 변경합니다.',
                                  enabled: !_primaryBusy &&
                                      !disableOthers &&
                                      !_isOtherDriving,
                                  onPressed: _skipDepartureDrivingToCompleted,
                                  backgroundColor: _BrandTone.ok(cs),
                                  foregroundColor: cs.onTertiary,
                                ),
                              ],
                              if (_type == PlateType.parkingRequests) ...[
                                const SizedBox(height: 10),
                                ParkingCompletedPrimaryCtaButton(
                                  colorScheme: cs,
                                  icon: Icons.skip_next_rounded,
                                  title: '주행 스킵 후 입차 완료',
                                  subtitle:
                                      '주행 과정을 생략하고 바로 입차 완료로 변경합니다. (주차 구역 선택 필요)',
                                  enabled: !_primaryBusy &&
                                      !disableOthers &&
                                      !_isOtherDriving,
                                  onPressed:
                                      _skipEntryDrivingToParkingCompleted,
                                  backgroundColor: _BrandTone.ok(cs),
                                  foregroundColor: cs.onTertiary,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 140),
                          opacity: disableOthers ? 0.45 : 1,
                          child: AbsorbPointer(
                            absorbing: disableOthers,
                            child: ParkingCompletedSectionCard(
                              colorScheme: cs,
                              title: '기타',
                              subtitle: disableOthers
                                  ? '주행 중에는 다른 기능을 사용할 수 없습니다.'
                                  : '로그, 정산, 정보 수정, 상태 되돌리기, 삭제 등',
                              child: Column(
                                children: [
                                  GridView.count(
                                    crossAxisCount: 2,
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 2.6,
                                    children: tiles,
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ParkingCompletedDangerActionButton(
                                      colorScheme: cs,
                                      icon: Icons.delete_forever,
                                      label: '삭제',
                                      enabled: !_primaryBusy,
                                      onPressed: () async {
                                        final deleted = await widget.onDelete();
                                        if (!mounted) return;
                                        if (deleted) {
                                          Navigator.of(context).pop(true);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
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

class _GearShiftStartControl extends StatefulWidget {
  const _GearShiftStartControl({
    required this.cs,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onEngage,
    required this.onComplete,
    required this.onCancel,
    required this.enabled,
    required this.busy,
    required this.latched,
    required this.blocked,
    required this.blockedBy,
    this.threshold = kDefaultThreshold,
  });

  static const double kDefaultThreshold = 0.86;

  final ColorScheme cs;
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<bool> Function() onEngage;
  final Future<void> Function()? onComplete;
  final Future<void> Function()? onCancel;
  final bool enabled;
  final bool busy;
  final bool latched;
  final bool blocked;
  final String blockedBy;
  final double threshold;

  @override
  State<_GearShiftStartControl> createState() => _GearShiftStartControlState();
}

class _GearShiftStartControlState extends State<_GearShiftStartControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  bool _armedHapticSent = false;

  static const double _trackHeight = 124;
  static const double _trackWidth = 84;
  static const double _handleHeight = 46;
  static const double _pad = 12;
  static const double _slotWidth = 30;

  double get _travel => _trackHeight - (_pad * 2) - _handleHeight;

  double get _slotHeight => _trackHeight - (_pad * 2);

  bool get _armed => _ctrl.value >= widget.threshold;

  bool get _lockUp => widget.busy || widget.latched;

  bool get _dragEnabled =>
      widget.enabled && !widget.busy && !widget.latched && !widget.blocked;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
      value: (widget.busy || widget.latched) ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(covariant _GearShiftStartControl oldWidget) {
    super.didUpdateWidget(oldWidget);

    final target = _lockUp ? 1.0 : 0.0;

    if (oldWidget.busy != widget.busy || oldWidget.latched != widget.latched) {
      _armedHapticSent = false;
      _animateTo(target);
      return;
    }

    if (oldWidget.blocked != widget.blocked) {
      _armedHapticSent = false;
      if (widget.blocked && !_lockUp) {
        _animateTo(0);
      }
    }

    if (!widget.enabled && oldWidget.enabled) {
      _armedHapticSent = false;
      if (!_lockUp) _animateTo(0);
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
    if (!_dragEnabled) return;
    _armedHapticSent = false;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_dragEnabled) return;

    final delta = (-d.delta.dy) / _travel;
    final next = (_ctrl.value + delta).clamp(0.0, 1.0).toDouble();
    _ctrl.value = next;

    if (_armed && !_armedHapticSent) {
      _armedHapticSent = true;
      try {
        HapticFeedback.selectionClick();
      } catch (_) {}
    }

    if (!_armed) _armedHapticSent = false;
  }

  Future<void> _onDragEnd(DragEndDetails d) async {
    if (!_dragEnabled) return;

    if (_armed) {
      try {
        HapticFeedback.mediumImpact();
      } catch (_) {}

      await _animateTo(1);

      bool ok = false;
      try {
        ok = await widget.onEngage();
      } catch (_) {
        ok = false;
      }

      if (!mounted) return;

      if (!ok) {
        _armedHapticSent = false;
        await _animateTo(0);
      }
      return;
    }

    await _animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final p = _ctrl.value.clamp(0.0, 1.0).toDouble();
        final armed = _armed;

        final bg = Color.lerp(
          cs.primary.withOpacity(0.10),
          cs.primary.withOpacity(0.18),
          (armed || _lockUp) ? 1 : 0,
        )!;

        final border = Color.lerp(
          cs.primary.withOpacity(0.28),
          cs.primary.withOpacity(0.48),
          (armed || _lockUp) ? 1 : 0,
        )!;

        final hint = widget.blocked
            ? '다른 사용자가 주행 중입니다. (선점자: ${widget.blockedBy.isEmpty ? "—" : widget.blockedBy})'
            : (widget.busy
                ? '처리 중...'
                : (widget.latched
                    ? '주행 모드(락): 아래 버튼으로 완료/취소'
                    : (armed ? '놓으면 시작' : '기어를 위로 올려 START')));

        final handleTop = _pad + ((1 - p) * _travel);
        final fillH = (_slotHeight * p).clamp(0.0, _slotHeight).toDouble();
        final slotLeft = (_trackWidth - _slotWidth) / 2;

        final effectiveOpacity =
            (widget.enabled && !widget.blocked) ? 1.0 : 0.55;

        return Opacity(
          opacity: effectiveOpacity,
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
                      onVerticalDragStart: _dragEnabled ? _onDragStart : null,
                      onVerticalDragUpdate: _dragEnabled ? _onDragUpdate : null,
                      onVerticalDragEnd: _dragEnabled ? _onDragEnd : null,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                color: cs.surfaceContainerLow,
                                border:
                                    Border.all(color: _BrandTone.border(cs)),
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
                                'START',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                  color: (armed || _lockUp)
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
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
                              active: (armed || _lockUp),
                              busy: widget.busy,
                              latched: widget.latched,
                            ),
                          ),
                          if (widget.busy)
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
                      widget.latched
                          ? Icons.lock
                          : (widget.blocked
                              ? Icons.block
                              : (armed
                                  ? Icons.lock_open
                                  : Icons.keyboard_arrow_up)),
                      size: 18,
                      color:
                          (armed || _lockUp) ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        hint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: (armed || _lockUp)
                              ? cs.primary
                              : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.latched) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: (widget.busy || widget.onCancel == null)
                              ? null
                              : () async {
                                  try {
                                    HapticFeedback.selectionClick();
                                  } catch (_) {}
                                  await widget.onCancel!.call();
                                },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            side: BorderSide(color: cs.error.withOpacity(0.55)),
                            foregroundColor: cs.error,
                            backgroundColor:
                                cs.errorContainer.withOpacity(0.18),
                            textStyle: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w900),
                          ),
                          child: const Text('주행 취소'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: (widget.busy || widget.onComplete == null)
                              ? null
                              : () async {
                                  try {
                                    HapticFeedback.mediumImpact();
                                  } catch (_) {}
                                  await widget.onComplete!.call();
                                },
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            textStyle: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w900),
                          ),
                          child: const Text('주행 완료'),
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
    required this.latched,
  });

  final ColorScheme cs;
  final bool active;
  final bool busy;
  final bool latched;

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
        : (latched ? Icons.lock : Icons.drag_handle_rounded);

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
