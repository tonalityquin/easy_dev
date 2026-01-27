import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../../hubs_mode/dev_package/debug_package/debug_action_recorder.dart';
import '../../../../../single_mode/utils/att_brk_repository.dart';

void _traceTriplePunch(BuildContext context, AttBrkModeType type, DateTime dateTime) {
  final String name;
  switch (type) {
    case AttBrkModeType.workIn:
      name = 'Triple 출근 펀칭';
      break;
    case AttBrkModeType.breakTime:
      name = 'Triple 휴게 펀칭';
      break;
    case AttBrkModeType.workOut:
      name = 'Triple 퇴근 펀칭';
      break;
  }

  DebugActionRecorder.instance.recordAction(
    name,
    route: ModalRoute.of(context)?.settings.name,
    meta: <String, dynamic>{
      'screen': 'triple_dashboard_punch_card_feedback',
      'action': 'punch_feedback_show',
      'type': type.toString(),
      'at': dateTime.toIso8601String(),
    },
  );
}

Future<void> showTripleDashboardPunchCardFeedback(
    BuildContext context, {
      required AttBrkModeType type,
      required DateTime dateTime,
    }) async {
  _traceTriplePunch(context, type, dateTime);

  HapticFeedback.mediumImpact();
  SystemSound.play(SystemSoundType.click);

  final cs = Theme.of(context).colorScheme;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'triple_punch_card_feedback',
    barrierColor: cs.scrim.withOpacity(0.35),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (ctx, anim, secondaryAnim) {
      return _PunchCardSheet(
        type: type,
        dateTime: dateTime,
      );
    },
    transitionBuilder: (ctx, anim, secondaryAnim, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1.0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

String _typeLabel(AttBrkModeType type) {
  switch (type) {
    case AttBrkModeType.workIn:
      return '출근 펀칭';
    case AttBrkModeType.workOut:
      return '퇴근 펀칭';
    case AttBrkModeType.breakTime:
      return '휴게 펀칭';
  }
}

IconData _iconForType(AttBrkModeType type) {
  switch (type) {
    case AttBrkModeType.workIn:
      return Icons.login;
    case AttBrkModeType.workOut:
      return Icons.logout;
    case AttBrkModeType.breakTime:
      return Icons.free_breakfast;
  }
}

Color _accentColorForType(AttBrkModeType type) {
  switch (type) {
    case AttBrkModeType.workIn:
      return const Color(0xFF09367D);
    case AttBrkModeType.workOut:
      return const Color(0xFFEF6C53);
    case AttBrkModeType.breakTime:
      return const Color(0xFFF2A93B);
  }
}

String _weekdayKo(DateTime dt) {
  const days = ['월', '화', '수', '목', '금', '토', '일'];
  return days[dt.weekday - 1];
}

class _PunchCardSheet extends StatefulWidget {
  final AttBrkModeType type;
  final DateTime dateTime;

  const _PunchCardSheet({
    required this.type,
    required this.dateTime,
  });

  @override
  State<_PunchCardSheet> createState() => _PunchCardSheetState();
}

class _PunchCardSheetState extends State<_PunchCardSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sheetScale;
  late final Animation<double> _headDrop;
  late final Animation<double> _flash;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _sheetScale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);

    _headDrop = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeInOutBack),
    );

    _flash = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 1.0, curve: Curves.easeOutQuad),
    );

    _controller.forward();

    Future.microtask(() async {
      await Future.delayed(const Duration(milliseconds: 950));
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _punchedWorkIn => widget.type == AttBrkModeType.workIn;
  bool get _punchedBreak => widget.type == AttBrkModeType.breakTime;
  bool get _punchedWorkOut => widget.type == AttBrkModeType.workOut;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accentColor = _accentColorForType(widget.type);
    final typeIcon = _iconForType(widget.type);
    final typeLabel = _typeLabel(widget.type);

    final textTheme = Theme.of(context).textTheme;
    final date = widget.dateTime;
    final dateStr = DateFormat('MM.dd').format(date);
    final weekDayStr = _weekdayKo(date);
    final monthStr = DateFormat('yyyy.MM').format(date);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Align(
          alignment: Alignment.topCenter,
          child: ScaleTransition(
            scale: _sheetScale,
            child: Material(
              color: Colors.transparent,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final headDy = lerpDouble(-32, 0, _headDrop.value) ?? 0;
                  final flashStrength = _flash.value;

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: cs.shadow.withOpacity(0.18),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                        border: Border.all(color: cs.outlineVariant.withOpacity(0.75), width: 1),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.translate(
                            offset: Offset(0, headDy),
                            child: Opacity(
                              opacity: 0.90,
                              child: Container(
                                width: 68,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: cs.onSurface.withOpacity(0.88),
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: cs.shadow.withOpacity(0.30),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Icon(typeIcon, size: 18, color: cs.surface),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          Row(
                            children: [
                              Text(
                                '출퇴근기록카드',
                                style: textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                monthStr,
                                style: textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: accentColor.withOpacity(0.12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: accentColor.withOpacity(0.35),
                                      blurRadius: 6 * flashStrength,
                                      offset: Offset(0, 2 * flashStrength),
                                    ),
                                  ],
                                ),
                                child: Icon(typeIcon, color: accentColor, size: 18),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$typeLabel · 카드에 펀칭이 찍혔습니다.',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          Container(
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.outlineVariant.withOpacity(0.75), width: 0.9),
                              boxShadow: [
                                BoxShadow(
                                  color: cs.shadow.withOpacity(0.06),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerLow,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                  ),
                                  child: Row(
                                    children: const [
                                      _HeaderCell(label: '일자', flex: 3),
                                      _HeaderCell(label: '출근', flex: 3),
                                      _HeaderCell(label: '휴게', flex: 3),
                                      _HeaderCell(label: '퇴근', flex: 3),
                                    ],
                                  ),
                                ),
                                Divider(height: 1, thickness: 0.8, color: cs.outlineVariant.withOpacity(0.75)),

                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              dateStr,
                                              style: textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: cs.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              weekDayStr,
                                              style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                                            ),
                                          ],
                                        ),
                                      ),

                                      Expanded(
                                        flex: 3,
                                        child: _PunchStatusCell(
                                          punched: _punchedWorkIn,
                                          label: '출근',
                                          accentColor: _accentColorForType(AttBrkModeType.workIn),
                                          highlighted: widget.type == AttBrkModeType.workIn,
                                          flashStrength: flashStrength,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: _PunchStatusCell(
                                          punched: _punchedBreak,
                                          label: '휴게',
                                          accentColor: _accentColorForType(AttBrkModeType.breakTime),
                                          highlighted: widget.type == AttBrkModeType.breakTime,
                                          flashStrength: flashStrength,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: _PunchStatusCell(
                                          punched: _punchedWorkOut,
                                          label: '퇴근',
                                          accentColor: _accentColorForType(AttBrkModeType.workOut),
                                          highlighted: widget.type == AttBrkModeType.workOut,
                                          flashStrength: flashStrength,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '펀칭 완료',
                              style: textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;

  const _HeaderCell({
    required this.label,
    this.flex = 3,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w900,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _PunchStatusCell extends StatelessWidget {
  final bool punched;
  final String label;
  final Color accentColor;
  final bool highlighted;
  final double flashStrength;

  const _PunchStatusCell({
    required this.punched,
    required this.label,
    required this.accentColor,
    required this.highlighted,
    required this.flashStrength,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final showCheck = punched;
    final glow = highlighted ? flashStrength : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      alignment: Alignment.center,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: highlighted ? accentColor.withOpacity(0.15 + 0.20 * glow) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: highlighted && glow > 0
              ? [
            BoxShadow(
              color: accentColor.withOpacity(0.40 * glow),
              blurRadius: 8 * glow,
              offset: Offset(0, 3 * glow),
            ),
          ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              showCheck ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              size: 16,
              color: showCheck ? accentColor.withOpacity(0.95) : cs.outlineVariant.withOpacity(0.9),
            ),
            const SizedBox(height: 2),
            Text(
              showCheck ? label : '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: showCheck ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
