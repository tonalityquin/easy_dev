// lib/screens/dev_package/dev_calendar_package/board_kanban_view.dart
import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

/// 보드 버킷 정의
enum BoardBucket { today, thisWeek, later, done }

/// progress 추출, 편집/삭제/토글, 이동 콜백을 외부에서 주입
/// - 이 버전은 "한 화면에 한 컬럼"만 보여주고, PageView 스와이프로 칼럼 전환
class DevBoardKanbanView extends StatefulWidget {
  const DevBoardKanbanView({
    super.key,
    required this.allEvents,
    required this.progressOf,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleProgress,
    required this.onMove,
    this.initialPage = 0,
  });

  final List<gcal.Event> allEvents;
  final int Function(gcal.Event e) progressOf;
  final Future<void> Function(BuildContext context, gcal.Event e) onEdit;
  final Future<void> Function(BuildContext context, gcal.Event e) onDelete;
  final Future<void> Function(BuildContext context, gcal.Event e, bool done) onToggleProgress;
  final Future<void> Function(BuildContext context, gcal.Event e, BoardBucket target) onMove;

  /// 0: 오늘, 1: 이번주, 2: 나중에, 3: 완료
  final int initialPage;

  @override
  State<DevBoardKanbanView> createState() => _DevBoardKanbanViewState();
}

class _DevBoardKanbanViewState extends State<DevBoardKanbanView> {
  late final PageController _pageController;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialPage.clamp(0, 3);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final buckets = _splitByBucket(widget.allEvents, widget.progressOf, now);

    final pages = <_BoardPageData>[
      _BoardPageData(
        title: '오늘',
        bucket: BoardBucket.today,
        events: buckets[BoardBucket.today]!,
      ),
      _BoardPageData(
        title: '이번주',
        bucket: BoardBucket.thisWeek,
        events: buckets[BoardBucket.thisWeek]!,
      ),
      _BoardPageData(
        title: '나중에',
        bucket: BoardBucket.later,
        events: buckets[BoardBucket.later]!,
      ),
      _BoardPageData(
        title: '완료',
        bucket: BoardBucket.done,
        events: buckets[BoardBucket.done]!,
      ),
    ];

    return Column(
      children: [
        _TopTabs(
          index: _index,
          pages: pages,
          onTap: (i) {
            setState(() => _index = i);
            _pageController.animateToPage(
              i,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: pages.length,
            itemBuilder: (context, i) {
              final p = pages[i];
              return _KanbanColumnPage(
                title: p.title,
                bucket: p.bucket,
                events: p.events,
                progressOf: widget.progressOf,
                onEdit: widget.onEdit,
                onDelete: widget.onDelete,
                onToggleProgress: widget.onToggleProgress,
                onMove: widget.onMove,
              );
            },
          ),
        ),
      ],
    );
  }

  /// 버킷 분류
  Map<BoardBucket, List<gcal.Event>> _splitByBucket(
      List<gcal.Event> source,
      int Function(gcal.Event e) progressOf,
      DateTime now,
      ) {
    final map = {
      BoardBucket.today: <gcal.Event>[],
      BoardBucket.thisWeek: <gcal.Event>[],
      BoardBucket.later: <gcal.Event>[],
      BoardBucket.done: <gcal.Event>[],
    };

    final today0 = DateTime(now.year, now.month, now.day);
    final tomorrow0 = today0.add(const Duration(days: 1));
    // 주 시작(월=1) ~ 다음 주 시작
    final weekStart = today0.subtract(Duration(days: today0.weekday - 1));
    final nextWeekStart = weekStart.add(const Duration(days: 7));

    for (final e in source) {
      final p = progressOf(e);
      if (p == 100) {
        map[BoardBucket.done]!.add(e);
        continue;
      }

      final s = _startLocal(e) ?? today0;

      if (s.isAfterOrEqual(today0) && s.isBefore(tomorrow0)) {
        map[BoardBucket.today]!.add(e);
      } else if (s.isAfterOrEqual(weekStart) && s.isBefore(nextWeekStart)) {
        map[BoardBucket.thisWeek]!.add(e);
      } else {
        map[BoardBucket.later]!.add(e);
      }
    }

    // 시작 시간 오름차순 정렬
    for (final k in map.keys) {
      map[k]!.sort((a, b) {
        final sa = _startLocal(a) ?? DateTime(1900);
        final sb = _startLocal(b) ?? DateTime(1900);
        return sa.compareTo(sb);
      });
    }
    return map;
  }

  static DateTime? _startLocal(gcal.Event e) {
    if (e.start?.dateTime != null) return e.start!.dateTime!.toLocal();
    if (e.start?.date != null) {
      final d = e.start!.date!;
      return DateTime(d.year, d.month, d.day);
    }
    return null;
  }
}

class _BoardPageData {
  _BoardPageData({required this.title, required this.bucket, required this.events});
  final String title;
  final BoardBucket bucket;
  final List<gcal.Event> events;
}

/// 상단 탭 (인디케이터 + 카운트)
class _TopTabs extends StatelessWidget {
  const _TopTabs({required this.index, required this.pages, required this.onTap});
  final int index;
  final List<_BoardPageData> pages;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.purple.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: List.generate(pages.length, (i) {
          final sel = i == index;
          final p = pages[i];
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: sel
                    ? BoxDecoration(
                  color: Colors.purple.shade100.withOpacity(.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.purple.shade200),
                )
                    : null,
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        p.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: sel ? Colors.purple.shade800 : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: sel ? Colors.purple.shade300 : Colors.purple.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${p.events.length}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// 실제 한 컬럼 페이지
class _KanbanColumnPage extends StatelessWidget {
  const _KanbanColumnPage({
    required this.title,
    required this.bucket,
    required this.events,
    required this.progressOf,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleProgress,
    required this.onMove,
  });

  final String title;
  final BoardBucket bucket;
  final List<gcal.Event> events;
  final int Function(gcal.Event e) progressOf;
  final Future<void> Function(BuildContext context, gcal.Event e) onEdit;
  final Future<void> Function(BuildContext context, gcal.Event e) onDelete;
  final Future<void> Function(BuildContext context, gcal.Event e, bool done) onToggleProgress;
  final Future<void> Function(BuildContext context, gcal.Event e, BoardBucket target) onMove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ColumnHeader(title: title, count: events.length),
        const Divider(height: 1),
        Expanded(
          child: DragTarget<gcal.Event>(
            onWillAccept: (_) => true,
            onAccept: (e) => onMove(context, e, bucket),
            builder: (context, candidate, rejected) {
              final isActive = candidate.isNotEmpty;
              return Container(
                decoration: BoxDecoration(
                  color: isActive ? Colors.purple.withOpacity(.05) : null,
                  border: isActive
                      ? Border(left: BorderSide(color: Colors.purple.withOpacity(.25), width: 3))
                      : null,
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: events.length,
                  itemBuilder: (context, i) {
                    final e = events[i];
                    return _DraggableEventCard(
                      event: e,
                      progress: progressOf(e),
                      onEdit: () => onEdit(context, e),
                      onDelete: () => onDelete(context, e),
                      onToggleDone: () => onToggleProgress(context, e, progressOf(e) != 100),
                      onMove: (t) => onMove(context, e, t),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      color: Colors.purple.shade50,
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.purple.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// 드래그 가능한 이벤트 카드 (다른 버킷으로 '이동' 메뉴 포함)
class _DraggableEventCard extends StatelessWidget {
  const _DraggableEventCard({
    required this.event,
    required this.progress,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleDone,
    required this.onMove,
  });

  final gcal.Event event;
  final int progress;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleDone;
  final void Function(BoardBucket target) onMove;

  @override
  Widget build(BuildContext context) {
    final title = event.summary?.trim().isNotEmpty == true ? event.summary!.trim() : '(제목 없음)';
    final subtitle = _formatWhen(event);
    final isDone = progress == 100;

    final card = Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.purple.shade50,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDone ? Colors.green.shade600 : Colors.purple.shade300,
            shape: BoxShape.circle,
          ),
          child: Icon(isDone ? Icons.check_rounded : Icons.drag_indicator_rounded, color: Colors.white, size: 18),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            decoration: isDone ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.grey.shade600,
            decoration: isDone ? TextDecoration.lineThrough : null,
          ),
        ),
        trailing: Wrap(
          spacing: 2,
          children: [
            IconButton(
              icon: Icon(isDone ? Icons.undo_rounded : Icons.done_rounded),
              tooltip: isDone ? '미완료로' : '완료하기',
              onPressed: onToggleDone,
              iconSize: 20,
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: '편집',
              onPressed: onEdit,
              iconSize: 20,
            ),
            PopupMenuButton<String>(
              tooltip: '이동',
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'today', child: Text('오늘로 이동')),
                const PopupMenuItem(value: 'week', child: Text('이번주로 이동')),
                const PopupMenuItem(value: 'later', child: Text('나중에로 이동')),
                const PopupMenuItem(value: 'done', child: Text('완료로 이동')),
              ],
              onSelected: (v) {
                switch (v) {
                  case 'today':
                    onMove(BoardBucket.today);
                    break;
                  case 'week':
                    onMove(BoardBucket.thisWeek);
                    break;
                  case 'later':
                    onMove(BoardBucket.later);
                    break;
                  case 'done':
                    onMove(BoardBucket.done);
                    break;
                }
              },
              icon: const Icon(Icons.more_vert, size: 20),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '삭제',
              onPressed: onDelete,
              iconSize: 20,
            ),
          ],
        ),
      ),
    );

    return LongPressDraggable<gcal.Event>(
      data: event,
      feedback: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Material(
          color: Colors.transparent,
          child: Opacity(opacity: .9, child: card),
        ),
      ),
      childWhenDragging: Opacity(opacity: .35, child: card),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      child: card,
    );
  }

  String _formatWhen(gcal.Event e) {
    if (e.start?.date != null) {
      // 종일
      final sd = e.start!.date!;
      return '종일 • ${sd.month}/${sd.day}';
    }
    final s = e.start?.dateTime?.toLocal();
    final en = e.end?.dateTime?.toLocal();
    if (s == null) return '';
    String hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (en != null) return '${hhmm(s)}–${hhmm(en)}';
    return hhmm(s);
  }
}

extension _Cmp on DateTime {
  bool isAfterOrEqual(DateTime other) => isAfter(other) || isAtSameMomentAs(other);
}
