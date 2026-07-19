import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
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
import '../../../../shared/plate/widgets/log_viewer_bottom_sheet.dart';
import '../../../../shared/plate/widgets/parking_completed_prompt_dialog.dart';
import '../../../../shared/plate/widgets/parking_completed_status_widgets.dart';

Future<bool> _showDeleteDialog(BuildContext context, PlateModel plate) async {
  return showParkingCompletedDeleteDialog(context, plate);
}

Future<void> showDoubleParkingCompletedStatusBottomSheetFromDialog({
  required BuildContext context,
  required PlateModel plate,
  bool popParentOnDelete = true,
}) async {
  final deleted = await showDoubleParkingCompletedStatusBottomSheet(
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

Future<bool?> showDoubleParkingCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  required Future<void> Function() onRequestEntry,
  required Future<bool> Function() onDelete,
}) async {
  final plateNumber = plate.plateNumber;
  final division = context.read<UserState>().division;
  final area = context.read<AreaState>().currentArea;

  return showPromptOverlayBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    transparentBackground: true,
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

  final GlobalKey _billingRowKey = GlobalKey();

  bool _primaryBusy = false;

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

  bool get _needsBilling => _plate.isLockedFee != true;

  bool get _isFreeBilling =>
      (_plate.basicAmount ?? 0) == 0 && (_plate.addAmount ?? 0) == 0;

  bool get _overrideActive {
    if (!_departureOverrideArmed || _departureOverrideArmedAt == null) {
      return false;
    }
    return DateTime.now().difference(_departureOverrideArmedAt!) <=
        _overrideWindow;
  }

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

  void _resetOverride() {
    _departureOverrideArmed = false;
    _departureOverrideArmedAt = null;
  }

  void _armOverride() {
    _departureOverrideArmed = true;
    _departureOverrideArmedAt = DateTime.now();
  }

  Future<void> _triggerBillingRequiredAttention({
    required String message,
  }) async {
    final ctx = _billingRowKey.currentContext;
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

  Future<bool> _autoPreBillFreeIfNeeded() async {
    if (_plate.isLockedFee == true) return true;
    if (!_isFreeBilling) return false;

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

      _resetOverride();
      return true;
    } catch (e) {
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
    final movementPlate = context.read<MovementPlate>();
    await movementPlate.setDepartureCompletedDirectFromParkingCompleted(
      _plate.plateNumber,
      _plate.area,
      _effectiveLocation,
    );

    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _handlePrebill() async {
    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final plateState = context.read<DoublePlateState>();

    final bt = (_plate.billingType ?? '').trim();
    if (bt.isEmpty) {
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

    final updatedPlate = _plate.copyWith(
      isLockedFee: true,
      lockedAtTimeInSeconds: currentTime,
      lockedFeeAmount: result.lockedFee,
      paymentMethod: result.paymentMethod,
    );

    try {
      await repo.settlePlateBilling(
        documentId: _plateDocId,
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

      final refreshedPlate = await repo.getPlate(_plateDocId) ?? updatedPlate;

      await plateState.doubleUpdatePlateLocally(
        PlateType.parkingCompleted,
        refreshedPlate,
      );

      if (!mounted) return;

      setState(() => _plate = refreshedPlate);
      _resetOverride();
    } catch (e) {
      if (!mounted) return;
    }
  }

  Future<void> _handleCancelPrebill() async {
    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final plateState = context.read<DoublePlateState>();

    if (_plate.isLockedFee != true) {
      return;
    }

    final confirm = await showPromptOverlayDialog<bool>(
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
      _resetOverride();
    } catch (e) {
      if (!mounted) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    final isLocked = _plate.isLockedFee == true;
    final lockedFee = _plate.lockedFeeAmount;
    final paymentMethod = (_plate.paymentMethod ?? '').trim();
    final billingType = (_plate.billingType ?? '').trim();
    final location = _effectiveLocation;

    final statusMemo = resolveParkingCompletedStatusMemo(_plate);

    return SafeArea(
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
                  const ParkingCompletedSheetTitleRow(
                    title: '입차 완료 상태 처리',
                    icon: Icons.settings,
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

                  return ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                                            ParkingCompletedPlateSummaryCard(
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
                      const SizedBox(height: 14),
                      ParkingCompletedSectionCard(
                        title: '핵심 작업',
                        subtitle: '차량 상태를 출차 완료로 전환합니다.',
                        child: Column(
                          children: [
                            ParkingCompletedPrimaryCtaButton(
                              icon: Icons.exit_to_app,
                              title: '출차 완료로 이동',
                              subtitle: '차량을 출차 완료 상태로 전환합니다.',
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              onPressed: () async {
                                await _runPrimary(() async {
                                  if (_needsBilling) {
                                    if (_isFreeBilling) {
                                      final ok =
                                          await _autoPreBillFreeIfNeeded();
                                      if (!ok) return;
                                      await _goDepartureCompleted();
                                      return;
                                    }

                                    if (_overrideActive) {
                                      _resetOverride();

                                      final choice =
                                          await _showDepartureOverrideDialog();
                                      if (!mounted) return;

                                      if (choice ==
                                          ParkingCompletedOverrideChoice.proceed) {
                                        await _goDepartureCompleted();
                                        return;
                                      }

                                      if (choice ==
                                          ParkingCompletedOverrideChoice.goBilling) {
                                        await _triggerBillingRequiredAttention(
                                          message:
                                              '정산을 진행해주세요. 정산 후 출차 완료로 이동할 수 있습니다.',
                                        );
                                        return;
                                      }

                                      return;
                                    }

                                    _armOverride();
                                    await _triggerBillingRequiredAttention(
                                      message: '정산이 필요합니다. 먼저 정산을 진행하세요.\n'
                                          '정산 없이 출차 완료가 필요하면, 출차 완료 버튼을 한 번 더 누르세요.',
                                    );
                                    return;
                                  }

                                  _resetOverride();
                                  await _goDepartureCompleted();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      ParkingCompletedSectionCard(
                        title: '기타',
                        subtitle: '로그 확인, 정보 수정, 정산/취소, 삭제 등',
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
                                ParkingCompletedSecondaryActionButton(
                                  icon: Icons.history,
                                  label: '로그 확인',
                                  onPressed: () async {
                                    await LogViewerBottomSheet.show(
                                      context,
                                      initialPlateNumber: widget.plateNumber,
                                      division: widget.division,
                                      area: widget.area,
                                      requestTime: _plate.requestTime,
                                      plateId: _plate.id.trim().isEmpty
                                          ? null
                                          : _plate.id.trim(),
                                    );
                                  },
                                ),
                                ParkingCompletedSecondaryActionButton(
                                  icon: Icons.edit_note_outlined,
                                  label: '정보 수정',
                                  onPressed: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      rootContext,
                                      MaterialPageRoute(
                                        builder: (_) => ModifyPlateScreen(
                                          plate: _plate,
                                          collectionKey:
                                              PlateType.parkingCompleted,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                KeyedSubtree(
                                  key: _billingRowKey,
                                  child: ParkingCompletedSecondaryActionButton(
                                    icon: Icons.receipt_long,
                                    label: '정산',
                                    badgeText: _needsBilling ? '필수' : null,
                                    backgroundColor: _needsBilling
                                        ? cs.errorContainer.withOpacity(0.35)
                                        : cs.surfaceContainerLow,
                                    borderColor: _needsBilling
                                        ? cs.error.withOpacity(0.45)
                                        : cs.outlineVariant.withOpacity(0.85),
                                    foregroundColor:
                                        _needsBilling ? cs.error : cs.onSurface,
                                    attention: _needsBilling ? attention : 0,
                                    onPressed: () async =>
                                        _runPrimary(_handlePrebill),
                                  ),
                                ),
                                ParkingCompletedSecondaryActionButton(
                                  icon: Icons.lock_open,
                                  label: '정산 취소',
                                  badgeText: isLocked ? '잠김' : '비잠김',
                                  backgroundColor: isLocked
                                      ? cs.tertiaryContainer.withOpacity(0.45)
                                      : cs.surfaceContainerLow,
                                  borderColor: isLocked
                                      ? cs.tertiary.withOpacity(0.35)
                                      : cs.outlineVariant.withOpacity(0.85),
                                  foregroundColor:
                                      isLocked ? cs.tertiary : cs.onSurface,
                                  onPressed: () async =>
                                      _runPrimary(_handleCancelPrebill),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ParkingCompletedDangerActionButton(
                              icon: Icons.delete_forever,
                              label: '삭제',
                              onPressed: () async {
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
                      const SizedBox(height: 10),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
