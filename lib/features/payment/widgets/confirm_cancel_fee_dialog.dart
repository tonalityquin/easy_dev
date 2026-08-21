import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';

class ConfirmCancelFeeDialog extends StatefulWidget {
  const ConfirmCancelFeeDialog({
    super.key,
    required this.plateNumber,
    required this.lockedFeeAmount,
    required this.paymentMethod,
    this.trace,
  });

  final String plateNumber;
  final int lockedFeeAmount;
  final String paymentMethod;
  final DeveloperOperationTrace? trace;

  @override
  State<ConfirmCancelFeeDialog> createState() => _ConfirmCancelFeeDialogState();
}

class _ConfirmCancelFeeDialogState extends State<ConfirmCancelFeeDialog> {
  static const int _reviewSeconds = 3;

  final NumberFormat _currency = NumberFormat('#,###', 'ko_KR');
  Timer? _timer;
  int _remainingSeconds = _reviewSeconds;

  bool get _enabled => _remainingSeconds == 0;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  String get _paymentMethod {
    final value = widget.paymentMethod.trim();
    return value.isEmpty ? '미기록' : value;
  }

  String get _formattedAmount => '₩${_currency.format(widget.lockedFeeAmount)}';

  void _log(String message, {double? progress}) {
    final line =
        'billing_cancel_confirm $message plate=${widget.plateNumber} lockedFee=${widget.lockedFeeAmount} payment=$_paymentMethod';
    final trace = widget.trace;
    if (trace != null) {
      trace.log(line, progress: progress);
      return;
    }
    debugPrint('[BillingCancelConfirm] $line');
  }

  @override
  void initState() {
    super.initState();
    _log(
      'opened reviewSeconds=$_reviewSeconds animation=overlay_fade_scale progress=countdown',
      progress: .2,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
        _log('review_completed destructiveAction=enabled', progress: .34);
      } else {
        setState(() => _remainingSeconds -= 1);
        _log(
          'review_tick remainingSeconds=$_remainingSeconds destructiveAction=disabled',
          progress: .28,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _keepSettlement() {
    _log('dismissed result=keep_settlement', progress: .36);
    Navigator.of(context).pop(false);
  }

  void _confirmCancellation() {
    if (!_enabled) {
      _log(
        'confirm_ignored reason=review_incomplete remainingSeconds=$_remainingSeconds',
        progress: .3,
      );
      return;
    }
    _log('confirmed result=cancel_settlement', progress: .4);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final elapsed = _reviewSeconds - _remainingSeconds;
    final progress = (elapsed / _reviewSeconds).clamp(0.0, 1.0).toDouble();
    final motion = _reduceMotion ? Duration.zero : CommonUiMotion.selection;

    return CommonDialogFrame(
      animate: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: motion,
                  curve: CommonUiMotion.enter,
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: tokens.dangerContainer,
                    borderRadius: BorderRadius.circular(CommonUiShapes.control),
                    border: Border.all(
                      color: tokens.danger.withOpacity(
                        tokens.isDark ? .58 : .36,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.undo_rounded,
                    color: tokens.danger,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '정산 취소',
                        style: textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '완료된 정산을 되돌립니다.',
                        style: textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AnimatedContainer(
              duration: motion,
              curve: CommonUiMotion.standard,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(CommonUiShapes.card),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.plateNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleLarge?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CancelBillingInfoRow(
                    label: '현재 정산',
                    value: _formattedAmount,
                  ),
                  const SizedBox(height: 8),
                  _CancelBillingInfoRow(
                    label: '결제수단',
                    value: _paymentMethod,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.warningContainer.withOpacity(.72),
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(
                  color: tokens.warning.withOpacity(tokens.isDark ? .5 : .34),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: tokens.warning,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '정산을 취소하면 현재 요금 잠금이 해제됩니다. 다음 정산 시 요금이 다시 계산될 수 있습니다.',
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.onWarningContainer,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 18,
                        color: tokens.textSecondary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '취소 전 확인',
                          style: textTheme.labelLarge?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: motion,
                        switchInCurve: CommonUiMotion.enter,
                        switchOutCurve: CommonUiMotion.exit,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: .92, end: 1).animate(
                                animation,
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          _enabled ? '확인 완료' : '$_remainingSeconds초',
                          key: ValueKey<int>(_remainingSeconds),
                          style: textTheme.labelLarge?.copyWith(
                            color: _enabled
                                ? tokens.textPrimary
                                : tokens.warning,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  TweenAnimationBuilder<double>(
                    duration: motion,
                    curve: CommonUiMotion.enter,
                    tween: Tween<double>(begin: 0, end: progress),
                    builder: (context, value, _) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 7,
                          backgroundColor: tokens.borderSubtle,
                          color: _enabled ? tokens.danger : tokens.warning,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: CommonButton(
                    label: '정산 유지',
                    icon: Icons.arrow_back_rounded,
                    variant: CommonButtonVariant.tertiary,
                    haptic: CommonHaptic.light,
                    onPressed: _keepSettlement,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedScale(
                    scale: _enabled ? 1 : .98,
                    duration: motion,
                    curve: CommonUiMotion.enter,
                    child: CommonButton(
                      label: '정산 취소',
                      icon: Icons.undo_rounded,
                      variant: CommonButtonVariant.destructive,
                      haptic: CommonHaptic.medium,
                      onPressed: _enabled ? _confirmCancellation : null,
                    ),
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

class _CancelBillingInfoRow extends StatelessWidget {
  const _CancelBillingInfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: textTheme.bodyMedium?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}
