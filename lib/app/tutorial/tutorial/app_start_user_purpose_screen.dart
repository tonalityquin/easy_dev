import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/di/routes.dart';
import '../../../app/init/app_start_debug_trace.dart';
import '../../../app/init/app_start_flow_prefs.dart';
import '../../../app/init/app_start_user_purpose.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_side_dock_action_tile.dart';
import '../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../features/selector/application/dev_auth.dart';
import '../policy/policy_documents.dart';
import 'app_start_setup_specs.dart';

class AppStartUserPurposeScreen extends StatefulWidget {
  const AppStartUserPurposeScreen({super.key});

  @override
  State<AppStartUserPurposeScreen> createState() =>
      _AppStartUserPurposeScreenState();
}

class _AppStartUserPurposeScreenState extends State<AppStartUserPurposeScreen> {
  AppStartUserPurpose? _selected;
  AppStartUserPurpose? _dockPurpose;
  bool _busy = false;
  bool _dockActive = false;
  Map<String, Object?> _dockDebugState = const <String, Object?>{};

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    AppStartDebugTrace.log(
      'user_purpose',
      'screen_init',
      meta: const <String, Object?>{
        'uiProfile': 'list_surface_left_sidedock_single_line_tiles_adaptive_scroll',
        'mainVerticalScroll': false,
        'dockVerticalScrollMode': 'adaptive',
        'inlineExpansion': false,
      },
    );
    DevAuth.isDevModeEnabled();
    _loadSavedPurpose();
  }

  Future<void> _loadSavedPurpose() async {
    final saved = await AppStartFlowPrefs.getUserPurpose();
    if (!mounted || saved == null) return;
    setState(() => _selected = saved);
    AppStartDebugTrace.log(
      'user_purpose',
      'saved_purpose_loaded',
      meta: <String, Object?>{
        'purpose': saved.storageValue,
        'stepCount': saved.permissionStepNumbers.length,
        'steps': saved.permissionStepNumbers.join(','),
        'policyPostSetup':
            saved.skipsPolicyAndPostSetup ? 'skip' : 'required',
      },
    );
  }

  IconData _iconForPurpose(AppStartUserPurpose purpose) {
    return switch (purpose) {
      AppStartUserPurpose.branchEmployee => Icons.business_rounded,
      AppStartUserPurpose.headOfficeEmployee => Icons.domain_rounded,
      AppStartUserPurpose.tabletInstallation => Icons.tablet_android_rounded,
      AppStartUserPurpose.commuteRecorder => Icons.schedule_rounded,
      AppStartUserPurpose.personal => Icons.person_rounded,
    };
  }


  Future<void> _selectAndOpenPurpose(AppStartUserPurpose purpose) async {
    if (_busy || _dockActive) return;

    final previous = _selected;
    final changed = previous != purpose;

    if (changed) {
      await HapticFeedback.selectionClick();
      if (!mounted) return;
      setState(() => _selected = purpose);
    } else {
      await HapticFeedback.lightImpact();
      if (!mounted) return;
    }

    AppStartDebugTrace.log(
      'user_purpose',
      changed ? 'purpose_selected' : 'purpose_reopened',
      meta: <String, Object?>{
        'previous': previous?.storageValue ?? 'none',
        'purpose': purpose.storageValue,
        'stepCount': purpose.permissionStepNumbers.length,
        'steps': purpose.permissionStepNumbers.join(','),
        'policyPostSetup':
            purpose.skipsPolicyAndPostSetup ? 'skip' : 'required',
        'reduceMotion': _reduceMotion,
      },
    );

    await _openPurposeSideDock(purpose);
  }

  Future<void> _openPurposeSideDock(AppStartUserPurpose purpose) async {
    if (!mounted || _busy || _dockActive) return;

    setState(() {
      _dockActive = true;
      _dockPurpose = purpose;
    });
    _dockDebugState = <String, Object?>{
      'dockSection': 'permissions',
      'permissionLayout': 'single_line_vertical',
      'permissionCount': purpose.permissionStepNumbers.length,
      'detailType': 'none',
      'dockVerticalScrollMode': 'adaptive',
      'dockVerticalScrollEnabled': false,
    };

    AppStartDebugTrace.log(
      'user_purpose',
      'purpose_dock_open',
      meta: <String, Object?>{
        'purpose': purpose.storageValue,
        'stepCount': purpose.permissionStepNumbers.length,
        'steps': purpose.permissionStepNumbers.join(','),
        'policyPostSetup':
            purpose.skipsPolicyAndPostSetup ? 'skip' : 'required',
        'side': 'left',
        'verticalScrollMode': 'adaptive',
        'reduceMotion': _reduceMotion,
      },
    );

    final confirmed = await showCommonLeftSideDock<bool>(
      context: context,
      barrierLabel: '${purpose.label} 설정',
      barrierDismissible: true,
      builder: (dockContext) {
        return _buildPurposeSideDock(
          dockContext,
          purpose,
        );
      },
    );

    if (!mounted) return;

    setState(() {
      _dockActive = false;
      _dockPurpose = null;
    });

    AppStartDebugTrace.log(
      'user_purpose',
      'purpose_dock_close',
      meta: <String, Object?>{
        'purpose': purpose.storageValue,
        'confirmed': confirmed == true,
        'result': confirmed == null ? 'dismissed' : confirmed,
      },
    );

    if (confirmed == true) {
      await _confirmPurpose(purpose);
    }
  }

  Future<void> _confirmPurpose(AppStartUserPurpose selected) async {
    if (_busy) return;

    if (_selected != selected && mounted) {
      setState(() => _selected = selected);
    }

    setState(() => _busy = true);

    AppStartDebugTrace.log(
      'user_purpose',
      'purpose_confirm_start',
      meta: <String, Object?>{
        'purpose': selected.storageValue,
        'stepCount': selected.permissionStepNumbers.length,
        'steps': selected.permissionStepNumbers.join(','),
        'source': 'left_sidedock',
      },
    );

    try {
      await AppStartFlowPrefs.setUserPurpose(selected);
      AppStartDebugTrace.log(
        'user_purpose',
        'purpose_confirm_success',
        meta: <String, Object?>{
          'purpose': selected.storageValue,
          'stepCount': selected.permissionStepNumbers.length,
          'policyPostSetup':
              selected.skipsPolicyAndPostSetup ? 'skip' : 'required',
          'nextRoute': AppRoutes.appStartPermissionNotice,
          'source': 'left_sidedock',
        },
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.appStartPermissionNotice,
      );
    } catch (error, stackTrace) {
      AppStartDebugTrace.log(
        'user_purpose',
        'purpose_confirm_failure',
        meta: <String, Object?>{
          'purpose': selected.storageValue,
          'error': error,
          'stackTrace': stackTrace,
          'source': 'left_sidedock',
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showDeveloperStatus(
    BuildContext dialogContext, {
    AppStartUserPurpose? purpose,
    String origin = 'app_bar',
  }) async {
    final selected = purpose ?? _selected;
    AppStartDebugTrace.log(
      'user_purpose',
      'developer_status_snapshot',
      meta: <String, Object?>{
        'origin': origin,
        'selected': selected?.storageValue ?? 'none',
        'busy': _busy,
        'dockActive': _dockActive,
        'dockPurpose': _dockPurpose?.storageValue ?? 'none',
        'reduceMotion': _reduceMotion,
        'stepCount': selected?.permissionStepNumbers.length ?? 0,
        'steps': selected?.permissionStepNumbers.join(',') ?? '',
        'policyPostSetup': selected == null
            ? 'none'
            : selected.skipsPolicyAndPostSetup
                ? 'skip'
                : 'required',
        'uiProfile': 'list_surface_left_sidedock_single_line_tiles_adaptive_scroll',
        'mainVerticalScroll': false,
        'dockVerticalScrollMode': 'adaptive',
        ..._dockDebugState,
      },
    );

    await AppStartDebugTrace.showDeveloperStatus(
      dialogContext,
      title: '사용 환경 선택 개발자 상태',
      description: '사용 환경 선택 화면의 debugPrint 코드를 복사할 수 있습니다.',
      scope: 'user_purpose',
    );
  }

  Widget _buildHeader(
    BuildContext context,
    _PurposeLayoutMetrics metrics,
  ) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return _PurposeSectionEntrance(
      child: Column(
        children: [
          Text(
            '어떻게 사용하시나요?',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (metrics.ultra
                    ? textTheme.titleLarge
                    : textTheme.headlineSmall)
                ?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (metrics.showHeaderDescription) ...[
            SizedBox(height: metrics.headerTextGap),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Text(
                '사용 환경에 맞게 필요한 권한과 시작 설정을 구성합니다.',
                textAlign: TextAlign.center,
                maxLines: metrics.compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: (metrics.compact
                        ? textTheme.bodyMedium
                        : textTheme.bodyLarge)
                    ?.copyWith(
                  color: tokens.textSecondary,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPurposeListSurface(
    BuildContext context,
    _PurposeLayoutMetrics metrics,
  ) {
    final tokens = CommonUiTheme.of(context);
    final purposes = AppStartUserPurpose.values;

    return _PurposeSectionEntrance(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < purposes.length; i++) ...[
                  _PurposeSelectionRow(
                    purpose: purposes[i],
                    icon: _iconForPurpose(purposes[i]),
                    selected: _selected == purposes[i],
                    enabled: !_busy && !_dockActive,
                    metrics: metrics,
                    onTap: () => _selectAndOpenPurpose(purposes[i]),
                  ),
                  if (i < purposes.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: tokens.borderSubtle,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPurposeSideDock(
    BuildContext dockContext,
    AppStartUserPurpose purpose,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.maybeOf(context);
        final textScale = media?.textScaler.scale(1.0) ?? 1.0;
        final compact = constraints.maxHeight < 620 || textScale >= 1.30;
        final buttonHeight = compact ? 46.0 : 52.0;
        final sectionGap = compact ? 8.0 : 12.0;

        return CommonSideDockFrame(
          title: purpose.label,
          subtitle: purpose.description,
          icon: _iconForPurpose(purpose),
          onClose: () {
            AppStartDebugTrace.log(
              'user_purpose',
              'purpose_dock_close_requested',
              meta: <String, Object?>{
                'purpose': purpose.storageValue,
                'source': 'close_button',
                ..._dockDebugState,
              },
            );
            Navigator.of(dockContext).pop(false);
          },
          headerAction: ValueListenableBuilder<bool>(
            valueListenable: DevAuth.devModeEnabled,
            builder: (context, enabled, child) {
              if (!enabled) return const SizedBox.shrink();
              return IconButton(
                onPressed: () => _showDeveloperStatus(
                  dockContext,
                  purpose: purpose,
                  origin: 'left_sidedock',
                ),
                icon: const Icon(Icons.terminal_rounded),
              );
            },
          ),
          sectionGap: sectionGap,
          child: _PurposeSetupPreviewDock(
            purpose: purpose,
            onDebugStateChanged: (state) {
              _dockDebugState = state;
            },
          ),
          footer: CommonSideDockPrimaryFooter(
            child: CommonButton(
              label: '이 유형으로 시작',
              icon: Icons.arrow_forward_rounded,
              onPressed: () {
                AppStartDebugTrace.log(
                  'user_purpose',
                  'purpose_dock_confirm',
                  meta: <String, Object?>{
                    'purpose': purpose.storageValue,
                    'stepCount': purpose.permissionStepNumbers.length,
                    'steps': purpose.permissionStepNumbers.join(','),
                    ..._dockDebugState,
                  },
                );
                Navigator.of(dockContext).pop(true);
              },
              expand: true,
              minHeight: buttonHeight,
              haptic: CommonHaptic.selection,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(
        builder: (context) {
          final tokens = CommonUiTheme.of(context);
          final iconBrightness =
              tokens.isDark ? Brightness.light : Brightness.dark;

          return PopScope(
            canPop: false,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: tokens.surface,
                statusBarIconBrightness: iconBrightness,
                statusBarBrightness:
                    tokens.isDark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: tokens.canvas,
                systemNavigationBarIconBrightness: iconBrightness,
                systemNavigationBarDividerColor: tokens.borderSubtle,
              ),
              child: Scaffold(
                backgroundColor: tokens.canvas,
                appBar: AppBar(
                  title: const Text('사용 환경 선택'),
                  centerTitle: true,
                  automaticallyImplyLeading: false,
                  actions: [
                    ValueListenableBuilder<bool>(
                      valueListenable: DevAuth.devModeEnabled,
                      builder: (context, enabled, child) {
                        if (!enabled) return const SizedBox.shrink();
                        return IconButton(
                          onPressed: () => _showDeveloperStatus(context),
                          icon: const Icon(Icons.terminal_rounded),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                body: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final media = MediaQuery.maybeOf(context);
                      final textScale =
                          media?.textScaler.scale(1.0) ?? 1.0;
                      final metrics = _PurposeLayoutMetrics.resolve(
                        height: constraints.maxHeight,
                        textScale: textScale,
                      );

                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              metrics.topPadding,
                              16,
                              metrics.bottomPadding,
                            ),
                            child: Column(
                              children: [
                                _buildHeader(context, metrics),
                                SizedBox(height: metrics.sectionGap),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: _buildPurposeListSurface(
                                      context,
                                      metrics,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PurposeSelectionRow extends StatefulWidget {
  const _PurposeSelectionRow({
    required this.purpose,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.metrics,
    required this.onTap,
  });

  final AppStartUserPurpose purpose;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final _PurposeLayoutMetrics metrics;
  final VoidCallback onTap;

  @override
  State<_PurposeSelectionRow> createState() => _PurposeSelectionRowState();
}

class _PurposeSelectionRowState extends State<_PurposeSelectionRow> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selected = widget.selected;
    final metrics = widget.metrics;

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      enabled: widget.enabled,
      label:
          '${widget.purpose.label}, ${widget.purpose.description}, 설정 ${widget.purpose.permissionStepNumbers.length}단계',
      value: selected ? '선택됨' : '선택 안 됨',
      child: AnimatedScale(
        scale: _pressed && widget.enabled ? 0.985 : 1,
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.standard,
        alignment: Alignment.center,
        child: Stack(
          children: [
            AnimatedContainer(
              duration:
                  reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              color: selected
                  ? tokens.surfaceSelected.withOpacity(
                      tokens.isDark ? 0.78 : 0.72,
                    )
                  : Colors.transparent,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.enabled ? widget.onTap : null,
                  onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
                  onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
                  onTapCancel:
                      widget.enabled ? () => _setPressed(false) : null,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      metrics.rowHorizontalPadding,
                      metrics.rowVerticalPadding,
                      metrics.rowHorizontalPadding + 1,
                      metrics.rowVerticalPadding,
                    ),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: reduceMotion
                              ? Duration.zero
                              : CommonUiMotion.selection,
                          curve: CommonUiMotion.standard,
                          width: metrics.iconBoxSize,
                          height: metrics.iconBoxSize,
                          decoration: BoxDecoration(
                            color: selected
                                ? tokens.accentContainer
                                : tokens.surfaceOverlay,
                            borderRadius: BorderRadius.circular(
                              metrics.iconRadius,
                            ),
                          ),
                          child: AnimatedSwitcher(
                            duration: reduceMotion
                                ? Duration.zero
                                : CommonUiMotion.selection,
                            switchInCurve: CommonUiMotion.enter,
                            switchOutCurve: CommonUiMotion.exit,
                            child: Icon(
                              widget.icon,
                              key: ValueKey<bool>(selected),
                              size: metrics.iconSize,
                              color: selected
                                  ? tokens.onAccentContainer
                                  : tokens.iconSecondary,
                            ),
                          ),
                        ),
                        SizedBox(width: metrics.leadingGap),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.purpose.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: (metrics.compact
                                        ? textTheme.titleSmall
                                        : textTheme.titleMedium)
                                    ?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (metrics.showDescriptions) ...[
                                SizedBox(height: metrics.descriptionGap),
                                Text(
                                  widget.purpose.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: (metrics.compact
                                          ? textTheme.bodySmall
                                          : textTheme.bodyMedium)
                                      ?.copyWith(
                                    color: tokens.textSecondary,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(width: metrics.trailingGap),
                        AnimatedDefaultTextStyle(
                          duration: reduceMotion
                              ? Duration.zero
                              : CommonUiMotion.selection,
                          curve: CommonUiMotion.standard,
                          style: (metrics.compact
                                  ? textTheme.labelSmall
                                  : textTheme.labelMedium)
                              ?.copyWith(
                                color: selected
                                    ? tokens.accent
                                    : tokens.textSecondary,
                                fontWeight: FontWeight.w800,
                              ) ??
                              const TextStyle(),
                          child: Text(
                            '${widget.purpose.permissionStepNumbers.length}단계',
                            maxLines: 1,
                          ),
                        ),
                        SizedBox(width: metrics.indicatorGap),
                        AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : CommonUiMotion.selection,
                          switchInCurve: CommonUiMotion.enter,
                          switchOutCurve: CommonUiMotion.exit,
                          transitionBuilder: (child, animation) {
                            final fade = CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                              reverseCurve: Curves.easeInCubic,
                            );
                            return FadeTransition(
                              opacity: fade,
                              child: ScaleTransition(
                                scale: Tween<double>(begin: 0.82, end: 1)
                                    .animate(fade),
                                child: child,
                              ),
                            );
                          },
                          child: selected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  key: const ValueKey<String>('selected'),
                                  color: tokens.accent,
                                  size: metrics.indicatorSize,
                                )
                              : Icon(
                                  Icons.radio_button_unchecked_rounded,
                                  key: const ValueKey<String>('unselected'),
                                  color: tokens.iconSecondary,
                                  size: metrics.indicatorSize,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: metrics.railInset,
              bottom: metrics.railInset,
              right: 0,
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : CommonUiMotion.selection,
                  curve: CommonUiMotion.standard,
                  width: selected ? 3 : 0,
                  decoration: BoxDecoration(
                    color: tokens.accent,
                    borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PurposeDockSection {
  permissions,
  followUp,
}

enum _PurposeDockGroup {
  none,
  policy,
  google,
}

class _PurposeDockInfoDetail {
  const _PurposeDockInfoDetail({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.icon,
    required this.meta,
  });

  final String id;
  final String type;
  final String title;
  final String description;
  final IconData icon;
  final String meta;
}

class _PurposeSetupPreviewDock extends StatefulWidget {
  const _PurposeSetupPreviewDock({
    required this.purpose,
    required this.onDebugStateChanged,
  });

  final AppStartUserPurpose purpose;
  final ValueChanged<Map<String, Object?>> onDebugStateChanged;

  @override
  State<_PurposeSetupPreviewDock> createState() =>
      _PurposeSetupPreviewDockState();
}

class _PurposeSetupPreviewDockState extends State<_PurposeSetupPreviewDock> {
  final ScrollController _scrollController = ScrollController();
  _PurposeDockSection _section = _PurposeDockSection.permissions;
  _PurposeDockGroup _group = _PurposeDockGroup.none;
  _PurposeDockInfoDetail? _infoDetail;
  bool _verticalScrollEnabled = false;
  double _viewportHeight = 0;
  double _textScale = 1;
  bool? _lastReportedVerticalScroll;

  List<AppStartPermissionSpec> get _permissionSpecs =>
      appStartPermissionSpecsForSteps(widget.purpose.permissionStepNumbers);

  bool get _skipsFollowUp => widget.purpose.skipsPolicyAndPostSetup;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _emitDebug('purpose_dock_content_ready');
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Map<String, Object?> _debugState() {
    final permissionCount = _permissionSpecs.length;
    final hasClients = _scrollController.hasClients;
    final position = hasClients ? _scrollController.position : null;
    return <String, Object?>{
      'dockSection': _section.name,
      'permissionLayout': 'single_line_vertical',
      'permissionCount': permissionCount,
      'visiblePermissionCount': permissionCount,
      'detailGroup': _group.name,
      'detailType': _infoDetail?.type ?? 'none',
      'detailId': _infoDetail?.id ?? 'none',
      'followUpSkipped': _skipsFollowUp,
      'dockVerticalScrollMode': 'adaptive',
      'dockVerticalScrollEnabled': _verticalScrollEnabled,
      'dockViewportHeight': _viewportHeight.toStringAsFixed(1),
      'dockTextScale': _textScale.toStringAsFixed(2),
      'dockScrollOffset':
          hasClients ? _scrollController.offset.toStringAsFixed(1) : '0.0',
      'dockScrollMaxExtent':
          position == null ? '0.0' : position.maxScrollExtent.toStringAsFixed(1),
    };
  }

  void _emitDebug(
    String event, {
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final state = <String, Object?>{
      ..._debugState(),
      ...meta,
    };
    widget.onDebugStateChanged(state);
    AppStartDebugTrace.log(
      'user_purpose',
      event,
      meta: <String, Object?>{
        'purpose': widget.purpose.storageValue,
        ...state,
      },
    );
  }

  Future<void> _feedback() async {
    await HapticFeedback.selectionClick();
  }

  void _resetScrollPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (_scrollController.offset == 0) return;
      if (reduceMotion) {
        _scrollController.jumpTo(0);
        return;
      }
      _scrollController.animateTo(
        0,
        duration: CommonUiMotion.component,
        curve: CommonUiMotion.enter,
      );
    });
  }

  void _reportScrollModeIfNeeded() {
    if (_lastReportedVerticalScroll == _verticalScrollEnabled) return;
    _lastReportedVerticalScroll = _verticalScrollEnabled;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _emitDebug(
        'purpose_dock_scroll_mode_changed',
        meta: <String, Object?>{
          'enabled': _verticalScrollEnabled,
          'viewportHeight': _viewportHeight.toStringAsFixed(1),
          'textScale': _textScale.toStringAsFixed(2),
        },
      );
    });
  }

  void _setSection(_PurposeDockSection section) {
    if (_section == section &&
        _group == _PurposeDockGroup.none &&
        _infoDetail == null) {
      return;
    }
    _feedback();
    setState(() {
      _section = section;
      _group = _PurposeDockGroup.none;
      _infoDetail = null;
    });
    _resetScrollPosition();
    _emitDebug('purpose_dock_section_changed');
  }

  void _openPermissionDetail(
    AppStartPermissionSpec spec,
    int index,
    int total,
  ) {
    _feedback();
    setState(() {
      _infoDetail = _PurposeDockInfoDetail(
        id: spec.keyName,
        type: 'permission',
        title: spec.title,
        description: spec.description,
        icon: spec.icon,
        meta: '${index + 1} / $total 단계',
      );
    });
    _resetScrollPosition();
    _emitDebug(
      'purpose_dock_permission_detail_open',
      meta: <String, Object?>{'step': spec.step},
    );
  }

  void _openGroup(_PurposeDockGroup group) {
    _feedback();
    setState(() {
      _group = group;
      _infoDetail = null;
    });
    _resetScrollPosition();
    _emitDebug('purpose_dock_follow_up_group_open');
  }

  void _openInfoDetail(_PurposeDockInfoDetail detail) {
    _feedback();
    setState(() => _infoDetail = detail);
    _resetScrollPosition();
    _emitDebug('purpose_dock_info_detail_open');
  }

  void _goBack() {
    _feedback();
    if (_infoDetail != null) {
      setState(() => _infoDetail = null);
      _resetScrollPosition();
      _emitDebug('purpose_dock_detail_back');
      return;
    }
    if (_group != _PurposeDockGroup.none) {
      setState(() => _group = _PurposeDockGroup.none);
      _resetScrollPosition();
      _emitDebug('purpose_dock_group_back');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.maybeOf(context);
        final textScale = media?.textScaler.scale(1.0) ?? 1.0;
        final reduceMotion = media?.disableAnimations ?? false;
        final metrics = _PurposeDockContentMetrics.resolve(
          height: constraints.maxHeight,
          textScale: textScale,
        );
        _verticalScrollEnabled = metrics.verticalScrollEnabled;
        _viewportHeight = constraints.maxHeight;
        _textScale = textScale;
        _reportScrollModeIfNeeded();

        final content = _buildCurrentContent(context, metrics);
        final switchedContent = AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
          switchInCurve: CommonUiMotion.enter,
          switchOutCurve: CommonUiMotion.exit,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.topCenter,
              children: <Widget>[
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          transitionBuilder: (child, animation) {
            final fade = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(.035, 0),
                  end: Offset.zero,
                ).animate(fade),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<String>(_contentKey()),
            child: content,
          ),
        );

        final contentViewport = metrics.verticalScrollEnabled
            ? Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                interactive: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: metrics.scrollbarContentInset,
                      bottom: metrics.scrollBottomPadding,
                    ),
                    child: switchedContent,
                  ),
                ),
              )
            : switchedContent;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_group == _PurposeDockGroup.none && _infoDetail == null) ...[
              _buildSectionSwitcher(context, metrics),
              SizedBox(height: metrics.contentGap),
            ] else ...[
              _buildBackHeader(context, metrics),
              SizedBox(height: metrics.contentGap),
            ],
            Expanded(
              child: AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                child: KeyedSubtree(
                  key: ValueKey<bool>(metrics.verticalScrollEnabled),
                  child: contentViewport,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _contentKey() {
    if (_infoDetail != null) {
      return 'info_${_infoDetail!.type}_${_infoDetail!.id}';
    }
    if (_group != _PurposeDockGroup.none) {
      return 'group_${_group.name}';
    }
    return _section == _PurposeDockSection.permissions
        ? 'permissions_single_line'
        : 'follow_up_single_line';
  }

  Widget _buildCurrentContent(
    BuildContext context,
    _PurposeDockContentMetrics metrics,
  ) {
    if (_infoDetail != null) {
      return _buildInfoDetail(context, metrics, _infoDetail!);
    }
    if (_group == _PurposeDockGroup.policy) {
      return _buildPolicyGroup(context, metrics);
    }
    if (_group == _PurposeDockGroup.google) {
      return _buildGoogleGroup(context, metrics);
    }
    if (_section == _PurposeDockSection.followUp) {
      return _buildFollowUpOverview(context, metrics);
    }
    return _buildPermissionsOverview(context, metrics);
  }

  Widget _buildSectionSwitcher(
    BuildContext context,
    _PurposeDockContentMetrics metrics,
  ) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return CommonSideDockReveal(
      order: 1,
      offsetY: 5,
      child: Container(
        height: metrics.switcherHeight,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: tokens.surfaceOverlay,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Row(
          children: [
            Expanded(
              child: _PurposeDockSectionButton(
                label: '필요한 설정 ${_permissionSpecs.length}',
                selected: _section == _PurposeDockSection.permissions,
                reduceMotion: reduceMotion,
                onTap: () => _setSection(_PurposeDockSection.permissions),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _PurposeDockSectionButton(
                label: '후속 설정 2',
                selected: _section == _PurposeDockSection.followUp,
                reduceMotion: reduceMotion,
                onTap: () => _setSection(_PurposeDockSection.followUp),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackHeader(
    BuildContext context,
    _PurposeDockContentMetrics metrics,
  ) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final title = _infoDetail?.title ??
        (_group == _PurposeDockGroup.policy
            ? '정책 동의'
            : 'Google 서비스 연결');
    return CommonSideDockReveal(
      order: 1,
      offsetY: 5,
      child: Row(
        children: [
          Material(
            color: tokens.surfaceOverlay,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _goBack,
              child: SizedBox(
                width: metrics.backButtonSize,
                height: metrics.backButtonSize,
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: metrics.backIconSize,
                  color: tokens.iconPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsOverview(
    BuildContext context,
    _PurposeDockContentMetrics metrics,
  ) {
    final specs = _permissionSpecs;
    return CommonSideDockSection(
      title: '필요한 설정 · ${specs.length}단계',
      order: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < specs.length; i++) ...[
            CommonSideDockReveal(
              order: 3 + i,
              offsetY: 4,
              child: CommonSideDockActionTile(
                icon: specs[i].icon,
                title: specs[i].title,
                description: specs[i].description,
                status: '${i + 1}/${specs.length}',
                compact: metrics.compact,
                singleLine: true,
                onTap: () => _openPermissionDetail(
                  specs[i],
                  i,
                  specs.length,
                ),
              ),
            ),
            if (i < specs.length - 1) SizedBox(height: metrics.tileGap),
          ],
        ],
      ),
    );
  }

  Widget _buildFollowUpOverview(
    BuildContext context,
    _PurposeDockContentMetrics metrics,
  ) {
    final tokens = CommonUiTheme.of(context);
    final status = _skipsFollowUp ? '생략' : '';
    return CommonSideDockSection(
      title: '후속 설정 · 2개',
      order: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CommonSideDockReveal(
            order: 3,
            offsetY: 4,
            child: CommonSideDockActionTile(
              icon: Icons.fact_check_outlined,
              title: '정책 동의',
              description: '이용약관, 개인정보처리방침, 계정 삭제 요청 기준을 확인합니다.',
              status: status.isEmpty ? '3단계' : status,
              compact: metrics.compact,
              singleLine: true,
              accentColor: _skipsFollowUp ? tokens.surfaceOverlay : null,
              foregroundColor: _skipsFollowUp ? tokens.iconSecondary : null,
              onTap: () => _openGroup(_PurposeDockGroup.policy),
            ),
          ),
          SizedBox(height: metrics.tileGap),
          CommonSideDockReveal(
            order: 4,
            offsetY: 4,
            child: CommonSideDockActionTile(
              icon: Icons.link_rounded,
              title: 'Google 서비스 연결',
              description: 'Google Calendar, Gmail, Google Cloud Storage 연결 항목을 확인합니다.',
              status: status.isEmpty ? '3개' : status,
              compact: metrics.compact,
              singleLine: true,
              accentColor: _skipsFollowUp ? tokens.surfaceOverlay : null,
              foregroundColor: _skipsFollowUp ? tokens.iconSecondary : null,
              onTap: () => _openGroup(_PurposeDockGroup.google),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyGroup(
    BuildContext context,
    _PurposeDockContentMetrics metrics,
  ) {
    const kinds = <PolicyConsentKind>[
      PolicyConsentKind.termsOfService,
      PolicyConsentKind.privacyPolicy,
      PolicyConsentKind.accountDeletion,
    ];
    final specs = kinds.map(policyDocumentOf).toList(growable: false);
    return _buildInfoTileList(
      context,
      metrics,
      title: '정책 동의 · ${specs.length}단계',
      itemCount: specs.length,
      itemBuilder: (index) {
        final spec = specs[index];
        return CommonSideDockActionTile(
          icon: spec.icon,
          title: spec.title,
          description: spec.subtitle,
          status: _skipsFollowUp ? '생략' : '${spec.step}/${spec.totalSteps}',
          compact: metrics.compact,
          singleLine: true,
          onTap: () => _openInfoDetail(
            _PurposeDockInfoDetail(
              id: spec.kind.name,
              type: 'policy',
              title: spec.title,
              description: spec.subtitle,
              icon: spec.icon,
              meta: _skipsFollowUp
                  ? '이 사용 환경에서는 생략'
                  : '${spec.step} / ${spec.totalSteps} 단계',
            ),
          ),
        );
      },
    );
  }

  Widget _buildGoogleGroup(
    BuildContext context,
    _PurposeDockContentMetrics metrics,
  ) {
    final specs = appStartGoogleServiceSpecs;
    return _buildInfoTileList(
      context,
      metrics,
      title: 'Google 서비스 연결 · ${specs.length}개',
      itemCount: specs.length,
      itemBuilder: (index) {
        final spec = specs[index];
        return CommonSideDockActionTile(
          icon: spec.icon,
          title: spec.title,
          description: spec.description,
          status: _skipsFollowUp ? '생략' : '${index + 1}/${specs.length}',
          compact: metrics.compact,
          singleLine: true,
          onTap: () => _openInfoDetail(
            _PurposeDockInfoDetail(
              id: spec.keyName,
              type: 'google',
              title: spec.title,
              description: spec.description,
              icon: spec.icon,
              meta: _skipsFollowUp ? '이 사용 환경에서는 생략' : spec.detail,
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoTileList(
    BuildContext context,
    _PurposeDockContentMetrics metrics, {
    required String title,
    required int itemCount,
    required Widget Function(int index) itemBuilder,
  }) {
    return CommonSideDockSection(
      title: title,
      order: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < itemCount; i++) ...[
            CommonSideDockReveal(
              order: 3 + i,
              offsetY: 4,
              child: itemBuilder(i),
            ),
            if (i < itemCount - 1) SizedBox(height: metrics.tileGap),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoDetail(
    BuildContext context,
    _PurposeDockContentMetrics metrics,
    _PurposeDockInfoDetail detail,
  ) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return CommonSideDockReveal(
      order: 2,
      offsetY: 6,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(metrics.detailPadding),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: metrics.detailIconBoxSize,
                height: metrics.detailIconBoxSize,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: tokens.shadow,
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(
                  detail.icon,
                  color: tokens.onAccentContainer,
                  size: metrics.detailIconSize,
                ),
              ),
              SizedBox(height: metrics.detailGap),
              Text(
                detail.title,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                detail.description,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                  height: 1.4,
                ),
              ),
              if (detail.meta.trim().isNotEmpty) ...[
                SizedBox(height: metrics.detailGap),
                Divider(height: 1, color: tokens.borderSubtle),
                SizedBox(height: metrics.detailGap),
                Text(
                  detail.meta,
                  textAlign: TextAlign.center,
                  style: textTheme.labelLarge?.copyWith(
                    color: tokens.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PurposeDockSectionButton extends StatelessWidget {
  const _PurposeDockSectionButton({
    required this.label,
    required this.selected,
    required this.reduceMotion,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.standard,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? tokens.accentContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: AnimatedDefaultTextStyle(
            duration:
                reduceMotion ? Duration.zero : CommonUiMotion.selection,
            curve: CommonUiMotion.standard,
            style: textTheme.labelLarge?.copyWith(
                  color: selected
                      ? tokens.onAccentContainer
                      : tokens.textSecondary,
                  fontWeight: FontWeight.w800,
                ) ??
                const TextStyle(),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

class _PurposeDockContentMetrics {
  const _PurposeDockContentMetrics({
    required this.compact,
    required this.verticalScrollEnabled,
    required this.switcherHeight,
    required this.contentGap,
    required this.tileGap,
    required this.backButtonSize,
    required this.backIconSize,
    required this.detailPadding,
    required this.detailIconBoxSize,
    required this.detailIconSize,
    required this.detailGap,
    required this.scrollbarContentInset,
    required this.scrollBottomPadding,
  });

  factory _PurposeDockContentMetrics.resolve({
    required double height,
    required double textScale,
  }) {
    final compact = height < 520 || textScale >= 1.30;
    final verticalScrollEnabled = height < 500 || textScale >= 1.35;
    if (compact) {
      return _PurposeDockContentMetrics(
        compact: true,
        verticalScrollEnabled: verticalScrollEnabled,
        switcherHeight: 38,
        contentGap: 6,
        tileGap: 3,
        backButtonSize: 34,
        backIconSize: 19,
        detailPadding: 13,
        detailIconBoxSize: 46,
        detailIconSize: 23,
        detailGap: 9,
        scrollbarContentInset: verticalScrollEnabled ? 8 : 0,
        scrollBottomPadding: verticalScrollEnabled ? 8 : 0,
      );
    }
    return _PurposeDockContentMetrics(
      compact: false,
      verticalScrollEnabled: verticalScrollEnabled,
      switcherHeight: 42,
      contentGap: 8,
      tileGap: 5,
      backButtonSize: 38,
      backIconSize: 21,
      detailPadding: 17,
      detailIconBoxSize: 54,
      detailIconSize: 27,
      detailGap: 12,
      scrollbarContentInset: verticalScrollEnabled ? 8 : 0,
      scrollBottomPadding: verticalScrollEnabled ? 10 : 0,
    );
  }

  final bool compact;
  final bool verticalScrollEnabled;
  final double switcherHeight;
  final double contentGap;
  final double tileGap;
  final double backButtonSize;
  final double backIconSize;
  final double detailPadding;
  final double detailIconBoxSize;
  final double detailIconSize;
  final double detailGap;
  final double scrollbarContentInset;
  final double scrollBottomPadding;
}

class _PurposeSectionEntrance extends StatelessWidget {
  const _PurposeSectionEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: CommonUiMotion.layout,
      curve: CommonUiMotion.enter,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _PurposeLayoutMetrics {
  const _PurposeLayoutMetrics({
    required this.compact,
    required this.ultra,
    required this.showDescriptions,
    required this.showHeaderDescription,
    required this.topPadding,
    required this.bottomPadding,
    required this.sectionGap,
    required this.headerTextGap,
    required this.rowHorizontalPadding,
    required this.rowVerticalPadding,
    required this.iconBoxSize,
    required this.iconSize,
    required this.iconRadius,
    required this.leadingGap,
    required this.descriptionGap,
    required this.trailingGap,
    required this.indicatorGap,
    required this.indicatorSize,
    required this.railInset,
  });

  factory _PurposeLayoutMetrics.resolve({
    required double height,
    required double textScale,
  }) {
    final ultra = height < 470 || textScale >= 1.55;
    final compact = ultra || height < 560 || textScale >= 1.25;

    if (ultra) {
      return const _PurposeLayoutMetrics(
        compact: true,
        ultra: true,
        showDescriptions: false,
        showHeaderDescription: false,
        topPadding: 8,
        bottomPadding: 8,
        sectionGap: 10,
        headerTextGap: 4,
        rowHorizontalPadding: 10,
        rowVerticalPadding: 7,
        iconBoxSize: 34,
        iconSize: 18,
        iconRadius: 10,
        leadingGap: 9,
        descriptionGap: 2,
        trailingGap: 7,
        indicatorGap: 7,
        indicatorSize: 23,
        railInset: 7,
      );
    }

    if (compact) {
      return const _PurposeLayoutMetrics(
        compact: true,
        ultra: false,
        showDescriptions: true,
        showHeaderDescription: true,
        topPadding: 10,
        bottomPadding: 10,
        sectionGap: 12,
        headerTextGap: 5,
        rowHorizontalPadding: 12,
        rowVerticalPadding: 9,
        iconBoxSize: 36,
        iconSize: 19,
        iconRadius: 11,
        leadingGap: 10,
        descriptionGap: 2,
        trailingGap: 8,
        indicatorGap: 8,
        indicatorSize: 24,
        railInset: 8,
      );
    }

    return const _PurposeLayoutMetrics(
      compact: false,
      ultra: false,
      showDescriptions: true,
      showHeaderDescription: true,
      topPadding: 18,
      bottomPadding: 18,
      sectionGap: 18,
      headerTextGap: 7,
      rowHorizontalPadding: 15,
      rowVerticalPadding: 12,
      iconBoxSize: 42,
      iconSize: 22,
      iconRadius: 13,
      leadingGap: 13,
      descriptionGap: 3,
      trailingGap: 10,
      indicatorGap: 10,
      indicatorSize: 27,
      railInset: 9,
    );
  }

  final bool compact;
  final bool ultra;
  final bool showDescriptions;
  final bool showHeaderDescription;
  final double topPadding;
  final double bottomPadding;
  final double sectionGap;
  final double headerTextGap;
  final double rowHorizontalPadding;
  final double rowVerticalPadding;
  final double iconBoxSize;
  final double iconSize;
  final double iconRadius;
  final double leadingGap;
  final double descriptionGap;
  final double trailingGap;
  final double indicatorGap;
  final double indicatorSize;
  final double railInset;
}

