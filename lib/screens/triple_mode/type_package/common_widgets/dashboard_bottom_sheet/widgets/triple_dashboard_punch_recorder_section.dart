import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../../../features/commute/domain/repositories/commute_true_false_repository.dart';
import '../../../../../../features/mode_single/application/att_brk_repository.dart';
import '../../../../../../utils/init/app_exit_service.dart';
import '../../../../../../widgets/dialog/block_dialog_package/work_end_duration_blocking_dialog.dart';
import 'triple_dashboard_punch_card_feedback.dart';
import '../../../../../../utils/config/commute_true_false_mode_config.dart';

class _NeutralTone {
  final Color text;
  final Color border;

  const _NeutralTone({
    required this.text,
    required this.border,
  });
}

class TripleDashboardInsidePunchRecorderSection extends StatefulWidget {
  const TripleDashboardInsidePunchRecorderSection({
    super.key,
    required this.userId,
    required this.userName,
    required this.area,
    required this.division,
  });

  final String userId;
  final String userName;
  final String area;
  final String division;

  @override
  State<TripleDashboardInsidePunchRecorderSection> createState() =>
      _TripleDashboardInsidePunchRecorderSectionState();
}

class _TripleDashboardInsidePunchRecorderSectionState
    extends State<TripleDashboardInsidePunchRecorderSection> {
  late DateTime _selectedDate;

  String? _workInTime;
  String? _breakTime;
  String? _workOutTime;
  bool _loading = true;

  final CommuteTrueFalseRepository _commuteTrueFalseRepo =
  CommuteTrueFalseRepository();

  bool get _hasWorkIn => _workInTime != null && _workInTime!.isNotEmpty;
  bool get _hasBreak => _breakTime != null && _breakTime!.isNotEmpty;

  bool get _disableWorkInPunch => true;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadForDate(_selectedDate);
  }

  Future<void> _loadForDate(DateTime date) async {
    setState(() => _loading = true);

    final events = await AttBrkRepository.instance.getEventsForDate(date);

    setState(() {
      _selectedDate = date;
      _workInTime = events[AttBrkModeType.workIn];
      _breakTime = events[AttBrkModeType.breakTime];
      _workOutTime = events[AttBrkModeType.workOut];
      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    final init = _selectedDate;
    final first = DateTime(init.year - 1, 1, 1);
    final last = DateTime(init.year + 1, 12, 31);

    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: first,
      lastDate: last,
      builder: (context, child) => child ?? const SizedBox.shrink(),
    );

    if (picked == null) return;
    await _loadForDate(picked);
  }

  Future<void> _recordClockInAtToCommuteTrueFalse(DateTime clockInAt) async {
    final enabled = await CommuteTrueFalseModeConfig.isEnabled();
    if (!enabled) {
      debugPrint('[TriplePunchRecorder] commute_true_false OFF → 스킵');
      return;
    }

    final company = widget.division.trim();
    final area = widget.area.trim();
    final workerName = widget.userName.trim();
    if (company.isEmpty || area.isEmpty || workerName.isEmpty) return;

    await _commuteTrueFalseRepo.setClockInAt(
      company: company,
      area: area,
      workerName: workerName,
      clockInAt: clockInAt,
    );
  }

  Future<void> _exitAppAfterClockOut(BuildContext context) async {
    await AppExitService.exitApp(context);
  }

  Future<void> _punch(AttBrkModeType type) async {
    if (_loading) return;

    if (type == AttBrkModeType.workIn && _disableWorkInPunch) {
      return;
    }

    if (type == AttBrkModeType.breakTime && !_hasWorkIn) {
      return;
    }

    if (type == AttBrkModeType.workOut && (!_hasWorkIn || !_hasBreak)) {
      return;
    }

    if (type == AttBrkModeType.workIn || type == AttBrkModeType.workOut) {
      final isClockIn = type == AttBrkModeType.workIn;

      final proceed = await showWorkEndDurationBlockingDialog(
        context,
        message: isClockIn
            ? '출근을 펀칭하면 근무가 시작됩니다.\n약 5초 정도 소요됩니다.'
            : '퇴근을 펀칭하면 오늘 근무가 종료되고 앱이 종료됩니다.\n약 5초 정도 소요됩니다.',
        duration: const Duration(seconds: 5),
      );

      if (!proceed) return;
    }

    final now = DateTime.now();

    final targetDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );

    await AttBrkRepository.instance.insertEvent(
      dateTime: targetDateTime,
      type: type,
    );

    await showTripleDashboardPunchCardFeedback(
      context,
      type: type,
      dateTime: targetDateTime,
    );

    if (type == AttBrkModeType.workIn) {
      await _recordClockInAtToCommuteTrueFalse(targetDateTime);
    }

    await _loadForDate(_selectedDate);

    if (type == AttBrkModeType.workOut) {
      await _exitAppAfterClockOut(context);
    }
  }

  _NeutralTone _neutralTone(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _NeutralTone(
      text: cs.onSurfaceVariant,
      border: cs.outlineVariant,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = _neutralTone(context);

    final monthStr = DateFormat('yyyy.MM').format(_selectedDate);
    final dateStr = DateFormat('MM.dd').format(_selectedDate);
    final textTheme = Theme.of(context).textTheme;

    final bool canPunchWorkIn = !_disableWorkInPunch ? true : false;
    final bool canPunchBreak = _hasWorkIn;
    final bool canPunchWorkOut = _hasWorkIn && _hasBreak;

    return Card(
      elevation: 0,
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.border.withOpacity(.55)),
      ),
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.access_time,
                    size: 16, color: t.text.withOpacity(.85)),
                const SizedBox(width: 4),
                Text(
                  '출퇴근 기록기',
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _pickDate,
                  child: Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 14, color: t.text.withOpacity(.85)),
                        const SizedBox(width: 4),
                        Text(
                          '$monthStr · $dateStr',
                          style: TextStyle(
                            fontSize: 12,
                            color: t.text.withOpacity(.85),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '선택한 날짜($dateStr) 기준으로 휴게 · 퇴근을 순서대로 펀칭하세요.\n'
                  '출근은 서비스 로그인에서 처리되며, 이 화면에서는 변경할 수 없습니다.',
              style: TextStyle(
                fontSize: 11,
                color: t.text.withOpacity(.85),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: t.border.withOpacity(.55),
                        width: 0.9,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: _PunchSlot(
                            label: '출근',
                            type: AttBrkModeType.workIn,
                            time: _workInTime,
                            enabled: canPunchWorkIn,
                            onTap: () => _punch(AttBrkModeType.workIn),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PunchSlot(
                            label: '휴게',
                            type: AttBrkModeType.breakTime,
                            time: _breakTime,
                            enabled: canPunchBreak,
                            onTap: () => _punch(AttBrkModeType.breakTime),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PunchSlot(
                            label: '퇴근',
                            type: AttBrkModeType.workOut,
                            time: _workOutTime,
                            enabled: canPunchWorkOut,
                            onTap: () => _punch(AttBrkModeType.workOut),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '날짜를 선택해 과거 기록도 수정/재펀칭할 수 있습니다.',
                      style: textTheme.labelSmall
                          ?.copyWith(color: t.text.withOpacity(.75)),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PunchSlot extends StatelessWidget {
  final String label;
  final AttBrkModeType type;
  final String? time;
  final bool enabled;
  final VoidCallback onTap;

  const _PunchSlot({
    required this.label,
    required this.type,
    required this.time,
    required this.enabled,
    required this.onTap,
  });

  Color get _accent {
    switch (type) {
      case AttBrkModeType.workIn:
        return const Color(0xFF09367D);
      case AttBrkModeType.breakTime:
        return const Color(0xFFF2A93B);
      case AttBrkModeType.workOut:
        return const Color(0xFFEF6C53);
    }
  }

  IconData get _icon {
    switch (type) {
      case AttBrkModeType.workIn:
        return Icons.login;
      case AttBrkModeType.breakTime:
        return Icons.free_breakfast;
      case AttBrkModeType.workOut:
        return Icons.logout;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final punched = time != null && time!.isNotEmpty;

    final borderColor = punched
        ? _accent.withOpacity(0.85)
        : cs.outlineVariant.withOpacity(enabled ? .70 : .35);

    final bgColor = punched ? _accent.withOpacity(0.08) : cs.surface;

    final content = Ink(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: borderColor,
          width: punched ? 1.1 : 0.8,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _icon,
                size: 14,
                color: enabled
                    ? _accent.withOpacity(0.92)
                    : cs.onSurfaceVariant.withOpacity(0.35),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: enabled
                      ? _accent.withOpacity(0.92)
                      : cs.onSurfaceVariant.withOpacity(0.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Icon(
            punched ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 18,
            color: punched
                ? _accent.withOpacity(0.95)
                : cs.outlineVariant.withOpacity(enabled ? .9 : .4),
          ),
          const SizedBox(height: 2),
          Text(
            punched ? '펀칭 완료' : '미펀칭',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: punched ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: content,
      ),
    );
  }
}
