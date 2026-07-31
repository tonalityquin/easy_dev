import 'package:flutter/material.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_ui.dart';

Future<void> showSprintExternalEventEditorSheet({
  required BuildContext context,
  required SprintModeStore store,
  SprintExternalEvent? event,
  DateTime? initialDate,
  String? initialCalendarProfileId,
}) async {
  await sprintShowBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => SprintExternalEventEditorSheet(
      store: store,
      event: event,
      initialDate: initialDate,
      initialCalendarProfileId: initialCalendarProfileId,
    ),
  );
}

class SprintExternalEventEditorSheet extends StatefulWidget {
  const SprintExternalEventEditorSheet({
    super.key,
    required this.store,
    this.event,
    this.initialDate,
    this.initialCalendarProfileId,
  });

  final SprintModeStore store;
  final SprintExternalEvent? event;
  final DateTime? initialDate;
  final String? initialCalendarProfileId;

  @override
  State<SprintExternalEventEditorSheet> createState() =>
      _SprintExternalEventEditorSheetState();
}

class _SprintExternalEventEditorSheetState
    extends State<SprintExternalEventEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String? _calendarProfileId;
  late bool _allDay;
  late DateTime _startDate;
  late DateTime _endDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  bool get _editing => widget.event != null;
  bool get _busy => _saving || _deleting;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    final initialDay = _day(widget.initialDate ?? DateTime.now());
    _titleController = TextEditingController(text: event?.title ?? '');
    _descriptionController =
        TextEditingController(text: event?.description ?? '');
    _calendarProfileId = event?.calendarProfileId ??
        widget.store
            .preferredEditableCalendarProfile(widget.initialCalendarProfileId)
            ?.id;
    _allDay = event?.allDay ?? true;
    if (event == null) {
      _startDate = initialDay;
      _endDate = initialDay;
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 10, minute: 0);
    } else if (event.allDay) {
      _startDate = _day(event.start);
      _endDate = _day(event.end.subtract(const Duration(days: 1)));
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 10, minute: 0);
    } else {
      _startDate = _day(event.start);
      _endDate = _day(event.end);
      _startTime = TimeOfDay.fromDateTime(event.start);
      _endTime = TimeOfDay.fromDateTime(event.end);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  SprintCalendarProfile? get _profile =>
      widget.store.calendarProfileById(_calendarProfileId);

  DateTime get _resolvedStart {
    if (_allDay) return _startDate;
    return DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _startTime.hour,
      _startTime.minute,
    );
  }

  DateTime get _resolvedEnd {
    if (_allDay) return _endDate.add(const Duration(days: 1));
    return DateTime(
      _endDate.year,
      _endDate.month,
      _endDate.day,
      _endTime.hour,
      _endTime.minute,
    );
  }

  String _errorMessage(Object error) {
    final value = error.toString().toLowerCase();
    if (value.contains('calendar_event_conflict')) {
      return '다른 기기에서 먼저 변경된 일정입니다. 캘린더를 다시 동기화한 뒤 수정하세요.';
    }
    if (value.contains('calendar_write_access_required')) {
      return '이 캘린더에는 일정 변경 권한이 없습니다.';
    }
    if (value.contains('calendar_event_invalid_range')) {
      return '종료 시각은 시작 시각보다 늦어야 합니다.';
    }
    if (value.contains('calendar_profile_not_found')) {
      return '연결된 Google 캘린더를 찾지 못했습니다.';
    }
    if (value.contains('calendar_profile_account_mismatch') ||
        value.contains('calendar_profile_account_missing')) {
      return '현재 앱 사용자 계정의 공유 캘린더 목록에서 이 캘린더를 다시 연결하세요.';
    }
    if (value.contains('google_authentication_required')) {
      return '현재 앱 사용자 계정의 Google Calendar 권한을 갱신하세요.';
    }
    if (value.contains('404') || value.contains('not found')) {
      return 'Google Calendar에서 일정을 찾지 못했습니다.';
    }
    return 'Google Calendar 일정 작업을 완료하지 못했습니다.';
  }

  Future<void> _pickStartDate() async {
    final picked = await sprintShowDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      cancelText: '취소',
      confirmText: '선택',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startDate = _day(picked);
      if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      _error = null;
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await sprintShowDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime(2100),
      cancelText: '취소',
      confirmText: '선택',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _endDate = _day(picked);
      _error = null;
    });
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      cancelText: '취소',
      confirmText: '선택',
      builder: (pickerContext, child) {
        return CommonUiScope(child: child ?? const SizedBox.shrink());
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startTime = picked;
      _error = null;
    });
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      cancelText: '취소',
      confirmText: '선택',
      builder: (pickerContext, child) {
        return CommonUiScope(child: child ?? const SizedBox.shrink());
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _endTime = picked;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    final profile = _profile;
    final title = _titleController.text.trim();
    if (profile == null || !profile.canEditEvents) {
      setState(() => _error = '일정 변경 권한이 있는 캘린더를 선택하세요.');
      return;
    }
    if (title.isEmpty) {
      setState(() => _error = '일정명을 입력하세요.');
      return;
    }
    final start = _resolvedStart;
    final end = _resolvedEnd;
    if (!end.isAfter(start)) {
      setState(() => _error = '종료 시각은 시작 시각보다 늦어야 합니다.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: _editing ? 'Google 일정 수정' : 'Google 일정 추가',
      initialMessage: _editing
          ? '공유 Google Calendar 일정을 수정하고 있습니다.'
          : '공유 Google Calendar에 일정을 추가하고 있습니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: Google Calendar 작업 로그를 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: Google Calendar 작업 로그를 콘솔에 기록합니다.',
    );
    trace.log(
      'profile=${profile.id} calendar=${profile.calendarId} '
      'accessRole=${profile.accessRole} account=${widget.store.accountForProfile(profile.id)?.email ?? ''}',
      progress: 0.16,
    );
    trace.log(
      'event=${widget.event?.googleEventId ?? 'new'} allDay=$_allDay '
      'start=${start.toIso8601String()} end=${end.toIso8601String()} '
      'titleLength=${title.length} descriptionLength=${_descriptionController.text.trim().length}',
      progress: 0.34,
    );
    try {
      if (!widget.store.isProfileAuthenticated(profile.id)) {
        trace.log('현재 앱 사용자 계정의 Calendar 권한을 갱신하고 있습니다.', progress: 0.46);
        await widget.store.authenticateCalendarProfile(profile.id);
      }
      trace.log('Google Calendar API에 변경 내용을 전송하고 있습니다.', progress: 0.7);
      final result = _editing
          ? await widget.store.updateExternalCalendarEvent(
              eventId: widget.event!.id,
              title: title,
              description: _descriptionController.text,
              start: start,
              end: end,
              allDay: _allDay,
            )
          : await widget.store.createExternalCalendarEvent(
              calendarProfileId: profile.id,
              title: title,
              description: _descriptionController.text,
              start: start,
              end: end,
              allDay: _allDay,
            );
      trace.log(
        'event=${result.googleEventId} etag=${result.etag ?? ''} '
        'remoteUpdatedAt=${result.remoteUpdatedAt?.toIso8601String() ?? ''}',
        progress: 0.94,
      );
      await trace.succeed(
        _editing
            ? 'Google Calendar 일정을 수정했습니다.'
            : 'Google Calendar에 일정을 추가했습니다.',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      final message = _errorMessage(error);
      await trace.fail(
        message,
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _error = message);
      if (!trace.developerMode) {
        sprintShowMessage(
          context: context,
          message: message,
          danger: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final event = widget.event;
    final profile = _profile;
    if (event == null || profile == null || _busy) return;
    final confirmed = await sprintShowDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Google 일정 삭제'),
              content: Text('${event.title} 일정을 Google Calendar에서 삭제할까요?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('취소'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('삭제'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: 'Google 일정 삭제',
      initialMessage: '공유 Google Calendar 일정을 삭제하고 있습니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: Google Calendar 삭제 로그를 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: Google Calendar 삭제 로그를 콘솔에 기록합니다.',
    );
    trace.log(
      'profile=${profile.id} calendar=${profile.calendarId} '
      'accessRole=${profile.accessRole} event=${event.googleEventId} '
      'etag=${event.etag ?? ''}',
      progress: 0.32,
    );
    try {
      if (!widget.store.isProfileAuthenticated(profile.id)) {
        trace.log('현재 앱 사용자 계정의 Calendar 권한을 갱신하고 있습니다.', progress: 0.48);
        await widget.store.authenticateCalendarProfile(profile.id);
      }
      trace.log('Google Calendar API에 삭제를 요청하고 있습니다.', progress: 0.72);
      await widget.store.deleteExternalCalendarEvent(event.id);
      await trace.succeed('Google Calendar 일정을 삭제했습니다.');
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      final message = _errorMessage(error);
      await trace.fail(
        message,
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _error = message);
      if (!trace.developerMode) {
        sprintShowMessage(
          context: context,
          message: message,
          danger: true,
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 260);
    final profiles = widget.store.editableCalendarProfiles;
    final profile = _profile;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: AnimatedSize(
          duration: duration,
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AnimatedSwitcher(
                    duration: duration,
                    child: Icon(
                      _editing
                          ? Icons.edit_calendar_rounded
                          : Icons.event_available_rounded,
                      key: ValueKey<bool>(_editing),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _editing ? 'Google 일정 수정' : 'Google 일정 추가',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: profiles.any((candidate) =>
                        candidate.id == _calendarProfileId)
                    ? _calendarProfileId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Google 캘린더',
                  prefixIcon: Icon(Icons.calendar_month_outlined),
                ),
                items: profiles
                    .map(
                      (candidate) => DropdownMenuItem<String>(
                        value: candidate.id,
                        child: Text(
                          '${candidate.label} · ${candidate.accessRoleLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _editing || _busy
                    ? null
                    : (value) {
                        setState(() {
                          _calendarProfileId = value;
                          _error = null;
                        });
                      },
              ),
              AnimatedSwitcher(
                duration: duration,
                child: profile == null
                    ? const SizedBox.shrink()
                    : Padding(
                        key: ValueKey<String>(
                          '${profile.id}-${profile.accessRole}',
                        ),
                        padding: const EdgeInsets.only(top: 8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: profile.canManageSharing
                                ? colors.primaryContainer
                                : colors.secondaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  profile.canManageSharing
                                      ? Icons.admin_panel_settings_rounded
                                      : Icons.edit_calendar_outlined,
                                  size: 19,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    profile.canManageSharing
                                        ? '변경 및 공유 관리 권한으로 일정 전체 편집 가능'
                                        : '일정 변경 권한으로 추가·수정·삭제 가능',
                                    style: const TextStyle(
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
              const SizedBox(height: 14),
              TextField(
                controller: _titleController,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '일정명',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                enabled: !_busy,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '일정 내용',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: _allDay
                      ? colors.primaryContainer
                      : colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SwitchListTile.adaptive(
                  value: _allDay,
                  onChanged: _busy
                      ? null
                      : (value) {
                          setState(() {
                            _allDay = value;
                            _error = null;
                          });
                        },
                  title: const Text(
                    '종일 일정',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  secondary: const Icon(Icons.wb_sunny_outlined),
                ),
              ),
              const SizedBox(height: 12),
              _DateTimeSelectionTile(
                icon: Icons.play_circle_outline_rounded,
                title: '시작',
                dateLabel: sprintFormatDate(_startDate),
                timeLabel: _allDay ? null : _startTime.format(context),
                duration: duration,
                enabled: !_busy,
                onDateTap: _pickStartDate,
                onTimeTap: _pickStartTime,
              ),
              const SizedBox(height: 10),
              _DateTimeSelectionTile(
                icon: Icons.stop_circle_outlined,
                title: '종료',
                dateLabel: sprintFormatDate(_endDate),
                timeLabel: _allDay ? null : _endTime.format(context),
                duration: duration,
                enabled: !_busy,
                onDateTap: _pickEndDate,
                onTimeTap: _pickEndTime,
              ),
              AnimatedSize(
                duration: duration,
                curve: Curves.easeOutCubic,
                child: _error == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: colors.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: duration,
                child: _busy
                    ? const Center(
                        key: ValueKey<String>('calendar-event-busy'),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.6),
                        ),
                      )
                    : FilledButton.icon(
                        key: const ValueKey<String>('calendar-event-save'),
                        onPressed: profile?.canEditEvents == true ? _save : null,
                        icon: Icon(
                          _editing
                              ? Icons.save_outlined
                              : Icons.add_circle_outline_rounded,
                        ),
                        label: Text(_editing ? '변경 저장' : 'Google 일정 추가'),
                      ),
              ),
              if (_editing) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Google Calendar에서 삭제'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DateTimeSelectionTile extends StatelessWidget {
  const _DateTimeSelectionTile({
    required this.icon,
    required this.title,
    required this.dateLabel,
    required this.timeLabel,
    required this.duration,
    required this.enabled,
    required this.onDateTap,
    required this.onTimeTap,
  });

  final IconData icon;
  final String title;
  final String dateLabel;
  final String? timeLabel;
  final Duration duration;
  final bool enabled;
  final VoidCallback onDateTap;
  final VoidCallback onTimeTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          SizedBox(
            width: 42,
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: OutlinedButton(
              onPressed: enabled ? onDateTap : null,
              child: Text(dateLabel),
            ),
          ),
          AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            child: timeLabel == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: OutlinedButton(
                      onPressed: enabled ? onTimeTap : null,
                      child: Text(timeLabel!),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
