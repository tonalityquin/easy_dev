import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';

import '../../account/applications/user_state.dart';
import '../domain/models/headquarter_calendar_event.dart';
import '../domain/models/headquarter_calendar_event_page.dart';
import '../domain/models/headquarter_calendar_month_summary.dart';
import '../domain/models/headquarter_calendar_search.dart';
import '../domain/repositories/headquarter_calendar_repository.dart';
import 'headquarter_calendar_status_dialog.dart';

class HeadquarterCalendarCard extends StatefulWidget {
  const HeadquarterCalendarCard({
    super.key,
    this.usePromptUi = false,
  });

  final bool usePromptUi;

  @override
  State<HeadquarterCalendarCard> createState() =>
      _HeadquarterCalendarCardState();
}

class _HeadquarterCalendarCardState extends State<HeadquarterCalendarCard> {
  static const int _pageSize = 20;
  static const List<String> _weekdays = <String>[
    '일',
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
  ];
  static const List<_Option> _eventTypes = <_Option>[
    _Option('notice', '공지', Icons.campaign_rounded),
    _Option('field_support', '현장 지원', Icons.support_agent_rounded),
    _Option('annual_leave', '연차', Icons.event_available_rounded),
    _Option('absence', '결근', Icons.person_off_rounded),
    _Option('new_hire', '신규', Icons.person_add_alt_1_rounded),
    _Option('document', '서류', Icons.description_rounded),
    _Option('meeting', '회의', Icons.groups_rounded),
    _Option('end', '종료', Icons.task_alt_rounded),
    _Option('resignation', '퇴사', Icons.logout_rounded),
    _Option('vacation', '휴가', Icons.beach_access_rounded),
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
  StreamSubscription<HeadquarterCalendarMonthSummary>? _monthSubscription;
  StreamSubscription<List<HeadquarterCalendarEvent>>? _eventSubscription;
  HeadquarterCalendarMonthSummary? _monthSummary;
  List<HeadquarterCalendarEvent> _liveEvents =
      const <HeadquarterCalendarEvent>[];
  List<HeadquarterCalendarEvent> _pagedEvents =
      const <HeadquarterCalendarEvent>[];
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

  String get _monthKey =>
      HeadquarterCalendarEvent.monthKeyOf(_visibleMonth);

  String get _selectedDateKey =>
      HeadquarterCalendarEvent.dateKeyOf(_selectedDay);

  List<HeadquarterCalendarEvent> get _events {
    final map = <String, HeadquarterCalendarEvent>{};
    for (final event in _pagedEvents) {
      map[event.id] = event;
    }
    for (final event in _liveEvents) {
      map[event.id] = event;
    }
    final result = map.values.toList()..sort(_compareEvents);
    return result;
  }

  int _compareEvents(
    HeadquarterCalendarEvent left,
    HeadquarterCalendarEvent right,
  ) {
    final priority = right.priorityRank.compareTo(left.priorityRank);
    if (priority != 0) return priority;
    final leftCreated =
        left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final rightCreated =
        right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final created = rightCreated.compareTo(leftCreated);
    if (created != 0) return created;
    return right.id.compareTo(left.id);
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
        .watchMonthSummary(monthKey: _monthKey)
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
        _liveEvents = const <HeadquarterCalendarEvent>[];
        _pagedEvents = const <HeadquarterCalendarEvent>[];
        _nextCursor = null;
        _hasMore = false;
        _acknowledgedIds = const <String>{};
        _ackCacheKey = '';
      });
    }
    _eventSubscription = repository
        .watchFirstEventsForDate(
          dateKey: _selectedDateKey,
          limit: _pageSize,
        )
        .listen(
      (events) {
        if (!mounted || generation != _eventSubscriptionGeneration) return;
        final orderedEvents = events.toList()..sort(_compareEvents);
        setState(() {
          _liveEvents = events;
          _eventsLoading = false;
          _eventError = null;
          _nextCursor = orderedEvents.isEmpty
              ? null
              : _cursorOf(orderedEvents.last);
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

  HeadquarterCalendarEventCursor _cursorOf(
    HeadquarterCalendarEvent event,
  ) {
    return HeadquarterCalendarEventCursor(
      priorityRank: event.priorityRank,
      createdAtMillis:
          (event.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .millisecondsSinceEpoch,
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
    if (repository == null || cursor == null || _loadingMore || !_hasMore) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final page = await repository.fetchMoreEventsForDate(
        dateKey: _selectedDateKey,
        cursor: cursor,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _pagedEvents = _mergeEvents(_pagedEvents, page.events);
        _nextCursor = page.nextCursor ?? _nextCursor;
        _hasMore = page.hasMore &&
            (_monthSummary?.day(_selectedDateKey).count ?? _events.length) >
                _events.length;
      });
      await _loadAcknowledged();
    } catch (error, stackTrace) {
      if (!mounted) return;
      await _showFailure(
        title: '이전 일정 조회 실패',
        operation: 'fetchMoreEventsForDate',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{'dateKey': _selectedDateKey},
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
    for (final event in left) {
      map[event.id] = event;
    }
    for (final event in right) {
      map[event.id] = event;
    }
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
      if (day.year != _visibleMonth.year ||
          day.month != _visibleMonth.month) {
        _visibleMonth = DateTime(day.year, day.month, 1);
      }
    });
    HapticFeedback.selectionClick();
    _subscribeMonth();
    unawaited(_subscribeEvents());
  }

  void _moveMonth(int delta) {
    final next = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + delta,
      1,
    );
    final day = math.min(
      _selectedDay.day,
      DateTime(next.year, next.month + 1, 0).day,
    );
    setState(() {
      _visibleMonth = next;
      _selectedDay = DateTime(next.year, next.month, day);
    });
    _subscribeMonth();
    unawaited(_subscribeEvents());
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

  Future<T?> _showCalendarDialog<T>({
    BuildContext? anchorContext,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    final targetContext = anchorContext ?? context;
    if (widget.usePromptUi) {
      return showPromptOverlayDialog<T>(
        context: targetContext,
        barrierDismissible: barrierDismissible,
        builder: builder,
      );
    }
    return showDialog<T>(
      context: targetContext,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  }

  Future<T?> _showCalendarBottomSheet<T>({
    BuildContext? anchorContext,
    required WidgetBuilder builder,
  }) {
    final targetContext = anchorContext ?? context;
    if (widget.usePromptUi) {
      return showPromptOverlayBottomSheet<T>(
        context: targetContext,
        isScrollControlled: true,
        useSafeArea: true,
        builder: builder,
      );
    }
    return showModalBottomSheet<T>(
      context: targetContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: builder,
    );
  }

  Future<DateTime?> _showCalendarDatePicker({
    required BuildContext anchorContext,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    if (widget.usePromptUi) {
      return showPromptDatePicker(
        context: anchorContext,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
      );
    }
    return showDatePicker(
      context: anchorContext,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }

  Future<void> _openEditor({HeadquarterCalendarEvent? event}) async {
    final repository = _repository;
    if (repository == null) return;
    final userState = context.read<UserState>();
    final actor = _actor(userState);
    final titleController = TextEditingController(text: event?.title ?? '');
    final descriptionController =
        TextEditingController(text: event?.description ?? '');
    var startDate = event?.startDate ?? _selectedDay;
    var endDate = event?.endDate ?? _selectedDay;
    var eventType = _normalizedEventType(event?.eventType ?? 'notice');
    var priority = event?.priority ?? 'normal';
    var requiresAck = event?.requiresAck ?? false;
    var recurrence =
        event?.isRecurring == true ? event!.recurrenceFrequency : 'none';
    var recurrenceInterval = event?.recurrenceInterval ?? 1;
    var recurrenceUntil = event?.recurrenceUntilDateKey.isNotEmpty == true
        ? HeadquarterCalendarEvent.dateFromKey(
                event!.recurrenceUntilDateKey) ??
            startDate
        : DateTime(startDate.year + 1, startDate.month, startDate.day)
            .subtract(const Duration(days: 1));
    var applyToSeries = event?.isRecurring == true;
    var saving = false;
    String validation = '';

    await _showCalendarDialog<void>(
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickStart() async {
              final value = await _showCalendarDatePicker(
                anchorContext: context,
                initialDate: startDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2040),
              );
              if (value == null) return;
              setDialogState(() {
                startDate = DateTime(value.year, value.month, value.day);
                if (endDate.isBefore(startDate)) endDate = startDate;
                if (recurrenceUntil.isBefore(startDate)) {
                  recurrenceUntil = startDate;
                }
              });
            }

            Future<void> pickEnd() async {
              final value = await _showCalendarDatePicker(
                anchorContext: context,
                initialDate: endDate,
                firstDate: startDate,
                lastDate: startDate.add(const Duration(days: 365)),
              );
              if (value == null) return;
              setDialogState(() {
                endDate = DateTime(value.year, value.month, value.day);
              });
            }

            Future<void> pickUntil() async {
              final maxDate = DateTime(
                startDate.year + 1,
                startDate.month,
                startDate.day,
              ).subtract(const Duration(days: 1));
              final initial = recurrenceUntil.isAfter(maxDate)
                  ? maxDate
                  : recurrenceUntil;
              final value = await _showCalendarDatePicker(
                anchorContext: context,
                initialDate: initial.isBefore(startDate)
                    ? startDate
                    : initial,
                firstDate: startDate,
                lastDate: maxDate,
              );
              if (value == null) return;
              setDialogState(() {
                recurrenceUntil =
                    DateTime(value.year, value.month, value.day);
              });
            }

            Future<void> save() async {
              if (saving) return;
              final title = titleController.text.trim();
              if (title.isEmpty) {
                setDialogState(() {
                  validation = '일정 제목을 입력해 주세요.';
                });
                return;
              }
              if (endDate.isBefore(startDate)) {
                setDialogState(() {
                  validation = '종료일은 시작일보다 빠를 수 없습니다.';
                });
                return;
              }
              setDialogState(() {
                validation = '';
                saving = true;
              });
              final draft = HeadquarterCalendarEventDraft(
                title: title,
                description: descriptionController.text.trim(),
                startDate: startDate,
                endDate: endDate,
                eventType: eventType,
                priority: priority,
                requiresAck: requiresAck,
                recurrenceFrequency: recurrence,
                recurrenceInterval: recurrenceInterval,
                recurrenceUntilDate: recurrenceUntil,
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
                    _visibleMonth =
                        DateTime(startDate.year, startDate.month, 1);
                    _selectedDay = startDate;
                  });
                  _subscribeAll();
                }
              } catch (error, stackTrace) {
                if (!context.mounted) return;
                setDialogState(() => saving = false);
                await _showFailure(
                  title: '본사 일정 저장 실패',
                  operation:
                      event == null ? 'createEvent' : 'updateEvent',
                  error: error,
                  stackTrace: stackTrace,
                  details: <String, Object?>{
                    'eventId': event?.id ?? '',
                    'startDateKey':
                        HeadquarterCalendarEvent.dateKeyOf(startDate),
                    'endDateKey':
                        HeadquarterCalendarEvent.dateKeyOf(endDate),
                    'eventType': eventType,
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
                                event == null
                                    ? '본사 일정 추가'
                                    : '본사 일정 수정',
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
                        const SizedBox(height: 10),
                        TextField(
                          controller: titleController,
                          maxLength: 80,
                          decoration: const InputDecoration(
                            labelText: '제목',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: descriptionController,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: 1000,
                          decoration: const InputDecoration(
                            labelText: '내용',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _ValueButton(
                                label: '시작일',
                                value: _dateLabel(startDate),
                                onTap: pickStart,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _ValueButton(
                                label: '종료일',
                                value: _dateLabel(endDate),
                                onTap: pickEnd,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '모든 일정은 종일 일정으로 저장됩니다.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: eventType,
                          decoration: const InputDecoration(
                            labelText: '유형',
                            border: OutlineInputBorder(),
                          ),
                          items: _eventTypes
                              .map(
                                (option) => DropdownMenuItem<String>(
                                  value: option.value,
                                  child: Text(option.label),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            setDialogState(() {
                              eventType = value ?? 'notice';
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: priority,
                          decoration: const InputDecoration(
                            labelText: '중요도',
                            border: OutlineInputBorder(),
                          ),
                          items: _priorities
                              .map(
                                (option) => DropdownMenuItem<String>(
                                  value: option.value,
                                  child: Text(option.label),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            setDialogState(() {
                              priority = value ?? 'normal';
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: recurrence,
                          decoration: const InputDecoration(
                            labelText: '반복',
                            border: OutlineInputBorder(),
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem<String>(
                              value: 'none',
                              child: Text('반복 없음'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'weekly',
                              child: Text('매주 반복'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'monthly',
                              child: Text('매월 반복'),
                            ),
                          ],
                          onChanged: event?.isRecurring == true
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    recurrence = value ?? 'none';
                                  });
                                },
                        ),
                        if (recurrence != 'none') ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: recurrenceInterval,
                                  decoration: const InputDecoration(
                                    labelText: '반복 간격',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: List<DropdownMenuItem<int>>.generate(
                                    4,
                                    (index) {
                                      final value = index + 1;
                                      return DropdownMenuItem<int>(
                                        value: value,
                                        child: Text(
                                          '$value${recurrence == 'weekly' ? '주' : '개월'}마다',
                                        ),
                                      );
                                    },
                                  ),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      recurrenceInterval = value ?? 1;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _ValueButton(
                                  label: '반복 종료일',
                                  value: _dateLabel(recurrenceUntil),
                                  onTap: pickUntil,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (event?.isRecurring == true) ...[
                          const SizedBox(height: 4),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: applyToSeries,
                            title: const Text(
                              '이 일정부터 이후 반복 일정에 적용',
                            ),
                            onChanged: (value) {
                              setDialogState(() => applyToSeries = value);
                            },
                          ),
                        ],
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: requiresAck,
                          title: const Text('확인 필요'),
                          onChanged: (value) {
                            setDialogState(() => requiresAck = value);
                          },
                        ),
                        if (validation.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            validation,
                            style: TextStyle(
                              color: cs.error,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: saving ? null : save,
                          icon: saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
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
    await _showCalendarDialog<void>(
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> acknowledge() async {
              if (working) return;
              setDialogState(() => working = true);
              try {
                await repository.acknowledgeEvent(
                  event: event,
                  actor: actor,
                );
                acknowledged = true;
                if (mounted) {
                  setState(() {
                    _acknowledgedIds = <String>{
                      ..._acknowledgedIds,
                      event.id,
                    };
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
                if (context.mounted) {
                  setDialogState(() => working = false);
                }
              }
            }

            Future<void> delete() async {
              var applyToSeries = false;
              final confirmed = await _showCalendarDialog<bool>(
                anchorContext: context,
                builder: (confirmContext) {
                  return StatefulBuilder(
                    builder: (context, setConfirmState) {
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
                                title: const Text(
                                  '이 일정부터 이후 반복 일정 삭제',
                                ),
                                onChanged: (value) {
                                  setConfirmState(() {
                                    applyToSeries = value == true;
                                  });
                                },
                              ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(confirmContext, false),
                            child: const Text('취소'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.pop(confirmContext, true),
                            child: const Text('삭제'),
                          ),
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
                    details: <String, Object?>{
                      'eventId': event.id,
                      'applyToSeries': applyToSeries,
                    },
                  );
                }
              }
            }

            final cs = Theme.of(context).colorScheme;
            final media = MediaQuery.of(context);
            final maxDialogHeight = math.max(
              320.0,
              math.min(720.0, media.size.height - 48),
            );
            final type = _option(_eventTypes, event.eventType);
            final priority = _option(_priorities, event.priority);
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
                            _InfoChip(
                              icon: Icons.date_range_rounded,
                              label: _rangeLabel(event),
                            ),
                            _InfoChip(icon: type.icon, label: type.label),
                            _InfoChip(
                              icon: priority.icon,
                              label: priority.label,
                            ),
                            const _InfoChip(
                              icon: Icons.apartment_rounded,
                              label: '본사 일정',
                            ),
                            if (event.isRecurring)
                              _InfoChip(
                                icon: Icons.repeat_rounded,
                                label: _recurrenceLabel(event),
                              ),
                          ],
                        ),
                        if (event.description.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(
                            event.description,
                            style: TextStyle(
                              color: cs.onSurface,
                              height: 1.45,
                            ),
                          ),
                        ],
                        if (event.requiresAck) ...[
                          const SizedBox(height: 14),
                          FilledButton.tonalIcon(
                            onPressed:
                                acknowledged || working ? null : acknowledge,
                            icon: Icon(
                              acknowledged
                                  ? Icons.verified_rounded
                                  : Icons.task_alt_rounded,
                            ),
                            label: Text(
                              acknowledged ? '확인 완료' : '확인 완료 처리',
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
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
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: cs.error,
                                ),
                                label: Text(
                                  '삭제',
                                  style: TextStyle(color: cs.error),
                                ),
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

  Future<void> _openSearch() async {
    final repository = _repository;
    if (repository == null) return;
    final controller = TextEditingController();
    var eventType = 'all';
    var priority = 'all';
    DateTime? fromDate = DateTime(
      DateTime.now().year - 1,
      DateTime.now().month,
      DateTime.now().day,
    );
    DateTime? toDate = DateTime.now();
    var includeDeleted = false;
    var loading = false;
    var loadingMore = false;
    var results = <HeadquarterCalendarEvent>[];
    var hasSearched = false;
    HeadquarterCalendarSearchCursor? cursor;
    var hasMore = false;
    Object? failure;

    await _showCalendarBottomSheet<void>(
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            HeadquarterCalendarSearchQuery query() {
              return HeadquarterCalendarSearchQuery(
                keyword: controller.text.trim(),
                eventType: eventType,
                priority: priority,
                fromDate: fromDate,
                toDate: toDate,
                includeDeleted: includeDeleted,
              );
            }

            Future<void> run({bool more = false}) async {
              if (controller.text.trim().length < 2 ||
                  loading ||
                  loadingMore) {
                return;
              }
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
                  results = more
                      ? _mergeEvents(results, page.events)
                      : page.events;
                  cursor = page.nextCursor;
                  hasMore = page.hasMore;
                });
              } catch (error, stackTrace) {
                if (!context.mounted) return;
                setSheetState(() => failure = error);
                await _showFailure(
                  title: '달력 전체 검색 실패',
                  operation:
                      more ? 'searchEventsNextPage' : 'searchEvents',
                  error: error,
                  stackTrace: stackTrace,
                  details: <String, Object?>{
                    'keyword': controller.text.trim(),
                    'eventType': eventType,
                    'priority': priority,
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
              final initial = from
                  ? fromDate ?? DateTime.now()
                  : toDate ?? DateTime.now();
              final value = await _showCalendarDatePicker(
                anchorContext: context,
                initialDate: initial,
                firstDate: DateTime(2015),
                lastDate: DateTime(2040),
              );
              if (value == null) return;
              setSheetState(() {
                if (from) {
                  fromDate = value;
                  if (toDate != null && toDate!.isBefore(value)) {
                    toDate = value;
                  }
                } else {
                  toDate = value;
                  if (fromDate != null && fromDate!.isAfter(value)) {
                    fromDate = value;
                  }
                }
              });
            }

            final cs = Theme.of(context).colorScheme;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                MediaQuery.of(context).viewInsets.bottom + 18,
              ),
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
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: loading ? null : () => run(),
                        child: const Text('검색'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterDropdown(
                          value: eventType,
                          label: '유형',
                          items: <String, String>{
                            'all': '전체',
                            for (final item in _eventTypes)
                              item.value: item.label,
                          },
                          onChanged: (value) {
                            setSheetState(() => eventType = value);
                          },
                        ),
                        const SizedBox(width: 6),
                        _FilterDropdown(
                          value: priority,
                          label: '중요도',
                          items: <String, String>{
                            'all': '전체',
                            for (final item in _priorities)
                              item.value: item.label,
                          },
                          onChanged: (value) {
                            setSheetState(() => priority = value);
                          },
                        ),
                        const SizedBox(width: 6),
                        ActionChip(
                          label: Text(
                            fromDate == null
                                ? '시작일'
                                : _dateLabel(fromDate!),
                          ),
                          onPressed: () => pickRange(true),
                        ),
                        const SizedBox(width: 6),
                        ActionChip(
                          label: Text(
                            toDate == null
                                ? '종료일'
                                : _dateLabel(toDate!),
                          ),
                          onPressed: () => pickRange(false),
                        ),
                        const SizedBox(width: 6),
                        FilterChip(
                          selected: includeDeleted,
                          label: const Text('삭제 포함'),
                          onSelected: (value) {
                            setSheetState(() => includeDeleted = value);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : failure != null
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '검색하지 못했습니다.',
                                      style: TextStyle(
                                        color: cs.error,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    OutlinedButton(
                                      onPressed: loadingMore
                                          ? null
                                          : () => run(
                                                more: cursor != null,
                                              ),
                                      child: const Text('다시 시도'),
                                    ),
                                  ],
                                ),
                              )
                            : results.isEmpty
                                ? Center(
                                    child: Text(
                                      hasSearched
                                          ? '조건에 맞는 일정이 없습니다.'
                                          : '검색어를 입력하고 검색을 실행하세요.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount:
                                        results.length + (hasMore ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index == results.length) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          child: Center(
                                            child: OutlinedButton(
                                              onPressed: loadingMore
                                                  ? null
                                                  : () => run(more: true),
                                              child: Text(
                                                loadingMore
                                                    ? '조회 중'
                                                    : '다음 20개',
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                      final event = results[index];
                                      final type = _option(
                                        _eventTypes,
                                        event.eventType,
                                      );
                                      return ListTile(
                                        leading: Icon(type.icon),
                                        title: Text(event.title),
                                        subtitle: Text(
                                          '${_rangeLabel(event)} · ${type.label}',
                                        ),
                                        trailing: const Icon(
                                          Icons.chevron_right_rounded,
                                        ),
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
      usePromptUi: widget.usePromptUi,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = PromptUiTheme.of(context);
    final events = _events;
    final dayTotal =
        _monthSummary?.day(_selectedDateKey).count ?? events.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(.65)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => _moveMonth(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '${_visibleMonth.year}년 ${_visibleMonth.month.toString().padLeft(2, '0')}월',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: () => _moveMonth(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              IconButton(
                onPressed: _openSearch,
                icon: const Icon(Icons.manage_search_rounded),
                tooltip: '일정 검색',
              ),
              IconButton(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add_circle_rounded),
                tooltip: '일정 추가',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: _weekdays
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 5),
          if (_monthLoading && _monthSummary == null)
            const SizedBox(
              height: 250,
              child: Center(child: CircularProgressIndicator()),
            )
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
                  details: <String, Object?>{'monthKey': _monthKey},
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
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '${events.length} / $dayTotal개',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_eventsLoading && events.isEmpty)
            const SizedBox(
              height: 90,
              child: Center(child: CircularProgressIndicator()),
            )
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
                  },
                );
              },
            )
          else if (events.isEmpty)
            _EmptyBox(onAdd: () => _openEditor())
          else ...[
            for (final event in events)
              _EventTile(
                event: event,
                acknowledged: _acknowledgedIds.contains(event.id),
                type: _option(_eventTypes, event.eventType),
                onTap: () => _openDetail(event),
              ),
            if (_hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: _loadingMore ? null : _loadMore,
                  icon: _loadingMore
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(
                    _loadingMore ? '조회 중' : '다음 20개 일정',
                  ),
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
    final days = List<DateTime>.generate(
      42,
      (index) => start.add(Duration(days: index)),
    );
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
        final inMonth = day.month == _visibleMonth.month &&
            day.year == _visibleMonth.year;
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

  bool _sameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  static String _dateLabel(DateTime date) {
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  }

  static String _rangeLabel(HeadquarterCalendarEvent event) {
    if (event.isSingleDay) {
      return '${_dateLabel(event.startDate)} · 종일';
    }
    return '${_dateLabel(event.startDate)} ~ ${_dateLabel(event.endDate)} · ${event.durationDays}일';
  }

  static String _recurrenceLabel(HeadquarterCalendarEvent event) {
    final unit = event.recurrenceFrequency == 'monthly' ? '개월' : '주';
    return '${event.recurrenceInterval}$unit마다 반복';
  }

  static String _normalizedEventType(String value) {
    return _eventTypes.any((option) => option.value == value)
        ? value
        : 'notice';
  }

  static _Option _option(List<_Option> options, String value) {
    return options.firstWhere(
      (option) => option.value == value,
      orElse: () => options.first,
    );
  }
}

class _Option {
  const _Option(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;
}

class _ValueButton extends StatelessWidget {
  const _ValueButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

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
            Text(
              label,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
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
        color: cs.surfaceContainerHighest.withOpacity(.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
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
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        borderRadius: BorderRadius.circular(14),
        items: items.entries
            .map(
              (entry) => DropdownMenuItem<String>(
                value: entry.key,
                child: Text('${label}: ${entry.value}'),
              ),
            )
            .toList(growable: false),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
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
    final tokens = PromptUiTheme.of(context);
    final foreground = selected
        ? cs.onPrimary
        : inMonth
            ? cs.onSurface
            : cs.onSurfaceVariant.withOpacity(.45);
    final background = selected
        ? cs.primary
        : today
            ? cs.primaryContainer.withOpacity(.45)
            : tokens.transparent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: today && !selected
              ? Border.all(color: cs.primary.withOpacity(.45))
              : null,
        ),
        child: Column(
          children: [
            Text(
              '$day',
              style: TextStyle(
                color: foreground,
                fontWeight: selected || today
                    ? FontWeight.w900
                    : FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            if (count > 0)
              Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: selected
                      ? cs.onPrimary.withOpacity(.2)
                      : important
                          ? cs.errorContainer
                          : cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: TextStyle(
                    color: selected
                        ? cs.onPrimary
                        : important
                            ? cs.onErrorContainer
                            : cs.onSecondaryContainer,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              )
            else
              const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.acknowledged,
    required this.type,
    required this.onTap,
  });

  final HeadquarterCalendarEvent event;
  final bool acknowledged;
  final _Option type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = PromptUiTheme.of(context);
    final color = event.priority == 'urgent'
        ? cs.error
        : event.priority == 'high'
            ? cs.primary
            : cs.secondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: tokens.transparent,
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
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withOpacity(.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(type.icon, color: color, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_HeadquarterCalendarCardState._rangeLabel(event)} · ${type.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (event.isRecurring)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.repeat_rounded, size: 17),
                  ),
                if (event.requiresAck)
                  Icon(
                    acknowledged
                        ? Icons.verified_rounded
                        : Icons.assignment_late_rounded,
                    color: acknowledged ? cs.primary : cs.error,
                    size: 18,
                  ),
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
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Text('선택한 날짜에 일정이 없습니다.'),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('일정 추가'),
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
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: cs.onErrorContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('재시도')),
        ],
      ),
    );
  }
}
