import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../application/monthly_date_range_calculator.dart';
import '../../controllers/monthly_plate_controller.dart';
import '../../domain/monthly_parking_options.dart';
import '../widgets/monthly_prompt_ui.dart';
import 'widgets/monthly_payment_section.dart';

class MonthlyPaymentBottomSheet extends StatefulWidget {
  const MonthlyPaymentBottomSheet({
    super.key,
    required this.controller,
  });

  final MonthlyPlateController controller;

  @override
  State<MonthlyPaymentBottomSheet> createState() =>
      _MonthlyPaymentBottomSheetState();
}

class _MonthlyPaymentBottomSheetState
    extends State<MonthlyPaymentBottomSheet> {
  String _won(String value) {
    final amount = int.tryParse(value.trim());
    if (amount == null) return value.trim().isEmpty ? '-' : value;
    return '₩${NumberFormat.decimalPattern('ko_KR').format(amount)}';
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 1,
      child: PromptSheetScaffold(
        title: '결제 처리',
        icon: Icons.payments_outlined,
        onClose: () => Navigator.of(context).maybePop(),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            PromptAnimatedReveal(child: _buildSummaryCard(context)),
            const SizedBox(height: 14),
            MonthlyPaymentSection(
              controller: widget.controller,
              onPaymentAmountChanged: () => setState(() {}),
              onExtendedChanged: (value) {
                setState(() {
                  widget.controller.isExtended = value ?? false;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final controller = widget.controller;
    final plate = controller.buildPlateNumber();
    final countType = controller.nameController?.text.trim() ?? '';
    final regularType = controller.selectedRegularType?.trim() ?? '';
    controller.ensurePaymentAmountDefault();
    final amount = controller.paymentAmountController.text.trim();
    final durationValue =
        int.tryParse(controller.durationController?.text.trim() ?? '') ?? 0;
    final duration = durationValue > 0
        ? MonthlyParkingOptions.durationLabel(
            regularType: controller.selectedRegularType,
            duration: durationValue,
            periodUnit: controller.selectedPeriodUnit,
          )
        : '-';
    final startDate = controller.startDateController?.text.trim() ?? '';
    final endDate = controller.endDateController?.text.trim() ?? '';
    final nextStart = controller.previewExtendedStartDate();
    final nextEnd = controller.previewExtendedEndDate();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        border: Border.all(color: tokens.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  borderRadius: BorderRadius.circular(PromptUiShapes.control),
                  border: Border.all(
                    color: tokens.accent.withOpacity(
                      tokens.isDark ? 0.56 : 0.34,
                    ),
                  ),
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: tokens.onAccentContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plate,
                      style: textTheme.titleLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${countType.isEmpty ? '-' : countType} · ${regularType.isEmpty ? '-' : regularType}',
                      style: textTheme.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const MonthlyPromptBadge(
                label: '결제 대상',
                icon: Icons.verified_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tokens.accentContainer,
              borderRadius: BorderRadius.circular(PromptUiShapes.card),
              border: Border.all(
                color: tokens.accent.withOpacity(
                  tokens.isDark ? 0.56 : 0.34,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '이번 결제 금액',
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.onAccentContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedSwitcher(
                  duration: MediaQuery.maybeOf(context)?.disableAnimations ??
                          false
                      ? Duration.zero
                      : PromptUiMotion.component,
                  child: Text(
                    _won(amount),
                    key: ValueKey<String>(amount),
                    style: textTheme.headlineMedium?.copyWith(
                      color: tokens.onAccentContainer,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _PaymentSummaryRow(
            label: '현재 기간',
            value: '$startDate ~ $endDate',
          ),
          _PaymentSummaryRow(label: '기간 단위', value: duration),
          _PaymentSummaryRow(
            label: '번호판 지역',
            value: controller.dropdownValue,
          ),
          if (controller.isExtended && nextStart != null && nextEnd != null) ...[
            const SizedBox(height: 10),
            AnimatedContainer(
              duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                  ? Duration.zero
                  : PromptUiMotion.selection,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.successContainer,
                borderRadius: BorderRadius.circular(PromptUiShapes.control),
                border: Border.all(
                  color: tokens.success.withOpacity(0.3),
                ),
              ),
              child: Text(
                '연장 후 기간: ${MonthlyDateRangeCalculator.format(nextStart)} ~ ${MonthlyDateRangeCalculator.format(nextEnd)}',
                style: textTheme.bodyMedium?.copyWith(
                  color: tokens.onSuccessContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentSummaryRow extends StatelessWidget {
  const _PaymentSummaryRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
