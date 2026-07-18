import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';

class TimeFieldSpec {
  const TimeFieldSpec({
    required this.id,
    required this.label,
    required this.initial,
  });

  final String id;
  final String label;
  final String initial;
}

typedef TimeSheetValidator = String? Function(Map<String, String> values);

Future<Map<String, String>?> showTimeEditSheet({
  required BuildContext context,
  required DateTime date,
  required List<TimeFieldSpec> fields,
  List<TimeSheetValidator> validators = const [],
  String? title,
  bool usePromptUi = false,
}) {
  Widget buildSheet(BuildContext sheetContext) {
    return _TimeEditSheet(
      date: date,
      fields: fields,
      validators: validators,
      title: title,
      usePromptUi: usePromptUi,
    );
  }

  if (usePromptUi) {
    return showPromptOverlayBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      transparentBackground: false,
      builder: buildSheet,
    );
  }

  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: buildSheet,
  );
}

class _TimeEditSheet extends StatefulWidget {
  const _TimeEditSheet({
    required this.date,
    required this.fields,
    required this.validators,
    required this.title,
    required this.usePromptUi,
  });

  final DateTime date;
  final List<TimeFieldSpec> fields;
  final List<TimeSheetValidator> validators;
  final String? title;
  final bool usePromptUi;

  @override
  State<_TimeEditSheet> createState() => _TimeEditSheetState();
}

class _TimeEditSheetState extends State<_TimeEditSheet> {
  late final Map<String, TextEditingController> _hourControllers;
  late final Map<String, TextEditingController> _minuteControllers;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _hourControllers = {};
    _minuteControllers = {};
    for (final field in widget.fields) {
      final parts = (field.initial.isNotEmpty ? field.initial : '00:00')
          .split(':');
      _hourControllers[field.id] = TextEditingController(
        text: parts.isNotEmpty ? parts[0] : '00',
      );
      _minuteControllers[field.id] = TextEditingController(
        text: parts.length > 1 ? parts[1] : '00',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _hourControllers.values) {
      controller.dispose();
    }
    for (final controller in _minuteControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _dateLabel(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String? _validate(Map<String, String> values) {
    for (final value in values.values) {
      final parts = value.split(':');
      if (parts.length != 2) return '시간 형식은 HH:mm 이어야 합니다.';
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) return '숫자만 입력해 주세요.';
      if (hour < 0 || hour > 23) return '시(0~23)를 확인해 주세요.';
      if (minute < 0 || minute > 59) return '분(0~59)을 확인해 주세요.';
    }
    for (final validator in widget.validators) {
      final message = validator(values);
      if (message != null) return message;
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final values = <String, String>{};
    for (final field in widget.fields) {
      final hour = _hourControllers[field.id]!.text.trim().padLeft(2, '0');
      final minute =
          _minuteControllers[field.id]!.text.trim().padLeft(2, '0');
      values[field.id] = '$hour:$minute';
    }
    final error = _validate(values);
    if (error != null) {
      setState(() => _error = error);
      await HapticFeedback.mediumImpact();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    Navigator.of(context).pop<Map<String, String>>(values);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return ColoredBox(
      color: tokens.surfaceRaised,
      child: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
          curve: PromptUiMotion.standard,
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.handle,
                      borderRadius: BorderRadius.circular(PromptUiShapes.pill),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: tokens.accentContainer,
                        borderRadius:
                            BorderRadius.circular(PromptUiShapes.control),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.schedule_rounded,
                        color: tokens.onAccentContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title ?? _dateLabel(widget.date),
                        style: textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    PromptIconButton(
                      icon: Icons.close_rounded,
                      tooltip: '닫기',
                      onPressed: () => Navigator.of(context).pop(),
                      haptic: PromptHaptic.selection,
                    ),
                  ],
                ),
                AnimatedSize(
                  duration:
                      reduceMotion ? Duration.zero : PromptUiMotion.component,
                  curve: PromptUiMotion.standard,
                  child: _error == null
                      ? const SizedBox(height: 14)
                      : Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.dangerContainer,
                              borderRadius:
                                  BorderRadius.circular(PromptUiShapes.control),
                              border: Border.all(
                                color: tokens.danger.withOpacity(
                                  tokens.isDark ? .60 : .38,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  color: tokens.danger,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: tokens.onDangerContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                ...widget.fields.asMap().entries.map(
                      (entry) => PromptAnimatedReveal(
                        delay: Duration(milliseconds: entry.key * 45),
                        offset: const Offset(0, .025),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _TimeInputRow(
                            label: entry.value.label,
                            hourController:
                                _hourControllers[entry.value.id]!,
                            minuteController:
                                _minuteControllers[entry.value.id]!,
                          ),
                        ),
                      ),
                    ),
                const SizedBox(height: 4),
                PromptButton(
                  label: '저장',
                  icon: Icons.save_rounded,
                  onPressed: _save,
                  loading: _saving,
                  expand: true,
                  haptic: PromptHaptic.selection,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeInputRow extends StatelessWidget {
  const _TimeInputRow({
    required this.label,
    required this.hourController,
    required this.minuteController,
  });

  final String label;
  final TextEditingController hourController;
  final TextEditingController minuteController;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelLarge?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: hourController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  maxLength: 2,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: '시',
                    counterText: '',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  ':',
                  style: textTheme.titleLarge?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: minuteController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  maxLength: 2,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: '분',
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AttendanceTimeResult {
  const AttendanceTimeResult(this.inTime, this.outTime);

  final String inTime;
  final String outTime;
}

Future<AttendanceTimeResult?> showAttendanceTimeSheet({
  required BuildContext context,
  required DateTime date,
  required String initialInTime,
  required String initialOutTime,
  bool usePromptUi = false,
}) async {
  final result = await showTimeEditSheet(
    context: context,
    date: date,
    title:
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    fields: [
      TimeFieldSpec(id: 'in', label: '출근 시간', initial: initialInTime),
      TimeFieldSpec(id: 'out', label: '퇴근 시간', initial: initialOutTime),
    ],
    usePromptUi: usePromptUi,
    validators: [
      (values) {
        final inTime = values['in']!;
        final outTime = values['out']!;
        if (inTime.isNotEmpty &&
            outTime.isNotEmpty &&
            inTime.compareTo(outTime) > 0) {
          return '퇴근 시간이 출근 시간보다 빠를 수 없습니다.';
        }
        return null;
      },
    ],
  );
  if (result == null) return null;
  return AttendanceTimeResult(result['in']!, result['out']!);
}

Future<String?> showBreakTimeSheet({
  required BuildContext context,
  required DateTime date,
  required String initialTime,
  bool usePromptUi = false,
}) async {
  final result = await showTimeEditSheet(
    context: context,
    date: date,
    fields: [
      TimeFieldSpec(id: 'break', label: '휴게 시간', initial: initialTime),
    ],
    usePromptUi: usePromptUi,
  );
  return result?['break'];
}
