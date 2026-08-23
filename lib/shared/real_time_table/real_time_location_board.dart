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
import '../parking_dot_map/effective_child_region_geometry.dart';
import '../parking_dot_map/parking_status_dot_map_surface.dart';
import '../parking_spatial/parking_spatial_geometry.dart';
import 'real_time_sort_state.dart';
import 'real_time_source_rect_modal.dart';
import 'real_time_tab_controller.dart';
import 'real_time_table_row_vm.dart';
import 'real_time_table_zone.dart';

const double _kZoneTouchTargetMin = 44.0;
const double _kParentPageLockDistance = 10.0;
const double _kParentPageTriggerFraction = .16;
const double _kParentPageMinVelocity = 520.0;
const Duration _kZonePeekShowDuration = Duration(milliseconds: 160);
const Duration _kZonePeekHideDuration = Duration(milliseconds: 130);

class RealTimeLocationBoard extends StatefulWidget {
  const RealTimeLocationBoard({
    super.key,
    required this.groups,
    required this.onPlateTap,
    required this.onParentPageChanged,
    required this.onUserActivity,
    this.onAutoPauseStart,
    this.onAutoPauseEnd,
    this.externalDebugLines,
    this.parentFocusRequest,
    this.onParentFocusApplied,
  });

  final List<ZoneGroupVM> groups;
  final ValueChanged<RealTimeRowVM> onPlateTap;
  final void Function(String parent, int index, int count) onParentPageChanged;
  final VoidCallback onUserActivity;
  final VoidCallback? onAutoPauseStart;
  final VoidCallback? onAutoPauseEnd;
  final List<String> Function()? externalDebugLines;
  final RealTimeParentFocusRequest? parentFocusRequest;
  final void Function(RealTimeParentFocusRequest request, int index)?
      onParentFocusApplied;

  @override
  State<RealTimeLocationBoard> createState() => _RealTimeLocationBoardState();
}

class _RealTimeLocationBoardState extends State<RealTimeLocationBoard> {
  final PageController _pageController = PageController(initialPage: 1);
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
  int _virtualPageIndex = 1;
  int _pagingOriginVirtualIndex = 1;
  bool _pagingLocked = false;
  bool _pagingRejected = false;
  bool _rawPagingInProgress = false;
  bool _pageSettleInProgress = false;
  bool _suppressPageChanged = false;
  bool _debugDialogShowing = false;
  int _lastParentFocusSerial = 0;

  bool get _currentParentInteractionLocked => _activeParent.isNotEmpty &&
      (_parentInteractionLocked[_activeParent] ?? false);

  int get _virtualPageCount =>
      widget.groups.length < 2 ? widget.groups.length : widget.groups.length + 2;

  int _logicalIndexForVirtual(int virtualIndex) {
    final count = widget.groups.length;
    if (count <= 1) return 0;
    if (virtualIndex <= 0) return count - 1;
    if (virtualIndex >= count + 1) return 0;
    return virtualIndex - 1;
  }

  int _canonicalVirtualIndexForLogical(int logicalIndex) {
    final count = widget.groups.length;
    if (count <= 1) return 0;
    return logicalIndex.clamp(0, count - 1).toInt() + 1;
  }

  bool _isSentinelVirtualIndex(int virtualIndex) {
    final count = widget.groups.length;
    return count > 1 && (virtualIndex == 0 || virtualIndex == count + 1);
  }

  String _virtualPageRole(int virtualIndex) {
    final count = widget.groups.length;
    if (count <= 1) return 'single';
    if (virtualIndex == 0) return 'leading_sentinel';
    if (virtualIndex == count + 1) return 'trailing_sentinel';
    return 'canonical';
  }

  @override
  void initState() {
    super.initState();
    if (widget.groups.isNotEmpty) {
      _activeParent = widget.groups.first.group;
    }
    _virtualPageIndex = widget.groups.length > 1 ? 1 : 0;
    _debugLog(
      'board_initialized',
      <String, Object?>{
        'parents': widget.groups.length,
        'activeParent': _activeParent,
        'interaction': 'parent_child_dialog_slot',
        'childDialogAutoPause': true,
        'systemBackPolicy': 'dialog_reverse_to_parent',
        'childRegionShape': 'child_slot_area_ids_difference_path',
        'childRegionHitTest': 'effective_path_contains',
        'childDialogParkingDots': 'owned_child_slot_area_ids_only',
        'parentPaging': widget.groups.length > 1
            ? 'circular_sentinel'
            : 'single_parent',
        'sentinelPages': widget.groups.length > 1 ? 2 : 0,
        'firebaseAdditionalRead': 0,
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_applyParentFocusRequest(widget.parentFocusRequest));
    });
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
      _virtualPageIndex = 0;
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
    final reconciled = nextIndex != _pageIndex ||
        _activeParent != widget.groups[nextIndex].group;
    final structureChanged = oldWidget.groups.length != widget.groups.length;
    if (reconciled) {
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
    }
    final canonicalVirtual =
        _canonicalVirtualIndexForLogical(_pageIndex);
    _virtualPageIndex = canonicalVirtual;
    final oldRequest = oldWidget.parentFocusRequest;
    final newRequest = widget.parentFocusRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.groups.length > 1 &&
          _pageController.hasClients &&
          (reconciled || structureChanged)) {
        _suppressPageChanged = true;
        _pageController.jumpToPage(canonicalVirtual);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _suppressPageChanged = false;
        });
      }
      if (newRequest != null && oldRequest?.serial != newRequest.serial) {
        unawaited(_applyParentFocusRequest(newRequest));
      }
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

  List<String> get _combinedDebugLines {
    final combined = <String>[
      ...?widget.externalDebugLines?.call(),
      ..._debugLines,
    ];
    if (combined.length <= 260) return combined;
    return combined.sublist(combined.length - 260);
  }

  String get _debugPrintCode => _combinedDebugLines
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');

  Future<void> _showDeveloperDebugDialog() async {
    if (!mounted || _debugDialogShowing || _combinedDebugLines.isEmpty) return;
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !mounted || _debugDialogShowing) return;
    _debugLog(
      'developer_status_dialog_opened',
      <String, Object?>{
        'activeParent': _activeParent,
        'page': _pageIndex + 1,
        'count': widget.groups.length,
        'virtualPage': _virtualPageIndex,
        'parentPaging': widget.groups.length > 1
            ? 'circular_sentinel'
            : 'single_parent',
        'sentinelPages': widget.groups.length > 1 ? 2 : 0,
        'wrapMotion': 'finger_follow_220ms_easeOutCubic',
        'autoTransitionPaused': true,
        'parentMapFrame': 'hidden',
        'parentMapSurface': 'transparent',
        'parentMapClip': 'rect',
        'parentMapReveal': 'fade_scale_220ms',
        'childRegionShape': 'child_slot_area_ids_difference_path',
        'childRegionHitTest': 'effective_path_contains',
        'childRegionMotion': 'fade_scale_220ms_highlight_170ms',
        'childDialogParkingDots': 'owned_child_slot_area_ids_only',
        'childDialogEffectiveRegionMotion': 'modal_progress_fade_scale',
        'childDialogBorder': 'hidden',
        'childDialogSurface': 'opacity_0.96',
        'childDialogShape': 'rounded_surface',
        'childDialogShadow': 'subtle',
        'childMapFrame': 'hidden',
        'childMapSurface': 'transparent',
        'childMapClip': 'rect',
        'childDialogMotion': 'source_rect_crop_expand_reverse_collapse',
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
        description: _combinedDebugLines.join('\n'),
        copyText: code,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: Duration.zero,
        useCommonUi: true,
        awaitManualClose: true,
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
          'virtualPage': _virtualPageIndex,
          'parentPaging': widget.groups.length > 1
              ? 'circular_sentinel'
              : 'single_parent',
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

  void _onPageChanged(int virtualIndex) {
    if (_suppressPageChanged ||
        _rawPagingInProgress ||
        _pageSettleInProgress) {
      return;
    }
    _virtualPageIndex = virtualIndex;
    _commitPageChanged(_logicalIndexForVirtual(virtualIndex));
  }

  Future<void> _applyParentFocusRequest(
    RealTimeParentFocusRequest? request,
  ) async {
    if (request == null || request.serial <= _lastParentFocusSerial) return;
    _lastParentFocusSerial = request.serial;
    final parent = request.parent.trim();
    final target = widget.groups.indexWhere(
      (group) => group.group.trim() == parent,
    );
    if (target < 0) {
      _debugLog(
        'parent_focus_rejected',
        <String, Object?>{
          'serial': request.serial,
          'parent': parent,
          'reason': 'parent_not_found',
          'count': widget.groups.length,
        },
      );
      return;
    }
    final multiple = widget.groups.length > 1;
    if (multiple && !_pageController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _lastParentFocusSerial = request.serial - 1;
        unawaited(_applyParentFocusRequest(request));
      });
      return;
    }
    final fromIndex = _pageIndex;
    final targetVirtual = _canonicalVirtualIndexForLogical(target);
    final animated = multiple && target != fromIndex;
    _pageSettleInProgress = true;
    _suppressPageChanged = true;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _debugLog(
      'parent_focus_started',
      <String, Object?>{
        'serial': request.serial,
        'parent': parent,
        'fromIndex': fromIndex,
        'toIndex': target,
        'fromVirtualIndex': _virtualPageIndex,
        'toVirtualIndex': targetVirtual,
        'parentPaging': multiple ? 'circular_sentinel' : 'single_parent',
        'reduceMotion': reduceMotion,
      },
    );
    try {
      if (multiple) {
        if (reduceMotion || !animated) {
          _pageController.jumpToPage(targetVirtual);
        } else {
          await _pageController.animateToPage(
            targetVirtual,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      }
      _virtualPageIndex = targetVirtual;
    } finally {
      _pageSettleInProgress = false;
      _suppressPageChanged = false;
    }
    if (!mounted) return;
    if (_pageIndex != target || _activeParent != widget.groups[target].group) {
      setState(() {
        _pageIndex = target;
        _activeParent = widget.groups[target].group;
      });
      widget.onParentPageChanged(
        widget.groups[target].group,
        target,
        widget.groups.length,
      );
    }
    widget.onUserActivity();
    widget.onParentFocusApplied?.call(request, target);
    _debugLog(
      'parent_focus_applied',
      <String, Object?>{
        'serial': request.serial,
        'parent': widget.groups[target].group,
        'index': target,
        'virtualIndex': targetVirtual,
        'count': widget.groups.length,
        'durationMs': reduceMotion || !animated ? 0 : 220,
      },
    );
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
    if (!_pageController.hasClients || widget.groups.length < 2) return;
    final maxVirtual = math.max(0, _virtualPageCount - 1);
    final origin =
        _pagingOriginVirtualIndex.clamp(0, maxVirtual).toInt();
    _suppressPageChanged = true;
    _rawPagingInProgress = false;
    _pageController.jumpToPage(origin);
    _virtualPageIndex = origin;
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
    final currentVirtual = (_pageController.page ?? _virtualPageIndex.toDouble())
        .round()
        .clamp(0, _virtualPageCount - 1)
        .toInt();
    _virtualPageIndex = currentVirtual;
    _pagingOriginVirtualIndex = currentVirtual;
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
    if (!_pageController.hasClients || widget.groups.length < 2) {
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
    final maxVirtual = _virtualPageCount - 1;
    final originVirtual =
        _pagingOriginVirtualIndex.clamp(0, maxVirtual).toInt();
    var targetVirtual = originVirtual;
    final accepted = !canceled &&
        (distanceX.abs() >= threshold ||
            velocityX.abs() >= _kParentPageMinVelocity);
    if (accepted) {
      targetVirtual += distanceX < 0 ||
              (distanceX.abs() < threshold && velocityX < 0)
          ? 1
          : -1;
    }
    targetVirtual = targetVirtual.clamp(0, maxVirtual).toInt();
    final originLogical = _logicalIndexForVirtual(originVirtual);
    final targetLogical = _logicalIndexForVirtual(targetVirtual);
    final wrap = accepted && _isSentinelVirtualIndex(targetVirtual);
    final boundary = targetVirtual == 0
        ? 'first_to_last'
        : targetVirtual == maxVirtual
            ? 'last_to_first'
            : 'none';
    final direction = targetVirtual < originVirtual ? 'previous' : 'next';
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (wrap) {
      _debugLog(
        'parent_swipe_wrap_started',
        <String, Object?>{
          'direction': direction,
          'boundary': boundary,
          'fromParent': widget.groups[originLogical].group,
          'fromIndex': originLogical,
          'fromVirtualIndex': originVirtual,
          'toParent': widget.groups[targetLogical].group,
          'toIndex': targetLogical,
          'sentinelTarget': targetVirtual,
          'fingerFollow': true,
          'durationMs': reduceMotion ? 0 : 220,
        },
      );
    }
    _resetPagingCandidate();
    var finalVirtual = targetVirtual;
    try {
      if (reduceMotion) {
        finalVirtual = _canonicalVirtualIndexForLogical(targetLogical);
        _suppressPageChanged = true;
        _pageController.jumpToPage(finalVirtual);
        _virtualPageIndex = finalVirtual;
      } else {
        await _pageController.animateToPage(
          targetVirtual,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        _virtualPageIndex = targetVirtual;
        if (wrap && mounted && _pageController.hasClients) {
          finalVirtual = _canonicalVirtualIndexForLogical(targetLogical);
          _suppressPageChanged = true;
          _pageController.jumpToPage(finalVirtual);
          _virtualPageIndex = finalVirtual;
          await WidgetsBinding.instance.endOfFrame;
          if (mounted) {
            _debugLog(
              'parent_swipe_wrap_normalized',
              <String, Object?>{
                'boundary': boundary,
                'fromVirtualIndex': targetVirtual,
                'toVirtualIndex': finalVirtual,
                'logicalIndex': targetLogical,
                'parent': widget.groups[targetLogical].group,
                'visibleJump': false,
              },
            );
          }
        }
      }
    } finally {
      _suppressPageChanged = false;
      _rawPagingInProgress = false;
      _pageSettleInProgress = false;
    }
    if (!mounted) return;
    _commitPageChanged(targetLogical);
    _debugLog(
      wrap ? 'parent_swipe_wrap_completed' : 'parent_swipe_settle_completed',
      <String, Object?>{
        'fromIndex': originLogical,
        'toIndex': targetLogical,
        'fromParent': widget.groups[originLogical].group,
        'toParent': widget.groups[targetLogical].group,
        'virtualIndex': finalVirtual,
        'accepted': accepted,
        'canceled': canceled,
        'boundary': boundary,
        'parentPaging': 'circular_sentinel',
      },
    );
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

    Widget slide(int index, {String pageRole = 'single'}) {
      final group = widget.groups[index];
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: _ParentMapSlide(
          key: ValueKey<String>('parent-slide:${group.group}:$pageRole'),
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
      itemCount: multiple ? widget.groups.length + 2 : widget.groups.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, virtualIndex) {
        final logicalIndex = _logicalIndexForVirtual(virtualIndex);
        return slide(
          logicalIndex,
          pageRole: _virtualPageRole(virtualIndex),
        );
      },
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
  bool _dialogRouteOpen = false;
  bool _dialogCloseRequested = false;
  String _dialogCloseSource = 'route';
  BuildContext? _dialogRouteContext;
  _OccupiedSlot? _pendingSlotAction;
  Completer<void>? _dialogCollapsedCompleter;

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
    if (_tickerModeEnabled &&
        !enabled &&
        _focusedZoneKey != null &&
        !_dialogRouteOpen) {
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
          'child_dialog_released_after_tab_change',
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_dialogRouteOpen) {
        final dialogContext = _dialogRouteContext;
        final dialogRoute =
            dialogContext == null ? null : ModalRoute.of(dialogContext);
        if (dialogRoute?.isCurrent ?? false) {
          widget.onDebugLog(
            'child_dialog_close_requested_after_data_update',
            <String, Object?>{
              'parent': widget.group.group,
              'childKey': previous,
            },
          );
          _closeFocus(source: 'data_update');
        } else {
          widget.onDebugLog(
            'child_dialog_data_invalidated_while_covered',
            <String, Object?>{
              'parent': widget.group.group,
              'childKey': previous,
              'dialogCurrent': false,
            },
          );
        }
        return;
      }
      setState(() => _focusedZoneKey = null);
      _endFocusAutoPause(
        source: 'data_update',
        childKey: previous,
      );
      widget.onInteractionLockChanged(false);
      widget.onDebugLog(
        'child_dialog_released_after_data_update',
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
    RealTimeChildFocusBackGuard.unregister(this);
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
        'system_back_guard_intercepted',
        <String, Object?>{
          'parent': widget.group.group,
          'child': _focusedZone?.child,
          'action': 'collapse_child_dialog',
          'returnStage': 'parent_overview',
        },
      );
      _closeFocus(source: 'system_back_guard');
    });
    widget.onAutoPauseStart?.call();
    widget.onDebugLog(
      'child_dialog_auto_pause_started',
      <String, Object?>{
        'parent': zone.group,
        'child': zone.child,
        'reason': 'child_dialog',
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
      'child_dialog_auto_pause_ended',
      <String, Object?>{
        'parent': widget.group.group,
        'childKey': childKey,
        'source': source,
        'autoTransitionPaused': false,
      },
    );
  }

  Future<void> _focusZone(ZoneVM zone, Rect sourceRect) async {
    if (_dialogRouteOpen || _focusedZoneKey != null) return;
    final grid = widget.group.parentSource?.parkingGrid;
    final viewport = grid == null ? null : _resolveNominalChildRect(zone, grid);
    if (grid == null || viewport == null) {
      widget.onDebugLog(
        'child_dialog_rejected',
        <String, Object?>{
          'parent': zone.group,
          'child': zone.child,
          'reason': 'child_rect_unavailable',
          'childSlots': zone.source.childSlots.length,
        },
      );
      return;
    }

    final effectiveAreaIds = resolvedChildParkingAreaIds(zone.source);
    final effectiveStats = effectiveChildRegionStats(
      grid: grid,
      childRect: viewport,
      effectiveParkingAreaIds: effectiveAreaIds,
    );
    final useEffectiveShape = !zone.source.isTowerChild;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final targetRect = realTimeSourceRectModalTargetRect(context);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 340);

    _startFocusAutoPause(zone);
    _dialogRouteOpen = true;
    _dialogCloseRequested = false;
    _dialogCloseSource = 'route';
    _pendingSlotAction = null;
    _dialogCollapsedCompleter = Completer<void>();
    setState(() => _focusedZoneKey = zone.fullName);
    widget.onInteractionLockChanged(true);
    widget.onUserActivity();
    HapticFeedback.selectionClick();
    widget.onDebugLog(
      'child_dialog_expand_started',
      <String, Object?>{
        'parent': zone.group,
        'child': zone.child,
        'viewport': viewport.toKey(),
        'viewportSource': zone.source.childRect != null
            ? 'child_rect'
            : 'child_slots_bounds',
        'sourceRect': realTimeSourceRectDebug(sourceRect),
        'targetRect': realTimeSourceRectDebug(targetRect),
        'durationMs': duration.inMilliseconds,
        'slots': zone.source.childSlots.length,
        'occupied': zone.rows.length,
        'effectiveAreaIds': effectiveAreaIds.length,
        'containedParkingAreas': effectiveStats.containedParkingAreaCount,
        'ownedParkingAreas': effectiveStats.ownedParkingAreaCount,
        'cutParkingAreas': effectiveStats.cutParkingAreaCount,
        'effectiveShape': useEffectiveShape
            ? 'child_slot_area_ids_difference_path'
            : 'nominal_rect_tower',
        'dialogParkingDots': useEffectiveShape
            ? 'owned_child_slot_area_ids_only'
            : 'all_in_viewport_tower',
        'firebaseAdditionalRead': 0,
        'autoTransitionPaused': true,
        'dialogBorder': 'hidden',
        'dialogSurfaceOpacity': '0.92->0.96',
        'dialogShape': 'rounded_surface',
        'dialogShadow': 'subtle',
        'childMapFrame': 'hidden',
        'childMapSurface': 'transparent',
        'childMapClip': 'rect',
        'motion': 'source_rect_crop_expand_reverse_collapse',
      },
    );

    try {
      if (!reduceMotion) {
        await Future<void>.delayed(const Duration(milliseconds: 48));
        if (!mounted || _focusedZoneKey != zone.fullName) return;
      }

      await showGeneralDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierLabel: '${zone.displayName} 주차 구역',
        barrierColor: Colors.transparent,
        transitionDuration: duration,
        pageBuilder: (dialogContext, _, __) {
          _dialogRouteContext = dialogContext;
          return const SizedBox.expand();
        },
        transitionBuilder: (dialogContext, animation, _, __) {
          _dialogRouteContext = dialogContext;
          return RealTimeSourceRectModalTransition(
            animation: animation,
            sourceRect: sourceRect,
            targetRect: targetRect,
            reduceMotion: reduceMotion,
            closeSemanticsLabel: '${zone.displayName} 닫기',
            onCloseRequested: (source) {
              _requestDialogClose(dialogContext, source);
            },
            onSystemPop: _recordSystemDialogPop,
            onExpanded: () {
              widget.onDebugLog(
                'child_dialog_expand_completed',
                <String, Object?>{
                  'parent': zone.group,
                  'child': zone.child,
                  'targetRect': realTimeSourceRectDebug(targetRect),
                  'durationMs': duration.inMilliseconds,
                  'slotInteraction': 'enabled',
                  'dialogBorder': 'hidden',
                  'dialogSurfaceOpacity': '0.96',
                  'dialogShadow': 'subtle',
                  'childMapFrame': 'hidden',
                  'childMapSurface': 'transparent',
                },
              );
            },
            onCollapseLifecycle: (info) {
              widget.onDebugLog(
                'child_dialog_collapse_lifecycle',
                <String, Object?>{
                  'parent': zone.group,
                  'child': zone.child,
                  'expandedBeforeCollapse': info.expandedBeforeCollapse,
                  'earlyCollapse': info.earlyCollapse,
                  'maxRawProgress': info.maxRawProgress.toStringAsFixed(3),
                  'callback': 'guaranteed_on_dismissed',
                  'earlyReverseCurve': info.earlyCollapse
                      ? 'continuous_easeOutCubic'
                      : 'easeInOutCubic',
                },
              );
            },
            onCollapsed: () {
              final collapsed = _dialogCollapsedCompleter;
              if (collapsed != null && !collapsed.isCompleted) {
                collapsed.complete();
              }
              widget.onDebugLog(
                'child_dialog_collapse_completed',
                <String, Object?>{
                  'parent': zone.group,
                  'child': zone.child,
                  'source': _dialogCloseSource,
                  'targetRect': realTimeSourceRectDebug(sourceRect),
                  'pendingStatusDock': _pendingSlotAction != null,
                },
              );
            },
            builder: (context, progress, interactionEnabled) {
              return _ChildDotMapDialogSurface(
                zone: zone,
                grid: grid,
                progress: progress,
                reduceMotion: reduceMotion,
                interactionEnabled: interactionEnabled,
                onPlateTap: _handlePlateTap,
                onDeveloperDebugTap: widget.onDeveloperDebugTap,
                onClose: () => _requestDialogClose(
                  dialogContext,
                  'dialog_header',
                ),
              );
            },
          );
        },
      );
    } finally {
      final closeSource = _dialogCloseSource;
      final pendingSlotAction = _pendingSlotAction;
      final collapsed = _dialogCollapsedCompleter;
      if (pendingSlotAction != null &&
          collapsed != null &&
          !collapsed.isCompleted) {
        try {
          await collapsed.future.timeout(
            reduceMotion
                ? const Duration(milliseconds: 80)
                : const Duration(milliseconds: 520),
          );
        } on TimeoutException {
          widget.onDebugLog(
            'child_dialog_collapse_wait_timeout',
            <String, Object?>{
              'parent': zone.group,
              'child': zone.child,
              'source': closeSource,
              'pendingPlateId': pendingSlotAction.row.plateId,
            },
          );
        }
      }
      _dialogRouteContext = null;
      _dialogRouteOpen = false;
      _dialogCloseRequested = false;
      if (mounted && _focusedZoneKey == zone.fullName) {
        setState(() => _focusedZoneKey = null);
        widget.onInteractionLockChanged(false);
        widget.onUserActivity();
      }
      if (pendingSlotAction != null &&
          closeSource == 'slot_action' &&
          mounted) {
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) {
          widget.onDebugLog(
            'child_dialog_slot_action_dispatched',
            <String, Object?>{
              'parent': pendingSlotAction.zone.group,
              'child': pendingSlotAction.zone.child,
              'slot': pendingSlotAction.slot.no,
              'plateId': pendingSlotAction.row.plateId,
              'plateNumber': pendingSlotAction.row.plateNumber,
              'dialogClosed': true,
              'action': 'open_status_side_dock',
              'autoTransitionPaused': true,
            },
          );
          widget.onPlateTap(pendingSlotAction.row);
        }
      }
      _pendingSlotAction = null;
      _dialogCollapsedCompleter = null;
      _endFocusAutoPause(
        source: closeSource,
        childKey: zone.fullName,
      );
      widget.onDebugLog(
        'child_dialog_closed',
        <String, Object?>{
          'parent': zone.group,
          'child': zone.child,
          'source': closeSource,
          'returnStage': 'parent_overview',
          'statusDockDispatched': pendingSlotAction != null &&
              closeSource == 'slot_action' &&
              mounted,
          'autoTransitionPaused': false,
        },
      );
    }
  }

  void _requestDialogClose(BuildContext dialogContext, String source) {
    if (_dialogCloseRequested) return;
    _dialogCloseRequested = true;
    _dialogCloseSource = source;
    widget.onUserActivity();
    HapticFeedback.selectionClick();
    widget.onDebugLog(
      'child_dialog_collapse_started',
      <String, Object?>{
        'parent': widget.group.group,
        'child': _focusedZone?.child,
        'source': source,
        'returnStage': 'parent_overview',
        'autoTransitionPaused': true,
      },
    );
    Navigator.of(dialogContext).pop();
  }

  void _recordSystemDialogPop() {
    if (_dialogCloseRequested) return;
    _dialogCloseRequested = true;
    _dialogCloseSource = 'system_back';
    widget.onUserActivity();
    HapticFeedback.selectionClick();
    widget.onDebugLog(
      'child_dialog_collapse_started',
      <String, Object?>{
        'parent': widget.group.group,
        'child': _focusedZone?.child,
        'source': 'system_back',
        'returnStage': 'parent_overview',
        'autoTransitionPaused': true,
      },
    );
  }

  void _closeFocus({String source = 'header_back'}) {
    final childKey = _focusedZoneKey;
    if (childKey == null) return;
    final dialogContext = _dialogRouteContext;
    if (_dialogRouteOpen &&
        dialogContext != null &&
        dialogContext.mounted) {
      _requestDialogClose(dialogContext, source);
      return;
    }
    if (mounted) {
      setState(() => _focusedZoneKey = null);
    } else {
      _focusedZoneKey = null;
    }
    _endFocusAutoPause(
      source: source,
      childKey: childKey,
    );
    widget.onInteractionLockChanged(false);
    widget.onUserActivity();
    widget.onDebugLog(
      'child_dialog_closed_without_route',
      <String, Object?>{
        'parent': widget.group.group,
        'childKey': childKey,
        'source': source,
        'autoTransitionPaused': false,
      },
    );
  }

  void _handlePlateTap(_OccupiedSlot occupied) {
    if (_dialogCloseRequested || !_dialogRouteOpen) {
      widget.onDebugLog(
        'child_dialog_slot_tap_blocked',
        <String, Object?>{
          'parent': occupied.zone.group,
          'child': occupied.zone.child,
          'slot': occupied.slot.no,
          'plateId': occupied.row.plateId,
          'plateNumber': occupied.row.plateNumber,
          'reason': _dialogCloseRequested
              ? 'dialog_closing'
              : 'dialog_route_inactive',
          'dialogCloseRequested': _dialogCloseRequested,
          'dialogRouteOpen': _dialogRouteOpen,
          'action': 'status_side_dock_blocked',
        },
      );
      return;
    }
    final dialogContext = _dialogRouteContext;
    if (dialogContext == null || !dialogContext.mounted) {
      widget.onDebugLog(
        'child_dialog_slot_tap_blocked',
        <String, Object?>{
          'parent': occupied.zone.group,
          'child': occupied.zone.child,
          'slot': occupied.slot.no,
          'plateId': occupied.row.plateId,
          'plateNumber': occupied.row.plateNumber,
          'reason': 'dialog_context_inactive',
          'action': 'status_side_dock_blocked',
        },
      );
      return;
    }
    _pendingSlotAction = occupied;
    widget.onUserActivity();
    widget.onDebugLog(
      'child_dialog_slot_tapped',
      <String, Object?>{
        'parent': occupied.zone.group,
        'child': occupied.zone.child,
        'slot': occupied.slot.no,
        'plateId': occupied.row.plateId,
        'plateNumber': occupied.row.plateNumber,
        'plateLast4': _plateLast4(occupied.row.plateNumber),
        'action': 'collapse_dialog_then_open_status_side_dock',
        'childDialogRemainsOpen': false,
        'sideDockAfterCollapse': true,
      },
    );
    _requestDialogClose(dialogContext, 'slot_action');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final focused = _focusedZone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            height: 34,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.group.group,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
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
            selectedZoneKey: focused?.fullName,
            onZoneTap: (zone, sourceRect) {
              unawaited(_focusZone(zone, sourceRect));
            },
            onUserActivity: widget.onUserActivity,
            onDebugLog: widget.onDebugLog,
            reduceMotion: reduceMotion,
          ),
        ),
      ],
    );
  }
}

class _ChildDotMapDialogSurface extends StatelessWidget {
  const _ChildDotMapDialogSurface({
    required this.zone,
    required this.grid,
    required this.progress,
    required this.reduceMotion,
    required this.interactionEnabled,
    required this.onPlateTap,
    required this.onDeveloperDebugTap,
    required this.onClose,
  });

  final ZoneVM zone;
  final ParkingGridModel grid;
  final double progress;
  final bool reduceMotion;
  final bool interactionEnabled;
  final ValueChanged<_OccupiedSlot> onPlateTap;
  final VoidCallback onDeveloperDebugTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final headerProgress =
        ((progress - .52) / .48).clamp(0.0, 1.0).toDouble();
    final outerPadding = 10.0 * progress;
    final headerHeight = 34.0 * headerProgress;
    final mapTop = headerHeight + 7.0 * progress;
    final surfaceOpacity = (.92 + .04 * progress).clamp(0.0, 1.0).toDouble();
    final remaining =
        zone.remaining ?? math.max(0, zone.capacity - zone.current);

    return Material(
      color: cs.surface.withOpacity(surfaceOpacity),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                outerPadding,
                mapTop,
                outerPadding,
                outerPadding,
              ),
              child: _ChildFocusDotMap(
                zone: zone,
                grid: grid,
                revealProgress: progress,
                onPlateTap: onPlateTap,
                reduceMotion: reduceMotion,
                interactionEnabled: interactionEnabled,
              ),
            ),
          ),
          if (headerProgress > .01)
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 34,
                child: IgnorePointer(
                  ignoring: headerProgress < .9,
                  child: Opacity(
                    opacity: headerProgress,
                    child: Transform.translate(
                      offset: Offset(0, -8 * (1 - headerProgress)),
                      child: ColoredBox(
                        color: cs.surface.withOpacity(.94),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: [
                              Semantics(
                                button: true,
                                label: '${zone.displayName} 닫기',
                                child: IconButton(
                                  onPressed: onClose,
                                  padding: EdgeInsets.zero,
                                  constraints:
                                      const BoxConstraints.tightFor(
                                    width: 34,
                                    height: 34,
                                  ),
                                  splashRadius: 18,
                                  icon: const Icon(
                                    Icons.arrow_back_rounded,
                                    size: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  zone.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleSmall?.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$remaining / ${zone.capacity}',
                                style: text.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const <FontFeature>[
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              ValueListenableBuilder<bool>(
                                valueListenable: DevAuth.devModeEnabled,
                                builder: (context, enabled, _) {
                                  if (!enabled) {
                                    return const SizedBox(width: 4);
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 2),
                                    child: Semantics(
                                      button: true,
                                      label: '구역 DOT MAP 디버그 상태',
                                      child: IconButton(
                                        onPressed: onDeveloperDebugTap,
                                        padding: EdgeInsets.zero,
                                        constraints:
                                            const BoxConstraints.tightFor(
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
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ),
        ],
      ),
    );
  }
}

class _ParentMapPage extends StatefulWidget {
  const _ParentMapPage({
    required this.group,
    required this.selectedZoneKey,
    required this.onZoneTap,
    required this.onUserActivity,
    required this.onDebugLog,
    required this.reduceMotion,
  });

  final ZoneGroupVM group;
  final String? selectedZoneKey;
  final void Function(ZoneVM, Rect) onZoneTap;
  final VoidCallback onUserActivity;
  final void Function(String, [Map<String, Object?>]) onDebugLog;
  final bool reduceMotion;

  @override
  State<_ParentMapPage> createState() => _ParentMapPageState();
}

class _ParentMapPageState extends State<_ParentMapPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _revealController;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.reduceMotion ? 1 : 0,
    );
    if (!widget.reduceMotion) {
      widget.onDebugLog(
        'parent_map_reveal_start',
        <String, Object?>{
          'parent': widget.group.group,
          'durationMs': 220,
          'motion': 'fade_scale',
          'frame': 'hidden',
          'surface': 'transparent',
        },
      );
      unawaited(
        _revealController.forward().then<void>((_) {
          if (!mounted) return;
          widget.onDebugLog(
            'parent_map_reveal_complete',
            <String, Object?>{
              'parent': widget.group.group,
              'frame': 'hidden',
              'surface': 'transparent',
            },
          );
        }),
      );
    } else {
      widget.onDebugLog(
        'parent_map_reveal_skipped',
        <String, Object?>{
          'parent': widget.group.group,
          'reason': 'reduce_motion',
          'frame': 'hidden',
          'surface': 'transparent',
        },
      );
    }
  }

  @override
  void didUpdateWidget(covariant _ParentMapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotion != widget.reduceMotion) {
      if (widget.reduceMotion) {
        _revealController.value = 1;
      } else {
        _revealController
          ..value = 0
          ..forward();
      }
    }
    if (oldWidget.group.group != widget.group.group && !widget.reduceMotion) {
      _revealController
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grid = widget.group.parentSource?.parkingGrid;
    if (grid == null || grid.rows <= 0 || grid.cols <= 0) {
      return const _InlineEmpty(message: '부모 주차 구역 DOT MAP 데이터가 없습니다.');
    }

    final map = _ParentOverviewDotMap(
      group: widget.group,
      grid: grid,
      selectedZoneKey: widget.selectedZoneKey,
      onZoneTap: widget.onZoneTap,
      onUserActivity: widget.onUserActivity,
      onDebugLog: widget.onDebugLog,
      reduceMotion: widget.reduceMotion,
    );
    if (widget.reduceMotion) return map;
    return AnimatedBuilder(
      animation: _revealController,
      child: map,
      builder: (context, child) {
        final progress = Curves.easeOutCubic.transform(
          _revealController.value.clamp(0.0, 1.0).toDouble(),
        );
        return Opacity(
          opacity: .88 + .12 * progress,
          child: Transform.scale(
            scale: .992 + .008 * progress,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
    );
  }
}

class _ParentOverviewDotMap extends StatefulWidget {
  const _ParentOverviewDotMap({
    required this.group,
    required this.grid,
    required this.selectedZoneKey,
    required this.onZoneTap,
    required this.onUserActivity,
    required this.onDebugLog,
    required this.reduceMotion,
  });

  final ZoneGroupVM group;
  final ParkingGridModel grid;
  final String? selectedZoneKey;
  final void Function(ZoneVM, Rect) onZoneTap;
  final VoidCallback onUserActivity;
  final void Function(String, [Map<String, Object?>]) onDebugLog;
  final bool reduceMotion;

  @override
  State<_ParentOverviewDotMap> createState() => _ParentOverviewDotMapState();
}

class _ParentOverviewDotMapState extends State<_ParentOverviewDotMap> {
  final GlobalKey _mapKey = GlobalKey();
  String? _peekZoneKey;
  Offset? _peekAnchor;
  bool _peekVisible = false;
  int _peekEpoch = 0;
  String? _lastGeometryDebugSignature;

  void _recordResolvedGeometry(List<_ResolvedChildZone> zones) {
    final signature = zones
        .map(
          (entry) => [
            entry.zone.fullName,
            entry.useEffectiveShape,
            entry.containedParkingAreaCount,
            entry.ownedParkingAreaCount,
            entry.cutParkingAreaCount,
            entry.nominalRect.left.toStringAsFixed(1),
            entry.nominalRect.top.toStringAsFixed(1),
            entry.nominalRect.right.toStringAsFixed(1),
            entry.nominalRect.bottom.toStringAsFixed(1),
          ].join(':'),
        )
        .join('|');
    if (_lastGeometryDebugSignature == signature) return;
    _lastGeometryDebugSignature = signature;
    final contained = zones.fold<int>(
      0,
      (sum, entry) => sum + entry.containedParkingAreaCount,
    );
    final owned = zones.fold<int>(
      0,
      (sum, entry) => sum + entry.ownedParkingAreaCount,
    );
    final cut = zones.fold<int>(
      0,
      (sum, entry) => sum + entry.cutParkingAreaCount,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastGeometryDebugSignature != signature) return;
      widget.onDebugLog(
        'child_region_geometry_resolved',
        <String, Object?>{
          'parent': widget.group.group,
          'zones': zones.length,
          'effectiveZones':
              zones.where((entry) => entry.useEffectiveShape).length,
          'towerZones':
              zones.where((entry) => !entry.useEffectiveShape).length,
          'containedParkingAreas': contained,
          'ownedParkingAreas': owned,
          'cutParkingAreas': cut,
          'render': 'child_slot_area_ids_difference_path',
          'hitTest': 'effective_path_contains',
          'entryMotionMs': widget.reduceMotion ? 0 : 220,
          'highlightMotionMs': widget.reduceMotion ? 0 : 170,
        },
      );
    });
  }

  void _handleZoneTap(_ResolvedChildZone entry) {
    final renderObject = _mapKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final origin = renderObject.localToGlobal(Offset.zero);
    final sourceRect = entry.nominalRect.shift(origin);
    widget.onDebugLog(
      'child_zone_tapped',
      <String, Object?>{
        'parent': entry.zone.group,
        'child': entry.zone.child,
        'effectiveShape': entry.useEffectiveShape
            ? 'child_slot_area_ids_difference_path'
            : 'nominal_rect_tower',
        'containedParkingAreas': entry.containedParkingAreaCount,
        'ownedParkingAreas': entry.ownedParkingAreaCount,
        'cutParkingAreas': entry.cutParkingAreaCount,
        'hitTest': 'effective_path_contains',
        'transitionSource': 'nominal_child_rect',
      },
    );
    widget.onZoneTap(entry.zone, sourceRect);
  }

  void _showZonePeek(_ResolvedChildZone entry, Offset localPosition) {
    _peekEpoch++;
    final anchor = Offset(
      entry.hitRect.left + localPosition.dx,
      entry.hitRect.top + localPosition.dy,
    );
    setState(() {
      _peekZoneKey = entry.zone.fullName;
      _peekAnchor = anchor;
      _peekVisible = true;
    });
    widget.onUserActivity();
    HapticFeedback.mediumImpact();
    widget.onDebugLog(
      'child_zone_peek_started',
      <String, Object?>{
        'parent': entry.zone.group,
        'child': entry.zone.child,
        'remaining': entry.zone.remaining,
        'capacity': entry.zone.capacity,
        'current': entry.zone.current,
        'anchor': '${anchor.dx.toStringAsFixed(1)},${anchor.dy.toStringAsFixed(1)}',
        'effectiveShape': entry.useEffectiveShape
            ? 'child_slot_area_ids_difference_path'
            : 'nominal_rect_tower',
        'containedParkingAreas': entry.containedParkingAreaCount,
        'ownedParkingAreas': entry.ownedParkingAreaCount,
        'cutParkingAreas': entry.cutParkingAreaCount,
        'hitTest': 'effective_path_contains',
        'action': 'peek_only',
        'childDialogOpened': false,
      },
    );
  }

  void _hideZonePeek(
    _ResolvedChildZone entry, {
    required String source,
  }) {
    if (_peekZoneKey != entry.zone.fullName) return;
    final epoch = ++_peekEpoch;
    if (_peekVisible) {
      setState(() => _peekVisible = false);
    }
    widget.onUserActivity();
    widget.onDebugLog(
      source == 'cancel' ? 'child_zone_peek_cancelled' : 'child_zone_peek_ended',
      <String, Object?>{
        'parent': entry.zone.group,
        'child': entry.zone.child,
        'remaining': entry.zone.remaining,
        'capacity': entry.zone.capacity,
        'source': source,
        'childDialogOpened': false,
      },
    );
    final delay = widget.reduceMotion ? Duration.zero : _kZonePeekHideDuration;
    if (delay == Duration.zero) {
      if (mounted && epoch == _peekEpoch) {
        setState(() {
          _peekZoneKey = null;
          _peekAnchor = null;
        });
      }
      return;
    }
    unawaited(
      Future<void>.delayed(delay).then<void>((_) {
        if (!mounted || epoch != _peekEpoch || _peekVisible) return;
        setState(() {
          _peekZoneKey = null;
          _peekAnchor = null;
        });
      }),
    );
  }

  @override
  void didUpdateWidget(covariant _ParentOverviewDotMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = _peekZoneKey;
    if (key == null) return;
    final exists = widget.group.zones.any((zone) => zone.fullName == key);
    if (exists) return;
    _peekEpoch++;
    _peekZoneKey = null;
    _peekAnchor = null;
    _peekVisible = false;
  }

  @override
  Widget build(BuildContext context) {
    final occupied = _occupiedSlots(widget.group);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final layout = ParkingStatusDotMapLayout.resolve(
          size: size,
          grid: widget.grid,
        );
        final zones = layout == null
            ? const <_ResolvedChildZone>[]
            : _resolveChildZones(
                zones: widget.group.zones,
                grid: widget.grid,
                layout: layout,
                minimum: _kZoneTouchTargetMin,
              );
        final labels = layout == null
            ? const <_ResolvedOccupiedSlot>[]
            : _resolveOccupiedLabels(
                occupied: occupied,
                layout: layout,
              );
        _recordResolvedGeometry(zones);

        return SizedBox(
          key: _mapKey,
          width: size.width,
          height: size.height,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: ParkingStatusDotMapSurface(
                  grid: widget.grid,
                  framed: false,
                ),
              ),
              for (final entry in zones)
                _ChildZoneVisualOverlay(
                  key: ValueKey<String>('zone-visual:${entry.zone.fullName}'),
                  entry: entry,
                  selected: widget.selectedZoneKey == entry.zone.fullName,
                  peeked: _peekZoneKey == entry.zone.fullName && _peekVisible,
                  reduceMotion: widget.reduceMotion,
                ),
              for (final entry in labels)
                _OccupiedSlotLabel(
                  key: ValueKey<String>(
                    'overview-label:${entry.slot.zone.fullName}:${entry.slot.slot.no}:${entry.slot.row.plateId}',
                  ),
                  entry: entry,
                  reduceMotion: widget.reduceMotion,
                ),
              for (final entry in zones)
                _ChildZoneHitOverlay(
                  key: ValueKey<String>('zone-hit:${entry.zone.fullName}'),
                  entry: entry,
                  onTap: () => _handleZoneTap(entry),
                  onLongPressStart: (position) =>
                      _showZonePeek(entry, position),
                  onLongPressEnd: () =>
                      _hideZonePeek(entry, source: 'release'),
                  onLongPressCancel: () =>
                      _hideZonePeek(entry, source: 'cancel'),
                ),
              if (_peekZoneKey != null && _peekAnchor != null)
                _ChildZonePeekBubble(
                  key: ValueKey<String>('zone-peek:$_peekZoneKey'),
                  zone: widget.group.zones.firstWhere(
                    (zone) => zone.fullName == _peekZoneKey,
                  ),
                  anchor: _peekAnchor!,
                  mapSize: size,
                  visible: _peekVisible,
                  reduceMotion: widget.reduceMotion,
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
    required this.zone,
    required this.grid,
    required this.revealProgress,
    required this.onPlateTap,
    required this.reduceMotion,
    this.interactionEnabled = true,
  });

  final ZoneVM zone;
  final ParkingGridModel grid;
  final double revealProgress;
  final ValueChanged<_OccupiedSlot> onPlateTap;
  final bool reduceMotion;
  final bool interactionEnabled;

  @override
  Widget build(BuildContext context) {
    final viewport = _resolveNominalChildRect(zone, grid);
    if (viewport == null) {
      return const _InlineEmpty(message: '자식 주차 구역 DOT MAP 데이터가 없습니다.');
    }
    final effectiveAreaIds = resolvedChildParkingAreaIds(zone.source);
    final useEffectiveShape = !zone.source.isTowerChild;
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
        Rect? nominalRect;
        Path? effectivePath;
        if (layout != null) {
          nominalRect = layout.rectFor(viewport).intersect(layout.mapRect);
          if (!nominalRect.isEmpty) {
            effectivePath = buildEffectiveChildRegionPath(
              grid: grid,
              childRect: viewport,
              effectiveParkingAreaIds: effectiveAreaIds,
              nominalRegion: RRect.fromRectAndRadius(
                nominalRect,
                const Radius.circular(8),
              ),
              useEffectiveShape: useEffectiveShape,
              parkingAreaRect: (area) => layout.rectFor(
                GridRect(
                  r0: area.r0,
                  c0: area.c0,
                  r1: area.r1,
                  c1: area.c1,
                ),
              ),
              cutInflate: math.max(.5, layout.scale * .035),
              cutRadius: math.max(3.0, layout.scale * .13),
            );
          }
        }
        final regionProgress = reduceMotion
            ? 1.0
            : ((revealProgress - .28) / .72).clamp(0.0, 1.0).toDouble();

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
                  visibleParkingAreaIds:
                      useEffectiveShape ? effectiveAreaIds : null,
                  framed: false,
                ),
              ),
              if (nominalRect != null && effectivePath != null)
                _ChildFocusRegionOverlay(
                  nominalRect: nominalRect,
                  effectivePath: effectivePath,
                  useEffectiveShape: useEffectiveShape,
                  progress: regionProgress,
                ),
              for (final entry in resolved)
                if (interactionEnabled)
                  _OccupiedSlotOverlay(
                    key: ValueKey<String>(
                      'child-slot:${entry.slot.zone.fullName}:${entry.slot.slot.no}:${entry.slot.row.plateId}',
                    ),
                    entry: entry,
                    onTap: () => onPlateTap(entry.slot),
                    reduceMotion: reduceMotion,
                  )
                else
                  _OccupiedSlotLabel(
                    key: ValueKey<String>(
                      'child-slot-label:${entry.slot.zone.fullName}:${entry.slot.slot.no}:${entry.slot.row.plateId}',
                    ),
                    entry: entry,
                    reduceMotion: reduceMotion,
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _ChildFocusRegionOverlay extends StatelessWidget {
  const _ChildFocusRegionOverlay({
    required this.nominalRect,
    required this.effectivePath,
    required this.useEffectiveShape,
    required this.progress,
  });

  final Rect nominalRect;
  final Path effectivePath;
  final bool useEffectiveShape;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _ChildFocusRegionPainter(
            nominalRect: nominalRect,
            effectivePath: effectivePath,
            useEffectiveShape: useEffectiveShape,
            progress: progress,
            fillColor: cs.primary,
            strokeColor: cs.primary,
            nominalStrokeColor: cs.outlineVariant,
          ),
        ),
      ),
    );
  }
}

class _ChildFocusRegionPainter extends CustomPainter {
  const _ChildFocusRegionPainter({
    required this.nominalRect,
    required this.effectivePath,
    required this.useEffectiveShape,
    required this.progress,
    required this.fillColor,
    required this.strokeColor,
    required this.nominalStrokeColor,
  });

  final Rect nominalRect;
  final Path effectivePath;
  final bool useEffectiveShape;
  final double progress;
  final Color fillColor;
  final Color strokeColor;
  final Color nominalStrokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final eased = Curves.easeOutCubic.transform(
      progress.clamp(0.0, 1.0).toDouble(),
    );
    if (eased <= 0) return;
    final center = nominalRect.center;
    final scale = .985 + .015 * eased;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale, scale);
    canvas.translate(-center.dx, -center.dy);
    if (useEffectiveShape) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          nominalRect,
          const Radius.circular(8),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = nominalStrokeColor.withOpacity(.28 * eased),
      );
    }
    canvas.drawPath(
      effectivePath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = fillColor.withOpacity(.035 * eased),
    );
    canvas.drawPath(
      effectivePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15 + .45 * eased
        ..strokeJoin = StrokeJoin.round
        ..color = strokeColor.withOpacity(.46 * eased),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ChildFocusRegionPainter oldDelegate) {
    return oldDelegate.nominalRect != nominalRect ||
        oldDelegate.effectivePath != effectivePath ||
        oldDelegate.useEffectiveShape != useEffectiveShape ||
        oldDelegate.progress != progress ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.nominalStrokeColor != nominalStrokeColor;
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
    required this.nominalRect,
    required this.effectivePath,
    required this.hitRect,
    required this.useEffectiveShape,
    required this.containedParkingAreaCount,
    required this.ownedParkingAreaCount,
    required this.cutParkingAreaCount,
  });

  final ZoneVM zone;
  final Rect nominalRect;
  final Path effectivePath;
  final Rect hitRect;
  final bool useEffectiveShape;
  final int containedParkingAreaCount;
  final int ownedParkingAreaCount;
  final int cutParkingAreaCount;
}

class _ChildZoneVisualOverlay extends StatefulWidget {
  const _ChildZoneVisualOverlay({
    super.key,
    required this.entry,
    required this.selected,
    required this.peeked,
    required this.reduceMotion,
  });

  final _ResolvedChildZone entry;
  final bool selected;
  final bool peeked;
  final bool reduceMotion;

  @override
  State<_ChildZoneVisualOverlay> createState() => _ChildZoneVisualOverlayState();
}

class _ChildZoneVisualOverlayState extends State<_ChildZoneVisualOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _highlightController;

  bool get _highlighted => widget.selected || widget.peeked;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.reduceMotion ? 1 : 0,
    );
    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 170),
      value: _highlighted ? 1 : 0,
    );
    if (!widget.reduceMotion) {
      _entryController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _ChildZoneVisualOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) {
      _entryController.value = 1;
      _highlightController.value = _highlighted ? 1 : 0;
      return;
    }
    if (oldWidget.reduceMotion && !widget.reduceMotion) {
      _entryController.value = 1;
    }
    final target = _highlighted ? 1.0 : 0.0;
    if (_highlightController.value != target) {
      _highlightController.animateTo(
        target,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    _highlightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final localPath = widget.entry.effectivePath.shift(
      -widget.entry.nominalRect.topLeft,
    );
    final localNominalRect = Offset.zero & widget.entry.nominalRect.size;

    return Positioned.fromRect(
      rect: widget.entry.nominalRect,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _entryController,
          builder: (context, _) {
            final entryProgress = Curves.easeOutCubic.transform(
              _entryController.value.clamp(0.0, 1.0).toDouble(),
            );
            return AnimatedBuilder(
              animation: _highlightController,
              builder: (context, _) {
                final highlightProgress = Curves.easeOutCubic.transform(
                  _highlightController.value.clamp(0.0, 1.0).toDouble(),
                );
                final scale =
                    (.97 + .03 * entryProgress) * (1 + .012 * highlightProgress);
                return Opacity(
                  opacity: entryProgress,
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.center,
                    child: CustomPaint(
                      painter: _ChildZoneRegionPainter(
                        nominalRect: localNominalRect,
                        effectivePath: localPath,
                        useEffectiveShape: widget.entry.useEffectiveShape,
                        highlightProgress: highlightProgress,
                        fillColor: cs.primary,
                        strokeColor: cs.primary,
                        nominalStrokeColor: cs.outlineVariant,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ChildZoneRegionPainter extends CustomPainter {
  const _ChildZoneRegionPainter({
    required this.nominalRect,
    required this.effectivePath,
    required this.useEffectiveShape,
    required this.highlightProgress,
    required this.fillColor,
    required this.strokeColor,
    required this.nominalStrokeColor,
  });

  final Rect nominalRect;
  final Path effectivePath;
  final bool useEffectiveShape;
  final double highlightProgress;
  final Color fillColor;
  final Color strokeColor;
  final Color nominalStrokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final highlight =
        highlightProgress.clamp(0.0, 1.0).toDouble();
    if (useEffectiveShape) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          nominalRect,
          const Radius.circular(8),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = nominalStrokeColor.withOpacity(.34 + .08 * highlight),
      );
    }
    if (highlight > 0) {
      canvas.drawShadow(
        effectivePath,
        strokeColor.withOpacity(.14 * highlight),
        5 + 3 * highlight,
        false,
      );
    }
    canvas.drawPath(
      effectivePath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = fillColor.withOpacity(.045 + .055 * highlight),
    );
    canvas.drawPath(
      effectivePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 + .8 * highlight
        ..strokeJoin = StrokeJoin.round
        ..color = strokeColor.withOpacity(.46 + .42 * highlight),
    );
  }

  @override
  bool shouldRepaint(covariant _ChildZoneRegionPainter oldDelegate) {
    return oldDelegate.nominalRect != nominalRect ||
        oldDelegate.effectivePath != effectivePath ||
        oldDelegate.useEffectiveShape != useEffectiveShape ||
        oldDelegate.highlightProgress != highlightProgress ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.nominalStrokeColor != nominalStrokeColor;
  }
}

class _ChildZoneHitOverlay extends StatelessWidget {
  const _ChildZoneHitOverlay({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
  });

  final _ResolvedChildZone entry;
  final VoidCallback onTap;
  final ValueChanged<Offset> onLongPressStart;
  final VoidCallback onLongPressEnd;
  final VoidCallback onLongPressCancel;

  @override
  Widget build(BuildContext context) {
    final localPath = entry.effectivePath.shift(-entry.hitRect.topLeft);
    return Positioned.fromRect(
      rect: entry.hitRect,
      child: Semantics(
        button: true,
        label: '${entry.zone.group} ${entry.zone.child} 주차 구역',
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTap: onTap,
          onLongPressStart: (details) =>
              onLongPressStart(details.localPosition),
          onLongPressEnd: (_) => onLongPressEnd(),
          onLongPressCancel: onLongPressCancel,
          child: CustomPaint(
            painter: _ChildZoneHitTestPainter(localPath),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _ChildZoneHitTestPainter extends CustomPainter {
  const _ChildZoneHitTestPainter(this.path);

  final Path path;

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool? hitTest(Offset position) => path.contains(position);

  @override
  bool shouldRepaint(covariant _ChildZoneHitTestPainter oldDelegate) {
    return oldDelegate.path != path;
  }
}

class _ChildZonePeekBubble extends StatelessWidget {
  const _ChildZonePeekBubble({
    super.key,
    required this.zone,
    required this.anchor,
    required this.mapSize,
    required this.visible,
    required this.reduceMotion,
  });

  final ZoneVM zone;
  final Offset anchor;
  final Size mapSize;
  final bool visible;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final remaining = zone.remaining ?? math.max(0, zone.capacity - zone.current);
    final availableWidth = math.max(56.0, mapSize.width - 12).toDouble();
    final preferredWidth =
        math.min(156.0, math.max(88.0, mapSize.width * .4)).toDouble();
    final width = math.min(preferredWidth, availableWidth).toDouble();
    const height = 30.0;
    const edge = 6.0;
    final maxLeft = math.max(edge, mapSize.width - width - edge).toDouble();
    final left = (anchor.dx - width / 2).clamp(edge, maxLeft).toDouble();
    var top = anchor.dy - height - 46;
    if (top < edge) {
      top = anchor.dy + 32;
    }
    final maxTop = math.max(edge, mapSize.height - height - edge).toDouble();
    top = top.clamp(edge, maxTop).toDouble();
    final showDuration = reduceMotion ? Duration.zero : _kZonePeekShowDuration;
    final hideDuration = reduceMotion ? Duration.zero : _kZonePeekHideDuration;
    final duration = visible ? showDuration : hideDuration;
    final curve = visible ? Curves.easeOutCubic : Curves.easeInCubic;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: IgnorePointer(
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, .16),
          duration: duration,
          curve: curve,
          child: AnimatedScale(
            scale: visible ? 1 : .94,
            duration: duration,
            curve: curve,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: duration,
              curve: curve,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surface.withOpacity(.97),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(.76),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withOpacity(.16),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          zone.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelSmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '$remaining/${zone.capacity}',
                        maxLines: 1,
                        style: text.labelSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w900,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ],
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

class _OccupiedSlotLabel extends StatelessWidget {
  const _OccupiedSlotLabel({
    super.key,
    required this.entry,
    required this.reduceMotion,
    this.pressed = false,
  });

  final _ResolvedOccupiedSlot entry;
  final bool reduceMotion;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final row = entry.slot.row;
    final last4 = _plateLast4(row.plateNumber);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
    final pressDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 90);

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
          child: AnimatedScale(
            scale: pressed ? .965 : 1,
            duration: pressDuration,
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(pressed ? 1 : .9),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: cs.primary.withOpacity(pressed ? .96 : .72),
                  width: pressed ? 1.4 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withOpacity(pressed ? .14 : .08),
                    blurRadius: pressed ? 7 : 4,
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
      ),
    );
  }
}

class _OccupiedSlotOverlay extends StatefulWidget {
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
  State<_OccupiedSlotOverlay> createState() => _OccupiedSlotOverlayState();
}

class _OccupiedSlotOverlayState extends State<_OccupiedSlotOverlay> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.entry.slot.row;
    return Stack(
      children: [
        _OccupiedSlotLabel(
          entry: widget.entry,
          reduceMotion: widget.reduceMotion,
          pressed: _pressed,
        ),
        Positioned.fromRect(
          rect: widget.entry.hitRect,
          child: Semantics(
            button: true,
            label:
                '${widget.entry.slot.zone.group} ${widget.entry.slot.zone.child} 슬롯 ${widget.entry.slot.slot.no}, 번호판 ${row.plateNumber}, 상태 처리 빠른 실행',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onHighlightChanged: _setPressed,
                onTap: widget.onTap,
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
  final nominalRects = <Rect>[];
  final effectivePaths = <Path>[];
  final useEffectiveShapes = <bool>[];
  final stats = <EffectiveChildRegionStats>[];
  for (final zone in zones) {
    final childRect = _resolveNominalChildRect(zone, grid);
    if (childRect == null) continue;
    final nominalRect = layout.rectFor(childRect).intersect(layout.mapRect);
    if (nominalRect.isEmpty ||
        nominalRect.width <= 0 ||
        nominalRect.height <= 0) {
      continue;
    }
    final effectiveAreaIds = resolvedChildParkingAreaIds(zone.source);
    final useEffectiveShape = !zone.source.isTowerChild;
    final regionStats = effectiveChildRegionStats(
      grid: grid,
      childRect: childRect,
      effectiveParkingAreaIds: effectiveAreaIds,
    );
    final effectivePath = buildEffectiveChildRegionPath(
      grid: grid,
      childRect: childRect,
      effectiveParkingAreaIds: effectiveAreaIds,
      nominalRegion: RRect.fromRectAndRadius(
        nominalRect,
        const Radius.circular(8),
      ),
      useEffectiveShape: useEffectiveShape,
      parkingAreaRect: (area) => layout.rectFor(
        GridRect(
          r0: area.r0,
          c0: area.c0,
          r1: area.r1,
          c1: area.c1,
        ),
      ),
      cutInflate: math.max(.5, layout.scale * .035),
      cutRadius: math.max(3.0, layout.scale * .13),
    );
    mapped.add(zone);
    nominalRects.add(nominalRect);
    effectivePaths.add(effectivePath);
    useEffectiveShapes.add(useEffectiveShape);
    stats.add(regionStats);
  }

  final hits = <Rect>[
    for (final nominalRect in nominalRects)
      _minimumHitRect(nominalRect, layout.mapRect, minimum),
  ];

  for (var i = 0; i < hits.length; i++) {
    for (var j = i + 1; j < hits.length; j++) {
      if (!hits[i].overlaps(hits[j])) continue;
      if (nominalRects[i].overlaps(nominalRects[j])) continue;
      final separated = _separateHitRects(
        firstVisual: nominalRects[i],
        secondVisual: nominalRects[j],
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
          nominalRect: nominalRects[i],
          effectivePath: effectivePaths[i],
          hitRect: hits[i],
          useEffectiveShape: useEffectiveShapes[i],
          containedParkingAreaCount: stats[i].containedParkingAreaCount,
          ownedParkingAreaCount: stats[i].ownedParkingAreaCount,
          cutParkingAreaCount: stats[i].cutParkingAreaCount,
        ),
  ];
}

GridRect? _resolveNominalChildRect(ZoneVM zone, ParkingGridModel grid) {
  return resolveParkingSpatialChildRect(zone.source, grid);
}

(Rect, Rect) _separateHitRects({
  required Rect firstVisual,
  required Rect secondVisual,
  required Rect firstHit,
  required Rect secondHit,
}) {
  return parkingSpatialSeparateHitRects(
    firstVisual: firstVisual,
    secondVisual: secondVisual,
    firstHit: firstHit,
    secondHit: secondHit,
  );
}

Rect _minimumHitRect(Rect source, Rect bounds, double minimum) {
  return parkingSpatialMinimumHitRect(source, bounds, minimum);
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
