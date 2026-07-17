import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../dev/application/area_state.dart';

class BillSettingBottomSheet extends StatefulWidget {
  final Function(Map<String, dynamic> billData) onSave;

  const BillSettingBottomSheet({super.key, required this.onSave});

  @override
  State<BillSettingBottomSheet> createState() => _BillSettingBottomSheetState();
}

class _BillSettingBottomSheetState extends State<BillSettingBottomSheet> {
  final TextEditingController _billController = TextEditingController();
  final TextEditingController _basicAmountController = TextEditingController();
  final TextEditingController _addAmountController = TextEditingController();
  String? _basicStandardValue;
  String? _addStandardValue;
  String? _errorMessage;

  static const List<String> _basicStandardOptions = <String>['1분', '5분', '30분', '60분', '120분', '240분'];
  static const List<String> _addStandardOptions = <String>['1분', '10분', '30분', '60분'];

  @override
  void dispose() {
    _billController.dispose();
    _basicAmountController.dispose();
    _addAmountController.dispose();
    super.dispose();
  }

  int? _digitsToInt(String s) {
    final onlyDigits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (onlyDigits.isEmpty) return null;
    return int.tryParse(onlyDigits);
  }

  int _standardToMinutes(String value) {
    return int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  String _formatAmount(String value) {
    final amount = _digitsToInt(value);
    if (amount == null) return '미입력';
    return '₩$amount';
  }

  void _setError(String? message) {
    setState(() => _errorMessage = message);
  }

  void _clearErrorIfAny() {
    setState(() => _errorMessage = null);
  }

  bool _validateInput() {
    final countTypeOk = _billController.text.trim().isNotEmpty;
    final basicStdOk = _basicStandardValue != null;
    final addStdOk = _addStandardValue != null;
    final basicAmount = _digitsToInt(_basicAmountController.text);
    final addAmount = _digitsToInt(_addAmountController.text);

    if (!countTypeOk) {
      _setError('정산 유형명을 입력하세요.');
      return false;
    }
    if (!basicStdOk) {
      _setError('기본 시간을 선택하세요.');
      return false;
    }
    if (basicAmount == null || basicAmount < 0) {
      _setError('기본 요금을 0 이상 숫자로 입력하세요.');
      return false;
    }
    if (!addStdOk) {
      _setError('추가 시간을 선택하세요.');
      return false;
    }
    if (addAmount == null || addAmount < 0) {
      _setError('추가 요금을 0 이상 숫자로 입력하세요.');
      return false;
    }

    _setError(null);
    return true;
  }

  void _handleSave() {
    FocusScope.of(context).unfocus();
    if (!_validateInput()) return;

    final currentArea = context.read<AreaState>().currentArea;
    final billData = <String, dynamic>{
      'type': '변동',
      'CountType': _billController.text.trim(),
      'basicStandard': _standardToMinutes(_basicStandardValue!),
      'basicAmount': _digitsToInt(_basicAmountController.text) ?? 0,
      'addStandard': _standardToMinutes(_addStandardValue!),
      'addAmount': _digitsToInt(_addAmountController.text) ?? 0,
      'area': currentArea,
      'isSelected': false,
    };

    widget.onSave(billData);
    Navigator.pop(context);
  }

  Widget _buildRuleNameSection(BuildContext context) {
    return OpsWorkSection(
      title: '정산 유형명',
      subtitle: '요금 정책을 운영자가 목록에서 즉시 식별할 수 있는 이름으로 등록합니다.',
      icon: Icons.receipt_long_rounded,
      child: TextField(
        controller: _billController,
        onChanged: (_) => _clearErrorIfAny(),
        textInputAction: TextInputAction.next,
        inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\n\r]'))],
        decoration: opsInputDecoration(
          context,
          label: '변동 정산 유형',
          prefixIcon: const Icon(Icons.label_rounded),
          errorText: _errorMessage == '정산 유형명을 입력하세요.' ? _errorMessage : null,
        ),
      ),
    );
  }

  Widget _buildStandardDropdown({
    required BuildContext context,
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    required IconData icon,
    required String? errorText,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: opsInputDecoration(context, label: label, prefixIcon: Icon(icon), errorText: errorText),
      items: options.map((option) => DropdownMenuItem<String>(value: option, child: Text(option))).toList(growable: false),
      onChanged: (next) {
        _clearErrorIfAny();
        onChanged(next);
      },
    );
  }

  Widget _buildAmountField({
    required BuildContext context,
    required String label,
    required TextEditingController controller,
    required String? errorText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => _clearErrorIfAny(),
      decoration: opsInputDecoration(
        context,
        label: label,
        prefixIcon: const Icon(Icons.payments_rounded),
        suffixText: '원',
        errorText: errorText,
      ),
    );
  }

  Widget _buildPriceRuleSection(BuildContext context) {
    return OpsWorkSection(
      title: '요금 기준',
      subtitle: '입차 후 기본 시간과 초과 시간별 추가 요금을 지정합니다.',
      icon: Icons.calculate_rounded,
      child: Column(
        children: [
          _buildStandardDropdown(
            context: context,
            label: '기본 시간',
            value: _basicStandardValue,
            options: _basicStandardOptions,
            onChanged: (next) => setState(() => _basicStandardValue = next),
            icon: Icons.timer_rounded,
            errorText: _errorMessage == '기본 시간을 선택하세요.' ? _errorMessage : null,
          ),
          const SizedBox(height: 12),
          _buildAmountField(
            context: context,
            label: '기본 요금',
            controller: _basicAmountController,
            errorText: _errorMessage == '기본 요금을 0 이상 숫자로 입력하세요.' ? _errorMessage : null,
          ),
          const SizedBox(height: 12),
          _buildStandardDropdown(
            context: context,
            label: '추가 시간',
            value: _addStandardValue,
            options: _addStandardOptions,
            onChanged: (next) => setState(() => _addStandardValue = next),
            icon: Icons.more_time_rounded,
            errorText: _errorMessage == '추가 시간을 선택하세요.' ? _errorMessage : null,
          ),
          const SizedBox(height: 12),
          _buildAmountField(
            context: context,
            label: '추가 요금',
            controller: _addAmountController,
            errorText: _errorMessage == '추가 요금을 0 이상 숫자로 입력하세요.' ? _errorMessage : null,
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = _billController.text.trim().isEmpty ? '정산 유형 미입력' : _billController.text.trim();
    return OpsWorkSection(
      title: '저장 전 요약',
      subtitle: '등록 후 정산 관리 목록에 표시될 변동 요금 기준입니다.',
      icon: Icons.fact_check_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name,
            style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -.2),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OpsInfoPill(text: '변동 정산', icon: Icons.dynamic_feed_rounded),
              OpsInfoPill(text: '기본 ${_basicStandardValue ?? '미선택'}', icon: Icons.timer_rounded),
              OpsInfoPill(text: _formatAmount(_basicAmountController.text), icon: Icons.payments_rounded),
              OpsInfoPill(text: '추가 ${_addStandardValue ?? '미선택'}', icon: Icons.more_time_rounded),
              OpsInfoPill(text: _formatAmount(_addAmountController.text), icon: Icons.add_card_rounded),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentArea = context.watch<AreaState>().currentArea.trim();
    final areaLabel = currentArea.isEmpty ? '지역 미설정' : currentArea;
    final basicAmount = _digitsToInt(_basicAmountController.text);
    final addAmount = _digitsToInt(_addAmountController.text);

    return OpsWorkSheet(
      title: '정산 유형 등록',
      subtitle: '현장 입차 정산에 사용할 변동 요금 정책을 생성합니다.',
      icon: Icons.receipt_long_rounded,
      areaLabel: areaLabel,
      metrics: [
        OpsMetric(label: '유형', value: _billController.text.trim().isEmpty ? '필수' : '입력', icon: Icons.label_rounded, color: _billController.text.trim().isEmpty ? cs.error : cs.primary),
        OpsMetric(label: '기본', value: _basicStandardValue ?? '-', icon: Icons.timer_rounded, color: _basicStandardValue == null ? cs.error : cs.primary),
        OpsMetric(label: '기본요금', value: basicAmount == null ? '-' : '$basicAmount', icon: Icons.payments_rounded, color: basicAmount == null ? cs.error : cs.primary),
        OpsMetric(label: '추가', value: _addStandardValue ?? '-', icon: Icons.more_time_rounded, color: _addStandardValue == null ? cs.error : cs.primary),
      ],
      bottomBar: OpsBottomActionBar(
        children: [
          Expanded(
            child: OpsActionButton(
              label: '취소',
              icon: Icons.close_rounded,
              onPressed: () => Navigator.pop(context),
              tonal: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OpsActionButton(
              label: '정산 유형 저장',
              icon: Icons.save_rounded,
              onPressed: _handleSave,
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpsInlineMessage(message: _errorMessage),
          OpsCommandPanel(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OpsInfoPill(text: '변동 정산', icon: Icons.dynamic_feed_rounded),
                  OpsInfoPill(text: areaLabel, icon: Icons.business_rounded),
                  OpsInfoPill(text: addAmount == null ? '추가 요금 미입력' : '추가 $addAmount원', icon: Icons.add_card_rounded),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRuleNameSection(context),
          _buildPriceRuleSection(context),
          _buildPreviewSection(context),
        ],
      ),
    );
  }
}
