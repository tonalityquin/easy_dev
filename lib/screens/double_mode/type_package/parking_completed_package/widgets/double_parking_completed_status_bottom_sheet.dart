import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../models/plate_model.dart';

import '../../../../../states/area/area_state.dart';
import '../../../../../states/plate/double_plate_state.dart';
import '../../../../../states/plate/movement_plate.dart';
import '../../../../../states/user/user_state.dart';
import '../../../../../enums/plate_type.dart';

import '../../../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../../../utils/snackbar_helper.dart';
import '../../../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../../../widgets/dialog/confirm_cancel_fee_dialog.dart';

import '../../../../common_package/log_package/log_viewer_bottom_sheet.dart';
import '../../../modify_package/double_modify_plate_screen.dart';

/// ✅ 추가: 다이얼로그/테이블에서 “콜백 없이” 바로 열기 위한 wrapper
Future<void> showDoubleParkingCompletedStatusBottomSheetFromDialog({
  required BuildContext context,
  required PlateModel plate,
}) async {
  await showDoubleParkingCompletedStatusBottomSheet(
    context: context,
    plate: plate,
    onRequestEntry: () async {
      final area = context.read<AreaState>().currentArea;
      await handleEntryParkingRequest(context, plate.plateNumber, area);
    },
    onDelete: () {
      try {
        showFailedSnackbar(context, '이 경로에서는 삭제 기능을 사용할 수 없습니다.');
      } catch (_) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('이 경로에서는 삭제 기능을 사용할 수 없습니다.')),
        );
      }
    },
  );
}

Future<void> showDoubleParkingCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  required Future<void> Function() onRequestEntry,
  required VoidCallback onDelete,
}) async {
  final plateNumber = plate.plateNumber;
  final division = context.read<UserState>().division;
  final area = context.read<AreaState>().currentArea;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
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
  final VoidCallback onDelete;

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
        tween: Tween<double>(begin: 0, end: 1).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 0).chain(CurveTween(curve: Curves.easeInCubic)),
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
    if (!_departureOverrideArmed || _departureOverrideArmedAt == null) return false;
    return DateTime.now().difference(_departureOverrideArmedAt!) <= _overrideWindow;
  }

  void _resetOverride() {
    _departureOverrideArmed = false;
    _departureOverrideArmedAt = null;
  }

  void _armOverride() {
    _departureOverrideArmed = true;
    _departureOverrideArmedAt = DateTime.now();
  }

  void _showWarningSafe(String message) {
    try {
      showFailedSnackbar(context, message);
      return;
    } catch (_) {}

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final nav = Navigator.of(context, rootNavigator: true);
    final messenger2 = ScaffoldMessenger.maybeOf(nav.context);
    if (messenger2 != null) {
      messenger2.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    showDialog<void>(
      context: nav.context,
      builder: (_) => AlertDialog(
        title: const Text('안내'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(nav.context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerBillingRequiredAttention({
    required String message,
  }) async {
    _showWarningSafe(message);

    if (_scrollController.hasClients) {
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
    final firestore = FirebaseFirestore.instance;

    final now = DateTime.now();
    final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;

    final updatedPlate = _plate.copyWith(
      isLockedFee: true,
      lockedAtTimeInSeconds: currentTime,
      lockedFeeAmount: 0,
      paymentMethod: '무료',
    );

    try {
      await repo.addOrUpdatePlate(_plate.id, updatedPlate);
      _reportDbSafe(
        area: _plate.area,
        action: 'write',
        source: 'parkingCompletedStatus.freeAutoPrebill.repo.addOrUpdatePlate',
        n: 1,
      );

      await plateState.doubleUpdatePlateLocally(
        PlateType.parkingCompleted,
        updatedPlate,
      );

      final log = {
        'action': '무료 자동 정산',
        'performedBy': userName,
        'timestamp': now.toIso8601String(),
        'lockedFee': 0,
        'paymentMethod': '무료',
      };

      await firestore.collection('plates').doc(_plate.id).update({
        'logs': FieldValue.arrayUnion([log]),
      });
      _reportDbSafe(
        area: _plate.area,
        action: 'write',
        source: 'parkingCompletedStatus.freeAutoPrebill.plates.update.logs.arrayUnion',
        n: 1,
      );

      if (!mounted) return false;
      setState(() => _plate = updatedPlate);

      _resetOverride();

      return true;
    } catch (e) {
      if (!mounted) return false;
      _showWarningSafe('무료 자동 정산 중 오류가 발생했습니다: $e');
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
        final cs2 = Theme.of(context).colorScheme;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: cs2.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs2.outlineVariant.withOpacity(0.85)),
              boxShadow: [
                BoxShadow(
                  color: cs2.shadow.withOpacity(0.12),
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
                        color: cs2.errorContainer.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs2.error.withOpacity(0.28)),
                      ),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: cs2.onErrorContainer,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '정산 없이 출차 완료',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: cs2.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs2.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs2.outlineVariant.withOpacity(0.85)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '현재 사전 정산이 되어있지 않습니다.',
                        style: TextStyle(
                          color: cs2.onSurface,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '그래도 출차 완료로 이동하시겠습니까?',
                        style: TextStyle(
                          color: cs2.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: cs2.errorContainer.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs2.error.withOpacity(0.30)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.directions_car_filled, size: 16, color: cs2.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '차량: ${_plate.plateNumber}',
                                style: TextStyle(
                                  color: cs2.onSurface,
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
                      onPressed: () => Navigator.pop(context, _DepartureOverrideChoice.cancel),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs2.onSurface,
                        side: BorderSide(color: cs2.outlineVariant.withOpacity(0.85)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      child: const Text('취소', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context, _DepartureOverrideChoice.goBilling),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs2.primary,
                        side: BorderSide(color: cs2.primary.withOpacity(0.35)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        backgroundColor: cs2.primary.withOpacity(0.06),
                      ),
                      child: const Text('정산하기', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _DepartureOverrideChoice.proceed),
                      style: FilledButton.styleFrom(
                        backgroundColor: cs2.error,
                        foregroundColor: cs2.onError,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      child: const Text('그래도 출차 완료', style: TextStyle(fontWeight: FontWeight.w900)),
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

  Future<void> _goDepartureCompleted() async {
    final movementPlate = context.read<MovementPlate>();
    await movementPlate.setDepartureCompletedDirectFromParkingCompleted(
      _plate.plateNumber,
      _plate.area,
      _plate.location,
    );

    if (!mounted) return;
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
    final location = (_plate.location).trim().isEmpty ? '미지정' : _plate.location.trim();

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
                        color: cs.outlineVariant.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  _SheetTitleRow(
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

                  final shakeDx = math.sin(_attentionCtrl.value * math.pi * 10) *
                      (1 - _attentionCtrl.value) *
                      6;
                  final scale = 1 + (attention * 0.012);

                  return ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      Transform.translate(
                        offset: Offset(_needsBilling ? shakeDx : 0, 0),
                        child: Transform.scale(
                          scale: _needsBilling ? scale : 1,
                          child: _PlateSummaryCard(
                            plateNumber: widget.plateNumber,
                            area: _plate.area,
                            location: location,
                            billingType: billingType,
                            isLocked: isLocked,
                            lockedFee: lockedFee,
                            paymentMethod: paymentMethod,
                            attention: _needsBilling ? attention : 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: '핵심 작업',
                        subtitle: '자주 사용하는 기능을 상단에 배치했습니다.',
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _ActionTileButton(
                                    icon: Icons.receipt_long,
                                    title: '정산',
                                    subtitle: '사전 정산',
                                    tone: _ActionTone.positive,
                                    attention: _needsBilling ? attention : 0,
                                    onTap: () async {
                                      final userName = context.read<UserState>().name;
                                      final repo = context.read<PlateRepository>();
                                      final plateState = context.read<DoublePlateState>();
                                      final firestore = FirebaseFirestore.instance;

                                      final bt = (_plate.billingType ?? '').trim();
                                      if (bt.isEmpty) {
                                        _showWarningSafe('정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
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
                                        await repo.addOrUpdatePlate(_plate.id, updatedPlate);
                                        _reportDbSafe(
                                          area: _plate.area,
                                          action: 'write',
                                          source: 'parkingCompletedStatus.prebill.repo.addOrUpdatePlate',
                                          n: 1,
                                        );

                                        await plateState.doubleUpdatePlateLocally(
                                          PlateType.parkingCompleted,
                                          updatedPlate,
                                        );

                                        final log = {
                                          'action': '사전 정산',
                                          'performedBy': userName,
                                          'timestamp': now.toIso8601String(),
                                          'lockedFee': result.lockedFee,
                                          'paymentMethod': result.paymentMethod,
                                          if (result.reason != null && result.reason!.trim().isNotEmpty)
                                            'reason': result.reason!.trim(),
                                        };
                                        await firestore.collection('plates').doc(_plate.id).update({
                                          'logs': FieldValue.arrayUnion([log]),
                                        });
                                        _reportDbSafe(
                                          area: _plate.area,
                                          action: 'write',
                                          source: 'parkingCompletedStatus.prebill.plates.update.logs.arrayUnion',
                                          n: 1,
                                        );

                                        if (!mounted) return;

                                        setState(() => _plate = updatedPlate);

                                        _resetOverride();

                                        try {
                                          showSuccessSnackbar(
                                            context,
                                            '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})',
                                          );
                                        } catch (_) {
                                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                            SnackBar(
                                              content: Text('사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})'),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (!mounted) return;
                                        _showWarningSafe('사전 정산 중 오류가 발생했습니다: $e');
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _ActionTileButton(
                                    icon: Icons.lock_open,
                                    title: '정산 취소',
                                    subtitle: isLocked ? '잠금 해제' : '잠금 아님',
                                    tone: _ActionTone.neutral,
                                    badgeText: isLocked ? '잠김' : '비잠김',
                                    onTap: () async {
                                      final userName = context.read<UserState>().name;
                                      final repo = context.read<PlateRepository>();
                                      final plateState = context.read<DoublePlateState>();
                                      final firestore = FirebaseFirestore.instance;

                                      if (_plate.isLockedFee != true) {
                                        _showWarningSafe('현재 사전 정산 상태가 아닙니다.');
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
                                        await repo.addOrUpdatePlate(_plate.id, updatedPlate);
                                        _reportDbSafe(
                                          area: _plate.area,
                                          action: 'write',
                                          source: 'parkingCompletedStatus.unlock.repo.addOrUpdatePlate',
                                          n: 1,
                                        );

                                        await plateState.doubleUpdatePlateLocally(
                                          PlateType.parkingCompleted,
                                          updatedPlate,
                                        );

                                        final cancelLog = {
                                          'action': '사전 정산 취소',
                                          'performedBy': userName,
                                          'timestamp': now.toIso8601String(),
                                        };
                                        await firestore.collection('plates').doc(_plate.id).update({
                                          'logs': FieldValue.arrayUnion([cancelLog]),
                                        });
                                        _reportDbSafe(
                                          area: _plate.area,
                                          action: 'write',
                                          source: 'parkingCompletedStatus.unlock.plates.update.logs.arrayUnion',
                                          n: 1,
                                        );

                                        if (!mounted) return;

                                        setState(() => _plate = updatedPlate);

                                        _resetOverride();

                                        try {
                                          showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
                                        } catch (_) {
                                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                            const SnackBar(content: Text('사전 정산이 취소되었습니다.')),
                                          );
                                        }
                                      } catch (e) {
                                        if (!mounted) return;
                                        _showWarningSafe('정산 취소 중 오류가 발생했습니다: $e');
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _PrimaryCtaButton(
                              icon: Icons.exit_to_app,
                              title: '출차 완료로 이동',
                              subtitle: '차량을 출차 완료 상태로 전환합니다.',
                              onPressed: () async {
                                if (_needsBilling) {
                                  if (_isFreeBilling) {
                                    final ok = await _autoPreBillFreeIfNeeded();
                                    if (!ok) return;
                                    await _goDepartureCompleted();
                                    return;
                                  }

                                  if (_overrideActive) {
                                    _resetOverride();

                                    final choice = await _showDepartureOverrideDialog();
                                    if (!mounted) return;

                                    if (choice == _DepartureOverrideChoice.proceed) {
                                      await _goDepartureCompleted();
                                      return;
                                    }

                                    if (choice == _DepartureOverrideChoice.goBilling) {
                                      await _triggerBillingRequiredAttention(
                                        message: '정산을 진행해주세요. 정산 후 출차 완료로 이동할 수 있습니다.',
                                      );
                                      return;
                                    }

                                    return;
                                  }

                                  _armOverride();
                                  await _triggerBillingRequiredAttention(
                                    message:
                                    '정산이 필요합니다. 먼저 정산을 진행하세요.\n정산 없이 출차 완료가 필요하면, 출차 완료 버튼을 한 번 더 누르세요.',
                                  );
                                  return;
                                }

                                _resetOverride();
                                await _goDepartureCompleted();
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: '기타',
                        subtitle: '로그 확인, 정보 수정, 삭제 등',
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
                                _SecondaryActionButton(
                                  icon: Icons.history,
                                  label: '로그 확인',
                                  onPressed: () {
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
                                _SecondaryActionButton(
                                  icon: Icons.edit_note_outlined,
                                  label: '정보 수정',
                                  onPressed: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      rootContext,
                                      MaterialPageRoute(
                                        builder: (_) => DoubleModifyPlateScreen(
                                          plate: _plate,
                                          collectionKey: PlateType.parkingCompleted,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _DangerActionButton(
                              icon: Icons.delete_forever,
                              label: '삭제',
                              onPressed: () {
                                Navigator.pop(context);
                                widget.onDelete();
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
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

class _SheetTitleRow extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SheetTitleRow({
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}
class _PlateSummaryCard extends StatelessWidget {
  final String plateNumber;
  final String area;
  final String location;
  final String billingType;
  final bool isLocked;
  final int? lockedFee;
  final String paymentMethod;
  final double attention;

  const _PlateSummaryCard({
    required this.plateNumber,
    required this.area,
    required this.location,
    required this.billingType,
    required this.isLocked,
    required this.lockedFee,
    required this.paymentMethod,
    this.attention = 0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final badgeColor = isLocked ? cs.tertiary : cs.onSurfaceVariant;
    final badgeText = isLocked ? '사전정산 잠김' : '사전정산 없음';

    final feeText = (isLocked && lockedFee != null)
        ? '₩$lockedFee${paymentMethod.isNotEmpty ? " ($paymentMethod)" : ""}'
        : '—';

    final billingText = billingType.isNotEmpty ? billingType : '미지정';

    final borderColor = Color.lerp(
      cs.outlineVariant,
      cs.error,
      (attention * 0.9).clamp(0, 1),
    )!;
    final bgColor = Color.lerp(
      cs.surfaceContainerLow,
      cs.errorContainer.withOpacity(0.35),
      (attention * 0.8).clamp(0, 1),
    )!;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
          if (attention > 0.001)
            BoxShadow(
              color: cs.error.withOpacity(0.18 * attention),
              blurRadius: 18 * attention,
              spreadRadius: 1 * attention,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plateNumber,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeColor.withOpacity(0.35)),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (attention > 0.001 && !isLocked) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.errorContainer.withOpacity(0.45),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.error.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: cs.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '정산이 필요합니다. 정산 후 출차 완료로 이동할 수 있습니다.',
                      style: TextStyle(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              Expanded(child: _InfoLine(label: '지역', value: area)),
              const SizedBox(width: 12),
              Expanded(child: _InfoLine(label: '위치', value: location)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _InfoLine(label: '정산 타입', value: billingText)),
              const SizedBox(width: 12),
              Expanded(child: _InfoLine(label: '잠금 금액', value: feeText)),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = value.trim().isEmpty ? '—' : value.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          v,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: cs.onSurface)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

enum _ActionTone { positive, neutral }

class _ActionTileButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final _ActionTone tone;
  final String? badgeText;
  final VoidCallback onTap;
  final double attention;

  const _ActionTileButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tone,
    required this.onTap,
    this.badgeText,
    this.attention = 0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color base = (tone == _ActionTone.positive) ? cs.tertiary : cs.onSurface;
    final Color bg = (tone == _ActionTone.positive)
        ? cs.tertiaryContainer.withOpacity(0.55)
        : cs.surfaceContainerLow;
    final Color border = (tone == _ActionTone.positive)
        ? cs.tertiary.withOpacity(0.25)
        : cs.outlineVariant.withOpacity(0.85);

    final Color attentionBorder = Color.lerp(border, cs.error, (attention * 0.9).clamp(0, 1))!;
    final Color attentionBg = Color.lerp(bg, cs.errorContainer.withOpacity(0.35), (attention * 0.8).clamp(0, 1))!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: attentionBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: attentionBorder, width: 1.2),
            boxShadow: [
              if (attention > 0.001)
                BoxShadow(
                  color: cs.error.withOpacity(0.18 * attention),
                  blurRadius: 16 * attention,
                  spreadRadius: 1 * attention,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: base),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: cs.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (badgeText != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: base.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: base.withOpacity(0.25)),
                      ),
                      child: Text(
                        badgeText!,
                        style: TextStyle(
                          color: base,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (attention > 0.001) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.arrow_forward_rounded, size: 16, color: cs.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '정산을 먼저 진행하세요',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryCtaButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onPressed;

  const _PrimaryCtaButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        onPressed: () async => onPressed(),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimary.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _SecondaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _SecondaryActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return OutlinedButton.icon(
      icon: Icon(icon, size: 18, color: cs.onSurface),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 46),
        foregroundColor: cs.onSurface,
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: cs.surfaceContainerLow,
      ),
    );
  }
}

class _DangerActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _DangerActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(icon, color: cs.error),
        label: Text(
          label,
          style: TextStyle(color: cs.error, fontWeight: FontWeight.w900),
        ),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          side: BorderSide(color: cs.error.withOpacity(0.35)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: cs.errorContainer.withOpacity(0.45),
        ),
      ),
    );
  }
}

void _reportDbSafe({
  required String area,
  required String action,
  required String source,
  int n = 1,
}) {
  try {
    /*UsageReporter.instance.report(
      area: area.trim(),
      action: action,
      n: n,
      source: source,
    );*/
  } catch (_) {}
}

Future<void> handleEntryParkingRequest(
    BuildContext context,
    String plateNumber,
    String area,
    ) async {
  final movementPlate = context.read<MovementPlate>();
  await movementPlate.goBackToParkingRequest(
    fromType: PlateType.parkingCompleted,
    plateNumber: plateNumber,
    area: area,
    newLocation: "미지정",
  );
}
