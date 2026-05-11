import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../productivity_sheet.dart';
import '../../utils/productivity_tools.dart';

Future<void> showCalendarDialog({
  required BuildContext context,
  DateTime? initialFocusDate,
  int? initialFocusEventId,
}) async {
  await ChillStore.instance.init();
  final focus = initialFocusDate ?? DateTime.now();
  final visibleMonth = DateTime(focus.year, focus.month, 1);
  final range = _monthGridRange(visibleMonth);
  await ChillStore.instance.refreshEventsRange(
    startInclusive: range.$1,
    endExclusive: range.$2,
  );
  if (!context.mounted) return;

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => CalendarDialog(
      initialFocusDate: focus,
      initialFocusEventId: initialFocusEventId,
    ),
  );
}

class ChillCalendarRouter {
  ChillCalendarRouter._();

  static bool _bound = false;
  static Future<void>? _dialogFuture;

  static void bind(GlobalKey<NavigatorState> navigatorKey) {
    if (_bound) return;
    _bound = true;

    ChillStore.instance.openEventId.addListener(() {
      final id = ChillStore.instance.consumeOpenEventId();
      if (id == null) return;
      if (_dialogFuture != null) return;

      final state = navigatorKey.currentState;
      final ctx = state?.overlay?.context ?? state?.context;
      if (ctx == null) return;

      _dialogFuture = () async {
        final ev = await ChillStore.instance.fetchEventById(id);
        final focus = ev?.startAt ?? DateTime.now();
        await showCalendarDialog(
          context: ctx,
          initialFocusDate: focus,
          initialFocusEventId: id,
        );
      }().whenComplete(() => _dialogFuture = null);
    });
  }
}

class CalendarDialog extends StatelessWidget {
  final DateTime initialFocusDate;
  final int? initialFocusEventId;

  const CalendarDialog({
    super.key,
    required this.initialFocusDate,
    this.initialFocusEventId,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: CalendarPanel(
          mode: CalendarPanelMode.dialog,
          initialFocusDate: initialFocusDate,
          initialFocusEventId: initialFocusEventId,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

class CalendarTab extends StatelessWidget {
  const CalendarTab({super.key});

  @override
  Widget build(BuildContext context) {
    return CalendarPanel(
      mode: CalendarPanelMode.tab,
      initialFocusDate: DateTime.now(),
    );
  }
}

enum CalendarPanelMode { tab, dialog }

enum _EventFilter { upcoming, done, all }

enum _QuickRemind { none, atStart, min5, min10, min30, hour1 }

class CalendarPanel extends StatefulWidget {
  final CalendarPanelMode mode;
  final DateTime initialFocusDate;
  final int? initialFocusEventId;
  final VoidCallback? onClose;

  const CalendarPanel({
    super.key,
    required this.mode,
    required this.initialFocusDate,
    this.initialFocusEventId,
    this.onClose,
  });

  @override
  State<CalendarPanel> createState() => _CalendarPanelState();
}

class _CalendarPanelState extends State<CalendarPanel> {
  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  int? _focusEventId;

  final ScrollController _sc = ScrollController();
  final Map<int, GlobalKey> _eventKeys = <int, GlobalKey>{};

  final TextEditingController _quickTitleCtrl = TextEditingController();
  bool _quickAllDay = false;
  TimeOfDay _quickStartTime = const TimeOfDay(hour: 9, minute: 0);
  int _quickDurationMin = 60;
  _QuickRemind _quickRemind = _QuickRemind.none;

  _EventFilter _filter = _EventFilter.upcoming;

  @override
  void initState() {
    super.initState();

    final focus = widget.initialFocusDate;
    _visibleMonth = DateTime(focus.year, focus.month, 1);
    _selectedDate = DateTime(focus.year, focus.month, focus.day);
    _focusEventId = widget.initialFocusEventId;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final fromNoti = ChillStore.instance.consumeOpenEventId();
      if (fromNoti != null) {
        final ev = await ChillStore.instance.fetchEventById(fromNoti);
        if (!mounted) return;
        final fd = ev?.startAt ?? DateTime.now();
        setState(() {
          _visibleMonth = DateTime(fd.year, fd.month, 1);
          _selectedDate = DateTime(fd.year, fd.month, fd.day);
          _focusEventId = fromNoti;
        });
      }
      await _loadMonthRange();
      _scrollToFocusIfPossible();
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    _quickTitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMonthRange() async {
    final range = _monthGridRange(_visibleMonth);
    await ChillStore.instance.refreshEventsRange(
      startInclusive: range.$1,
      endExclusive: range.$2,
    );
  }

  Future<void> _goPrevMonth() async {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
      _focusEventId = null;
    });
    await _loadMonthRange();
  }

  Future<void> _goNextMonth() async {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
      _focusEventId = null;
    });
    await _loadMonthRange();
  }

  Future<void> _goToday() async {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = DateTime(now.year, now.month, 1);
      _selectedDate = DateTime(now.year, now.month, now.day);
      _focusEventId = null;
    });
    await _loadMonthRange();
  }

  void _selectDate(DateTime d) {
    setState(() {
      _selectedDate = DateTime(d.year, d.month, d.day);
      _focusEventId = null;
    });
  }

  void _openCalendarComposer() {
    widget.onClose?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ProductivitySheet.openPanel(tab: ProductivitySheetTab.calendar));
    });
  }

  Future<void> _editEvent(ChillEvent e) async {
    if (e.isLocked) return;
    final draft = await _openEventEditor(context, existing: e, seedDate: null);
    if (draft == null) return;

    await ChillStore.instance.updateEvent(
      id: e.id,
      title: draft.title,
      startAt: draft.startAt,
      endAt: draft.endAt,
      allDay: draft.allDay,
      remindAt: draft.remindAt,
    );

    if (!mounted) return;
    setState(() {
      _selectedDate = DateTime(draft.startAt.year, draft.startAt.month, draft.startAt.day);
      _focusEventId = e.id;
    });
    _scrollToFocusIfPossible();
  }

  Future<void> _deleteEvent(ChillEvent e) async {
    if (e.isLocked) return;
    final ok = await _confirmDelete(
      context,
      title: '일정 삭제',
      message: '"${e.title}"을(를) 삭제할까요?',
    );
    if (!ok) return;
    if (_focusEventId == e.id) setState(() => _focusEventId = null);
    await ChillStore.instance.deleteEvent(e);
  }

  Future<void> _toggleDone(ChillEvent e) async {
    if (e.isLocked) return;
    await ChillStore.instance.toggleEventDone(e);
    if (!mounted) return;
    if (_focusEventId == e.id) _scrollToFocusIfPossible();
  }

  Future<void> _clearDoneInVisibleRange(int doneCount) async {
    if (doneCount <= 0) return;
    final ok = await _confirmDelete(
      context,
      title: '완료 일정 비우기',
      message: '이 달의 완료된 일정 $doneCount개를 삭제할까요?',
    );
    if (!ok) return;

    final range = _monthGridRange(_visibleMonth);
    await ChillStore.instance.deleteDoneEventsInRange(
      startInclusive: range.$1,
      endExclusive: range.$2,
    );

    if (!mounted) return;
    setState(() => _focusEventId = null);
    await _loadMonthRange();
  }

  void _scrollToFocusIfPossible() {
    final id = _focusEventId;
    if (id == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _eventKeys[id];
      final ctx = key?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.15,
      );
    });
  }

  Widget _header(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final label = '${_visibleMonth.year}년 ${_visibleMonth.month}월';

    Widget iconBtn({
      required String tooltip,
      required VoidCallback? onPressed,
      required IconData icon,
    }) {
      return IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        onPressed: onPressed,
        icon: Icon(icon, color: cs.onSurfaceVariant),
      );
    }

    return LayoutBuilder(
      builder: (ctx, c) {
        final compact = c.maxWidth < 380;

        final titleRow = Row(
          children: [
            Icon(Icons.calendar_month_rounded, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.mode == CalendarPanelMode.tab ? '일정 추가' : '달력',
                style: (tt.titleMedium ?? const TextStyle(fontSize: 16))
                    .copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
              ),
            ),
            if (widget.mode == CalendarPanelMode.dialog)
              iconBtn(
                tooltip: '닫기',
                onPressed: widget.onClose,
                icon: Icons.close_rounded,
              ),
          ],
        );

        if (compact) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              titleRow,
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (tt.labelLarge ?? const TextStyle(fontSize: 14))
                          .copyWith(fontWeight: FontWeight.w900, color: cs.onSurface),
                    ),
                  ),
                  iconBtn(
                    tooltip: '이전 달',
                    onPressed: _goPrevMonth,
                    icon: Icons.chevron_left_rounded,
                  ),
                  iconBtn(
                    tooltip: '다음 달',
                    onPressed: _goNextMonth,
                    icon: Icons.chevron_right_rounded,
                  ),
                  PopupMenuButton<int>(
                    tooltip: '메뉴',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                    icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant),
                    onSelected: (v) {
                      if (v == 0) {
                        _goToday();
                        return;
                      }
                      if (v == 1) {
                        if (widget.mode == CalendarPanelMode.dialog) {
                          _openCalendarComposer();
                        } else {
                          showCalendarDialog(context: context, initialFocusDate: _selectedDate);
                        }
                        return;
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem<int>(value: 0, child: Text('오늘')),
                      PopupMenuItem<int>(
                        value: 1,
                        child: Text(widget.mode == CalendarPanelMode.dialog ? '일정 생성' : '일정 보기/정리'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Icon(Icons.calendar_month_rounded, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.mode == CalendarPanelMode.tab ? '일정 추가' : '달력',
                style: (tt.titleMedium ?? const TextStyle(fontSize: 16))
                    .copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: (tt.labelLarge ?? const TextStyle(fontSize: 14))
                      .copyWith(fontWeight: FontWeight.w900, color: cs.onSurface),
                ),
              ),
            ),
            const SizedBox(width: 4),
            iconBtn(
              tooltip: '이전 달',
              onPressed: _goPrevMonth,
              icon: Icons.chevron_left_rounded,
            ),
            iconBtn(
              tooltip: '다음 달',
              onPressed: _goNextMonth,
              icon: Icons.chevron_right_rounded,
            ),
            iconBtn(
              tooltip: '오늘',
              onPressed: _goToday,
              icon: Icons.today_rounded,
            ),
            if (widget.mode == CalendarPanelMode.dialog)
              iconBtn(
                tooltip: '닫기',
                onPressed: widget.onClose,
                icon: Icons.close_rounded,
              ),
          ],
        );
      },
    );
  }

  Widget _weekdayHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    const days = ['일', '월', '화', '수', '목', '금', '토'];

    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(
                days[i],
                style: (tt.labelMedium ?? const TextStyle(fontSize: 12))
                    .copyWith(fontWeight: FontWeight.w900, color: cs.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }

  Widget _monthGrid(BuildContext context, Map<int, int> countByDayKey) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final range = _monthGridRange(_visibleMonth);
    final start = range.$1;

    bool isSameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    bool isInMonth(DateTime d) => d.month == _visibleMonth.month;

    String dayText(DateTime d) => d.day.toString();

    return LayoutBuilder(
      builder: (ctx, c) {
        const crossAxisCount = 7;
        const spacing = 6.0;

        final maxW = c.maxWidth.isFinite
            ? c.maxWidth
            : MediaQuery.of(context).size.width;

        final rawCellW =
            (maxW - spacing * (crossAxisCount - 1)) / crossAxisCount;
        final cellW = math.max(1.0, rawCellW);
        final cellH = math.max(cellW, 34.0);
        final ratio = cellW / cellH;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: ratio,
          ),
          itemCount: 42,
          itemBuilder: (ctx, i) {
            final d = start.add(Duration(days: i));
            final selected = isSameDay(d, _selectedDate);
            final today = isSameDay(d, DateTime.now());

            final key = _dayKey(d);
            final count = countByDayKey[key] ?? 0;

            final bg = selected
                ? cs.primary.withOpacity(0.20)
                : cs.surfaceVariant.withOpacity(0.35);

            final border = selected
                ? Border.all(color: cs.primary.withOpacity(0.85), width: 1.2)
                : Border.all(color: cs.outlineVariant.withOpacity(0.55), width: 1.0);

            final fg = isInMonth(d)
                ? cs.onSurface
                : cs.onSurfaceVariant.withOpacity(0.55);

            final dayStyle = (tt.bodyMedium ?? const TextStyle(fontSize: 13))
                .copyWith(fontWeight: FontWeight.w900, color: fg);

            final Widget marker = today
                ? Container(
              width: 18,
              height: 3,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.85),
                borderRadius: BorderRadius.circular(4),
              ),
            )
                : (count > 0
                ? Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.85),
                shape: BoxShape.circle,
              ),
            )
                : const SizedBox(width: 6, height: 6));

            return InkWell(
              onTap: () => _selectDate(d),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                  border: border,
                ),
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(dayText(d), style: dayStyle),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: marker,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<ChillEvent> _eventsForSelected(List<ChillEvent> all) {
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    Iterable<ChillEvent> it = all.where((e) => sameDay(e.startAt, _selectedDate));

    if (widget.mode == CalendarPanelMode.dialog) {
      if (_filter == _EventFilter.upcoming) it = it.where((e) => !e.isDone);
      if (_filter == _EventFilter.done) it = it.where((e) => e.isDone);
    }

    final list = it.toList(growable: false);
    list.sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      return a.startAt.compareTo(b.startAt);
    });
    return list;
  }

  String _timeLabel(ChillEvent e) {
    String hhmm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (e.allDay) return '종일';
    if (e.endAt == null) return hhmm(e.startAt);
    return '${hhmm(e.startAt)}–${hhmm(e.endAt!)}';
  }

  Widget _dialogFilterRow(BuildContext context, int doneCountInRange) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: SegmentedButton<_EventFilter>(
            segments: const [
              ButtonSegment<_EventFilter>(
                value: _EventFilter.upcoming,
                icon: const Tooltip(
                  message: 'Upcoming',
                  child: const Icon(Icons.upcoming_rounded),
                ),
              ),
              ButtonSegment<_EventFilter>(
                value: _EventFilter.done,
                icon: const Tooltip(
                  message: 'Done',
                  child: const Icon(Icons.check_circle_rounded),
                ),
              ),
              ButtonSegment<_EventFilter>(
                value: _EventFilter.all,
                icon: const Tooltip(
                  message: 'All',
                  child: const Icon(Icons.all_inclusive_rounded),
                ),
              ),
            ],
            selected: <_EventFilter>{_filter},
            onSelectionChanged: (s) {
              if (s.isEmpty) return;
              setState(() => _filter = s.first);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 10)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: doneCountInRange <= 0 ? null : () => _clearDoneInVisibleRange(doneCountInRange),
          icon: const Icon(Icons.delete_sweep_rounded, size: 18),
          label: const Text('완료 비우기'),
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.onSurface,
            side: BorderSide(color: cs.outlineVariant.withOpacity(0.75)),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _eventsHeader(BuildContext context, int count) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final label = '${_selectedDate.month}/${_selectedDate.day} 일정';

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: (tt.titleSmall ?? const TextStyle(fontSize: 14))
                .copyWith(fontWeight: FontWeight.w900, color: cs.onSurface),
          ),
        ),
        Text(
          count.toString(),
          style: (tt.labelLarge ?? const TextStyle(fontSize: 13))
              .copyWith(fontWeight: FontWeight.w900, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _eventsList(BuildContext context, List<ChillEvent> list) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (list.isEmpty) {
      return Center(
        child: Text(
          '이 날은 일정이 없어요.',
          style: (tt.bodyMedium ?? const TextStyle(fontSize: 13))
              .copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return ListView.separated(
      controller: _sc,
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final e = list[i];
        _eventKeys.putIfAbsent(e.id, () => GlobalKey());
        final highlight = _focusEventId == e.id;

        final border = highlight
            ? Border.all(color: cs.primary.withOpacity(0.85), width: 1.2)
            : Border.all(color: cs.outlineVariant.withOpacity(0.6), width: 1.0);

        final meta = <String>[_timeLabel(e)];
        if (e.remindAt != null) meta.add('알림 ${chillFormatDateTime(e.remindAt!)}');
        if (e.isLocked) meta.add('삭제 불가');

        final titleStyle = (tt.bodyMedium ?? const TextStyle(fontSize: 13)).copyWith(
          fontWeight: FontWeight.w900,
          decoration: e.isDone ? TextDecoration.lineThrough : null,
          color: e.isDone ? cs.onSurfaceVariant : cs.onSurface,
        );

        return Container(
          key: _eventKeys[e.id],
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: border,
          ),
          child: Dismissible(
            key: ValueKey('event_${e.id}'),
            direction: e.isLocked
                ? DismissDirection.none
                : DismissDirection.endToStart,
            confirmDismiss: (_) async {
              if (e.isLocked) return false;
              await _deleteEvent(e);
              return false;
            },
            background: _deleteBg(ctx),
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceVariant.withOpacity(0.45),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListTile(
                onTap: e.isLocked ? null : () => _editEvent(e),
                leading: widget.mode == CalendarPanelMode.dialog
                    ? e.isLocked
                        ? Icon(Icons.lock_rounded, color: cs.primary)
                        : Checkbox(
                            value: e.isDone,
                            onChanged: (_) => _toggleDone(e),
                          )
                    : Icon(
                        e.isLocked ? Icons.lock_rounded : Icons.event_rounded,
                        color: e.isLocked ? cs.primary : null,
                      ),
                title: Text(
                  e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
                subtitle: Text(
                  meta.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: (tt.bodySmall ?? const TextStyle(fontSize: 12))
                      .copyWith(color: cs.onSurfaceVariant),
                ),
                trailing: e.isLocked
                    ? Icon(Icons.lock_outline_rounded, color: cs.primary)
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '수정',
                            onPressed: () => _editEvent(e),
                            icon: Icon(Icons.edit_rounded, color: cs.onSurfaceVariant),
                          ),
                          IconButton(
                            tooltip: '삭제',
                            onPressed: () => _deleteEvent(e),
                            icon: Icon(Icons.delete_outline_rounded, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  int? _quickRemindOffset(_QuickRemind r) {
    switch (r) {
      case _QuickRemind.none:
        return null;
      case _QuickRemind.atStart:
        return 0;
      case _QuickRemind.min5:
        return 5;
      case _QuickRemind.min10:
        return 10;
      case _QuickRemind.min30:
        return 30;
      case _QuickRemind.hour1:
        return 60;
    }
  }

  DateTime _quickStartAt() {
    final d = _selectedDate;
    if (_quickAllDay) {
      return DateTime(d.year, d.month, d.day);
    }
    return DateTime(d.year, d.month, d.day, _quickStartTime.hour, _quickStartTime.minute);
  }

  DateTime? _quickEndAt(DateTime startAt) {
    if (_quickAllDay) return null;
    return startAt.add(Duration(minutes: _quickDurationMin));
  }

  DateTime? _quickRemindAt(DateTime startAt) {
    final off = _quickRemindOffset(_quickRemind);
    if (off == null) return null;

    if (_quickAllDay) {
      final base = DateTime(startAt.year, startAt.month, startAt.day, 9, 0);
      return base.subtract(Duration(minutes: off));
    }
    return startAt.subtract(Duration(minutes: off));
  }

  Future<void> _pickQuickStartTime() async {
    final t = await showTimePicker(context: context, initialTime: _quickStartTime);
    if (t == null) return;
    if (!mounted) return;
    setState(() => _quickStartTime = t);
  }

  Future<void> _submitQuickAdd() async {
    final title = _quickTitleCtrl.text.trim();
    if (title.isEmpty) return;

    final startAt = _quickStartAt();
    final endAt = _quickEndAt(startAt);
    final remindAt = _quickRemindAt(startAt);

    await ChillStore.instance.addEvent(
      title: title,
      startAt: startAt,
      endAt: endAt,
      allDay: _quickAllDay,
      remindAt: remindAt,
    );

    if (!mounted) return;
    setState(() => _focusEventId = null);
    _quickTitleCtrl.clear();
  }

  Widget _quickComposer(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final startLabel = _quickAllDay
        ? '종일'
        : '${_quickStartTime.hour.toString().padLeft(2, '0')}:${_quickStartTime.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_selectedDate.month}/${_selectedDate.day} 빠른 추가',
            style: (tt.titleSmall ?? const TextStyle(fontSize: 14))
                .copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _quickTitleCtrl,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitQuickAdd(),
            decoration: InputDecoration(
              hintText: '예: 고객 미팅 / 차량 입고 / 전화',
              isDense: true,
              filled: true,
              fillColor: cs.surface.withOpacity(0.35),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surface.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '종일',
                        style: (tt.labelMedium ?? const TextStyle(fontSize: 12))
                            .copyWith(fontWeight: FontWeight.w900, color: cs.onSurfaceVariant),
                      ),
                      const Spacer(),
                      Switch(
                        value: _quickAllDay,
                        onChanged: (v) => setState(() => _quickAllDay = v),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        activeColor: cs.primary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _quickAllDay ? null : _pickQuickStartTime,
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: Text(startLabel),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  side: BorderSide(color: cs.outlineVariant.withOpacity(0.75)),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _quickDurationMin,
                  decoration: const InputDecoration(
                    labelText: '길이(분)',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('30분')),
                    DropdownMenuItem(value: 60, child: Text('60분')),
                    DropdownMenuItem(value: 90, child: Text('90분')),
                    DropdownMenuItem(value: 120, child: Text('120분')),
                  ],
                  onChanged: _quickAllDay ? null : (v) {
                    if (v == null) return;
                    setState(() => _quickDurationMin = v);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<_QuickRemind>(
                  value: _quickRemind,
                  decoration: const InputDecoration(
                    labelText: '리마인드',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: _QuickRemind.none, child: Text('없음')),
                    DropdownMenuItem(value: _QuickRemind.atStart, child: Text('시작 시')),
                    DropdownMenuItem(value: _QuickRemind.min5, child: Text('5분 전')),
                    DropdownMenuItem(value: _QuickRemind.min10, child: Text('10분 전')),
                    DropdownMenuItem(value: _QuickRemind.min30, child: Text('30분 전')),
                    DropdownMenuItem(value: _QuickRemind.hour1, child: Text('1시간 전')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _quickRemind = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _submitQuickAdd,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('추가'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => showCalendarDialog(
                  context: context,
                  initialFocusDate: _selectedDate,
                ),
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: const Text('보기/정리'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  side: BorderSide(color: cs.outlineVariant.withOpacity(0.75)),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final padding = widget.mode == CalendarPanelMode.dialog
        ? const EdgeInsets.fromLTRB(16, 14, 16, 12)
        : const EdgeInsets.fromLTRB(16, 10, 16, 16);

    return Padding(
      padding: padding,
      child: Column(
        children: [
          _header(context),
          const SizedBox(height: 10),
          _weekdayHeader(context),
          const SizedBox(height: 8),
          ValueListenableBuilder<List<ChillEvent>>(
            valueListenable: ChillStore.instance.events,
            builder: (_, all, __) {
              final map = <int, int>{};
              for (final e in all) {
                final k = _dayKey(e.startAt);
                map[k] = (map[k] ?? 0) + 1;
              }
              return _monthGrid(context, map);
            },
          ),
          const SizedBox(height: 12),
          if (widget.mode == CalendarPanelMode.tab)
            _quickComposer(context)
          else
            ValueListenableBuilder<List<ChillEvent>>(
              valueListenable: ChillStore.instance.events,
              builder: (_, all, __) {
                final doneCount = all.where((e) => e.isDone).length;
                final list = _eventsForSelected(all);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _scrollToFocusIfPossible();
                });

                return Expanded(
                  child: Column(
                    children: [
                      _dialogFilterRow(context, doneCount),
                      const SizedBox(height: 10),
                      _eventsHeader(context, list.length),
                      const SizedBox(height: 8),
                      Expanded(child: _eventsList(context, list)),
                    ],
                  ),
                );
              },
            ),
          if (widget.mode == CalendarPanelMode.dialog) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: _openCalendarComposer,
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('생성'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: widget.onClose,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.onSurface,
                        side: BorderSide(color: cs.outlineVariant.withOpacity(0.75)),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        backgroundColor: cs.surface.withOpacity(0.22),
                      ),
                      child: const Text('닫기'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

Widget _deleteBg(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 18),
    decoration: BoxDecoration(
      color: cs.errorContainer.withOpacity(0.85),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(Icons.delete_rounded, color: cs.onErrorContainer),
  );
}

int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

(DateTime, DateTime) _monthGridRange(DateTime monthFirstDay) {
  final first = DateTime(monthFirstDay.year, monthFirstDay.month, 1);
  final offset = first.weekday % 7;
  final start = DateTime(first.year, first.month, first.day).subtract(Duration(days: offset));
  final end = start.add(const Duration(days: 42));
  return (start, end);
}

class _EventDraft {
  final String title;
  final DateTime startAt;
  final DateTime? endAt;
  final bool allDay;
  final DateTime? remindAt;

  const _EventDraft({
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.allDay,
    required this.remindAt,
  });
}

enum _RemindPreset { none, atStart, min5, min10, min30, hour1, custom }

Future<_EventDraft?> _openEventEditor(
    BuildContext context, {
      required ChillEvent? existing,
      required DateTime? seedDate,
    }) async {
  final cs = Theme.of(context).colorScheme;

  final titleCtrl = TextEditingController(text: existing?.title ?? '');
  bool allDay = existing?.allDay ?? false;

  DateTime startAt;
  DateTime? endAt;

  if (existing != null) {
    startAt = existing.startAt;
    endAt = existing.endAt;
  } else {
    final base = seedDate ?? DateTime.now();
    startAt = DateTime(base.year, base.month, base.day, 9, 0);
    endAt = startAt.add(const Duration(hours: 1));
  }

  DateTime? remindAt = existing?.remindAt;

  _RemindPreset preset = _RemindPreset.none;
  DateTime? customRemindAt;

  DateTime remindBase() {
    if (!allDay) return startAt;
    return DateTime(startAt.year, startAt.month, startAt.day, 9, 0);
  }

  if (remindAt == null) {
    preset = _RemindPreset.none;
  } else {
    final base = remindBase();
    final diffMin = base.difference(remindAt).inMinutes;
    if (diffMin == 0) preset = _RemindPreset.atStart;
    else if (diffMin == 5) preset = _RemindPreset.min5;
    else if (diffMin == 10) preset = _RemindPreset.min10;
    else if (diffMin == 30) preset = _RemindPreset.min30;
    else if (diffMin == 60) preset = _RemindPreset.hour1;
    else {
      preset = _RemindPreset.custom;
      customRemindAt = remindAt;
    }
  }

  Future<DateTime?> pickDateTime(DateTime initial) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDate: initial,
    );
    if (d == null) return null;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<DateTime?> pickDate(DateTime initial) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDate: initial,
    );
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  int? presetOffsetMinutes(_RemindPreset p) {
    switch (p) {
      case _RemindPreset.none:
        return null;
      case _RemindPreset.atStart:
        return 0;
      case _RemindPreset.min5:
        return 5;
      case _RemindPreset.min10:
        return 10;
      case _RemindPreset.min30:
        return 30;
      case _RemindPreset.hour1:
        return 60;
      case _RemindPreset.custom:
        return null;
    }
  }

  DateTime? computeRemindAt() {
    if (preset == _RemindPreset.none) return null;
    if (preset == _RemindPreset.custom) return customRemindAt;
    final off = presetOffsetMinutes(preset) ?? 0;
    final base = remindBase();
    return base.subtract(Duration(minutes: off));
  }

  String fmt(DateTime? dt) => dt == null ? '-' : chillFormatDateTime(dt);

  String? error;

  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> pickStart() async {
          final picked =
          allDay ? await pickDate(startAt) : await pickDateTime(startAt);
          if (picked == null) return;
          setState(() {
            startAt = allDay
                ? DateTime(picked.year, picked.month, picked.day)
                : picked;
            if (allDay) endAt = null;
            error = null;
            if (preset != _RemindPreset.custom) {
              remindAt = computeRemindAt();
            }
          });
        }

        Future<void> pickEnd() async {
          if (allDay) return;
          final base = endAt ?? startAt.add(const Duration(hours: 1));
          final picked = await pickDateTime(base);
          if (picked == null) return;
          setState(() {
            endAt = picked;
            error = null;
          });
        }

        Future<void> pickCustomRemind() async {
          final base = customRemindAt ?? startAt;
          final picked = await pickDateTime(base);
          if (picked == null) return;
          setState(() {
            customRemindAt = picked;
            remindAt = computeRemindAt();
          });
        }

        void toggleAllDay(bool v) {
          setState(() {
            allDay = v;
            if (allDay) {
              startAt = DateTime(startAt.year, startAt.month, startAt.day);
              endAt = null;
            }
            if (preset != _RemindPreset.custom) {
              remindAt = computeRemindAt();
            }
          });
        }

        return AlertDialog(
          title: Text(existing == null ? '일정 추가' : '일정 수정'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    autofocus: true,
                    decoration:
                    const InputDecoration(hintText: '예: 회의 / 병원 / 약속'),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: allDay,
                    onChanged: toggleAllDay,
                    title: const Text('종일'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  _dtRowLite(
                    context,
                    label: '시작',
                    value: fmt(startAt),
                    onPick: pickStart,
                    onClear: null,
                  ),
                  const SizedBox(height: 8),
                  if (!allDay)
                    _dtRowLite(
                      context,
                      label: '종료',
                      value: fmt(endAt),
                      onPick: pickEnd,
                      onClear: endAt == null
                          ? null
                          : () => setState(() => endAt = null),
                    ),
                  if (!allDay) const SizedBox(height: 8),
                  DropdownButtonFormField<_RemindPreset>(
                    value: preset,
                    decoration: const InputDecoration(
                      labelText: '리마인드',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: _RemindPreset.none, child: Text('없음')),
                      DropdownMenuItem(
                          value: _RemindPreset.atStart, child: Text('시작 시')),
                      DropdownMenuItem(
                          value: _RemindPreset.min5, child: Text('5분 전')),
                      DropdownMenuItem(
                          value: _RemindPreset.min10, child: Text('10분 전')),
                      DropdownMenuItem(
                          value: _RemindPreset.min30, child: Text('30분 전')),
                      DropdownMenuItem(
                          value: _RemindPreset.hour1, child: Text('1시간 전')),
                      DropdownMenuItem(
                          value: _RemindPreset.custom, child: Text('직접 선택')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        preset = v;
                        if (preset != _RemindPreset.custom) {
                          customRemindAt = null;
                          remindAt = computeRemindAt();
                        } else {
                          customRemindAt = remindAt ?? remindBase();
                          remindAt = computeRemindAt();
                        }
                      });
                    },
                  ),
                  if (preset == _RemindPreset.custom) ...[
                    const SizedBox(height: 8),
                    _dtRowLite(
                      context,
                      label: '알림',
                      value: fmt(customRemindAt),
                      onPick: pickCustomRemind,
                      onClear: customRemindAt == null
                          ? null
                          : () => setState(() {
                        customRemindAt = null;
                        remindAt = computeRemindAt();
                      }),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        error!,
                        style: TextStyle(
                            color: cs.error, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
              ),
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                if (!allDay && endAt != null && endAt!.isBefore(startAt)) {
                  setState(() =>
                  error = '종료 시간이 시작 시간보다 빠를 수 없어요.');
                  return;
                }
                remindAt = computeRemindAt();
                Navigator.of(ctx).pop(true);
              },
              child: const Text('저장'),
            ),
          ],
        );
      },
    ),
  );

  if (ok != true) return null;

  final title = titleCtrl.text.trim();
  if (title.isEmpty) return null;

  final resolvedStart =
  allDay ? DateTime(startAt.year, startAt.month, startAt.day) : startAt;
  final resolvedEnd = allDay ? null : endAt;

  return _EventDraft(
    title: title,
    startAt: resolvedStart,
    endAt: resolvedEnd,
    allDay: allDay,
    remindAt: remindAt,
  );
}

Widget _dtRowLite(
    BuildContext context, {
      required String label,
      required String value,
      required VoidCallback onPick,
      required VoidCallback? onClear,
    }) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;

  return Row(
    children: [
      SizedBox(
        width: 72,
        child: Text(
          label,
          style: (tt.bodyMedium ?? const TextStyle(fontSize: 13))
              .copyWith(color: cs.onSurfaceVariant),
        ),
      ),
      Expanded(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (tt.bodyMedium ?? const TextStyle(fontSize: 13))
              .copyWith(color: cs.onSurface),
        ),
      ),
      IconButton(
        tooltip: '선택',
        onPressed: onPick,
        icon: const Icon(Icons.event_available_rounded),
      ),
      IconButton(
        tooltip: '지우기',
        onPressed: onClear,
        icon: const Icon(Icons.clear_rounded),
      ),
    ],
  );
}

Future<bool> _confirmDelete(
    BuildContext context, {
      required String title,
      required String message,
    }) async {
  final cs = Theme.of(context).colorScheme;
  final res = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: cs.error,
            foregroundColor: cs.onError,
          ),
          onPressed: () => Navigator.of(dctx).pop(true),
          child: const Text('삭제'),
        ),
      ],
    ),
  );
  return res == true;
}
