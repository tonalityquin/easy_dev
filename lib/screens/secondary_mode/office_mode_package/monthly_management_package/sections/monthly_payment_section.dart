import 'package:flutter/material.dart';
import '../../../../../../utils/snackbar_helper.dart';
import '../monthly_plate_controller.dart';

class _SvcColors {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const light = Color(0xFF5472D3);
  static const fg = Color(0xFFFFFFFF);
}

/// 결제 섹션(결제 전용)
/// - 결제 저장/연장 여부/메모
/// - 실제 저장 로직은 MonthlyPlateController.processPayment로 위임
class MonthlyPaymentSection extends StatefulWidget {
  final MonthlyPlateController controller;
  final Function(bool?) onExtendedChanged;

  const MonthlyPaymentSection({
    super.key,
    required this.controller,
    required this.onExtendedChanged,
  });

  @override
  State<MonthlyPaymentSection> createState() => _MonthlyPaymentSectionState();
}

class _MonthlyPaymentSectionState extends State<MonthlyPaymentSection> {
  final TextEditingController _noteController = TextEditingController();
  bool _isPaying = false;

  // 로컬 표시용 로그(기존 유지)
  final List<String> _paymentHistoryLog = [];

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
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '$y.$m.$d $hh:$mm';
  }

  Future<void> _handlePayment() async {
    FocusScope.of(context).unfocus();

    // 메모 반영(결제 직전)
    widget.controller.specialNote = _noteController.text.trim();

    // 컨트롤러에서 결제 검증/저장 처리
    if (!widget.controller.validatePaymentBeforeWrite(context)) {
      return;
    }

    setState(() => _isPaying = true);
    try {
      await widget.controller.processPayment(context);
      if (!mounted) return;

      // 로컬 로그(낙관적 업데이트)
      final label = _formatNow();
      setState(() {
        _paymentHistoryLog.insert(
          0,
          '$label - 결제 완료'
              '${_noteController.text.trim().isNotEmpty ? ' | 메모: ${_noteController.text.trim()}' : ''}'
              '${widget.controller.isExtended ? ' | 연장' : ''}',
        );
      });

      // 입력값 초기화(기존 흐름 유지)
      _noteController.clear();
      widget.controller.specialNote = '';

      // 연장 여부 초기화(+부모 콜백)
      widget.controller.isExtended = false;
      widget.onExtendedChanged(false);

      showSuccessSnackbar(context, '결제 내역이 저장되었습니다.');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '결제 실패: $e');
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  InputDecoration _svcInputDecoration(BuildContext context, {required String label}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      floatingLabelStyle: const TextStyle(
        color: _SvcColors.dark,
        fontWeight: FontWeight.w700,
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      filled: true,
      fillColor: _SvcColors.light.withOpacity(.06),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _SvcColors.light.withOpacity(.45)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _SvcColors.base, width: 1.2),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.error.withOpacity(.8)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.error, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _SvcColors.light.withOpacity(.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _SvcColors.light.withOpacity(.40)),
                ),
                child: const Icon(Icons.payment_outlined, color: _SvcColors.dark),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '결제',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: _SvcColors.dark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 특이사항
          TextFormField(
            controller: _noteController,
            decoration: _svcInputDecoration(context, label: '특이사항(결제 메모)'),
            maxLines: 2,
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isPaying ? null : _handlePayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _SvcColors.base,
                    foregroundColor: _SvcColors.fg,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  icon: _isPaying
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_SvcColors.fg),
                    ),
                  )
                      : const Icon(Icons.payment),
                  label: Text(_isPaying ? '처리 중...' : '결제 저장'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _SvcColors.light.withOpacity(.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _SvcColors.light.withOpacity(.35)),
                  ),
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    controlAffinity: ListTileControlAffinity.leading,
                    value: widget.controller.isExtended,
                    onChanged: (val) {
                      setState(() {
                        widget.controller.isExtended = val ?? false;
                      });
                      widget.onExtendedChanged(val);
                    },
                    title: Text(
                      '연장 여부',
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: _SvcColors.dark,
                      ),
                    ),
                    activeColor: _SvcColors.base,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              const Icon(Icons.history, color: _SvcColors.dark, size: 18),
              const SizedBox(width: 8),
              Text(
                '최근 결제 내역(로컬)',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_paymentHistoryLog.isEmpty)
            Text(
              '결제 내역이 없습니다.',
              style: text.bodyMedium?.copyWith(color: Colors.black.withOpacity(.45)),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < _paymentHistoryLog.length; i++) ...[
                    ListTile(
                      dense: true,
                      title: Text(
                        _paymentHistoryLog[i],
                        style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      leading: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _SvcColors.base.withOpacity(.85),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    if (i != _paymentHistoryLog.length - 1)
                      Divider(height: 1, color: cs.outlineVariant.withOpacity(.45)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
