// lib/screens/head_package/calendar_package/board_kanban_view.dart
import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

import '../../dev_package/debug_package/debug_api_logger.dart';

@immutable
class _BoardTokens {
  const _BoardTokens({
    required this.divider,
    required this.surface,
    required this.surfaceLow,
    required this.surfaceVariant,

    required this.text,
    required this.textSub,
    required this.textMuted,

    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,

    required this.badgeBgSelected,
    required this.badgeFgSelected,
    required this.badgeBg,
    required this.badgeFg,

    required this.todoDot,
    required this.todoDotFg,
    required this.doneDot,
    required this.doneDotFg,

    required this.cardTint,
  });

  final Color divider;

  final Color surface;
  final Color surfaceLow;
  final Color surfaceVariant;

  final Color text;
  final Color textSub;
  final Color textMuted;

  final Color accent;
  final Color onAccent;
  final Color accentContainer;
  final Color onAccentContainer;

  final Color badgeBgSelected;
  final Color badgeFgSelected;
  final Color badgeBg;
  final Color badgeFg;

  final Color todoDot;
  final Color todoDotFg;
  final Color doneDot;
  final Color doneDotFg;

  final Color cardTint;

  factory _BoardTokens.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ✅ 회사 캘린더 보드도 “브랜드테마”로 일관: primary 기반
    final accent = cs.primary;
    final onAccent = cs.onPrimary;

    final accentContainer = cs.primaryContainer;
    final onAccentContainer = cs.onPrimaryContainer;

    // 배지: 선택은 primary, 비선택은 surfaceVariant 계열
    final badgeBgSelected = accent;
    final badgeFgSelected = onAccent;

    final badgeBg = cs.surfaceVariant;
    final badgeFg = cs.onSurfaceVariant;

    // 도트: 미완료는 secondary, 완료는 primary(강조)
    final todoDot = cs.secondary;
    final todoDotFg = cs.onSecondary;
    final doneDot = accent;
    final doneDotFg = onAccent;

    final surfaceLow = cs.surfaceContainerLow;
    final cardTint = Color.alphaBlend(accent.withOpacity(0.08), cs.surface);

    return _BoardTokens(
      divider: cs.outlineVariant,

      surface: cs.surface,
      surfaceLow: surfaceLow,
      surfaceVariant: cs.surfaceVariant,

      text: cs.onSurface,
      textSub: cs.onSurfaceVariant,
      textMuted: cs.onSurfaceVariant.withOpacity(0.85),

      accent: accent,
      onAccent: onAccent,
      accentContainer: accentContainer,
      onAccentContainer: onAccentContainer,

      badgeBgSelected: badgeBgSelected,
      badgeFgSelected: badgeFgSelected,
      badgeBg: badgeBg,
      badgeFg: badgeFg,

      todoDot: todoDot,
      todoDotFg: todoDotFg,
      doneDot: doneDot,
      doneDotFg: doneDotFg,

      cardTint: cardTint,
    );
  }
}

/// 보드 버킷 정의
enum BoardBucket { today, thisWeek, later, done }

/// progress 추출, 완료 토글 콜백(onToggleProgress)만 외부에서 주입
/// - "한 화면에 한 컬럼"만 보여주고, PageView 스와이프로 칼럼 전환
class BoardKanbanView extends StatefulWidget {
  const BoardKanbanView({
    super.key,
    required this.allEvents,
    required this.progressOf,
    required this.onToggleProgress,
    this.initialPage = 0,
  });

  final List<gcal.Event> allEvents;
  final int Function(gcal.Event e) progressOf;
  final Future<void> Function(BuildContext context, gcal.Event e, bool done) onToggleProgress;

  /// 0: 오늘, 1: 이번주, 2: 나중에, 3: 완료
  final int initialPage;

  @override
  State<BoardKanbanView> createState() => _BoardKanbanViewState();
}

class _BoardKanbanViewState extends State<BoardKanbanView> {
  late final PageController _pageController;
  late int _index;

  // ─────────────────────────────────────────────────────────────
  // ✅ API 디버그 로직: 표준 태그 / 로깅 헬퍼
  // ─────────────────────────────────────────────────────────────
  static const String _tCal = 'calendar';
  static const String _tKanban = 'calendar/kanban';
  static const String _tUi = 'calendar/ui';
  static const String _tBucket = 'calendar/kanban/bucket';

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
      // ignore
    }
  }

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
    final tokens = _BoardTokens.of(context);
    final now = DateTime.now();

    late final Map<BoardBucket, List<gcal.Event>> buckets;
    try {
      buckets = _splitByBucket(widget.allEvents, widget.progressOf, now);
    } catch (e) {
      _logApiError(
        tag: 'BoardKanbanView._splitByBucket',
        message: 'Kanban 버킷 분류 실패(예외)',
        error: e,
        extra: <String, dynamic>{
          'eventsCount': widget.allEvents.length,
          'now': now.toIso8601String(),
        },
        tags: const <String>[_tCal, _tKanban, _tBucket],
      );

      buckets = <BoardBucket, List<gcal.Event>>{
        BoardBucket.today: <gcal.Event>[],
        BoardBucket.thisWeek: <gcal.Event>[],
        BoardBucket.later: <gcal.Event>[],
        BoardBucket.done: <gcal.Event>[],
      };
    }

    final pages = <_BoardPageData>[
      _BoardPageData(title: '오늘', bucket: BoardBucket.today, events: buckets[BoardBucket.today] ?? <gcal.Event>[]),
      _BoardPageData(title: '이번주', bucket: BoardBucket.thisWeek, events: buckets[BoardBucket.thisWeek] ?? <gcal.Event>[]),
      _BoardPageData(title: '나중에', bucket: BoardBucket.later, events: buckets[BoardBucket.later] ?? <gcal.Event>[]),
      _BoardPageData(title: '완료', bucket: BoardBucket.done, events: buckets[BoardBucket.done] ?? <gcal.Event>[]),
    ];

    return Column(
      children: [
        _TopTabs(
          index: _index,
          pages: pages,
          onTap: (i) async {
            try {
              setState(() => _index = i);
              _pageController.animateToPage(
                i,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
            } catch (e) {
              await _logApiError(
                tag: 'BoardKanbanView._TopTabs.onTap',
                message: '탭 전환(animateToPage) 실패',
                error: e,
                extra: <String, dynamic>{
                  'targetIndex': i,
                  'currentIndex': _index,
                },
                tags: const <String>[_tCal, _tKanban, _tUi],
              );
            }
          },
        ),
        Divider(height: 1, color: tokens.divider),
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: (i) {
              try {
                setState(() => _index = i);
              } catch (e) {
                _logApiError(
                  tag: 'BoardKanbanView.onPageChanged',
                  message: '페이지 전환 상태 반영(setState) 실패',
                  error: e,
                  extra: <String, dynamic>{'targetIndex': i},
                  tags: const <String>[_tCal, _tKanban, _tUi],
                );
              }
            },
            children: [
              for (final p in pages)
                _KanbanColumnPage(
                  title: p.title,
                  bucket: p.bucket,
                  events: p.events,
                  progressOf: widget.progressOf,
                  onToggleProgress: widget.onToggleProgress,
                ),
            ],
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
    final map = <BoardBucket, List<gcal.Event>>{
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
    final tokens = _BoardTokens.of(context);

    return Container(
      color: tokens.surfaceLow,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: List.generate(pages.length, (i) {
          final sel = i == index;
          final p = pages[i];

          final tabBg = sel ? tokens.accentContainer : Colors.transparent;
          final tabBorder = sel ? tokens.accent.withOpacity(0.30) : Colors.transparent;

          final titleColor = sel ? tokens.accent : tokens.text;
          final badgeBg = sel ? tokens.badgeBgSelected : tokens.badgeBg;
          final badgeFg = sel ? tokens.badgeFgSelected : tokens.badgeFg;

          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: tabBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tabBorder),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        p.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${p.events.length}',
                          style: TextStyle(
                            color: badgeFg,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
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

/// 실제 한 컬럼 페이지 (완료 토글 버튼만 유지)
class _KanbanColumnPage extends StatelessWidget {
  const _KanbanColumnPage({
    required this.title,
    required this.bucket,
    required this.events,
    required this.progressOf,
    required this.onToggleProgress,
  });

  final String title;
  final BoardBucket bucket;
  final List<gcal.Event> events;
  final int Function(gcal.Event e) progressOf;
  final Future<void> Function(BuildContext context, gcal.Event e, bool done) onToggleProgress;

  @override
  Widget build(BuildContext context) {
    final tokens = _BoardTokens.of(context);

    return Column(
      children: [
        _ColumnHeader(title: title, count: events.length),
        Divider(height: 1, color: tokens.divider),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: events.length,
            itemBuilder: (context, i) {
              final e = events[i];
              return _EventCard(
                event: e,
                progress: progressOf(e),
                onToggleDone: () async {
                  await _safeToggleProgress(context, e, progressOf(e) != 100, onToggleProgress);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

Future<void> _safeToggleProgress(
    BuildContext context,
    gcal.Event e,
    bool nextDone,
    Future<void> Function(BuildContext context, gcal.Event e, bool done) onToggleProgress,
    ) async {
  try {
    await onToggleProgress(context, e, nextDone);
  } catch (err) {
    try {
      await DebugApiLogger().log(
        <String, dynamic>{
          'tag': 'BoardKanbanView.onToggleProgress',
          'message': '칸반 완료 토글 실패',
          'error': err.toString(),
          'extra': <String, dynamic>{
            'eventId': e.id ?? '',
            'summaryLen': (e.summary ?? '').trim().length,
            'targetDone': nextDone,
          },
        },
        level: 'error',
        tags: const <String>['calendar', 'calendar/kanban', 'calendar/action'],
      );
    } catch (_) {}
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = _BoardTokens.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      color: tokens.surfaceLow,
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: tokens.text,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: tokens.badgeBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: tokens.badgeFg,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.progress,
    required this.onToggleDone,
  });

  final gcal.Event event;
  final int progress;
  final VoidCallback onToggleDone;

  @override
  Widget build(BuildContext context) {
    final tokens = _BoardTokens.of(context);

    final title = event.summary?.trim().isNotEmpty == true ? event.summary!.trim() : '(제목 없음)';
    final subtitle = _formatWhen(event);
    final isDone = progress == 100;

    final dotBg = isDone ? tokens.doneDot : tokens.todoDot;
    final dotFg = isDone ? tokens.doneDotFg : tokens.todoDotFg;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: tokens.surface,
      surfaceTintColor: tokens.cardTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tokens.divider.withOpacity(0.85)),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: dotBg,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isDone ? Icons.check_rounded : Icons.circle_outlined,
            color: dotFg,
            size: 18,
          ),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: tokens.text,
            decoration: isDone ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.textSub,
            decoration: isDone ? TextDecoration.lineThrough : null,
          ),
        ),
        trailing: IconButton(
          icon: Icon(isDone ? Icons.undo_rounded : Icons.done_rounded),
          tooltip: isDone ? '미완료로' : '완료하기',
          onPressed: onToggleDone,
          iconSize: 20,
        ),
      ),
    );
  }

  String _formatWhen(gcal.Event e) {
    if (e.start?.date != null) {
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
