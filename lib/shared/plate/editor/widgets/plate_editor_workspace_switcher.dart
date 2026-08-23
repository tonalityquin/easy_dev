import 'package:flutter/material.dart';

enum PlateEditorWorkspaceTransitionStyle {
  ordered,
  overviewHub,
}

class PlateEditorWorkspaceSwitcher extends StatefulWidget {
  const PlateEditorWorkspaceSwitcher({
    super.key,
    required this.activeKey,
    required this.activeOrder,
    required this.child,
    this.style = PlateEditorWorkspaceTransitionStyle.ordered,
    this.duration = const Duration(milliseconds: 170),
    this.hierarchyDuration = const Duration(milliseconds: 185),
    this.peerDuration = const Duration(milliseconds: 150),
  });

  final String activeKey;
  final int activeOrder;
  final Widget child;
  final PlateEditorWorkspaceTransitionStyle style;
  final Duration duration;
  final Duration hierarchyDuration;
  final Duration peerDuration;

  @override
  State<PlateEditorWorkspaceSwitcher> createState() => _PlateEditorWorkspaceSwitcherState();
}

class _PlateEditorWorkspaceSwitcherState extends State<PlateEditorWorkspaceSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Widget? _previousChild;
  Widget? _currentChild;
  String? _currentKey;
  int _currentOrder = 0;
  double _direction = 1;
  double _distance = 8;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _currentChild = widget.child;
    _currentKey = widget.activeKey;
    _currentOrder = widget.activeOrder;
    _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant PlateEditorWorkspaceSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentKey == widget.activeKey) {
      _currentChild = widget.child;
      return;
    }

    final previousKey = _currentKey ?? '';
    final nextKey = widget.activeKey;
    _previousChild = _currentChild;

    if (widget.style == PlateEditorWorkspaceTransitionStyle.overviewHub) {
      final previousOverview = previousKey == 'overview';
      final nextOverview = nextKey == 'overview';
      if (previousOverview && !nextOverview) {
        _direction = 1;
        _distance = 10;
        _controller.duration = widget.hierarchyDuration;
      } else if (!previousOverview && nextOverview) {
        _direction = -1;
        _distance = 10;
        _controller.duration = widget.hierarchyDuration;
      } else {
        _direction = 0;
        _distance = 0;
        _controller.duration = widget.peerDuration;
      }
    } else {
      _direction = widget.activeOrder >= _currentOrder ? 1 : -1;
      _distance = 8;
      _controller.duration = widget.duration;
    }

    _currentChild = widget.child;
    _currentKey = nextKey;
    _currentOrder = widget.activeOrder;
    _controller
      ..stop()
      ..value = 0
      ..forward().whenComplete(() {
        if (!mounted) return;
        setState(() => _previousChild = null);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      return KeyedSubtree(
        key: ValueKey<String>(widget.activeKey),
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        final children = <Widget>[];
        final previous = _previousChild;
        if (previous != null) {
          children.add(
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 1 - t,
                  child: Transform.translate(
                    offset: Offset(-_distance * _direction * t, 0),
                    child: previous,
                  ),
                ),
              ),
            ),
          );
        }
        final current = _currentChild ?? widget.child;
        children.add(
          Positioned.fill(
            child: Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(_distance * _direction * (1 - t), 0),
                child: current,
              ),
            ),
          ),
        );
        return ClipRect(child: Stack(children: children));
      },
    );
  }
}
