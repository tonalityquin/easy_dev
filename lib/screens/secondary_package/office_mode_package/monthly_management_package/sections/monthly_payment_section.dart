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
    // ✅ 메모리 누수 방지
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
    // ✅ 포커스 해제(키보드 닫기)
    FocusScope.of(context).unfocus();

    // === [추가] 간단 유효성 가드 ===
    // 번호판 유효성
    if (!widget.controller.isInputValid()) {
      showFailedSnackbar(context, '번호판을 먼저 정확히 입력하세요.');
      return;
    }
    // 결제 금액 유효성 (없거나 0 이하면 거부)
    final amount = int.tryParse(widget.controller.amountController?.text.trim() ?? '');
    if (amount == null || amount <= 0) {
      showFailedSnackbar(context, '결제 금액을 확인해주세요.');
      return;
    }
    // === [끝] 간단 유효성 가드 ===

    setState(() => _isPaying = true);
    try {
      // 컨트롤러로 메모 전달
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

      // ✅ 성공 스낵바
      showSuccessSnackbar(context, '결제 내역이 저장되었습니다.');
    } catch (e) {
      if (!mounted) return;
      // ❌ 실패 스낵바
      showFailedSnackbar(context, '결제 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _isPaying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),

        // 특이사항 입력
        TextFormField(
          controller: _noteController,
          decoration: const InputDecoration(
            labelText: '특이사항',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),

        // 결제 + 연장여부
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
            const SizedBox(width: 12),
            // ✅ 접근성/터치타깃 개선 + 내부 즉시 반영
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
                title: const Text('연장 여부'),
                activeColor: cs.primary,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 최근 결제 내역
        const Text(
          '최근 결제 내역',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_paymentHistoryLog.isEmpty)
          const Text('결제 내역이 없습니다.', style: TextStyle(color: Colors.grey)),
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
