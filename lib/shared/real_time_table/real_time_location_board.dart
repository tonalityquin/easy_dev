import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/utils/status_dialog.dart';
import '../../features/location/domain/models/grid_rect.dart';
import '../../features/location/domain/models/location_model.dart';
import '../../features/location/domain/models/parking_grid_model.dart';
import '../../features/selector/application/dev_auth.dart';
import '../parking_dot_map/parking_status_dot_map_surface.dart';
import 'real_time_sort_state.dart';
import 'real_time_table_row_vm.dart';
import 'real_time_table_zone.dart';

const double _kZoneTouchTargetMin = 44.0;
const double _kParentPageLockDistance = 10.0;
const double _kParentPageTriggerFraction = .16;
const double _kParentPageMinVelocity = 520.0;

class RealTimeLocationBoard extends StatefulWidget {
  const RealTimeLocationBoard({
    super.key,
    required this.groups,
    required this.onPlateTap,
    required this.onParentPageChanged,
    required this.onUserActivity,
    this.onAutoPauseStart,
    this.onAutoPauseEnd,
  });

  final List<ZoneGroupVM> groups;
  final ValueChanged<RealTimeRowVM> onPlateTap;
  final void Function(String parent, int index, int count) onParentPageChanged;
  final VoidCallback onUserActivity;
  final VoidCallback? onAutoPauseStart;
  final VoidCallback? onAutoPauseEnd;

  @override
  State<RealTimeLocationBoard> createState() => _RealTimeLocationBoardState();
}

class _RealTimeLocationBoardState extends State<RealTimeLocationBoard> {
  final PageController _pageController = PageController();
  final Map<String, bool> _parentInteractionLocked = <String, bool>{};
  final Set<int> _activePointers = <int>{};
  final List<String> _debugLines = <String>[];
  int _pageIndex = 0;
  String _activeParent = '';
  int? _pagingPointer;
  Offset? _pagingStartPosition;
  Offset? _pagingLastPosition;
  Duration? _pagingLastTimestamp;
  double _pagingVelocityX = 0;
  double _pagingStartPixels = 0;
  int _pagingOriginIndex = 0;
  bool _pagingLocked = false;
  bool _pagingRejected = false;
  bool _rawPagingInProgress = false;
  bool _pageSettleInProgress = false;
  bool _suppressPageChanged = false;
  bool _debugDialogShowing = false;

  bool get _currentParentInteractionLocked => _activeParent.isNotEmpty &&
      (_parentInteractionLocked[_activeParent] ?? false);

  @override
  void initState() {
    super.initState();
    if (widget.groups.isNotEmpty) {
      _activeParent = widget.groups.first.group;
    }
    _debugLog(
      'board_initialized',
      <String, Object?>{
        'parents': widget.groups.length,
        'activeParent': _activeParent,
        'interaction': 'parent_child_slot',
        'childFocusAutoPause': true,
        'systemBackPolicy': 'child_to_parent',
        'firebaseAdditionalRead': 0,
      },
    );
    unawaited(
      DevAuth.isDevModeEnabled().then<void>((enabled) {
        _debugLog(
          'developer_mode_resolved',
          <String, Object?>{'enabled': enabled},
        );
      }),
    );
  }

  @override
  void didUpdateWidget(covariant RealTimeLocationBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final validParents = widget.groups.map((group) => group.group).toSet();
    _parentInteractionLocked.removeWhere(
      (key, value) => !validParents.contains(key),
    );
    _resetPagingCandidate();
    if (widget.groups.isEmpty) {
      _pageIndex = 0;
      _activeParent = '';
      _debugLog('board_updated_empty');
      return;
    }
    var nextIndex = _activeParent.isEmpty
        ? _pageIndex.clamp(0, widget.groups.length - 1).toInt()
        : widget.groups.indexWhere((group) => group.group == _activeParent);
    if (nextIndex < 0) {
      nextIndex = _pageIndex.clamp(0, widget.groups.length - 1).toInt();
    }
    if (nextIndex == _pageIndex &&
        _activeParent == widget.groups[nextIndex].group) {
      return;
    }
    _pageIndex = nextIndex;
    _activeParent = widget.groups[nextIndex].group;
    _debugLog(
      'board_parent_reconciled',
      <String, Object?>{
        'parent': _activeParent,
        'index': _pageIndex,
        'count': widget.groups.length,
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(_pageIndex);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _debugLog(
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {
    final buffer = StringBuffer()
      ..write('[RealTimeLocationBoard] ')
      ..write(DateTime.now().toIso8601String())
      ..write(' event=')
      ..write(event);
    for (final entry in details.entries) {
      if (entry.value == null) continue;
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('=')
        ..write(entry.value);
    }
    final line = buffer.toString();
    _debugLines.add(line);
    if (_debugLines.length > 180) {
      _debugLines.removeRange(0, _debugLines.length - 180);
    }
    debugPrint(line);
  }

  String get _debugPrintCode => _debugLines
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');

  Future<void> _showDeveloperDebugDialog() async {
    if (!mounted || _debugDialogShowing || _debugLines.isEmpty) return;
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !mounted || _debugDialogShowing) return;
    _debugLog(
      'developer_status_dialog_opened',
      <String, Object?>{
        'activeParent': _activeParent,
        'page': _pageIndex + 1,
        'count': widget.groups.length,
        'autoTransitionPaused': true,
      },
    );
    final code = _debugPrintCode.trim();
    if (code.isEmpty) return;
    _debugDialogShowing = true;
    widget.onAutoPauseStart?.call();
    try {
      await StatusDialog.showSuccess(
        context,
        title: '구역 DOT MAP 디버그',
        description: _debugLines.join('\n'),
        copyText: code,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: const Duration(seconds: 45),
        useCommonUi: true,
      );
    } finally {
      widget.onAutoPauseEnd?.call();
      widget.onUserActivity();
      _debugDialogShowing = false;
      _debugLog(
        'developer_status_dialog_closed',
        <String, Object?>{
          'activeParent': _activeParent,
          'page': _pageIndex + 1,
          'count': widget.groups.length,
          'autoTransitionPaused': _currentParentInteractionLocked,
        },
      );
    }
  }

  void _commitPageChanged(int index) {
    if (index < 0 || index >= widget.groups.length) return;
    if (_pageIndex == index && _activeParent == widget.groups[index].group) {
      return;
    }
    setState(() {
      _pageIndex = index;
      _activeParent = widget.groups[index].group;
    });
    widget.onUserActivity();
    HapticFeedback.selectionClick();
    _debugLog(
      'parent_page_changed',
      <String, Object?>{
        'parent': widget.groups[index].group,
        'index': index,
        'count': widget.groups.length,
        'stage': 'parent_overview',
      },
    );
    widget.onParentPageChanged(
      widget.groups[index].group,
      index,
      widget.groups.length,
    );
  }

  void _onPageChanged(int index) {
    if (_suppressPageChanged || _rawPagingInProgress) return;
    _commitPageChanged(index);
  }

  void _onParentInteractionLockChanged(String parent, bool locked) {
    if (_parentInteractionLocked[parent] == locked) return;
    _parentInteractionLocked[parent] = locked;
    _debugLog(
      'parent_interaction_lock_changed',
      <String, Object?>{
        'parent': parent,
        'locked': locked,
      },
    );
    if (parent == _activeParent && mounted) {
      setState(() {});
    }
  }

  void _resetPagingCandidate() {
    _pagingPointer = null;
    _pagingStartPosition = null;
    _pagingLastPosition = null;
    _pagingLastTimestamp = null;
    _pagingVelocityX = 0;
    _pagingLocked = false;
    _pagingRejected = false;
  }

  void _restorePagingOriginImmediately() {
    if (!_pageController.hasClients || widget.groups.isEmpty) return;
    final origin = _pagingOriginIndex.clamp(0, widget.groups.length - 1).toInt();
    _suppressPageChanged = true;
    _rawPagingInProgress = false;
    _pageController.jumpToPage(origin);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _suppressPageChanged = false;
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) {
      if (_pagingLocked) {
        _restorePagingOriginImmediately();
      }
      _resetPagingCandidate();
      widget.onUserActivity();
      return;
    }
    if (widget.groups.length < 2 ||
        _currentParentInteractionLocked ||
        _pageSettleInProgress ||
        !_pageController.hasClients) {
      return;
    }
    _pagingPointer = event.pointer;
    _pagingStartPosition = event.position;
    _pagingLastPosition = event.position;
    _pagingLastTimestamp = event.timeStamp;
    _pagingVelocityX = 0;
    _pagingStartPixels = _pageController.position.pixels;
    _pagingOriginIndex = _pageIndex;
    _pagingLocked = false;
    _pagingRejected = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pagingPointer != event.pointer ||
        _activePointers.length != 1 ||
        _currentParentInteractionLocked ||
        _pageSettleInProgress ||
        !_pageController.hasClients) {
      return;
    }
    final start = _pagingStartPosition;
    if (start == null || _pagingRejected) return;
    final delta = event.position - start;
    if (!_pagingLocked) {
      if (delta.distance < _kParentPageLockDistance) return;
      if (delta.dx.abs() <= delta.dy.abs() * 1.15) {
        _pagingRejected = true;
        return;
      }
      _pagingLocked = true;
      _rawPagingInProgress = true;
      widget.onUserActivity();
    }

    final lastPosition = _pagingLastPosition;
    final lastTimestamp = _pagingLastTimestamp;
    if (lastPosition != null && lastTimestamp != null) {
      final micros =
          event.timeStamp.inMicroseconds - lastTimestamp.inMicroseconds;
      if (micros > 0) {
        _pagingVelocityX =
            (event.position.dx - lastPosition.dx) * 1000000 / micros;
      }
    }
    _pagingLastPosition = event.position;
    _pagingLastTimestamp = event.timeStamp;

    final position = _pageController.position;
    final target = (_pagingStartPixels - delta.dx)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((target - position.pixels).abs() > .01) {
      position.jumpTo(target);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_pagingPointer != event.pointer) return;
    final start = _pagingStartPosition;
    final locked = _pagingLocked;
    final rejected = _pagingRejected;
    final velocity = _pagingVelocityX;
    final end = event.position;
    if (!locked || rejected || start == null) {
      _resetPagingCandidate();
      return;
    }
    _settleRawPageDrag(
      distanceX: end.dx - start.dx,
      velocityX: velocity,
      canceled: false,
    );
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (_pagingPointer != event.pointer) return;
    final locked = _pagingLocked;
    if (!locked) {
      _resetPagingCandidate();
      return;
    }
    _settleRawPageDrag(
      distanceX: 0,
      velocityX: 0,
      canceled: true,
    );
  }

  Future<void> _settleRawPageDrag({
    required double distanceX,
    required double velocityX,
    required bool canceled,
  }) async {
    if (!_pageController.hasClients || widget.groups.isEmpty) {
      _rawPagingInProgress = false;
      _resetPagingCandidate();
      return;
    }
    _pageSettleInProgress = true;
    final position = _pageController.position;
    final pageExtent =
        position.viewportDimension * _pageController.viewportFraction;
    final threshold = math.max(
      _kZoneTouchTargetMin,
      pageExtent * _kParentPageTriggerFraction,
    );
    var target = _pagingOriginIndex;
    if (!canceled &&
        (distanceX.abs() >= threshold ||
            velocityX.abs() >= _kParentPageMinVelocity)) {
      target += distanceX < 0 ||
              (distanceX.abs() < threshold && velocityX < 0)
          ? 1
          : -1;
    }
    target = target.clamp(0, widget.groups.length - 1).toInt();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _resetPagingCandidate();
    try {
      if (reduceMotion) {
        _pageController.jumpToPage(target);
      } else {
        await _pageController.animateToPage(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      _rawPagingInProgress = false;
      _pageSettleInProgress = false;
    }
    if (!mounted) return;
    _commitPageChanged(target);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) {
      return const _InlineEmpty(message: '표시할 주차 구역 데이터가 없습니다.');
    }

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final currentIndex = _pageIndex.clamp(0, widget.groups.length - 1).toInt();
    final multiple = widget.groups.length > 1;

    Widget slide(int index) {
      final group = widget.groups[index];
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: _ParentMapSlide(
          key: ValueKey<String>('parent-slide:${group.group}'),
          group: group,
          index: index,
          count: widget.groups.length,
          onPlateTap: widget.onPlateTap,
          onUserActivity: widget.onUserActivity,
          onAutoPauseStart: widget.onAutoPauseStart,
          onAutoPauseEnd: widget.onAutoPauseEnd,
          onInteractionLockChanged: (locked) {
            _onParentInteractionLockChanged(group.group, locked);
          },
          onDebugLog: _debugLog,
          onDeveloperDebugTap: _showDeveloperDebugDialog,
        ),
      );
    }

    final pager = PageView.builder(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.groups.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) => slide(index),
    );

    return Column(
      children: [
        Expanded(
          child: multiple
              ? Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  child: pager,
                )
              : slide(0),
        ),
        if (multiple) ...[
          _PageIndicator(
            count: widget.groups.length,
            index: currentIndex,
            reduceMotion: reduceMotion,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ParentMapSlide extends StatefulWidget {
  const _ParentMapSlide({
    super.key,
    required this.group,
    required this.index,
    required this.count,
    required this.onPlateTap,
    required this.onUserActivity,
    required this.onInteractionLockChanged,
    required this.onDebugLog,
    required this.onDeveloperDebugTap,
    this.onAutoPauseStart,
    this.onAutoPauseEnd,
  });

  final ZoneGroupVM group;
  final int index;
  final int count;
  final ValueChanged<RealTimeRowVM> onPlateTap;
  final VoidCallback onUserActivity;
  final ValueChanged<bool> onInteractionLockChanged;
  final VoidCallback? onAutoPauseStart;
  final VoidCallback? onAutoPauseEnd;
  final void Function(String, [Map<String, Object?>]) onDebugLog;
  final VoidCallback onDeveloperDebugTap;

  @override
  State<_ParentMapSlide> createState() => _ParentMapSlideState();
}

class _ParentMapSlideState extends State<_ParentMapSlide> {
  String? _focusedZoneKey;
  bool _focusAutoPauseActive = false;
  bool _tickerModeEnabled = true;

  ZoneVM? get _focusedZone {
    final key = _focusedZoneKey;
    if (key == null) return null;
    for (final zone in widget.group.zones) {
      if (zone.fullName == key) return zone;
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.of(context);
    if (_tickerModeEnabled && !enabled && _focusedZoneKey != null) {
      final previous = _focusedZoneKey;
      _focusedZoneKey = null;
      RealTimeChildFocusBackGuard.unregister(this);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _endFocusAutoPause(
          source: 'tab_inactive',
          childKey: previous,
        );
        widget.onInteractionLockChanged(false);
        widget.onDebugLog(
          'child_focus_released_after_tab_change',
          <String, Object?>{
            'parent': widget.group.group,
            'childKey': previous,
            'autoTransitionPaused': false,
          },
        );
      });
    }
    _tickerModeEnabled = enabled;
  }

  @override
  void didUpdateWidget(covariant _ParentMapSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusedZoneKey == null) return;
    final exists = widget.group.zones.any(
      (zone) => zone.fullName == _focusedZoneKey,
    );
    if (exists) return;
    final previous = _focusedZoneKey;
    _focusedZoneKey = null;
    RealTimeChildFocusBackGuard.unregister(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _endFocusAutoPause(
        source: 'data_update',
        childKey: previous,
      );
      widget.onInteractionLockChanged(false);
      widget.onDebugLog(
        'child_focus_released_after_data_update',
        <String, Object?>{
          'parent': widget.group.group,
          'childKey': previous,
          'autoTransitionPaused': false,
        },
      );
    });
  }

  @override
  void dispose() {
    _endFocusAutoPause(
      source: 'dispose',
      childKey: _focusedZoneKey,
    );
    super.dispose();
  }

  void _startFocusAutoPause(ZoneVM zone) {
    if (_focusAutoPauseActive) return;
    _focusAutoPauseActive = true;
    RealTimeChildFocusBackGuard.register(this, () {
      if (!mounted || _focusedZoneKey == null) return;
      widget.onDebugLog(
        'system_back_intercepted',
        <String, Object?>{
          'parent': widget.group.group,
          'child': _focusedZone?.child,
          'action': 'close_child_focus',
          'returnStage': 'parent_overview',
        },
      );
      _closeFocus(source: 'system_back');
    });
    widget.onAutoPauseStart?.call();
    widget.onDebugLog(
      'child_focus_auto_pause_started',
      <String, Object?>{
        'parent': zone.group,
        'child': zone.child,
        'reason': 'child_focus',
        'autoTransitionPaused': true,
      },
    );
  }

  void _endFocusAutoPause({
    required String source,
    String? childKey,
  }) {
    RealTimeChildFocusBackGuard.unregister(this);
    if (!_focusAutoPauseActive) return;
    _focusAutoPauseActive = false;
    widget.onAutoPauseEnd?.call();
    widget.onDebugLog(
      'child_focus_auto_pause_ended',
      <String, Object?>{
        'parent': widget.group.group,
        'childKey': childKey,
        'source': source,
        'autoTransitionPaused': false,
      },
    );
  }

  void _focusZone(ZoneVM zone) {
    if (_focusedZoneKey == zone.fullName) return;
    final grid = widget.group.parentSource?.parkingGrid;
    final viewport = grid == null ? null : _effectiveChildRect(zone, grid);
    if (viewport == null) {
      widget.onDebugLog(
        'child_focus_rejected',
        <String, Object?>{
          'parent': zone.group,
          'child': zone.child,
          'reason': 'child_rect_unavailable',
          'childSlots': zone.source.childSlots.length,
        },
      );
      return;
    }
    _startFocusAutoPause(zone);
    setState(() => _focusedZoneKey = zone.fullName);
    widget.onInteractionLockChanged(true);
    widget.onUserActivity();
    HapticFeedback.selectionClick();
    widget.onDebugLog(
      'child_focus_opened',
      <String, Object?>{
        'parent': zone.group,
        'child': zone.child,
        'viewport': viewport.toKey(),
        'viewportSource': zone.source.childRect != null
            ? 'child_rect'
            : 'child_slots_bounds',
        'slots': zone.source.childSlots.length,
        'occupied': zone.rows.length,
        'firebaseAdditionalRead': 0,
        'autoTransitionPaused': true,
      },
    );
  }

  void _closeFocus({String source = 'header_back'}) {
    final zone = _focusedZone;
    final childKey = _focusedZoneKey;
    if (childKey == null) return;
    setState(() => _focusedZoneKey = null);
    _endFocusAutoPause(
      source: source,
      childKey: childKey,
    );
    widget.onInteractionLockChanged(false);
    widget.onUserActivity();
    HapticFeedback.selectionClick();
    widget.onDebugLog(
      'child_focus_closed',
      <String, Object?>{
        'parent': widget.group.group,
        'child': zone?.child,
        'source': source,
        'returnStage': 'parent_overview',
        'autoTransitionPaused': false,
      },
    );
  }

  void _handlePlateTap(_OccupiedSlot occupied) {
    widget.onUserActivity();
    HapticFeedback.selectionClick();
    widget.onDebugLog(
      'child_slot_tapped',
      <String, Object?>{
        'parent': occupied.zone.group,
        'child': occupied.zone.child,
        'slot': occupied.slot.no,
        'plateId': occupied.row.plateId,
        'plateNumber': occupied.row.plateNumber,
        'plateLast4': _plateLast4(occupied.row.plateNumber),
        'action': 'open_status_side_dock',
      },
    );
    widget.onPlateTap(occupied.row);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final focused = _focusedZone;
    final transitionDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            height: 34,
            child: Row(
              children: [
                if (focused != null)
                  Semantics(
                    button: true,
                    label: '${focused.child}에서 ${widget.group.group}으로 돌아가기',
                    child: IconButton(
                      onPressed: () => _closeFocus(source: 'header_back'),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 34,
                        height: 34,
                      ),
                      splashRadius: 18,
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    ),
                  ),
                if (focused != null) const SizedBox(width: 4),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: transitionDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      if (reduceMotion) return child;
                      final slide = Tween<Offset>(
                        begin: const Offset(.035, 0),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child: focused == null
                        ? Text(
                            widget.group.group,
                            key: ValueKey<String>(
                              'parent-title:${widget.group.group}',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        : Row(
                            key: ValueKey<String>(
                              'child-title:${focused.fullName}',
                            ),
                            children: [
                              Flexible(
                                child: Text(
                                  widget.group.group,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.labelLarge?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 5),
                                child: Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  focused.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleSmall?.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                '${focused.current}/${focused.capacity}',
                                style: text.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const <FontFeature>[
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: DevAuth.devModeEnabled,
                  builder: (context, enabled, _) {
                    if (!enabled) return const SizedBox.shrink();
                    return Semantics(
                      button: true,
                      label: '구역 DOT MAP 디버그 상태',
                      child: IconButton(
                        onPressed: widget.onDeveloperDebugTap,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 34,
                          height: 34,
                        ),
                        splashRadius: 18,
                        icon: Icon(
                          Icons.bug_report_outlined,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
                if (widget.count > 1) ...[
                  const SizedBox(width: 5),
                  Text(
                    '${widget.index + 1} / ${widget.count}',
                    style: text.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 7),
        Expanded(
          child: _ParentMapPage(
            group: widget.group,
            focusedZone: focused,
            onZoneTap: _focusZone,
            onPlateTap: _handlePlateTap,
            reduceMotion: reduceMotion,
          ),
        ),
      ],
    );
  }
}

class _ParentMapPage extends StatelessWidget {
  const _ParentMapPage({
    required this.group,
    required this.focusedZone,
    required this.onZoneTap,
    required this.onPlateTap,
    required this.reduceMotion,
  });

  final ZoneGroupVM group;
  final ZoneVM? focusedZone;
  final ValueChanged<ZoneVM> onZoneTap;
  final ValueChanged<_OccupiedSlot> onPlateTap;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final grid = group.parentSource?.parkingGrid;
    if (grid == null || grid.rows <= 0 || grid.cols <= 0) {
      return const _InlineEmpty(message: '부모 주차 구역 DOT MAP 데이터가 없습니다.');
    }

    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final focused = focusedZone;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AnimatedSwitcher(
        duration: duration,
        reverseDuration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          if (reduceMotion) return child;
          final scale = Tween<double>(begin: .965, end: 1).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
          );
          final slide = Tween<Offset>(
            begin: const Offset(.025, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
          );
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: slide,
              child: ScaleTransition(scale: scale, child: child),
            ),
          );
        },
        child: focused == null
            ? _ParentOverviewDotMap(
                key: ValueKey<String>('overview:${group.group}'),
                group: group,
                grid: grid,
                onZoneTap: onZoneTap,
                reduceMotion: reduceMotion,
              )
            : _ChildFocusDotMap(
                key: ValueKey<String>('child:${focused.fullName}'),
                zone: focused,
                grid: grid,
                onPlateTap: onPlateTap,
                reduceMotion: reduceMotion,
              ),
      ),
    );
  }
}

class _ParentOverviewDotMap extends StatelessWidget {
  const _ParentOverviewDotMap({
    super.key,
    required this.group,
    required this.grid,
    required this.onZoneTap,
    required this.reduceMotion,
  });

  final ZoneGroupVM group;
  final ParkingGridModel grid;
  final ValueChanged<ZoneVM> onZoneTap;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final occupied = _occupiedSlots(group);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final layout = ParkingStatusDotMapLayout.resolve(
          size: size,
          grid: grid,
        );
        final zones = layout == null
            ? const <_ResolvedChildZone>[]
            : _resolveChildZones(
                zones: group.zones,
                grid: grid,
                layout: layout,
                minimum: _kZoneTouchTargetMin,
              );
        final labels = layout == null
            ? const <_ResolvedOccupiedSlot>[]
            : _resolveOccupiedLabels(
                occupied: occupied,
                layout: layout,
              );

        return SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: ParkingStatusDotMapSurface(grid: grid),
              ),
              for (final entry in zones)
                _ChildZoneVisualOverlay(
                  key: ValueKey<String>('zone-visual:${entry.zone.fullName}'),
                  entry: entry,
                  reduceMotion: reduceMotion,
                ),
              for (final entry in labels)
                _OccupiedSlotLabel(
                  key: ValueKey<String>(
                    'overview-label:${entry.slot.zone.fullName}:${entry.slot.slot.no}:${entry.slot.row.plateId}',
                  ),
                  entry: entry,
                  reduceMotion: reduceMotion,
                ),
              for (final entry in zones)
                _ChildZoneHitOverlay(
                  key: ValueKey<String>('zone-hit:${entry.zone.fullName}'),
                  entry: entry,
                  onTap: () => onZoneTap(entry.zone),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ChildFocusDotMap extends StatelessWidget {
  const _ChildFocusDotMap({
    super.key,
    required this.zone,
    required this.grid,
    required this.onPlateTap,
    required this.reduceMotion,
  });

  final ZoneVM zone;
  final ParkingGridModel grid;
  final ValueChanged<_OccupiedSlot> onPlateTap;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final viewport = _effectiveChildRect(zone, grid);
    if (viewport == null) {
      return const _InlineEmpty(message: '자식 주차 구역 DOT MAP 데이터가 없습니다.');
    }
    final occupied = _occupiedSlotsForZone(zone);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final layout = ParkingStatusDotMapLayout.resolve(
          size: size,
          grid: grid,
          viewport: viewport,
        );
        final resolved = layout == null
            ? const <_ResolvedOccupiedSlot>[]
            : _resolveOccupiedSlots(
                occupied: occupied,
                layout: layout,
                minimum: _kZoneTouchTargetMin,
              );

        return SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: ParkingStatusDotMapSurface(
                  grid: grid,
                  viewport: viewport,
                ),
              ),
              for (final entry in resolved)
                _OccupiedSlotOverlay(
                  key: ValueKey<String>(
                    'child-slot:${entry.slot.zone.fullName}:${entry.slot.slot.no}:${entry.slot.row.plateId}',
                  ),
                  entry: entry,
                  onTap: () => onPlateTap(entry.slot),
                  reduceMotion: reduceMotion,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.count,
    required this.index,
    required this.reduceMotion,
  });

  final int count;
  final int index;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          AnimatedContainer(
            duration:
                reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: i == index ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index
                  ? cs.primary
                  : cs.onSurfaceVariant.withOpacity(.28),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          if (i != count - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _OccupiedSlot {
  const _OccupiedSlot({
    required this.zone,
    required this.slot,
    required this.row,
  });

  final ZoneVM zone;
  final ChildSlot slot;
  final RealTimeRowVM row;
}

class _ResolvedOccupiedSlot {
  const _ResolvedOccupiedSlot({
    required this.slot,
    required this.visualRect,
    required this.hitRect,
  });

  final _OccupiedSlot slot;
  final Rect visualRect;
  final Rect hitRect;
}

class _ResolvedChildZone {
  const _ResolvedChildZone({
    required this.zone,
    required this.visualRect,
    required this.hitRect,
  });

  final ZoneVM zone;
  final Rect visualRect;
  final Rect hitRect;
}

class _ChildZoneVisualOverlay extends StatelessWidget {
  const _ChildZoneVisualOverlay({
    super.key,
    required this.entry,
    required this.reduceMotion,
  });

  final _ResolvedChildZone entry;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 190);
    final showLabel = entry.visualRect.width >= 48 && entry.visualRect.height >= 24;

    return Positioned.fromRect(
      rect: entry.visualRect,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: .96, end: 1),
          duration: duration,
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value.clamp(0.0, 1.0).toDouble(),
              child: Transform.scale(scale: value, child: child),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(.045),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cs.primary.withOpacity(.46),
                width: 1.2,
              ),
            ),
            child: showLabel
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surface.withOpacity(.86),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: cs.outlineVariant.withOpacity(.7),
                        ),
                      ),
                      child: Text(
                        '${entry.zone.displayName} ${entry.zone.current}/${entry.zone.capacity}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelSmall?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _ChildZoneHitOverlay extends StatelessWidget {
  const _ChildZoneHitOverlay({
    super.key,
    required this.entry,
    required this.onTap,
  });

  final _ResolvedChildZone entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: entry.hitRect,
      child: Semantics(
        button: true,
        label: '${entry.zone.group} ${entry.zone.child} 주차 구역',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _OccupiedSlotLabel extends StatelessWidget {
  const _OccupiedSlotLabel({
    super.key,
    required this.entry,
    required this.reduceMotion,
  });

  final _ResolvedOccupiedSlot entry;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final row = entry.slot.row;
    final last4 = _plateLast4(row.plateNumber);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);

    return Positioned.fromRect(
      rect: entry.visualRect,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: .88, end: 1),
          duration: duration,
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Opacity(
              opacity: value.clamp(0.0, 1.0).toDouble(),
              child: Transform.scale(scale: value, child: child),
            );
          },
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(.9),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: cs.primary.withOpacity(.72)),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withOpacity(.08),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                if (reduceMotion) return child;
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: .88, end: 1).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutBack,
                      ),
                    ),
                    child: child,
                  ),
                );
              },
              child: FittedBox(
                key: ValueKey<String>(
                  '${row.plateId}:${row.plateNumber}:${entry.slot.slot.no}',
                ),
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Text(
                    last4,
                    maxLines: 1,
                    softWrap: false,
                    style: text.labelMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OccupiedSlotOverlay extends StatelessWidget {
  const _OccupiedSlotOverlay({
    super.key,
    required this.entry,
    required this.onTap,
    required this.reduceMotion,
  });

  final _ResolvedOccupiedSlot entry;
  final VoidCallback onTap;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final row = entry.slot.row;
    return Stack(
      children: [
        _OccupiedSlotLabel(
          entry: entry,
          reduceMotion: reduceMotion,
        ),
        Positioned.fromRect(
          rect: entry.hitRect,
          child: Semantics(
            button: true,
            label:
                '${entry.slot.zone.group} ${entry.slot.zone.child} 슬롯 ${entry.slot.slot.no}, 번호판 ${row.plateNumber}, 상태 처리 빠른 실행',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onTap,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

List<_OccupiedSlot> _occupiedSlots(ZoneGroupVM group) {
  final out = <_OccupiedSlot>[];
  for (final zone in group.zones) {
    out.addAll(_occupiedSlotsForZone(zone));
  }
  return out;
}

List<_OccupiedSlot> _occupiedSlotsForZone(ZoneVM zone) {
  if (zone.rows.isEmpty || zone.source.childSlots.isEmpty) {
    return const <_OccupiedSlot>[];
  }
  final out = <_OccupiedSlot>[];
  final rowsBySlot = _rowsBySlot(zone.rows);
  final slots = List<ChildSlot>.of(zone.source.childSlots)
    ..sort((a, b) => a.no.compareTo(b.no));
  for (final slot in slots) {
    final row = rowsBySlot[slot.no];
    if (row == null) continue;
    out.add(_OccupiedSlot(zone: zone, slot: slot, row: row));
  }
  return out;
}

List<_ResolvedOccupiedSlot> _resolveOccupiedLabels({
  required List<_OccupiedSlot> occupied,
  required ParkingStatusDotMapLayout layout,
}) {
  final out = <_ResolvedOccupiedSlot>[];
  for (final entry in occupied) {
    final visual = layout
        .rectFor(
          GridRect(
            r0: entry.slot.r0,
            c0: entry.slot.c0,
            r1: entry.slot.r1,
            c1: entry.slot.c1,
          ),
        )
        .intersect(layout.mapRect);
    if (visual.isEmpty || visual.width <= 0 || visual.height <= 0) continue;
    out.add(
      _ResolvedOccupiedSlot(
        slot: entry,
        visualRect: visual,
        hitRect: visual,
      ),
    );
  }
  return out;
}

List<_ResolvedOccupiedSlot> _resolveOccupiedSlots({
  required List<_OccupiedSlot> occupied,
  required ParkingStatusDotMapLayout layout,
  required double minimum,
}) {
  final mapped = <_OccupiedSlot>[];
  final visuals = <Rect>[];
  for (final entry in occupied) {
    final visual = layout
        .rectFor(
          GridRect(
            r0: entry.slot.r0,
            c0: entry.slot.c0,
            r1: entry.slot.r1,
            c1: entry.slot.c1,
          ),
        )
        .intersect(layout.mapRect);
    if (visual.isEmpty || visual.width <= 0 || visual.height <= 0) continue;
    mapped.add(entry);
    visuals.add(visual);
  }

  final hits = <Rect>[
    for (final visual in visuals)
      _minimumHitRect(visual, layout.mapRect, minimum),
  ];

  for (var i = 0; i < hits.length; i++) {
    for (var j = i + 1; j < hits.length; j++) {
      if (!hits[i].overlaps(hits[j])) continue;
      final separated = _separateHitRects(
        firstVisual: visuals[i],
        secondVisual: visuals[j],
        firstHit: hits[i],
        secondHit: hits[j],
      );
      hits[i] = separated.$1.intersect(layout.mapRect);
      hits[j] = separated.$2.intersect(layout.mapRect);
    }
  }

  return <_ResolvedOccupiedSlot>[
    for (var i = 0; i < mapped.length; i++)
      if (!hits[i].isEmpty && hits[i].width > 0 && hits[i].height > 0)
        _ResolvedOccupiedSlot(
          slot: mapped[i],
          visualRect: visuals[i],
          hitRect: hits[i],
        ),
  ];
}

List<_ResolvedChildZone> _resolveChildZones({
  required List<ZoneVM> zones,
  required ParkingGridModel grid,
  required ParkingStatusDotMapLayout layout,
  required double minimum,
}) {
  final mapped = <ZoneVM>[];
  final visuals = <Rect>[];
  for (final zone in zones) {
    final childRect = _effectiveChildRect(zone, grid);
    if (childRect == null) continue;
    final visual = layout.rectFor(childRect).intersect(layout.mapRect);
    if (visual.isEmpty || visual.width <= 0 || visual.height <= 0) continue;
    mapped.add(zone);
    visuals.add(visual);
  }

  final hits = <Rect>[
    for (final visual in visuals)
      _minimumHitRect(visual, layout.mapRect, minimum),
  ];

  for (var i = 0; i < hits.length; i++) {
    for (var j = i + 1; j < hits.length; j++) {
      if (!hits[i].overlaps(hits[j])) continue;
      if (visuals[i].overlaps(visuals[j])) continue;
      final separated = _separateHitRects(
        firstVisual: visuals[i],
        secondVisual: visuals[j],
        firstHit: hits[i],
        secondHit: hits[j],
      );
      hits[i] = separated.$1.intersect(layout.mapRect);
      hits[j] = separated.$2.intersect(layout.mapRect);
    }
  }

  return <_ResolvedChildZone>[
    for (var i = 0; i < mapped.length; i++)
      if (!hits[i].isEmpty && hits[i].width > 0 && hits[i].height > 0)
        _ResolvedChildZone(
          zone: mapped[i],
          visualRect: visuals[i],
          hitRect: hits[i],
        ),
  ];
}

GridRect? _effectiveChildRect(ZoneVM zone, ParkingGridModel grid) {
  GridRect? raw = zone.source.childRect?.normalized();
  if (raw == null && zone.source.childSlots.isNotEmpty) {
    var top = zone.source.childSlots.first.r0;
    var left = zone.source.childSlots.first.c0;
    var bottom = zone.source.childSlots.first.r1;
    var right = zone.source.childSlots.first.c1;
    for (final slot in zone.source.childSlots.skip(1)) {
      top = math.min(top, math.min(slot.r0, slot.r1));
      left = math.min(left, math.min(slot.c0, slot.c1));
      bottom = math.max(bottom, math.max(slot.r0, slot.r1));
      right = math.max(right, math.max(slot.c0, slot.c1));
    }
    raw = GridRect(r0: top, c0: left, r1: bottom, c1: right);
  }
  if (raw == null || grid.rows <= 0 || grid.cols <= 0) return null;
  final normalized = raw.normalized();
  final top = normalized.top.clamp(0, grid.rows - 1).toInt();
  final left = normalized.left.clamp(0, grid.cols - 1).toInt();
  final bottom = normalized.bottom.clamp(0, grid.rows - 1).toInt();
  final right = normalized.right.clamp(0, grid.cols - 1).toInt();
  if (bottom < top || right < left) return null;
  return GridRect(r0: top, c0: left, r1: bottom, c1: right);
}

(Rect, Rect) _separateHitRects({
  required Rect firstVisual,
  required Rect secondVisual,
  required Rect firstHit,
  required Rect secondHit,
}) {
  if (firstVisual.right <= secondVisual.left) {
    final boundary = (firstVisual.right + secondVisual.left) / 2;
    return (
      Rect.fromLTRB(
        firstHit.left,
        firstHit.top,
        math.max(firstVisual.right, math.min(firstHit.right, boundary)),
        firstHit.bottom,
      ),
      Rect.fromLTRB(
        math.min(secondVisual.left, math.max(secondHit.left, boundary)),
        secondHit.top,
        secondHit.right,
        secondHit.bottom,
      ),
    );
  }
  if (secondVisual.right <= firstVisual.left) {
    final boundary = (secondVisual.right + firstVisual.left) / 2;
    return (
      Rect.fromLTRB(
        math.min(firstVisual.left, math.max(firstHit.left, boundary)),
        firstHit.top,
        firstHit.right,
        firstHit.bottom,
      ),
      Rect.fromLTRB(
        secondHit.left,
        secondHit.top,
        math.max(secondVisual.right, math.min(secondHit.right, boundary)),
        secondHit.bottom,
      ),
    );
  }
  if (firstVisual.bottom <= secondVisual.top) {
    final boundary = (firstVisual.bottom + secondVisual.top) / 2;
    return (
      Rect.fromLTRB(
        firstHit.left,
        firstHit.top,
        firstHit.right,
        math.max(firstVisual.bottom, math.min(firstHit.bottom, boundary)),
      ),
      Rect.fromLTRB(
        secondHit.left,
        math.min(secondVisual.top, math.max(secondHit.top, boundary)),
        secondHit.right,
        secondHit.bottom,
      ),
    );
  }
  if (secondVisual.bottom <= firstVisual.top) {
    final boundary = (secondVisual.bottom + firstVisual.top) / 2;
    return (
      Rect.fromLTRB(
        firstHit.left,
        math.min(firstVisual.top, math.max(firstHit.top, boundary)),
        firstHit.right,
        firstHit.bottom,
      ),
      Rect.fromLTRB(
        secondHit.left,
        secondHit.top,
        secondHit.right,
        math.max(secondVisual.bottom, math.min(secondHit.bottom, boundary)),
      ),
    );
  }

  final dx = secondVisual.center.dx - firstVisual.center.dx;
  final dy = secondVisual.center.dy - firstVisual.center.dy;
  if (dx.abs() >= dy.abs()) {
    final boundary = (firstVisual.center.dx + secondVisual.center.dx) / 2;
    if (dx >= 0) {
      return (
        Rect.fromLTRB(
          firstHit.left,
          firstHit.top,
          math.max(firstHit.left, math.min(firstHit.right, boundary)),
          firstHit.bottom,
        ),
        Rect.fromLTRB(
          math.min(secondHit.right, math.max(secondHit.left, boundary)),
          secondHit.top,
          secondHit.right,
          secondHit.bottom,
        ),
      );
    }
    return (
      Rect.fromLTRB(
        math.min(firstHit.right, math.max(firstHit.left, boundary)),
        firstHit.top,
        firstHit.right,
        firstHit.bottom,
      ),
      Rect.fromLTRB(
        secondHit.left,
        secondHit.top,
        math.max(secondHit.left, math.min(secondHit.right, boundary)),
        secondHit.bottom,
      ),
    );
  }

  final boundary = (firstVisual.center.dy + secondVisual.center.dy) / 2;
  if (dy >= 0) {
    return (
      Rect.fromLTRB(
        firstHit.left,
        firstHit.top,
        firstHit.right,
        math.max(firstHit.top, math.min(firstHit.bottom, boundary)),
      ),
      Rect.fromLTRB(
        secondHit.left,
        math.min(secondHit.bottom, math.max(secondHit.top, boundary)),
        secondHit.right,
        secondHit.bottom,
      ),
    );
  }
  return (
    Rect.fromLTRB(
      firstHit.left,
      math.min(firstHit.bottom, math.max(firstHit.top, boundary)),
      firstHit.right,
      firstHit.bottom,
    ),
    Rect.fromLTRB(
      secondHit.left,
      secondHit.top,
      secondHit.right,
      math.max(secondHit.top, math.min(secondHit.bottom, boundary)),
    ),
  );
}

Rect _minimumHitRect(Rect source, Rect bounds, double minimum) {
  final width = math.min(bounds.width, math.max(minimum, source.width));
  final height = math.min(bounds.height, math.max(minimum, source.height));
  var left = source.center.dx - width / 2;
  var top = source.center.dy - height / 2;
  left = left.clamp(bounds.left, bounds.right - width).toDouble();
  top = top.clamp(bounds.top, bounds.bottom - height).toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

Map<int, RealTimeRowVM> _rowsBySlot(List<RealTimeRowVM> rows) {
  final out = <int, RealTimeRowVM>{};
  final ordered = List<RealTimeRowVM>.of(rows)
    ..sort(compareRowsByLocationSlot);
  for (final row in ordered) {
    final no = slotNumberFromRowLocation(row.location);
    if (no == null || no <= 0) continue;
    out.putIfAbsent(no, () => row);
  }
  return out;
}

String _plateLast4(String raw) {
  final normalized = raw.trim();
  final match = RegExp(r'(\d{4})$').firstMatch(normalized);
  if (match != null) return match.group(1) ?? '—';
  final digits =
      RegExp(r'\d').allMatches(normalized).map((m) => m.group(0)).join();
  if (digits.length >= 4) return digits.substring(digits.length - 4);
  return '—';
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withOpacity(.62)),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
