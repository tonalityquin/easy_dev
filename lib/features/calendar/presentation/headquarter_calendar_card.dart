import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../account/applications/user_state.dart';
import '../../selector/application/dev_auth.dart';
import '../application/headquarter_calendar_audience.dart';
import '../domain/models/headquarter_calendar_attendance.dart';
import '../domain/models/headquarter_calendar_event.dart';
import '../domain/models/headquarter_calendar_event_page.dart';
import '../domain/models/headquarter_calendar_month_summary.dart';
import '../domain/models/headquarter_calendar_search.dart';
import '../domain/repositories/headquarter_calendar_repository.dart';
import 'headquarter_calendar_status_dialog.dart';

class HeadquarterCalendarCard extends StatefulWidget {
  const HeadquarterCalendarCard({super.key});

  @override
  State<HeadquarterCalendarCard> createState() => _HeadquarterCalendarCardState();
}

class _HeadquarterCalendarCardState extends State<HeadquarterCalendarCard> {
  static const int _pageSize = 20;
  static const List<String> _weekdays = <String>['일', '월', '화', '수', '목', '금', '토'];
  static const List<_Option> _eventTypes = <_Option>[
    _Option('notice', '공지', Icons.campaign_rounded),
    _Option('meeting', '회의', Icons.groups_rounded),
    _Option('deadline', '마감', Icons.event_available_rounded),
    _Option('inspection', '점검', Icons.fact_check_rounded),
    _Option('education', '교육', Icons.school_rounded),
    _Option('settlement', '정산', Icons.request_quote_rounded),
    _Option('urgent', '긴급', Icons.priority_high_rounded),
    _Option('holiday', '휴무', Icons.beach_access_rounded),
  ];
  static const List<_Option> _priorities = <_Option>[
    _Option('normal', '일반', Icons.radio_button_unchecked_rounded),
    _Option('high', '중요', Icons.star_rounded),
    _Option('urgent', '긴급', Icons.warning_rounded),
  ];

  late DateTime _visibleMonth;
  late DateTime _selectedDay;
  HeadquarterCalendarRepository? _repository;
  String _configuredUserId = '';
  String _scopeFilter = 'all';
  StreamSubscription<HeadquarterCalendarMonthSummary>? _monthSubscription;
  StreamSubscription<List<HeadquarterCalendarEvent>>? _eventSubscription;
  HeadquarterCalendarMonthSummary? _monthSummary;
  List<HeadquarterCalendarEvent> _liveEvents = const <HeadquarterCalendarEvent>[];
  List<HeadquarterCalendarEvent> _pagedEvents = const <HeadquarterCalendarEvent>[];
  Set<String> _acknowledgedIds = const <String>{};
  String _ackCacheKey = '';
  HeadquarterCalendarEventCursor? _nextCursor;
  bool _monthLoading = true;
  bool _eventsLoading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _monthError;
  StackTrace? _monthStack;
  Object? _eventError;
  StackTrace? _eventStack;
  bool _legacyMigrationChecking = true;
  bool _legacyMigrationReady = false;
  bool _legacyMigrationKnown = false;
  Object? _legacyMigrationError;
  int _eventSubscriptionGeneration = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = context.read<HeadquarterCalendarRepository>();
    final userState = Provider.of<UserState>(context);
    final userId = userState.session?.id.trim() ?? '';
    if (!identical(_repository, repository) || _configuredUserId != userId) {
      _repository = repository;
      _configuredUserId = userId;
      _legacyMigrationKnown = false;
      _legacyMigrationReady = false;
      _subscribeAll();
    }
  }

  @override
  void dispose() {
    _eventSubscriptionGeneration += 1;
    _monthSubscription?.cancel();
    _eventSubscription?.cancel();
    super.dispose();
  }

  String get _monthKey => HeadquarterCalendarEvent.monthKeyOf(_visibleMonth);
  String get _selectedDateKey => HeadquarterCalendarEvent.dateKeyOf(_selectedDay);

  List<HeadquarterCalendarEvent> get _events {
    final map = <String, HeadquarterCalendarEvent>{};
    for (final event in _pagedEvents) map[event.id] = event;
    for (final event in _liveEvents) map[event.id] = event;
    final result = map.values.toList()
      ..sort((a, b) {
        final priority = b.priorityRank.compareTo(a.priorityRank);
        if (priority != 0) return priority;
        final left = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final created = right.compareTo(left);
        if (created != 0) return created;
        return b.id.compareTo(a.id);
      });
    return result;
  }

  void _subscribeAll() {
    _subscribeMonth();
    unawaited(_subscribeEvents());
  }

  void _subscribeMonth() {
    _monthSubscription?.cancel();
    final repository = _repository;
    if (repository == null) return;
    _monthLoading = true;
    _monthError = null;
    _monthStack = null;
    _monthSubscription = repository
        .watchMonthSummary(
          monthKey: _monthKey,
          userId: _configuredUserId,
          scopeFilter: _scopeFilter,
        )
        .listen(
      (summary) {
        if (!mounted) return;
        setState(() {
          _monthSummary = summary;
          _monthLoading = false;
          _monthError = null;
          _updateHasMore();
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        setState(() {
          _monthLoading = false;
          _monthError = error;
          _monthStack = stackTrace;
        });
      },
    );
  }

  Future<void> _subscribeEvents() async {
    final generation = ++_eventSubscriptionGeneration;
    await _eventSubscription?.cancel();
    final repository = _repository;
    if (repository == null) return;
    if (mounted) {
      setState(() {
        _eventsLoading = true;
        _eventError = null;
        _eventStack = null;
        _legacyMigrationChecking = true;
        _legacyMigrationError = null;
        _liveEvents = const <HeadquarterCalendarEvent>[];
        _pagedEvents = const <HeadquarterCalendarEvent>[];
        _nextCursor = null;
        _hasMore = false;
        _acknowledgedIds = const <String>{};
        _ackCacheKey = '';
      });
    }
    try {
      final ready = _legacyMigrationKnown
          ? _legacyMigrationReady
          : await repository.isLegacyMigrationComplete();
      if (!mounted || generation != _eventSubscriptionGeneration) return;
      if (!ready) {
        setState(() {
          _legacyMigrationChecking = false;
          _legacyMigrationReady = false;
          _legacyMigrationKnown = true;
          _eventsLoading = false;
        });
        return;
      }
      setState(() {
        _legacyMigrationChecking = false;
        _legacyMigrationReady = true;
        _legacyMigrationKnown = true;
      });
    } catch (error, stackTrace) {
      if (!mounted || generation != _eventSubscriptionGeneration) return;
      setState(() {
        _legacyMigrationChecking = false;
        _legacyMigrationReady = false;
        _legacyMigrationKnown = false;
        _legacyMigrationError = error;
        _eventsLoading = false;
        _eventStack = stackTrace;
      });
      return;
    }
    _eventSubscription = repository
        .watchFirstEventsForDate(
          dateKey: _selectedDateKey,
          userId: _configuredUserId,
          scopeFilter: _scopeFilter,
          limit: _pageSize,
        )
        .listen(
      (events) {
        if (!mounted || generation != _eventSubscriptionGeneration) return;
        setState(() {
          _liveEvents = events;
          _eventsLoading = false;
          _eventError = null;
          final modernEvents = events
              .where((event) => event.schemaVersion >= 2 && event.createdAt != null)
              .toList()
            ..sort((a, b) {
              final priority = b.priorityRank.compareTo(a.priorityRank);
              if (priority != 0) return priority;
              final created = (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
              if (created != 0) return created;
              return b.id.compareTo(a.id);
            });
          _nextCursor = modernEvents.isEmpty ? null : _cursorOf(modernEvents.last);
          _updateHasMore();
        });
        unawaited(_loadAcknowledged());
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || generation != _eventSubscriptionGeneration) return;
        setState(() {
          _eventsLoading = false;
          _eventError = error;
          _eventStack = stackTrace;
        });
      },
    );
  }

  HeadquarterCalendarEventCursor _cursorOf(HeadquarterCalendarEvent event) {
    return HeadquarterCalendarEventCursor(
      priorityRank: event.priorityRank,
      createdAtMillis: (event.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).millisecondsSinceEpoch,
      documentId: event.id,
    );
  }

  void _updateHasMore() {
    final total = _monthSummary?.day(_selectedDateKey).count ?? 0;
    _hasMore = _nextCursor != null && total > _events.length;
  }

  Future<void> _loadMore() async {
    final repository = _repository;
    final cursor = _nextCursor;
    if (repository == null || cursor == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await repository.fetchMoreEventsForDate(
        dateKey: _selectedDateKey,
        userId: _configuredUserId,
        scopeFilter: _scopeFilter,
        cursor: cursor,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _pagedEvents = _mergeEvents(_pagedEvents, page.events);
        _nextCursor = page.nextCursor ?? _nextCursor;
        _hasMore = page.hasMore &&
            (_monthSummary?.day(_selectedDateKey).count ?? _events.length) > _events.length;
      });
      await _loadAcknowledged();
    } catch (error, stackTrace) {
      if (!mounted) return;
      await _showFailure(
        title: '이전 일정 조회 실패',
        operation: 'fetchMoreEventsForDate',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{
          'dateKey': _selectedDateKey,
          'scopeFilter': _scopeFilter,
          'query': 'scopeKey whereIn + dateKeys arrayContains + priorityRank/createdAt/documentId order',
        },
      );
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<HeadquarterCalendarEvent> _mergeEvents(
    List<HeadquarterCalendarEvent> left,
    List<HeadquarterCalendarEvent> right,
  ) {
    final map = <String, HeadquarterCalendarEvent>{};
    for (final event in left) map[event.id] = event;
    for (final event in right) map[event.id] = event;
    return map.values.toList(growable: false);
  }

  Future<void> _loadAcknowledged() async {
    final repository = _repository;
    if (repository == null || _configuredUserId.isEmpty) return;
    final ids = _events.map((event) => event.id).toList()..sort();
    final key = '${_configuredUserId}|${ids.join(',')}';
    if (_ackCacheKey == key) return;
    _ackCacheKey = key;
    try {
      final result = await repository.readAcknowledgedEventIds(
        eventIds: ids,
        userId: _configuredUserId,
      );
      if (!mounted || _ackCacheKey != key) return;
      setState(() => _acknowledgedIds = result);
    } catch (_) {
      if (_ackCacheKey == key) _ackCacheKey = '';
    }
  }

  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay = DateTime(day.year, day.month, day.day);
      if (day.year != _visibleMonth.year || day.month != _visibleMonth.month) {
        _visibleMonth = DateTime(day.year, day.month, 1);
      }
    });
    HapticFeedback.selectionClick();
    _subscribeMonth();
    unawaited(_subscribeEvents());
  }

  void _moveMonth(int delta) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1);
    final day = math.min(_selectedDay.day, DateTime(next.year, next.month + 1, 0).day);
    setState(() {
      _visibleMonth = next;
      _selectedDay = DateTime(next.year, next.month, day);
    });
    _subscribeMonth();
    unawaited(_subscribeEvents());
  }

  void _changeScope(String value) {
    if (_scopeFilter == value) return;
    setState(() => _scopeFilter = value);
    _subscribeAll();
  }

  HeadquarterCalendarActor _actor(UserState state) {
    final session = state.session;
    return HeadquarterCalendarActor(
      userId: session?.id ?? '',
      userName: session?.displayName ?? state.name,
      role: state.role,
      division: state.division,
      areaName: state.currentArea,
    );
  }

  Future<List<_StaffChoice>> _loadStaff(UserState state) async {
    final repository = _repository;
    if (repository != null) {
      try {
        final members = await repository.readStaffMembers();
        if (members.isNotEmpty) {
          return members
              .map((member) => _StaffChoice(
                    id: member.id,
                    name: member.name,
                    role: member.position.isNotEmpty ? member.position : member.role,
                    division: member.division,
                    areaName: member.areaName,
                  ))
              .toList(growable: false);
        }
      } catch (_) {}
    }
    return _staff(state);
  }

  List<_StaffChoice> _staff(UserState state) {
    final map = <String, _StaffChoice>{};
    for (final user in state.users) {
      if (!user.isActive || user.id.trim().isEmpty) continue;
      if (!isHeadquarterCalendarStaffScope(
        role: user.role,
        position: user.position ?? '',
        division: user.divisions.join(' '),
      )) continue;
      map[user.id] = _StaffChoice(
        id: user.id,
        name: user.name.trim().isEmpty ? user.id : user.name.trim(),
        role: user.position?.trim().isNotEmpty == true ? user.position!.trim() : user.role.trim(),
        division: user.divisions.isEmpty ? '' : user.divisions.first,
        areaName: user.currentArea ?? (user.areas.isEmpty ? '' : user.areas.first),
      );
    }
    final current = state.session;
    if (current != null && current.id.trim().isNotEmpty) {
      map.putIfAbsent(
        current.id,
        () => _StaffChoice(
          id: current.id,
          name: current.displayName,
          role: state.position.isNotEmpty ? state.position : state.role,
          division: state.division,
          areaName: state.currentArea,
        ),
      );
    }
    final result = map.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  Future<void> _openEditor({HeadquarterCalendarEvent? event}) async {
    final repository = _repository;
    if (repository == null) return;
    final userState = context.read<UserState>();
    final actor = _actor(userState);
    final staff = await _loadStaff(userState);
    final titleController = TextEditingController(text: event?.title ?? '');
    final descriptionController = TextEditingController(text: event?.description ?? '');
    var startDate = event?.startDate ?? _selectedDay;
    var endDate = event?.endDate ?? _selectedDay;
    var scopeKey = event?.isPersonal == true ? 'personal' : 'company';
    var eventType = event?.eventType ?? 'notice';
    var priority = event?.priority ?? 'normal';
    var requiresAck = event?.requiresAck ?? false;
    var recurrence = event?.isRecurring == true ? event!.recurrenceFrequency : 'none';
    var recurrenceInterval = event?.recurrenceInterval ?? 1;
    var recurrenceUntil = event?.recurrenceUntilDateKey.isNotEmpty == true
        ? HeadquarterCalendarEvent.dateFromKey(event!.recurrenceUntilDateKey) ?? startDate
        : DateTime(startDate.year + 1, startDate.month, startDate.day).subtract(const Duration(days: 1));
    var attendeeMode = event?.attendeeMode ?? 'none';
    final selectedAttendees = <String>{...event?.attendeeIds ?? const <String>[]};
    var applyToSeries = event?.isRecurring == true;
    var saving = false;
    String validation = '';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickStart() async {
              final value = await showDatePicker(
                context: context,
                initialDate: startDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2040),
              );
              if (value == null) return;
              setSheetState(() {
                startDate = DateTime(value.year, value.month, value.day);
                if (endDate.isBefore(startDate)) endDate = startDate;
                if (recurrenceUntil.isBefore(startDate)) recurrenceUntil = startDate;
              });
            }

            Future<void> pickEnd() async {
              final value = await showDatePicker(
                context: context,
                initialDate: endDate,
                firstDate: startDate,
                lastDate: startDate.add(const Duration(days: 365)),
              );
              if (value == null) return;
              setSheetState(() => endDate = DateTime(value.year, value.month, value.day));
            }

            Future<void> pickUntil() async {
              final maxDate = DateTime(startDate.year + 1, startDate.month, startDate.day)
                  .subtract(const Duration(days: 1));
              final initial = recurrenceUntil.isAfter(maxDate) ? maxDate : recurrenceUntil;
              final value = await showDatePicker(
                context: context,
                initialDate: initial.isBefore(startDate) ? startDate : initial,
                firstDate: startDate,
                lastDate: maxDate,
              );
              if (value == null) return;
              setSheetState(() => recurrenceUntil = DateTime(value.year, value.month, value.day));
            }

            Future<void> chooseAttendees() async {
              final result = await showDialog<Set<String>>(
                context: context,
                builder: (dialogContext) {
                  final draft = <String>{...selectedAttendees};
                  return StatefulBuilder(
                    builder: (context, setDialogState) {
                      return AlertDialog(
                        title: const Text('참석자 선택'),
                        content: SizedBox(
                          width: 420,
                          height: math.min(520.0, MediaQuery.of(context).size.height * .65),
                          child: ListView.builder(
                            itemCount: staff.length,
                            itemBuilder: (context, index) {
                              final person = staff[index];
                              return CheckboxListTile(
                                value: draft.contains(person.id),
                                title: Text(person.name),
                                subtitle: Text(<String>[person.role, person.division, person.areaName]
                                    .where((value) => value.isNotEmpty)
                                    .join(' · ')),
                                onChanged: (checked) {
                                  setDialogState(() {
                                    if (checked == true) {
                                      draft.add(person.id);
                                    } else {
                                      draft.remove(person.id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('취소'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, draft),
                            child: Text('${draft.length}명 선택'),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
              if (result == null) return;
              setSheetState(() {
                selectedAttendees
                  ..clear()
                  ..addAll(result);
              });
            }

            Future<void> save() async {
              if (saving) return;
              final title = titleController.text.trim();
              if (title.isEmpty) {
                setSheetState(() => validation = '일정 제목을 입력해 주세요.');
                return;
              }
              if (endDate.isBefore(startDate)) {
                setSheetState(() => validation = '종료일은 시작일보다 빠를 수 없습니다.');
                return;
              }
              if (attendeeMode == 'selected' && selectedAttendees.isEmpty) {
                setSheetState(() => validation = '선택 참석자를 한 명 이상 지정해 주세요.');
                return;
              }
              setSheetState(() {
                validation = '';
                saving = true;
              });
              final targetIds = attendeeMode == 'all' ||
                      attendeeMode == 'none' && requiresAck
                  ? staff.map((person) => person.id).toSet()
                  : attendeeMode == 'selected'
                      ? selectedAttendees
                      : <String>{};
              final names = <String, String>{};
              for (final person in staff) {
                if (targetIds.contains(person.id)) names[person.id] = person.name;
              }
              final owner = scopeKey == 'personal' ? actor.userId : '';
              final draft = HeadquarterCalendarEventDraft(
                title: title,
                description: descriptionController.text.trim(),
                startDate: startDate,
                endDate: endDate,
                scopeKey: scopeKey == 'personal' ? 'user:${actor.userId}' : 'company',
                ownerUserId: owner,
                eventType: eventType,
                priority: priority,
                requiresAck: requiresAck,
                recurrenceFrequency: recurrence,
                recurrenceInterval: recurrenceInterval,
                recurrenceUntilDate: recurrenceUntil,
                attendeeMode: attendeeMode,
                attendeeIds: targetIds.toList(growable: false),
                attendeeNames: names,
                targetCountSnapshot: targetIds.length,
              );
              try {
                if (event == null) {
                  await repository.createEvent(draft: draft, actor: actor);
                } else {
                  await repository.updateEvent(
                    eventId: event.id,
                    draft: draft,
                    actor: actor,
                    applyToSeries: applyToSeries,
                  );
                }
                if (!context.mounted) return;
                Navigator.pop(context);
                if (mounted) {
                  setState(() {
                    _visibleMonth = DateTime(startDate.year, startDate.month, 1);
                    _selectedDay = startDate;
                  });
                  _subscribeAll();
                }
              } catch (error, stackTrace) {
                if (!context.mounted) return;
                setSheetState(() => saving = false);
                await _showFailure(
                  title: '본사 일정 저장 실패',
                  operation: event == null ? 'createEvent' : 'updateEvent',
                  error: error,
                  stackTrace: stackTrace,
                  details: <String, Object?>{
                    'eventId': event?.id ?? '',
                    'startDateKey': HeadquarterCalendarEvent.dateKeyOf(startDate),
                    'endDateKey': HeadquarterCalendarEvent.dateKeyOf(endDate),
                    'scopeKey': scopeKey,
                    'recurrence': recurrence,
                  },
                );
              }
            }

            final cs = Theme.of(context).colorScheme;
            final media = MediaQuery.of(context);
            final maxDialogHeight = math.max(
              360.0,
              math.min(
                760.0,
                media.size.height - media.viewInsets.bottom - 48,
              ),
            );
            return Dialog(
              backgroundColor: cs.surface,
              surfaceTintColor: cs.surface,
              elevation: 12,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 720,
                  maxHeight: maxDialogHeight,
                ),
                child: Container(
                  color: cs.surface,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event == null ? '본사 일정 추가' : '본사 일정 수정',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          tooltip: '닫기',
                          onPressed: saving
                              ? null
                              : () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: '제목', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descriptionController,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(labelText: '내용', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _ValueButton(label: '시작일', value: _dateLabel(startDate), onTap: pickStart)),
                        const SizedBox(width: 8),
                        Expanded(child: _ValueButton(label: '종료일', value: _dateLabel(endDate), onTap: pickEnd)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('모든 일정은 종일 일정으로 저장됩니다. ${endDate.difference(startDate).inDays + 1}일',
                        style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: scopeKey,
                            decoration: const InputDecoration(labelText: '일정 범위', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'company', child: Text('본사 공용')),
                              DropdownMenuItem(value: 'personal', child: Text('내 일정')),
                            ],
                            onChanged: (value) => setSheetState(() => scopeKey = value ?? 'company'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: eventType,
                            decoration: const InputDecoration(labelText: '유형', border: OutlineInputBorder()),
                            items: _eventTypes
                                .map((option) => DropdownMenuItem(value: option.value, child: Text(option.label)))
                                .toList(),
                            onChanged: (value) => setSheetState(() => eventType = value ?? 'notice'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: priority,
                      decoration: const InputDecoration(labelText: '중요도', border: OutlineInputBorder()),
                      items: _priorities
                          .map((option) => DropdownMenuItem(value: option.value, child: Text(option.label)))
                          .toList(),
                      onChanged: (value) => setSheetState(() => priority = value ?? 'normal'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: recurrence,
                      decoration: const InputDecoration(labelText: '반복', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('반복 없음')),
                        DropdownMenuItem(value: 'weekly', child: Text('매주 반복')),
                        DropdownMenuItem(value: 'monthly', child: Text('매월 반복')),
                      ],
                      onChanged: event?.isRecurring == true
                          ? null
                          : (value) => setSheetState(() => recurrence = value ?? 'none'),
                    ),
                    if (recurrence != 'none') ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: recurrenceInterval,
                              decoration: const InputDecoration(labelText: '반복 간격', border: OutlineInputBorder()),
                              items: List.generate(4, (index) {
                                final value = index + 1;
                                return DropdownMenuItem(
                                  value: value,
                                  child: Text('$value${recurrence == 'weekly' ? '주' : '개월'}마다'),
                                );
                              }),
                              onChanged: (value) => setSheetState(() => recurrenceInterval = value ?? 1),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: _ValueButton(label: '반복 종료일', value: _dateLabel(recurrenceUntil), onTap: pickUntil)),
                        ],
                      ),
                    ],
                    if (event?.isRecurring == true) ...[
                      const SizedBox(height: 4),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: applyToSeries,
                        title: const Text('이 일정부터 이후 반복 일정에 적용'),
                        onChanged: (value) => setSheetState(() => applyToSeries = value),
                      ),
                    ],
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: requiresAck,
                      title: const Text('확인 필요'),
                      onChanged: (value) => setSheetState(() => requiresAck = value),
                    ),
                    DropdownButtonFormField<String>(
                      value: attendeeMode,
                      decoration: const InputDecoration(labelText: '참석자', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('참석자 관리 안 함')),
                        DropdownMenuItem(value: 'all', child: Text('본사 전체')),
                        DropdownMenuItem(value: 'selected', child: Text('직원 직접 선택')),
                      ],
                      onChanged: (value) => setSheetState(() => attendeeMode = value ?? 'none'),
                    ),
                    if (attendeeMode == 'selected') ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: chooseAttendees,
                        icon: const Icon(Icons.people_alt_rounded),
                        label: Text('참석자 ${selectedAttendees.length}명 선택'),
                      ),
                    ],
                    if (validation.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(validation, style: TextStyle(color: cs.error, fontWeight: FontWeight.w800)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: saving ? null : save,
                      icon: saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_rounded),
                      label: Text(saving ? '저장 중' : '저장'),
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
    titleController.dispose();
    descriptionController.dispose();
  }

  Future<void> _openDetail(HeadquarterCalendarEvent event) async {
    final repository = _repository;
    if (repository == null) return;
    final userState = context.read<UserState>();
    final actor = _actor(userState);
    var acknowledged = _acknowledgedIds.contains(event.id);
    var working = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> acknowledge() async {
              if (working) return;
              setSheetState(() => working = true);
              try {
                await repository.acknowledgeEvent(event: event, actor: actor);
                acknowledged = true;
                if (mounted) {
                  setState(() {
                    _acknowledgedIds = <String>{..._acknowledgedIds, event.id};
                  });
                }
              } catch (error, stackTrace) {
                if (context.mounted) {
                  await _showFailure(
                    title: '일정 확인 처리 실패',
                    operation: 'acknowledgeEvent',
                    error: error,
                    stackTrace: stackTrace,
                    details: <String, Object?>{'eventId': event.id},
                  );
                }
              } finally {
                if (context.mounted) setSheetState(() => working = false);
              }
            }

            Future<void> attendance(String status) async {
              if (working) return;
              setSheetState(() => working = true);
              try {
                await repository.setAttendanceStatus(event: event, actor: actor, status: status);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('참석 상태가 ${_attendanceLabel(status)}로 저장되었습니다.')),
                  );
                }
              } catch (error, stackTrace) {
                if (context.mounted) {
                  await _showFailure(
                    title: '참석 상태 저장 실패',
                    operation: 'setAttendanceStatus',
                    error: error,
                    stackTrace: stackTrace,
                    details: <String, Object?>{'eventId': event.id, 'status': status},
                  );
                }
              } finally {
                if (context.mounted) setSheetState(() => working = false);
              }
            }

            Future<void> delete() async {
              var applyToSeries = false;
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) {
                  return StatefulBuilder(
                    builder: (context, setDialogState) {
                      return AlertDialog(
                        title: const Text('일정 삭제'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('“${event.title}” 일정을 삭제하시겠습니까?'),
                            if (event.isRecurring)
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: applyToSeries,
                                title: const Text('이 일정부터 이후 반복 일정 삭제'),
                                onChanged: (value) => setDialogState(() => applyToSeries = value == true),
                              ),
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
                          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('삭제')),
                        ],
                      );
                    },
                  );
                },
              );
              if (confirmed != true) return;
              try {
                await repository.softDeleteEvent(
                  eventId: event.id,
                  actor: actor,
                  applyToSeries: applyToSeries,
                );
                if (context.mounted) Navigator.pop(context);
              } catch (error, stackTrace) {
                if (context.mounted) {
                  await _showFailure(
                    title: '일정 삭제 실패',
                    operation: 'softDeleteEvent',
                    error: error,
                    stackTrace: stackTrace,
                    details: <String, Object?>{'eventId': event.id, 'applyToSeries': applyToSeries},
                  );
                }
              }
            }

            final cs = Theme.of(context).colorScheme;
            final attendanceTarget = _isAttendanceTarget(
              event,
              actor.userId,
            );
            final media = MediaQuery.of(context);
            final maxDialogHeight = math.max(
              320.0,
              math.min(720.0, media.size.height - 48),
            );
            return Dialog(
              backgroundColor: cs.surface,
              surfaceTintColor: cs.surface,
              elevation: 12,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 640,
                  maxHeight: maxDialogHeight,
                ),
                child: Container(
                  color: cs.surface,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          tooltip: '닫기',
                          onPressed: working
                              ? null
                              : () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _InfoChip(icon: Icons.date_range_rounded, label: _rangeLabel(event)),
                        _InfoChip(icon: _option(_eventTypes, event.eventType).icon, label: _option(_eventTypes, event.eventType).label),
                        _InfoChip(icon: _option(_priorities, event.priority).icon, label: _option(_priorities, event.priority).label),
                        _InfoChip(icon: event.isPersonal ? Icons.person_rounded : Icons.apartment_rounded, label: event.isPersonal ? '내 일정' : '본사 공용'),
                        if (event.isRecurring) _InfoChip(icon: Icons.repeat_rounded, label: _recurrenceLabel(event)),
                      ],
                    ),
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(event.description, style: TextStyle(color: cs.onSurface, height: 1.45)),
                    ],
                    const SizedBox(height: 14),
                    Text(_attendeeSummary(event), style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800)),
                    if (event.requiresAck) ...[
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: acknowledged || working ? null : acknowledge,
                        icon: Icon(acknowledged ? Icons.verified_rounded : Icons.task_alt_rounded),
                        label: Text(acknowledged ? '확인 완료' : '확인 완료 처리'),
                      ),
                    ],
                    if (event.attendeeMode != 'none') ...[
                      const SizedBox(height: 12),
                      Text('참석 여부', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 7),
                      if (attendanceTarget)
                        Wrap(
                          spacing: 7,
                          children: [
                            OutlinedButton(onPressed: working ? null : () => attendance('attending'), child: const Text('참석')),
                            OutlinedButton(onPressed: working ? null : () => attendance('tentative'), child: const Text('미정')),
                            OutlinedButton(onPressed: working ? null : () => attendance('declined'), child: const Text('불참')),
                          ],
                        )
                      else
                        Text(
                          '이 일정의 참석 응답 대상이 아닙니다.',
                          style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                        ),
                    ],
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => _openStats(event, userState),
                      icon: const Icon(Icons.analytics_rounded),
                      label: const Text('확인·참석 현황'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.pop(context);
                              await _openEditor(event: event);
                            },
                            icon: const Icon(Icons.edit_rounded),
                            label: const Text('수정'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: delete,
                            icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                            label: Text('삭제', style: TextStyle(color: cs.error)),
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
  }

  Future<void> _openStats(HeadquarterCalendarEvent event, UserState userState) async {
    final repository = _repository;
    if (repository == null) return;
    final staff = await _loadStaff(userState);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return FutureBuilder<List<dynamic>>(
          future: Future.wait<dynamic>(<Future<dynamic>>[
            repository.readReceipts(eventId: event.id),
            repository.readAttendanceResponses(eventId: event.id),
          ]),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(height: 260, child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError) {
              return SizedBox(
                height: 260,
                child: Center(
                  child: FilledButton(
                    onPressed: () => HeadquarterCalendarStatusDialog.showFailure(
                      context,
                      title: '현황 조회 실패',
                      operation: 'readCalendarStats',
                      error: snapshot.error,
                      stackTrace: snapshot.stackTrace,
                      details: <String, Object?>{'eventId': event.id},
                    ),
                    child: const Text('오류 확인'),
                  ),
                ),
              );
            }
            final values = snapshot.data ?? const <Object>[];
            final receipts = values.isNotEmpty
                ? values[0] as List<HeadquarterCalendarReceipt>
                : const <HeadquarterCalendarReceipt>[];
            final responses = values.length > 1
                ? values[1] as List<HeadquarterCalendarAttendanceResponse>
                : const <HeadquarterCalendarAttendanceResponse>[];
            final usesCurrentStaffSnapshot = event.attendeeIds.isEmpty &&
                (event.attendeeMode == 'all' || event.requiresAck);
            final targetIds = event.attendeeIds.isNotEmpty
                ? event.attendeeIds.toSet()
                : event.attendeeMode == 'all' || event.requiresAck
                    ? staff.map((person) => person.id).toSet()
                    : <String>{};
            final receiptByUser = <String, HeadquarterCalendarReceipt>{};
            for (final receipt in receipts) {
              if (targetIds.contains(receipt.userId)) {
                receiptByUser[receipt.userId] = receipt;
              }
            }
            final responseByUser = <String, HeadquarterCalendarAttendanceResponse>{};
            for (final response in responses) {
              if (targetIds.contains(response.userId)) {
                responseByUser[response.userId] = response;
              }
            }
            final confirmedIds = receiptByUser.keys.toSet();
            final unconfirmed = targetIds.difference(confirmedIds);
            final attending = responseByUser.values.where((item) => item.status == 'attending').length;
            final tentative = responseByUser.values.where((item) => item.status == 'tentative').length;
            final declined = responseByUser.values.where((item) => item.status == 'declined').length;
            final staffById = <String, _StaffChoice>{for (final person in staff) person.id: person};
            final orderedTargetIds = targetIds.toList()
              ..sort((a, b) {
                final left = staffById[a]?.name ?? event.attendeeNames[a] ?? a;
                final right = staffById[b]?.name ?? event.attendeeNames[b] ?? b;
                return left.compareTo(right);
              });
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('확인·참석 현황', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Metric(label: '대상', value: '${targetIds.isEmpty ? event.targetCountSnapshot : targetIds.length}명'),
                        _Metric(label: '확인', value: '${confirmedIds.length}명'),
                        _Metric(label: '미확인', value: '${unconfirmed.length}명'),
                        _Metric(label: '참석', value: '$attending명'),
                        _Metric(label: '미정', value: '$tentative명'),
                        _Metric(label: '불참', value: '$declined명'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (usesCurrentStaffSnapshot) ...[
                      Text(
                        '이 일정은 생성 당시 대상 명단이 저장되지 않아 현재 본사 인원 기준으로 계산됩니다.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (orderedTargetIds.isNotEmpty)
                      ...orderedTargetIds.map((userId) {
                        final person = staffById[userId];
                        final name = person?.name ?? event.attendeeNames[userId] ?? userId;
                        final confirmed = confirmedIds.contains(userId);
                        final attendance = responseByUser[userId]?.status ?? 'invited';
                        final organization = person == null
                            ? ''
                            : <String>[person.role, person.division, person.areaName]
                                .where((value) => value.isNotEmpty)
                                .join(' · ');
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name.substring(0, 1))),
                          title: Text(name),
                          subtitle: Text(<String>[
                            if (organization.isNotEmpty) organization,
                            '${confirmed ? '확인' : '미확인'} · ${_attendanceLabel(attendance)}',
                          ].join('\n')),
                          trailing: Icon(
                            confirmed ? Icons.verified_rounded : Icons.pending_actions_rounded,
                            color: confirmed ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
                          ),
                        );
                      })
                    else
                      const Text('확인 또는 참석 대상이 없습니다.'),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openSearch() async {
    final repository = _repository;
    if (repository == null) return;
    final controller = TextEditingController();
    var scope = _scopeFilter;
    var eventType = 'all';
    var priority = 'all';
    DateTime? fromDate = DateTime(DateTime.now().year - 1, DateTime.now().month, DateTime.now().day);
    DateTime? toDate = DateTime.now();
    var includeDeleted = false;
    var loading = false;
    var loadingMore = false;
    var results = <HeadquarterCalendarEvent>[];
    var hasSearched = false;
    HeadquarterCalendarSearchCursor? cursor;
    var hasMore = false;
    var developerMode = false;
    var migrationWorking = false;
    var migrationText = '';
    Object? failure;
    developerMode = await DevAuth.isDeveloperLoggedIn();
    if (!mounted) return;
    if (!_legacyMigrationReady && !developerMode) {
      controller.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기존 일정 데이터 업그레이드가 완료된 뒤 검색할 수 있습니다.')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            HeadquarterCalendarSearchQuery query() {
              return HeadquarterCalendarSearchQuery(
                keyword: controller.text.trim(),
                userId: _configuredUserId,
                scopeFilter: scope,
                eventType: eventType,
                priority: priority,
                fromDate: fromDate,
                toDate: toDate,
                includeDeleted: includeDeleted,
              );
            }

            Future<void> run({bool more = false}) async {
              if (controller.text.trim().length < 2 || loading || loadingMore) return;
              setSheetState(() {
                if (more) {
                  loadingMore = true;
                } else {
                  loading = true;
                  hasSearched = true;
                  results = <HeadquarterCalendarEvent>[];
                  cursor = null;
                  hasMore = false;
                }
                failure = null;
              });
              try {
                final page = await repository.searchEvents(
                  query: query(),
                  cursor: more ? cursor : null,
                  limit: _pageSize,
                );
                if (!context.mounted) return;
                setSheetState(() {
                  results = more ? _mergeEvents(results, page.events) : page.events;
                  cursor = page.nextCursor;
                  hasMore = page.hasMore;
                });
              } catch (error, stackTrace) {
                if (!context.mounted) return;
                setSheetState(() {
                  failure = error;
                });
                await _showFailure(
                  title: '달력 전체 검색 실패',
                  operation: more ? 'searchEventsNextPage' : 'searchEvents',
                  error: error,
                  stackTrace: stackTrace,
                  details: <String, Object?>{
                    'keyword': controller.text.trim(),
                    'scope': scope,
                    'eventType': eventType,
                    'priority': priority,
                    'query': 'scopeKey whereIn + searchTokens arrayContains + optional isDeleted/eventType/priority/toDate + startDateKey/documentId order',
                  },
                );
              } finally {
                if (context.mounted) {
                  setSheetState(() {
                    loading = false;
                    loadingMore = false;
                  });
                }
              }
            }

            Future<void> pickRange(bool from) async {
              final initial = from ? fromDate ?? DateTime.now() : toDate ?? DateTime.now();
              final value = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(2015),
                lastDate: DateTime(2040),
              );
              if (value == null) return;
              setSheetState(() {
                if (from) {
                  fromDate = value;
                  if (toDate != null && toDate!.isBefore(value)) toDate = value;
                } else {
                  toDate = value;
                  if (fromDate != null && fromDate!.isAfter(value)) fromDate = value;
                }
              });
            }

            Future<void> migrate() async {
              if (migrationWorking) return;
              setSheetState(() => migrationWorking = true);
              try {
                final batch = await repository.migrateLegacyEvents(limit: 50);
                if (!context.mounted) return;
                setSheetState(() {
                  migrationText = batch.completed
                      ? '기존 일정 마이그레이션 완료'
                      : '${batch.scannedCount}개 확인 · ${batch.updatedCount}개 갱신 · 다음 50개 가능';
                });
                if (batch.completed) {
                  _legacyMigrationKnown = false;
                  unawaited(_subscribeEvents());
                }
              } catch (error, stackTrace) {
                if (context.mounted) {
                  await _showFailure(
                    title: '기존 일정 마이그레이션 실패',
                    operation: 'migrateLegacyEvents',
                    error: error,
                    stackTrace: stackTrace,
                    details: const <String, Object?>{'batchSize': 50},
                  );
                }
              } finally {
                if (context.mounted) setSheetState(() => migrationWorking = false);
              }
            }

            final cs = Theme.of(context).colorScheme;
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(context).viewInsets.bottom + 18),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => run(),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search_rounded),
                            labelText: '전체 일정 검색',
                            hintText: '제목, 내용, 작성자, 참석자',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: loading ? null : () => run(), child: const Text('검색')),
                    ],
                  ),
                  const SizedBox(height: 9),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterDropdown(
                          value: scope,
                          label: '범위',
                          items: const <String, String>{'all': '함께', 'company': '본사', 'personal': '개인'},
                          onChanged: (value) => setSheetState(() => scope = value),
                        ),
                        const SizedBox(width: 6),
                        _FilterDropdown(
                          value: eventType,
                          label: '유형',
                          items: <String, String>{'all': '전체', for (final item in _eventTypes) item.value: item.label},
                          onChanged: (value) => setSheetState(() => eventType = value),
                        ),
                        const SizedBox(width: 6),
                        _FilterDropdown(
                          value: priority,
                          label: '중요도',
                          items: <String, String>{'all': '전체', for (final item in _priorities) item.value: item.label},
                          onChanged: (value) => setSheetState(() => priority = value),
                        ),
                        const SizedBox(width: 6),
                        ActionChip(label: Text(fromDate == null ? '시작일' : _dateLabel(fromDate!)), onPressed: () => pickRange(true)),
                        const SizedBox(width: 6),
                        ActionChip(label: Text(toDate == null ? '종료일' : _dateLabel(toDate!)), onPressed: () => pickRange(false)),
                        const SizedBox(width: 6),
                        FilterChip(
                          selected: includeDeleted,
                          label: const Text('삭제 포함'),
                          onSelected: (value) => setSheetState(() => includeDeleted = value),
                        ),
                      ],
                    ),
                  ),
                  if (developerMode) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: migrationWorking ? null : migrate,
                          icon: migrationWorking
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.upgrade_rounded),
                          label: const Text('기존 일정 50개 마이그레이션'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(migrationText, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : failure != null
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('검색하지 못했습니다.', style: TextStyle(color: cs.error, fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 8),
                                    OutlinedButton(
                                      onPressed: loadingMore ? null : () => run(more: cursor != null),
                                      child: const Text('다시 시도'),
                                    ),
                                  ],
                                ),
                              )
                            : results.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          !hasSearched
                                              ? '검색어를 입력하고 검색을 실행하세요.'
                                              : hasMore
                                                  ? '현재 후보에서는 일치하는 일정이 없습니다.'
                                                  : '조건에 맞는 일정이 없습니다.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: cs.onSurfaceVariant),
                                        ),
                                        if (hasSearched && hasMore) ...[
                                          const SizedBox(height: 10),
                                          OutlinedButton(
                                            onPressed: loadingMore ? null : () => run(more: true),
                                            child: Text(loadingMore ? '조회 중' : '다음 후보 20개 검색'),
                                          ),
                                        ],
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: results.length + (hasMore ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index == results.length) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          child: Center(
                                            child: OutlinedButton(
                                              onPressed: loadingMore ? null : () => run(more: true),
                                              child: Text(loadingMore ? '조회 중' : '다음 20개'),
                                            ),
                                          ),
                                        );
                                      }
                                      final event = results[index];
                                      return ListTile(
                                        leading: Icon(_option(_eventTypes, event.eventType).icon),
                                        title: Text(event.title),
                                        subtitle: Text('${_rangeLabel(event)} · ${event.isPersonal ? '내 일정' : '본사'}'),
                                        trailing: const Icon(Icons.chevron_right_rounded),
                                        onTap: () {
                                          Navigator.pop(context);
                                          _openDetail(event);
                                        },
                                      );
                                    },
                                  ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    controller.dispose();
  }

  Future<void> _showFailure({
    required String title,
    required String operation,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    return HeadquarterCalendarStatusDialog.showFailure(
      context,
      title: title,
      operation: operation,
      error: error,
      stackTrace: stackTrace,
      details: details,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final events = _events;
    final dayTotal = _monthSummary?.day(_selectedDateKey).count ?? events.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(.65)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 18, offset: const Offset(0, 7)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(onPressed: () => _moveMonth(-1), icon: const Icon(Icons.chevron_left_rounded)),
              Expanded(
                child: Text(
                  '${_visibleMonth.year}년 ${_visibleMonth.month.toString().padLeft(2, '0')}월',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(onPressed: () => _moveMonth(1), icon: const Icon(Icons.chevron_right_rounded)),
              IconButton(onPressed: _openSearch, icon: const Icon(Icons.manage_search_rounded), tooltip: '일정 검색'),
              IconButton(
                onPressed: _legacyMigrationReady ? () => _openEditor() : null,
                icon: const Icon(Icons.add_circle_rounded),
                tooltip: '일정 추가',
              ),
            ],
          ),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment(value: 'all', label: Text('함께')),
              ButtonSegment(value: 'company', label: Text('본사')),
              ButtonSegment(value: 'personal', label: Text('내 일정')),
            ],
            selected: <String>{_scopeFilter},
            onSelectionChanged: (values) => _changeScope(values.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 12),
          Row(
            children: _weekdays
                .map((day) => Expanded(
                      child: Center(
                        child: Text(day, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w900, fontSize: 12)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 5),
          if (_monthLoading && _monthSummary == null)
            const SizedBox(height: 250, child: Center(child: CircularProgressIndicator()))
          else if (_monthError != null && _monthSummary == null)
            _ErrorBox(
              text: '월간 일정을 불러오지 못했습니다.',
              onRetry: () {
                _subscribeMonth();
                _showFailure(
                  title: '월간 달력 조회 실패',
                  operation: 'watchMonthSummary',
                  error: _monthError,
                  stackTrace: _monthStack,
                  details: <String, Object?>{'monthKey': _monthKey, 'scopeFilter': _scopeFilter},
                );
              },
            )
          else
            _buildCalendarGrid(),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_selectedDay.month}월 ${_selectedDay.day}일 ${_weekdays[_selectedDay.weekday % 7]}요일',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Text('${events.length} / $dayTotal개', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          if (_legacyMigrationChecking)
            const SizedBox(height: 90, child: Center(child: CircularProgressIndicator()))
          else if (!_legacyMigrationReady)
            _MigrationBox(
              hasError: _legacyMigrationError != null,
              onOpenMigration: _openSearch,
              onRetry: () {
                _legacyMigrationKnown = false;
                unawaited(_subscribeEvents());
              },
            )
          else if (_eventsLoading && events.isEmpty)
            const SizedBox(height: 90, child: Center(child: CircularProgressIndicator()))
          else if (_eventError != null && events.isEmpty)
            _ErrorBox(
              text: '선택 날짜 일정을 불러오지 못했습니다.',
              onRetry: () {
                unawaited(_subscribeEvents());
                _showFailure(
                  title: '날짜 일정 조회 실패',
                  operation: 'watchFirstEventsForDate',
                  error: _eventError,
                  stackTrace: _eventStack,
                  details: <String, Object?>{
                    'dateKey': _selectedDateKey,
                    'scopeFilter': _scopeFilter,
                    'query': 'scopeKey whereIn + dateKeys arrayContains + priorityRank/createdAt/documentId order',
                  },
                );
              },
            )
          else if (events.isEmpty)
            _EmptyBox(onAdd: () => _openEditor())
          else ...[
            for (var index = 0; index < events.length; index++)
              _EventTile(
                event: events[index],
                acknowledged: _acknowledgedIds.contains(events[index].id),
                onTap: () => _openDetail(events[index]),
              ),
            if (_hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: _loadingMore ? null : _loadMore,
                  icon: _loadingMore
                      ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(_loadingMore ? '조회 중' : '다음 20개 일정'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final start = first.subtract(Duration(days: first.weekday % 7));
    final days = List<DateTime>.generate(42, (index) => start.add(Duration(days: index)));
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: .88,
      ),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        final key = HeadquarterCalendarEvent.dateKeyOf(day);
        final summary = _monthSummary?.day(key);
        final selected = _sameDay(day, _selectedDay);
        final today = _sameDay(day, DateTime.now());
        final inMonth = day.month == _visibleMonth.month && day.year == _visibleMonth.year;
        return _DayCell(
          day: day.day,
          count: summary?.count ?? 0,
          important: summary?.hasImportantEvents ?? false,
          selected: selected,
          today: today,
          inMonth: inMonth,
          onTap: () => _selectDay(day),
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dateLabel(DateTime date) =>
      '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';

  static String _rangeLabel(HeadquarterCalendarEvent event) {
    if (event.isSingleDay) return '${_dateLabel(event.startDate)} · 종일';
    return '${_dateLabel(event.startDate)} ~ ${_dateLabel(event.endDate)} · ${event.durationDays}일';
  }

  static String _recurrenceLabel(HeadquarterCalendarEvent event) {
    final unit = event.recurrenceFrequency == 'monthly' ? '개월' : '주';
    return '${event.recurrenceInterval}$unit마다 반복';
  }

  static bool _isAttendanceTarget(
    HeadquarterCalendarEvent event,
    String userId,
  ) {
    final cleanUserId = userId.trim();
    if (cleanUserId.isEmpty) return false;
    if (event.attendeeMode == 'all') {
      return event.attendeeIds.isEmpty || event.attendeeIds.contains(cleanUserId);
    }
    if (event.attendeeMode == 'selected') {
      return event.attendeeIds.contains(cleanUserId);
    }
    return false;
  }

  static String _attendeeSummary(HeadquarterCalendarEvent event) {
    switch (event.attendeeMode) {
      case 'all':
        return '참석자: 본사 전체 ${event.targetCountSnapshot}명';
      case 'selected':
        return '참석자: 선택 ${event.attendeeIds.length}명';
      default:
        return '참석자 관리 없음';
    }
  }

  static String _attendanceLabel(String status) {
    switch (status) {
      case 'attending':
        return '참석';
      case 'declined':
        return '불참';
      case 'tentative':
        return '미정';
      default:
        return '미응답';
    }
  }

  static _Option _option(List<_Option> options, String value) {
    return options.firstWhere((option) => option.value == value, orElse: () => options.first);
  }
}

class _Option {
  const _Option(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;
}

class _StaffChoice {
  const _StaffChoice({
    required this.id,
    required this.name,
    required this.role,
    required this.division,
    required this.areaName,
  });
  final String id;
  final String name;
  final String role;
  final String division;
  final String areaName;
}

class _ValueButton extends StatelessWidget {
  const _ValueButton({required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
  });
  final String value;
  final String label;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(12),
      items: items.entries
          .map((entry) => DropdownMenuItem(value: entry.key, child: Text('$label: ${entry.value}')))
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.count,
    required this.important,
    required this.selected,
    required this.today,
    required this.inMonth,
    required this.onTap,
  });
  final int day;
  final int count;
  final bool important;
  final bool selected;
  final bool today;
  final bool inMonth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = selected
        ? cs.onPrimary
        : inMonth
            ? cs.onSurface
            : cs.onSurfaceVariant.withOpacity(.45);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selected ? cs.primary : today ? cs.primaryContainer.withOpacity(.45) : null,
          borderRadius: BorderRadius.circular(12),
          border: today && !selected ? Border.all(color: cs.primary.withOpacity(.5)) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$day', style: TextStyle(color: foreground, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            if (count > 0)
              Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? cs.onPrimary.withOpacity(.2)
                      : important
                          ? cs.errorContainer
                          : cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected
                        ? cs.onPrimary
                        : important
                            ? cs.onErrorContainer
                            : cs.onSecondaryContainer,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              )
            else
              const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.acknowledged, required this.onTap});
  final HeadquarterCalendarEvent event;
  final bool acknowledged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = event.priority == 'urgent'
        ? cs.error
        : event.priority == 'high'
            ? cs.primary
            : cs.secondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Color.alphaBlend(color.withOpacity(.07), cs.surface),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(.2)),
            ),
            child: Row(
              children: [
                Icon(event.isPersonal ? Icons.person_rounded : Icons.apartment_rounded, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(
                        _HeadquarterCalendarCardState._rangeLabel(event),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                if (event.isRecurring) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.repeat_rounded, size: 17)),
                if (event.requiresAck)
                  Icon(acknowledged ? Icons.verified_rounded : Icons.assignment_late_rounded,
                      color: acknowledged ? cs.primary : cs.error, size: 18),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Text('선택한 날짜에 일정이 없습니다.'),
          const SizedBox(height: 6),
          TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('일정 추가')),
        ],
      ),
    );
  }
}

class _MigrationBox extends StatelessWidget {
  const _MigrationBox({
    required this.hasError,
    required this.onOpenMigration,
    required this.onRetry,
  });

  final bool hasError;
  final VoidCallback onOpenMigration;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withOpacity(.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            hasError ? '달력 데이터 상태를 확인하지 못했습니다.' : '기존 일정 데이터 업그레이드가 필요합니다.',
            style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            hasError
                ? '네트워크 상태를 확인한 뒤 다시 시도해 주세요.'
                : '개발자 모드에서 기존 일정을 50개씩 마이그레이션한 뒤 신형 일정 조회와 페이지네이션을 사용할 수 있습니다.',
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: onRetry, child: const Text('상태 다시 확인')),
              FilledButton.tonal(onPressed: onOpenMigration, child: const Text('검색·마이그레이션 열기')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer.withOpacity(.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: cs.error),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w800))),
          TextButton(onPressed: onRetry, child: const Text('재시도')),
        ],
      ),
    );
  }
}
