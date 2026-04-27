import 'dart:async';

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../features/account/applications/user_state.dart';
import '../../../features/dev/application/area_state.dart';
import '../../../features/plate/application/common/view_doc_rows_store.dart';
import '../../../shared/page/application/common/type_view_mode_state.dart';

import 'real_time_tab_controller.dart';
import 'real_time_table_body.dart';
import 'real_time_table_components.dart';
import 'real_time_table_spec.dart';

class RealTimeViewModeAutoSpec {
  final Duration idleToStatusAfter;
  final Set<String> tabIdsForceTableOnTap;

  const RealTimeViewModeAutoSpec({
    this.idleToStatusAfter = const Duration(seconds: 3),
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
  Timer? _idleTimer;
  int _lastActivityAtMs = 0;

  bool _transitionMaskOn = false;
  String _transitionMaskMessage = '구역 불러오는 중...';
  bool _handlingTap = false;

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
    if (_viewMode == next) return;
    _detachViewModeListener();
    _viewMode = next;
    _viewMode?.addListener(_onViewModeChanged);
    _syncIdleWithMode();
  }

  void _detachViewModeListener() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _viewMode?.removeListener(_onViewModeChanged);
    _viewMode = null;
  }

  void _onViewModeChanged() {
    if (!mounted) return;
    _syncIdleWithMode();
  }

  void _syncIdleWithMode() {
    final auto = widget.viewModeAuto;
    final vm = _viewMode;
    if (auto == null || vm == null) {
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }
    if (vm.mode == TypeViewMode.table) {
      _scheduleIdle(auto);
    } else {
      _idleTimer?.cancel();
      _idleTimer = null;
    }
  }

  void _scheduleIdle(RealTimeViewModeAutoSpec auto) {
    _idleTimer?.cancel();
    _idleTimer = Timer(auto.idleToStatusAfter, () {
      if (!mounted) return;
      final vm = _viewMode;
      if (vm == null) return;
      if (widget.viewModeAuto == null) return;
      if (vm.mode != TypeViewMode.table) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastActivityAtMs < auto.idleToStatusAfter.inMilliseconds) {
        _scheduleIdle(auto);
        return;
      }
      _runMaskedAutoSwitchToStatus(auto);
    });
  }

  Future<void> _runMaskedAutoSwitchToStatus(
      RealTimeViewModeAutoSpec auto) async {
    if (!mounted) return;
    if (_transitionMaskOn) return;

    setState(() {
      _transitionMaskMessage = '현황 전환 중...';
      _transitionMaskOn = true;
    });

    final started = DateTime.now();

    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final vm = _viewMode;
      if (vm == null) return;
      if (widget.viewModeAuto == null) return;
      if (vm.mode != TypeViewMode.table) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastActivityAtMs < auto.idleToStatusAfter.inMilliseconds) {
        return;
      }

      vm.setMode(TypeViewMode.status);
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
  }

  void _onUserActivity() {
    final auto = widget.viewModeAuto;
    final vm = _viewMode;
    if (auto == null || vm == null) return;
    if (vm.mode != TypeViewMode.table) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastActivityAtMs < 80) return;
    _lastActivityAtMs = now;
    _scheduleIdle(auto);
  }

  bool _shouldForceTableOnTap(int index) {
    final auto = widget.viewModeAuto;
    final vm = _viewMode;
    if (auto == null || vm == null) return false;
    if (vm.mode != TypeViewMode.status) return false;
    final id = widget.tabs[index].id;
    return auto.tabIdsForceTableOnTap.contains(id);
  }

  Widget _sharedAxisYTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final offset = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(curved);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(position: offset, child: child),
    );
  }

  Widget _transitionMask(BuildContext context, {required String message}) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Positioned.fill(
      child: AbsorbPointer(
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

    _onUserActivity();
    try {
      await _runMaskedTabTransition(index);
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

        return Container(
          margin: const EdgeInsets.only(left: 6),
          constraints: const BoxConstraints(minHeight: 24, minWidth: 28),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: bc),
          ),
          child: Text(
            '$count',
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

    Widget out = Container(
      color: cs.surface,
      child: Column(
        children: [
          Expanded(
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
                        ),
                      );

                      final custom = widget.bodyBuilder;
                      final showCustom = custom != null;

                      final status = showCustom
                          ? KeyedSubtree(
                        key: ValueKey<String>('status:${t.id}'),
                        child: custom(context, t, _controllers[i]),
                      )
                          : null;

                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
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
                        child: showCustom ? status : table,
                      );
                    }

                    return RealTimeLockedPanel(
                      title: '${t.label} 실시간 탭이 비활성화되어 있습니다',
                      message:
                      '설정에서 “${t.label} 실시간 모드(탭) 사용”을 ON으로 변경한 뒤 다시 시도해 주세요.',
                    );
                  }),
                ),
                if (_transitionMaskOn)
                  _transitionMask(context, message: _transitionMaskMessage),
              ],
            ),
          ),
          _buildBottomTabBar(cs),
        ],
      ),
    );

    if (widget.viewModeAuto != null && _viewMode != null) {
      out = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _onUserActivity(),
        onPointerMove: (_) => _onUserActivity(),
        onPointerUp: (_) => _onUserActivity(),
        onPointerSignal: (_) => _onUserActivity(),
        child: out,
      );
    }

    return out;
  }
}
