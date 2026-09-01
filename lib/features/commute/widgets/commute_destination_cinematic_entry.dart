import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/tutorial/widgets/app_start_cinematic_reveal.dart';
import '../../launcher/application/launcher_diagnostics.dart';

class CommuteDestinationCinematicEntry extends StatefulWidget {
  const CommuteDestinationCinematicEntry({
    super.key,
    required this.routeName,
    required this.child,
  });

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
      duration: const Duration(milliseconds: 560),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    LauncherDiagnostics.record(
      'commute_route_enter_start',
      scope: 'commute_power',
      meta: <String, Object?>{
        'route': widget.routeName,
        'reduceMotion': reduceMotion,
      },
    );
    if (reduceMotion) {
      _controller.value = 1;
      LauncherDiagnostics.record(
        'commute_route_enter_complete',
        scope: 'commute_power',
        meta: <String, Object?>{'route': widget.routeName},
      );
      return;
    }
    unawaited(
      _controller.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        LauncherDiagnostics.record(
          'commute_route_enter_complete',
          scope: 'commute_power',
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
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final reveal = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return AppStartCinematicReveal(
      animation: reveal,
      reduceMotion: reduceMotion,
      child: widget.child,
    );
  }
}
