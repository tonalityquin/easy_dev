import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

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
  final void Function(BuildContext, gcal.Event) onEdit;   // (읽기 전용 시트에서는 사용 안 함)
  final void Function(BuildContext, gcal.Event) onDelete; // (읽기 전용 시트에서는 사용 안 함)
  final Future<void> Function(BuildContext, gcal.Event, bool) onToggleProgress; // (읽기 전용 시트에서는 사용 안 함)
  final Future<void> Function(DateTime monthStart, DateTime monthEnd)? onMonthRequested;

  @override
  State<MonthCalendarView> createState() => _MonthCalendarViewState();
}

class _MonthCalendarViewState extends State<MonthCalendarView> {
  late DateTime _visibleMonth; // 해당 월의 1일
  DateTime? _selectedDay; // 탭 하이라이트

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);

    // 첫 빌드 직후 현재 보이는 달 범위 로드 요청
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyMonthRequested());
  }

  void _notifyMonthRequested() {
    if (widget.onMonthRequested == null) return;
    final start = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final end = DateTime(start.year, start.month + 1, 1); // 다음 달 1일(Exclusive)
    widget.onMonthRequested!(start, end);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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

  // ❌ 미사용 메서드 제거: _eventCountOnDay

  Future<void> _openDaySheet(BuildContext context, DateTime day) async {
    final events = _eventsOnDay(day);
    final fmtDay = DateFormat('yyyy-MM-dd (EEE)');
    final fmtTime = DateFormat('HH:mm');

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, controller) {
            return Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12, borderRadius: BorderRadius.circular(2),
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
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: events.isEmpty
                        ? const Center(child: Text('이 날짜에 이벤트가 없습니다.'))
                        : ListView.separated(
                      controller: controller,
                      itemCount: events.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
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
                          leading: done
                              ? const Icon(Icons.check_circle, size: 20)
                              : const Icon(Icons.radio_button_unchecked, size: 20),
                          title: Text(
                            e.summary ?? '(제목 없음)',
                            style: done
                                ? const TextStyle(decoration: TextDecoration.lineThrough)
                                : null,
                          ),
                          subtitle: Text(whenText),
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
  }

  @override
  Widget build(BuildContext context) {
    final days = _daysInGrid(_visibleMonth);
    final monthLabel = DateFormat('yyyy년 M월').format(_visibleMonth);
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Column(
      children: [
        // ==== 월 헤더 ====
        Row(
          children: [
            IconButton(
              tooltip: '이전 달',
              icon: const Icon(Icons.chevron_left),
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            IconButton(
              tooltip: '다음 달',
              icon: const Icon(Icons.chevron_right),
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
              final d = days[i];
              final inMonth = d.month == _visibleMonth.month;
              final isToday = _isSameDay(d, DateTime.now());
              final isSelected = _selectedDay != null && _isSameDay(d, _selectedDay!);

              // 해당 날짜의 이벤트 및 개수
              final eventsOfDay = _eventsOnDay(d);
              final cnt = eventsOfDay.length;

              final bg = isSelected
                  ? Theme.of(context).colorScheme.primary.withOpacity(isLight ? .12 : .22)
                  : Colors.transparent;

              final fg = inMonth
                  ? (isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface)
                  : Colors.grey;

              return InkWell(
                onTap: () {
                  setState(() => _selectedDay = d);
                  _openDaySheet(context, d);
                },
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
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
                            Text('${d.day}', style: TextStyle(fontSize: 12, color: fg)),
                            if (isToday)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary,
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
                                final color = (p == 100) ? Colors.red : Colors.black;
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
                                    style: TextStyle(
                                      fontSize: 9,
                                      height: 1.0,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.6),
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
    final isSun = label == '일';
    final isSat = label == '토';
    final color = isSun
        ? Colors.redAccent
        : (isSat ? Colors.blueAccent : Theme.of(context).colorScheme.onSurface.withOpacity(.7));
    return Expanded(
      child: Center(
        child: Text(label, style: TextStyle(fontSize: 12, color: color)),
      ),
    );
  }
}
