import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/models/capability.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../account/applications/user_state.dart';
import '../../../headquarter/application/actions/headquarter_common_actions.dart';
import '../../../headquarter/application/snapshot/headquarter_snapshot_repository.dart';
import '../../../headquarter/widgets/headquarter_dashboard_identity_header.dart';
import '../../../selector/application/dev_auth.dart';

class HeadquarterModeDockResult {
  const HeadquarterModeDockResult.navigate({
    required this.modeKey,
    required this.areaName,
  }) : openSecondary = false;

  const HeadquarterModeDockResult.switchMode(this.modeKey)
      : areaName = '',
        openSecondary = false;

  const HeadquarterModeDockResult.openSecondary()
      : modeKey = '',
        areaName = '',
        openSecondary = true;

  final String modeKey;
  final String areaName;
  final bool openSecondary;
}

Future<HeadquarterModeDockResult?> showHeadquarterModeSideDock({
  required BuildContext context,
  required String currentModeKey,
  required String currentScreen,
}) {
  return showCommonLeftSideDock<HeadquarterModeDockResult>(
    context: context,
    barrierLabel: '헤드쿼터 이동',
    maxWidth: 440,
    widthFactor: 0.96,
    builder: (_) => HeadquarterModeSideDock(
      currentModeKey: currentModeKey,
      currentScreen: currentScreen,
    ),
  );
}

class HeadquarterModeSideDock extends StatefulWidget {
  const HeadquarterModeSideDock({
    super.key,
    required this.currentModeKey,
    required this.currentScreen,
  });

  final String currentModeKey;
  final String currentScreen;

  @override
  State<HeadquarterModeSideDock> createState() =>
      _HeadquarterModeSideDockState();
}

class _HeadquarterModeSideDockState extends State<HeadquarterModeSideDock> {
  static const List<_HeadquarterRailItem> _workModeItems = <_HeadquarterRailItem>[
    _HeadquarterRailItem(
      modeKey: 'single',
      label: '싱글',
      title: '싱글 헤드쿼터',
      icon: Icons.looks_one_rounded,
    ),
    _HeadquarterRailItem(
      modeKey: 'double',
      label: '더블',
      title: '더블 헤드쿼터',
      icon: Icons.view_week_rounded,
    ),
    _HeadquarterRailItem(
      modeKey: 'triple',
      label: '트리플',
      title: '트리플 헤드쿼터',
      icon: Icons.apartment_rounded,
    ),
    _HeadquarterRailItem(
      modeKey: 'minor',
      label: '마이너',
      title: '마이너 헤드쿼터',
      icon: Icons.tune_rounded,
    ),
  ];

  static const _HeadquarterRailItem _sprintItem = _HeadquarterRailItem(
    modeKey: 'sprint',
    label: '스프린트',
    title: '스프린트 모드',
    icon: Icons.bolt_rounded,
  );

  static const List<_HeadquarterRailItem> _allModeItems =
      <_HeadquarterRailItem>[
    ..._workModeItems,
    _sprintItem,
  ];

  final _HeadquarterDockDebugLog _debugLog = _HeadquarterDockDebugLog();
  late String _selectedModeKey;
  bool _developerLoggedIn = false;
  bool _devModeEnabled = false;
  bool _developerStateResolved = false;
  bool _supportLoading = true;
  String _division = '';
  String _downloadedAtIso = '';
  String? _expandedArea;
  String? _supportError;
  List<_BranchSupportViewData> _branches = const <_BranchSupportViewData>[];

  @override
  void initState() {
    super.initState();
    _selectedModeKey = widget.currentModeKey;
    _debugLog.log(
      'mounted screen=${widget.currentScreen} current=${widget.currentModeKey} source=sqlite_download_snapshot rail=single,double,triple,minor|developer:sprint,secondary dockSide=left dockAnchor=left dockSlideDirection=negative_x_to_zero maxWidth=440 widthFactor=0.96 sizePolicy=preserved dashboardIdentity=mode_dock modeSource=currentModeKey userSource=UserState identityAnimation=fade_scale_y_settle actionCarousel=excluded additionalFirebaseRead=0 additionalFirebaseWrite=0',
    );
    DevAuth.devModeEnabled.addListener(_handleDevModeChanged);
    _resolveDeveloperState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSupportData();
    });
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_handleDevModeChanged);
    _debugLog.log('disposed selected=$_selectedModeKey');
    super.dispose();
  }

  Future<void> _resolveDeveloperState() async {
    final loggedIn = await DevAuth.isDeveloperLoggedIn();
    final modeEnabled = await DevAuth.isDevModeEnabled();
    if (!mounted) return;
    final resetSprint = !modeEnabled && _selectedModeKey == _sprintItem.modeKey;
    setState(() {
      _developerLoggedIn = loggedIn;
      _devModeEnabled = modeEnabled;
      _developerStateResolved = true;
      if (resetSprint) {
        _selectedModeKey = _fallbackWorkModeKey;
        _expandedArea = null;
      }
    });
    _debugLog.log(
      'developer_state loggedIn=$loggedIn modeEnabled=$modeEnabled sprintVisible=$modeEnabled selectionReset=$resetSprint selected=$_selectedModeKey',
    );
  }

  void _handleDevModeChanged() {
    if (!mounted) return;
    final value = DevAuth.devModeEnabled.value;
    if (_devModeEnabled == value && _developerStateResolved) return;
    final resetSprint = !value && _selectedModeKey == _sprintItem.modeKey;
    setState(() {
      _devModeEnabled = value;
      _developerStateResolved = true;
      if (resetSprint) {
        _selectedModeKey = _fallbackWorkModeKey;
        _expandedArea = null;
      }
    });
    _debugLog.log(
      'developer_mode_changed enabled=$value sprintVisible=$value selectionReset=$resetSprint selected=$_selectedModeKey',
    );
    unawaited(_resolveDeveloperState());
  }

  Future<void> _loadSupportData() async {
    if (!mounted) return;
    final userState = context.read<UserState>();
    final division = userState.division.trim();
    _debugLog.log('snapshot_load_start division=$division');
    if (!_supportLoading) {
      setState(() {
        _supportLoading = true;
        _supportError = null;
      });
    }

    if (division.isEmpty) {
      setState(() {
        _division = '';
        _branches = const <_BranchSupportViewData>[];
        _supportLoading = false;
        _supportError = 'division_empty';
      });
      _debugLog.log('snapshot_load_stop reason=division_empty');
      return;
    }

    try {
      final snapshot = await HeadquarterSnapshotRepository.instance
          .readSnapshot(division);
      if (!mounted) return;

      if (snapshot == null) {
        setState(() {
          _division = division;
          _branches = const <_BranchSupportViewData>[];
          _downloadedAtIso = '';
          _supportLoading = false;
          _supportError = 'snapshot_missing';
        });
        _debugLog.log('snapshot_load_stop reason=snapshot_missing');
        return;
      }

      final snapshotAreas = snapshot.areas.where((area) {
        return area.name.trim().isNotEmpty;
      }).toList(growable: false);

      final branches = snapshotAreas.map((area) {
        return _BranchSupportViewData(
          areaName: area.name.trim(),
          modes: Set<String>.unmodifiable(area.modes),
          tabletSupported:
              area.capabilities.contains(Capability.tablet),
          capabilities: Set<Capability>.unmodifiable(area.capabilities),
          isHeadquarter: area.isHeadquarter,
        );
      }).toList(growable: false)
        ..sort(
          (a, b) => a.areaName.toLowerCase().compareTo(
                b.areaName.toLowerCase(),
              ),
        );

      final diagnostics = await HeadquarterSnapshotRepository.instance
          .readDiagnostics(division);
      if (!mounted) return;

      setState(() {
        _division = division;
        _branches = List<_BranchSupportViewData>.unmodifiable(branches);
        _downloadedAtIso = snapshot.downloadedAtIso;
        _supportLoading = false;
        _supportError = null;
      });

      _debugLog.log(
        'snapshot_load_complete division=$division areas=${branches.length} downloadedAt=${snapshot.downloadedAtIso}',
      );
      if (diagnostics != null) {
        _debugLog.log(
          'snapshot_db version=${diagnostics.databaseVersion} areas=${diagnostics.areaCount} single=${diagnostics.singleCount} double=${diagnostics.doubleCount} triple=${diagnostics.tripleCount} minor=${diagnostics.minorCount} tablet=${diagnostics.tabletCount}',
        );
      }
      for (final branch in branches) {
        _debugLog.log(
          'snapshot_area area=${branch.areaName} modes=${branch.modes.toList()..sort()} tablet=${branch.tabletSupported} capabilities=${branch.capabilities.map((item) => item.key).toList()..sort()}',
        );
      }
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _division = division;
        _branches = const <_BranchSupportViewData>[];
        _supportLoading = false;
        _supportError = 'load_failed';
      });
      _debugLog.log('snapshot_load_failure error=$error stack=$stackTrace');
    }
  }


  String get _fallbackWorkModeKey {
    final current = widget.currentModeKey;
    for (final item in _workModeItems) {
      if (item.modeKey == current) return current;
    }
    return _workModeItems.first.modeKey;
  }

  _HeadquarterRailItem get _selectedItem {
    final selectedModeKey =
        _selectedModeKey == _sprintItem.modeKey &&
                (!_developerStateResolved || !_devModeEnabled)
            ? _fallbackWorkModeKey
            : _selectedModeKey;
    return _allModeItems.firstWhere(
      (item) => item.modeKey == selectedModeKey,
      orElse: () => _workModeItems.first,
    );
  }

  int? _supportCountFor(String modeKey) {
    if (modeKey == 'sprint') return null;
    if (_supportLoading || _supportError != null) return null;
    return _branches.where((branch) => branch.supports(modeKey)).length;
  }

  void _select(String modeKey) {
    if (modeKey == _sprintItem.modeKey && !_devModeEnabled) {
      _debugLog.log(
        'rail_select_blocked mode=sprint reason=developer_mode_off',
      );
      HapticFeedback.mediumImpact();
      return;
    }
    if (_selectedModeKey == modeKey) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedModeKey = modeKey;
      _expandedArea = null;
    });
    _debugLog.log(
      'rail_selected mode=$modeKey supportCount=${_supportCountFor(modeKey)}',
    );
  }

  void _toggleArea(String areaName) {
    final next = _expandedArea == areaName ? null : areaName;
    HapticFeedback.selectionClick();
    setState(() => _expandedArea = next);
    _debugLog.log(
      'area_detail area=$areaName expanded=${next == areaName} mode=$_selectedModeKey',
    );
  }

  void _navigateArea(_BranchSupportViewData area) {
    if (!area.supports(_selectedModeKey)) return;
    final userState = context.read<UserState>();
    final currentArea = userState.currentArea.trim();
    if (_selectedModeKey == widget.currentModeKey &&
        currentArea == area.areaName) {
      _debugLog.log(
        'area_navigation_noop mode=$_selectedModeKey area=${area.areaName} reason=already_current',
      );
      HapticFeedback.selectionClick();
      Navigator.of(context).pop();
      return;
    }
    _debugLog.log(
      'area_navigation_select fromMode=${widget.currentModeKey} fromArea=$currentArea toMode=$_selectedModeKey toArea=${area.areaName} isHeadquarter=${area.isHeadquarter} dataSource=sqlite firebaseRead=0 firebaseWrite=0',
    );
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(
      HeadquarterModeDockResult.navigate(
        modeKey: _selectedModeKey,
        areaName: area.areaName,
      ),
    );
  }

  void _confirm() {
    if (_selectedModeKey == _sprintItem.modeKey && !_devModeEnabled) {
      _debugLog.log(
        'switch_confirm_blocked to=sprint reason=developer_mode_off',
      );
      HapticFeedback.mediumImpact();
      return;
    }
    if (_selectedModeKey == widget.currentModeKey) return;
    _debugLog.log(
      'switch_confirm from=${widget.currentModeKey} to=$_selectedModeKey',
    );
    Navigator.of(context).pop(
      HeadquarterModeDockResult.switchMode(_selectedModeKey),
    );
  }

  void _openSecondary() {
    if (!_developerLoggedIn) return;
    _debugLog.log('secondary_confirm');
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(const HeadquarterModeDockResult.openSecondary());
  }

  Future<void> _showDeveloperStatus() async {
    if (!_devModeEnabled) return;
    _debugLog.log(
      'status_dialog_open division=$_division selected=$_selectedModeKey current=${widget.currentModeKey} areas=${_branches.length} downloadedAt=$_downloadedAtIso supportError=${_supportError ?? ''} dockSide=left dockAnchor=left dockSlideDirection=negative_x_to_zero maxWidth=440 widthFactor=0.96 sizePolicy=preserved dashboardIdentity=mode_dock modeSource=currentModeKey userSource=UserState identityAnimation=fade_scale_y_settle actionCarousel=excluded additionalFirebaseRead=0 additionalFirebaseWrite=0',
    );
    await _debugLog.showStatus(
      context,
      additionalLines: HeadquarterCommonActions.debugLines,
    );
  }

  void _close() {
    _debugLog.log('close_button');
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selected = _selectedItem;
    final isCurrent = selected.modeKey == widget.currentModeKey;
    final userState = context.watch<UserState>();

    return Column(
      children: [
        HeadquarterDashboardIdentityHeader(
          name: userState.name,
          position: userState.position,
          modeKey: widget.currentModeKey,
          variant: HeadquarterDashboardIdentityVariant.modeDock,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tokens.accentContainer,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.swap_horiz_rounded,
                color: tokens.onAccentContainer,
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '헤드쿼터 이동',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : CommonUiMotion.selection,
                    child: Text(
                      _downloadedAtIso.trim().isEmpty
                          ? '업무 데이터 없음'
                          : '${_formatTimestamp(_downloadedAtIso)} 업데이트 기준',
                      key: ValueKey<String>(_downloadedAtIso),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: _downloadedAtIso.trim().isEmpty
                                ? tokens.warning
                                : tokens.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            if (_devModeEnabled)
              CommonIconButton(
                icon: Icons.bug_report_rounded,
                tooltip: '상태',
                onPressed: _showDeveloperStatus,
                haptic: CommonHaptic.selection,
              ),
            const SizedBox(width: 4),
            CommonIconButton(
              icon: Icons.close_rounded,
              tooltip: '닫기',
              onPressed: _close,
              haptic: CommonHaptic.light,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 68,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.surfaceOverlay,
                    borderRadius: BorderRadius.circular(CommonUiShapes.card),
                    border: Border.all(color: tokens.borderSubtle),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                for (final item in _workModeItems) ...[
                                  _HeadquarterRailButton(
                                    item: item,
                                    selected:
                                        item.modeKey == _selectedModeKey,
                                    current:
                                        item.modeKey == widget.currentModeKey,
                                    supportCount:
                                        _supportCountFor(item.modeKey),
                                    onTap: () => _select(item.modeKey),
                                  ),
                                  if (item != _workModeItems.last)
                                    const SizedBox(height: 4),
                                ],
                              ],
                            ),
                          ),
                        ),
                        AnimatedSize(
                          duration: reduceMotion
                              ? Duration.zero
                              : CommonUiMotion.selection,
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: AnimatedSwitcher(
                            duration: reduceMotion
                                ? Duration.zero
                                : CommonUiMotion.selection,
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _devModeEnabled || _developerLoggedIn
                                ? Column(
                                    key: ValueKey<String>(
                                      'developer-rail-$_devModeEnabled-$_developerLoggedIn',
                                    ),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        child: Divider(
                                          height: 1,
                                          color: tokens.borderStrong,
                                        ),
                                      ),
                                      if (_devModeEnabled)
                                        _HeadquarterRailButton(
                                          item: _sprintItem,
                                          selected: _selectedModeKey ==
                                              _sprintItem.modeKey,
                                          current: widget.currentModeKey ==
                                              _sprintItem.modeKey,
                                          supportCount: null,
                                          onTap: () =>
                                              _select(_sprintItem.modeKey),
                                        ),
                                      if (_devModeEnabled &&
                                          _developerLoggedIn)
                                        const SizedBox(height: 4),
                                      if (_developerLoggedIn)
                                        _HeadquarterRailButton(
                                          item: const _HeadquarterRailItem(
                                            modeKey: 'secondary',
                                            label: '운영',
                                            title: '운영 관리',
                                            icon: Icons
                                                .admin_panel_settings_rounded,
                                          ),
                                          selected: false,
                                          current: false,
                                          supportCount: null,
                                          onTap: _openSecondary,
                                        ),
                                    ],
                                  )
                                : const SizedBox.shrink(
                                    key: ValueKey<String>(
                                      'developer-rail-hidden',
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.canvas,
                    borderRadius: BorderRadius.circular(CommonUiShapes.card),
                    border: Border.all(color: tokens.borderSubtle),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : CommonUiMotion.component,
                          switchInCurve: CommonUiMotion.enter,
                          switchOutCurve: CommonUiMotion.exit,
                          transitionBuilder: (child, animation) {
                            if (reduceMotion) return child;
                            final curved = CurvedAnimation(
                              parent: animation,
                              curve: CommonUiMotion.enter,
                              reverseCurve: CommonUiMotion.exit,
                            );
                            return FadeTransition(
                              opacity: curved,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(.035, 0),
                                  end: Offset.zero,
                                ).animate(curved),
                                child: child,
                              ),
                            );
                          },
                          child: _HeadquarterModeContent(
                            key: ValueKey<String>(selected.modeKey),
                            item: selected,
                            current: isCurrent,
                            branches: _branches,
                            loading: _supportLoading,
                            supportError: _supportError,
                            downloadedAtIso: _downloadedAtIso,
                            expandedArea: _expandedArea,
                            currentModeKey: widget.currentModeKey,
                            currentArea: userState.currentArea.trim(),
                            onToggleArea: _toggleArea,
                            onNavigateArea: _navigateArea,
                            reduceMotion: reduceMotion,
                          ),
                        ),
                      ),
                      if (selected.modeKey == _sprintItem.modeKey)
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: CommonButton(
                            label: isCurrent ? '현재 모드' : '스프린트 열기',
                            icon: isCurrent
                                ? Icons.check_circle_rounded
                                : Icons.bolt_rounded,
                            onPressed: isCurrent ? null : _confirm,
                            expand: true,
                            haptic: CommonHaptic.selection,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeadquarterModeContent extends StatelessWidget {
  const _HeadquarterModeContent({
    super.key,
    required this.item,
    required this.current,
    required this.branches,
    required this.loading,
    required this.supportError,
    required this.downloadedAtIso,
    required this.expandedArea,
    required this.currentModeKey,
    required this.currentArea,
    required this.onToggleArea,
    required this.onNavigateArea,
    required this.reduceMotion,
  });

  final _HeadquarterRailItem item;
  final bool current;
  final List<_BranchSupportViewData> branches;
  final bool loading;
  final String? supportError;
  final String downloadedAtIso;
  final String? expandedArea;
  final String currentModeKey;
  final String currentArea;
  final ValueChanged<String> onToggleArea;
  final ValueChanged<_BranchSupportViewData> onNavigateArea;
  final bool reduceMotion;

  bool get _isSprint => item.modeKey == 'sprint';

  List<_BranchSupportViewData> get _supportedBranches {
    if (_isSprint) return const <_BranchSupportViewData>[];
    final result = branches
        .where((branch) => branch.supports(item.modeKey))
        .toList(growable: false);
    result.sort(
      (a, b) => a.areaName.toLowerCase().compareTo(
            b.areaName.toLowerCase(),
          ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_isSprint) {
      return _SprintModeContent(
        item: item,
        current: current,
        reduceMotion: reduceMotion,
      );
    }

    final supported = _supportedBranches;
    final total = branches.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      children: [
        _ModeIdentity(
          item: item,
          current: current,
          reduceMotion: reduceMotion,
        ),
        const SizedBox(height: 12),
        _CoverageCard(
          supported: supported.length,
          total: total,
          loading: loading,
          unavailable: supportError != null,
          reduceMotion: reduceMotion,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '지원 지역',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: CommonUiTheme.of(context).textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            if (downloadedAtIso.trim().isNotEmpty)
              _TimeBadge(
                label: '${_formatTimestamp(downloadedAtIso)} 다운로드',
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (loading)
          _LocalLoadingSurface(reduceMotion: reduceMotion)
        else if (supportError != null)
          const _DataUnavailableSurface()
        else if (supported.isEmpty)
          const _EmptySupportSurface()
        else
          for (var index = 0; index < supported.length; index++) ...[
            _BranchSupportCard(
              branch: supported[index],
              selectedModeKey: item.modeKey,
              expanded: expandedArea == supported[index].areaName,
              current: currentModeKey == item.modeKey &&
                  currentArea == supported[index].areaName,
              onTap: () => onNavigateArea(supported[index]),
              onToggleDetail: () => onToggleArea(supported[index].areaName),
              reduceMotion: reduceMotion,
              revealDelay: reduceMotion
                  ? Duration.zero
                  : Duration(milliseconds: 22 * index.clamp(0, 6).toInt()),
            ),
            if (index != supported.length - 1) const SizedBox(height: 7),
          ],
      ],
    );
  }
}

class _SprintModeContent extends StatelessWidget {
  const _SprintModeContent({
    required this.item,
    required this.current,
    required this.reduceMotion,
  });

  final _HeadquarterRailItem item;
  final bool current;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: .96, end: 1),
          duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
          curve: CommonUiMotion.enter,
          builder: (context, value, child) {
            return Transform.scale(scale: value, child: child);
          },
          child: _ModeIdentity(
            item: item,
            current: current,
            reduceMotion: reduceMotion,
          ),
        ),
      ),
    );
  }
}

class _ModeIdentity extends StatelessWidget {
  const _ModeIdentity({
    required this.item,
    required this.current,
    required this.reduceMotion,
  });

  final _HeadquarterRailItem item;
  final bool current;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: .9, end: 1),
          duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
          curve: CommonUiMotion.enter,
          builder: (context, value, child) {
            return Transform.scale(scale: value, child: child);
          },
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: tokens.accentContainer,
              borderRadius: BorderRadius.circular(CommonUiShapes.card),
              border: Border.all(color: tokens.borderSubtle),
            ),
            alignment: Alignment.center,
            child: Icon(
              item.icon,
              size: 27,
              color: tokens.onAccentContainer,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          item.title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
        ),
        if (current) ...[
          const SizedBox(height: 7),
          _HeadquarterStatusBadge(
            label: '현재',
            color: tokens.accent,
          ),
        ],
      ],
    );
  }
}

class _CoverageCard extends StatelessWidget {
  const _CoverageCard({
    required this.supported,
    required this.total,
    required this.loading,
    required this.unavailable,
    required this.reduceMotion,
  });

  final int supported;
  final int total;
  final bool loading;
  final bool unavailable;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final fraction = total <= 0 ? 0.0 : supported / total;
    final valueText = loading || unavailable ? '—' : '$supported / $total';

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '지원 지역',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                child: Text(
                  valueText,
                  key: ValueKey<String>(valueText),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AnimatedRatioBar(
            fraction: loading || unavailable ? 0 : fraction,
            color: tokens.accent,
            background: tokens.surfaceOverlay,
            reduceMotion: reduceMotion,
          ),
        ],
      ),
    );
  }
}

class _BranchSupportCard extends StatefulWidget {
  const _BranchSupportCard({
    required this.branch,
    required this.selectedModeKey,
    required this.expanded,
    required this.current,
    required this.onTap,
    required this.onToggleDetail,
    required this.reduceMotion,
    required this.revealDelay,
  });

  final _BranchSupportViewData branch;
  final String selectedModeKey;
  final bool expanded;
  final bool current;
  final VoidCallback onTap;
  final VoidCallback onToggleDetail;
  final bool reduceMotion;
  final Duration revealDelay;

  @override
  State<_BranchSupportCard> createState() => _BranchSupportCardState();
}

class _BranchSupportCardState extends State<_BranchSupportCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.reduceMotion ? Duration.zero : CommonUiMotion.component,
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: CommonUiMotion.enter,
    );
    _opacity = curved;
    _offset = Tween<Offset>(
      begin: const Offset(0, .035),
      end: Offset.zero,
    ).animate(curved);
    if (widget.reduceMotion || widget.revealDelay == Duration.zero) {
      _controller.value = 1;
    } else {
      Future<void>.delayed(widget.revealDelay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _BranchSupportCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotion != widget.reduceMotion && widget.reduceMotion) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: AnimatedScale(
          scale: _pressed ? .985 : 1,
          duration:
              widget.reduceMotion ? Duration.zero : CommonUiMotion.press,
          curve: CommonUiMotion.standard,
          child: AnimatedContainer(
            duration:
                widget.reduceMotion ? Duration.zero : CommonUiMotion.selection,
            curve: CommonUiMotion.standard,
            decoration: BoxDecoration(
              color: widget.expanded
                  ? tokens.surfaceSelected
                  : tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              border: Border.all(
                color: widget.expanded ? tokens.accent : tokens.borderSubtle,
                width: widget.expanded ? 1.25 : 1,
              ),
            ),
            child: Material(
              color: tokens.transparent,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              child: InkWell(
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                onTap: widget.onTap,
                onTapDown: (_) => setState(() => _pressed = true),
                onTapCancel: () => setState(() => _pressed = false),
                onTapUp: (_) => setState(() => _pressed = false),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: AnimatedSize(
                    duration: widget.reduceMotion
                        ? Duration.zero
                        : CommonUiMotion.layout,
                    curve: CommonUiMotion.enter,
                    alignment: Alignment.topCenter,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.branch.areaName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color: tokens.textPrimary,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                            ),
                            if (widget.current) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.successContainer,
                                  borderRadius: BorderRadius.circular(
                                    CommonUiShapes.pill,
                                  ),
                                  border: Border.all(
                                    color: tokens.success.withOpacity(.28),
                                  ),
                                ),
                                child: Text(
                                  '현재',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: tokens.success,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 9.5,
                                      ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: widget.onToggleDetail,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 30,
                              ),
                              icon: AnimatedRotation(
                                turns: widget.expanded ? .5 : 0,
                                duration: widget.reduceMotion
                                    ? Duration.zero
                                    : CommonUiMotion.selection,
                                curve: CommonUiMotion.standard,
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: tokens.iconSecondary,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: tokens.accent,
                              size: 14,
                            ),
                          ],
                        ),
                        if (widget.branch.isHeadquarter) ...[
                          const SizedBox(height: 5),
                          Text(
                            '본사',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: tokens.accent,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _ModeMatrix(
                                modes: widget.branch.modes,
                                selectedModeKey: widget.selectedModeKey,
                              ),
                            ),
                            if (widget.branch.tabletSupported) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 1,
                                height: 24,
                                color: tokens.borderSubtle,
                              ),
                              const SizedBox(width: 6),
                              const _TabletBadge(),
                            ],
                          ],
                        ),
                        if (widget.expanded) ...[
                          const SizedBox(height: 10),
                          Divider(height: 1, color: tokens.borderSubtle),
                          const SizedBox(height: 10),
                          _CapabilitiesDetail(
                            capabilities: widget.branch.capabilities,
                          ),
                        ],
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

class _ModeMatrix extends StatelessWidget {
  const _ModeMatrix({
    required this.modes,
    required this.selectedModeKey,
  });

  final Set<String> modes;
  final String selectedModeKey;

  static const List<_ModeMarker> _markers = <_ModeMarker>[
    _ModeMarker('single', 'S'),
    _ModeMarker('double', 'D'),
    _ModeMarker('triple', 'T'),
    _ModeMarker('minor', 'M'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final marker in _markers)
          _ModeMarkerChip(
            marker: marker,
            supported: modes.contains(marker.key),
            selected: marker.key == selectedModeKey,
          ),
      ],
    );
  }
}

class _ModeMarkerChip extends StatelessWidget {
  const _ModeMarkerChip({
    required this.marker,
    required this.supported,
    required this.selected,
  });

  final _ModeMarker marker;
  final bool supported;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final activeSelected = supported && selected;
    final background = activeSelected
        ? tokens.accent
        : supported
            ? tokens.accentContainer
            : tokens.surfaceDisabled;
    final foreground = activeSelected
        ? tokens.onAccent
        : supported
            ? tokens.onAccentContainer
            : tokens.textDisabled;
    final border = activeSelected
        ? tokens.accent
        : supported
            ? tokens.borderStrong
            : tokens.borderSubtle;

    return Semantics(
      label: '${marker.key} ${supported ? '지원' : '미지원'}',
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Text(
          marker.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w900,
                fontSize: 10,
              ),
        ),
      ),
    );
  }
}

class _TabletBadge extends StatelessWidget {
  const _TabletBadge();

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Semantics(
      label: '태블릿 지원',
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: tokens.infoContainer,
          borderRadius: BorderRadius.circular(CommonUiShapes.pill),
          border: Border.all(color: tokens.info.withOpacity(.32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tablet_mac_rounded, size: 13, color: tokens.info),
            const SizedBox(width: 3),
            Text(
              'Tablet',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.info,
                    fontWeight: FontWeight.w800,
                    fontSize: 9.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapabilitiesDetail extends StatelessWidget {
  const _CapabilitiesDetail({required this.capabilities});

  final Set<Capability> capabilities;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final values = Capability.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '다운로드 기능 정보',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final capability in values)
              _CapabilityPill(
                label: capability.label,
                supported: capabilities.contains(capability),
              ),
          ],
        ),
      ],
    );
  }
}

class _CapabilityPill extends StatelessWidget {
  const _CapabilityPill({
    required this.label,
    required this.supported,
  });

  final String label;
  final bool supported;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: supported ? tokens.accentContainer : tokens.surfaceDisabled,
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(
          color: supported ? tokens.borderStrong : tokens.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            supported ? Icons.check_rounded : Icons.remove_rounded,
            size: 12,
            color: supported ? tokens.onAccentContainer : tokens.textDisabled,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: supported
                      ? tokens.onAccentContainer
                      : tokens.textDisabled,
                  fontWeight: FontWeight.w700,
                  fontSize: 9.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedRatioBar extends StatelessWidget {
  const _AnimatedRatioBar({
    required this.fraction,
    required this.color,
    required this.background,
    required this.reduceMotion,
  });

  final double fraction;
  final Color color;
  final Color background;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(CommonUiShapes.pill),
      child: SizedBox(
        height: 7,
        child: ColoredBox(
          color: background,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: 0,
              end: fraction.clamp(0.0, 1.0).toDouble(),
            ),
            duration: reduceMotion ? Duration.zero : CommonUiMotion.layout,
            curve: CommonUiMotion.enter,
            builder: (context, value, child) {
              return Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: value,
                  child: SizedBox.expand(child: child),
                ),
              );
            },
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
  }
}

class _TimeBadge extends StatelessWidget {
  const _TimeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 9,
            ),
      ),
    );
  }
}

class _LocalLoadingSurface extends StatelessWidget {
  const _LocalLoadingSurface({required this.reduceMotion});

  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      height: 74,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: reduceMotion
          ? Icon(
              Icons.hourglass_top_rounded,
              color: tokens.accent,
              size: 22,
            )
          : SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: tokens.accent,
              ),
            ),
    );
  }
}

class _DataUnavailableSurface extends StatelessWidget {
  const _DataUnavailableSurface();

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      height: 74,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Text(
        '업무 데이터 없음',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _EmptySupportSurface extends StatelessWidget {
  const _EmptySupportSurface();

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      height: 74,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Text(
        '지원 지역 없음',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _HeadquarterRailButton extends StatefulWidget {
  const _HeadquarterRailButton({
    required this.item,
    required this.selected,
    required this.current,
    required this.supportCount,
    required this.onTap,
  });

  final _HeadquarterRailItem item;
  final bool selected;
  final bool current;
  final int? supportCount;
  final VoidCallback onTap;

  @override
  State<_HeadquarterRailButton> createState() => _HeadquarterRailButtonState();
}

class _HeadquarterRailButtonState extends State<_HeadquarterRailButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final foreground = widget.selected
        ? tokens.onAccentContainer
        : widget.current
            ? tokens.accent
            : tokens.textSecondary;
    final background = widget.selected
        ? tokens.accentContainer
        : widget.current
            ? tokens.surfaceSelected
            : tokens.surfaceRaised;
    final borderColor = widget.selected
        ? tokens.accent
        : widget.current
            ? tokens.borderStrong
            : tokens.borderSubtle;

    return AnimatedScale(
      scale: _pressed ? .97 : 1,
      duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
      curve: CommonUiMotion.standard,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        height: 62,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(CommonUiShapes.control),
          border: Border.all(
            color: borderColor,
            width: widget.selected ? 1.3 : 1,
          ),
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(CommonUiShapes.control),
          child: InkWell(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.item.icon, size: 18, color: foreground),
                      const SizedBox(height: 3),
                      Text(
                        widget.item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: foreground,
                              fontSize: 9.2,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
                if (const <String>{
                  'single',
                  'double',
                  'triple',
                  'minor',
                }.contains(widget.item.modeKey))
                  Positioned(
                    top: 3,
                    right: 3,
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      child: Container(
                        key: ValueKey<Object>(widget.supportCount ?? 'unknown'),
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: widget.selected
                              ? tokens.accent
                              : tokens.surfaceOverlay,
                          borderRadius:
                              BorderRadius.circular(CommonUiShapes.pill),
                          border: Border.all(
                            color: widget.selected
                                ? tokens.accent
                                : tokens.borderSubtle,
                          ),
                        ),
                        child: Text(
                          widget.supportCount?.toString() ?? '—',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: widget.selected
                                    ? tokens.onAccent
                                    : tokens.textSecondary,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeadquarterStatusBadge extends StatelessWidget {
  const _HeadquarterStatusBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(color: color.withOpacity(.32)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 9.5,
            ),
      ),
    );
  }
}

class _HeadquarterRailItem {
  const _HeadquarterRailItem({
    required this.modeKey,
    required this.label,
    required this.title,
    required this.icon,
  });

  final String modeKey;
  final String label;
  final String title;
  final IconData icon;
}

class _ModeMarker {
  const _ModeMarker(this.key, this.label);

  final String key;
  final String label;
}

class _BranchSupportViewData {
  const _BranchSupportViewData({
    required this.areaName,
    required this.modes,
    required this.tabletSupported,
    required this.capabilities,
    required this.isHeadquarter,
  });

  final String areaName;
  final Set<String> modes;
  final bool tabletSupported;
  final Set<Capability> capabilities;
  final bool isHeadquarter;

  bool supports(String modeKey) => modes.contains(modeKey.trim().toLowerCase());
}

class _HeadquarterDockDebugLog {
  final List<String> _lines = <String>[];

  void log(String message) {
    final line =
        '[HeadquarterModeSideDock][${DateTime.now().toIso8601String()}] $message';
    _lines.add(line);
    if (_lines.length > 240) {
      _lines.removeRange(0, _lines.length - 240);
    }
    debugPrint(line);
  }

  String get debugPrintCode => _lines
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');

  Future<void> showStatus(
    BuildContext context, {
    List<String> additionalLines = const <String>[],
  }) async {
    final combined = <String>[..._lines, ...additionalLines];
    final code = combined
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
    await StatusDialog.showSuccess(
      context,
      title: '헤드쿼터 이동 상태',
      description: combined.join('\n'),
      copyText: code,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}



String _formatTimestamp(String iso) {
  final raw = iso.trim();
  if (raw.isEmpty) return '—';
  final parsed = DateTime.tryParse(raw)?.toLocal();
  if (parsed == null) return raw;
  final month = parsed.month.toString().padLeft(2, '0');
  final day = parsed.day.toString().padLeft(2, '0');
  final hour = parsed.hour.toString().padLeft(2, '0');
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '$month.$day $hour:$minute';
}
