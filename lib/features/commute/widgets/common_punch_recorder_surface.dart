import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/common_ui/common_ui_theme.dart';

enum CommonPunchSlotState {
  actionable,
  completed,
  completedActionable,
  readOnly,
  disabled,
  loading,
}

enum CommonPunchTone {
  info,
  warning,
  danger,
}

class CommonPunchSlotData {
  const CommonPunchSlotData({
    required this.label,
    required this.icon,
    required this.tone,
    required this.state,
    this.time,
    this.statusLabel,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final CommonPunchTone tone;
  final CommonPunchSlotState state;
  final String? time;
  final String? statusLabel;
  final Future<void> Function()? onTap;
}

class CommonPunchRecorderSurface extends StatelessWidget {
  const CommonPunchRecorderSurface({
    super.key,
    required this.slots,
    this.title = '출퇴근 기록기',
    this.dateLabel,
    this.onDateTap,
    this.loading = false,
    this.embedded = false,
    this.margin,
    this.onDeveloperStatus,
  });

  final List<CommonPunchSlotData> slots;
  final String title;
  final String? dateLabel;
  final VoidCallback? onDateTap;
  final bool loading;
  final bool embedded;
  final EdgeInsetsGeometry? margin;
  final Future<void> Function()? onDeveloperStatus;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final neutralText = cs.onSurfaceVariant;
    final neutralBorder = cs.outlineVariant;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.access_time,
              size: 16,
              color: neutralText.withOpacity(.85),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if ((dateLabel ?? '').trim().isNotEmpty)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onDateTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 14,
                        color: neutralText.withOpacity(.85),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        dateLabel!,
                        style: TextStyle(
                          fontSize: 12,
                          color: neutralText.withOpacity(.85),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          switchInCurve: CommonUiMotion.enter,
          switchOutCurve: CommonUiMotion.exit,
          transitionBuilder: (child, animation) {
            if (reduceMotion) return child;
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .025),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: loading
              ? const Padding(
                  key: ValueKey<String>('punch_loading'),
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : Container(
                  key: const ValueKey<String>('punch_slots'),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: neutralBorder.withOpacity(.55),
                      width: .9,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < slots.length; index++) ...[
                        if (index > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _CommonPunchSlot(data: slots[index]),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );

    final surface = embedded
        ? content
        : Card(
            elevation: 0,
            color: cs.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: neutralBorder.withOpacity(.55)),
            ),
            margin: margin ?? const EdgeInsets.symmetric(vertical: 12),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: content,
            ),
          );

    if (onDeveloperStatus == null) return surface;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () async {
        HapticFeedback.mediumImpact();
        await onDeveloperStatus?.call();
      },
      child: surface,
    );
  }
}

class _CommonPunchSlot extends StatefulWidget {
  const _CommonPunchSlot({required this.data});

  final CommonPunchSlotData data;

  @override
  State<_CommonPunchSlot> createState() => _CommonPunchSlotState();
}

class _CommonPunchSlotState extends State<_CommonPunchSlot> {
  bool _pressed = false;

  bool get _enabled =>
      (widget.data.state == CommonPunchSlotState.actionable ||
          widget.data.state == CommonPunchSlotState.completedActionable) &&
      widget.data.onTap != null;

  bool get _punched {
    final time = (widget.data.time ?? '').trim();
    return time.isNotEmpty ||
        widget.data.state == CommonPunchSlotState.completed ||
        widget.data.state == CommonPunchSlotState.completedActionable ||
        widget.data.state == CommonPunchSlotState.readOnly;
  }

  bool get _loading => widget.data.state == CommonPunchSlotState.loading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final accent = _accent(widget.data.tone);
    final borderColor = _punched
        ? accent.withOpacity(.85)
        : cs.outlineVariant.withOpacity(_enabled ? .70 : .35);
    final bgColor = _punched ? accent.withOpacity(.08) : cs.surface;
    final statusLabel = _loading ? '처리 중' : (_punched ? '펀칭 완료' : '미펀칭');
    final semantics = <String>[
      widget.data.label,
      statusLabel,
      if ((widget.data.time ?? '').trim().isNotEmpty) widget.data.time!.trim(),
      if ((widget.data.statusLabel ?? '').trim().isNotEmpty)
        widget.data.statusLabel!.trim(),
    ].join(', ');

    return Semantics(
      button: _enabled,
      enabled: _enabled,
      label: semantics,
      child: Opacity(
        opacity: _enabled ? 1 : .45,
        child: AnimatedScale(
          scale: _pressed ? .985 : 1,
          duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
          curve: CommonUiMotion.enter,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _enabled
                ? () async {
                    await widget.data.onTap?.call();
                  }
                : null,
            onHighlightChanged: (value) {
              if (!_enabled || _pressed == value) return;
              setState(() => _pressed = value);
            },
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: borderColor,
                  width: _punched ? 1.1 : .8,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _icon(widget.data.tone),
                        size: 14,
                        color: _enabled
                            ? accent.withOpacity(.92)
                            : cs.onSurfaceVariant.withOpacity(.35),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          widget.data.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _enabled
                                ? accent.withOpacity(.92)
                                : cs.onSurfaceVariant.withOpacity(.35),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    switchInCurve: CommonUiMotion.enter,
                    switchOutCurve: CommonUiMotion.exit,
                    transitionBuilder: (child, animation) {
                      if (reduceMotion) return child;
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: .9, end: 1)
                              .animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: _loading
                        ? SizedBox(
                            key: const ValueKey<String>('loading'),
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accent.withOpacity(.95),
                            ),
                          )
                        : Icon(
                            _punched
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked,
                            key: ValueKey<bool>(_punched),
                            size: 18,
                            color: _punched
                                ? accent.withOpacity(.95)
                                : cs.outlineVariant
                                    .withOpacity(_enabled ? .9 : .4),
                          ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    child: Text(
                      statusLabel,
                      key: ValueKey<String>(statusLabel),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _punched
                                ? cs.onSurface
                                : cs.onSurfaceVariant,
                          ),
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


  IconData _icon(CommonPunchTone tone) {
    switch (tone) {
      case CommonPunchTone.info:
        return Icons.login;
      case CommonPunchTone.warning:
        return Icons.free_breakfast;
      case CommonPunchTone.danger:
        return Icons.logout;
    }
  }

  Color _accent(CommonPunchTone tone) {
    switch (tone) {
      case CommonPunchTone.info:
        return const Color(0xFF09367D);
      case CommonPunchTone.warning:
        return const Color(0xFFF2A93B);
      case CommonPunchTone.danger:
        return const Color(0xFFEF6C53);
    }
  }
}
