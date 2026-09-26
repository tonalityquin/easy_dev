import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';

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

typedef TimeDialogValidator = String? Function(Map<String, String> values);
typedef TimeDialogDebugLog = void Function(String message);
typedef TimeDialogDeveloperStatus = Future<void> Function();

Future<Map<String, String>?> showTimeEditDialog({
  required BuildContext context,
  required DateTime date,
  required List<TimeFieldSpec> fields,
  List<TimeDialogValidator> validators = const [],
  String? title,
  bool useCommonUi = false,
  bool developerMode = false,
  TimeDialogDebugLog? onDebugLog,
  TimeDialogDeveloperStatus? onDeveloperStatus,
}) {
  onDebugLog?.call(
    'dialog_route_push date=${date.toIso8601String()} fields=${fields.map((field) => field.id).join(',')} commonUi=$useCommonUi developerMode=$developerMode',
  );

  return showCommonOverlayDialog<Map<String, String>>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: title ?? '시간 기록 수정',
    builder: (dialogContext) {
      return _TimeEditDialog(
        date: date,
        fields: fields,
        validators: validators,
        title: title,
        useCommonUi: useCommonUi,
        developerMode: developerMode,
        onDebugLog: onDebugLog,
        onDeveloperStatus: onDeveloperStatus,
      );
    },
  ).whenComplete(() {
    onDebugLog?.call(
      'dialog_route_closed date=${date.toIso8601String()} commonUi=$useCommonUi',
    );
  });
}

class _TimeEditDialog extends StatefulWidget {
  const _TimeEditDialog({
    required this.date,
    required this.fields,
    required this.validators,
    required this.title,
    required this.useCommonUi,
    required this.developerMode,
    required this.onDebugLog,
    required this.onDeveloperStatus,
  });

  final DateTime date;
  final List<TimeFieldSpec> fields;
  final List<TimeDialogValidator> validators;
  final String? title;
  final bool useCommonUi;
  final bool developerMode;
  final TimeDialogDebugLog? onDebugLog;
  final TimeDialogDeveloperStatus? onDeveloperStatus;

  @override
  State<_TimeEditDialog> createState() => _TimeEditDialogState();
}

class _TimeEditDialogState extends State<_TimeEditDialog> {
  late final Map<String, TextEditingController> _hourControllers;
  late final Map<String, TextEditingController> _minuteControllers;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _hourControllers = <String, TextEditingController>{};
    _minuteControllers = <String, TextEditingController>{};
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _log(
        'dialog_presented date=${widget.date.toIso8601String()} fieldCount=${widget.fields.length} commonUi=${widget.useCommonUi}',
      );
    });
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

  void _log(String message) {
    final callback = widget.onDebugLog;
    if (callback != null) {
      callback(message);
      return;
    }
    debugPrint('[TimeEditDialog] $message');
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

  Map<String, String> _collectValues() {
    final values = <String, String>{};
    for (final field in widget.fields) {
      final hour = _hourControllers[field.id]!.text.trim().padLeft(2, '0');
      final minute =
          _minuteControllers[field.id]!.text.trim().padLeft(2, '0');
      values[field.id] = '$hour:$minute';
    }
    return values;
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final values = _collectValues();
    final error = _validate(values);
    if (error != null) {
      _log(
        'validation_failed date=${widget.date.toIso8601String()} message=$error values=$values',
      );
      setState(() => _error = error);
      await HapticFeedback.mediumImpact();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    _log(
      'apply_requested date=${widget.date.toIso8601String()} values=$values',
    );
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true)
        .pop<Map<String, String>>(values);
  }

  Future<void> _showDeveloperStatus() async {
    if (!widget.developerMode) return;
    final callback = widget.onDeveloperStatus;
    if (callback == null) return;
    _log(
      'developer_status_requested date=${widget.date.toIso8601String()} values=${_collectValues()} error=${_error ?? '-'} saving=$_saving',
    );
    await callback();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final screen = MediaQuery.sizeOf(context);
    final maxWidth = (screen.width - 32).clamp(280.0, 420.0).toDouble();
    final maxHeight = (screen.height - viewInsets.bottom - 32)
        .clamp(260.0, screen.height * .78)
        .toDouble();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        child: Material(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(CommonUiShapes.sheet),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: tokens.borderSubtle),
              borderRadius: BorderRadius.circular(CommonUiShapes.sheet),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPress: widget.developerMode
                              ? _showDeveloperStatus
                              : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title ?? '시간 기록 수정',
                                style: textTheme.titleMedium?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _dateLabel(widget.date),
                                style: textTheme.bodySmall?.copyWith(
                                  color: tokens.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: _saving
                            ? null
                            : () {
                                _log(
                                  'dismiss_requested date=${widget.date.toIso8601String()} source=close_button',
                                );
                                Navigator.of(context, rootNavigator: true).pop();
                              },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: tokens.borderSubtle),
                Flexible(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...widget.fields.asMap().entries.expand((entry) sync* {
                          if (entry.key > 0) {
                            yield Divider(
                              height: 1,
                              indent: 20,
                              endIndent: 20,
                              color: tokens.borderSubtle,
                            );
                          }
                          yield _TimeInputListRow(
                            label: entry.value.label,
                            hourController:
                                _hourControllers[entry.value.id]!,
                            minuteController:
                                _minuteControllers[entry.value.id]!,
                          );
                        }),
                        AnimatedSize(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 170),
                          curve: Curves.easeOutCubic,
                          child: _error == null
                              ? const SizedBox.shrink()
                              : Column(
                                  children: [
                                    Divider(
                                      height: 1,
                                      color: tokens.borderSubtle,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        20,
                                        12,
                                        20,
                                        12,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.error_outline_rounded,
                                            size: 19,
                                            color: tokens.danger,
                                          ),
                                          const SizedBox(width: 9),
                                          Expanded(
                                            child: Text(
                                              _error!,
                                              style: textTheme.bodySmall
                                                  ?.copyWith(
                                                color: tokens.danger,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, color: tokens.borderSubtle),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () {
                                _log(
                                  'dismiss_requested date=${widget.date.toIso8601String()} source=cancel_button',
                                );
                                Navigator.of(context, rootNavigator: true).pop();
                              },
                        child: const Text('취소'),
                      ),
                      const SizedBox(width: 8),
                      AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _saving
                            ? const SizedBox(
                                key: ValueKey<String>('applying'),
                                width: 88,
                                height: 40,
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  ),
                                ),
                              )
                            : FilledButton.icon(
                                key: const ValueKey<String>('apply'),
                                onPressed: _save,
                                icon: const Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                ),
                                label: const Text('적용'),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeInputListRow extends StatelessWidget {
  const _TimeInputListRow({
    required this.label,
    required this.hourController,
    required this.minuteController,
  });

  final String label;
  final TextEditingController hourController;
  final TextEditingController minuteController;

  Widget _buildTimeFields(
    BuildContext context,
    CommonUiTokens tokens,
    TextTheme textTheme,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 66,
          child: TextField(
            controller: hourController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            maxLength: 2,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              labelText: '시',
              counterText: '',
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            ':',
            style: textTheme.titleLarge?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          width: 66,
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
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 330;
        if (compact) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  style: textTheme.labelLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildTimeFields(context, tokens, textTheme),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: textTheme.labelLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _buildTimeFields(context, tokens, textTheme),
            ],
          ),
        );
      },
    );
  }
}

class AttendanceTimeResult {
  const AttendanceTimeResult(this.inTime, this.outTime);

  final String inTime;
  final String outTime;
}

Future<AttendanceTimeResult?> showAttendanceTimeDialog({
  required BuildContext context,
  required DateTime date,
  required String initialInTime,
  required String initialOutTime,
  bool useCommonUi = false,
  bool developerMode = false,
  TimeDialogDebugLog? onDebugLog,
  TimeDialogDeveloperStatus? onDeveloperStatus,
}) async {
  final result = await showTimeEditDialog(
    context: context,
    date: date,
    title: '출·퇴근 기록 수정',
    fields: [
      TimeFieldSpec(id: 'in', label: '출근', initial: initialInTime),
      TimeFieldSpec(id: 'out', label: '퇴근', initial: initialOutTime),
    ],
    useCommonUi: useCommonUi,
    developerMode: developerMode,
    onDebugLog: onDebugLog,
    onDeveloperStatus: onDeveloperStatus,
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

Future<String?> showBreakTimeDialog({
  required BuildContext context,
  required DateTime date,
  required String initialTime,
  bool useCommonUi = false,
  bool developerMode = false,
  TimeDialogDebugLog? onDebugLog,
  TimeDialogDeveloperStatus? onDeveloperStatus,
}) async {
  final result = await showTimeEditDialog(
    context: context,
    date: date,
    title: '휴게 기록 수정',
    fields: [
      TimeFieldSpec(id: 'break', label: '휴게', initial: initialTime),
    ],
    useCommonUi: useCommonUi,
    developerMode: developerMode,
    onDebugLog: onDebugLog,
    onDeveloperStatus: onDeveloperStatus,
  );
  return result?['break'];
}
