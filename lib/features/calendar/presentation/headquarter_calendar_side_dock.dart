import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/utils/status_dialog.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
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
        subtitle: '선택 날짜의 전체 일정',
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
            const CommonSideDockSection(
              title: '전체 일정',
              subtitle: '선택 날짜의 일정을 시간순으로 확인합니다.',
              order: 1,
              child: SizedBox.shrink(),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: entries.isEmpty
                  ? const _DockEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.only(right: 2, bottom: 4),
                      physics: const BouncingScrollPhysics(),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return CommonSideDockReveal(
                          order: index + 2,
                          child: _DockEventTile(
                            entry: entry,
                            onTap: () => _openEntry(entry),
                          ),
                        );
                      },
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

class _DockEventTile extends StatefulWidget {
  const _DockEventTile({
    required this.entry,
    required this.onTap,
  });

  final HeadquarterCalendarDockEntry entry;
  final Future<void> Function() onTap;

  @override
  State<_DockEventTile> createState() => _DockEventTileState();
}

class _DockEventTileState extends State<_DockEventTile> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final entry = widget.entry;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: FocusableActionDetector(
        onShowHoverHighlight: (value) {
          if (mounted) setState(() => _hovered = value);
        },
        onShowFocusHighlight: (value) {
          if (mounted) setState(() => _focused = value);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          child: AnimatedScale(
            scale: _pressed ? .985 : 1,
            duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
            curve: CommonUiMotion.standard,
            child: AnimatedContainer(
              duration: duration,
              curve: CommonUiMotion.enter,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: _hovered
                    ? tokens.surfaceSelected
                    : Color.alphaBlend(
                        entry.color.withOpacity(.06),
                        tokens.surfaceRaised,
                      ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _focused
                      ? tokens.focusRing
                      : entry.color.withOpacity(_hovered ? .34 : .20),
                  width: _focused ? 2 : 1,
                ),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: tokens.shadow.withOpacity(tokens.isDark ? .22 : .08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : const [],
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: duration,
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: entry.color.withOpacity(.12),
                      borderRadius: BorderRadius.circular(11),
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
                  AnimatedSlide(
                    duration: duration,
                    offset: _hovered ? const Offset(.12, 0) : Offset.zero,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: tokens.textSecondary,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockEmptyState extends StatelessWidget {
  const _DockEmptyState();

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
