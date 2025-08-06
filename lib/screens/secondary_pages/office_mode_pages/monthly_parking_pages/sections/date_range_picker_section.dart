import 'package:flutter/material.dart';

class DateRangePickerSection extends StatefulWidget {
  final TextEditingController startDateController;
  final TextEditingController endDateController;
  final String periodUnit; // ✅ 추가
  final int duration;       // ✅ 추가

  const DateRangePickerSection({
    super.key,
    required this.startDateController,
    required this.endDateController,
    required this.periodUnit,
    required this.duration,
  });

  @override
  State<DateRangePickerSection> createState() => _DateRangePickerSectionState();
}

class _DateRangePickerSectionState extends State<DateRangePickerSection> {
  String? _errorText;

  void _onStartDateTap() async {
    final picked = await _showManualDateInputSheet(initialDate: DateTime.now());
    if (picked != null) {
      widget.startDateController.text = _formatDate(picked);

      // ✅ 종료일 계산
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
        return DateTime(startDate.year, startDate.month + widget.duration, startDate.day);
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

  Future<DateTime?> _showManualDateInputSheet({required DateTime initialDate}) async {
    final yearCtrl = TextEditingController(text: initialDate.year.toString());
    final monthCtrl = TextEditingController(text: initialDate.month.toString().padLeft(2, '0'));
    final dayCtrl = TextEditingController(text: initialDate.day.toString().padLeft(2, '0'));

    String? localError;

    return await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return Padding(
          padding: MediaQuery.of(context).viewInsets.add(const EdgeInsets.all(16)),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('날짜 입력 (숫자만)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildDateField('년 (YYYY)', yearCtrl),
                      const SizedBox(width: 12),
                      _buildDateField('월 (MM)', monthCtrl),
                      const SizedBox(width: 12),
                      _buildDateField('일 (DD)', dayCtrl),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (localError != null)
                    Text(localError!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      final year = int.tryParse(yearCtrl.text);
                      final month = int.tryParse(monthCtrl.text);
                      final day = int.tryParse(dayCtrl.text);

                      if (year == null || month == null || day == null) {
                        setModalState(() => localError = '숫자를 정확히 입력해주세요.');
                        return;
                      }

                      try {
                        final selectedDate = DateTime(year, month, day);
                        Navigator.of(context).pop(selectedDate);
                      } catch (_) {
                        setModalState(() => localError = '존재하지 않는 날짜입니다.');
                      }
                    },
                    child: const Text('선택 완료'),
                  ),
                  const SizedBox(height: 80),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDateField(String label, TextEditingController controller) {
    return Expanded(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '정기 정산 기간 (${widget.duration}${widget.periodUnit})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.startDateController,
                readOnly: true,
                onTap: _onStartDateTap,
                decoration: const InputDecoration(
                  labelText: '시작일',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: widget.endDateController,
                readOnly: true,
                onTap: _onEndDateTap,
                decoration: const InputDecoration(
                  labelText: '종료일',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorText!,
            style: const TextStyle(color: Colors.red),
          ),
        ],
      ],
    );
  }
}
