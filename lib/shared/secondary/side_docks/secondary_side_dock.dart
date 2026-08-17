import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/utils/status_dialog.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../features/account/applications/user_state.dart';
import '../../../features/dev/application/area_state.dart';
import '../../../features/location/applications/location_state.dart';
import '../../../features/location/domain/models/location_model.dart';
import '../../../features/location/pages/location_management.dart';
import '../../../features/selector/application/dev_auth.dart';
import '../application/secondary_account_workspace_state.dart';
import '../application/secondary_info.dart';
import '../application/secondary_location_workspace_state.dart';
import '../application/secondary_state.dart';
import '../widgets/ops_console_widgets.dart';
import '../widgets/secondary_debug_scope.dart';

enum SecondaryDockRequest { open }

Future<T?> showSecondarySideDock<T>({
  required BuildContext context,
  String barrierLabel = '운영 관리',
  bool useRootNavigator = false,
}) {
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  debugPrint(
    '[SecondarySideDock] route_push label=$barrierLabel reduceMotion=$reduceMotion',
  );
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _SecondarySideDockRoute<T>(
      barrierLabelText: barrierLabel,
      reduceMotion: reduceMotion,
    ),
  );
}

class _SecondarySideDockRoute<T> extends PopupRoute<T> {
  _SecondarySideDockRoute({
    required this.barrierLabelText,
    required this.reduceMotion,
  });

  final String barrierLabelText;
  final bool reduceMotion;
  String? _closeSource;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => barrierLabelText;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 210);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 190);

  void _dismissFromScrim(BuildContext context) {
    _closeSource = 'scrim';
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
  }

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    if (popped) {
      debugPrint(
        '[SecondarySideDock] route_pop label=$barrierLabelText source=${_closeSource ?? 'route'}',
      );
    }
    return popped;
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: reduceMotion ? Curves.linear : CommonUiMotion.enter,
      reverseCurve: reduceMotion ? Curves.linear : CommonUiMotion.exit,
    );

    return CommonUiScope(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: curved,
          builder: (context, _) {
            final media = MediaQuery.of(context);
            final tokens = CommonUiTheme.of(context);
            final progress = reduceMotion
                ? 1.0
                : curved.value.clamp(0.0, 1.0).toDouble();
            final maxDockWidth = (media.size.width * .92)
                .clamp(240.0, double.infinity)
                .toDouble();
            final dockWidth = maxDockWidth < 360.0 ? maxDockWidth : 360.0;
            final translateX = 22.0 * (1 - progress);
            final opacity = .90 + (.10 * progress);

            return Stack(
              children: [
                Positioned.fill(
                  child: Semantics(
                    button: true,
                    label: '$barrierLabelText 닫기',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _dismissFromScrim(context),
                      child: ColoredBox(
                        color: tokens.scrim.withOpacity(.22 * progress),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: dockWidth,
                  child: Transform.translate(
                    offset: Offset(translateX, 0),
                    child: Opacity(
                      opacity: opacity,
                      child: _SecondaryDockSurface(
                        width: dockWidth,
                        child: SafeArea(
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom: media.viewInsets.bottom,
                            ),
                            child: const SecondarySideDock(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SecondaryDockSurface extends StatelessWidget {
  const _SecondaryDockSurface({
    required this.width,
    required this.child,
  });

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    const radius = BorderRadius.only(
      topLeft: Radius.circular(18),
      bottomLeft: Radius.circular(18),
    );

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: tokens.surface.withOpacity(tokens.isDark ? .86 : .90),
            border: Border.all(color: tokens.borderSubtle),
            boxShadow: [
              BoxShadow(
                blurRadius: 16,
                color: tokens.shadow,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class SecondarySideDock extends StatefulWidget {
  const SecondarySideDock({super.key});

  @override
  State<SecondarySideDock> createState() => _SecondarySideDockState();
}

class _SecondarySideDockState extends State<SecondarySideDock> {
  static const List<_SecondaryRailItem> _primaryItems = <_SecondaryRailItem>[
    _SecondaryRailItem(
      section: Section.local,
      label: '설정',
      icon: Icons.tune_rounded,
    ),
    _SecondaryRailItem(
      section: Section.user,
      label: '계정',
      icon: Icons.manage_accounts_rounded,
    ),
    _SecondaryRailItem(
      section: Section.sector,
      label: '섹터',
      icon: Icons.hub_rounded,
    ),
    _SecondaryRailItem(
      section: Section.location,
      label: '구역',
      icon: Icons.location_on_rounded,
    ),
    _SecondaryRailItem(
      section: Section.tablet,
      label: '태블릿',
      icon: Icons.tablet_mac_rounded,
    ),
    _SecondaryRailItem(
      section: Section.bill,
      label: '정산',
      icon: Icons.receipt_long_rounded,
    ),
  ];

  static const List<_SecondaryRailItem> _bottomItems = <_SecondaryRailItem>[
    _SecondaryRailItem(
      section: Section.backend,
      label: '백엔드',
      icon: Icons.settings_ethernet_rounded,
    ),
    _SecondaryRailItem(
      section: Section.area,
      label: '지역 추가',
      displayLabel: '지역',
      icon: Icons.add_location_alt_rounded,
    ),
  ];

  final _SecondaryDockDebugLog _debugLog = _SecondaryDockDebugLog();
  late final SecondaryAccountWorkspaceState _accountWorkspace;
  late final SecondaryLocationWorkspaceState _locationWorkspace;
  Section _selectedSection = Section.local;
  bool _devModeEnabled = false;
  bool _fallbackScheduled = false;
  String? _lastArea;

  @override
  void initState() {
    super.initState();
    _accountWorkspace = SecondaryAccountWorkspaceState(onDebug: _debugLog.log);
    _locationWorkspace = SecondaryLocationWorkspaceState(onDebug: _debugLog.log);
    _debugLog.log('mounted selected=${_selectedSection.name}');
    DevAuth.devModeEnabled.addListener(_handleDevModeNotifier);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final state = context.read<SecondaryState>();
      await state.refreshDeveloperLogin();
      final enabled = await DevAuth.isDevModeEnabled();
      if (!mounted) return;
      setState(() => _devModeEnabled = enabled);
      _debugLog.log(
        'developer_mode_resolved enabled=$enabled devLoggedIn=${state.devLoggedIn}',
      );
      _logAccessSnapshot(state);
    });
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_handleDevModeNotifier);
    _debugLog.log('disposed selected=${_selectedSection.name}');
    _accountWorkspace.dispose();
    _locationWorkspace.dispose();
    super.dispose();
  }

  void _handleDevModeNotifier() {
    if (!mounted) return;
    final enabled = DevAuth.devModeEnabled.value;
    if (_devModeEnabled == enabled) return;
    setState(() => _devModeEnabled = enabled);
    _debugLog.log('developer_mode_changed enabled=$enabled');
  }

  void _logAccessSnapshot(SecondaryState state) {
    final access = <String>[];
    for (final item in <_SecondaryRailItem>[..._primaryItems, ..._bottomItems]) {
      final allowed = state.canAccess(item.section);
      final reason = allowed ? 'allowed' : state.accessDebugReason(item.section);
      access.add('${item.section.name}:$allowed:$reason');
    }
    _debugLog.log(
      'access_snapshot role=${state.role.name} devLoggedIn=${state.devLoggedIn} ${access.join('|')}',
    );
  }

  Section _effectiveSection(SecondaryState state) {
    if (state.canAccess(_selectedSection)) return _selectedSection;
    for (final item in <_SecondaryRailItem>[..._primaryItems, ..._bottomItems]) {
      if (state.canAccess(item.section)) {
        if (_selectedSection != item.section && !_fallbackScheduled) {
          _fallbackScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _fallbackScheduled = false;
            if (!mounted) return;
            _accountWorkspace.reset(source: 'selection_fallback');
            _locationWorkspace.reset(source: 'selection_fallback');
            setState(() => _selectedSection = item.section);
            _debugLog.log(
              'selection_fallback target=${item.section.name}',
            );
          });
        }
        return item.section;
      }
    }
    return Section.local;
  }

  Future<void> _selectSection(SecondaryState state, Section section) async {
    final allowed = state.canAccess(section);
    final debugReason = state.accessDebugReason(section);
    _debugLog.log(
      'rail_tap section=${section.name} allowed=$allowed current=${_selectedSection.name} reason=$debugReason',
    );
    if (!allowed) {
      final reason = state.disabledReason(section);
      _debugLog.log(
        'rail_blocked section=${section.name} reason=$reason debug=$debugReason',
      );
      await HapticFeedback.lightImpact();
      if (!mounted) return;
      await StatusDialog.showFailure(
        context,
        title: '${_sectionDisplayTitle(section)} 사용 불가',
        description: reason,
        copyText: _devModeEnabled ? _debugLog.debugPrintCode : null,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: _devModeEnabled
            ? const Duration(seconds: 60)
            : const Duration(seconds: 4),
        useCommonUi: true,
      );
      return;
    }
    if (_selectedSection == section) {
      if (section == Section.location && _locationWorkspace.isParentFocus) {
        await HapticFeedback.selectionClick();
        context.read<LocationState>().clearSelection();
        _locationWorkspace.closeParent(source: 'rail_reselect');
        _debugLog.log('rail_reselected_location_focus_closed');
        return;
      }
      _debugLog.log('rail_reselected section=${section.name}');
      return;
    }
    if (_selectedSection == Section.user ||
        _selectedSection == Section.tablet ||
        section == Section.user ||
        section == Section.tablet) {
      final userState = context.read<UserState>();
      final selectedId = userState.selectedUserId;
      if (selectedId != null) {
        unawaited(userState.toggleUserCard(selectedId));
        _debugLog.log('shared_account_selection_cleared id=$selectedId');
      }
    }
    final accountContextChanged =
        _selectedSection != section &&
        (_selectedSection == Section.user ||
            _selectedSection == Section.tablet ||
            section == Section.user ||
            section == Section.tablet);
    if (accountContextChanged) {
      _accountWorkspace.reset(
        source: 'section_change_${_selectedSection.name}_to_${section.name}',
      );
    }
    if (_selectedSection == Section.location || section == Section.location) {
      context.read<LocationState>().clearSelection();
      _locationWorkspace.reset(
        source: 'section_change_${_selectedSection.name}_to_${section.name}',
      );
    }
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _selectedSection = section);
    _debugLog.log('rail_selected section=${section.name}');
  }

  Future<void> _selectAccountMode(SecondaryAccountMode mode) async {
    final supported =
        _selectedSection == Section.user || _selectedSection == Section.tablet;
    if (!supported) {
      _debugLog.log('account_mode_blocked mode=${mode.name} section=${_selectedSection.name}');
      return;
    }
    if (_accountWorkspace.mode == mode) {
      await HapticFeedback.selectionClick();
      _accountWorkspace.setMode(mode, source: 'rail');
      return;
    }
    final userState = context.read<UserState>();
    final selectedId = userState.selectedUserId;
    if (selectedId != null) {
      unawaited(userState.toggleUserCard(selectedId));
      _debugLog.log('account_mode_selection_cleared target=${mode.name}');
    }
    if (mode == SecondaryAccountMode.delete) {
      await HapticFeedback.mediumImpact();
    } else {
      await HapticFeedback.selectionClick();
    }
    if (!mounted) return;
    _accountWorkspace.setMode(mode, source: 'rail');
  }

  Future<void> _showDeveloperStatus() async {
    if (!_devModeEnabled) return;
    _logAccessSnapshot(context.read<SecondaryState>());
    _debugLog.log('status_dialog_open');
    await _debugLog.showStatus(context);
  }

  void _close() {
    _debugLog.log('close_button selected=${_selectedSection.name}');
    HapticFeedback.lightImpact();
    if (_selectedSection == Section.location && _locationWorkspace.isParentFocus) {
      context.read<LocationState>().clearSelection();
      _locationWorkspace.reset(source: 'dock_close');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop();
      });
      return;
    }
    Navigator.of(context).pop();
  }

  void _backLocationWorkspace() {
    if (_selectedSection != Section.location || !_locationWorkspace.isParentFocus) {
      return;
    }
    _debugLog.log('location_header_back');
    HapticFeedback.selectionClick();
    context.read<LocationState>().clearSelection();
    _locationWorkspace.closeParent(source: 'header_back');
  }

  String _locationNameKey(String raw) {
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  List<LocationModel> _focusedLocationChildren(
    LocationState state,
    String area,
  ) {
    if (!_locationWorkspace.isParentFocus) return const <LocationModel>[];
    final focusedParentId = _locationWorkspace.focusedParentId?.trim() ?? '';
    final focusedParentTitle =
        _locationWorkspace.focusedParentTitle?.trim() ?? '';
    final focusedParentNameKey = _locationNameKey(focusedParentTitle);
    final out = state.locations.where((location) {
      if (!location.isCompositeChild) return false;
      if (area.isNotEmpty && location.area.trim() != area) return false;
      final childParentId = location.parentId?.trim() ?? '';
      if (focusedParentId.isNotEmpty && childParentId.isNotEmpty) {
        return childParentId == focusedParentId;
      }
      final legacyParent = location.parent?.trim() ?? '';
      return focusedParentNameKey.isNotEmpty &&
          _locationNameKey(legacyParent) == focusedParentNameKey;
    }).toList();
    out.sort((a, b) => a.locationName.compareTo(b.locationName));
    return out;
  }

  Future<void> _selectLocationChildFromRail(LocationModel child) async {
    if (_selectedSection != Section.location ||
        !_locationWorkspace.isParentFocus) {
      _locationWorkspace.log(
        'child_rail_tap_ignored id=${child.id} reason=workspace_inactive',
      );
      return;
    }
    final state = context.read<LocationState>();
    if (state.selectedLocationId == child.id) {
      await HapticFeedback.selectionClick();
      _locationWorkspace.log('child_rail_reselected id=${child.id}');
      return;
    }
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    state.selectLocation(child.id);
    _locationWorkspace.log('child_selected id=${child.id} source=rail');
  }

  String _sectionDisplayTitle(Section section) {
    switch (section) {
      case Section.local:
        return '설정';
      case Section.user:
        return '계정 관리';
      case Section.sector:
        return '섹터 관리';
      case Section.location:
        return '구역 관리';
      case Section.tablet:
        return '태블릿 관리';
      case Section.bill:
        return '정산 관리';
      case Section.backend:
        return '백엔드 컨트롤러';
      case Section.area:
        return '지역 및 회사 관리';
      case Section.monthly:
        return '정기 주차';
    }
  }

  Widget _contentFor(Section section) {
    final info = kSectionTab[section];
    if (info == null) {
      return const SizedBox.shrink();
    }
    final child = section == Section.location
        ? LocationManagement(workspace: _locationWorkspace)
        : info.page;
    return OpsConsolePresentationScope(
      key: ValueKey<Section>(section),
      embedded: true,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final media = MediaQuery.maybeOf(context);
    final reduceMotion = media?.disableAnimations ?? false;
    final textScale = media?.textScaler.scale(1.0) ?? 1.0;
    final area = context.select<AreaState, String>(
      (state) => state.currentArea.trim(),
    );
    final previousArea = _lastArea;
    if (previousArea == null) {
      _lastArea = area;
    } else if (previousArea != area) {
      _lastArea = area;
      if (_locationWorkspace.isParentFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _locationWorkspace.reset(source: 'area_changed_${previousArea}_to_$area');
        });
      }
    }

    return SecondaryDebugScope(
      onLog: _debugLog.log,
      child: ChangeNotifierProvider<SecondaryAccountWorkspaceState>.value(
        value: _accountWorkspace,
        child: AnimatedBuilder(
          animation: _locationWorkspace,
          builder: (context, _) => Consumer2<SecondaryState, SecondaryAccountWorkspaceState>(
        builder: (context, state, accountWorkspace, _) {
          final selected = _effectiveSection(state);
          final selectedTitle = _sectionDisplayTitle(selected);
          final locationFocus =
              selected == Section.location && _locationWorkspace.isParentFocus;
          final locationState = context.watch<LocationState>();
          final locationChildren = locationFocus
              ? _focusedLocationChildren(locationState, area)
              : const <LocationModel>[];
          final locationTitle = _locationWorkspace.focusedParentTitle?.trim() ?? '';
          final contextTitle = locationFocus && locationTitle.isNotEmpty
              ? locationTitle
              : selectedTitle;
          final subtitle = area.isEmpty ? contextTitle : '$area · $contextTitle';

          return LayoutBuilder(
            builder: (context, constraints) {
              final dockHeight = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : media?.size.height ?? 720.0;
              final dockWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : media?.size.width ?? 360.0;
              final railMetrics = _SecondaryRailMetrics.resolve(
                dockHeight: dockHeight,
                textScale: textScale,
              );
              final effectiveRailWidth = math.min(
                railMetrics.railWidth,
                math.max(44.0, dockWidth * .17),
              );
              final effectiveRailGap = math.min(
                railMetrics.railGap,
                math.max(5.0, dockWidth * .025),
              );

              return Column(
                children: [
                  _SecondaryDockHeader(
                    subtitle: subtitle,
                    loading: state.isLoading,
                    showBack: locationFocus,
                    onBack: _backLocationWorkspace,
                    showDeveloperStatus: _devModeEnabled,
                    onDeveloperStatus: _showDeveloperStatus,
                    onClose: _close,
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AnimatedContainer(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          width: effectiveRailWidth,
                          child: ClipRect(
                            child: _SecondaryQuickActionRail(
                              primaryItems: _primaryItems,
                              bottomItems: _bottomItems,
                              selectedSection: selected,
                              accountMode: accountWorkspace.mode,
                              showAccountModes: selected == Section.user || selected == Section.tablet,
                              locationChildMode: locationFocus,
                              locationChildren: locationChildren,
                              selectedLocationId: locationState.selectedLocationId,
                              isEnabled: state.canAccess,
                              disabledReason: state.disabledReason,
                              metrics: railMetrics,
                              fullDockHeight: dockHeight,
                              dockWidth: dockWidth,
                              effectiveRailWidth: effectiveRailWidth,
                              effectiveRailGap: effectiveRailGap,
                              onDebug: _debugLog.log,
                              onSelect: (section) {
                                unawaited(_selectSection(state, section));
                              },
                              onSelectAccountMode: (mode) {
                                unawaited(_selectAccountMode(mode));
                              },
                              onSelectLocationChild: (child) {
                                unawaited(_selectLocationChildFromRail(child));
                              },
                            ),
                          ),
                        ),
                        AnimatedContainer(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          width: effectiveRailGap,
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(CommonUiShapes.card),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: tokens.canvas,
                                border: Border.all(color: tokens.borderSubtle),
                                borderRadius:
                                    BorderRadius.circular(CommonUiShapes.card),
                              ),
                              child: Stack(
                                children: [
                                  AnimatedSwitcher(
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
                                    child: _contentFor(selected),
                                  ),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring: !state.isLoading,
                                      child: AnimatedOpacity(
                                        opacity: state.isLoading ? 1 : 0,
                                        duration: reduceMotion
                                            ? Duration.zero
                                            : CommonUiMotion.selection,
                                        child: ColoredBox(
                                          color: tokens.scrim.withOpacity(.12),
                                          child: Center(
                                            child: Container(
                                              width: 46,
                                              height: 46,
                                              decoration: BoxDecoration(
                                                color: tokens.surfaceRaised,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                  CommonUiShapes.control,
                                                ),
                                                border: Border.all(
                                                  color: tokens.borderSubtle,
                                                ),
                                              ),
                                              alignment: Alignment.center,
                                              child: SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2.5,
                                                  color: tokens.accent,
                                                ),
                                              ),
                                            ),
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
                      ],
                    ),
                  ),
                ],
              );
            },
          );
          },
        ),
        ),
      ),
    );
  }
}

class _SecondaryDockHeader extends StatelessWidget {
  const _SecondaryDockHeader({
    required this.subtitle,
    required this.loading,
    required this.showBack,
    required this.onBack,
    required this.showDeveloperStatus,
    required this.onDeveloperStatus,
    required this.onClose,
  });

  final String subtitle;
  final bool loading;
  final bool showBack;
  final VoidCallback onBack;
  final bool showDeveloperStatus;
  final VoidCallback onDeveloperStatus;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        if (showBack)
          CommonIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: '구역 목록으로',
            onPressed: onBack,
            haptic: CommonHaptic.selection,
            size: 40,
            iconSize: 21,
          )
        else
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
              Icons.admin_panel_settings_rounded,
              size: 21,
              color: tokens.onAccentContainer,
            ),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '운영 관리',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (loading) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: tokens.accent,
            ),
          ),
        ],
        if (showDeveloperStatus) ...[
          const SizedBox(width: 6),
          CommonIconButton(
            icon: Icons.bug_report_rounded,
            tooltip: '상태',
            onPressed: onDeveloperStatus,
            haptic: CommonHaptic.selection,
          ),
        ],
        const SizedBox(width: 4),
        CommonIconButton(
          icon: Icons.close_rounded,
          tooltip: '닫기',
          onPressed: onClose,
          haptic: CommonHaptic.light,
        ),
      ],
    );
  }
}

class _SecondaryRailMetrics {
  const _SecondaryRailMetrics({
    required this.variantName,
    required this.compact,
    required this.ultra,
    required this.railWidth,
    required this.railGap,
    required this.minimumButtonExtent,
    required this.headerHeight,
    required this.outerHorizontal,
    required this.outerVertical,
    required this.headerGap,
    required this.actionInsetHorizontal,
    required this.actionInsetVertical,
  });

  final String variantName;
  final bool compact;
  final bool ultra;
  final double railWidth;
  final double railGap;
  final double minimumButtonExtent;
  final double headerHeight;
  final double outerHorizontal;
  final double outerVertical;
  final double headerGap;
  final double actionInsetHorizontal;
  final double actionInsetVertical;

  factory _SecondaryRailMetrics.resolve({
    required double dockHeight,
    required double textScale,
  }) {
    final ultra = dockHeight < 600 || textScale >= 1.30;
    final compact = !ultra && (dockHeight < 720 || textScale >= 1.15);
    return _SecondaryRailMetrics(
      variantName: ultra
          ? 'ultra_compact'
          : compact
              ? 'compact'
              : 'normal',
      compact: compact || ultra,
      ultra: ultra,
      railWidth: ultra
          ? 48.0
          : compact
              ? 52.0
              : 56.0,
      railGap: ultra
          ? 6.0
          : compact
              ? 7.0
              : 8.0,
      minimumButtonExtent: ultra || compact ? 48.0 : 52.0,
      headerHeight: ultra
          ? 34.0
          : compact
              ? 36.0
              : 38.0,
      outerHorizontal: ultra ? 2.0 : 3.0,
      outerVertical: ultra ? 6.0 : 7.0,
      headerGap: 6.0,
      actionInsetHorizontal: ultra
          ? 2.0
          : compact
              ? 3.0
              : 4.0,
      actionInsetVertical: ultra ? 2.0 : 3.0,
    );
  }
}

class _SecondaryQuickActionRail extends StatefulWidget {
  const _SecondaryQuickActionRail({
    required this.primaryItems,
    required this.bottomItems,
    required this.selectedSection,
    required this.accountMode,
    required this.showAccountModes,
    required this.locationChildMode,
    required this.locationChildren,
    required this.selectedLocationId,
    required this.isEnabled,
    required this.disabledReason,
    required this.metrics,
    required this.fullDockHeight,
    required this.dockWidth,
    required this.effectiveRailWidth,
    required this.effectiveRailGap,
    required this.onDebug,
    required this.onSelect,
    required this.onSelectAccountMode,
    required this.onSelectLocationChild,
  });

  final List<_SecondaryRailItem> primaryItems;
  final List<_SecondaryRailItem> bottomItems;
  final Section selectedSection;
  final SecondaryAccountMode accountMode;
  final bool showAccountModes;
  final bool locationChildMode;
  final List<LocationModel> locationChildren;
  final String? selectedLocationId;
  final bool Function(Section section) isEnabled;
  final String Function(Section section) disabledReason;
  final _SecondaryRailMetrics metrics;
  final double fullDockHeight;
  final double dockWidth;
  final double effectiveRailWidth;
  final double effectiveRailGap;
  final ValueChanged<String> onDebug;
  final ValueChanged<Section> onSelect;
  final ValueChanged<SecondaryAccountMode> onSelectAccountMode;
  final ValueChanged<LocationModel> onSelectLocationChild;

  @override
  State<_SecondaryQuickActionRail> createState() =>
      _SecondaryQuickActionRailState();
}

class _SecondaryQuickActionRailState extends State<_SecondaryQuickActionRail> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _childScrollController = ScrollController();
  String? _lastLayoutSignature;
  bool? _lastLocationChildMode;
  String? _lastChildSelectionId;

  @override
  void dispose() {
    _scrollController.dispose();
    _childScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final metrics = widget.metrics;
    final items = <_SecondaryRailItem>[
      ...widget.primaryItems,
      ...widget.bottomItems,
    ];

    Widget railButton(
      _SecondaryRailItem item, {
      required double extent,
    }) {
      return _SecondaryRailButton(
        key: ValueKey<Section>(item.section),
        item: item,
        selected: widget.selectedSection == item.section,
        enabled: widget.isEnabled(item.section),
        disabledReason: widget.disabledReason(item.section),
        compact: metrics.compact,
        extent: extent,
        onTap: () => widget.onSelect(item.section),
      );
    }

    Widget childRailButton(
      LocationModel child, {
      required double extent,
    }) {
      return _SecondaryLocationChildRailButton(
        key: ValueKey<String>('location-child-rail-${child.id}'),
        child: child,
        selected: widget.selectedLocationId == child.id,
        compact: metrics.compact,
        extent: extent,
        onTap: () => widget.onSelectLocationChild(child),
      );
    }

    Widget accountModeZone({required double buttonExtent}) {
      return _SecondaryAccountModeZone(
        visible: widget.showAccountModes,
        mode: widget.accountMode,
        compact: metrics.compact,
        buttonExtent: buttonExtent,
        horizontalInset: metrics.actionInsetHorizontal,
        verticalInset: metrics.actionInsetVertical,
        reduceMotion: reduceMotion,
        onSelect: widget.onSelectAccountMode,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final railHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 720.0;
        final globalActionCount = items.length;
        final globalEnabledCount =
            items.where((item) => widget.isEnabled(item.section)).length;
        final availableListHeight = math.max(
          0.0,
          railHeight -
              metrics.outerVertical * 2 -
              metrics.headerHeight -
              metrics.headerGap,
        );
        final minimumSlotExtent =
            metrics.minimumButtonExtent + metrics.actionInsetVertical * 2;
        final contextSeparatorExtent = metrics.headerGap + 1;
        final contextAreaExtent = minimumSlotExtent * 2 + contextSeparatorExtent;
        final availableNavigationHeight =
            math.max(0.0, availableListHeight - contextAreaExtent);
        final globalEqualSlotExtent = globalActionCount == 0
            ? 0.0
            : availableNavigationHeight / globalActionCount;
        final globalScrollable = globalActionCount > 0 &&
            (globalEqualSlotExtent + .5 < minimumSlotExtent ||
                availableListHeight <
                    globalActionCount * minimumSlotExtent + contextAreaExtent);
        final referenceButtonExtent = globalScrollable
            ? metrics.minimumButtonExtent
            : math.max(
                0.0,
                globalEqualSlotExtent - metrics.actionInsetVertical * 2,
              );
        final childCount = widget.locationChildren.length;
        final childSlotExtent =
            referenceButtonExtent + metrics.actionInsetVertical * 2;
        final childScrollable = widget.locationChildMode &&
            childCount > 0 &&
            childCount * childSlotExtent > availableListHeight + .5;
        final actionCount =
            widget.locationChildMode ? childCount : globalActionCount;
        final enabledCount =
            widget.locationChildMode ? childCount : globalEnabledCount;
        final distribution = widget.locationChildMode
            ? childCount == 0
                ? 'location_child_empty'
                : childScrollable
                    ? 'location_child_scroll'
                    : 'location_child_fixed'
            : globalActionCount == 0
                ? 'empty'
                : globalScrollable
                    ? 'scroll_fallback'
                    : 'equal_fill_with_context';
        final effectiveSlotExtent = widget.locationChildMode
            ? childSlotExtent
            : globalEqualSlotExtent;
        final effectiveButtonExtent = widget.locationChildMode
            ? referenceButtonExtent
            : globalScrollable
                ? metrics.minimumButtonExtent
                : referenceButtonExtent;
        if (_lastLocationChildMode != widget.locationChildMode) {
          final previousMode = _lastLocationChildMode;
          _lastLocationChildMode = widget.locationChildMode;
          _lastChildSelectionId = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final controller = widget.locationChildMode
                ? _childScrollController
                : _scrollController;
            if (controller.hasClients) {
              controller.jumpTo(0);
            }
            widget.onDebug(
              'secondary_rail_mode_changed from=${previousMode == null ? 'initial' : previousMode ? 'location_child' : 'global'} to=${widget.locationChildMode ? 'location_child' : 'global'} actions=$actionCount',
            );
          });
        }
        final currentChildSelection = widget.locationChildMode
            ? widget.selectedLocationId
            : null;
        if (_lastChildSelectionId != currentChildSelection) {
          _lastChildSelectionId = currentChildSelection;
          if (widget.locationChildMode &&
              childScrollable &&
              currentChildSelection != null) {
            final selectedIndex = widget.locationChildren.indexWhere(
              (child) => child.id == currentChildSelection,
            );
            if (selectedIndex >= 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || !_childScrollController.hasClients) return;
                final position = _childScrollController.position;
                final top = selectedIndex * childSlotExtent;
                final bottom = top + childSlotExtent;
                final currentTop = position.pixels;
                final currentBottom = currentTop + position.viewportDimension;
                double? target;
                if (top < currentTop) {
                  target = top;
                } else if (bottom > currentBottom) {
                  target = bottom - position.viewportDimension;
                }
                if (target == null) return;
                final clamped = target.clamp(
                  position.minScrollExtent,
                  position.maxScrollExtent,
                ).toDouble();
                if (reduceMotion) {
                  _childScrollController.jumpTo(clamped);
                } else {
                  unawaited(
                    _childScrollController.animateTo(
                      clamped,
                      duration: CommonUiMotion.selection,
                      curve: CommonUiMotion.enter,
                    ),
                  );
                }
                widget.onDebug(
                  'secondary_rail_child_scrolled_to_selection id=$currentChildSelection index=$selectedIndex offset=${clamped.toStringAsFixed(1)}',
                );
              });
            }
          }
        }
        final signature = <Object>[
          metrics.variantName,
          widget.fullDockHeight.toStringAsFixed(0),
          widget.dockWidth.toStringAsFixed(0),
          widget.effectiveRailWidth.toStringAsFixed(1),
          widget.effectiveRailGap.toStringAsFixed(1),
          railHeight.toStringAsFixed(0),
          widget.locationChildMode,
          actionCount,
          enabledCount,
          distribution,
          effectiveSlotExtent.toStringAsFixed(1),
          effectiveButtonExtent.toStringAsFixed(1),
          widget.selectedSection.name,
          widget.accountMode.name,
          widget.showAccountModes,
        ].join('|');
        if (_lastLayoutSignature != signature) {
          _lastLayoutSignature = signature;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.onDebug(
              'secondary_rail_layout mode=${widget.locationChildMode ? 'location_child' : 'global'} dock_width=${widget.dockWidth.toStringAsFixed(1)} dock_height=${widget.fullDockHeight.toStringAsFixed(1)} rail_height=${railHeight.toStringAsFixed(1)} base_width=${metrics.railWidth.toStringAsFixed(1)} width=${widget.effectiveRailWidth.toStringAsFixed(1)} base_gap=${metrics.railGap.toStringAsFixed(1)} gap=${widget.effectiveRailGap.toStringAsFixed(1)} navigation_actions=$actionCount enabled=$enabledCount reference_actions=$globalActionCount context_actions=${widget.locationChildMode ? 0 : 2} context_visible=${widget.locationChildMode ? false : widget.showAccountModes} account_mode=${widget.accountMode.name} distribution=$distribution scroll=${widget.locationChildMode ? childScrollable : globalScrollable} navigation_slot=${effectiveSlotExtent.toStringAsFixed(1)} button_extent=${effectiveButtonExtent.toStringAsFixed(1)} context_extent=${widget.locationChildMode ? '0.0' : contextAreaExtent.toStringAsFixed(1)} inset_x=${metrics.actionInsetHorizontal.toStringAsFixed(0)} inset_y=${metrics.actionInsetVertical.toStringAsFixed(0)} variant=${metrics.variantName}',
            );
          });
        }

        Widget contextSeparator() {
          return SizedBox(
            height: contextSeparatorExtent,
            child: AnimatedOpacity(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              opacity: widget.showAccountModes ? 1 : 0,
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  height: 1,
                  margin: EdgeInsets.symmetric(
                    horizontal: metrics.actionInsetHorizontal + 2,
                  ),
                  color: tokens.borderSubtle,
                ),
              ),
            ),
          );
        }

        Widget fixedChildColumn() {
          return Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in widget.locationChildren)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.actionInsetHorizontal,
                      vertical: metrics.actionInsetVertical,
                    ),
                    child: childRailButton(
                      child,
                      extent: referenceButtonExtent,
                    ),
                  ),
              ],
            ),
          );
        }

        Widget scrollableChildColumn() {
          return Scrollbar(
            controller: _childScrollController,
            thumbVisibility: true,
            thickness: 2,
            radius: const Radius.circular(2),
            child: SingleChildScrollView(
              controller: _childScrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final child in widget.locationChildren)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: metrics.actionInsetHorizontal,
                          vertical: metrics.actionInsetVertical,
                        ),
                        child: childRailButton(
                          child,
                          extent: referenceButtonExtent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        final Widget actionArea;
        if (widget.locationChildMode) {
          actionArea = childCount == 0
              ? const SizedBox.expand()
              : childScrollable
                  ? scrollableChildColumn()
                  : fixedChildColumn();
        } else if (globalActionCount == 0) {
          actionArea = const SizedBox.expand();
        } else if (globalScrollable) {
          actionArea = Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            thickness: 2,
            radius: const Radius.circular(2),
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in items)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: metrics.actionInsetHorizontal,
                          vertical: metrics.actionInsetVertical,
                        ),
                        child: railButton(
                          item,
                          extent: metrics.minimumButtonExtent,
                        ),
                      ),
                    contextSeparator(),
                    accountModeZone(
                      buttonExtent: metrics.minimumButtonExtent,
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          actionArea = Column(
            key: ValueKey<String>(
              'equal_context|${metrics.variantName}|$globalActionCount',
            ),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in items)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: metrics.actionInsetHorizontal,
                            vertical: metrics.actionInsetVertical,
                          ),
                          child: railButton(
                            item,
                            extent: referenceButtonExtent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              contextSeparator(),
              accountModeZone(
                buttonExtent: metrics.minimumButtonExtent,
              ),
            ],
          );
        }

        return Semantics(
          container: true,
          label: widget.locationChildMode ? '자식 주차 구역' : '운영 관리',
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: metrics.outerHorizontal,
              vertical: metrics.outerVertical,
            ),
            decoration: BoxDecoration(
              color: tokens.surface.withOpacity(.26),
              border: Border(
                right: BorderSide(color: tokens.borderSubtle),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: metrics.headerHeight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        width: metrics.ultra ? 18 : 22,
                        height: 3,
                        decoration: BoxDecoration(
                          color: tokens.iconSecondary,
                          borderRadius:
                              BorderRadius.circular(CommonUiShapes.pill),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '운영 관리',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: textTheme.labelSmall?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w900,
                          height: 1.02,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: metrics.headerGap),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeOutCubic,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          fit: StackFit.expand,
                          alignment: Alignment.center,
                          children: [
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      transitionBuilder: (child, animation) {
                        final begin = widget.locationChildMode
                            ? const Offset(.08, 0)
                            : const Offset(-.05, 0);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: begin,
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey<String>(
                          '${widget.locationChildMode ? 'location_child' : 'global'}|$distribution|${metrics.variantName}|$actionCount',
                        ),
                        child: actionArea,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SecondaryAccountModeZone extends StatelessWidget {
  const _SecondaryAccountModeZone({
    required this.visible,
    required this.mode,
    required this.compact,
    required this.buttonExtent,
    required this.horizontalInset,
    required this.verticalInset,
    required this.reduceMotion,
    required this.onSelect,
  });

  final bool visible;
  final SecondaryAccountMode mode;
  final bool compact;
  final double buttonExtent;
  final double horizontalInset;
  final double verticalInset;
  final bool reduceMotion;
  final ValueChanged<SecondaryAccountMode> onSelect;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.enter,
        opacity: visible ? 1 : 0,
        child: AnimatedSlide(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.enter,
          offset: visible ? Offset.zero : const Offset(0, .06),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalInset,
                  vertical: verticalInset,
                ),
                child: _SecondaryAccountModeButton(
                  mode: SecondaryAccountMode.operation,
                  selected: mode == SecondaryAccountMode.operation,
                  compact: compact,
                  extent: buttonExtent,
                  onTap: () => onSelect(SecondaryAccountMode.operation),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalInset,
                  vertical: verticalInset,
                ),
                child: _SecondaryAccountModeButton(
                  mode: SecondaryAccountMode.delete,
                  selected: mode == SecondaryAccountMode.delete,
                  compact: compact,
                  extent: buttonExtent,
                  onTap: () => onSelect(SecondaryAccountMode.delete),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryAccountModeButton extends StatefulWidget {
  const _SecondaryAccountModeButton({
    required this.mode,
    required this.selected,
    required this.compact,
    required this.extent,
    required this.onTap,
  });

  final SecondaryAccountMode mode;
  final bool selected;
  final bool compact;
  final double extent;
  final VoidCallback onTap;

  @override
  State<_SecondaryAccountModeButton> createState() =>
      _SecondaryAccountModeButtonState();
}

class _SecondaryAccountModeButtonState
    extends State<_SecondaryAccountModeButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final deleteMode = widget.mode == SecondaryAccountMode.delete;
    final base = deleteMode ? tokens.danger : tokens.success;
    final container =
        deleteMode ? tokens.dangerContainer : tokens.successContainer;
    final onBase = deleteMode ? tokens.onDanger : tokens.onSuccess;
    final onContainer =
        deleteMode ? tokens.onDangerContainer : tokens.onSuccessContainer;
    final background = widget.selected
        ? base.withOpacity(_pressed ? .88 : 1)
        : container.withOpacity(_pressed ? .92 : .72);
    final foreground = widget.selected ? onBase : onContainer;
    final border = widget.selected ? base : base.withOpacity(.32);
    final icon = deleteMode
        ? Icons.delete_forever_rounded
        : Icons.admin_panel_settings_rounded;
    final label = deleteMode ? '삭제' : '운영';

    return Semantics(
      button: true,
      selected: widget.selected,
      label: '$label 모드',
      child: AnimatedScale(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.enter,
        scale: _pressed ? .97 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            onHighlightChanged: (value) {
              if (!mounted) return;
              setState(() => _pressed = value);
            },
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              height: widget.extent,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedScale(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    scale: widget.selected ? 1.06 : 1,
                    child: Icon(
                      icon,
                      size: widget.compact ? 19 : 20,
                      color: foreground,
                    ),
                  ),
                  SizedBox(height: widget.compact ? 2 : 3),
                  AnimatedDefaultTextStyle(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    curve: CommonUiMotion.standard,
                    style: textTheme.labelSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ) ??
                        TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryRailButton extends StatelessWidget {
  const _SecondaryRailButton({
    super.key,
    required this.item,
    required this.selected,
    required this.enabled,
    required this.disabledReason,
    required this.compact,
    required this.extent,
    required this.onTap,
  });

  final _SecondaryRailItem item;
  final bool selected;
  final bool enabled;
  final String disabledReason;
  final bool compact;
  final double extent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SecondaryRailActionButton(
      semanticLabel: item.label,
      visualLabel: item.visualLabel,
      icon: item.icon,
      selected: selected,
      enabled: enabled,
      disabledReason: disabledReason,
      compact: compact,
      extent: extent,
      onTap: onTap,
    );
  }
}

class _SecondaryLocationChildRailButton extends StatelessWidget {
  const _SecondaryLocationChildRailButton({
    super.key,
    required this.child,
    required this.selected,
    required this.compact,
    required this.extent,
    required this.onTap,
  });

  final LocationModel child;
  final bool selected;
  final bool compact;
  final double extent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: child.locationName,
      child: _SecondaryRailActionButton(
        semanticLabel: '${child.locationName} 자식 주차 구역',
        visualLabel: child.locationName,
        icon: child.isTowerChild
            ? Icons.apartment_rounded
            : Icons.local_parking_rounded,
        selected: selected,
        enabled: true,
        disabledReason: '',
        compact: compact,
        extent: extent,
        onTap: onTap,
      ),
    );
  }
}

class _SecondaryRailActionButton extends StatefulWidget {
  const _SecondaryRailActionButton({
    required this.semanticLabel,
    required this.visualLabel,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.disabledReason,
    required this.compact,
    required this.extent,
    required this.onTap,
  });

  final String semanticLabel;
  final String visualLabel;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final String disabledReason;
  final bool compact;
  final double extent;
  final VoidCallback onTap;

  @override
  State<_SecondaryRailActionButton> createState() =>
      _SecondaryRailActionButtonState();
}

class _SecondaryRailActionButtonState
    extends State<_SecondaryRailActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = widget.enabled;
    final foreground = widget.selected && enabled
        ? tokens.accent
        : enabled
            ? tokens.iconPrimary
            : tokens.iconDisabled;
    final textColor = widget.selected && enabled
        ? tokens.accent
        : enabled
            ? tokens.textPrimary
            : tokens.textDisabled;
    final background = widget.selected && enabled
        ? tokens.accentContainer.withOpacity(_pressed ? .86 : .62)
        : _pressed && enabled
            ? tokens.accentContainer.withOpacity(.72)
            : enabled
                ? tokens.surfaceRaised
                : tokens.surfaceDisabled;
    final border = widget.selected && enabled
        ? tokens.accent.withOpacity(_pressed ? .58 : .38)
        : !enabled && _pressed
            ? tokens.warning
            : _pressed && enabled
                ? tokens.accent.withOpacity(.42)
                : tokens.borderSubtle;

    return Semantics(
      container: true,
      button: true,
      selected: widget.selected,
      enabled: true,
      excludeSemantics: true,
      label: widget.semanticLabel,
      value: enabled || widget.disabledReason.isEmpty
          ? null
          : widget.disabledReason,
      child: AnimatedOpacity(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        opacity: enabled ? 1 : .56,
        child: AnimatedScale(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.standard,
          scale: _pressed ? (enabled ? .97 : .985) : 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onTap,
              onHighlightChanged: (value) {
                if (!mounted) return;
                setState(() {
                  _pressed = value;
                });
              },
              child: AnimatedContainer(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                curve: CommonUiMotion.standard,
                width: double.infinity,
                height: widget.extent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedScale(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      scale: _pressed && enabled ? 1.04 : 1,
                      child: Icon(
                        widget.icon,
                        size: widget.compact ? 19 : 20,
                        color: foreground,
                      ),
                    ),
                    SizedBox(height: widget.compact ? 2 : 3),
                    AnimatedDefaultTextStyle(
                      duration: reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      curve: CommonUiMotion.standard,
                      style: textTheme.labelSmall?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                          ) ??
                          TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                          ),
                      child: Text(
                        widget.visualLabel,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryRailItem {
  const _SecondaryRailItem({
    required this.section,
    required this.label,
    required this.icon,
    this.displayLabel = '',
  });

  final Section section;
  final String label;
  final String displayLabel;
  final IconData icon;

  String get visualLabel {
    final value = displayLabel.trim();
    return value.isEmpty ? label.trim() : value;
  }
}

class _SecondaryDockDebugLog {
  final List<String> _lines = <String>[];

  void log(String message) {
    final line =
        '[SecondarySideDock][${DateTime.now().toIso8601String()}] $message';
    _lines.add(line);
    if (_lines.length > 200) {
      _lines.removeRange(0, _lines.length - 200);
    }
    debugPrint(line);
  }

  String get debugPrintCode => _lines
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');

  Future<void> showStatus(BuildContext context) async {
    final visible = _lines.length > 40
        ? _lines.sublist(_lines.length - 40)
        : List<String>.from(_lines);
    await StatusDialog.showSuccess(
      context,
      title: '운영 관리 상태',
      description: visible.join('\n'),
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: const Duration(seconds: 60),
      useCommonUi: true,
    );
  }
}
