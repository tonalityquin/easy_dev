import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/utils/status_dialog.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../selector/application/dev_auth.dart';

@immutable
class HeadquarterCalendarDockEntry {
  const HeadquarterCalendarDockEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.task = false,
    this.readOnly = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Future<void> Function() onTap;
  final bool task;
  final bool readOnly;
}

class HeadquarterCalendarSideDockDiagnostics {
  static const int _limit = 180;
  static final List<String> _lines = <String>[];

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static void log(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final line =
        '[HQ_CALENDAR][${DateTime.now().toIso8601String()}] $normalized';
    _lines.add(line);
    if (_lines.length > _limit) {
      _lines.removeRange(0, _lines.length - _limit);
    }
    debugPrint(line);
  }

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[HQ_CALENDAR] 기록된 로그가 없습니다.')});';
    }
    return _lines.map((line) => 'debugPrint(${jsonEncode(line)});').join('\n');
  }

  static Future<void> showStatus(
    BuildContext context, {
    required String title,
    required String description,
  }) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    await StatusDialog.showSuccess(
      context,
      title: title,
      description: description,
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}

Future<void> showHeadquarterCalendarSideDock({
  required BuildContext context,
  required DateTime selectedDay,
  required Listenable listenable,
  required List<HeadquarterCalendarDockEntry> Function() entriesBuilder,
  required Future<void> Function() onAdd,
  required CommonSideDockPresentationController presentationController,
}) async {
  HeadquarterCalendarSideDockDiagnostics.log(
    'dock_open date=${selectedDay.toIso8601String()} count=${entriesBuilder().length}',
  );
  await showCommonLeftSideDock<void>(
    context: context,
    barrierLabel: '선택 날짜 일정',
    maxWidth: 430,
    widthFactor: .94,
    presentationController: presentationController,
    builder: (dockContext) => _HeadquarterCalendarSideDock(
      selectedDay: selectedDay,
      listenable: listenable,
      entriesBuilder: entriesBuilder,
      onAdd: onAdd,
      presentationController: presentationController,
    ),
  );
  HeadquarterCalendarSideDockDiagnostics.log(
    'dock_closed date=${selectedDay.toIso8601String()} count=${entriesBuilder().length}',
  );
}

class _HeadquarterCalendarSideDock extends StatefulWidget {
  const _HeadquarterCalendarSideDock({
    required this.selectedDay,
    required this.listenable,
    required this.entriesBuilder,
    required this.onAdd,
    required this.presentationController,
  });

  final DateTime selectedDay;
  final Listenable listenable;
  final List<HeadquarterCalendarDockEntry> Function() entriesBuilder;
  final Future<void> Function() onAdd;
  final CommonSideDockPresentationController presentationController;

  @override
  State<_HeadquarterCalendarSideDock> createState() =>
      _HeadquarterCalendarSideDockState();
}

class _HeadquarterCalendarSideDockState
    extends State<_HeadquarterCalendarSideDock> {
  bool _developerMode = false;
  bool _adding = false;

  static const List<String> _weekdays = <String>[
    '일',
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
  ];

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_handleSourceChanged);
    _loadDeveloperMode();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_handleSourceChanged);
    super.dispose();
  }

  void _handleSourceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDeveloperMode() async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!mounted) return;
    setState(() => _developerMode = enabled);
  }

  String get _dateTitle {
    final day = widget.selectedDay;
    return '${day.month}월 ${day.day}일 ${_weekdays[day.weekday % 7]}요일';
  }

  Future<void> _showStatus() async {
    HeadquarterCalendarSideDockDiagnostics.log(
      'status_dialog date=${widget.selectedDay.toIso8601String()} count=${widget.entriesBuilder().length}',
    );
    await HeadquarterCalendarSideDockDiagnostics.showStatus(
      context,
      title: '일정 Side Dock 상태',
      description:
          '선택 날짜 $_dateTitle · 전체 ${widget.entriesBuilder().length}개 일정의 debugPrint 코드를 복사할 수 있습니다.',
    );
  }

  Future<void> _openEntry(HeadquarterCalendarDockEntry entry) async {
    HeadquarterCalendarSideDockDiagnostics.log(
      'event_open id=${entry.id} date=${widget.selectedDay.toIso8601String()}',
    );
    HapticFeedback.selectionClick();
    widget.presentationController.hide();
    try {
      await entry.onTap();
    } finally {
      widget.presentationController.show();
      HeadquarterCalendarSideDockDiagnostics.log(
        'event_closed id=${entry.id} date=${widget.selectedDay.toIso8601String()}',
      );
    }
  }

  Future<void> _add() async {
    if (_adding) return;
    setState(() => _adding = true);
    HeadquarterCalendarSideDockDiagnostics.log(
      'create_open date=${widget.selectedDay.toIso8601String()}',
    );
    widget.presentationController.hide();
    try {
      await widget.onAdd();
    } finally {
      widget.presentationController.show();
      HeadquarterCalendarSideDockDiagnostics.log(
        'create_closed date=${widget.selectedDay.toIso8601String()}',
      );
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final entries = widget.entriesBuilder();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: CommonSideDockFrame(
        title: _dateTitle,
        subtitle: '',
        icon: Icons.calendar_month_rounded,
        onClose: () => Navigator.of(context).pop(),
        onLongPress: _developerMode ? _showStatus : null,
        headerAction: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CountPill(count: entries.length),
            if (_developerMode) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: _showStatus,
                tooltip: '상태',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.bug_report_outlined,
                  color: tokens.textSecondary,
                  size: 19,
                ),
              ),
            ],
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                    ? Duration.zero
                    : CommonUiMotion.selection,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, .025),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: entries.isEmpty
                    ? const _DockEmptyState(
                        key: ValueKey<String>('calendar-dock-empty'),
                      )
                    : KeyedSubtree(
                        key: ValueKey<String>(
                          'calendar-dock-${entries.map((entry) => entry.id).join("|")}',
                        ),
                        child: ListView(
                          padding: const EdgeInsets.only(right: 2, bottom: 4),
                          physics: const BouncingScrollPhysics(),
                          children: [
                            CommonSideDockReveal(
                              order: 1,
                              child: OpsDockListSurface(
                                child: Column(
                                  children: [
                                    for (var index = 0;
                                        index < entries.length;
                                        index++) ...[
                                      if (index > 0)
                                        Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: tokens.borderSubtle,
                                        ),
                                      _DockEventTile(
                                        entry: entries[index],
                                        onTap: () =>
                                            _openEntry(entries[index]),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
        footer: CommonSideDockPrimaryFooter(
          child: CommonButton(
            label: '일정 추가',
            icon: Icons.add_rounded,
            onPressed: _adding ? null : _add,
            loading: _adding,
            expand: true,
            haptic: CommonHaptic.selection,
          ),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.accentContainer,
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(color: tokens.accent.withOpacity(.28)),
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .96, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: Text(
          '$count개',
          key: ValueKey<int>(count),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tokens.onAccentContainer,
                fontWeight: FontWeight.w900,
              ),
        ),
      ),
    );
  }
}

class _DockEventTile extends StatelessWidget {
  const _DockEventTile({
    required this.entry,
    required this.onTap,
  });

  final HeadquarterCalendarDockEntry entry;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return OpsDockSelectableRowSurface(
      selected: false,
      selectionColor: entry.color,
      selectedContainer: entry.color.withOpacity(.12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: entry.color.withOpacity(.10),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(entry.icon, color: entry.color, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (entry.task)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.bolt_rounded, color: entry.color, size: 17),
            )
          else if (entry.readOnly)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                Icons.lock_outline_rounded,
                color: tokens.textSecondary,
                size: 17,
              ),
            ),
          Icon(
            Icons.chevron_right_rounded,
            color: tokens.textSecondary,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _DockEmptyState extends StatelessWidget {
  const _DockEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Text(
        '선택한 날짜에 일정이 없습니다.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: tokens.textSecondary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
