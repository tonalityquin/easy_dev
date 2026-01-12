import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../models/plate_model.dart';

import '../../../../../states/area/area_state.dart';
import '../../../../../states/plate/lite_plate_state.dart';
import '../../../../../states/plate/movement_plate.dart';
import '../../../../../states/user/user_state.dart';
import '../../../../../enums/plate_type.dart';

import '../../../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../../../utils/snackbar_helper.dart';
import '../../../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../../../widgets/dialog/confirm_cancel_fee_dialog.dart';

// ✅ TTS (오프라인 TTS 사용)
import '../../../../../offlines/tts/offline_tts.dart';
import '../../../../common_package/log_package/log_viewer_bottom_sheet.dart';
import '../../../lite_modify_package/lite_modify_plate_screen.dart';

Future<void> showLiteParkingCompletedStatusBottomSheet({
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

class _FullHeightSheetState extends State<_FullHeightSheet> with SingleTickerProviderStateMixin {
  late PlateModel _plate;

  final ScrollController _scrollController = ScrollController();

  late final AnimationController _attentionCtrl;
  late final Animation<double> _attentionPulse;

  // ✅ “정산 없이 출차 완료” 2차 선택지 제공을 위한 상태
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

  /// ✅ 무료 판정: basicAmount == 0 && addAmount == 0
  bool get _isFreeBilling => (_plate.basicAmount ?? 0) == 0 && (_plate.addAmount ?? 0) == 0;

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

  /// ✅ Overlay 기반 커스텀 스낵바가 context/Overlay 구조에 따라 실패할 수 있으므로
  ///    1) showFailedSnackbar() 시도
  ///    2) 실패 시 ScaffoldMessenger SnackBar로 폴백
  void _showWarningSafe(String message) {
    // 1) 기존 커스텀 스낵바(Overlay 기반) 우선 시도
    try {
      showFailedSnackbar(context, message);
      return;
    } catch (_) {
      // no-op -> 아래 폴백
    }

    // 2) ScaffoldMessenger 폴백
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    // 3) 마지막 폴백: rootNavigator 쪽에서 다시 시도
    final nav = Navigator.of(context, rootNavigator: true);
    final messenger2 = ScaffoldMessenger.maybeOf(nav.context);
    if (messenger2 != null) {
      messenger2.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    // 4) 정말 최후: 다이얼로그(크래시 방지)
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
    // 1) 경고 (✅ 절대 크래시 나지 않게 Safe 경고)
    _showWarningSafe(message);

    // 2) 상단 이동(카드/정산 버튼이 화면에 보이도록)
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    }

    // 3) 임팩트 애니메이션(번호판 카드 + 정산 버튼)
    _attentionCtrl.forward(from: 0);
  }

  /// ✅ 무료면 자동 “사전정산(0원 잠금)” 처리
  /// - repo 업데이트
  /// - 로컬 상태 반영
  /// - logs 기록
  Future<bool> _autoPrebillFreeIfNeeded() async {
    if (_plate.isLockedFee == true) return true; // 이미 잠금(정산) 상태
    if (!_isFreeBilling) return false; // 무료가 아니면 여기서 처리하지 않음

    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final litePlateState = context.read<LitePlateState>();
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

      await litePlateState.liteUpdatePlateLocally(
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

      // 무료 자동 정산은 “정산 없이 진행” UX와 충돌하면 안 되므로 리셋
      _resetOverride();

      return true;
    } catch (e) {
      if (!mounted) return false;
      _showWarningSafe('무료 자동 정산 중 오류가 발생했습니다: $e');
      return false;
    }
  }

  Future<_DepartureOverrideChoice?> _showDepartureOverrideDialog() async {
    return showDialog<_DepartureOverrideChoice>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (_) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 헤더
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.28)),
                      ),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '정산 없이 출차 완료',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 메시지 카드(시트의 카드 톤)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '현재 사전 정산이 되어있지 않습니다.',
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.85),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '그래도 출차 완료로 이동하시겠습니까?',
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.70),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withOpacity(0.30)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.directions_car_filled, size: 16, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '차량: ${_plate.plateNumber}',
                                style: TextStyle(
                                  color: Colors.orange.shade800,
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

                // 버튼(중앙 정렬)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context, _DepartureOverrideChoice.cancel),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: const BorderSide(color: Colors.black12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      child: const Text(
                        '취소',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context, _DepartureOverrideChoice.goBilling),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blueAccent,
                        side: BorderSide(color: Colors.blueAccent.withOpacity(0.35)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        backgroundColor: Colors.blueAccent.withOpacity(0.06),
                      ),
                      child: const Text(
                        '정산하기',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _DepartureOverrideChoice.proceed),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      child: const Text(
                        '그래도 출차 완료',
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

  Future<void> _goDepartureCompleted() async {
    final movementPlate = context.read<MovementPlate>();
    await movementPlate.setDepartureCompletedDirectFromParkingCompleted(
      _plate.plateNumber,
      _plate.area,
      _plate.location,
    );

    // (기존 코드 유지)
    OfflineTts.instance.sayDepartureRequested(
      plateNumber: _plate.plateNumber,
    );

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    final isLocked = _plate.isLockedFee == true;
    final lockedFee = _plate.lockedFeeAmount;
    final paymentMethod = (_plate.paymentMethod ?? '').trim();
    final billingType = (_plate.billingType ?? '').trim();
    final location = (_plate.location).trim().isEmpty ? '미지정' : _plate.location.trim();

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const _SheetTitleRow(
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

                  final shakeDx = math.sin(_attentionCtrl.value * math.pi * 10) * (1 - _attentionCtrl.value) * 6;
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
                                      final litePlateState = context.read<LitePlateState>();
                                      final firestore = FirebaseFirestore.instance;

                                      final bt = (_plate.billingType ?? '').trim();
                                      if (bt.isEmpty) {
                                        _showWarningSafe('정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
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

                                        await litePlateState.liteUpdatePlateLocally(
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

                                        // ✅ 정산 성공 시, “정산 없이 진행” 상태 리셋
                                        _resetOverride();

                                        try {
                                          showSuccessSnackbar(
                                            context,
                                            '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})',
                                          );
                                        } catch (_) {
                                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})',
                                              ),
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
                                      final litePlateState = context.read<LitePlateState>();
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

                                        await litePlateState.liteUpdatePlateLocally(
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

                                        // ✅ 정산 취소 시 override는 리셋(다시 1차→2차 UX 유지)
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
                                // ✅ 정산 미완료 케이스
                                if (_needsBilling) {
                                  // ✅ 무료면: 자동 정산(0원 잠금) 후 바로 출차 완료
                                  if (_isFreeBilling) {
                                    final ok = await _autoPrebillFreeIfNeeded();
                                    if (!ok) return;
                                    await _goDepartureCompleted();
                                    return;
                                  }

                                  // 2차 클릭(유효 시간 내): 선택지 제공
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

                                    // cancel / null
                                    return;
                                  }

                                  // 1차 클릭: 경고 + 임팩트 + “다시 누르면 선택지” 안내
                                  _armOverride();
                                  await _triggerBillingRequiredAttention(
                                    message: '정산이 필요합니다. 먼저 정산을 진행하세요.\n'
                                        '정산 없이 출차 완료가 필요하면, 출차 완료 버튼을 한 번 더 누르세요.',
                                  );
                                  return;
                                }

                                // ✅ 정산 완료 상태면 기존 로직 그대로 수행
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
                                        builder: (_) => LiteModifyPlateScreen(
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
    return Row(
      children: [
        Icon(icon, color: Colors.blueAccent),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

  /// ✅ 0~1 (정산 필요 시 강조 애니메이션)
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
    final badgeColor = isLocked ? Colors.green : Colors.grey.shade600;
    final badgeText = isLocked ? '사전정산 잠김' : '사전정산 없음';

    final feeText =
    (isLocked && lockedFee != null) ? '₩$lockedFee${paymentMethod.isNotEmpty ? " ($paymentMethod)" : ""}' : '—';

    final billingText = billingType.isNotEmpty ? billingType : '미지정';

    final borderColor = Color.lerp(Colors.black12, Colors.orange, (attention * 0.9).clamp(0, 1))!;
    final bgColor =
    Color.lerp(Colors.grey.shade50, Colors.orange.withOpacity(0.06), (attention * 0.8).clamp(0, 1))!;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
          if (attention > 0.001)
            BoxShadow(
              color: Colors.orange.withOpacity(0.22 * attention),
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
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
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
                    fontWeight: FontWeight.w800,
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
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '정산이 필요합니다. 정산 후 출차 완료로 이동할 수 있습니다.',
                      style: TextStyle(
                        color: Colors.orange.shade800,
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
    final v = value.trim().isEmpty ? '—' : value.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          v,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 14,
            fontWeight: FontWeight.w700,
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12)),
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

  /// ✅ 0~1 강조(정산 버튼 임팩트)
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
    final Color base = (tone == _ActionTone.positive) ? Colors.green : Colors.grey.shade800;
    final Color bg = (tone == _ActionTone.positive) ? Colors.green.withOpacity(0.08) : Colors.grey.shade100;
    final Color border = (tone == _ActionTone.positive) ? Colors.green.withOpacity(0.25) : Colors.black12;

    final Color attentionBorder = Color.lerp(border, Colors.orange, (attention * 0.9).clamp(0, 1))!;
    final Color attentionBg = Color.lerp(bg, Colors.orange.withOpacity(0.10), (attention * 0.8).clamp(0, 1))!;

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
                  color: Colors.orange.withOpacity(0.22 * attention),
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
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
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
                  color: Colors.black.withOpacity(0.65),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (attention > 0.001) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '정산을 먼저 진행하세요',
                        style: TextStyle(
                          color: Colors.orange.shade800,
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
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
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
                      color: Colors.white.withOpacity(0.9),
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
    return OutlinedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 46),
        foregroundColor: Colors.black87,
        side: const BorderSide(color: Colors.black12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.grey.shade50,
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
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(icon, color: Colors.red.shade700),
        label: Text(label, style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w900)),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          side: BorderSide(color: Colors.red.shade200),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.red.withOpacity(0.04),
        ),
      ),
    );
  }
}

/// UsageReporter: 파이어베이스 DB 작업만 계측 (read / write / delete)
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
