import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../app/utils/status_dialog.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/google_calendar/google_event_colors.dart';
import '../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../selector/application/dev_auth.dart';
import '../../sprint/application/sprint_mode_store.dart';
import '../../sprint/domain/sprint_models.dart';
import '../../sprint/pages/sprint_ui.dart';

class HeadquarterCalendarEventEditorDiagnostics {
  static const int _limit = 180;
  static final List<String> _lines = <String>[];

  static void log(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final line =
        '[HQ_CALENDAR_EDITOR][${DateTime.now().toIso8601String()}] $normalized';
    _lines.add(line);
    if (_lines.length > _limit) {
      _lines.removeRange(0, _lines.length - _limit);
    }
    debugPrint(line);
  }

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[HQ_CALENDAR_EDITOR] 기록된 로그가 없습니다.')});';
    }
    return _lines.map((line) => 'debugPrint(${jsonEncode(line)});').join('\n');
  }

  static Future<void> showStatus(
    BuildContext context, {
    required String description,
  }) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    await StatusDialog.showSuccess(
      context,
      title: '일정 편집 Side Dock 상태',
      description: description,
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}

Future<void> showHeadquarterCalendarEventEditorSideDock({
  required BuildContext context,
  required SprintModeStore store,
  SprintExternalEvent? event,
  DateTime? initialDate,
  String? initialCalendarProfileId,
}) async {
  final editing = event != null;
  HeadquarterCalendarEventEditorDiagnostics.log(
    'dock_open mode=${editing ? 'update' : 'create'} '
    'event=${event?.googleEventId ?? 'new'} '
    'date=${(initialDate ?? event?.start)?.toIso8601String() ?? ''}',
  );
  await showCommonLeftSideDock<void>(
    context: context,
    barrierLabel: editing ? '일정 수정' : '일정 추가',
    maxWidth: 430,
    widthFactor: .94,
    barrierDismissible: false,
    builder: (_) => _HeadquarterCalendarEventEditorSideDock(
      store: store,
      event: event,
      initialDate: initialDate,
      initialCalendarProfileId: initialCalendarProfileId,
    ),
  );
  HeadquarterCalendarEventEditorDiagnostics.log(
    'dock_closed mode=${editing ? 'update' : 'create'} '
    'event=${event?.googleEventId ?? 'new'}',
  );
}

class _HeadquarterCalendarEventEditorSideDock extends StatefulWidget {
  const _HeadquarterCalendarEventEditorSideDock({
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
  State<_HeadquarterCalendarEventEditorSideDock> createState() =>
      _HeadquarterCalendarEventEditorSideDockState();
}

class _HeadquarterCalendarEventEditorSideDockState
    extends State<_HeadquarterCalendarEventEditorSideDock> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String? _calendarProfileId;
  late String? _colorId;
  late bool _allDay;
  late DateTime _startDate;
  late DateTime _endDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _calendarExpanded = false;
  bool _colorExpanded = false;
  bool _saving = false;
  bool _deleting = false;
  bool _dirty = false;
  bool _developerMode = false;
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
    _colorId = event?.colorId;
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
    _titleController.addListener(_handleTextChanged);
    _descriptionController.addListener(_handleTextChanged);
    unawaited(_loadDeveloperMode());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      HeadquarterCalendarEventEditorDiagnostics.log(
        'editor_ready mode=${_editing ? 'update' : 'create'} '
        'profile=${_calendarProfileId ?? ''} colorId=${_colorId ?? ''} '
        'allDay=$_allDay start=${_resolvedStart.toIso8601String()} '
        'end=${_resolvedEnd.toIso8601String()}',
      );
    });
  }

  @override
  void dispose() {
    _titleController.removeListener(_handleTextChanged);
    _descriptionController.removeListener(_handleTextChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    if (!mounted || (_dirty && _error == null)) return;
    setState(() {
      _dirty = true;
      _error = null;
    });
  }

  Future<void> _loadDeveloperMode() async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!mounted) return;
    setState(() => _developerMode = enabled);
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
      return '연결된 캘린더를 찾지 못했습니다.';
    }
    if (value.contains('calendar_profile_account_mismatch') ||
        value.contains('calendar_profile_account_missing')) {
      return '현재 앱 사용자 계정의 공유 캘린더 목록에서 이 캘린더를 다시 연결하세요.';
    }
    if (value.contains('google_authentication_required')) {
      return '현재 앱 사용자 계정의 캘린더 연결 권한을 갱신하세요.';
    }
    if (value.contains('404') || value.contains('not found')) {
      return '연결된 캘린더에서 일정을 찾지 못했습니다.';
    }
    return '일정 작업을 완료하지 못했습니다.';
  }

  void _markDirty(VoidCallback change) {
    if (!mounted) return;
    setState(() {
      change();
      _dirty = true;
      _error = null;
    });
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
    _markDirty(() {
      _startDate = _day(picked);
      if (_endDate.isBefore(_startDate)) _endDate = _startDate;
    });
    HeadquarterCalendarEventEditorDiagnostics.log(
      'start_date=${_startDate.toIso8601String()}',
    );
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
    _markDirty(() => _endDate = _day(picked));
    HeadquarterCalendarEventEditorDiagnostics.log(
      'end_date=${_endDate.toIso8601String()}',
    );
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
    _markDirty(() => _startTime = picked);
    HeadquarterCalendarEventEditorDiagnostics.log(
      'start_time=${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
    );
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
    _markDirty(() => _endTime = picked);
    HeadquarterCalendarEventEditorDiagnostics.log(
      'end_time=${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
    );
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final confirmed = await showCommonOverlayDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('일정 편집 종료'),
            content: const Text('변경한 내용을 저장하지 않고 닫을까요?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('계속 편집'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('닫기'),
              ),
            ],
          ),
        ) ??
        false;
    HeadquarterCalendarEventEditorDiagnostics.log(
      'discard_confirmed=$confirmed dirty=$_dirty',
    );
    return confirmed;
  }

  Future<bool> _handleWillPop() async {
    if (_busy) return false;
    return _confirmDiscard();
  }

  Future<void> _requestClose() async {
    if (_busy) return;
    if (!await _confirmDiscard() || !mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _showStatus() async {
    final profile = _profile;
    HeadquarterCalendarEventEditorDiagnostics.log(
      'status mode=${_editing ? 'update' : 'create'} dirty=$_dirty busy=$_busy '
      'profile=${profile?.id ?? ''} calendar=${profile?.calendarId ?? ''} '
      'colorId=${_colorId ?? ''} allDay=$_allDay '
      'start=${_resolvedStart.toIso8601String()} end=${_resolvedEnd.toIso8601String()}',
    );
    await HeadquarterCalendarEventEditorDiagnostics.showStatus(
      context,
      description:
          '${_editing ? '일정 수정' : '일정 추가'} · ${profile == null ? '캘린더 미선택' : widget.store.calendarProfileLabel(profile.id)} · debugPrint 코드를 복사할 수 있습니다.',
    );
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
    HeadquarterCalendarEventEditorDiagnostics.log(
      'save_start mode=${_editing ? 'update' : 'create'} '
      'profile=${profile.id} event=${widget.event?.googleEventId ?? 'new'} '
      'colorId=${_colorId ?? ''} allDay=$_allDay',
    );
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: _editing ? '일정 수정' : '일정 추가',
      initialMessage: _editing
          ? '연결된 캘린더 일정을 수정하고 있습니다.'
          : '연결된 캘린더에 일정을 추가하고 있습니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 일정 Side Dock 작업 로그를 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 일정 Side Dock 작업 로그를 콘솔에 기록합니다.',
    );
    trace.log(
      'presentation=left_side_dock profile=${profile.id} '
      'calendar=${profile.calendarId} accessRole=${profile.accessRole} '
      'account=${widget.store.accountForProfile(profile.id)?.email ?? ''}',
      progress: 0.16,
    );
    trace.log(
      'event=${widget.event?.googleEventId ?? 'new'} colorId=${_colorId ?? ''} '
      'allDay=$_allDay start=${start.toIso8601String()} '
      'end=${end.toIso8601String()} titleLength=${title.length} '
      'descriptionLength=${_descriptionController.text.trim().length}',
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
              colorId: _colorId,
            )
          : await widget.store.createExternalCalendarEvent(
              calendarProfileId: profile.id,
              title: title,
              description: _descriptionController.text,
              start: start,
              end: end,
              allDay: _allDay,
              colorId: _colorId,
            );
      trace.log(
        'event=${result.googleEventId} colorId=${result.colorId ?? ''} '
        'etag=${result.etag ?? ''} '
        'remoteUpdatedAt=${result.remoteUpdatedAt?.toIso8601String() ?? ''}',
        progress: 0.94,
      );
      await trace.succeed(_editing ? '일정을 수정했습니다.' : '일정을 추가했습니다.');
      HeadquarterCalendarEventEditorDiagnostics.log(
        'save_success event=${result.googleEventId} colorId=${result.colorId ?? ''}',
      );
      if (!mounted) return;
      setState(() => _dirty = false);
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      final message = _errorMessage(error);
      HeadquarterCalendarEventEditorDiagnostics.log(
        'save_failure error=$error message=$message',
      );
      await trace.fail(message, error: error, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _error = message);
      if (!trace.developerMode) {
        sprintShowMessage(context: context, message: message, danger: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final event = widget.event;
    final profile = _profile;
    if (event == null || profile == null || _busy) return;
    final confirmed = await showCommonOverlayDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('일정 삭제'),
            content: Text('${event.title} 일정을 연결된 캘린더에서 삭제할까요?'),
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
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    HeadquarterCalendarEventEditorDiagnostics.log(
      'delete_start profile=${profile.id} event=${event.googleEventId} '
      'etag=${event.etag ?? ''}',
    );
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '일정 삭제',
      initialMessage: '연결된 캘린더 일정을 삭제하고 있습니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 일정 Side Dock 삭제 로그를 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 일정 Side Dock 삭제 로그를 콘솔에 기록합니다.',
    );
    trace.log(
      'presentation=left_side_dock profile=${profile.id} '
      'calendar=${profile.calendarId} accessRole=${profile.accessRole} '
      'event=${event.googleEventId} etag=${event.etag ?? ''}',
      progress: 0.32,
    );
    try {
      if (!widget.store.isProfileAuthenticated(profile.id)) {
        trace.log('현재 앱 사용자 계정의 Calendar 권한을 갱신하고 있습니다.', progress: 0.48);
        await widget.store.authenticateCalendarProfile(profile.id);
      }
      trace.log('Google Calendar API에 삭제를 요청하고 있습니다.', progress: 0.72);
      await widget.store.deleteExternalCalendarEvent(event.id);
      await trace.succeed('일정을 삭제했습니다.');
      HeadquarterCalendarEventEditorDiagnostics.log(
        'delete_success event=${event.googleEventId}',
      );
      if (!mounted) return;
      setState(() => _dirty = false);
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      final message = _errorMessage(error);
      HeadquarterCalendarEventEditorDiagnostics.log(
        'delete_failure error=$error message=$message',
      );
      await trace.fail(message, error: error, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _error = message);
      if (!trace.developerMode) {
        sprintShowMessage(context: context, message: message, danger: true);
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _divider(CommonUiTokens tokens) {
    return Divider(height: 1, thickness: 1, color: tokens.borderSubtle);
  }

  Widget _buildCalendarSection(CommonUiTokens tokens) {
    final profile = _profile;
    final profiles = widget.store.editableCalendarProfiles;
    return OpsDockListSurface(
      child: Column(
        children: [
          _EditorValueRow(
            icon: Icons.calendar_today_outlined,
            label: '캘린더',
            value: profile == null
                ? '선택 안 됨'
                : widget.store.calendarProfileLabel(profile.id),
            enabled: !_busy && !_editing && profiles.length > 1,
            expanded: _calendarExpanded,
            onTap: !_busy && !_editing && profiles.length > 1
                ? () {
                    HapticFeedback.selectionClick();
                    setState(() => _calendarExpanded = !_calendarExpanded);
                  }
                : null,
          ),
          _divider(tokens),
          _EditorValueRow(
            icon: Icons.verified_user_outlined,
            label: '권한',
            value: profile?.accessRoleLabel ?? '확인 필요',
          ),
          AnimatedSize(
            duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                ? Duration.zero
                : CommonUiMotion.selection,
            curve: CommonUiMotion.enter,
            alignment: Alignment.topCenter,
            child: !_calendarExpanded || _editing
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      _divider(tokens),
                      for (var index = 0; index < profiles.length; index++) ...[
                        if (index > 0) _divider(tokens),
                        OpsDockSelectableRowSurface(
                          selected: profiles[index].id == _calendarProfileId,
                          selectionColor: tokens.accent,
                          selectedContainer: tokens.accentContainer,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _markDirty(() {
                              _calendarProfileId = profiles[index].id;
                              _calendarExpanded = false;
                            });
                            HeadquarterCalendarEventEditorDiagnostics.log(
                              'calendar_selected profile=${profiles[index].id} '
                              'calendar=${profiles[index].calendarId}',
                            );
                          },
                          child: Row(
                            children: [
                              Icon(
                                profiles[index].googlePrimary
                                    ? Icons.person_outline_rounded
                                    : Icons.business_outlined,
                                size: 19,
                                color: profiles[index].id == _calendarProfileId
                                    ? tokens.accent
                                    : tokens.iconSecondary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  widget.store.calendarProfileLabel(
                                    profiles[index].id,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: tokens.textPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                              Text(
                                profiles[index].accessRoleLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: tokens.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentSection(CommonUiTokens tokens) {
    return OpsDockListSurface(
      child: Column(
        children: [
          _EditorTextFieldRow(
            icon: Icons.title_rounded,
            label: '일정명',
            controller: _titleController,
            enabled: !_busy,
            maxLines: 1,
            textInputAction: TextInputAction.next,
          ),
          _divider(tokens),
          _EditorTextFieldRow(
            icon: Icons.notes_rounded,
            label: '일정 내용',
            controller: _descriptionController,
            enabled: !_busy,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
          ),
          _divider(tokens),
          _EditorValueRow(
            icon: Icons.palette_outlined,
            label: '색상',
            value: _colorId == null ? '기본' : '색상 $_colorId',
            leadingValue: _EventColorDot(colorId: _colorId),
            enabled: !_busy,
            expanded: _colorExpanded,
            onTap: _busy
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    setState(() => _colorExpanded = !_colorExpanded);
                  },
          ),
          AnimatedSize(
            duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                ? Duration.zero
                : CommonUiMotion.selection,
            curve: CommonUiMotion.enter,
            alignment: Alignment.topCenter,
            child: !_colorExpanded
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      _divider(tokens),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                        child: _CompactGoogleEventColorPicker(
                          selectedId: _colorId,
                          enabled: !_busy,
                          onSelected: (colorId) {
                            HapticFeedback.selectionClick();
                            _markDirty(() => _colorId = colorId);
                            HeadquarterCalendarEventEditorDiagnostics.log(
                              'color_selected colorId=$colorId',
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSection(CommonUiTokens tokens) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    return OpsDockListSurface(
      child: Column(
        children: [
          _EditorSwitchRow(
            icon: Icons.wb_sunny_outlined,
            label: '종일 일정',
            value: _allDay,
            enabled: !_busy,
            onChanged: (value) {
              HapticFeedback.selectionClick();
              _markDirty(() => _allDay = value);
              HeadquarterCalendarEventEditorDiagnostics.log(
                'all_day=$value',
              );
            },
          ),
          _divider(tokens),
          _EditorValueRow(
            icon: Icons.play_circle_outline_rounded,
            label: '시작 날짜',
            value: sprintFormatDate(_startDate),
            enabled: !_busy,
            onTap: _busy ? null : _pickStartDate,
          ),
          AnimatedSize(
            duration: duration,
            curve: CommonUiMotion.enter,
            alignment: Alignment.topCenter,
            child: _allDay
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      _divider(tokens),
                      _AnimatedEditorRow(
                        child: _EditorValueRow(
                          icon: Icons.schedule_rounded,
                          label: '시작 시간',
                          value: _startTime.format(context),
                          enabled: !_busy,
                          onTap: _busy ? null : _pickStartTime,
                        ),
                      ),
                    ],
                  ),
          ),
          _divider(tokens),
          _EditorValueRow(
            icon: Icons.stop_circle_outlined,
            label: '종료 날짜',
            value: sprintFormatDate(_endDate),
            enabled: !_busy,
            onTap: _busy ? null : _pickEndDate,
          ),
          AnimatedSize(
            duration: duration,
            curve: CommonUiMotion.enter,
            alignment: Alignment.topCenter,
            child: _allDay
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      _divider(tokens),
                      _AnimatedEditorRow(
                        child: _EditorValueRow(
                          icon: Icons.schedule_rounded,
                          label: '종료 시간',
                          value: _endTime.format(context),
                          enabled: !_busy,
                          onTap: _busy ? null : _pickEndTime,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(CommonUiTokens tokens) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    return AnimatedSize(
      duration: duration,
      curve: CommonUiMotion.enter,
      alignment: Alignment.topCenter,
      child: _error == null
          ? const SizedBox.shrink()
          : CommonSideDockReveal(
              order: 4,
              child: OpsDockListSurface(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 20,
                        color: tokens.danger,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: tokens.danger,
                                fontWeight: FontWeight.w800,
                                height: 1.35,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildFooter() {
    final children = <Widget>[];
    if (_editing) {
      children.add(
        Expanded(
          child: CommonButton(
            label: '일정 삭제',
            icon: Icons.delete_outline_rounded,
            variant: CommonButtonVariant.destructive,
            onPressed: _busy ? null : _delete,
            loading: _deleting,
            expand: true,
            minHeight: 46,
            haptic: CommonHaptic.selection,
          ),
        ),
      );
      children.add(const SizedBox(width: 8));
    }
    children.add(
      Expanded(
        child: CommonButton(
          label: _editing ? '변경 저장' : '일정 추가',
          icon: _editing ? Icons.save_outlined : Icons.add_rounded,
          onPressed: _busy || _profile?.canEditEvents != true ? null : _save,
          loading: _saving,
          expand: true,
          minHeight: 46,
          haptic: CommonHaptic.selection,
        ),
      ),
    );
    return OpsDockContextFooterTransition(
      child: OpsDockContextFooter(children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return WillPopScope(
      onWillPop: _handleWillPop,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: CommonSideDockFrame(
          title: _editing ? '일정 수정' : '일정 추가',
          subtitle: '',
          icon: _editing
              ? Icons.edit_calendar_rounded
              : Icons.event_available_rounded,
          closeEnabled: !_busy,
          onClose: () => unawaited(_requestClose()),
          headerAction: _developerMode
              ? IconButton(
                  onPressed: _busy ? null : _showStatus,
                  icon: Icon(
                    Icons.bug_report_outlined,
                    size: 19,
                    color: tokens.textSecondary,
                  ),
                )
              : null,
          child: ListView(
            padding: const EdgeInsets.only(right: 2, bottom: 4),
            physics: const BouncingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              CommonSideDockReveal(
                order: 1,
                child: _buildCalendarSection(tokens),
              ),
              const SizedBox(height: 10),
              CommonSideDockReveal(
                order: 2,
                child: _buildContentSection(tokens),
              ),
              const SizedBox(height: 10),
              CommonSideDockReveal(
                order: 3,
                child: _buildTimeSection(tokens),
              ),
              AnimatedSize(
                duration:
                    MediaQuery.maybeOf(context)?.disableAnimations ?? false
                        ? Duration.zero
                        : CommonUiMotion.selection,
                curve: CommonUiMotion.enter,
                child: _error == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _buildError(tokens),
                      ),
              ),
            ],
          ),
          footer: _buildFooter(),
        ),
      ),
    );
  }
}

class _EditorValueRow extends StatelessWidget {
  const _EditorValueRow({
    required this.icon,
    required this.label,
    required this.value,
    this.leadingValue,
    this.enabled = true,
    this.expanded = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? leadingValue;
  final bool enabled;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: enabled ? tokens.iconSecondary : tokens.iconDisabled,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: enabled ? tokens.textPrimary : tokens.textDisabled,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          if (leadingValue != null) ...[
            leadingValue!,
            const SizedBox(width: 8),
          ],
          Flexible(
            child: AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              switchInCurve: CommonUiMotion.enter,
              switchOutCurve: CommonUiMotion.exit,
              child: Text(
                value,
                key: ValueKey<String>(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: enabled
                          ? tokens.textSecondary
                          : tokens.textDisabled,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 5),
            AnimatedRotation(
              turns: expanded ? .25 : 0,
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.enter,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: tokens.iconSecondary,
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class _EditorTextFieldRow extends StatelessWidget {
  const _EditorTextFieldRow({
    required this.icon,
    required this.label,
    required this.controller,
    required this.enabled,
    required this.maxLines,
    required this.textInputAction,
  });

  final IconData icon;
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final int maxLines;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              size: 19,
              color: enabled ? tokens.iconSecondary : tokens.iconDisabled,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  enabled: enabled,
                  maxLines: maxLines,
                  minLines: maxLines > 1 ? 2 : 1,
                  textInputAction: textInputAction,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorSwitchRow extends StatelessWidget {
  const _EditorSwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      color: value ? tokens.accentContainer.withOpacity(.28) : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            curve: CommonUiMotion.standard,
            child: Icon(
              icon,
              size: 19,
              color: value ? tokens.accent : tokens.iconSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: enabled ? tokens.textPrimary : tokens.textDisabled,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            child: Text(
              value ? 'ON' : 'OFF',
              key: ValueKey<bool>(value),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: value ? tokens.accent : tokens.textSecondary,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: 42,
            height: 34,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Switch(
                value: value,
                onChanged: enabled ? onChanged : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedEditorRow extends StatelessWidget {
  const _AnimatedEditorRow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      duration: CommonUiMotion.selection,
      curve: CommonUiMotion.enter,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, _) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 6 * (1 - value)),
            child: child,
          ),
        );
      },
    );
  }
}

class _EventColorDot extends StatelessWidget {
  const _EventColorDot({required this.colorId});

  final String? colorId;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final color = googleEventColor(colorId, tokens.borderStrong);
    return AnimatedContainer(
      duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
          ? Duration.zero
          : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: tokens.surfaceRaised, width: 2),
      ),
    );
  }
}

class _CompactGoogleEventColorPicker extends StatelessWidget {
  const _CompactGoogleEventColorPicker({
    required this.selectedId,
    required this.enabled,
    required this.onSelected,
  });

  final String? selectedId;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: googleEventColorIds.map((colorId) {
        final selected = selectedId == colorId;
        final color = googleEventColors[colorId]!;
        return Semantics(
          button: true,
          selected: selected,
          enabled: enabled,
          label: '일정 색상 $colorId',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(CommonUiShapes.pill),
              onTap: enabled ? () => onSelected(colorId) : null,
              child: AnimatedScale(
                scale: selected ? 1.08 : 1,
                duration: duration,
                curve: CommonUiMotion.enter,
                child: AnimatedContainer(
                  duration: duration,
                  curve: CommonUiMotion.standard,
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: enabled ? color : color.withOpacity(.35),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? tokens.textPrimary : tokens.surfaceRaised,
                      width: selected ? 3 : 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: duration,
                    child: selected
                        ? Icon(
                            Icons.check_rounded,
                            key: ValueKey<String>('event-color-$colorId'),
                            size: 17,
                            color: googleEventForegroundColor(
                              colorId,
                              tokens.onAccent,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}
