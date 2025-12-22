import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ✅ AppCardPalette 사용 (프로젝트 경로에 맞게 수정)
// 예: import 'package:your_app/theme/app_card_palette.dart';
import '../../../../../theme.dart';

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
        return DateTime(startDate.year, startDate.month + widget.duration, startDate.day);
      default:
        return startDate.add(const Duration(days: 30));
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

  InputDecoration _svcInputDecoration(
      BuildContext context, {
        required String label,
        String? helperText,
        Widget? suffixIcon,
        String? errorText,
      }) {
    final cs = Theme.of(context).colorScheme;
    final palette = AppCardPalette.of(context);

    return InputDecoration(
      labelText: label,
      helperText: helperText,
      errorText: errorText,
      floatingLabelStyle: TextStyle(
        color: palette.serviceDark,
        fontWeight: FontWeight.w700,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: palette.serviceLight.withOpacity(.06),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.serviceLight.withOpacity(.45)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.serviceBase, width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.error.withOpacity(.8)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.error, width: 1.4),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Future<DateTime?> _showManualDateInputSheet({required DateTime initialDate}) async {
    final yearCtrl = TextEditingController(text: initialDate.year.toString());
    final monthCtrl = TextEditingController(text: initialDate.month.toString().padLeft(2, '0'));
    final dayCtrl = TextEditingController(text: initialDate.day.toString().padLeft(2, '0'));

    String? localError;

    return await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final cs = Theme.of(sheetCtx).colorScheme;
        final palette = AppCardPalette.of(sheetCtx);
        final insets = MediaQuery.of(sheetCtx).viewInsets;

        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.08),
                  blurRadius: 14,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Padding(
              padding: insets.add(const EdgeInsets.only(bottom: 16)),
              child: StatefulBuilder(
                builder: (ctx, setModalState) {
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: cs.outlineVariant.withOpacity(.6),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),

                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: palette.serviceLight.withOpacity(.18),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: palette.serviceLight.withOpacity(.40)),
                              ),
                              child: Icon(Icons.event_outlined, color: palette.serviceDark),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '날짜 입력',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: palette.serviceDark,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '닫기',
                              onPressed: () => Navigator.of(sheetCtx).pop(),
                              icon: const Icon(Icons.close),
                              color: palette.serviceDark,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: palette.serviceLight.withOpacity(.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: palette.serviceLight.withOpacity(.25)),
                          ),
                          child: Text(
                            '년/월/일을 숫자로 입력하세요.',
                            style: TextStyle(
                              color: palette.serviceDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        Row(
                          children: [
                            _buildDateField(ctx, '년 (YYYY)', yearCtrl, maxLen: 4),
                            const SizedBox(width: 12),
                            _buildDateField(ctx, '월 (MM)', monthCtrl, maxLen: 2),
                            const SizedBox(width: 12),
                            _buildDateField(ctx, '일 (DD)', dayCtrl, maxLen: 2),
                          ],
                        ),

                        if (localError != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.error.withOpacity(.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.error.withOpacity(.30)),
                            ),
                            child: Text(
                              localError!,
                              style: TextStyle(
                                color: cs.error,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 14),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(sheetCtx).pop(),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  shape: const StadiumBorder(),
                                  side: BorderSide(color: palette.serviceLight.withOpacity(.75)),
                                  foregroundColor: palette.serviceDark,
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

                                  if (year == null || month == null || day == null) {
                                    setModalState(() => localError = '숫자를 정확히 입력해주세요.');
                                    return;
                                  }

                                  try {
                                    final selectedDate = DateTime(year, month, day);
                                    Navigator.of(sheetCtx).pop(selectedDate);
                                  } catch (_) {
                                    setModalState(() => localError = '존재하지 않는 날짜입니다.');
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  backgroundColor: palette.serviceBase,
                                  foregroundColor: Colors.white,
                                  shape: const StadiumBorder(),
                                  elevation: 0,
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

  Widget _buildDateField(
      BuildContext context,
      String label,
      TextEditingController controller, {
        required int maxLen,
      }) {
    return Expanded(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(maxLen),
        ],
        decoration: _svcInputDecoration(
          context,
          label: label,
          helperText: maxLen == 4 ? '예: 2025' : (maxLen == 2 ? '예: 01' : null),
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
    final palette = AppCardPalette.of(context);

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
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: palette.serviceLight.withOpacity(.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.serviceLight.withOpacity(.40)),
                ),
                child: Icon(Icons.date_range_outlined, color: palette.serviceDark),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '정기 정산 기간 (${widget.duration}${widget.periodUnit})',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: palette.serviceDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.startDateController,
                  readOnly: true,
                  onTap: _onStartDateTap,
                  decoration: _svcInputDecoration(
                    context,
                    label: '시작일',
                    helperText: '탭하여 날짜 선택',
                    suffixIcon: Icon(Icons.edit_calendar_outlined, color: palette.serviceDark),
                    errorText: null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: widget.endDateController,
                  readOnly: true,
                  onTap: _onEndDateTap,
                  decoration: _svcInputDecoration(
                    context,
                    label: '종료일',
                    helperText: '탭하여 날짜 선택',
                    suffixIcon: Icon(Icons.edit_calendar_outlined, color: palette.serviceDark),
                    errorText: null,
                  ),
                ),
              ),
            ],
          ),

          if (_errorText != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.error.withOpacity(.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.error.withOpacity(.30)),
              ),
              child: Text(
                _errorText!,
                style: TextStyle(
                  color: cs.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
