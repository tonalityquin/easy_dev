import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../application/personal_calendar_store.dart';
import '../../domain/models/personal_calendar_event.dart';
import '../widgets/personal_prompt_components.dart';

Future<bool?> showPersonalCalendarDialog(BuildContext context) {
  return showPromptOverlayDialog<bool>(
    context: context,
    builder: (_) => const PersonalCalendarDialog(),
  );
}

class PersonalCalendarDialog extends StatefulWidget {
  const PersonalCalendarDialog({super.key});

  @override
  State<PersonalCalendarDialog> createState() => _PersonalCalendarDialogState();
}

class _PersonalCalendarDialogState extends State<PersonalCalendarDialog> {
  final PersonalCalendarStore _store = PersonalCalendarStore();
  List<PersonalCalendarEvent> _events = const <PersonalCalendarEvent>[];
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final events = await _store.load();
    if (!mounted) return;
    setState(() {
      _events = events;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final event = await showPromptOverlayDialog<PersonalCalendarEvent>(
      context: context,
      builder: (_) => _CalendarEventEditorDialog(initialDate: _selectedDay),
    );
    if (event == null) return;
    await _store.upsert(event);
    await _load();
  }

  Future<void> _remove(PersonalCalendarEvent event) async {
    HapticFeedback.mediumImpact();
    await _store.remove(event.id);
    await _load();
  }

  void _moveMonth(int delta) {
    HapticFeedback.selectionClick();
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + delta,
      );
      _selectedDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final size = MediaQuery.sizeOf(context);
    final selectedEvents = _events
        .where((event) => _sameDay(event.dayOnly, _selectedDay))
        .toList(growable: false);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      backgroundColor: tokens.surfaceRaised,
      surfaceTintColor: tokens.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PromptUiShapes.dialog),
        side: BorderSide(color: tokens.borderSubtle),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 580,
            maxHeight: size.height * .88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.accentContainer,
                      borderRadius: BorderRadius.circular(
                        PromptUiShapes.control,
                      ),
                    ),
                    child: Icon(
                      Icons.calendar_month_rounded,
                      color: tokens.onAccentContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '내 일정',
                      style: textTheme.titleLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  PersonalPromptStatusPill(
                    label: '${_events.length}개 일정',
                    foreground: tokens.statusMonthlyParking,
                    background: tokens.statusMonthlyParkingContainer,
                    icon: Icons.event_available_rounded,
                  ),
                  const SizedBox(width: 6),
                  PromptIconButton(
                    icon: Icons.close_rounded,
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(false),
                    haptic: PromptHaptic.selection,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: tokens.borderSubtle),
              const SizedBox(height: 14),
              Flexible(
                child: PersonalPromptAnimatedSwap(
                  stateKey: _loading ? 'loading' : 'calendar',
                  alignment: Alignment.topCenter,
                  child: _loading
                      ? const Center(
                          child: PersonalPromptLoadingState(
                            label: '일정을 불러오는 중입니다.',
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              PersonalPromptPanel(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: <Widget>[
                                    PromptIconButton(
                                      icon: Icons.chevron_left_rounded,
                                      tooltip: '이전 달',
                                      onPressed: () => _moveMonth(-1),
                                      haptic: PromptHaptic.selection,
                                    ),
                                    Expanded(
                                      child: AnimatedSwitcher(
                                        duration: personalPromptDuration(
                                          context,
                                          PromptUiMotion.selection,
                                        ),
                                        child: Text(
                                          '${_visibleMonth.year}년 ${_visibleMonth.month}월',
                                          key: ValueKey<String>(
                                            '${_visibleMonth.year}-${_visibleMonth.month}',
                                          ),
                                          textAlign: TextAlign.center,
                                          style: textTheme.titleMedium?.copyWith(
                                            color: tokens.textPrimary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                    PromptIconButton(
                                      icon: Icons.chevron_right_rounded,
                                      tooltip: '다음 달',
                                      onPressed: () => _moveMonth(1),
                                      haptic: PromptHaptic.selection,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              _CalendarGrid(
                                month: _visibleMonth,
                                selectedDay: _selectedDay,
                                events: _events,
                                onSelect: (day) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _selectedDay = day);
                                },
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      _formatDate(_selectedDay),
                                      style: textTheme.titleSmall?.copyWith(
                                        color: tokens.textPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  PersonalPromptStatusPill(
                                    label: '${selectedEvents.length}개',
                                    foreground: tokens.statusSynchronized,
                                    background:
                                        tokens.statusSynchronizedContainer,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              PersonalPromptAnimatedSwap(
                                stateKey:
                                    '${_selectedDay.millisecondsSinceEpoch}-${selectedEvents.length}',
                                alignment: Alignment.topCenter,
                                child: selectedEvents.isEmpty
                                    ? const PersonalPromptEmptyState(
                                        icon: Icons.event_busy_rounded,
                                        title: '이 날 등록된 일정이 없습니다.',
                                      )
                                    : Column(
                                        children: selectedEvents
                                            .asMap()
                                            .entries
                                            .map(
                                              (entry) => Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 8,
                                                ),
                                                child: PromptAnimatedReveal(
                                                  key: ValueKey<String>(
                                                    entry.value.id,
                                                  ),
                                                  delay: Duration(
                                                    milliseconds:
                                                        entry.key * 24,
                                                  ),
                                                  child: PersonalPromptPanel(
                                                    padding:
                                                        const EdgeInsets.all(4),
                                                    child: ListTile(
                                                      title: Text(
                                                        entry.value.title,
                                                        style: textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                          color: tokens
                                                              .textPrimary,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                      subtitle: Text(
                                                        _eventSubtitle(
                                                          entry.value,
                                                        ),
                                                        style: textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                          color: tokens
                                                              .textSecondary,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                      trailing: PromptIconButton(
                                                        icon: Icons
                                                            .delete_outline_rounded,
                                                        tooltip: '삭제',
                                                        onPressed: () =>
                                                            _remove(entry.value),
                                                        haptic:
                                                            PromptHaptic.medium,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(growable: false),
                                      ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              PromptButton(
                label: '일정 추가',
                icon: Icons.add_rounded,
                expand: true,
                haptic: PromptHaptic.light,
                onPressed: _add,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.month,
    required this.selectedDay,
    required this.events,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selectedDay;
  final List<PersonalCalendarEvent> events;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final first = DateTime(month.year, month.month, 1);
    final startOffset = first.weekday % 7;
    final gridStart = first.subtract(Duration(days: startOffset));
    final days = List<DateTime>.generate(
      42,
      (index) => DateTime(
        gridStart.year,
        gridStart.month,
        gridStart.day + index,
      ),
    );
    const weekdayLabels = <String>['일', '월', '화', '수', '목', '금', '토'];

    return PersonalPromptPanel(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: <Widget>[
          Row(
            children: weekdayLabels
                .map(
                  (label) => Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: textTheme.labelSmall?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              final day = days[index];
              final inMonth = day.month == month.month;
              final selected = _sameDay(day, selectedDay);
              final hasEvent = events.any(
                (event) => _sameDay(event.dayOnly, day),
              );
              return Semantics(
                button: true,
                selected: selected,
                label: '${day.month}월 ${day.day}일',
                value: hasEvent ? '일정 있음' : '일정 없음',
                child: InkWell(
                  borderRadius: BorderRadius.circular(PromptUiShapes.control),
                  onTap: () => onSelect(
                    DateTime(day.year, day.month, day.day),
                  ),
                  child: AnimatedContainer(
                    duration: personalPromptDuration(
                      context,
                      PromptUiMotion.selection,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? tokens.accent
                          : inMonth
                              ? tokens.surfaceOverlay
                              : tokens.surfaceDisabled,
                      borderRadius: BorderRadius.circular(
                        PromptUiShapes.control,
                      ),
                      border: Border.all(
                        color: selected
                            ? tokens.accent
                            : tokens.borderSubtle,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          '${day.day}',
                          style: textTheme.labelMedium?.copyWith(
                            color: selected
                                ? tokens.onAccent
                                : inMonth
                                    ? tokens.textPrimary
                                    : tokens.textDisabled,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        AnimatedContainer(
                          duration: personalPromptDuration(
                            context,
                            PromptUiMotion.selection,
                          ),
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: hasEvent
                                ? selected
                                    ? tokens.onAccent
                                    : tokens.statusMonthlyParking
                                : tokens.transparent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CalendarEventEditorDialog extends StatefulWidget {
  const _CalendarEventEditorDialog({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_CalendarEventEditorDialog> createState() =>
      _CalendarEventEditorDialogState();
}

class _CalendarEventEditorDialogState
    extends State<_CalendarEventEditorDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _plateController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _plateController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showPromptDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      HapticFeedback.mediumImpact();
      return;
    }
    final now = DateTime.now();
    Navigator.of(context).pop(
      PersonalCalendarEvent(
        id: 'evt_${now.microsecondsSinceEpoch}',
        title: title,
        plateNumber: _plateController.text.trim(),
        note: _noteController.text.trim(),
        date: _date,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: tokens.surfaceRaised,
      surfaceTintColor: tokens.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PromptUiShapes.dialog),
        side: BorderSide(color: tokens.borderSubtle),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.event_note_rounded, color: tokens.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '일정 추가',
                        style: textTheme.titleLarge?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _titleController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '일정 제목',
                    prefixIcon: Icon(Icons.title_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _plateController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '차량 번호',
                    prefixIcon: Icon(Icons.directions_car_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '메모',
                    prefixIcon: Icon(Icons.notes_rounded),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 12),
                PromptButton(
                  label: _formatDate(_date),
                  icon: Icons.event_rounded,
                  variant: PromptButtonVariant.secondary,
                  expand: true,
                  haptic: PromptHaptic.selection,
                  onPressed: _pickDate,
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: PromptButton(
                        label: '취소',
                        variant: PromptButtonVariant.tertiary,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PromptButton(
                        label: '저장',
                        icon: Icons.check_rounded,
                        haptic: PromptHaptic.light,
                        onPressed: _save,
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
  }
}

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _eventSubtitle(PersonalCalendarEvent event) {
  final parts = <String>[];
  if (event.plateNumber.trim().isNotEmpty) {
    parts.add(event.plateNumber.trim());
  }
  if (event.note.trim().isNotEmpty) parts.add(event.note.trim());
  return parts.isEmpty ? _formatDate(event.date) : parts.join(' · ');
}

String _formatDate(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  final d = dt.toLocal();
  return '${d.year}.${two(d.month)}.${two(d.day)}';
}
