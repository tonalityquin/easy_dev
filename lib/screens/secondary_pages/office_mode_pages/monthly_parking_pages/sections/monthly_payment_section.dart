import 'package:flutter/material.dart';
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

  Future<void> _handlePayment() async {
    setState(() => _isPaying = true);
    try {
      widget.controller.specialNote = _noteController.text;

      await widget.controller.recordPaymentHistory(context);

      if (!mounted) return;

      setState(() {
        _paymentHistoryLog.insert(
          0,
          '${DateTime.now().toLocal().toString().substring(0, 16)} - 결제 완료'
          '${_noteController.text.isNotEmpty ? ' | 메모: ${_noteController.text}' : ''}',
        );
      });

      _noteController.clear();
      widget.controller.specialNote = '';
      widget.controller.isExtended = false;
      widget.onExtendedChanged(false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('결제 내역이 저장되었습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('결제 실패: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPaying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        TextFormField(
          controller: _noteController,
          decoration: const InputDecoration(
            labelText: '특이사항',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ElevatedButton.icon(
              onPressed: _isPaying ? null : _handlePayment,
              icon: _isPaying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.payment),
              label: Text(_isPaying ? '처리 중...' : '결제'),
            ),
            Row(
              children: [
                Checkbox(
                  value: widget.controller.isExtended,
                  onChanged: widget.onExtendedChanged,
                ),
                const Text('연장 여부'),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          '최근 결제 내역',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_paymentHistoryLog.isEmpty) const Text('결제 내역이 없습니다.', style: TextStyle(color: Colors.grey)),
        ..._paymentHistoryLog.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $entry'),
            )),
      ],
    );
  }
}
