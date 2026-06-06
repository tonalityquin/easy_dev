import 'package:flutter/material.dart';

import '../../application/personal_calendar_store.dart';
import '../../domain/models/personal_calendar_event.dart';

Future<bool?> showPersonalCalendarDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
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
  DateTime _selectedDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
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
    final event = await showDialog<PersonalCalendarEvent>(
      context: context,
      builder: (_) => _CalendarEventEditorDialog(initialDate: _selectedDay),
    );
    if (event == null) return;
    await _store.upsert(event);
    await _load();
  }

  Future<void> _remove(PersonalCalendarEvent event) async {
    await _store.remove(event.id);
    await _load();
  }

  void _moveMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
      _selectedDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final selectedEvents = _events.where((e) => _sameDay(e.dayOnly, _selectedDay)).toList();

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Icon(Icons.calendar_month_rounded, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('내 일정', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: _loading
            ? const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(onPressed: () => _moveMonth(-1), icon: const Icon(Icons.chevron_left_rounded)),
                        Expanded(
                          child: Text(
                            '${_visibleMonth.year}년 ${_visibleMonth.month}월',
                            textAlign: TextAlign.center,
                            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(onPressed: () => _moveMonth(1), icon: const Icon(Icons.chevron_right_rounded)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _CalendarGrid(
                      month: _visibleMonth,
                      selectedDay: _selectedDay,
                      events: _events,
                      onSelect: (day) => setState(() => _selectedDay = day),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _formatDate(_selectedDay),
                      style: text.titleSmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    if (selectedEvents.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '이 날 등록된 일정이 없습니다.',
                          style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                        ),
                      )
                    else
                      ...selectedEvents.map(
                        (event) => Card(
                          elevation: 0,
                          color: cs.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: cs.outlineVariant.withOpacity(.55)),
                          ),
                          child: ListTile(
                            title: Text(event.title, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w900)),
                            subtitle: Text(_eventSubtitle(event), style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                            trailing: IconButton(
                              tooltip: '삭제',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => _remove(event),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('닫기')),
        FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('일정 추가')),
      ],
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
    final cs = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final startOffset = first.weekday % 7;
    final gridStart = first.subtract(Duration(days: startOffset));
    final days = List<DateTime>.generate(42, (i) => DateTime(gridStart.year, gridStart.month, gridStart.day + i));
    final weekdayLabels = const ['일', '월', '화', '수', '목', '금', '토'];

    return Column(
      children: [
        Row(
          children: weekdayLabels
              .map(
                (label) => Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: days.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 6, crossAxisSpacing: 6),
          itemBuilder: (context, index) {
            final day = days[index];
            final inMonth = day.month == month.month;
            final selected = _sameDay(day, selectedDay);
            final hasEvent = events.any((e) => _sameDay(e.dayOnly, day));
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelect(DateTime(day.year, day.month, day.day)),
              child: Container(
                decoration: BoxDecoration(
                  color: selected ? cs.primary : inMonth ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: selected ? cs.primary : cs.outlineVariant.withOpacity(.35)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${day.day}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: selected ? cs.onPrimary : inMonth ? cs.onSurface : cs.onSurfaceVariant.withOpacity(.55),
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: hasEvent ? (selected ? cs.onPrimary : cs.primary) : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CalendarEventEditorDialog extends StatefulWidget {
  const _CalendarEventEditorDialog({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_CalendarEventEditorDialog> createState() => _CalendarEventEditorDialogState();
}

class _CalendarEventEditorDialogState extends State<_CalendarEventEditorDialog> {
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
    final picked = await showDatePicker(
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
    if (title.isEmpty) return;
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
    return AlertDialog(
      title: const Text('일정 추가'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _titleController, decoration: const InputDecoration(labelText: '일정 제목', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _plateController, decoration: const InputDecoration(labelText: '차량 번호', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _noteController, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: '메모', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.event_rounded), label: Text(_formatDate(_date))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
        FilledButton(onPressed: _save, child: const Text('저장')),
      ],
    );
  }
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _eventSubtitle(PersonalCalendarEvent event) {
  final parts = <String>[];
  if (event.plateNumber.trim().isNotEmpty) parts.add(event.plateNumber.trim());
  if (event.note.trim().isNotEmpty) parts.add(event.note.trim());
  return parts.isEmpty ? _formatDate(event.date) : parts.join(' · ');
}

String _formatDate(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  final d = dt.toLocal();
  return '${d.year}.${two(d.month)}.${two(d.day)}';
}
