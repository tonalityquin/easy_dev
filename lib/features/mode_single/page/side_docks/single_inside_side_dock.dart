import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/utils/side_dock_action_catalog.dart';
import '../../application/single_inside_diagnostics.dart';

enum SingleInsideDockRequest {
  workSchedule,
  parkingArea,
  workRules,
  workManual,
  workStartReport,
  workEndReport,
  commuteSubmit,
  restTimeSubmit,
  statementForm,
  leaveApplication,
  faq,
  update,
  terms,
  privacy,
  operations,
  operationalSync,
  theme,
  logout,
  exitApp,
}

enum SingleInsideDashboardActionSection {
  work,
  report,
  submit,
  form,
  support,
  settings,
}

class SingleInsideDashboardActionSpec {
  const SingleInsideDashboardActionSpec({
    required this.request,
    required this.section,
    required this.icon,
    required this.label,
    required this.compactLabel,
  });

  final SingleInsideDockRequest request;
  final SingleInsideDashboardActionSection section;
  final IconData icon;
  final String label;
  final String compactLabel;
}

List<SingleInsideDashboardActionSpec> singleInsideDashboardActionSpecs({
  required bool showReport,
  required bool showOperations,
}) {
  return <SingleInsideDashboardActionSpec>[
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.workSchedule,
      section: SingleInsideDashboardActionSection.work,
      icon: Icons.calendar_month_rounded,
      label: '근무 일정',
      compactLabel: '일정',
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.parkingArea,
      section: SingleInsideDashboardActionSection.work,
      icon: Icons.local_parking_rounded,
      label: '주차 구역',
      compactLabel: '주차',
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.workRules,
      section: SingleInsideDashboardActionSection.work,
      icon: Icons.rule_rounded,
      label: '업무 규칙',
      compactLabel: '규칙',
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.workManual,
      section: SingleInsideDashboardActionSection.work,
      icon: Icons.menu_book_rounded,
      label: '업무 메뉴얼',
      compactLabel: '메뉴얼',
    ),
    if (showReport) ...[
      const SingleInsideDashboardActionSpec(
        request: SingleInsideDockRequest.workStartReport,
        section: SingleInsideDashboardActionSection.report,
        icon: SideDockActionCatalog.workStartReportIcon,
        label: SideDockActionCatalog.workStartReportLabel,
        compactLabel: '시작',
      ),
      const SingleInsideDashboardActionSpec(
        request: SingleInsideDockRequest.workEndReport,
        section: SingleInsideDashboardActionSection.report,
        icon: SideDockActionCatalog.workEndReportIcon,
        label: SideDockActionCatalog.workEndReportLabel,
        compactLabel: '종료',
      ),
    ],
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.commuteSubmit,
      section: SingleInsideDashboardActionSection.submit,
      icon: SideDockActionCatalog.commuteSubmitIcon,
      label: SideDockActionCatalog.commuteSubmitLabel,
      compactLabel: '출퇴근',
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.restTimeSubmit,
      section: SingleInsideDashboardActionSection.submit,
      icon: SideDockActionCatalog.restTimeSubmitIcon,
      label: SideDockActionCatalog.restTimeSubmitLabel,
      compactLabel: '휴게',
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.statementForm,
      section: SingleInsideDashboardActionSection.form,
      icon: SideDockActionCatalog.statementFormIcon,
      label: SideDockActionCatalog.statementFormLabel,
      compactLabel: '경위서',
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.leaveApplication,
      section: SingleInsideDashboardActionSection.form,
      icon: SideDockActionCatalog.leaveApplicationIcon,
      label: SideDockActionCatalog.leaveApplicationLabel,
      compactLabel: '연차',
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.faq,
      section: SingleInsideDashboardActionSection.support,
      icon: SideDockActionCatalog.faqIcon,
      label: SideDockActionCatalog.faqLabel,
      compactLabel: 'FAQ',
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.update,
      section: SingleInsideDashboardActionSection.support,
      icon: SideDockActionCatalog.updateIcon,
      label: SideDockActionCatalog.updateLabel,
      compactLabel: '업데이트',
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.terms,
      section: SingleInsideDashboardActionSection.support,
      icon: SideDockActionCatalog.termsIcon,
      label: SideDockActionCatalog.termsLabel,
      compactLabel: '약관',
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.privacy,
      section: SingleInsideDashboardActionSection.support,
      icon: SideDockActionCatalog.privacyIcon,
      label: SideDockActionCatalog.privacyLabel,
      compactLabel: '개인정보',
    ),
    if (showOperations)
      const SingleInsideDashboardActionSpec(
        request: SingleInsideDockRequest.operations,
        section: SingleInsideDashboardActionSection.settings,
        icon: SideDockActionCatalog.operationsIcon,
        label: SideDockActionCatalog.operationsLabel,
        compactLabel: '운영',
      ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.operationalSync,
      section: SingleInsideDashboardActionSection.settings,
      icon: SideDockActionCatalog.operationalSyncIcon,
      label: SideDockActionCatalog.operationalSyncLabel,
      compactLabel: '동기화',
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.theme,
      section: SingleInsideDashboardActionSection.settings,
      icon: Icons.palette_outlined,
      label: '테마',
      compactLabel: '테마',
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.logout,
      section: SingleInsideDashboardActionSection.settings,
      icon: SideDockActionCatalog.logoutIcon,
      label: SideDockActionCatalog.logoutLabel,
      compactLabel: '로그아웃',
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.exitApp,
      section: SingleInsideDashboardActionSection.settings,
      icon: Icons.power_settings_new_rounded,
      label: '앱 종료',
      compactLabel: '앱종료',
    ),
  ];
}

typedef SingleInsideDashboardRequestHandler = Future<void> Function(
  SingleInsideDockRequest request,
  String source,
);

class SingleInsideDashboardRail extends StatelessWidget {
  const SingleInsideDashboardRail({
    super.key,
    required this.width,
    required this.showReport,
    required this.showOperations,
    required this.enabled,
    required this.onDeveloperStatus,
    required this.onRequest,
    required this.selectedRequest,
  });

  final double width;
  final bool showReport;
  final bool showOperations;
  final bool enabled;
  final Future<void> Function() onDeveloperStatus;
  final SingleInsideDashboardRequestHandler onRequest;
  final SingleInsideDockRequest? selectedRequest;

  Future<void> _request(SingleInsideDockRequest request) async {
    if (!enabled) return;
    await onRequest(request, 'compact_rail');
  }

  Color _foreground(
    CommonUiTokens tokens,
    SingleInsideDockRequest request,
  ) {
    switch (request) {
      case SingleInsideDockRequest.workSchedule:
      case SingleInsideDockRequest.parkingArea:
      case SingleInsideDockRequest.workRules:
        return tokens.accent;
      case SingleInsideDockRequest.workManual:
        return tokens.info;
      case SingleInsideDockRequest.workStartReport:
      case SingleInsideDockRequest.commuteSubmit:
      case SingleInsideDockRequest.operationalSync:
      case SingleInsideDockRequest.faq:
      case SingleInsideDockRequest.privacy:
        return tokens.info;
      case SingleInsideDockRequest.update:
      case SingleInsideDockRequest.theme:
        return tokens.accent;
      case SingleInsideDockRequest.terms:
        return tokens.textSecondary;
      case SingleInsideDockRequest.workEndReport:
      case SingleInsideDockRequest.restTimeSubmit:
      case SingleInsideDockRequest.leaveApplication:
      case SingleInsideDockRequest.operations:
        return tokens.success;
      case SingleInsideDockRequest.statementForm:
        return tokens.warning;
      case SingleInsideDockRequest.logout:
      case SingleInsideDockRequest.exitApp:
        return tokens.danger;
    }
  }

  String _sectionTitle(SingleInsideDashboardActionSection section) {
    switch (section) {
      case SingleInsideDashboardActionSection.work:
        return '근무';
      case SingleInsideDashboardActionSection.report:
        return SideDockActionCatalog.sectionReport;
      case SingleInsideDashboardActionSection.submit:
        return SideDockActionCatalog.sectionSubmit;
      case SingleInsideDashboardActionSection.form:
        return SideDockActionCatalog.sectionForm;
      case SingleInsideDashboardActionSection.support:
        return SideDockActionCatalog.sectionSupport;
      case SingleInsideDashboardActionSection.settings:
        return SideDockActionCatalog.sectionSettings;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final media = MediaQuery.maybeOf(context);
    final compact = (media?.size.height ?? 720) < 680 ||
        (media?.textScaler.scale(1.0) ?? 1.0) >= 1.18;
    final extent = compact ? 46.0 : 50.0;
    final gap = compact ? 3.0 : 5.0;
    final actions = singleInsideDashboardActionSpecs(
      showReport: showReport,
      showOperations: showOperations,
    );
    final sections = <SingleInsideDashboardActionSection>[
      SingleInsideDashboardActionSection.work,
      if (showReport) SingleInsideDashboardActionSection.report,
      SingleInsideDashboardActionSection.submit,
      SingleInsideDashboardActionSection.form,
      SingleInsideDashboardActionSection.support,
      SingleInsideDashboardActionSection.settings,
    ];
    final children = <Widget>[];
    for (var sectionIndex = 0;
        sectionIndex < sections.length;
        sectionIndex++) {
      final section = sections[sectionIndex];
      if (sectionIndex > 0) {
        children.add(SizedBox(height: compact ? 5 : 7));
      }
      children.add(
        _DashboardRailSectionHeader(
          title: _sectionTitle(section),
          onLongPress: section == SingleInsideDashboardActionSection.settings
              ? onDeveloperStatus
              : null,
        ),
      );
      children.add(SizedBox(height: compact ? 2 : 3));
      final sectionActions = actions
          .where((action) => action.section == section)
          .toList(growable: false);
      for (var i = 0; i < sectionActions.length; i++) {
        if (i > 0) children.add(SizedBox(height: gap));
        final action = sectionActions[i];
        final button = _DashboardRailIconButton(
          semanticLabel: action.label,
          compactLabel: action.compactLabel,
          icon: action.icon,
          foreground: _foreground(tokens, action.request),
          extent: extent,
          enabled: enabled,
          selected: action.request == selectedRequest,
          onTap: () => _request(action.request),
        );
        children.add(button);
      }
    }
    return Semantics(
      container: true,
      label: '싱글 대시보드 빠른 실행',
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border(left: BorderSide(color: tokens.borderSubtle)),
        ),
        padding: EdgeInsets.fromLTRB(
          compact ? 3 : 4,
          compact ? 5 : 7,
          compact ? 3 : 4,
          compact ? 5 : 7,
        ),
        child: _DashboardRailScrollViewport(
          compact: compact,
          children: children,
        ),
      ),
    );
  }
}


class _DashboardRailScrollViewport extends StatefulWidget {
  const _DashboardRailScrollViewport({
    required this.compact,
    required this.children,
  });

  final bool compact;
  final List<Widget> children;

  @override
  State<_DashboardRailScrollViewport> createState() =>
      _DashboardRailScrollViewportState();
}

class _DashboardRailScrollViewportState
    extends State<_DashboardRailScrollViewport> {
  late final ScrollController _controller;
  bool _scrollable = false;
  bool _canScrollUp = false;
  bool _canScrollDown = false;
  bool _scrolling = false;
  double _offset = 0;
  double _maxScrollExtent = 0;
  double _viewportDimension = 0;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncMetrics());
  }

  @override
  void didUpdateWidget(covariant _DashboardRailScrollViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncMetrics());
  }

  void _handleScroll() {
    _syncMetrics();
  }

  void _syncMetrics() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final offset = position.pixels.clamp(0.0, position.maxScrollExtent).toDouble();
    final maxExtent = position.maxScrollExtent.clamp(0.0, double.infinity).toDouble();
    final viewport = position.viewportDimension.clamp(0.0, double.infinity).toDouble();
    final scrollable = maxExtent > 1;
    final canScrollUp = scrollable && offset > 1;
    final canScrollDown = scrollable && offset < maxExtent - 1;
    final stateChanged = scrollable != _scrollable ||
        canScrollUp != _canScrollUp ||
        canScrollDown != _canScrollDown;
    final metricsChanged = (_maxScrollExtent - maxExtent).abs() > .5 ||
        (_viewportDimension - viewport).abs() > .5;
    if (!stateChanged && !metricsChanged && (_offset - offset).abs() < .5) {
      return;
    }
    final previousScrollable = _scrollable;
    setState(() {
      _scrollable = scrollable;
      _canScrollUp = canScrollUp;
      _canScrollDown = canScrollDown;
      _offset = offset;
      _maxScrollExtent = maxExtent;
      _viewportDimension = viewport;
    });
    if (previousScrollable != scrollable || metricsChanged) {
      SingleInsideDiagnostics.log(
        'dashboard',
        'rail_scroll_metrics scrollable=$scrollable offset=${offset.toStringAsFixed(1)} max=${maxExtent.toStringAsFixed(1)} viewport=${viewport.toStringAsFixed(1)} compact=${widget.compact} compactLabelNoWrap=true compactLabelFit=scaleDown',
      );
    }
  }

  bool _handleNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification && !_scrolling) {
      setState(() => _scrolling = true);
      SingleInsideDiagnostics.log(
        'dashboard',
        'rail_scroll_start offset=${_offset.toStringAsFixed(1)} max=${_maxScrollExtent.toStringAsFixed(1)}',
      );
    } else if (notification is ScrollEndNotification) {
      _syncMetrics();
      if (_scrolling && mounted) {
        setState(() => _scrolling = false);
      }
      SingleInsideDiagnostics.log(
        'dashboard',
        'rail_scroll_end offset=${_offset.toStringAsFixed(1)} max=${_maxScrollExtent.toStringAsFixed(1)} canUp=$_canScrollUp canDown=$_canScrollDown',
      );
    }
    return false;
  }

  @override
  void dispose() {
    _controller.removeListener(_handleScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : CommonUiMotion.selection;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : _viewportDimension;
        final viewport = _viewportDimension > 0 ? _viewportDimension : height;
        final contentExtent = viewport + _maxScrollExtent;
        final minThumb = widget.compact ? 22.0 : 24.0;
        final rawThumbHeight = contentExtent > 0 && viewport > 0
            ? viewport * viewport / contentExtent
            : viewport;
        final safeMinThumb = viewport > 0
            ? minThumb.clamp(0.0, viewport).toDouble()
            : 0.0;
        final thumbHeight = viewport > 0
            ? rawThumbHeight.clamp(safeMinThumb, viewport).toDouble()
            : 0.0;
        final thumbTravel = (viewport - thumbHeight).clamp(0.0, double.infinity).toDouble();
        final thumbTop = _maxScrollExtent > 0
            ? (_offset / _maxScrollExtent).clamp(0.0, 1.0) * thumbTravel
            : 0.0;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _handleNotification,
              child: ListView(
                controller: _controller,
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.zero,
                children: widget.children,
              ),
            ),
            if (_scrollable)
              AnimatedPositioned(
                duration: _scrolling ? Duration.zero : duration,
                curve: Curves.easeOutCubic,
                left: 0,
                top: thumbTop,
                width: 2,
                height: thumbHeight,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: duration,
                    opacity: _scrolling ? .95 : .58,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.textSecondary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            _DashboardRailContinuationCue(
              visible: _canScrollUp,
              top: true,
              compact: widget.compact,
            ),
            _DashboardRailContinuationCue(
              visible: _canScrollDown,
              top: false,
              compact: widget.compact,
            ),
          ],
        );
      },
    );
  }
}

class _DashboardRailContinuationCue extends StatelessWidget {
  const _DashboardRailContinuationCue({
    required this.visible,
    required this.top,
    required this.compact,
  });

  final bool visible;
  final bool top;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final height = compact ? 22.0 : 24.0;
    final cue = IgnorePointer(
      child: AnimatedOpacity(
        duration: duration,
        curve: Curves.easeOutCubic,
        opacity: visible ? 1 : 0,
        child: AnimatedSlide(
          duration: duration,
          curve: Curves.easeOutCubic,
          offset: visible
              ? Offset.zero
              : Offset(0, top ? -.12 : .12),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: [
                  tokens.surface,
                  tokens.surface.withOpacity(.88),
                  tokens.surface.withOpacity(0),
                ],
              ),
            ),
            alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
            child: Icon(
              top
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: compact ? 14 : 15,
              color: tokens.textSecondary,
            ),
          ),
        ),
      ),
    );
    return Positioned(
      left: 0,
      right: 0,
      top: top ? 0 : null,
      bottom: top ? null : 0,
      child: cue,
    );
  }
}

class _DashboardRailSectionHeader extends StatelessWidget {
  const _DashboardRailSectionHeader({
    required this.title,
    this.onLongPress,
  });

  final String title;
  final Future<void> Function()? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final child = Container(
      height: 22,
      alignment: Alignment.center,
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.clip,
        textAlign: TextAlign.center,
        style: text.labelSmall?.copyWith(
          color: tokens.textSecondary,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: .15,
        ),
      ),
    );
    if (onLongPress == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () async {
        await HapticFeedback.mediumImpact();
        SingleInsideDiagnostics.log(
          'status',
          'developer_status_request source=compact_rail_section_header section=$title',
        );
        await onLongPress?.call();
      },
      child: child,
    );
  }
}

class _DashboardRailIconButton extends StatefulWidget {
  const _DashboardRailIconButton({
    required this.semanticLabel,
    required this.compactLabel,
    required this.icon,
    required this.foreground,
    required this.extent,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  final String semanticLabel;
  final String compactLabel;
  final IconData icon;
  final Color foreground;
  final double extent;
  final bool enabled;
  final bool selected;
  final Future<void> Function() onTap;

  @override
  State<_DashboardRailIconButton> createState() =>
      _DashboardRailIconButtonState();
}

class _DashboardRailIconButtonState extends State<_DashboardRailIconButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _labelController;
  late final Animation<double> _labelOpacity;
  late final Animation<Offset> _labelSlide;
  OverlayEntry? _labelEntry;
  Timer? _labelTimer;

  @override
  void initState() {
    super.initState();
    _labelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 170),
      reverseDuration: const Duration(milliseconds: 130),
    );
    final curve = CurvedAnimation(
      parent: _labelController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _labelOpacity = curve;
    _labelSlide = Tween<Offset>(
      begin: const Offset(.12, 0),
      end: Offset.zero,
    ).animate(curve);
  }

  Future<void> _hideLabel() async {
    _labelTimer?.cancel();
    _labelTimer = null;
    final entry = _labelEntry;
    if (entry == null) return;
    if (!(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      await _labelController.reverse();
    }
    if (_labelEntry == entry) {
      entry.remove();
      _labelEntry = null;
    }
  }

  Future<void> _showLabel() async {
    if (!widget.enabled || !mounted) return;
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    await _hideLabel();
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final box = context.findRenderObject() as RenderBox?;
    if (overlay == null || box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    final screenSize = MediaQuery.sizeOf(context);
    final tokens = CommonUiTheme.of(context);
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w900,
        );
    final right = (screenSize.width - origin.dx + 8)
        .clamp(8.0, screenSize.width - 8.0)
        .toDouble();
    final top = (origin.dy + (size.height - 36) / 2)
        .clamp(8.0, screenSize.height - 44.0)
        .toDouble();
    final entry = OverlayEntry(
      builder: (_) {
        return Positioned(
          right: right,
          top: top,
          child: IgnorePointer(
            child: FadeTransition(
              opacity: _labelOpacity,
              child: SlideTransition(
                position: _labelSlide,
                child: Material(
                  color: tokens.transparent,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.surfaceRaised,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: tokens.borderSubtle),
                      boxShadow: [
                        BoxShadow(
                          color: tokens.shadow.withOpacity(.18),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.semanticLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    _labelEntry = entry;
    overlay.insert(entry);
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _labelController.value = 1;
    } else {
      await _labelController.forward(from: 0);
    }
    SingleInsideDiagnostics.log(
      'dashboard',
      'rail_label_reveal label=${widget.semanticLabel}',
    );
    _labelTimer = Timer(
      const Duration(milliseconds: 1350),
      () => unawaited(_hideLabel()),
    );
  }

  @override
  void dispose() {
    _labelTimer?.cancel();
    _labelEntry?.remove();
    _labelEntry = null;
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = widget.enabled;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      excludeSemantics: true,
      label: widget.semanticLabel,
      child: AnimatedOpacity(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        opacity: enabled ? 1 : .42,
        child: AnimatedScale(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          scale: _pressed && enabled ? .95 : 1,
          child: Material(
            color: tokens.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: enabled ? () => unawaited(widget.onTap()) : null,
              onLongPress: enabled ? () => unawaited(_showLabel()) : null,
              onHighlightChanged: (value) {
                if (!mounted) return;
                setState(() => _pressed = enabled && value);
              },
              child: AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: double.infinity,
                height: widget.extent,
                decoration: BoxDecoration(
                  color: widget.selected
                      ? tokens.accentContainer
                      : _pressed
                          ? tokens.surfaceSelected
                          : tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.selected || _pressed
                        ? tokens.accent
                        : tokens.borderSubtle,
                  ),
                ),
                alignment: Alignment.center,
                child: AnimatedScale(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  scale: _pressed && enabled ? 1.06 : 1,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.icon,
                        size: 19,
                        color: enabled
                            ? widget.selected
                                ? tokens.accent
                                : widget.foreground
                            : tokens.iconDisabled,
                      ),
                      const SizedBox(height: 1),
                      AnimatedDefaultTextStyle(
                        duration: reduceMotion
                            ? Duration.zero
                            : CommonUiMotion.selection,
                        curve: Curves.easeOutCubic,
                        style: (Theme.of(context).textTheme.labelSmall ??
                                const TextStyle())
                            .copyWith(
                          color: enabled
                              ? widget.selected
                                  ? tokens.accent
                                  : tokens.textSecondary
                              : tokens.textDisabled,
                          fontSize: 9,
                          fontWeight: widget.selected
                              ? FontWeight.w900
                              : FontWeight.w800,
                          height: 1,
                          letterSpacing: -.15,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          height: 10,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: Text(
                              widget.compactLabel,
                              maxLines: 1,
                              softWrap: false,
                              textAlign: TextAlign.center,
                            ),
                          ),
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
