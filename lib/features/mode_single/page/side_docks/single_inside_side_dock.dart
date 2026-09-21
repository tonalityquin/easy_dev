import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/utils/side_dock_action_catalog.dart';
import '../../application/single_inside_diagnostics.dart';

enum SingleInsideDockRequest {
  workSchedule,
  punchRecorder,
  workStartReport,
  workEndReport,
  commuteSubmit,
  restTimeSubmit,
  statementForm,
  leaveApplication,
  operations,
  operationalSync,
  logout,
  exitApp,
}

enum SingleInsideDashboardActionSection {
  work,
  report,
  submit,
  form,
  settings,
}

class SingleInsideDashboardActionSpec {
  const SingleInsideDashboardActionSpec({
    required this.request,
    required this.section,
    required this.icon,
    required this.label,
  });

  final SingleInsideDockRequest request;
  final SingleInsideDashboardActionSection section;
  final IconData icon;
  final String label;
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
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.punchRecorder,
      section: SingleInsideDashboardActionSection.work,
      icon: Icons.access_time_rounded,
      label: '출퇴근 기록기',
    ),
    if (showReport) ...[
      const SingleInsideDashboardActionSpec(
        request: SingleInsideDockRequest.workStartReport,
        section: SingleInsideDashboardActionSection.report,
        icon: SideDockActionCatalog.workStartReportIcon,
        label: SideDockActionCatalog.workStartReportLabel,
      ),
      const SingleInsideDashboardActionSpec(
        request: SingleInsideDockRequest.workEndReport,
        section: SingleInsideDashboardActionSection.report,
        icon: SideDockActionCatalog.workEndReportIcon,
        label: SideDockActionCatalog.workEndReportLabel,
      ),
    ],
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.commuteSubmit,
      section: SingleInsideDashboardActionSection.submit,
      icon: SideDockActionCatalog.commuteSubmitIcon,
      label: SideDockActionCatalog.commuteSubmitLabel,
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.restTimeSubmit,
      section: SingleInsideDashboardActionSection.submit,
      icon: SideDockActionCatalog.restTimeSubmitIcon,
      label: SideDockActionCatalog.restTimeSubmitLabel,
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.statementForm,
      section: SingleInsideDashboardActionSection.form,
      icon: SideDockActionCatalog.statementFormIcon,
      label: SideDockActionCatalog.statementFormLabel,
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.leaveApplication,
      section: SingleInsideDashboardActionSection.form,
      icon: SideDockActionCatalog.leaveApplicationIcon,
      label: SideDockActionCatalog.leaveApplicationLabel,
    ),
    if (showOperations)
      const SingleInsideDashboardActionSpec(
        request: SingleInsideDockRequest.operations,
        section: SingleInsideDashboardActionSection.settings,
        icon: SideDockActionCatalog.operationsIcon,
        label: SideDockActionCatalog.operationsLabel,
      ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.operationalSync,
      section: SingleInsideDashboardActionSection.settings,
      icon: SideDockActionCatalog.operationalSyncIcon,
      label: SideDockActionCatalog.operationalSyncLabel,
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.logout,
      section: SingleInsideDashboardActionSection.settings,
      icon: SideDockActionCatalog.logoutIcon,
      label: SideDockActionCatalog.logoutLabel,
    ),
    const SingleInsideDashboardActionSpec(
      request: SingleInsideDockRequest.exitApp,
      section: SingleInsideDashboardActionSection.settings,
      icon: Icons.power_settings_new_rounded,
      label: '앱 종료',
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
    required this.onManualInteraction,
    required this.onRequest,
    required this.workScheduleSelected,
    required this.punchRecorderSelected,
  });

  final double width;
  final bool showReport;
  final bool showOperations;
  final bool enabled;
  final Future<void> Function() onDeveloperStatus;
  final ValueChanged<String> onManualInteraction;
  final SingleInsideDashboardRequestHandler onRequest;
  final bool workScheduleSelected;
  final bool punchRecorderSelected;

  Future<void> _request(SingleInsideDockRequest request) async {
    if (!enabled) return;
    onManualInteraction('dashboard_action_${request.name}');
    await onRequest(request, 'compact_rail');
  }

  Color _foreground(
    CommonUiTokens tokens,
    SingleInsideDockRequest request,
  ) {
    switch (request) {
      case SingleInsideDockRequest.workSchedule:
      case SingleInsideDockRequest.punchRecorder:
        return tokens.accent;
      case SingleInsideDockRequest.workStartReport:
      case SingleInsideDockRequest.commuteSubmit:
      case SingleInsideDockRequest.operationalSync:
        return tokens.info;
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
    final extent = compact ? 42.0 : 46.0;
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
          icon: action.icon,
          foreground: _foreground(tokens, action.request),
          extent: extent,
          enabled: enabled,
          selected: action.request == SingleInsideDockRequest.workSchedule
              ? workScheduleSelected
              : action.request == SingleInsideDockRequest.punchRecorder
                  ? punchRecorderSelected
                  : false,
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
        child: ListView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.zero,
          children: children,
        ),
      ),
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
    required this.icon,
    required this.foreground,
    required this.extent,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  final String semanticLabel;
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
                  child: Icon(
                    widget.icon,
                    size: 21,
                    color: enabled
                        ? widget.selected
                            ? tokens.accent
                            : widget.foreground
                        : tokens.iconDisabled,
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
