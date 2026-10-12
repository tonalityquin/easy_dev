import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../application/single_inside_hot_key_summary_loader.dart';
import '../hot_keys/single_inside_hot_key_content.dart';

class SingleInsideHotKeyCard extends StatefulWidget {
  const SingleInsideHotKeyCard({
    super.key,
    required this.content,
    required this.summary,
    required this.loading,
    required this.onOpen,
    required this.onEdit,
  });

  final SingleInsideHotKeyContent? content;
  final SingleInsideHotKeySummary? summary;
  final bool loading;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  State<SingleInsideHotKeyCard> createState() => _SingleInsideHotKeyCardState();
}

class _SingleInsideHotKeyCardState extends State<SingleInsideHotKeyCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final active = widget.content != null;
    final accent = active
        ? _accent(tokens, widget.content!)
        : tokens.textDisabled;
    final onTap = active ? widget.onOpen : widget.onEdit;
    final label = active ? widget.content!.title : '빠른 실행 비어 있음';

    return Semantics(
      button: true,
      label: label,
      child: AnimatedScale(
        scale: _pressed ? .985 : 1,
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.enter,
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
          curve: CommonUiMotion.standard,
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: active ? tokens.surfaceRaised : tokens.surfaceDisabled,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? accent.withOpacity(.32) : tokens.borderSubtle,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: tokens.shadow.withOpacity(.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              onHighlightChanged: (value) {
                if (_pressed == value) return;
                setState(() => _pressed = value);
              },
              child: AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.component,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(
                    begin: const Offset(.025, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                child: active
                    ? _ActiveCard(
                        key: ValueKey<String>(widget.content!.name),
                        content: widget.content!,
                        summary: widget.summary,
                        loading: widget.loading,
                        accent: accent,
                      )
                    : const _EmptyCard(
                        key: ValueKey<String>('empty'),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _accent(CommonUiTokens tokens, SingleInsideHotKeyContent content) {
    switch (content) {
      case SingleInsideHotKeyContent.parkingArea:
        return tokens.accent;
      case SingleInsideHotKeyContent.workSchedule:
        return tokens.brandSecondary;
      case SingleInsideHotKeyContent.workRules:
        return tokens.accent;
      case SingleInsideHotKeyContent.workManual:
        return tokens.info;
      case SingleInsideHotKeyContent.workStartReport:
        return tokens.info;
      case SingleInsideHotKeyContent.workEndReport:
        return tokens.success;
      case SingleInsideHotKeyContent.commuteSubmit:
        return tokens.info;
      case SingleInsideHotKeyContent.restTimeSubmit:
        return tokens.success;
    }
  }
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({
    super.key,
    required this.content,
    required this.summary,
    required this.loading,
    required this.accent,
  });

  final SingleInsideHotKeyContent content;
  final SingleInsideHotKeySummary? summary;
  final bool loading;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final veryCompact = height < 88;
        final compact = height < 122;
        final horizontalPadding = veryCompact ? 8.0 : compact ? 10.0 : 12.0;
        final verticalPadding = veryCompact ? 6.0 : compact ? 8.0 : 10.0;
        final iconBox = veryCompact ? 24.0 : compact ? 27.0 : 30.0;
        final iconSize = veryCompact ? 15.0 : compact ? 17.0 : 18.0;
        final gap = veryCompact ? 4.0 : compact ? 6.0 : 8.0;
        final primary = summary == null
            ? '상태 확인 중'
            : '${summary!.status} · ${summary!.primary}';
        final secondary = summary?.secondary.trim() ?? '';

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: iconBox,
                    height: iconBox,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(content.icon, size: iconSize, color: accent),
                  ),
                  SizedBox(width: veryCompact ? 6 : 8),
                  Expanded(
                    child: Text(
                      content.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (compact ? text.labelLarge : text.titleSmall)
                          ?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: gap),
              Expanded(
                child: loading
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: veryCompact ? 15 : 18,
                          height: veryCompact ? 15 : 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, summaryConstraints) {
                          final showSecondary = !veryCompact &&
                              secondary.isNotEmpty &&
                              summaryConstraints.maxHeight >= 38;
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: compact ? 18 : 20,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      primary,
                                      maxLines: 1,
                                      style: (compact
                                              ? text.labelLarge
                                              : text.titleSmall)
                                          ?.copyWith(
                                        color: tokens.textPrimary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                                if (showSecondary) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    secondary,
                                    maxLines: compact ? 1 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(
                                      color: tokens.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 100;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_rounded,
                color: tokens.iconSecondary,
                size: compact ? 20 : 24,
              ),
              SizedBox(height: compact ? 3 : 6),
              Text(
                '비어 있음',
                maxLines: 1,
                style: text.labelLarge?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
