import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/application/secondary_monthly_workspace_state.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import 'models/monthly_payment_settings_draft.dart';

class MonthlyPaymentSettingSectionEditorDialog extends StatefulWidget {
  const MonthlyPaymentSettingSectionEditorDialog({
    super.key,
    required this.section,
    required this.initialDraft,
    required this.extensionAvailable,
    required this.extensionSummary,
    required this.trace,
    required this.onApply,
  });

  final MonthlyWorkspaceSection section;
  final MonthlyPaymentSettingsDraft initialDraft;
  final bool extensionAvailable;
  final String extensionSummary;
  final DeveloperOperationTrace trace;
  final ValueChanged<MonthlyPaymentSettingsDraft> onApply;

  @override
  State<MonthlyPaymentSettingSectionEditorDialog> createState() =>
      _MonthlyPaymentSettingSectionEditorDialogState();
}

class _MonthlyPaymentSettingSectionEditorDialogState
    extends State<MonthlyPaymentSettingSectionEditorDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late bool _extended;
  bool _submitted = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.initialDraft.paymentAmount?.toString() ?? '',
    );
    _noteController = TextEditingController(text: widget.initialDraft.note);
    _extended = widget.initialDraft.extended && widget.extensionAvailable;
    widget.trace.log('결제 편집 화면이 열렸습니다: section=${widget.section.name}');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.section) {
      case MonthlyWorkspaceSection.paymentAmount:
        return '결제 금액';
      case MonthlyWorkspaceSection.paymentExtension:
        return '기간 연장';
      case MonthlyWorkspaceSection.paymentNote:
        return '결제 메모';
      case MonthlyWorkspaceSection.vehicle:
      case MonthlyWorkspaceSection.product:
      case MonthlyWorkspaceSection.period:
      case MonthlyWorkspaceSection.memo:
        return '결제 설정';
    }
  }

  IconData get _icon {
    switch (widget.section) {
      case MonthlyWorkspaceSection.paymentAmount:
        return Icons.payments_rounded;
      case MonthlyWorkspaceSection.paymentExtension:
        return Icons.update_rounded;
      case MonthlyWorkspaceSection.paymentNote:
        return Icons.edit_note_rounded;
      case MonthlyWorkspaceSection.vehicle:
      case MonthlyWorkspaceSection.product:
      case MonthlyWorkspaceSection.period:
      case MonthlyWorkspaceSection.memo:
        return Icons.point_of_sale_rounded;
    }
  }

  bool _validate() {
    if (widget.section == MonthlyWorkspaceSection.paymentAmount) {
      return (int.tryParse(_amountController.text.trim()) ?? 0) > 0;
    }
    if (widget.section == MonthlyWorkspaceSection.paymentExtension) {
      return !_extended || widget.extensionAvailable;
    }
    return true;
  }

  MonthlyPaymentSettingsDraft _resultDraft() {
    final base = widget.initialDraft;
    switch (widget.section) {
      case MonthlyWorkspaceSection.paymentAmount:
        return base.copyWith(
          paymentAmount: int.tryParse(_amountController.text.trim()),
        );
      case MonthlyWorkspaceSection.paymentExtension:
        return base.copyWith(extended: _extended);
      case MonthlyWorkspaceSection.paymentNote:
        return base.copyWith(note: _noteController.text.trim());
      case MonthlyWorkspaceSection.vehicle:
      case MonthlyWorkspaceSection.product:
      case MonthlyWorkspaceSection.period:
      case MonthlyWorkspaceSection.memo:
        return base;
    }
  }

  Future<void> _apply() async {
    setState(() => _submitted = true);
    if (!_validate()) {
      widget.trace.log('결제 입력 검증 실패: section=${widget.section.name}');
      await HapticFeedback.mediumImpact();
      return;
    }
    final result = _resultDraft();
    widget.trace.log(
      '결제 편집 적용: section=${widget.section.name} amount=${result.paymentAmount ?? 0} extended=${result.extended} noteLength=${result.note.length}',
    );
    widget.onApply(result);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(true);
  }

  void _cancel() {
    widget.trace.log('결제 편집 취소: section=${widget.section.name}');
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  Future<void> _showDeveloperTrace() async {
    widget.trace.log('개발자 로그 Status Dialog 요청: section=${widget.section.name}');
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '$_title 편집 로그',
      description: '현재 편집 동작의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
    );
  }

  Widget _buildBody(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    switch (widget.section) {
      case MonthlyWorkspaceSection.paymentAmount:
        return TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: opsInputDecoration(
            context,
            label: '이번 결제 금액',
            suffixText: '원',
            errorText: _submitted &&
                    (int.tryParse(_amountController.text.trim()) ?? 0) <= 0
                ? '1원 이상 입력하세요.'
                : null,
          ),
        );
      case MonthlyWorkspaceSection.paymentExtension:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.extensionSummary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 14),
            OpsDockSelectableRowSurface(
              selected: !_extended,
              selectionColor: tokens.accent,
              selectedContainer: tokens.accentContainer,
              onTap: () => setState(() => _extended = false),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    _extended
                        ? Icons.radio_button_unchecked_rounded
                        : Icons.radio_button_checked_rounded,
                    color: _extended ? tokens.iconSecondary : tokens.accent,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('연장하지 않음')),
                ],
              ),
            ),
            const SizedBox(height: 8),
            OpsDockSelectableRowSurface(
              selected: _extended,
              selectionColor: tokens.accent,
              selectedContainer: tokens.accentContainer,
              onTap: () {
                if (!widget.extensionAvailable) return;
                setState(() => _extended = true);
              },
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    _extended
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: widget.extensionAvailable
                        ? (_extended ? tokens.accent : tokens.iconSecondary)
                        : tokens.iconDisabled,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '다음 기간으로 연장',
                      style: TextStyle(
                        color: widget.extensionAvailable
                            ? tokens.textPrimary
                            : tokens.textDisabled,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_submitted && _extended && !widget.extensionAvailable) ...[
              const SizedBox(height: 8),
              Text(
                '현재 정기권 정보로 연장 기간을 계산할 수 없습니다.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.danger,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ],
        );
      case MonthlyWorkspaceSection.paymentNote:
        return TextField(
          controller: _noteController,
          maxLines: 5,
          decoration: opsInputDecoration(
            context,
            label: '결제 메모',
          ),
        );
      case MonthlyWorkspaceSection.vehicle:
      case MonthlyWorkspaceSection.product:
      case MonthlyWorkspaceSection.period:
      case MonthlyWorkspaceSection.memo:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: tokens.surfaceRaised,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.accentContainer,
                    borderRadius: BorderRadius.circular(CommonUiShapes.control),
                  ),
                  child: Icon(_icon, size: 20, color: tokens.onAccentContainer),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _title,
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (widget.trace.developerMode) ...[
                  CommonIconButton(
                    icon: Icons.bug_report_outlined,
                    tooltip: '디버그 상태',
                    onPressed: _showDeveloperTrace,
                    haptic: CommonHaptic.selection,
                    size: 36,
                    iconSize: 18,
                  ),
                  const SizedBox(width: 2),
                ],
                CommonIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '닫기',
                  onPressed: _cancel,
                  haptic: CommonHaptic.light,
                  size: 36,
                  iconSize: 18,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: AnimatedSwitcher(
                duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                child: KeyedSubtree(
                  key: ValueKey<MonthlyWorkspaceSection>(widget.section),
                  child: _buildBody(context),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: CommonButton(
                    label: '취소',
                    variant: CommonButtonVariant.secondary,
                    onPressed: _cancel,
                    haptic: CommonHaptic.selection,
                    expand: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CommonButton(
                    label: '적용',
                    icon: Icons.check_rounded,
                    onPressed: _apply,
                    haptic: CommonHaptic.medium,
                    expand: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
