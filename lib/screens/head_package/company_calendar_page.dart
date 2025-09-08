import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'calendar_package/calendar_model.dart';

class CompanyCalendarPage extends StatefulWidget {
  const CompanyCalendarPage({super.key});

  @override
  State<CompanyCalendarPage> createState() => _CompanyCalendarPageState();
}

class _CompanyCalendarPageState extends State<CompanyCalendarPage> {
  final _idCtrl = TextEditingController();

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final model = context.watch<CalendarModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('회사 달력'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 안내 배너
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '캘린더 ID를 입력하고 불러오기를 누르세요. (예: primary 또는 someone@example.com)',
                style: text.bodyMedium?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 입력 + 버튼
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _idCtrl,
                    decoration: const InputDecoration(
                      labelText: '캘린더 ID',
                      hintText: '예: primary 또는 공유받은 캘린더 이메일',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: model.loading
                      ? null
                      : () async {
                    FocusScope.of(context).unfocus();
                    await context
                        .read<CalendarModel>()
                        .load(newCalendarId: _idCtrl.text);
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('불러오기'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 상태 표시
            if (model.loading) const LinearProgressIndicator(),
            if (model.error != null) ...[
              const SizedBox(height: 8),
              Text(model.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],

            const SizedBox(height: 8),

            // 이벤트 목록
            Expanded(
              child: _EventList(events: model.events),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventList extends StatelessWidget {
  const _EventList({required this.events});
  final List<gcal.Event> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(child: Text('이벤트가 없습니다.'));
    }
    final fmtDate = DateFormat('yyyy-MM-dd (EEE) HH:mm');
    return ListView.separated(
      itemCount: events.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = events[i];
        final start = e.start?.dateTime ?? _asDateTime(e.start?.date);
        final end = e.end?.dateTime ?? _asDateTime(e.end?.date);
        final when = (start != null)
            ? '${fmtDate.format(start)}'
            : '(시작 시간 미정)';
        return ListTile(
          leading: const Icon(Icons.event),
          title: Text(e.summary ?? '(제목 없음)'),
          subtitle: Text(when),
          trailing: (end != null && start != null)
              ? Text(_durationLabel(end.difference(start)))
              : null,
        );
      },
    );
  }

  DateTime? _asDateTime(DateTime? d) {
    // 하루 종일(날짜만 있는) 이벤트는 00:00로 표시
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  String _durationLabel(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}분';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}시간' : '${h}시간 ${m}분';
  }
}
