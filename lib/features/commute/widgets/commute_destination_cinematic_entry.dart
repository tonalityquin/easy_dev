import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../launcher/application/launcher_diagnostics.dart';

class CommuteDestinationCinematicEntry extends StatefulWidget {
  const CommuteDestinationCinematicEntry({
    super.key,
    required this.routeName,
    required this.child,
  });

  static const Duration renderDuration = Duration(milliseconds: 620);

  final String routeName;
  final Widget child;

  @override
  State<CommuteDestinationCinematicEntry> createState() =>
      _CommuteDestinationCinematicEntryState();
}

class _CommuteDestinationCinematicEntryState
    extends State<CommuteDestinationCinematicEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: CommuteDestinationCinematicEntry.renderDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    LauncherDiagnostics.record(
      'commute_workspace_render_start',
      scope: 'commute_workspace',
      meta: <String, Object?>{
        'route': widget.routeName,
        'durationMs':
            CommuteDestinationCinematicEntry.renderDuration.inMilliseconds,
        'reduceMotion': reduceMotion,
        'presentation': 'parkinworkin_branded_workspace',
      },
    );
    if (reduceMotion) {
      _controller.value = 1;
      LauncherDiagnostics.record(
        'commute_workspace_render_complete',
        scope: 'commute_workspace',
        meta: <String, Object?>{'route': widget.routeName},
      );
      return;
    }
    unawaited(
      _controller.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        LauncherDiagnostics.record(
          'commute_workspace_render_complete',
          scope: 'commute_workspace',
          meta: <String, Object?>{'route': widget.routeName},
        );
      }),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = reduceMotion ? 1.0 : _controller.value;
        final brand = Curves.easeOutCubic.transform(
          ((value - 0.04) / 0.42).clamp(0.0, 1.0).toDouble(),
        );
        final content = Curves.easeOutCubic.transform(
          ((value - 0.22) / 0.78).clamp(0.0, 1.0).toDouble(),
        );
        final overlayOpacity =
            (1 - ((value - 0.36) / 0.46).clamp(0.0, 1.0)).toDouble();
        final dy = 9.0 * (1 - content);
        final scale = 0.992 + (0.008 * content);

        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: tokens.canvas),
            Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                scale: scale,
                child: IgnorePointer(
                  ignoring: !reduceMotion && value < 0.92,
                  child: Opacity(
                    opacity: content,
                    child: child,
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: Opacity(
                opacity: overlayOpacity,
                child: ColoredBox(
                  color: tokens.surfaceRaised,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Opacity(
                      opacity: brand,
                      child: _WorkspaceBrandReveal(tokens: tokens),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

class _WorkspaceBrandReveal extends StatelessWidget {
  const _WorkspaceBrandReveal({required this.tokens});

  final CommonUiTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(
          bottom: BorderSide(color: tokens.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: Image.asset(
              'assets/images/ParkinWorkin_logo.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'ParkinWorkin',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Container(
            width: 42,
            height: 3,
            decoration: BoxDecoration(
              color: tokens.accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }
}
