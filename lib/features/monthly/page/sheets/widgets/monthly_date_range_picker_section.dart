import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../application/monthly_date_range_calculator.dart';
import '../../../domain/monthly_parking_options.dart';
import '../../widgets/monthly_prompt_ui.dart';

class MonthlyDateRangePickerSection extends StatefulWidget {
  const MonthlyDateRangePickerSection({
    super.key,
    required this.startDateController,
    required this.endDateController,
    required this.periodUnit,
    required this.duration,
    this.regularType,
  });

  final TextEditingController startDateController;
  final TextEditingController endDateController;
  final String periodUnit;
  final int duration;
  final String? regularType;

  @override
  State<MonthlyDateRangePickerSection> createState() =>
      _MonthlyDateRangePickerSectionState();
}

class _MonthlyDateRangePickerSectionState
    extends State<MonthlyDateRangePickerSection> {
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
    if (oldWidget.duration != widget.duration ||
        oldWidget.periodUnit != widget.periodUnit ||
        oldWidget.regularType != widget.regularType) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _recalculateEndDateFromCurrentStart();
      });
    }
  }

  @override
  void dispose() {
    widget.startDateController.removeListener(_handleControllerChanged);
    widget.endDateController.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) _validateRange();
  }

  DateTime? _parse(String value) {
    return MonthlyDateRangeCalculator.parseStrict(value);
  }

  String _format(DateTime date) {
    return MonthlyDateRangeCalculator.format(date);
  }

  void _recalculateEndDateFromCurrentStart() {
    final start = _parse(widget.startDateController.text);
    if (start == null) {
      _validateRange();
      return;
    }
    final duration = widget.duration <= 0 ? 1 : widget.duration;
    final normalizedStart = MonthlyDateRangeCalculator.normalizeStartDate(
      startDate: start,
      regularType: widget.regularType,
    );
    final end = MonthlyDateRangeCalculator.calculateEndDate(
      startDate: normalizedStart,
      duration: duration,
      periodUnit: widget.periodUnit,
      regularType: widget.regularType,
    );
    if (_format(normalizedStart) != _format(start)) {
      widget.startDateController.text = _format(normalizedStart);
    }
    widget.endDateController.text = _format(end);
    _validateRange();
  }

  String? _rangeError() {
    final startText = widget.startDateController.text.trim();
    final endText = widget.endDateController.text.trim();
    final start = _parse(startText);
    final end = _parse(endText);
    if (startText.isEmpty && endText.isEmpty) return null;
    if (start == null || end == null) return '유효한 날짜를 선택해주세요.';
    if (start.isAfter(end)) return '시작일은 종료일보다 늦을 수 없습니다.';
    if (MonthlyParkingOptions.isWeekendType(widget.regularType) &&
        _format(start) !=
            _format(MonthlyDateRangeCalculator.nextSaturdayOnOrAfter(start))) {
      return '주말권 시작일은 토요일이어야 합니다.';
    }
    final expectedEnd = MonthlyDateRangeCalculator.calculateEndDate(
      startDate: start,
      duration: widget.duration <= 0 ? 1 : widget.duration,
      periodUnit: widget.periodUnit,
      regularType: widget.regularType,
    );
    if (_format(expectedEnd) != _format(end)) {
      return '종료일이 상품 기간 정보와 일치하지 않습니다.';
    }
    return null;
  }

  void _validateRange() {
    final next = _rangeError();
    if (next == _errorText || !mounted) return;
    setState(() => _errorText = next);
  }

  void _applyStartDate(DateTime selected) {
    final duration = widget.duration <= 0 ? 1 : widget.duration;
    final normalizedStart = MonthlyDateRangeCalculator.normalizeStartDate(
      startDate: selected,
      regularType: widget.regularType,
    );
    final end = MonthlyDateRangeCalculator.calculateEndDate(
      startDate: normalizedStart,
      duration: duration,
      periodUnit: widget.periodUnit,
      regularType: widget.regularType,
    );
    widget.startDateController.text = _format(normalizedStart);
    widget.endDateController.text = _format(end);
    _validateRange();
  }

  Future<void> _pickStartDate() async {
    final picked = await _showManualDateInputSheet(
      initialDate: _parse(widget.startDateController.text) ?? DateTime.now(),
    );
    if (picked != null) _applyStartDate(picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await _showManualDateInputSheet(
      initialDate: _parse(widget.endDateController.text) ?? DateTime.now(),
    );
    if (picked == null) return;
    widget.endDateController.text = _format(picked);
    _validateRange();
  }

  String? _summaryBadgeText() {
    if (MonthlyParkingOptions.isWeekendType(widget.regularType)) {
      return '주말 ${widget.duration <= 0 ? 1 : widget.duration}회';
    }
    final start = _parse(widget.startDateController.text);
    final end = _parse(widget.endDateController.text);
    if (start == null || end == null || start.isAfter(end)) return null;
    return '총 ${MonthlyDateRangeCalculator.daysBetweenInclusive(start, end)}일';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final summaryBadge = _summaryBadgeText();
    final description = MonthlyParkingOptions.isWeekendType(widget.regularType)
        ? '주말권은 토요일부터 시작하며 기간 1은 주말 1회로 계산합니다.'
        : '${widget.duration <= 0 ? 1 : widget.duration}${widget.periodUnit} 기준으로 종료일을 계산합니다.';

    return MonthlyPromptSection(
      title: '정기권 기간',
      subtitle: description,
      icon: Icons.event_available_outlined,
      delay: const Duration(milliseconds: 110),
      trailing: summaryBadge == null
          ? null
          : MonthlyPromptBadge(
              label: summaryBadge,
              icon: Icons.date_range_rounded,
              tone: _errorText == null
                  ? MonthlyPromptMessageTone.success
                  : MonthlyPromptMessageTone.warning,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickDateButton(
                label: '오늘',
                onTap: () => _applyStartDate(DateTime.now()),
              ),
              _QuickDateButton(
                label: '내일',
                onTap: () =>
                    _applyStartDate(DateTime.now().add(const Duration(days: 1))),
              ),
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
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
            switchInCurve: PromptUiMotion.enter,
            switchOutCurve: PromptUiMotion.exit,
            child: _errorText == null
                ? const SizedBox.shrink(
                    key: ValueKey<String>('date-range-valid'),
                  )
                : Container(
                    key: ValueKey<String>(_errorText!),
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.dangerContainer,
                      borderRadius:
                          BorderRadius.circular(PromptUiShapes.control),
                      border: Border.all(
                        color: tokens.danger.withOpacity(0.28),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: tokens.onDangerContainer,
                          size: 19,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorText!,
                            style: textTheme.bodyMedium?.copyWith(
                              color: tokens.onDangerContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<DateTime?> _showManualDateInputSheet({
    required DateTime initialDate,
  }) async {
    final yearController = TextEditingController(
      text: initialDate.year.toString().padLeft(4, '0'),
    );
    final monthController = TextEditingController(
      text: initialDate.month.toString().padLeft(2, '0'),
    );
    final dayController = TextEditingController(
      text: initialDate.day.toString().padLeft(2, '0'),
    );
    String? localError;

    final result = await showPromptOverlayBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      transparentBackground: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final tokens = PromptUiTheme.of(context);
            final textTheme = Theme.of(context).textTheme;
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Material(
                color: tokens.surfaceRaised,
                surfaceTintColor: tokens.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(PromptUiShapes.sheet),
                  ),
                  side: BorderSide(color: tokens.borderSubtle),
                ),
                clipBehavior: Clip.antiAlias,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: tokens.handle,
                              borderRadius:
                                  BorderRadius.circular(PromptUiShapes.pill),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: tokens.accentContainer,
                                borderRadius: BorderRadius.circular(
                                  PromptUiShapes.control,
                                ),
                              ),
                              child: Icon(
                                Icons.edit_calendar_outlined,
                                color: tokens.onAccentContainer,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '날짜 직접 입력',
                                    style: textTheme.titleMedium?.copyWith(
                                      color: tokens.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '년, 월, 일을 숫자로 입력하세요.',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PromptIconButton(
                              icon: Icons.close_rounded,
                              tooltip: '닫기',
                              haptic: PromptHaptic.selection,
                              onPressed: () =>
                                  Navigator.of(sheetContext).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _ManualDateField(
                                label: 'YYYY',
                                controller: yearController,
                                maxLength: 4,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ManualDateField(
                                label: 'MM',
                                controller: monthController,
                                maxLength: 2,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ManualDateField(
                                label: 'DD',
                                controller: dayController,
                                maxLength: 2,
                              ),
                            ),
                          ],
                        ),
                        AnimatedSwitcher(
                          duration: MediaQuery.maybeOf(context)
                                      ?.disableAnimations ??
                                  false
                              ? Duration.zero
                              : PromptUiMotion.component,
                          child: localError == null
                              ? const SizedBox.shrink(
                                  key: ValueKey<String>('manual-date-valid'),
                                )
                              : Padding(
                                  key: ValueKey<String>(localError!),
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    localError!,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: tokens.danger,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: PromptButton(
                                label: '취소',
                                variant: PromptButtonVariant.tertiary,
                                haptic: PromptHaptic.selection,
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: PromptButton(
                                label: '적용',
                                icon: Icons.check_rounded,
                                haptic: PromptHaptic.medium,
                                onPressed: () {
                                  final date =
                                      MonthlyDateRangeCalculator.composeStrict(
                                    year: int.tryParse(yearController.text),
                                    month: int.tryParse(monthController.text),
                                    day: int.tryParse(dayController.text),
                                  );
                                  if (date == null) {
                                    setSheetState(() {
                                      localError =
                                          '존재하는 날짜를 정확히 입력해주세요.';
                                    });
                                    return;
                                  }
                                  Navigator.of(sheetContext).pop(date);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    yearController.dispose();
    monthController.dispose();
    dayController.dispose();
    return result;
  }
}

class _QuickDateButton extends StatelessWidget {
  const _QuickDateButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PromptButton(
      label: label,
      variant: PromptButtonVariant.tertiary,
      minHeight: 38,
      haptic: PromptHaptic.selection,
      onPressed: onTap,
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
    final tokens = PromptUiTheme.of(context);
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w700,
          ),
      decoration: monthlyPromptInputDecoration(
        context,
        label: label,
        suffixIcon: Icon(
          Icons.edit_calendar_outlined,
          color: tokens.iconSecondary,
        ),
      ),
    );
  }
}

class _ManualDateField extends StatelessWidget {
  const _ManualDateField({
    required this.label,
    required this.controller,
    required this.maxLength,
  });

  final String label;
  final TextEditingController controller;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(maxLength),
      ],
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w700,
          ),
      decoration: monthlyPromptInputDecoration(
        context,
        label: label,
      ),
    );
  }
}
