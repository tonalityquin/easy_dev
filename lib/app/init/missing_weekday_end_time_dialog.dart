import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../features/account/applications/user_state.dart';
import 'work_schedule_prefs.dart';

Future<void> showMissingWeekdayEndTimeDialogIfNeeded(
  BuildContext context, {
  DateTime? clockInAt,
  bool usePromptUi = false,
}) async {
  if (!context.mounted) return;

  final userState = context.read<UserState>();
  if (userState.isTablet) return;

  final target = clockInAt ?? DateTime.now();
  final now = DateTime.now();
  if (!_isSameDate(target, now)) return;

  final prefs = await SharedPreferences.getInstance();
  final endByDay = WorkSchedulePrefs.readDayTimeMapFromPrefs(
    prefs,
    WorkSchedulePrefs.endMapKey,
  );
  final day = WorkSchedulePrefs.days[target.weekday - 1];
  if (endByDay[day] != null) return;

  if (!context.mounted) return;

  final picked = usePromptUi
      ? await showPromptDialog<TimeOfDay>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return _MissingWeekdayEndTimeDialog(
              day: day,
              usePromptUi: true,
            );
          },
        )
      : await showDialog<TimeOfDay>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return _MissingWeekdayEndTimeDialog(
              day: day,
              usePromptUi: false,
            );
          },
        );

  if (picked == null) return;
  if (!context.mounted) return;

  final saved = await userState.setCurrentUserWeekdayEndTime(
    day: day,
    endTime: picked,
  );

  if (!context.mounted) return;

  final message = saved
      ? '$day요일 정규 퇴근 시간이 ${WorkSchedulePrefs.formatTime(picked)}로 저장되었습니다.'
      : '퇴근 시간 저장에 실패했습니다. 사용자 정보를 확인해 주세요.';

  if (usePromptUi) {
    _showPromptSaveSnackBar(
      context,
      message: message,
      success: saved,
    );
    return;
  }

  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

void _showPromptSaveSnackBar(
  BuildContext context, {
  required String message,
  required bool success,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final tokens = PromptUiTheme.of(context);
  final text = Theme.of(context).textTheme;
  final accent = success ? tokens.success : tokens.danger;
  final background =
      success ? tokens.successContainer : tokens.dangerContainer;
  final foreground =
      success ? tokens.onSuccessContainer : tokens.onDangerContainer;

  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: background,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
        side: BorderSide(
          color: accent.withOpacity(tokens.isDark ? 0.58 : 0.36),
        ),
      ),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            color: accent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: text.bodyMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class _MissingWeekdayEndTimeDialog extends StatefulWidget {
  const _MissingWeekdayEndTimeDialog({
    required this.day,
    required this.usePromptUi,
  });

  final String day;
  final bool usePromptUi;

  @override
  State<_MissingWeekdayEndTimeDialog> createState() =>
      _MissingWeekdayEndTimeDialogState();
}

class _MissingWeekdayEndTimeDialogState
    extends State<_MissingWeekdayEndTimeDialog> {
  TimeOfDay _selected = const TimeOfDay(hour: 18, minute: 0);

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selected,
      confirmText: '선택',
      cancelText: '취소',
      builder: widget.usePromptUi
          ? (context, child) {
              return PromptUiScope(child: child ?? const SizedBox.shrink());
            }
          : null,
    );

    if (picked == null) return;
    setState(() {
      _selected = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.usePromptUi ? _buildPromptDialog() : _buildLegacyDialog();
  }

  Widget _buildPromptDialog() {
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final timeText = WorkSchedulePrefs.formatTime(_selected) ?? '18:00';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tokens.warningContainer,
                  borderRadius: BorderRadius.circular(PromptUiShapes.control),
                  border: Border.all(
                    color: tokens.warning.withOpacity(
                      tokens.isDark ? 0.58 : 0.36,
                    ),
                  ),
                ),
                child: Icon(
                  Icons.schedule_rounded,
                  color: tokens.warning,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '퇴근 시간 설정이 필요합니다',
                  style: text.titleLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '오늘은 ${widget.day}요일 기본 퇴근 시간이 설정되어 있지 않습니다. 퇴근 이후 안내를 위해 해당 요일의 정규 퇴근 시간을 설정해 주세요.',
            style: text.bodyMedium?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
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
                  '퇴근 예정 시간',
                  style: text.labelMedium?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _PromptTimeSelector(
                  timeText: timeText,
                  onPressed: _pickTime,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '저장하면 이 요일의 정규 퇴근 시간으로 적용됩니다.',
            style: text.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: PromptButton(
                  label: '넘기기',
                  icon: Icons.skip_next_rounded,
                  variant: PromptButtonVariant.tertiary,
                  onPressed: () => Navigator.of(context).pop(),
                  haptic: PromptHaptic.selection,
                  expand: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PromptButton(
                  label: '저장하기',
                  icon: Icons.save_rounded,
                  onPressed: () => Navigator.of(context).pop(_selected),
                  haptic: PromptHaptic.medium,
                  expand: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegacyDialog() {
    final timeText = WorkSchedulePrefs.formatTime(_selected) ?? '18:00';

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: Color(0xFFF97316),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '퇴근 시간 설정이 필요합니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '오늘은 ${widget.day}요일 기본 퇴근 시간이 설정되어 있지 않습니다. 퇴근 이후 안내를 위해 해당 요일의 정규 퇴근 시간을 설정해 주세요.',
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Color(0xFF4B5563),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '퇴근 예정 시간',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF111827),
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.access_time_rounded, size: 20),
                    label: Text(
                      timeText,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '저장하면 이 요일의 정규 퇴근 시간으로 적용됩니다.',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('넘기기'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('저장하기'),
        ),
      ],
    );
  }
}

class _PromptTimeSelector extends StatefulWidget {
  const _PromptTimeSelector({
    required this.timeText,
    required this.onPressed,
  });

  final String timeText;
  final VoidCallback onPressed;

  @override
  State<_PromptTimeSelector> createState() => _PromptTimeSelectorState();
}

class _PromptTimeSelectorState extends State<_PromptTimeSelector> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final background = _pressed || _hovered
        ? tokens.surfaceSelected
        : tokens.accentContainer;
    final border = _focused ? tokens.focusRing : tokens.accent;

    return Semantics(
      button: true,
      label: '퇴근 예정 시간 ${widget.timeText}',
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        width: double.infinity,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(PromptUiShapes.button),
          border: Border.all(color: border, width: _focused ? 2 : 1),
          boxShadow: [
            if (_focused)
              BoxShadow(
                color: tokens.focusRing.withOpacity(0.24),
                blurRadius: 0,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(PromptUiShapes.button),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onPressed,
            onHighlightChanged: (value) {
              if (_pressed == value) return;
              setState(() => _pressed = value);
            },
            onHover: (value) {
              if (_hovered == value) return;
              setState(() => _hovered = value);
            },
            onFocusChange: (value) {
              if (_focused == value) return;
              setState(() => _focused = value);
            },
            borderRadius: BorderRadius.circular(PromptUiShapes.button),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: AnimatedScale(
                scale: _pressed ? 0.98 : 1,
                duration: reduceMotion ? Duration.zero : PromptUiMotion.press,
                curve: PromptUiMotion.enter,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 20,
                      color: tokens.onAccentContainer,
                    ),
                    const SizedBox(width: 9),
                    AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : PromptUiMotion.selection,
                      switchInCurve: PromptUiMotion.enter,
                      switchOutCurve: PromptUiMotion.exit,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(scale: animation, child: child),
                        );
                      },
                      child: Text(
                        widget.timeText,
                        key: ValueKey<String>(widget.timeText),
                        style: text.titleMedium?.copyWith(
                          color: tokens.onAccentContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
