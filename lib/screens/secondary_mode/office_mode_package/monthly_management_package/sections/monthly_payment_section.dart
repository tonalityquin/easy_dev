import 'package:flutter/material.dart';
import '../../../../../../utils/snackbar_helper.dart';
import '../monthly_plate_controller.dart';

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

    widget.controller.specialNote = _noteController.text.trim();

    if (!widget.controller.validatePaymentBeforeWrite(context)) return;

    setState(() => _isPaying = true);
    try {
      await widget.controller.processPayment(context);
      if (!mounted) return;

      final label = _formatNow();
      setState(() {
        _paymentHistoryLog.insert(
          0,
          '$label - 결제 완료'
              '${_noteController.text.trim().isNotEmpty ? ' | 메모: ${_noteController.text.trim()}' : ''}'
              '${widget.controller.isExtended ? ' | 연장' : ''}',
        );
      });

      _noteController.clear();
      widget.controller.specialNote = '';

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
      floatingLabelStyle: TextStyle(
        color: cs.primary,
        fontWeight: FontWeight.w700,
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      filled: true,
      fillColor: cs.surfaceVariant.withOpacity(.30),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.65)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 1.2),
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
            color: cs.shadow.withOpacity(.06),
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
                  color: cs.primaryContainer.withOpacity(.60),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                ),
                child: Icon(Icons.payment_outlined, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '결제',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
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
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  icon: _isPaying
                      ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(cs.onPrimary),
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
                    color: cs.surfaceVariant.withOpacity(.30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
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
                        color: cs.onSurface,
                      ),
                    ),
                    activeColor: cs.primary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Icon(Icons.history, color: cs.onSurfaceVariant, size: 18),
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
              style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant.withOpacity(.70)),
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
                          color: cs.primary.withOpacity(.85),
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
