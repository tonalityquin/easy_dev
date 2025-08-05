import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class DateRangePickerSection extends StatefulWidget {
  final TextEditingController startDateController;
  final TextEditingController endDateController;

  const DateRangePickerSection({
    super.key,
    required this.startDateController,
    required this.endDateController,
  });

  @override
  State<DateRangePickerSection> createState() => _DateRangePickerSectionState();
}

class _DateRangePickerSectionState extends State<DateRangePickerSection> {
  String? _errorText;

  Future<void> _showManualDateInputSheet({
    required DateTime initialDate,
    required void Function(DateTime) onDateSelected,
  }) async {
    final yearController = TextEditingController(text: initialDate.year.toString());
    final monthController = TextEditingController(text: initialDate.month.toString().padLeft(2, '0'));
    final dayController = TextEditingController(text: initialDate.day.toString().padLeft(2, '0'));

    String? errorText;

    await showModalBottomSheet(
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
                  const Text(
                    '날짜 입력 (숫자만)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: yearController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '년 (YYYY)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: monthController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '월 (MM)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: dayController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '일 (DD)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (errorText != null)
                    Text(
                      errorText!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: Colors.black12),
                      ),
                    ),
                    onPressed: () {
                      final year = int.tryParse(yearController.text);
                      final month = int.tryParse(monthController.text);
                      final day = int.tryParse(dayController.text);

                      if (year == null || month == null || day == null) {
                        setModalState(() {
                          errorText = '숫자를 정확히 입력해주세요.';
                        });
                        return;
                      }

                      try {
                        final selected = DateTime(year, month, day);
                        Navigator.of(context).pop();
                        onDateSelected(selected);
                      } catch (_) {
                        setModalState(() {
                          errorText = '존재하지 않는 날짜입니다.';
                        });
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

  void _onStartDateTap() async {
    final picked = DateTime.now();
    await _showManualDateInputSheet(
      initialDate: picked,
      onDateSelected: (date) {
        final formatted = _formatDate(date);
        widget.startDateController.text = formatted;

        final endDate = date.add(const Duration(days: 30));
        widget.endDateController.text = _formatDate(endDate);

        _validateRange();
      },
    );
  }

  void _onEndDateTap() async {
    final picked = DateTime.now();
    await _showManualDateInputSheet(
      initialDate: picked,
      onDateSelected: (date) {
        widget.endDateController.text = _formatDate(date);
        _validateRange();
      },
    );
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

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  DateTime? _parseDate(String text) {
    try {
      return DateTime.parse(text.replaceAll('년 ', '-').replaceAll('월 ', '-').replaceAll('일', ''));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '정기 정산 기간',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
