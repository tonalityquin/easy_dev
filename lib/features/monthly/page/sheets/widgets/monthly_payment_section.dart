import 'package:flutter/material.dart';

import '../../../controllers/monthly_plate_controller.dart';

const _paymentInk = Color(0xFF101828);
const _paymentMuted = Color(0xFF667085);
const _paymentPanel = Color(0xFFFFFFFF);
const _paymentLine = Color(0xFFD8DEE8);
const _paymentBlue = Color(0xFF2563EB);
const _paymentGreen = Color(0xFF059669);

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
      final extended = widget.controller.isExtended;
      setState(() {
        _paymentHistoryLog.insert(
          0,
          '$label 결제 완료${_noteController.text.trim().isNotEmpty ? ' · ${_noteController.text.trim()}' : ''}${extended ? ' · 기간 연장' : ''}',
        );
      });
      _noteController.clear();
      widget.controller.specialNote = '';
      widget.controller.isExtended = false;
      widget.onExtendedChanged(false);
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('결제가 저장되었습니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('결제 저장에 실패했습니다. 다시 시도해주세요.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  InputDecoration _inputDecoration({required String label}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _paymentMuted, fontWeight: FontWeight.w800),
      floatingLabelStyle: const TextStyle(color: _paymentBlue, fontWeight: FontWeight.w900),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _paymentLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _paymentBlue, width: 1.4),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _paymentPanel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _paymentLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.point_of_sale_outlined, color: _paymentBlue, size: 19),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '결제 입력',
                      style: TextStyle(color: _paymentInk, fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '메모와 연장 여부를 확인한 뒤 저장합니다.',
                      style: TextStyle(color: _paymentMuted, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _noteController,
            decoration: _inputDecoration(label: '결제 메모'),
            maxLines: 2,
            style: const TextStyle(color: _paymentInk, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () {
              final next = !widget.controller.isExtended;
              setState(() => widget.controller.isExtended = next);
              widget.onExtendedChanged(next);
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: widget.controller.isExtended ? const Color(0xFFECFDF3) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: widget.controller.isExtended ? _paymentGreen.withOpacity(.28) : _paymentLine),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: widget.controller.isExtended,
                    activeColor: _paymentGreen,
                    onChanged: (val) {
                      setState(() => widget.controller.isExtended = val ?? false);
                      widget.onExtendedChanged(val);
                    },
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '결제 후 다음 기간으로 연장',
                          style: TextStyle(color: _paymentInk, fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '결제 내역 저장과 기간 갱신을 한 번에 처리합니다.',
                          style: TextStyle(color: _paymentMuted, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isPaying ? null : _handlePayment,
              style: FilledButton.styleFrom(
                backgroundColor: _paymentInk,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: _isPaying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(
                _isPaying ? '처리 중...' : '결제 저장',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          if (_paymentHistoryLog.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              '이번 화면 처리 내역',
              style: TextStyle(color: _paymentInk, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ..._paymentHistoryLog.map((item) {
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _paymentLine),
                ),
                child: Text(
                  item,
                  style: const TextStyle(color: _paymentSlate, fontWeight: FontWeight.w800),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

const _paymentSlate = Color(0xFF334155);
