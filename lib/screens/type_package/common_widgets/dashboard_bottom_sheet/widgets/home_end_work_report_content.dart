import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/area/area_state.dart';
import '../../../../../../utils/snackbar_helper.dart';
import '../../../../../repositories/plate_repo_services/plate_count_service.dart';

typedef OnReport = Future<void> Function(String type, String content);

class HomeEndWorkReportContent extends StatefulWidget {
  const HomeEndWorkReportContent({
    super.key,
    required this.initialVehicleInput,
    required this.initialVehicleOutput,
    required this.onReport,
  });

  final int initialVehicleInput;
  final int initialVehicleOutput;
  final OnReport onReport;

  @override
  State<HomeEndWorkReportContent> createState() =>
      _HomeEndWorkReportContentState();
}

class _HomeEndWorkReportContentState extends State<HomeEndWorkReportContent> {
  late final TextEditingController _inputCtrl;
  late final TextEditingController _outputCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _inputCtrl =
        TextEditingController(text: widget.initialVehicleInput.toString());
    _outputCtrl =
        TextEditingController(text: widget.initialVehicleOutput.toString());
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _outputCtrl.dispose();
    super.dispose();
  }

  Future<void> _refetchInput() async {
    final area = context.read<AreaState>().currentArea;
    try {
      final v = await PlateCountService()
          .getParkingCompletedCountAll(area)
          .timeout(const Duration(seconds: 10));
      _inputCtrl.text = '$v';
      HapticFeedback.selectionClick();
    } catch (_) {
      if (mounted) showFailedSnackbar(context, '입차 재집계 실패');
    }
  }

  Future<void> _refetchOutput() async {
    final area = context.read<AreaState>().currentArea;
    try {
      final v = await PlateCountService()
          .getDepartureCompletedCountAll(area)
          .timeout(const Duration(seconds: 10));
      _outputCtrl.text = '$v';
      HapticFeedback.selectionClick();
    } catch (_) {
      if (mounted) showFailedSnackbar(context, '출차 재집계 실패');
    }
  }

  Future<void> _handleSubmit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) {
      showFailedSnackbar(context, '숫자만 입력해 주세요.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final content = {
        'vehicleInput': int.tryParse(_inputCtrl.text) ?? 0,
        'vehicleOutput': int.tryParse(_outputCtrl.text) ?? 0,
      };
      await widget.onReport('end', jsonEncode(content)); // JSON 문자열로 전달
      HapticFeedback.lightImpact();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final area = context.watch<AreaState>().currentArea;

    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.assignment_turned_in),
            title: const Text(
              '업무 종료 보고',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('지역: $area'),
            trailing: IconButton(
              tooltip: '닫기',
              icon: const Icon(Icons.close),
              onPressed: () => widget.onReport('cancel', ''),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24 + 72),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _InfoCard(
                      title: '집계 기준',
                      lines: const [
                        '• 입차: parking_completed 문서 전체(현재 지역)',
                        '• 출차: departure_completed + 잠금요금(true) 문서 전체(현재 지역)',
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: '차량 수 입력',
                      child: Column(
                        children: [
                          _numberField(
                            context: context,
                            controller: _inputCtrl,
                            label: '입차 차량 수',
                            helper: 'parking_completed 전체 문서 기준 자동 집계',
                            onRefresh: _refetchInput,
                          ),
                          const SizedBox(height: 12),
                          _numberField(
                            context: context,
                            controller: _outputCtrl,
                            label: '출차 차량 수',
                            helper:
                            'departure_completed & 잠금요금(true) 전체 문서 기준',
                            onRefresh: _refetchOutput,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _FooterBar(
            onCancel: () => widget.onReport('cancel', ''),
            onSubmit: _handleSubmit,
            busy: _submitting,
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    String? helper,
    VoidCallback? onRefresh,
  }) {
    final cs = Theme.of(context).colorScheme;
    final suffix = onRefresh == null
        ? null
        : IconButton(
      onPressed: onRefresh,
      icon: const Icon(Icons.refresh),
      tooltip: '재집계',
    );
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        suffixIcon: suffix,
        isDense: true,
        filled: true,
        fillColor: cs.surfaceVariant.withOpacity(0.35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary),
        ),
      ),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      keyboardType: TextInputType.number,
      validator: (v) {
        if (v == null || v.isEmpty) return '값을 입력해 주세요.';
        if (int.tryParse(v) == null) return '정수만 입력 가능합니다.';
        return null;
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.lines});
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall!
                  .copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            ...lines.map(
                  (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(e),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.directions_car, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall!
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _FooterBar extends StatelessWidget {
  const _FooterBar({
    required this.onCancel,
    required this.onSubmit,
    required this.busy,
  });

  final VoidCallback onCancel;
  final VoidCallback onSubmit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: cs.surface,
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, -6),
            ),
          ],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onCancel,
                child: const Text('취소'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: busy ? null : onSubmit,
                child: busy
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Text('제출'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
