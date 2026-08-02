import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/utils/status_dialog.dart';
import '../../features/account/applications/user_state.dart';
import '../../features/dev/application/area_state.dart';
import '../../features/chat/presentation/area_chat_panel.dart';
import '../../features/voice/application/voice_appbar_ui_state.dart';
import '../page/application/common/type_auto_transition_guard.dart';
import '../page/application/common/type_view_mode_state.dart';
import '../plate/application/common/view_doc_rows_store.dart';
import 'real_time_tab_controller.dart';
import 'real_time_table_body.dart';
import 'real_time_table_components.dart';
import 'real_time_table_spec.dart';

class RealTimeViewModeAutoSpec {
  final Duration idleToStatusAfter;
  final Set<String> tabIdsForceTableOnTap;

  const RealTimeViewModeAutoSpec({
    this.idleToStatusAfter = const Duration(seconds: 5),
    this.tabIdsForceTableOnTap = const {
      'parking_requests',
      'parking_completed',
      'departure_requests',
    },
  });
}

class RealTimeTabbedTable extends StatefulWidget {
  final List<RealTimeTabSpec> tabs;
  final RealTimeTabBarStyle tabBarStyle;
  final int initialIndex;
  final String screen;
  final String description;
  final Widget Function(
      BuildContext context,
      RealTimeTabSpec spec,
      RealTimeTabController controller,
      )? bodyBuilder;

  final RealTimeViewModeAutoSpec? viewModeAuto;

  const RealTimeTabbedTable({
    super.key,
    required this.tabs,
    required this.tabBarStyle,
    required this.initialIndex,
    required this.screen,
    required this.description,
    this.bodyBuilder,
    this.viewModeAuto,
  }) : assert(tabs.length > 0);

  @override
  State<RealTimeTabbedTable> createState() => _RealTimeTabbedTableState();
}

class _RealTimeTabbedTableState extends State<RealTimeTabbedTable>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  late final List<RealTimeTabController> _controllers;

  bool _gatesLoaded = false;
  late List<bool> _enabled;

  TypeViewModeState? _viewMode;
  VoiceAppbarUiState? _talkUi;
  TypeAutoTransitionGuard? _autoGuard;
  Timer? _idleTimer;
  bool _idleSyncScheduled = false;

  bool _transitionMaskOn = false;
  String _transitionMaskMessage = '구역 불러오는 중...';
  bool _handlingTap = false;
  bool _debugDialogShowing = false;

  @override
  void initState() {
    super.initState();

    _enabled = List<bool>.filled(widget.tabs.length, false);
    _controllers = List<RealTimeTabController>.generate(
      widget.tabs.length,
          (_) => RealTimeTabController(),
    );

    _tabCtrl = TabController(
      length: widget.tabs.length,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, widget.tabs.length - 1),
    );

    _tabCtrl.addListener(() {
      if (!mounted) return;
      setState(() {});
    });

    _loadGates();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachAutoGuardListener();
    _attachTalkUiListener();
    if (widget.viewModeAuto == null) {
      _detachViewModeListener();
      return;
    }
    TypeViewModeState? next;
    try {
      next = context.read<TypeViewModeState>();
    } catch (_) {
      next = null;
    }
    if (_viewMode != next) {
      _detachViewModeListener();
      _viewMode = next;
      _viewMode?.addListener(_onViewModeChanged);
    }
    _scheduleIdleSyncAfterBuild();
  }

  void _scheduleIdleSyncAfterBuild() {
    if (_idleSyncScheduled) return;
    _idleSyncScheduled = true;
    _debugLog('idle_sync_scheduled', <String, Object?>{
      'screen': widget.screen,
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _idleSyncScheduled = false;
      if (!mounted) return;
      _debugLog('idle_sync_after_build', <String, Object?>{
        'mode': _viewMode?.mode.name,
        'talk': _talkUi?.enabled == true,
      });
      _syncIdleWithMode();
    });
  }

  void _attachAutoGuardListener() {
    TypeAutoTransitionGuard? next;
    try {
      next = context.read<TypeAutoTransitionGuard>();
    } catch (_) {
      next = null;
    }
    if (_autoGuard == next) return;
    _autoGuard?.removeListener(_onAutoGuardChanged);
    _autoGuard = next;
    _autoGuard?.addListener(_onAutoGuardChanged);
    final auto = widget.viewModeAuto;
    _debugLog('initialized', <String, Object?>{
      'idleMs': auto?.idleToStatusAfter.inMilliseconds,
      'screen': widget.screen,
    });
  }

  void _detachAutoGuardListener() {
    _autoGuard?.removeListener(_onAutoGuardChanged);
    _autoGuard = null;
  }

  void _onAutoGuardChanged() {
    if (!mounted) return;
    _scheduleIdleFromGuard();
  }

  void _attachTalkUiListener() {
    VoiceAppbarUiState? next;
    try {
      next = context.read<VoiceAppbarUiState>();
    } catch (_) {
      next = null;
    }
    if (_talkUi == next) return;
    _talkUi?.removeListener(_onTalkUiChanged);
    _talkUi = next;
    _talkUi?.addListener(_onTalkUiChanged);
  }

  void _detachTalkUiListener() {
    _talkUi?.removeListener(_onTalkUiChanged);
    _talkUi = null;
  }

  void _onTalkUiChanged() {
    if (!mounted) return;
    _debugLog('talk_ui_changed', <String, Object?>{
      'enabled': _talkUi?.enabled == true,
    });
    _syncIdleWithMode();
    setState(() {});
  }

  void _detachViewModeListener() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _viewMode?.removeListener(_onViewModeChanged);
    _viewMode = null;
  }

  void _onViewModeChanged() {
    if (!mounted) return;
    _debugLog('view_mode_changed', <String, Object?>{
      'mode': _viewMode?.mode.name,
    });
    _syncIdleWithMode();
  }

  void _syncIdleWithMode() {
    final auto = widget.viewModeAuto;
    final vm = _viewMode;
    final guard = _autoGuard;
    if (auto == null || vm == null || guard == null) {
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }

    guard.setCountdownDuration(auto.idleToStatusAfter);

    if (_talkUi?.enabled == true) {
      guard.setCountdownEnabled(false, reason: 'Talk');
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }

    if (vm.mode != TypeViewMode.table) {
      guard.setCountdownEnabled(false, reason: '현황 모드');
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }

    guard.setCountdownEnabled(true, reason: '테이블 모드');
    _scheduleIdleFromGuard();
  }

  void _debugLog(
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {
    final guard = _autoGuard;
    if (guard != null) {
      guard.log(event, details);
      return;
    }
    final buffer = StringBuffer()
      ..write('[RealTimeViewMode] ')
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
    debugPrint(buffer.toString());
  }

  Future<void> _showAutoSwitchDebugDialog() async {
    final guard = _autoGuard;
    if (!mounted || _debugDialogShowing || guard == null) return;
    await guard.refreshDeveloperMode();
    if (!guard.developerModeEnabled || !mounted || _debugDialogShowing) return;
    final code = guard.debugPrintCode.trim();
    if (code.isEmpty) return;
    _debugDialogShowing = true;
    try {
      await StatusDialog.showSuccess(
        context,
        title: '현황 자동 전환 디버그',
        description: guard.debugLines.join('\n'),
        copyText: code,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: const Duration(seconds: 45),
        useCommonUi: true,
      );
    } finally {
      _debugDialogShowing = false;
    }
  }

  void _scheduleIdleFromGuard() {
    _idleTimer?.cancel();
    _idleTimer = null;
    final auto = widget.viewModeAuto;
    final guard = _autoGuard;
    final vm = _viewMode;
    if (auto == null || guard == null || vm == null) return;
    if (_talkUi?.enabled == true) return;
    if (vm.mode != TypeViewMode.table) return;
    if (!guard.countdownRunning) return;

    final remaining = guard.remaining;
    _idleTimer = Timer(remaining, () {
      if (!mounted) return;
      final currentGuard = _autoGuard;
      final currentVm = _viewMode;
      if (currentGuard == null || currentVm == null) return;
      if (_talkUi?.enabled == true) return;
      if (currentVm.mode != TypeViewMode.table) return;
      if (!currentGuard.countdownElapsed) {
        _scheduleIdleFromGuard();
        return;
      }
      _debugLog('idle_timeout', <String, Object?>{
        'thresholdMs': auto.idleToStatusAfter.inMilliseconds,
        'tab': widget.tabs[_tabCtrl.index].id,
      });
      unawaited(_runMaskedAutoSwitchToStatus(auto));
    });
  }

  Future<void> _runMaskedAutoSwitchToStatus(
    RealTimeViewModeAutoSpec auto,
  ) async {
    if (!mounted) return;
    if (_transitionMaskOn) return;
    final guard = _autoGuard;
    final vm = _viewMode;
    if (guard == null || vm == null) return;
    if (_talkUi?.enabled == true) return;
    if (vm.mode != TypeViewMode.table) return;
    if (!guard.countdownElapsed) return;

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (_transitionMaskOn) return;
    if (_talkUi?.enabled == true) return;
    if (_viewMode?.mode != TypeViewMode.table) return;
    if (!guard.countdownElapsed) {
      _debugLog('auto_switch_cancelled', <String, Object?>{
        'reason': guard.isBlocked ? guard.blockReason : 'activity',
      });
      return;
    }

    _debugLog('auto_switch_started', <String, Object?>{
      'from': TypeViewMode.table.name,
      'to': TypeViewMode.status.name,
      'thresholdMs': auto.idleToStatusAfter.inMilliseconds,
      'tab': widget.tabs[_tabCtrl.index].id,
    });

    setState(() {
      _transitionMaskMessage = '현황 전환 중...';
      _transitionMaskOn = true;
    });

    final started = DateTime.now();
    var switched = false;

    try {
      vm.setMode(TypeViewMode.status);
      switched = true;
      _debugLog('auto_switch_completed', <String, Object?>{
        'mode': TypeViewMode.status.name,
      });
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      final elapsed = DateTime.now().difference(started);
      const min = Duration(milliseconds: 500);
      if (elapsed < min) {
        await Future.delayed(min - elapsed);
      }
      if (!mounted) return;
      setState(() {
        _transitionMaskOn = false;
        _transitionMaskMessage = '구역 불러오는 중...';
      });
    }

    if (switched && mounted) {
      unawaited(_showAutoSwitchDebugDialog());
    }
  }

  void _onUserActivity() {
    _autoGuard?.markActivity('table_body');
  }

  void _beginAutoPause() {
    _autoGuard?.beginBlock('테이블 다이얼로그');
  }

  void _endAutoPause() {
    _autoGuard?.endBlock('테이블 다이얼로그');
  }

  bool _shouldForceTableOnTap(int index) {
    final auto = widget.viewModeAuto;
    final vm = _viewMode;
    if (auto == null || vm == null) return false;
    if (vm.mode != TypeViewMode.status) return false;
    final id = widget.tabs[index].id;
    return auto.tabIdsForceTableOnTap.contains(id);
  }

  Duration _motionDuration(Duration duration) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return reduceMotion ? Duration.zero : duration;
  }

  Widget _sharedAxisYTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final offset = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(curved);
    final scale = Tween<double>(begin: 0.985, end: 1).animate(curved);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: offset,
        child: ScaleTransition(
          scale: scale,
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }

  Widget _transitionMaskSurface(
    BuildContext context, {
    required String message,
  }) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AbsorbPointer(
      absorbing: true,
      child: Container(
        color: cs.surface,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 44,
              width: 44,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: (text.titleMedium ?? text.bodyLarge ?? const TextStyle())
                  .copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transitionMaskLayer(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_transitionMaskOn,
        child: AnimatedSwitcher(
          duration: _motionDuration(const Duration(milliseconds: 240)),
          reverseDuration: _motionDuration(const Duration(milliseconds: 180)),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
                child: child,
              ),
            );
          },
          child: _transitionMaskOn
              ? KeyedSubtree(
                  key: ValueKey<String>(
                    'transition-mask:$_transitionMaskMessage',
                  ),
                  child: _transitionMaskSurface(
                    context,
                    message: _transitionMaskMessage,
                  ),
                )
              : const SizedBox.expand(
                  key: ValueKey<String>('transition-mask-off'),
                ),
        ),
      ),
    );
  }

  Future<void> _runMaskedTabTransition(int index) async {
    if (!mounted) return;
    if (_transitionMaskOn) return;
    setState(() {
      _transitionMaskMessage = '구역 불러오는 중...';
      _transitionMaskOn = true;
    });

    final started = DateTime.now();

    try {
      if (_shouldForceTableOnTap(index)) {
        await _switchStatusToTableAndRefresh(index);
      } else {
        _requestRefreshForIndex(index);
        await WidgetsBinding.instance.endOfFrame;
      }
    } finally {
      final elapsed = DateTime.now().difference(started);
      const min = Duration(milliseconds: 500);
      if (elapsed < min) {
        await Future.delayed(min - elapsed);
      }
      if (!mounted) return;
      setState(() {
        _transitionMaskOn = false;
      });
    }
  }

  Future<void> _switchStatusToTableAndRefresh(int index) async {
    final ctrl = _controllers[index];
    final vm = _viewMode;

    ctrl.unbind();

    if (vm != null && vm.mode == TypeViewMode.status) {
      _debugLog('manual_return_to_table', <String, Object?>{
        'tab': widget.tabs[index].id,
      });
      vm.setMode(TypeViewMode.table);
    }

    await WidgetsBinding.instance.endOfFrame;

    try {
      await ctrl.waitUntilBound().timeout(const Duration(seconds: 2));
    } catch (_) {}

    if (!mounted) return;
    if (!_gatesLoaded) return;
    if (!_isTabEnabled(index)) return;

    if (ctrl.isBound) {
      await ctrl.refreshUser();
    } else {
      _requestRefreshForIndex(index);
    }

    _syncIdleWithMode();
  }

  @override
  void dispose() {
    _detachViewModeListener();
    _detachTalkUiListener();
    _detachAutoGuardListener();
    _tabCtrl.dispose();
    super.dispose();
  }

  int _firstEnabledTabOr(int fallback) {
    for (int i = 0; i < _enabled.length; i++) {
      if (_enabled[i]) return i;
    }
    return fallback;
  }

  Future<void> _loadGates() async {
    try {
      final results = <bool>[];
      for (final t in widget.tabs) {
        results.add(await t.isEnabled());
      }

      if (!mounted) return;

      setState(() {
        _enabled = results;
        _gatesLoaded = true;
        _tabCtrl.index = _firstEnabledTabOr(_tabCtrl.index);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enabled = List<bool>.filled(widget.tabs.length, false);
        _gatesLoaded = true;
        _tabCtrl.index = widget.initialIndex.clamp(0, widget.tabs.length - 1);
      });
    }
  }

  bool _isTabEnabled(int idx) {
    if (idx < 0 || idx >= _enabled.length) return false;
    return _enabled[idx];
  }

  void _requestRefreshForIndex(int index) {
    final ctrl = _controllers[index];

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!_gatesLoaded) return;
      if (!_isTabEnabled(index)) return;

      if (ctrl.isBound) {
        await ctrl.refreshUser();
        return;
      }

      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      if (!_gatesLoaded) return;
      if (!_isTabEnabled(index)) return;

      await ctrl.refreshUser();
    });
  }

  Future<void> _onTapTab(int index) async {
    if (_handlingTap) return;
    _handlingTap = true;
    if (!_gatesLoaded) {
      _handlingTap = false;
      return;
    }

    if (!_isTabEnabled(index)) {
      _tabCtrl.animateTo(_firstEnabledTabOr(_tabCtrl.index));
      _handlingTap = false;
      return;
    }

    if (_talkUi?.enabled == true) {
      _handlingTap = false;
      return;
    }

    _onUserActivity();
    try {
      final guard = _autoGuard;
      if (guard == null) {
        await _runMaskedTabTransition(index);
      } else {
        await guard.runBlocked<void>(
          '탭 전환',
          () => _runMaskedTabTransition(index),
        );
      }
    } finally {
      _handlingTap = false;
    }
  }

  String _resolveArea() {
    final userArea =
    context.select<UserState, String>((s) => s.currentArea.trim());
    final stateArea =
    context.select<AreaState, String>((s) => s.currentArea.trim());
    return userArea.isNotEmpty ? userArea : stateArea;
  }

  Widget _countBadge({
    required String collection,
    required String area,
    required bool enabled,
    required bool selected,
    required Color accent,
  }) {
    final c = collection.trim();
    final a = area.trim();
    if (c.isEmpty || a.isEmpty) return const SizedBox.shrink();

    return Selector<ViewDocRowsStore, int>(
      selector: (_, store) => store.rows(collection: c, area: a).length,
      builder: (ctx, count, _) {
        final cs = Theme.of(ctx).colorScheme;
        final text = Theme.of(ctx).textTheme;
        final isDarkAccent =
            ThemeData.estimateBrightnessForColor(accent) == Brightness.dark;
        final fg = !enabled
            ? cs.outline
            : (selected
            ? (isDarkAccent ? Colors.white : Colors.black)
            : accent);

        final bg = !enabled
            ? cs.surfaceContainerLow.withOpacity(.70)
            : (selected ? accent : accent.withOpacity(.18));

        final bc = !enabled
            ? cs.outlineVariant.withOpacity(.55)
            : (selected ? accent.withOpacity(.95) : accent.withOpacity(.55));

        return AnimatedContainer(
          duration: _motionDuration(const Duration(milliseconds: 220)),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(left: 6),
          constraints: const BoxConstraints(minHeight: 24, minWidth: 28),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: bc),
          ),
          child: AnimatedSwitcher(
            duration: _motionDuration(const Duration(milliseconds: 180)),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
                  child: child,
                ),
              );
            },
            child: Text(
              '$count',
              key: ValueKey<int>(count),
              maxLines: 1,
              overflow: TextOverflow.fade,
              style: (text.labelMedium ?? text.bodyMedium ?? const TextStyle())
                  .copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: fg,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.0,
                letterSpacing: .1,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tabLabel({
    required String text,
    required String collection,
    required String area,
    required bool enabled,
    required bool selected,
    required Color accent,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!enabled) ...[
          Icon(Icons.lock_outline, size: 16, color: cs.outline.withOpacity(.9)),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        _countBadge(
          collection: collection,
          area: area,
          enabled: enabled,
          selected: selected,
          accent: accent,
        ),
      ],
    );
  }

  Widget _buildBottomTabBar(ColorScheme cs) {
    final area = _resolveArea();
    final idx = _tabCtrl.index.clamp(0, widget.tabs.length - 1);
    final current = widget.tabs[idx];
    final indicator = current.accent(cs);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: widget.tabBarStyle.containerColor(cs),
        border: Border(
          top: BorderSide(color: widget.tabBarStyle.borderColor(cs)),
        ),
      ),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: widget.tabBarStyle.pillColor(cs),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.tabBarStyle.borderColor(cs)),
        ),
        child: TabBar(
          controller: _tabCtrl,
          onTap: _onTapTab,
          labelColor: current.labelUsesAccent ? indicator : cs.onSurface,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: indicator,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          tabs: List<Widget>.generate(widget.tabs.length, (i) {
            final t = widget.tabs[i];
            return Tab(
              child: _tabLabel(
                text: t.label,
                collection: t.collection,
                area: area,
                enabled: _enabled[i],
                selected: i == _tabCtrl.index,
                accent: t.accent(cs),
              ),
            );
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final talkUiEnabled = _talkUi?.enabled ?? false;
    Widget out = Container(
      color: cs.surface,
      child: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: _motionDuration(const Duration(milliseconds: 320)),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: _sharedAxisYTransition,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              child: talkUiEnabled
                  ? const KeyedSubtree(
                      key: ValueKey<String>('area-chat-panel'),
                      child: AreaChatPanel(),
                    )
                  : KeyedSubtree(
                      key: const ValueKey<String>('real-time-tab-content'),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          TabBarView(
                            controller: _tabCtrl,
                            physics: const NeverScrollableScrollPhysics(),
                            children: List<Widget>.generate(widget.tabs.length, (i) {
                              final t = widget.tabs[i];
                              if (_isTabEnabled(i)) {
                                final table = KeyedSubtree(
                                  key: ValueKey<String>('table:${t.id}'),
                                  child: RealTimeTableBody(
                                    controller: _controllers[i],
                                    spec: t,
                                    description: widget.description,
                                    screen: widget.screen,
                                    onUserActivity: _onUserActivity,
                                    onAutoPauseStart: _beginAutoPause,
                                    onAutoPauseEnd: _endAutoPause,
                                  ),
                                );

                                final custom = widget.bodyBuilder;
                                final showCustom = custom != null;

                                final Widget activeChild = showCustom
                                    ? KeyedSubtree(
                                        key: ValueKey<String>('status:${t.id}'),
                                        child: custom(context, t, _controllers[i]),
                                      )
                                    : table;

                                return AnimatedSwitcher(
                                  duration: _motionDuration(const Duration(milliseconds: 320)),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: _sharedAxisYTransition,
                                  layoutBuilder: (currentChild, previousChildren) {
                                    return Stack(
                                      fit: StackFit.expand,
                                      children: <Widget>[
                                        ...previousChildren,
                                        if (currentChild != null) currentChild,
                                      ],
                                    );
                                  },
                                  child: activeChild,
                                );
                              }

                              return RealTimeLockedPanel(
                                title: '${t.label} 실시간 탭이 비활성화되어 있습니다',
                                message:
                                    '설정에서 “${t.label} 실시간 모드(탭) 사용”을 ON으로 변경한 뒤 다시 시도해 주세요.',
                              );
                            }),
                          ),
                          _transitionMaskLayer(context),
                        ],
                      ),
                    ),
            ),
          ),
          _buildBottomTabBar(cs),
        ],
      ),
    );

    return out;
  }
}
