import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/monthly_date_range_calculator.dart';

const _dateInk = Color(0xFF101828);
const _dateMuted = Color(0xFF667085);
const _datePanel = Color(0xFFFFFFFF);
const _dateLine = Color(0xFFD8DEE8);
const _dateBlue = Color(0xFF2563EB);
const _dateCanvas = Color(0xFFF3F6FA);
const _dateRed = Color(0xFFDC2626);

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
  State<MonthlyDateRangePickerSection> createState() => _MonthlyDateRangePickerSectionState();
}

class _MonthlyDateRangePickerSectionState extends State<MonthlyDateRangePickerSection> {
  String? _errorText;

  @override
  void initState() {
    super.initState();
    widget.startDateController.addListener(_handleControllerChanged);
    widget.endDateController.addListener(_handleControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _validateRange();
    });
  }

  @override
  void didUpdateWidget(covariant MonthlyDateRangePickerSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDateController != widget.startDateController) {
      oldWidget.startDateController.removeListener(_handleControllerChanged);
      widget.startDateController.addListener(_handleControllerChanged);
    }
    if (oldWidget.endDateController != widget.endDateController) {
      oldWidget.endDateController.removeListener(_handleControllerChanged);
      widget.endDateController.addListener(_handleControllerChanged);
    }
    if (oldWidget.duration != widget.duration || oldWidget.periodUnit != widget.periodUnit) {
      _recalculateEndDateFromCurrentStart();
    }
  }

  @override
  void dispose() {
    widget.startDateController.removeListener(_handleControllerChanged);
    widget.endDateController.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    _validateRange();
  }

  void _recalculateEndDateFromCurrentStart() {
    final start = _parse(widget.startDateController.text);
    if (start == null) {
      _validateRange();
      return;
    }
    final duration = widget.duration <= 0 ? 1 : widget.duration;
    final end = MonthlyDateRangeCalculator.calculateEndDate(
      startDate: start,
      duration: duration,
      periodUnit: widget.periodUnit,
    );
    widget.endDateController.text = _format(end);
    _validateRange();
  }

  DateTime? _parse(String value) {
    return MonthlyDateRangeCalculator.parseStrict(value);
  }

  String _format(DateTime date) {
    return MonthlyDateRangeCalculator.format(date);
  }

  void _validateRange() {
    final start = _parse(widget.startDateController.text);
    final end = _parse(widget.endDateController.text);
    setState(() {
      if (widget.startDateController.text.trim().isEmpty && widget.endDateController.text.trim().isEmpty) {
        _errorText = null;
      } else if (start == null || end == null) {
        _errorText = '유효한 날짜를 선택해주세요.';
      } else if (start.isAfter(end)) {
        _errorText = '시작일은 종료일보다 늦을 수 없습니다.';
      } else {
        _errorText = null;
      }
    });
  }

  void _applyStartDate(DateTime selected) {
    final duration = widget.duration <= 0 ? 1 : widget.duration;
    final end = MonthlyDateRangeCalculator.calculateEndDate(
      startDate: selected,
      duration: duration,
      periodUnit: widget.periodUnit,
    );
    widget.startDateController.text = _format(selected);
    widget.endDateController.text = _format(end);
    _validateRange();
  }

  Future<void> _pickStartDate() async {
    final picked = await _showManualDateInputSheet(initialDate: _parse(widget.startDateController.text) ?? DateTime.now());
    if (picked != null) _applyStartDate(picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await _showManualDateInputSheet(initialDate: _parse(widget.endDateController.text) ?? DateTime.now());
    if (picked != null) {
      widget.endDateController.text = _format(picked);
      _validateRange();
    }
  }

  int? _totalDays() {
    final start = _parse(widget.startDateController.text);
    final end = _parse(widget.endDateController.text);
    if (start == null || end == null || start.isAfter(end)) return null;
    return MonthlyDateRangeCalculator.daysBetweenInclusive(start, end);
  }

  @override
  Widget build(BuildContext context) {
    final totalDays = _totalDays();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _datePanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _dateLine),
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
                child: const Icon(Icons.event_available_outlined, color: _dateBlue, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '정기권 기간',
                      style: TextStyle(color: _dateInk, fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.duration <= 0 ? 1 : widget.duration}${widget.periodUnit} 기준으로 종료일을 계산합니다.',
                      style: const TextStyle(color: _dateMuted, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (totalDays != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _dateLine),
                  ),
                  child: Text(
                    '총 $totalDays일',
                    style: const TextStyle(color: _dateInk, fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickDateButton(label: '오늘', onTap: () => _applyStartDate(DateTime.now())),
              _QuickDateButton(label: '내일', onTap: () => _applyStartDate(DateTime.now().add(const Duration(days: 1)))),
              _QuickDateButton(
                label: '이번 달 1일',
                onTap: () {
                  final now = DateTime.now();
                  _applyStartDate(DateTime(now.year, now.month, 1));
                },
              ),
              _QuickDateButton(
                label: '다음 달 1일',
                onTap: () {
                  final now = DateTime.now();
                  _applyStartDate(DateTime(now.year, now.month + 1, 1));
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DateReadField(
                  label: '시작일',
                  controller: widget.startDateController,
                  onTap: _pickStartDate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateReadField(
                  label: '종료일',
                  controller: widget.endDateController,
                  onTap: _pickEndDate,
                ),
              ),
            ],
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _dateRed.withOpacity(.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _dateRed.withOpacity(.25)),
              ),
              child: Text(
                _errorText!,
                style: const TextStyle(color: _dateRed, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<DateTime?> _showManualDateInputSheet({required DateTime initialDate}) async {
    final yearCtrl = TextEditingController(text: initialDate.year.toString().padLeft(4, '0'));
    final monthCtrl = TextEditingController(text: initialDate.month.toString().padLeft(2, '0'));
    final dayCtrl = TextEditingController(text: initialDate.day.toString().padLeft(2, '0'));
    String? localError;

    final result = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: _dateCanvas,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                    border: Border(top: BorderSide(color: _dateLine)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCBD5E1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '날짜 직접 입력',
                        style: TextStyle(color: _dateInk, fontWeight: FontWeight.w900, fontSize: 20),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '년, 월, 일을 숫자로 입력하세요.',
                        style: TextStyle(color: _dateMuted, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _ManualDateField(label: 'YYYY', controller: yearCtrl, maxLen: 4)),
                          const SizedBox(width: 10),
                          Expanded(child: _ManualDateField(label: 'MM', controller: monthCtrl, maxLen: 2)),
                          const SizedBox(width: 10),
                          Expanded(child: _ManualDateField(label: 'DD', controller: dayCtrl, maxLen: 2)),
                        ],
                      ),
                      if (localError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          localError!,
                          style: const TextStyle(color: _dateRed, fontWeight: FontWeight.w900),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(sheetCtx).pop(),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text('취소'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                final date = MonthlyDateRangeCalculator.composeStrict(
                                  year: int.tryParse(yearCtrl.text),
                                  month: int.tryParse(monthCtrl.text),
                                  day: int.tryParse(dayCtrl.text),
                                );
                                if (date == null) {
                                  setModalState(() => localError = '존재하는 날짜를 정확히 입력해주세요.');
                                  return;
                                }
                                Navigator.of(sheetCtx).pop(date);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: _dateInk,
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text('적용'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    yearCtrl.dispose();
    monthCtrl.dispose();
    dayCtrl.dispose();
    return result;
  }
}

class _QuickDateButton extends StatelessWidget {
  const _QuickDateButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _dateLine),
        ),
        child: Text(
          label,
          style: const TextStyle(color: _dateInk, fontWeight: FontWeight.w900, fontSize: 12),
        ),
      ),
    );
  }
}

class _DateReadField extends StatelessWidget {
  const _DateReadField({
    required this.label,
    required this.controller,
    required this.onTap,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      style: const TextStyle(color: _dateInk, fontWeight: FontWeight.w900),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _dateMuted, fontWeight: FontWeight.w800),
        suffixIcon: const Icon(Icons.edit_calendar_outlined, color: _dateMuted),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _dateLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _dateBlue, width: 1.4),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _ManualDateField extends StatelessWidget {
  const _ManualDateField({
    required this.label,
    required this.controller,
    required this.maxLen,
  });

  final String label;
  final TextEditingController controller;
  final int maxLen;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(maxLen),
      ],
      style: const TextStyle(color: _dateInk, fontWeight: FontWeight.w900, fontSize: 18),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _dateMuted, fontWeight: FontWeight.w800),
        filled: true,
        fillColor: _datePanel,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _dateLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _dateBlue, width: 1.4),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
