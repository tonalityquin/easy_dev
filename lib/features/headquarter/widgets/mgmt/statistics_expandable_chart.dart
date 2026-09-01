import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';

typedef StatisticsExpandedChartBuilder = Widget Function(
  BuildContext context,
  bool landscape,
);

class StatisticsChartInteractionLog {
  static final List<String> _lines = <String>[];

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static void log(String message) {
    final line = '[StatisticsChart] $message';
    _lines.add(line);
    if (_lines.length > 120) {
      _lines.removeRange(0, _lines.length - 120);
    }
    debugPrint(line);
  }
}

class StatisticsExpandableChart extends StatelessWidget {
  final String title;
  final String subtitle;
  final String debugLabel;
  final Widget preview;
  final StatisticsExpandedChartBuilder expandedBuilder;
  final BorderRadius borderRadius;

  const StatisticsExpandableChart({
    super.key,
    required this.title,
    required this.subtitle,
    required this.debugLabel,
    required this.preview,
    required this.expandedBuilder,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '$title 그래프 크게 보기',
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: () => _open(context),
          child: Stack(
            children: [
              preview,
              Positioned(
                top: 6,
                right: 6,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(.94),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.open_in_full_rounded,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    HapticFeedback.selectionClick();
    final orientation = MediaQuery.of(context).orientation;
    StatisticsChartInteractionLog.log(
      'dialog_open chart=$debugLabel orientation=${orientation.name}',
    );
    await showStatisticsExpandedChartDialog(
      context: context,
      title: title,
      subtitle: subtitle,
      debugLabel: debugLabel,
      builder: expandedBuilder,
    );
    StatisticsChartInteractionLog.log('dialog_close chart=$debugLabel');
  }
}

Future<void> showStatisticsExpandedChartDialog({
  required BuildContext context,
  required String title,
  required String subtitle,
  required String debugLabel,
  required StatisticsExpandedChartBuilder builder,
}) async {
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  final duration = reduceMotion ? Duration.zero : CommonUiMotion.component;
  await showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Theme.of(context).colorScheme.scrim.withOpacity(.42),
    transitionDuration: duration,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _StatisticsExpandedChartDialogBody(
        title: title,
        subtitle: subtitle,
        debugLabel: debugLabel,
        builder: builder,
      );
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      if (reduceMotion) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: CommonUiMotion.enter,
        reverseCurve: CommonUiMotion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: .965, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _StatisticsExpandedChartDialogBody extends StatelessWidget {
  final String title;
  final String subtitle;
  final String debugLabel;
  final StatisticsExpandedChartBuilder builder;

  const _StatisticsExpandedChartDialogBody({
    required this.title,
    required this.subtitle,
    required this.debugLabel,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final landscape = media.orientation == Orientation.landscape;
    final phone = media.size.shortestSide < 600;
    final reduceMotion = media.disableAnimations;
    final width = math.min(
      landscape ? media.size.width * .96 : media.size.width * .94,
      1180.0,
    ).toDouble();
    final height = math.min(
      landscape ? media.size.height * .92 : media.size.height * .86,
      820.0,
    ).toDouble();
    StatisticsChartInteractionLog.log(
      'dialog_layout chart=$debugLabel orientation=${media.orientation.name} width=${width.round()} height=${height.round()}',
    );
    return Center(
      child: Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: landscape ? 14 : 12,
          vertical: landscape ? 8 : 20,
        ),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
          curve: CommonUiMotion.standard,
          width: width,
          height: height,
          color: cs.surface,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  landscape ? 20 : 18,
                  landscape ? 10 : 14,
                  8,
                  landscape ? 8 : 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: landscape ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                child: !landscape && phone
                    ? Container(
                        key: const ValueKey<String>('portrait-advice'),
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.screen_rotation_alt_rounded,
                              size: 18,
                              color: cs.onSecondaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '휴대폰을 가로로 돌리면 축과 선택값을 더 넓게 볼 수 있습니다.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSecondaryContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey<String>('landscape-advice-hidden'),
                      ),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    landscape ? 18 : 12,
                    landscape ? 12 : 10,
                    landscape ? 18 : 12,
                    landscape ? 12 : 14,
                  ),
                  child: builder(context, landscape),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StatisticsChartSelectionPanel extends StatelessWidget {
  final String title;
  final List<String> values;
  final IconData icon;

  const StatisticsChartSelectionPanel({
    super.key,
    required this.title,
    required this.values,
    this.icon = Icons.touch_app_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AnimatedContainer(
      duration: MediaQuery.maybeOf(context)?.disableAnimations == true
          ? Duration.zero
          : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (values.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 12,
                    runSpacing: 3,
                    children: [
                      for (final value in values)
                        Text(
                          value,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
