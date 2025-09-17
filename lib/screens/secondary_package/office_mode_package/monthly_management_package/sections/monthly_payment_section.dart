import 'package:flutter/material.dart';
import '../../../../../utils/snackbar_helper.dart';
import '../monthly_plate_controller.dart';

/// 정기 결제 섹션
/// - 결제 진행 상태 표시 및 중복 클릭 방지
/// - 결제 성공/실패 스낵바 안내
/// - 메모 입력 및 연장 여부 토글
/// - 최근 결제 내역(로컬 로그) 표시
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
    // 컨트롤러에 보관중인 특이사항을 초기값으로 반영
    _noteController.text = widget.controller.specialNote;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  /// 간단한 날짜/시간 포맷(yyyy.MM.dd HH:mm)
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

    // === 유효성 가드 ===
    if (!widget.controller.isInputValid()) {
      showFailedSnackbar(context, '번호판을 먼저 정확히 입력하세요.');
      return;
    }
    final amount =
    int.tryParse(widget.controller.amountController?.text.trim() ?? '');
    if (amount == null || amount <= 0) {
      showFailedSnackbar(context, '결제 금액을 확인해주세요.');
      return;
    }
    // ==================

    setState(() => _isPaying = true);
    try {
      widget.controller.specialNote = _noteController.text;

      // 파이어스토어에 결제 내역 기록
      await widget.controller.recordPaymentHistory(context);
      if (!mounted) return;

      // 로컬 로그(낙관적 업데이트)
      final label = _formatNow();
      setState(() {
        _paymentHistoryLog.insert(
          0,
          '$label - 결제 완료'
              '${_noteController.text.isNotEmpty ? ' | 메모: ${_noteController.text}' : ''}',
        );
      });

      // 입력값 초기화
      _noteController.clear();
      widget.controller.specialNote = '';

      // 연장 여부 초기화(+부모 콜백 알림)
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

  InputDecoration _noteDecoration(ColorScheme cs) => InputDecoration(
    labelText: '특이사항',
    isDense: true,
    contentPadding:
    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    filled: true,
    fillColor: cs.surface,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: cs.outlineVariant),
      borderRadius: BorderRadius.circular(10),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: cs.primary, width: 1.6),
      borderRadius: BorderRadius.circular(10),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final ButtonStyle payStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),

        // 특이사항 입력 (색 반영)
        TextFormField(
          controller: _noteController,
          decoration: _noteDecoration(cs),
          maxLines: 2,
        ),
        const SizedBox(height: 16),

        // 결제 + 연장여부
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isPaying ? null : _handlePayment,
              style: payStyle,
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
              label: Text(_isPaying ? '처리 중...' : '결제'),
            ),
            const SizedBox(width: 12),
            // 접근성/터치타깃 개선 + 내부 즉시 반영
            Expanded(
              child: CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
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
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                activeColor: cs.primary,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 최근 결제 내역
        Text(
          '최근 결제 내역',
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (_paymentHistoryLog.isEmpty)
          Text(
            '결제 내역이 없습니다.',
            style: text.bodyMedium?.copyWith(color: Colors.grey),
          )
        else
          ..._paymentHistoryLog.map(
                (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $entry'),
            ),
          ),
      ],
    );
  }
}
