import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/application/secondary_bill_workspace_state.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import 'models/bill_settings_draft.dart';

class BillSettingSectionEditorDialog extends StatefulWidget {
  const BillSettingSectionEditorDialog({
    super.key,
    required this.section,
    required this.initialDraft,
    required this.trace,
    required this.onApply,
  });

  final BillSettingsSection section;
  final BillSettingsDraft initialDraft;
  final DeveloperOperationTrace trace;
  final ValueChanged<BillSettingsDraft> onApply;

  @override
  State<BillSettingSectionEditorDialog> createState() =>
      _BillSettingSectionEditorDialogState();
}

class _BillSettingSectionEditorDialogState
    extends State<BillSettingSectionEditorDialog> {
  static const List<int> _basicStandardOptions = <int>[1, 5, 30, 60, 120, 240];
  static const List<int> _addStandardOptions = <int>[1, 10, 30, 60];

  late final TextEditingController _countTypeController;
  late final TextEditingController _basicAmountController;
  late final TextEditingController _addAmountController;
  int? _basicStandard;
  int? _addStandard;
  bool _submitted = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _countTypeController = TextEditingController(text: draft.countType);
    _basicAmountController = TextEditingController(
      text: draft.basicAmount?.toString() ?? '',
    );
    _addAmountController = TextEditingController(
      text: draft.addAmount?.toString() ?? '',
    );
    _basicStandard = draft.basicStandard;
    _addStandard = draft.addStandard;
    widget.trace.log('편집 화면이 열렸습니다: section=${widget.section.name}');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    _countTypeController.dispose();
    _basicAmountController.dispose();
    _addAmountController.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.section) {
      case BillSettingsSection.identity:
        return '정산 유형';
      case BillSettingsSection.pricing:
        return '요금 기준';
    }
  }

  IconData get _icon {
    switch (widget.section) {
      case BillSettingsSection.identity:
        return Icons.receipt_long_rounded;
      case BillSettingsSection.pricing:
        return Icons.calculate_rounded;
    }
  }

  int? _parseAmount(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }

  bool get _identityOk => _countTypeController.text.trim().isNotEmpty;
  bool get _basicAmountOk {
    final amount = _parseAmount(_basicAmountController.text);
    return amount != null && amount >= 0;
  }

  bool get _addAmountOk {
    final amount = _parseAmount(_addAmountController.text);
    return amount != null && amount >= 0;
  }

  bool get _pricingOk =>
      _basicStandard != null &&
      _addStandard != null &&
      _basicAmountOk &&
      _addAmountOk;

  bool _validate() {
    switch (widget.section) {
      case BillSettingsSection.identity:
        return _identityOk;
      case BillSettingsSection.pricing:
        return _pricingOk;
    }
  }

  BillSettingsDraft _resultDraft() {
    final base = widget.initialDraft;
    switch (widget.section) {
      case BillSettingsSection.identity:
        return base.copyWith(countType: _countTypeController.text.trim());
      case BillSettingsSection.pricing:
        return base.copyWith(
          basicStandard: _basicStandard,
          basicAmount: _parseAmount(_basicAmountController.text),
          addStandard: _addStandard,
          addAmount: _parseAmount(_addAmountController.text),
        );
    }
  }

  Future<void> _apply() async {
    setState(() => _submitted = true);
    if (!_validate()) {
      widget.trace.log('입력 검증 실패: section=${widget.section.name}');
      await HapticFeedback.mediumImpact();
      return;
    }
    final result = _resultDraft();
    widget.trace.log(
      '편집 적용: section=${widget.section.name} countTypeLength=${result.countType.length} basicStandard=${result.basicStandard ?? -1} basicAmountValid=${result.basicAmount != null} addStandard=${result.addStandard ?? -1} addAmountValid=${result.addAmount != null}',
    );
    widget.onApply(result);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(true);
  }

  void _cancel() {
    widget.trace.log('편집 취소: section=${widget.section.name}');
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  Future<void> _showDeveloperTrace() async {
    widget.trace.log(
      '개발자 로그 Status Dialog 요청: section=${widget.section.name}',
    );
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '$_title 편집 로그',
      description: '현재 편집 동작의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
    );
  }

  Widget _identityEditor(BuildContext context) {
    return TextField(
      controller: _countTypeController,
      textInputAction: TextInputAction.done,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.deny(RegExp(r'[\n\r]')),
      ],
      onChanged: (_) {
        if (_submitted) setState(() {});
      },
      decoration: opsInputDecoration(
        context,
        label: '정산 유형명',
        prefixIcon: const Icon(Icons.label_rounded),
        errorText: _submitted && !_identityOk ? '정산 유형명을 입력하세요.' : null,
      ),
    );
  }

  Widget _standardDropdown({
    Key? key,
    required BuildContext context,
    required String label,
    required IconData icon,
    required int? value,
    required List<int> options,
    required ValueChanged<int?> onChanged,
    required bool showError,
  }) {
    return DropdownButtonFormField<int>(
      key: key,
      value: value,
      isExpanded: true,
      decoration: opsInputDecoration(
        context,
        label: label,
        prefixIcon: Icon(icon),
        errorText: showError ? '$label을 선택하세요.' : null,
      ),
      items: options
          .map(
            (minutes) => DropdownMenuItem<int>(
              value: minutes,
              child: Text('$minutes분'),
            ),
          )
          .toList(growable: false),
      onChanged: onChanged,
    );
  }

  Widget _amountField({
    required BuildContext context,
    required String label,
    required TextEditingController controller,
    required bool valid,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      onChanged: (_) {
        if (_submitted) setState(() {});
      },
      decoration: opsInputDecoration(
        context,
        label: label,
        prefixIcon: const Icon(Icons.payments_rounded),
        suffixText: '원',
        errorText: _submitted && !valid ? '$label을 0 이상 숫자로 입력하세요.' : null,
      ),
    );
  }

  Widget _pricingEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          child: _standardDropdown(
            key: ValueKey<int?>(_basicStandard),
            context: context,
            label: '기본 시간',
            icon: Icons.timer_rounded,
            value: _basicStandard,
            options: _basicStandardOptions,
            showError: _submitted && _basicStandard == null,
            onChanged: (value) {
              setState(() => _basicStandard = value);
              widget.trace.log('기본 시간 변경: minutes=${value ?? -1}');
            },
          ),
        ),
        const SizedBox(height: 12),
        _amountField(
          context: context,
          label: '기본 요금',
          controller: _basicAmountController,
          valid: _basicAmountOk,
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          child: _standardDropdown(
            key: ValueKey<int?>(_addStandard),
            context: context,
            label: '추가 시간',
            icon: Icons.more_time_rounded,
            value: _addStandard,
            options: _addStandardOptions,
            showError: _submitted && _addStandard == null,
            onChanged: (value) {
              setState(() => _addStandard = value);
              widget.trace.log('추가 시간 변경: minutes=${value ?? -1}');
            },
          ),
        ),
        const SizedBox(height: 12),
        _amountField(
          context: context,
          label: '추가 요금',
          controller: _addAmountController,
          valid: _addAmountOk,
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    switch (widget.section) {
      case BillSettingsSection.identity:
        return _identityEditor(context);
      case BillSettingsSection.pricing:
        return _pricingEditor(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
          child: Row(
            children: [
              Icon(_icon, size: 20, color: tokens.accent),
              const SizedBox(width: 9),
              Expanded(
                child: AnimatedSwitcher(
                  duration: _reduceMotion
                      ? Duration.zero
                      : CommonUiMotion.selection,
                  child: Text(
                    _title,
                    key: ValueKey<String>(_title),
                    style: textTheme.titleSmall?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (widget.trace.developerMode)
                IconButton(
                  tooltip: '개발자 로그',
                  onPressed: _showDeveloperTrace,
                  icon: Icon(
                    Icons.bug_report_rounded,
                    size: 19,
                    color: tokens.warning,
                  ),
                ),
              IconButton(
                tooltip: '닫기',
                onPressed: _cancel,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Container(height: 1, color: tokens.borderSubtle),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: _body(context),
          ),
        ),
        Container(height: 1, color: tokens.borderSubtle),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: CommonButton(
                  label: '취소',
                  icon: Icons.close_rounded,
                  onPressed: _cancel,
                  variant: CommonButtonVariant.secondary,
                  haptic: CommonHaptic.selection,
                  minHeight: 42,
                  expand: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CommonButton(
                  label: '적용',
                  icon: Icons.check_rounded,
                  onPressed: _apply,
                  variant: CommonButtonVariant.primary,
                  haptic: CommonHaptic.selection,
                  minHeight: 42,
                  expand: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
