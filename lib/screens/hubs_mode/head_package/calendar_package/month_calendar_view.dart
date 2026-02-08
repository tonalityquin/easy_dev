import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

import '../../dev_package/debug_package/debug_api_logger.dart';

class MonthCalendarView extends StatefulWidget {
  const MonthCalendarView({
    super.key,
    required this.allEvents,
    required this.progressOf,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleProgress,
    this.onMonthRequested, // 보이는 월 범위를 부모에 요청
  });

  final List<gcal.Event> allEvents;
  final int Function(gcal.Event) progressOf;

  // (읽기 전용 시트에서는 사용 안 함)
  final void Function(BuildContext, gcal.Event) onEdit;
  final void Function(BuildContext, gcal.Event) onDelete;
  final Future<void> Function(BuildContext, gcal.Event, bool) onToggleProgress;

  final Future<void> Function(DateTime monthStart, DateTime monthEnd)? onMonthRequested;

  @override
  State<MonthCalendarView> createState() => _MonthCalendarViewState();
}

class _MonthCalendarViewState extends State<MonthCalendarView> {
  late DateTime _visibleMonth; // 해당 월의 1일
  DateTime? _selectedDay; // 탭 하이라이트

  // ✅ 월 범위 요청 중복 호출 방지
  bool _monthRequestBusy = false;

  // ─────────────────────────────────────────────────────────────
  // ✅ API 디버그 로직: 표준 태그 / 로깅 헬퍼
  // ─────────────────────────────────────────────────────────────
  static const String _tCal = 'calendar';
  static const String _tCalUi = 'calendar/ui';
  static const String _tCalMonth = 'calendar/month';
  static const String _tCalMonthRequest = 'calendar/month/request';
  static const String _tCalSheet = 'calendar/day_sheet';

  Future<void> _logApiError({
    required String tag,
    required String message,
    required Object error,
    Map<String, dynamic>? extra,
    List<String>? tags,
  }) async {
    try {
      await DebugApiLogger().log(
        <String, dynamic>{
          'tag': tag,
          'message': message,
          'error': error.toString(),
          if (extra != null) 'extra': extra,
        },
        level: 'error',
        tags: tags,
      );
    } catch (_) {
      // 로깅 실패는 UI 기능에 영향 없도록 무시
    }
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);

    // 첫 빌드 직후 현재 보이는 달 범위 로드 요청
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyMonthRequested();
    });
  }

  Future<void> _notifyMonthRequested() async {
    final fn = widget.onMonthRequested;
    if (fn == null) return;

    // 중복 호출 방지(버튼 연타, 빠른 월 이동 등)
    if (_monthRequestBusy) return;
    _monthRequestBusy = true;

    final start = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final end = DateTime(start.year, start.month + 1, 1); // 다음 달 1일(Exclusive)

    try {
      await fn(start, end);
    } catch (e) {
      await _logApiError(
        tag: 'MonthCalendarView._notifyMonthRequested',
        message: '월 범위 이벤트 로드(onMonthRequested) 실패',
        error: e,
        extra: <String, dynamic>{
          'monthStart': start.toIso8601String(),
          'monthEndExclusive': end.toIso8601String(),
        },
        tags: const <String>[_tCal, _tCalMonth, _tCalMonthRequest],
      );
    } finally {
      _monthRequestBusy = false;
    }
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  List<DateTime> _daysInGrid(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final weekday = first.weekday % 7; // Sun=0, Mon=1,... (Flutter는 Mon=1~Sun=7)
    final start = first.subtract(Duration(days: weekday)); // 그리드 시작(일요일)
    return List.generate(42, (i) => DateTime(start.year, start.month, start.day + i));
  }

  DateTime? _eventStartLocal(gcal.Event e) {
    final dt = e.start?.dateTime?.toLocal();
    final d = e.start?.date;
    return dt ?? d;
  }

  bool _eventOccursOn(gcal.Event e, DateTime day) {
    // 종일 이벤트: [start.date, end.date) 구간
    if (e.start?.date != null && e.end?.date != null) {
      final s = DateTime(e.start!.date!.year, e.start!.date!.month, e.start!.date!.day);
      final ed = DateTime(e.end!.date!.year, e.end!.date!.month, e.end!.date!.day);
      return !day.isBefore(s) && day.isBefore(ed);
    }

    // 시간 이벤트: 시작~끝 사이 날짜 포함
    final start = e.start?.dateTime?.toLocal();
    final end = e.end?.dateTime?.toLocal();
    if (start != null) {
      final sd = DateTime(start.year, start.month, start.day);
      if (_isSameDay(sd, day)) return true;
      if (end != null) {
        final ed = DateTime(end.year, end.month, end.day);
        return !day.isBefore(sd) && !day.isAfter(ed);
      }
    }
    return false;
  }

  List<gcal.Event> _eventsOnDay(DateTime day) {
    final list = widget.allEvents.where((e) => _eventOccursOn(e, day)).toList();
    list.sort((a, b) {
      final sa = _eventStartLocal(a) ?? DateTime(1900);
      final sb = _eventStartLocal(b) ?? DateTime(1900);
      return sa.compareTo(sb);
    });
    return list;
  }

  Future<void> _openDaySheet(BuildContext context, DateTime day) async {
    final events = _eventsOnDay(day);
    final fmtDay = DateFormat('yyyy-MM-dd (EEE)');
    final fmtTime = DateFormat('HH:mm');
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    try {
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: cs.surface, // ✅ 테마 surface
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (context, controller) {
              final theme = Theme.of(context);
              final cs = theme.colorScheme;

              return Material(
                color: cs.surface,
                surfaceTintColor: Colors.transparent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withOpacity(0.35), // ✅ 핸들도 테마화
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              fmtDay.format(day),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: cs.onSurface),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: cs.outlineVariant.withOpacity(0.6)),
                    Expanded(
                      child: events.isEmpty
                          ? Center(
                        child: Text(
                          '이 날짜에 이벤트가 없습니다.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                          : ListView.separated(
                        controller: controller,
                        itemCount: events.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: cs.outlineVariant.withOpacity(0.6),
                        ),
                        itemBuilder: (context, i) {
                          final e = events[i];
                          final isAllDay = (e.start?.date != null) && (e.start?.dateTime == null);

                          String whenText;
                          if (isAllDay) {
                            whenText = '종일';
                          } else {
                            final st = e.start?.dateTime?.toLocal();
                            final ed = e.end?.dateTime?.toLocal();
                            if (st != null && ed != null) {
                              whenText = '${fmtTime.format(st)} ~ ${fmtTime.format(ed)}';
                            } else if (st != null) {
                              whenText = fmtTime.format(st);
                            } else {
                              whenText = '(시간 미정)';
                            }
                          }

                          final done = widget.progressOf(e) == 100;

                          return ListTile(
                            leading: Icon(
                              done ? Icons.check_circle : Icons.radio_button_unchecked,
                              size: 20,
                              color: done ? cs.primary : cs.onSurfaceVariant,
                            ),
                            title: Text(
                              e.summary ?? '(제목 없음)',
                              style: done
                                  ? theme.textTheme.bodyLarge?.copyWith(
                                decoration: TextDecoration.lineThrough,
                                color: cs.onSurfaceVariant,
                              )
                                  : theme.textTheme.bodyLarge?.copyWith(
                                color: cs.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              whenText,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
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
    } catch (e) {
      await _logApiError(
        tag: 'MonthCalendarView._openDaySheet',
        message: 'Day Sheet 열기 실패',
        error: e,
        extra: <String, dynamic>{
          'day': DateFormat('yyyy-MM-dd').format(day),
          'eventsCount': events.length,
        },
        tags: const <String>[_tCal, _tCalUi, _tCalSheet],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final days = _daysInGrid(_visibleMonth);
    final monthLabel = DateFormat('yyyy년 M월').format(_visibleMonth);
    final isLight = theme.brightness == Brightness.light;

    return Column(
      children: [
        // ==== 월 헤더 ====
        Row(
          children: [
            IconButton(
              tooltip: '이전 달',
              icon: Icon(Icons.chevron_left, color: cs.primary),
              onPressed: () {
                setState(() {
                  _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
                });
                _notifyMonthRequested();
              },
            ),
            Expanded(
              child: Center(
                child: Text(
                  monthLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '다음 달',
              icon: Icon(Icons.chevron_right, color: cs.primary),
              onPressed: () {
                setState(() {
                  _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
                });
                _notifyMonthRequested();
              },
            ),
          ],
        ),
        const SizedBox(height: 4),

        // ==== 요일 헤더 ====
        Row(
          children: const [
            _DowCell('일'),
            _DowCell('월'),
            _DowCell('화'),
            _DowCell('수'),
            _DowCell('목'),
            _DowCell('금'),
            _DowCell('토'),
          ],
        ),
        const SizedBox(height: 4),

        // ==== 월 그리드 ====
        AspectRatio(
          aspectRatio: 7 / 6,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
            ),
            itemCount: days.length,
            itemBuilder: (context, i) {
              final theme = Theme.of(context);
              final cs = theme.colorScheme;

              final d = days[i];
              final inMonth = d.month == _visibleMonth.month;
              final isToday = _isSameDay(d, DateTime.now());
              final isSelected = _selectedDay != null && _isSameDay(d, _selectedDay!);

              // 해당 날짜의 이벤트 및 개수
              final eventsOfDay = _eventsOnDay(d);
              final cnt = eventsOfDay.length;

              final bg = isSelected
                  ? cs.primary.withOpacity(isLight ? .12 : .22)
                  : Colors.transparent;

              final fg = inMonth
                  ? (isSelected ? cs.primary : cs.onSurface)
                  : cs.onSurfaceVariant.withOpacity(0.45);

              return InkWell(
                onTap: () {
                  setState(() => _selectedDay = d);
                  _openDaySheet(context, d);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? cs.primary.withOpacity(0.35) : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // 날짜 + 오늘 점 (좌측 상단)
                      Positioned(
                        top: 4,
                        left: 6,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${d.day}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: fg,
                              ),
                            ),
                            if (isToday)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // 진행도에 따른 dot 표시 (우측 하단)
                      if (cnt > 0)
                        Positioned(
                          right: 6,
                          bottom: 4,
                          child: Row(
                            children: [
                              ...eventsOfDay.take(3).map((e) {
                                final p = widget.progressOf(e);
                                // ✅ 완료/미완료 도트도 하드코딩 제거 → 테마 기반
                                final color = (p == 100) ? cs.primary : cs.secondary;
                                return Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: color,
                                    ),
                                  ),
                                );
                              }),
                              if (cnt > 3)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(
                                    '+${cnt - 3}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      height: 1.0,
                                      color: cs.onSurfaceVariant.withOpacity(0.7),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DowCell extends StatelessWidget {
  const _DowCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isSun = label == '일';
    final isSat = label == '토';

    // ✅ 주말 컬러도 하드코딩 제거: Sunday=error, Saturday=primary(혹은 secondary로 바꿔도 됨)
    final color = isSun
        ? cs.error
        : (isSat ? cs.primary : cs.onSurfaceVariant.withOpacity(.8));

    return Expanded(
      child: Center(
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: color,
          ),
        ),
      ),
    );
  }
}
