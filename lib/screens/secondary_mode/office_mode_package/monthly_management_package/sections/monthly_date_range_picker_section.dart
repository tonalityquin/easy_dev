import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MonthlyDateRangePickerSection extends StatefulWidget {
  final TextEditingController startDateController;
  final TextEditingController endDateController;
  final String periodUnit;
  final int duration;

  const MonthlyDateRangePickerSection({
    super.key,
    required this.startDateController,
    required this.endDateController,
    required this.periodUnit,
    required this.duration,
  });

  @override
  State<MonthlyDateRangePickerSection> createState() =>
      _MonthlyDateRangePickerSectionState();
}

class _MonthlyDateRangePickerSectionState
    extends State<MonthlyDateRangePickerSection> {
  String? _errorText;

  void _onStartDateTap() async {
    final picked = await _showManualDateInputSheet(initialDate: DateTime.now());
    if (picked != null) {
      widget.startDateController.text = _formatDate(picked);

      final endDate = _calculateEndDate(picked);
      widget.endDateController.text = _formatDate(endDate);

      _validateRange();
    }
  }

  void _onEndDateTap() async {
    final picked = await _showManualDateInputSheet(initialDate: DateTime.now());
    if (picked != null) {
      widget.endDateController.text = _formatDate(picked);
      _validateRange();
    }
  }

  DateTime _calculateEndDate(DateTime startDate) {
    switch (widget.periodUnit) {
      case '일':
        return startDate.add(Duration(days: widget.duration));
      case '주':
        return startDate.add(Duration(days: widget.duration * 7));
      case '월':
        return DateTime(
            startDate.year, startDate.month + widget.duration, startDate.day);
      default:
        return startDate.add(const Duration(days: 30)); // fallback
    }
  }

  void _validateRange() {
    final start = _parseDate(widget.startDateController.text);
    final end = _parseDate(widget.endDateController.text);

    setState(() {
      if (start == null || end == null) {
        _errorText = '유효한 날짜를 입력해주세요.';
      } else if (start.isAfter(end)) {
        _errorText = '⚠ 시작일은 종료일보다 이전이어야 합니다.';
      } else {
        _errorText = null;
      }
    });
  }

  Future<DateTime?> _showManualDateInputSheet(
      {required DateTime initialDate}) async {
    final yearCtrl = TextEditingController(text: initialDate.year.toString());
    final monthCtrl =
    TextEditingController(text: initialDate.month.toString().padLeft(2, '0'));
    final dayCtrl =
    TextEditingController(text: initialDate.day.toString().padLeft(2, '0'));

    String? localError;

    return await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final insets = MediaQuery.of(ctx).viewInsets;

        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border.all(color: cs.outlineVariant),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Padding(
              padding: insets.add(const EdgeInsets.only(bottom: 16)),
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle
                        Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Text(
                          '날짜 입력 (숫자만)',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _buildDateField(context, '년 (YYYY)', yearCtrl,
                                maxLen: 4),
                            const SizedBox(width: 12),
                            _buildDateField(context, '월 (MM)', monthCtrl,
                                maxLen: 2),
                            const SizedBox(width: 12),
                            _buildDateField(context, '일 (DD)', dayCtrl,
                                maxLen: 2),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (localError != null)
                          Text(
                            localError!,
                            style: TextStyle(color: cs.error),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  shape: const StadiumBorder(),
                                  side: BorderSide(color: cs.outlineVariant),
                                  foregroundColor: Colors.black87,
                                ),
                                child: const Text('취소'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  final year = int.tryParse(yearCtrl.text);
                                  final month = int.tryParse(monthCtrl.text);
                                  final day = int.tryParse(dayCtrl.text);

                                  if (year == null ||
                                      month == null ||
                                      day == null) {
                                    setModalState(() => localError = '숫자를 정확히 입력해주세요.');
                                    return;
                                  }

                                  try {
                                    final selectedDate = DateTime(year, month, day);
                                    Navigator.of(context).pop(selectedDate);
                                  } catch (_) {
                                    setModalState(
                                            () => localError = '존재하지 않는 날짜입니다.');
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  backgroundColor: cs.primary,
                                  foregroundColor: cs.onPrimary,
                                  shape: const StadiumBorder(),
                                ),
                                child: const Text('선택 완료'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDateField(BuildContext context, String label,
      TextEditingController controller,
      {required int maxLen}) {
    final cs = Theme.of(context).colorScheme;

    return Expanded(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(maxLen),
        ],
        decoration: InputDecoration(
          labelText: label,
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
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  DateTime? _parseDate(String text) {
    try {
      return DateTime.parse(text);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    InputDecoration _pickerDecoration(String label) => InputDecoration(
      labelText: label,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '정기 정산 기간 (${widget.duration}${widget.periodUnit})',
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.startDateController,
                readOnly: true,
                onTap: _onStartDateTap,
                decoration: _pickerDecoration('시작일'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: widget.endDateController,
                readOnly: true,
                onTap: _onEndDateTap,
                decoration: _pickerDecoration('종료일'),
              ),
            ),
          ],
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorText!,
            style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}
