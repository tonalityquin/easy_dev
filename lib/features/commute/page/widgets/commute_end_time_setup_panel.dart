import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/init/work_schedule_prefs.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import 'parkinworkin_windows_desktop.dart';

enum CommuteEndTimeSetupFeedback {
  editing,
  saving,
  success,
  failure,
}

enum CommuteEndTimeInputSource {
  initial,
  scroll,
  direct,
}

enum CommuteEndTimeInputField {
  none,
  hour,
  minute,
}

class CommuteEndTimeDraftSnapshot {
  const CommuteEndTimeDraftSnapshot({
    required this.value,
    required this.source,
    required this.inputValid,
    required this.inputText,
    required this.hourInput,
    required this.minuteInput,
    required this.focusedField,
    required this.keyboardVisible,
    required this.directInputActive,
  });

  final TimeOfDay value;
  final CommuteEndTimeInputSource source;
  final bool inputValid;
  final String inputText;
  final String hourInput;
  final String minuteInput;
  final CommuteEndTimeInputField focusedField;
  final bool keyboardVisible;
  final bool directInputActive;
}

class CommuteEndTimeConsoleSection extends StatefulWidget {
  const CommuteEndTimeConsoleSection({
    super.key,
    required this.day,
    required this.reduceMotion,
    required this.feedback,
    required this.onSkip,
    required this.onSave,
    this.onDraftChanged,
  });

  final String day;
  final bool reduceMotion;
  final CommuteEndTimeSetupFeedback feedback;
  final Future<void> Function() onSkip;
  final Future<void> Function(TimeOfDay value) onSave;
  final ValueChanged<CommuteEndTimeDraftSnapshot>? onDraftChanged;

  @override
  State<CommuteEndTimeConsoleSection> createState() =>
      _CommuteEndTimeConsoleSectionState();
}

class _CommuteEndTimeConsoleSectionState
    extends State<CommuteEndTimeConsoleSection> with WidgetsBindingObserver {
  TimeOfDay _selected = const TimeOfDay(hour: 0, minute: 0);
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  late final TextEditingController _hourInputController;
  late final TextEditingController _minuteInputController;
  late final FocusNode _hourFocusNode;
  late final FocusNode _minuteFocusNode;
  final GlobalKey _inputActionKey = GlobalKey();
  bool _inputValid = true;
  bool _syncingInput = false;
  bool _directInputActive = false;
  bool _keyboardVisible = false;
  int _actionAttentionEpoch = 0;

  bool get _locked =>
      widget.feedback != CommuteEndTimeSetupFeedback.editing;

  bool get _directFieldFocused =>
      _hourFocusNode.hasFocus || _minuteFocusNode.hasFocus;

  CommuteEndTimeInputField get _focusedField {
    if (_hourFocusNode.hasFocus) return CommuteEndTimeInputField.hour;
    if (_minuteFocusNode.hasFocus) return CommuteEndTimeInputField.minute;
    return CommuteEndTimeInputField.none;
  }

  String get _timeText =>
      WorkSchedulePrefs.formatTime(_selected) ?? '00:00';

  String get _directInputText =>
      '${_hourInputController.text}:${_minuteInputController.text}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hourController = FixedExtentScrollController(initialItem: _selected.hour);
    _minuteController =
        FixedExtentScrollController(initialItem: _selected.minute);
    _hourInputController = TextEditingController(text: '00');
    _minuteInputController = TextEditingController(text: '00');
    _hourFocusNode = FocusNode()..addListener(_handleHourFocusChanged);
    _minuteFocusNode = FocusNode()..addListener(_handleMinuteFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
      _notifyDraft(CommuteEndTimeInputSource.initial);
    });
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final visible = MediaQuery.viewInsetsOf(context).bottom > 0;
      final changed = visible != _keyboardVisible;
      if (changed) {
        setState(() {
          _keyboardVisible = visible;
        });
      }
      if (!visible) {
        _syncWheelToSelected();
      } else if (_directFieldFocused) {
        _ensureInputActionVisible();
      }
      if (changed) {
        _notifyDraft(
          _directInputActive
              ? CommuteEndTimeInputSource.direct
              : CommuteEndTimeInputSource.initial,
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant CommuteEndTimeConsoleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feedback == CommuteEndTimeSetupFeedback.editing &&
        widget.feedback != CommuteEndTimeSetupFeedback.editing) {
      FocusManager.instance.primaryFocus?.unfocus();
      if (_directInputActive) {
        _normalizeDirectInputs();
      } else {
        _syncDirectInputToSelected();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hourFocusNode.removeListener(_handleHourFocusChanged);
    _minuteFocusNode.removeListener(_handleMinuteFocusChanged);
    _hourFocusNode.dispose();
    _minuteFocusNode.dispose();
    _hourInputController.dispose();
    _minuteInputController.dispose();
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _handleHourFocusChanged() {
    _handleDirectFocusChanged(
      focusNode: _hourFocusNode,
      controller: _hourInputController,
    );
  }

  void _handleMinuteFocusChanged() {
    _handleDirectFocusChanged(
      focusNode: _minuteFocusNode,
      controller: _minuteInputController,
    );
  }

  void _handleDirectFocusChanged({
    required FocusNode focusNode,
    required TextEditingController controller,
  }) {
    if (focusNode.hasFocus) {
      _activateDirectInputIfNeeded();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !focusNode.hasFocus) return;
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
        _ensureInputActionVisible();
      });
      _notifyDraft(CommuteEndTimeInputSource.direct);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _directFieldFocused) return;
      _normalizeDirectInputs();
      _notifyDraft(
        _directInputActive
            ? CommuteEndTimeInputSource.direct
            : CommuteEndTimeInputSource.initial,
      );
    });
  }

  void _activateDirectInputIfNeeded() {
    if (_directInputActive) return;
    setState(() {
      _directInputActive = true;
    });
  }

  void _handleWheelChanged({
    required int? hour,
    required int? minute,
  }) {
    if (_locked) return;
    final next = TimeOfDay(
      hour: hour ?? _selected.hour,
      minute: minute ?? _selected.minute,
    );
    if (next.hour == _selected.hour && next.minute == _selected.minute) return;
    final wasInvalid = !_inputValid;
    setState(() {
      _selected = next;
      _inputValid = true;
      if (wasInvalid) _actionAttentionEpoch += 1;
    });
    _syncDirectInputToSelected();
    _notifyDraft(CommuteEndTimeInputSource.scroll);
    unawaited(HapticFeedback.selectionClick());
  }

  void _handleHourChanged(String value) {
    if (_syncingInput || _locked) return;
    _directInputActive = true;
    if (value.length == 1) {
      final firstDigit = int.tryParse(value);
      if (firstDigit != null && firstDigit >= 3) {
        final normalized = '0$value';
        _setSingleInputText(_hourInputController, normalized);
        _applyDirectDraft();
        if (_hourFocusNode.hasFocus) _minuteFocusNode.requestFocus();
        return;
      }
    }
    _applyDirectDraft();
    final hour = _parsePart(_hourInputController.text, 23);
    if (_hourInputController.text.length == 2 &&
        hour != null &&
        _hourFocusNode.hasFocus) {
      _minuteFocusNode.requestFocus();
    }
  }

  void _handleMinuteChanged(String value) {
    if (_syncingInput || _locked) return;
    _directInputActive = true;
    if (value.length == 1) {
      final firstDigit = int.tryParse(value);
      if (firstDigit != null && firstDigit >= 6) {
        _setSingleInputText(_minuteInputController, '0$value');
      }
    }
    _applyDirectDraft();
  }

  void _handleHourSubmitted(String value) {
    if (_locked) return;
    final normalized = _normalizePart(
      value,
      max: 23,
      fallback: _selected.hour,
    );
    _setSingleInputText(_hourInputController, normalized);
    _applyDirectDraft();
    _minuteFocusNode.requestFocus();
  }

  void _handleMinuteSubmitted(String value) {
    if (_locked) return;
    final normalized = _normalizePart(
      value,
      max: 59,
      fallback: _selected.minute,
    );
    _setSingleInputText(_minuteInputController, normalized);
    _applyDirectDraft();
    _minuteFocusNode.unfocus();
  }

  void _applyDirectDraft() {
    final hour = _parsePart(_hourInputController.text, 23);
    final minute = _parsePart(_minuteInputController.text, 59);
    final nextValid = hour != null && minute != null;
    final wasValid = _inputValid;

    if (!nextValid) {
      if (_inputValid) {
        setState(() {
          _inputValid = false;
        });
      }
      _notifyDraft(CommuteEndTimeInputSource.direct);
      return;
    }

    final next = TimeOfDay(hour: hour, minute: minute);
    final changed = next.hour != _selected.hour || next.minute != _selected.minute;
    setState(() {
      _selected = next;
      _inputValid = true;
      if (!wasValid) _actionAttentionEpoch += 1;
    });
    if (changed) {
      _syncWheelToSelected();
      unawaited(HapticFeedback.selectionClick());
    }
    _notifyDraft(CommuteEndTimeInputSource.direct);
  }

  int? _parsePart(String value, int max) {
    if (value.length != 2) return null;
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0 || parsed > max) return null;
    return parsed;
  }

  void _normalizeDirectInputs() {
    final normalizedHour = _normalizePart(
      _hourInputController.text,
      max: 23,
      fallback: _selected.hour,
    );
    final normalizedMinute = _normalizePart(
      _minuteInputController.text,
      max: 59,
      fallback: _selected.minute,
    );
    _syncDirectInputText(
      hour: normalizedHour,
      minute: normalizedMinute,
    );

    final hour = _parsePart(normalizedHour, 23) ?? _selected.hour;
    final minute = _parsePart(normalizedMinute, 59) ?? _selected.minute;
    final next = TimeOfDay(hour: hour, minute: minute);
    final changed = next.hour != _selected.hour || next.minute != _selected.minute;
    final wasInvalid = !_inputValid;
    if (changed || wasInvalid) {
      setState(() {
        _selected = next;
        _inputValid = true;
        if (wasInvalid) _actionAttentionEpoch += 1;
      });
      if (changed) _syncWheelToSelected();
    }
  }

  String _normalizePart(
    String value, {
    required int max,
    required int fallback,
  }) {
    if (value.isEmpty) return '00';
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0 || parsed > max) {
      return fallback.toString().padLeft(2, '0');
    }
    return parsed.toString().padLeft(2, '0');
  }

  void _syncDirectInputToSelected() {
    _syncDirectInputText(
      hour: _selected.hour.toString().padLeft(2, '0'),
      minute: _selected.minute.toString().padLeft(2, '0'),
    );
  }

  void _syncDirectInputText({
    required String hour,
    required String minute,
  }) {
    _syncingInput = true;
    _hourInputController.value = TextEditingValue(
      text: hour,
      selection: TextSelection.collapsed(offset: hour.length),
    );
    _minuteInputController.value = TextEditingValue(
      text: minute,
      selection: TextSelection.collapsed(offset: minute.length),
    );
    _syncingInput = false;
  }

  void _setSingleInputText(
    TextEditingController controller,
    String value,
  ) {
    _syncingInput = true;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _syncingInput = false;
  }

  void _syncWheelToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _moveWheel(_hourController, _selected.hour);
      _moveWheel(_minuteController, _selected.minute);
    });
  }

  void _moveWheel(FixedExtentScrollController controller, int item) {
    if (!controller.hasClients) return;
    if (widget.reduceMotion) {
      controller.jumpToItem(item);
      return;
    }
    unawaited(
      controller.animateToItem(
        item,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _ensureInputActionVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = _inputActionKey.currentContext;
      if (targetContext == null) return;
      unawaited(
        Scrollable.ensureVisible(
          targetContext,
          duration: widget.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.88,
        ),
      );
    });
    if (!widget.reduceMotion) {
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 220), () {
          if (!mounted || !_directFieldFocused) return;
          final targetContext = _inputActionKey.currentContext;
          if (targetContext == null) return;
          unawaited(
            Scrollable.ensureVisible(
              targetContext,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: 0.88,
            ),
          );
        }),
      );
    }
  }

  Future<void> _handleSkipAction() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await widget.onSkip();
  }

  Future<void> _handleSaveAction() async {
    if (!_inputValid) return;
    if (_directInputActive) _normalizeDirectInputs();
    FocusManager.instance.primaryFocus?.unfocus();
    await widget.onSave(_selected);
  }

  void _notifyDraft(CommuteEndTimeInputSource source) {
    widget.onDraftChanged?.call(
      CommuteEndTimeDraftSnapshot(
        value: _selected,
        source: source,
        inputValid: _inputValid,
        inputText: _directInputText,
        hourInput: _hourInputController.text,
        minuteInput: _minuteInputController.text,
        focusedField: _focusedField,
        keyboardVisible: _keyboardVisible,
        directInputActive: _directInputActive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final duration = widget.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 170);
    final statusColor = _statusColor(tokens);
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compactForKeyboard = keyboardVisible && _directFieldFocused;

    return Semantics(
      liveRegion: true,
      container: true,
      label: '퇴근 시간 설정이 필요합니다. 현재 선택 시간 $_timeText',
      child: AnimatedSize(
        duration: duration,
        curve: CommonUiMotion.standard,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ParkinWorkinConsoleRow(
              label: 'WEEKDAY',
              value: '${widget.day}요일',
              reduceMotion: widget.reduceMotion,
              valueColor: tokens.textPrimary,
              valueFontWeight: FontWeight.w600,
            ),
            const SizedBox(height: 8),
            ParkinWorkinConsoleRow(
              label: 'END TIME',
              value: _timeText,
              reduceMotion: widget.reduceMotion,
              valueColor: tokens.textPrimary,
              valueFontWeight: FontWeight.w800,
            ),
            const SizedBox(height: 8),
            ParkinWorkinConsoleRow(
              label: 'STATUS',
              value: _statusLabel,
              reduceMotion: widget.reduceMotion,
              valueColor: statusColor,
              trailing: widget.feedback == CommuteEndTimeSetupFeedback.saving
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: statusColor,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            ParkinWorkinConsoleRow(
              label: 'DETAIL',
              value: _detailText,
              reduceMotion: widget.reduceMotion,
              valueColor: tokens.textSecondary,
              valueFontWeight: FontWeight.w600,
            ),
            AnimatedSwitcher(
              duration: duration,
              reverseDuration: duration,
              switchInCurve: CommonUiMotion.enter,
              switchOutCurve: CommonUiMotion.exit,
              transitionBuilder: (child, animation) {
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: CommonUiMotion.enter,
                  reverseCurve: CommonUiMotion.exit,
                );
                final slide = Tween<Offset>(
                  begin: const Offset(0, 0.025),
                  end: Offset.zero,
                ).animate(curved);
                return FadeTransition(
                  opacity: curved,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: widget.feedback == CommuteEndTimeSetupFeedback.editing
                  ? Padding(
                      key: const ValueKey<String>('end_time_console_editing'),
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AnimatedSize(
                            duration: duration,
                            curve: CommonUiMotion.standard,
                            alignment: Alignment.topCenter,
                            child: compactForKeyboard
                                ? const SizedBox.shrink()
                                : _EndTimeWheelRow(
                                    selected: _selected,
                                    hourController: _hourController,
                                    minuteController: _minuteController,
                                    reduceMotion: widget.reduceMotion,
                                    locked: _locked,
                                    onHourChanged: (value) =>
                                        _handleWheelChanged(
                                      hour: value,
                                      minute: null,
                                    ),
                                    onMinuteChanged: (value) =>
                                        _handleWheelChanged(
                                      hour: null,
                                      minute: value,
                                    ),
                                  ),
                          ),
                          if (!compactForKeyboard) const SizedBox(height: 8),
                          Container(
                            key: _inputActionKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _EndTimeDirectInputRow(
                                  hourController: _hourInputController,
                                  minuteController: _minuteInputController,
                                  hourFocusNode: _hourFocusNode,
                                  minuteFocusNode: _minuteFocusNode,
                                  reduceMotion: widget.reduceMotion,
                                  valid: _inputValid,
                                  enabled: !_locked,
                                  onHourChanged: _handleHourChanged,
                                  onMinuteChanged: _handleMinuteChanged,
                                  onHourSubmitted: _handleHourSubmitted,
                                  onMinuteSubmitted: _handleMinuteSubmitted,
                                ),
                                const SizedBox(height: 4),
                                ParkinWorkinConsoleAction(
                                  reduceMotion: widget.reduceMotion,
                                  attentionEnabled: _inputValid,
                                  attentionToken:
                                      '${widget.day}_$_actionAttentionEpoch',
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Wrap(
                                      alignment: WrapAlignment.end,
                                      spacing: 4,
                                      children: [
                                        TextButton(
                                          onPressed: () => unawaited(
                                            _handleSkipAction(),
                                          ),
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                tokens.textSecondary,
                                            minimumSize: const Size(0, 44),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            tapTargetSize:
                                                MaterialTapTargetSize.padded,
                                          ),
                                          child: const Text('넘기기'),
                                        ),
                                        TextButton.icon(
                                          onPressed: _inputValid
                                              ? () => unawaited(
                                                    _handleSaveAction(),
                                                  )
                                              : null,
                                          icon: const Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('저장하고 계속'),
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                tokens.brandPrimary,
                                            disabledForegroundColor: tokens
                                                .textSecondary
                                                .withOpacity(0.45),
                                            minimumSize: const Size(0, 44),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            tapTargetSize:
                                                MaterialTapTargetSize.padded,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey<String>('end_time_console_locked'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String get _statusLabel {
    if (widget.feedback == CommuteEndTimeSetupFeedback.editing &&
        !_inputValid) {
      return 'CHECK INPUT';
    }
    return switch (widget.feedback) {
      CommuteEndTimeSetupFeedback.editing => 'READY TO SAVE',
      CommuteEndTimeSetupFeedback.saving => 'SAVING',
      CommuteEndTimeSetupFeedback.success => 'SAVED',
      CommuteEndTimeSetupFeedback.failure => 'SAVE FAILED',
    };
  }

  String get _detailText {
    if (widget.feedback == CommuteEndTimeSetupFeedback.editing &&
        !_inputValid) {
      return '시간은 00부터 23, 분은 00부터 59 사이의 숫자로 입력해 주세요.';
    }
    return switch (widget.feedback) {
      CommuteEndTimeSetupFeedback.editing =>
        '${widget.day}요일 기본 퇴근 시간이 설정되어 있지 않습니다.',
      CommuteEndTimeSetupFeedback.saving =>
        '${widget.day}요일 정규 퇴근 시간을 기기에 저장하고 있습니다.',
      CommuteEndTimeSetupFeedback.success =>
        '${widget.day}요일 정규 퇴근 시간 저장이 완료되었습니다.',
      CommuteEndTimeSetupFeedback.failure =>
        '저장하지 못했지만 출근은 정상 처리되어 업무 화면으로 계속 이동합니다.',
    };
  }

  Color _statusColor(CommonUiTokens tokens) {
    if (widget.feedback == CommuteEndTimeSetupFeedback.editing &&
        !_inputValid) {
      return tokens.danger;
    }
    return switch (widget.feedback) {
      CommuteEndTimeSetupFeedback.editing => tokens.warning,
      CommuteEndTimeSetupFeedback.saving => tokens.brandPrimary,
      CommuteEndTimeSetupFeedback.success => tokens.success,
      CommuteEndTimeSetupFeedback.failure => tokens.danger,
    };
  }
}

class _EndTimeWheelRow extends StatelessWidget {
  const _EndTimeWheelRow({
    required this.selected,
    required this.hourController,
    required this.minuteController,
    required this.reduceMotion,
    required this.locked,
    required this.onHourChanged,
    required this.onMinuteChanged,
  });

  final TimeOfDay selected;
  final FixedExtentScrollController hourController;
  final FixedExtentScrollController minuteController;
  final bool reduceMotion;
  final bool locked;
  final ValueChanged<int> onHourChanged;
  final ValueChanged<int> onMinuteChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);

    return ParkinWorkinConsoleRow(
      label: 'SCROLL',
      reduceMotion: reduceMotion,
      child: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          height: 92,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ConsoleTimeWheel(
                semanticLabel: '퇴근 시간 선택',
                controller: hourController,
                selectedValue: selected.hour,
                itemCount: 24,
                reduceMotion: reduceMotion,
                enabled: !locked,
                onSelectedItemChanged: onHourChanged,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  ':',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ),
              _ConsoleTimeWheel(
                semanticLabel: '퇴근 분 선택',
                controller: minuteController,
                selectedValue: selected.minute,
                itemCount: 60,
                reduceMotion: reduceMotion,
                enabled: !locked,
                onSelectedItemChanged: onMinuteChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsoleTimeWheel extends StatelessWidget {
  const _ConsoleTimeWheel({
    required this.semanticLabel,
    required this.controller,
    required this.selectedValue,
    required this.itemCount,
    required this.reduceMotion,
    required this.enabled,
    required this.onSelectedItemChanged,
  });

  final String semanticLabel;
  final FixedExtentScrollController controller;
  final int selectedValue;
  final int itemCount;
  final bool reduceMotion;
  final bool enabled;
  final ValueChanged<int> onSelectedItemChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;

    return Semantics(
      label: semanticLabel,
      value: selectedValue.toString().padLeft(2, '0'),
      child: SizedBox(
        width: 58,
        child: ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: 30,
          physics: enabled
              ? const FixedExtentScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          diameterRatio: 1.7,
          perspective: 0.003,
          overAndUnderCenterOpacity: 0.32,
          onSelectedItemChanged: enabled ? onSelectedItemChanged : null,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: itemCount,
            builder: (context, index) {
              final selected = index == selectedValue;
              return Center(
                child: AnimatedDefaultTextStyle(
                  duration: duration,
                  curve: CommonUiMotion.standard,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: selected
                                ? tokens.brandPrimary
                                : tokens.textSecondary,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ) ??
                      const TextStyle(),
                  child: Text(index.toString().padLeft(2, '0')),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EndTimeDirectInputRow extends StatelessWidget {
  const _EndTimeDirectInputRow({
    required this.hourController,
    required this.minuteController,
    required this.hourFocusNode,
    required this.minuteFocusNode,
    required this.reduceMotion,
    required this.valid,
    required this.enabled,
    required this.onHourChanged,
    required this.onMinuteChanged,
    required this.onHourSubmitted,
    required this.onMinuteSubmitted,
  });

  final TextEditingController hourController;
  final TextEditingController minuteController;
  final FocusNode hourFocusNode;
  final FocusNode minuteFocusNode;
  final bool reduceMotion;
  final bool valid;
  final bool enabled;
  final ValueChanged<String> onHourChanged;
  final ValueChanged<String> onMinuteChanged;
  final ValueChanged<String> onHourSubmitted;
  final ValueChanged<String> onMinuteSubmitted;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);

    return ParkinWorkinConsoleRow(
      label: 'INPUT',
      reduceMotion: reduceMotion,
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NumericTimeField(
              semanticLabel: '퇴근 시간 직접 입력',
              suffixLabel: 'HH',
              controller: hourController,
              focusNode: hourFocusNode,
              enabled: enabled,
              valid: valid,
              textInputAction: TextInputAction.next,
              onChanged: onHourChanged,
              onSubmitted: onHourSubmitted,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Text(
                ':',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ),
            _NumericTimeField(
              semanticLabel: '퇴근 분 직접 입력',
              suffixLabel: 'MM',
              controller: minuteController,
              focusNode: minuteFocusNode,
              enabled: enabled,
              valid: valid,
              textInputAction: TextInputAction.done,
              onChanged: onMinuteChanged,
              onSubmitted: onMinuteSubmitted,
            ),
          ],
        ),
      ),
    );
  }
}

class _NumericTimeField extends StatelessWidget {
  const _NumericTimeField({
    required this.semanticLabel,
    required this.suffixLabel,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.valid,
    required this.textInputAction,
    required this.onChanged,
    required this.onSubmitted,
  });

  final String semanticLabel;
  final String suffixLabel;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool valid;
  final TextInputAction textInputAction;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);

    return SizedBox(
      width: 52,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            textField: true,
            label: semanticLabel,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              keyboardType: TextInputType.number,
              textInputAction: textInputAction,
              autocorrect: false,
              enableSuggestions: false,
              maxLines: 1,
              scrollPadding: const EdgeInsets.only(bottom: 140),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: tokens.borderSubtle),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: valid ? tokens.borderSubtle : tokens.danger,
                  ),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: valid ? tokens.brandPrimary : tokens.danger,
                    width: 1.6,
                  ),
                ),
                disabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: tokens.borderSubtle),
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            suffixLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
          ),
        ],
      ),
    );
  }
}
