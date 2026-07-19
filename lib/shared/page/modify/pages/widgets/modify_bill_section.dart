import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../../features/payment/applications/bill_state.dart';
import '../../../../../features/payment/domain/models/bill_model.dart';
import '../../../../../features/payment/domain/models/regular_bill_model.dart';
import '../prompt_modify_ui.dart';

class ModifyBillSection extends StatelessWidget {
  const ModifyBillSection({
    super.key,
    required this.selectedBill,
    required this.selectedBillType,
    required this.onChanged,
    required this.onTypeChanged,
  });

  final String? selectedBill;
  final String selectedBillType;
  final ValueChanged<dynamic> onChanged;
  final ValueChanged<String> onTypeChanged;

  Future<void> _showBillPicker(
    BuildContext context,
    List<dynamic> bills,
    bool isGeneral,
  ) async {
    await showPromptOverlayBottomSheet<void>(
      context: context,
      useSafeArea: false,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: .54,
        minChildSize: .36,
        maxChildSize: .9,
        builder: (sheetContext, scrollController) {
          final tokens = PromptUiTheme.of(sheetContext);
          return PromptSheetScaffold(
            title: '${isGeneral ? '변동' : '고정'} 정산 선택',
            icon: Icons.receipt_long_rounded,
            onClose: () => Navigator.of(sheetContext).pop(),
            body: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: bills.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final bill = bills[index];
                final countType = isGeneral
                    ? (bill as BillModel).countType
                    : (bill as RegularBillModel).countType;
                final selected = countType == selectedBill;
                return Material(
                  color: selected
                      ? tokens.surfaceSelected
                      : tokens.surfaceOverlay,
                  borderRadius: BorderRadius.circular(PromptUiShapes.control),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onChanged(bill);
                    },
                    child: AnimatedContainer(
                      duration: MediaQuery.maybeOf(context)?.disableAnimations ??
                              false
                          ? Duration.zero
                          : PromptUiMotion.selection,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(PromptUiShapes.control),
                        border: Border.all(
                          color: selected
                              ? tokens.accent
                              : tokens.borderSubtle,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              countType,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: MediaQuery.maybeOf(context)
                                        ?.disableAnimations ??
                                    false
                                ? Duration.zero
                                : PromptUiMotion.selection,
                            child: selected
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    key: const ValueKey('selected'),
                                    color: tokens.accent,
                                  )
                                : Icon(
                                    Icons.circle_outlined,
                                    key: const ValueKey('unselected'),
                                    color: tokens.iconSecondary,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final billState = context.watch<BillState>();
    final isGeneral = selectedBillType == '변동';
    final bills = isGeneral
        ? List<dynamic>.from(billState.generalBills)
        : List<dynamic>.from(billState.regularBills);

    return PromptAnimatedReveal(
      child: PromptModifySectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PromptModifySectionTitle(
              icon: Icons.receipt_long_rounded,
              title: '정산 유형',
              subtitle: '차량에 적용할 정산 방식을 확인합니다.',
            ),
            const SizedBox(height: 14),
            if (billState.isLoading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(color: tokens.accent),
                ),
              )
            else if (bills.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: tokens.surfaceOverlay,
                  borderRadius: BorderRadius.circular(PromptUiShapes.control),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: Text(
                  '${isGeneral ? '변동' : '고정'} 정산 유형이 없습니다.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
                      ),
                ),
              )
            else
              PromptButton(
                label: selectedBill ?? '정산 선택',
                icon: Icons.expand_more_rounded,
                variant: PromptButtonVariant.secondary,
                selected: selectedBill != null && selectedBill!.isNotEmpty,
                expand: true,
                onPressed: () => _showBillPicker(context, bills, isGeneral),
              ),
          ],
        ),
      ),
    );
  }
}
