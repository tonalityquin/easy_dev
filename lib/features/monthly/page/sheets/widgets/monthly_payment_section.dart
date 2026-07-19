import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../controllers/monthly_plate_controller.dart';
import '../../widgets/monthly_prompt_ui.dart';

class MonthlyPaymentSection extends StatefulWidget {
  const MonthlyPaymentSection({
    super.key,
    required this.controller,
    required this.onExtendedChanged,
    this.onPaymentAmountChanged,
  });

  final MonthlyPlateController controller;
  final ValueChanged<bool?> onExtendedChanged;
  final VoidCallback? onPaymentAmountChanged;

  @override
  State<MonthlyPaymentSection> createState() =>
      _MonthlyPaymentSectionState();
}

class _MonthlyPaymentSectionState extends State<MonthlyPaymentSection> {
  final TextEditingController _noteController = TextEditingController();
  final List<String> _paymentHistoryLog = <String>[];
  bool _isPaying = false;

  @override
  void initState() {
    super.initState();
    _noteController.text = widget.controller.specialNote;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String _formatNow() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$year.$month.$day $hour:$minute';
  }

  void _toggleExtended(bool value) {
    setState(() => widget.controller.isExtended = value);
    widget.onExtendedChanged(value);
  }

  Future<void> _handlePayment() async {
    FocusScope.of(context).unfocus();
    widget.controller.specialNote = _noteController.text.trim();
    if (!widget.controller.validatePaymentBeforeWrite(context)) return;

    setState(() => _isPaying = true);
    try {
      await widget.controller.processPayment(context);
      if (!mounted) return;
      final note = _noteController.text.trim();
      final extended = widget.controller.isExtended;
      setState(() {
        _paymentHistoryLog.insert(
          0,
          '${_formatNow()} 결제 완료${note.isNotEmpty ? ' · $note' : ''}${extended ? ' · 기간 연장' : ''}',
        );
      });
      _noteController.clear();
      widget.controller.specialNote = '';
      _toggleExtended(false);
      showMonthlyPromptMessage(
        context,
        '결제가 저장되었습니다.',
        tone: MonthlyPromptMessageTone.success,
      );
    } catch (_) {
      if (!mounted) return;
      showMonthlyPromptMessage(
        context,
        '결제 저장에 실패했습니다. 다시 시도해주세요.',
        tone: MonthlyPromptMessageTone.danger,
      );
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return MonthlyPromptSection(
      title: '결제 입력',
      subtitle: '결제 금액, 메모와 기간 연장 여부를 확인합니다.',
      icon: Icons.point_of_sale_outlined,
      delay: const Duration(milliseconds: 70),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: widget.controller.paymentAmountController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => widget.onPaymentAmountChanged?.call(),
            style: textTheme.bodyLarge?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
            decoration: monthlyPromptInputDecoration(
              context,
              label: '이번 결제 금액',
              prefixIcon: Icon(
                Icons.payments_outlined,
                color: tokens.iconSecondary,
              ),
              suffixText: '원',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _noteController,
            maxLines: 2,
            style: textTheme.bodyLarge?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            decoration: monthlyPromptInputDecoration(
              context,
              label: '결제 메모',
              prefixIcon: Icon(
                Icons.edit_note_rounded,
                color: tokens.iconSecondary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            button: true,
            toggled: widget.controller.isExtended,
            label: '결제 후 다음 기간으로 연장',
            child: InkWell(
              onTap: () => _toggleExtended(!widget.controller.isExtended),
              borderRadius: BorderRadius.circular(PromptUiShapes.card),
              child: AnimatedContainer(
                duration:
                    reduceMotion ? Duration.zero : PromptUiMotion.selection,
                curve: PromptUiMotion.standard,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: widget.controller.isExtended
                      ? tokens.successContainer
                      : tokens.surfaceOverlay,
                  borderRadius: BorderRadius.circular(PromptUiShapes.card),
                  border: Border.all(
                    color: widget.controller.isExtended
                        ? tokens.success.withOpacity(0.34)
                        : tokens.borderSubtle,
                  ),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: widget.controller.isExtended,
                      activeColor: tokens.success,
                      checkColor: tokens.onSuccess,
                      onChanged: (value) => _toggleExtended(value ?? false),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '결제 후 다음 기간으로 연장',
                            style: textTheme.bodyLarge?.copyWith(
                              color: widget.controller.isExtended
                                  ? tokens.onSuccessContainer
                                  : tokens.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '결제 내역 저장과 기간 갱신을 함께 처리합니다.',
                            style: textTheme.bodySmall?.copyWith(
                              color: widget.controller.isExtended
                                  ? tokens.onSuccessContainer
                                  : tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          PromptButton(
            label: _isPaying ? '처리 중' : '결제 저장',
            icon: Icons.check_circle_outline_rounded,
            expand: true,
            loading: _isPaying,
            haptic: PromptHaptic.medium,
            onPressed: _isPaying ? null : _handlePayment,
          ),
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
            switchInCurve: PromptUiMotion.enter,
            switchOutCurve: PromptUiMotion.exit,
            child: _paymentHistoryLog.isEmpty
                ? const SizedBox.shrink(
                    key: ValueKey<String>('empty-payment-log'),
                  )
                : Padding(
                    key: const ValueKey<String>('payment-log'),
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '이번 화면 처리 내역',
                          style: textTheme.titleSmall?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (var index = 0;
                            index < _paymentHistoryLog.length;
                            index++)
                          PromptAnimatedReveal(
                            delay: reduceMotion
                                ? Duration.zero
                                : Duration(milliseconds: index * 35),
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: tokens.surfaceOverlay,
                                borderRadius: BorderRadius.circular(
                                  PromptUiShapes.control,
                                ),
                                border: Border.all(
                                  color: tokens.borderSubtle,
                                ),
                              ),
                              child: Text(
                                _paymentHistoryLog[index],
                                style: textTheme.bodyMedium?.copyWith(
                                  color: tokens.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
