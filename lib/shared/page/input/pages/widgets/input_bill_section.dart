import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../../features/payment/applications/bill_state.dart';
import '../prompt_input_ui.dart';

class InputBillSection extends StatelessWidget {
  final String? selectedBill;
  final String selectedBillType;
  final ValueChanged<String?> onChanged;
  final ValueChanged<String> onTypeChanged;
  final TextEditingController? countTypeController;

  const InputBillSection({
    super.key,
    required this.selectedBill,
    required this.selectedBillType,
    required this.onChanged,
    required this.onTypeChanged,
    this.countTypeController,
  });

  Future<void> _showBillSheet(
    BuildContext context,
    String normalizedType,
    List<dynamic> bills,
  ) async {
    await showPromptOverlayBottomSheet<void>(
      context: context,
      useSafeArea: false,
      builder: (sheetContext) {
        final tokens = PromptUiTheme.of(sheetContext);
        return DraggableScrollableSheet(
          initialChildSize: .55,
          minChildSize: .36,
          maxChildSize: .9,
          builder: (sheetContext, scrollController) {
            return PromptSheetScaffold(
              title: '$normalizedType 정산 선택',
              icon: Icons.receipt_long_rounded,
              onClose: () => Navigator.of(sheetContext).pop(),
              body: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: bills.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final bill = bills[index];
                  final value = bill.countType as String;
                  final selected = value == selectedBill;
                  return AnimatedContainer(
                    duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                        ? Duration.zero
                        : PromptUiMotion.selection,
                    decoration: BoxDecoration(
                      color: selected
                          ? tokens.surfaceSelected
                          : tokens.surfaceOverlay,
                      borderRadius: BorderRadius.circular(PromptUiShapes.control),
                      border: Border.all(
                        color: selected ? tokens.accent : tokens.borderSubtle,
                      ),
                    ),
                    child: ListTile(
                      title: Text(
                        value,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      trailing: selected
                          ? Icon(Icons.check_rounded, color: tokens.accent)
                          : Icon(Icons.chevron_right_rounded,
                              color: tokens.iconSecondary),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onChanged(value);
                      },
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final billState = context.watch<BillState>();
    final normalizedType = selectedBillType == '고정' ? '변동' : selectedBillType;
    final isGeneral = normalizedType == '변동';
    final isMonthly = normalizedType == '정기';
    final filteredBills = billState.generalBills;

    return PromptInputSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PromptInputSectionTitle(
            icon: Icons.payments_rounded,
            title: '정산 유형',
            subtitle: '입차 차량에 적용할 정산 방식을 선택합니다.',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: PromptButton(
                  label: '변동',
                  selected: isGeneral,
                  variant: PromptButtonVariant.secondary,
                  onPressed: () => onTypeChanged('변동'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PromptButton(
                  label: '정기',
                  selected: isMonthly,
                  variant: PromptButtonVariant.secondary,
                  onPressed: () => onTypeChanged('정기'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                ? Duration.zero
                : PromptUiMotion.component,
            switchInCurve: PromptUiMotion.enter,
            switchOutCurve: PromptUiMotion.exit,
            child: isMonthly
                ? TextField(
                    key: const ValueKey('monthly'),
                    controller: countTypeController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: '정기 호실 또는 구분',
                      prefixIcon: Icon(Icons.apartment_rounded),
                    ),
                  )
                : billState.isLoading
                    ? SizedBox(
                        key: const ValueKey('loading'),
                        height: 72,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: tokens.accent,
                          ),
                        ),
                      )
                    : filteredBills.isEmpty
                        ? Container(
                            key: const ValueKey('empty'),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: tokens.warningContainer,
                              borderRadius:
                                  BorderRadius.circular(PromptUiShapes.control),
                              border: Border.all(
                                color: tokens.warning.withOpacity(.36),
                              ),
                            ),
                            child: Text(
                              '$normalizedType 정산 유형이 없습니다.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: tokens.onWarningContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          )
                        : PromptButton(
                            key: const ValueKey('selector'),
                            label: selectedBill ?? '정산 선택',
                            icon: Icons.expand_more_rounded,
                            variant: PromptButtonVariant.secondary,
                            expand: true,
                            onPressed: () => _showBillSheet(
                              context,
                              normalizedType,
                              filteredBills,
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
