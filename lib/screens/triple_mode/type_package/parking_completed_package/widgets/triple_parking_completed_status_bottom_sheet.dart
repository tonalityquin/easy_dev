import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../models/plate_model.dart';

import '../../../../../states/area/area_state.dart';
import '../../../../../states/plate/triple_plate_state.dart';
import '../../../../../states/plate/movement_plate.dart';
import '../../../../../states/user/user_state.dart';
import '../../../../../enums/plate_type.dart';

import '../../../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../../../utils/snackbar_helper.dart';
import '../../../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../../../widgets/dialog/confirm_cancel_fee_dialog.dart';

import '../../../../common_package/log_package/log_viewer_bottom_sheet.dart';
import '../../../modify_package/triple_modify_plate_screen.dart';

/// ✅ 추가: 다이얼로그/테이블에서 “콜백 없이” 바로 열기 위한 wrapper
/// - 기존 showTripleParkingCompletedStatusBottomSheet 시그니처(콜백 required)는 유지
Future<void> showTripleParkingCompletedStatusBottomSheetFromDialog({
  required BuildContext context,
  required PlateModel plate,
}) async {
  await showTripleParkingCompletedStatusBottomSheet(
    context: context,
    plate: plate,
    onRequestEntry: () async {
      final area = context.read<AreaState>().currentArea;
      await handleEntryParkingRequest(context, plate.plateNumber, area);
    },
    onDelete: () {
      // 테이블 상세 → 작업 수행 경로에서는 삭제 기본 비활성화(정책 유지)
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

Future<void> showTripleParkingCompletedStatusBottomSheet({
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
enum _DrivingResult { completed, cancelled, failed }

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

  PlateType? get _type => _plate.typeEnum;

  /// ✅ (기능 유지) parkingCompleted인데 아직 사전정산(잠금) 아니면 billing 필요
  bool get _needsBilling =>
      (_type == PlateType.parkingCompleted) && (_plate.isLockedFee != true);

  /// ✅ 무료 판정: basicAmount == 0 && addAmount == 0
  bool get _isFreeBilling =>
      (_plate.basicAmount ?? 0) == 0 && (_plate.addAmount ?? 0) == 0;

  /// ✅ 앱 강제 종료/재실행 등으로 '주행 중(선점)' 상태가 남아있을 때,
  /// 동일 사용자가 다시 진입하면 UI 문구를 '시작'이 아닌 '계속'으로 노출합니다.
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

  String _plateDocId() {
    if (_plate.id.trim().isNotEmpty) return _plate.id.trim();
    return '${_plate.plateNumber}_${_plate.area}';
  }

  String get _effectiveLocation =>
      _plate.location.trim().isEmpty ? '미지정' : _plate.location.trim();

  Future<void> _runPrimary(Future<void> Function() fn) async {
    if (_primaryBusy) return;
    setState(() => _primaryBusy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _primaryBusy = false);
    }
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

  Future<void> _triggerBillingRequiredAttention({required String message}) async {
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

  Future<bool> _autoPrebillFreeIfNeeded() async {
    if (_plate.isLockedFee == true) return true;
    if (!_isFreeBilling) return false;

    final userName = context.read<UserState>().name;
    final repo = context.read<PlateRepository>();
    final plateState = context.read<TriplePlateState>();
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

      await plateState.tripleUpdatePlateLocally(
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
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.error.withOpacity(0.30)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.directions_car_filled, size: 16, color: cs.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '차량: ${_plate.plateNumber}',
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
                      onPressed: () => Navigator.pop(context, _DepartureOverrideChoice.cancel),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.onSurface,
                        side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      child: const Text('취소', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context, _DepartureOverrideChoice.goBilling),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.primary,
                        side: BorderSide(color: cs.primary.withOpacity(0.35)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        backgroundColor: cs.primaryContainer.withOpacity(0.35),
                      ),
                      child: const Text('정산하기', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _DepartureOverrideChoice.proceed),
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.error,
                        foregroundColor: cs.onError,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      child: const Text('그래도 출차 요청', style: TextStyle(fontWeight: FontWeight.w900)),
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

  /// ✅ 신규: "주행 스킵 → 바로 출차 완료" 타입 전환
  /// - departure_requests 상태에서만 허용
  /// - 다른 사용자가 이미 선점(주행 중)인 경우에는 차단(정합성/충돌 방지)
  /// - 주행 다이얼로그 없이 곧바로 departure_completed로 transition
  Future<void> _skipDepartureDrivingToCompleted() async {
    await _runPrimary(() async {
      if (_type != PlateType.departureRequests) {
        _showWarningSafe('현재 상태에서는 출차 완료 처리(스킵)가 불가능합니다.');
        return;
      }

      final userName = context.read<UserState>().name;
      final selectedBy = (_plate.selectedBy ?? '').trim();

      if (_plate.isSelected == true &&
          selectedBy.isNotEmpty &&
          selectedBy != userName) {
        _showWarningSafe('다른 사용자가 이미 주행 중입니다. (선택자: $selectedBy)');
        return;
      }

      final movementPlate = context.read<MovementPlate>();

      try {
        await movementPlate.setDepartureCompleted(_plate);

        if (!mounted) return;

        // UI 정리(선점 표시가 남아있다면 정리)
        setState(() {
          _plate = _plate.copyWith(isSelected: false, selectedBy: null);
        });

        try {
          showSuccessSnackbar(context, '주행을 스킵하고 출차 완료로 변경했습니다.');
        } catch (_) {}

        Navigator.pop(context);
      } on FirebaseException catch (e) {
        _showWarningSafe('출차 완료 처리 실패: ${e.message ?? e.code}');
      } catch (e) {
        _showWarningSafe('출차 완료 처리 실패: $e');
      }
    });
  }

  Future<void> _logDrivingCancel({
    required String plateId,
    required String phase,
    required String userName,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final now = DateTime.now();
    final cancelLog = {
      'action': '주행 취소',
      'performedBy': userName,
      'timestamp': now.toIso8601String(),
      'phase': phase,
    };

    await firestore.collection('plates').doc(plateId).update({
      'logs': FieldValue.arrayUnion([cancelLog]),
    });
  }

  Future<_DrivingResult> _showDrivingBlockingDialog({
    required String message,
    required bool canCancel,
    required String cancelDisabledHint,
    required Future<void> Function() onComplete,
    required Future<void> Function() onCancel,
  }) async {
    Object? err;

    final result = await showDialog<_DrivingResult>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Theme.of(context).colorScheme.scrim.withOpacity(0.55),
      builder: (_) => PopScope(
        canPop: false,
        child: _DrivingBlockingDialog(
          message: message,
          canCancel: canCancel,
          cancelDisabledHint: cancelDisabledHint,
          onComplete: () async {
            try {
              await onComplete();
              return _DrivingResult.completed;
            } catch (e) {
              err = e;
              return _DrivingResult.failed;
            }
          },
          onCancel: () async {
            try {
              await onCancel();
              return _DrivingResult.cancelled;
            } catch (e) {
              err = e;
              return _DrivingResult.failed;
            }
          },
        ),
      ),
    );

    final r = result ?? _DrivingResult.failed;
    if (r == _DrivingResult.failed && err != null) {
      _showWarningSafe('주행 처리 실패: $err');
    }
    return r;
  }

  Future<void> _startEntryDriving() async {
    await _runPrimary(() async {
      if (_type != PlateType.parkingRequests) {
        _showWarningSafe('현재 상태에서는 입차 주행 시작이 불가능합니다.');
        return;
      }

      final userName = context.read<UserState>().name;
      final selectedBy = (_plate.selectedBy ?? '').trim();
      if (_plate.isSelected == true && selectedBy.isNotEmpty && selectedBy != userName) {
        _showWarningSafe('다른 사용자가 이미 주행 중입니다. (선택자: $selectedBy)');
        return;
      }

      final repo = context.read<PlateRepository>();
      final movementPlate = context.read<MovementPlate>();
      final plateState = context.read<TriplePlateState>();
      final id = _plateDocId();

      try {
        // 1) 주행 시작(선점)
        await repo.recordWhoPlateClick(
          id,
          true,
          selectedBy: userName,
          area: _plate.area,
        );

        if (mounted) {
          setState(() {
            _plate = _plate.copyWith(
              isSelected: true,
              selectedBy: userName,
            );
          });
        }

        // 2) 블로킹 다이얼로그 (완료/취소)
        final canCancel = ((_plate.selectedBy ?? '').trim() == userName);
        final result = await _showDrivingBlockingDialog(
          message: '입차 주행 중입니다.',
          canCancel: canCancel,
          cancelDisabledHint: '선점자만 주행 취소가 가능합니다.',
          onComplete: () async {
            await movementPlate.setParkingCompleted(
              _plate.plateNumber,
              _plate.area,
              _effectiveLocation,
            );
          },
          onCancel: () async {
            final currentSelectedBy = (_plate.selectedBy ?? '').trim();
            if (currentSelectedBy != userName) {
              throw StateError('권한 없음: 선점자만 취소 가능');
            }

            await repo.recordWhoPlateClick(
              id,
              false,
              area: _plate.area,
            );

            await _logDrivingCancel(
              plateId: id,
              phase: '입차',
              userName: userName,
            );

            final updated = _plate.copyWith(isSelected: false, selectedBy: null);
            if (mounted) setState(() => _plate = updated);
            try {
              await plateState.tripleUpdatePlateLocally(PlateType.parkingRequests, updated);
            } catch (_) {}

            try {
              showSuccessSnackbar(context, '주행이 취소되었습니다.');
            } catch (_) {}
          },
        );

        if (result == _DrivingResult.completed) {
          if (!mounted) return;
          Navigator.pop(context);
          return;
        }

        if (result == _DrivingResult.cancelled) {
          return;
        }

        // 실패 시 선점 해제(잠김 방지)
        try {
          await repo.recordWhoPlateClick(
            id,
            false,
            area: _plate.area,
          );
        } catch (_) {}
      } on FirebaseException catch (e) {
        _showWarningSafe('입차 주행 시작 실패: ${e.message ?? e.code}');
      } catch (e) {
        _showWarningSafe('입차 주행 시작 실패: $e');
      }
    });
  }

  Future<void> _startDepartureDriving() async {
    await _runPrimary(() async {
      if (_type != PlateType.departureRequests) {
        _showWarningSafe('현재 상태에서는 출차 주행 시작이 불가능합니다.');
        return;
      }

      final userName = context.read<UserState>().name;
      final selectedBy = (_plate.selectedBy ?? '').trim();
      if (_plate.isSelected == true && selectedBy.isNotEmpty && selectedBy != userName) {
        _showWarningSafe('다른 사용자가 이미 주행 중입니다. (선택자: $selectedBy)');
        return;
      }

      final repo = context.read<PlateRepository>();
      final movementPlate = context.read<MovementPlate>();
      final plateState = context.read<TriplePlateState>();
      final id = _plateDocId();

      try {
        await repo.recordWhoPlateClick(
          id,
          true,
          selectedBy: userName,
          area: _plate.area,
        );

        if (mounted) {
          setState(() {
            _plate = _plate.copyWith(
              isSelected: true,
              selectedBy: userName,
            );
          });
        }

        final canCancel = ((_plate.selectedBy ?? '').trim() == userName);
        final result = await _showDrivingBlockingDialog(
          message: '출차 주행 중입니다.',
          canCancel: canCancel,
          cancelDisabledHint: '선점자만 주행 취소가 가능합니다.',
          onComplete: () async {
            await movementPlate.setDepartureCompleted(_plate);
          },
          onCancel: () async {
            final currentSelectedBy = (_plate.selectedBy ?? '').trim();
            if (currentSelectedBy != userName) {
              throw StateError('권한 없음: 선점자만 취소 가능');
            }

            await repo.recordWhoPlateClick(
              id,
              false,
              area: _plate.area,
            );

            await _logDrivingCancel(
              plateId: id,
              phase: '출차',
              userName: userName,
            );

            final updated = _plate.copyWith(isSelected: false, selectedBy: null);
            if (mounted) setState(() => _plate = updated);
            try {
              await plateState.tripleUpdatePlateLocally(PlateType.departureRequests, updated);
            } catch (_) {}

            try {
              showSuccessSnackbar(context, '주행이 취소되었습니다.');
            } catch (_) {}
          },
        );

        if (result == _DrivingResult.completed) {
          if (!mounted) return;
          Navigator.pop(context);
          return;
        }

        if (result == _DrivingResult.cancelled) {
          return;
        }

        try {
          await repo.recordWhoPlateClick(
            id,
            false,
            area: _plate.area,
          );
        } catch (_) {}
      } on FirebaseException catch (e) {
        _showWarningSafe('출차 주행 시작 실패: ${e.message ?? e.code}');
      } catch (e) {
        _showWarningSafe('출차 주행 시작 실패: $e');
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
    final location = (_plate.location).trim().isEmpty ? '미지정' : _plate.location.trim();

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
              await _triggerBillingRequiredAttention(
                message: '정산을 진행해주세요. 정산 후 출차 요청으로 이동할 수 있습니다.',
              );
              return;
            }

            return;
          }

          _armOverride();
          await _triggerBillingRequiredAttention(
            message: '정산이 필요합니다. 먼저 정산을 진행하세요.\n'
                '정산 없이 출차 요청이 필요하면, 출차 요청 버튼을 한 번 더 누르세요.',
          );
          return;
        }

        _resetOverride();
        await _goDepartureRequested();
      });
    };

    if (_type == PlateType.parkingRequests) {
      primaryIcon = Icons.play_circle_fill;
      primaryTitle = _isMyDriving ? '입차 주행 계속' : '입차 주행 시작';
      primarySubtitle = _isMyDriving
          ? '이전에 시작된 주행 상태가 유지되었습니다. 완료 또는 취소로 정리하세요.'
          : '주행 중으로 전환 후, 완료 시 입차 완료로 변경됩니다.';
      primaryOnPressed = _startEntryDriving;
    } else if (_type == PlateType.departureRequests) {
      primaryIcon = Icons.play_circle_fill;
      primaryTitle = _isMyDriving ? '출차 주행 계속' : '출차 주행 시작';
      primarySubtitle = _isMyDriving
          ? '이전에 시작된 주행 상태가 유지되었습니다. 완료 또는 취소로 정리하세요.'
          : '주행 중으로 전환 후, 완료 시 출차 완료로 변경됩니다.';
      primaryOnPressed = _startDepartureDriving;
    }

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

                  final shakeDx =
                      math.sin(_attentionCtrl.value * math.pi * 10) * (1 - _attentionCtrl.value) * 6;
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
                                      final plateState = context.read<TriplePlateState>();
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

                                        await plateState.tripleUpdatePlateLocally(
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
                                      final plateState = context.read<TriplePlateState>();
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

                                        await plateState.tripleUpdatePlateLocally(
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
                              icon: primaryIcon,
                              title: primaryTitle,
                              subtitle: primarySubtitle,
                              onPressed: primaryOnPressed,
                            ),

                            /// ✅ 신규 버튼 위치: "출차 주행 시작" 하단
                            /// - departure_requests 타입일 때만 표시
                            if (_type == PlateType.departureRequests) ...[
                              const SizedBox(height: 10),
                              _PrimaryCtaButton(
                                icon: Icons.skip_next_rounded,
                                title: '주행 스킵 후 출차 완료',
                                subtitle: '주행 과정을 생략하고 바로 출차 완료로 변경합니다.',
                                onPressed: _skipDepartureDrivingToCompleted,
                                // 동일 컴포넌트/레이아웃 유지 + 색만 구분(오동작 방지)
                                backgroundColor: cs.tertiary,
                                foregroundColor: cs.onTertiary,
                              ),
                            ],
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
                                        builder: (_) => TripleModifyPlateScreen(
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

/// ✅ 주행 중(선점) 다이얼로그: ColorScheme 기반으로 색 통일
class _DrivingBlockingDialog extends StatefulWidget {
  const _DrivingBlockingDialog({
    required this.message,
    required this.canCancel,
    required this.cancelDisabledHint,
    required this.onComplete,
    required this.onCancel,
  });

  final String message;
  final bool canCancel;
  final String cancelDisabledHint;

  final Future<_DrivingResult> Function() onComplete;
  final Future<_DrivingResult> Function() onCancel;

  @override
  State<_DrivingBlockingDialog> createState() => _DrivingBlockingDialogState();
}

class _DrivingBlockingDialogState extends State<_DrivingBlockingDialog> {
  bool _busy = false;

  Future<void> _run(Future<_DrivingResult> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await fn();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _busy ? cs.onSurfaceVariant : cs.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
            if (!widget.canCancel) ...[
              const SizedBox(height: 10),
              Text(
                widget.cancelDisabledHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: (_busy || !widget.canCancel) ? null : () => _run(widget.onCancel),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      foregroundColor: cs.onSurface,
                    ),
                    child: Text(_busy ? '처리 중...' : '주행 취소'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _run(widget.onComplete),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    child: Text(_busy ? '처리 중...' : '주행 완료'),
                  ),
                ),
              ],
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
            fontWeight: FontWeight.bold,
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

    // ✅ 사전정산 완료 = 성공 톤(tertiary), 미정산 = 중립 톤
    final badgeColor = isLocked ? cs.tertiary : cs.onSurfaceVariant;
    final badgeText = isLocked ? '사전정산 잠김' : '사전정산 없음';

    final feeText = (isLocked && lockedFee != null)
        ? '₩$lockedFee${paymentMethod.isNotEmpty ? " ($paymentMethod)" : ""}'
        : '—';

    final billingText = billingType.isNotEmpty ? billingType : '미지정';

    // ✅ attention(정산 필요) = error 계열로 강조
    final borderColor =
    Color.lerp(cs.outlineVariant.withOpacity(0.85), cs.error, (attention * 0.9).clamp(0, 1))!;
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
            color: cs.shadow.withOpacity(0.03),
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
                color: cs.errorContainer.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.error.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: cs.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '정산이 필요합니다. 정산 후 출차 요청으로 이동할 수 있습니다.',
                      style: TextStyle(
                        color: cs.error,
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
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: cs.onSurface)),
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

    final Color base = (tone == _ActionTone.positive) ? cs.tertiary : cs.onSurfaceVariant;
    final Color bg = (tone == _ActionTone.positive)
        ? cs.tertiaryContainer.withOpacity(0.45)
        : cs.surfaceContainerLow;
    final Color border = (tone == _ActionTone.positive)
        ? cs.tertiary.withOpacity(0.35)
        : cs.outlineVariant.withOpacity(0.85);

    final Color attentionBorder =
    Color.lerp(border, cs.error, (attention * 0.9).clamp(0, 1))!;
    final Color attentionBg =
    Color.lerp(bg, cs.errorContainer.withOpacity(0.35), (attention * 0.8).clamp(0, 1))!;

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
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: cs.onSurface,
                      ),
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
                          color: cs.error,
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

  /// ✅ 리팩터링: 동일한 버튼 디자인 유지하면서, 상황별(스킵 버튼 등) 색만 구분 가능하게 확장
  final Color? backgroundColor;
  final Color? foregroundColor;

  const _PrimaryCtaButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bg = backgroundColor ?? cs.primary;
    final fg = foregroundColor ?? cs.onPrimary;

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
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
                      color: fg.withOpacity(0.90),
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
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 46),
        foregroundColor: cs.onSurface,
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: cs.surface,
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
          side: BorderSide(color: cs.error.withOpacity(0.45)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: cs.errorContainer.withOpacity(0.35),
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
