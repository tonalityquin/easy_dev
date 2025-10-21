// lib/screens/type_package/common_widgets/dashboard_bottom_sheet/widgets/home_end_work_report_content.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/area/area_state.dart';
import '../../../../../../states/user/user_state.dart';
import '../../../../../repositories/plate_repo_services/plate_count_service.dart';
import '../../../../../../utils/snackbar_helper.dart';
// import '../../../../../../utils/usage_reporter.dart';

const _kBasePad = 16.0;

// ── Brand palette (minimal use only)
const Color _base  = Color(0xFF0D47A1);
const Color _light = Color(0xFF5472D3);

class HomeEndWorkReportContent extends StatefulWidget {
  final Future<void> Function(String reportType, String content) onReport;
  final int? initialVehicleInput; // 입차
  final int? initialVehicleOutput; // 출차
  final ScrollController? externalScrollController;

  const HomeEndWorkReportContent({
    super.key,
    required this.onReport,
    this.initialVehicleInput,
    this.initialVehicleOutput,
    this.externalScrollController,
  });

  @override
  State<HomeEndWorkReportContent> createState() => _HomeEndWorkReportContentState();
}

class _HomeEndWorkReportContentState extends State<HomeEndWorkReportContent> {
  final _formKey = GlobalKey<FormState>();
  final _inputCtrl = TextEditingController(); // 입차
  final _outputCtrl = TextEditingController(); // 출차
  final _inputFocus = FocusNode();
  final _outputFocus = FocusNode();

  bool _submitting = false;
  bool _reloadingInput = false;
  bool _reloadingOutput = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialVehicleInput != null) {
      _inputCtrl.text = widget.initialVehicleInput.toString();
    }
    if (widget.initialVehicleOutput != null) {
      _outputCtrl.text = widget.initialVehicleOutput.toString();
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _outputCtrl.dispose();
    _inputFocus.dispose();
    _outputFocus.dispose();
    super.dispose();
  }

  String? _numberValidator(String? v) {
    if (v == null || v.trim().isEmpty) return '값을 입력하세요';
    final ok = RegExp(r'^\d+$').hasMatch(v.trim());
    if (!ok) return '숫자만 입력 가능합니다';
    return null;
  }

  Future<void> _refetchInput() async {
    final area = context.read<AreaState>().currentArea;
    if (!mounted) return;
    setState(() => _reloadingInput = true);
    try {
      final v = await PlateCountService().getParkingCompletedCountAll(area);
      if (!mounted) return;
      _inputCtrl.text = v.toString();
      if (!mounted) return;
      HapticFeedback.selectionClick();
    } catch (_) {
      // no-op
    } finally {
      if (mounted) setState(() => _reloadingInput = false);
    }
  }

  Future<void> _refetchOutput() async {
    final area = context.read<AreaState>().currentArea;
    if (!mounted) return;
    setState(() => _reloadingOutput = true);
    try {
      final v = await PlateCountService().getDepartureCompletedCountAll(area);
      if (!mounted) return;
      _outputCtrl.text = v.toString();
      if (!mounted) return;
      HapticFeedback.selectionClick();
    } catch (_) {
      // no-op
    } finally {
      if (mounted) setState(() => _reloadingOutput = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (!mounted) return;
    setState(() => _submitting = true);
    try {
      final user = Provider.of<UserState>(context, listen: false).user;
      final division = user?.divisions.first;
      final area = context.read<AreaState>().currentArea;

      if (division == null || area.isEmpty) {
        if (!mounted) return;
        showFailedSnackbar(context, '지역/부서 정보가 없습니다.');
        return;
      }

      final entry = int.tryParse(_inputCtrl.text.trim());
      final exit = int.tryParse(_outputCtrl.text.trim());

      if (entry == null || exit == null) {
        if (!mounted) return;
        showFailedSnackbar(context, '입차/출차 차량 수는 숫자만 입력 가능합니다.');
        return;
      }

      // 상위 onReport에서 스냅샷 기반 처리
      final reportMap = <String, dynamic>{
        'vehicleInput': entry,
        'vehicleOutput': exit,
      };

      await widget.onReport('end', jsonEncode(reportMap));
      if (!mounted) return;

      await _refetchOutput();
      if (!mounted) return;

      HapticFeedback.mediumImpact();
      if (!mounted) return;
      showSuccessSnackbar(context, '업무 종료 보고를 제출했습니다.');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '보고 제출 실패: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom + _kBasePad;
    return SingleChildScrollView(
      controller: widget.externalScrollController,
      padding: EdgeInsets.fromLTRB(_kBasePad, 8, _kBasePad, bottomPad),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _LabeledNumberField(
                    label: '입차 차량 수',
                    controller: _inputCtrl,
                    focusNode: _inputFocus,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(_outputFocus),
                    validator: _numberValidator,
                    helper: '현재 지역의 parking_completed 전체 문서 기준 자동 집계',
                    suffix: _reloadingInput
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(_base),
                      ),
                    )
                        : IconButton(
                      tooltip: '입차 수 재계산',
                      icon: const Icon(Icons.refresh, color: _base),
                      onPressed: _refetchInput,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LabeledNumberField(
                    label: '출차 차량 수',
                    controller: _outputCtrl,
                    focusNode: _outputFocus,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
                    validator: _numberValidator,
                    helper:
                    '현재 지역의 departure_completed & 잠금요금(true) 전체 문서 기준',
                    suffix: _reloadingOutput
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(_base),
                      ),
                    )
                        : IconButton(
                      tooltip: '출차 수 재계산',
                      icon: const Icon(Icons.refresh, color: _base),
                      onPressed: _refetchOutput,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _base,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _light.withOpacity(.5),
                ),
                icon: _submitting
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : const Icon(Icons.send),
                label: Text(_submitting ? '제출 중…' : '제출'),
                onPressed: _submitting
                    ? null
                    : () async {
                  if (!(_formKey.currentState?.validate() ?? false)) {
                    HapticFeedback.lightImpact();
                    return;
                  }
                  await _handleSubmit();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledNumberField extends StatelessWidget {
  const _LabeledNumberField({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.textInputAction,
    required this.onFieldSubmitted,
    required this.validator,
    required this.helper,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextInputAction textInputAction;
  final void Function(String) onFieldSubmitted;
  final String? Function(String?) validator;
  final String helper;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).dividerColor.withOpacity(.2);
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(width: 1.6, color: _base), // brand on focus
        ),
        suffixIcon: suffix,
      ),
    );
  }
}
