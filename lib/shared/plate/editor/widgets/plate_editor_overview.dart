import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';

const double _plateEditorOverviewRowHeight = 72;

enum PlateEditorSectionStatus {
  none,
  changed,
  complete,
  incomplete,
  pending,
  loading,
  error,
}

class PlateEditorOverview extends StatelessWidget {
  const PlateEditorOverview({
    super.key,
    required this.title,
    this.subtitle,
    required this.sections,
  });

  final String title;
  final String? subtitle;
  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.view_list_rounded,
                color: tokens.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    if (subtitle?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!.trim(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                              height: 1.3,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _PlateEditorListSurface(
            child: ListView.separated(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: sections.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                thickness: 1,
                color: tokens.borderSubtle,
              ),
              itemBuilder: (_, index) => sections[index],
            ),
          ),
        ),
      ],
    );
  }
}

class PlateEditorOverviewSection extends StatelessWidget {
  const PlateEditorOverviewSection({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.status = PlateEditorSectionStatus.none,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  final PlateEditorSectionStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final statusLabel = _statusLabel(status);
    final statusColor = _statusColor(tokens, status);

    return Semantics(
      button: true,
      label: [
        title,
        value,
        if (statusLabel != null) statusLabel,
      ].join(', '),
      child: SizedBox(
        height: _plateEditorOverviewRowHeight,
        child: _PlateEditorActionRowSurface(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _PlateEditorStatusDot(status: status),
                  const SizedBox(width: 8),
                  Icon(
                    icon,
                    color: tokens.iconSecondary,
                    size: 19,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  if (statusLabel != null) ...[
                    const SizedBox(width: 6),
                    AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: CommonUiMotion.enter,
                      switchOutCurve: CommonUiMotion.exit,
                      child: Text(
                        statusLabel,
                        key: ValueKey<String>(statusLabel),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: tokens.iconSecondary,
                    size: 19,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              AnimatedSwitcher(
                duration: duration,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                child: Text(
                  value,
                  key: ValueKey<String>(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                        height: 1.3,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlateEditorVehicleIdentitySection extends StatelessWidget {
  const PlateEditorVehicleIdentitySection({
    super.key,
    required this.region,
    required this.plate,
    required this.onRegionTap,
    required this.onPlateTap,
    this.regionStatus = PlateEditorSectionStatus.none,
    this.plateStatus = PlateEditorSectionStatus.none,
    this.plateAnchorKey,
  });

  final String region;
  final String plate;
  final VoidCallback onRegionTap;
  final VoidCallback? onPlateTap;
  final PlateEditorSectionStatus regionStatus;
  final PlateEditorSectionStatus plateStatus;
  final Key? plateAnchorKey;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return SizedBox(
      height: _plateEditorOverviewRowHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 10, 13, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.badge_rounded,
                  color: tokens.iconSecondary,
                  size: 19,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '차량 정보',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 3,
                  child: _PlateEditorSplitActionSurface(
                    label: '등록 지역',
                    value: region.trim(),
                    status: regionStatus,
                    onTap: onRegionTap,
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  flex: 7,
                  child: _PlateEditorSplitActionSurface(
                    key: plateAnchorKey,
                    label: '번호판',
                    value: plate.trim(),
                    status: plateStatus,
                    onTap: onPlateTap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlateEditorSplitActionSurface extends StatefulWidget {
  const _PlateEditorSplitActionSurface({
    super.key,
    required this.label,
    required this.value,
    required this.status,
    required this.onTap,
  });

  final String label;
  final String value;
  final PlateEditorSectionStatus status;
  final VoidCallback? onTap;

  @override
  State<_PlateEditorSplitActionSurface> createState() =>
      _PlateEditorSplitActionSurfaceState();
}

class _PlateEditorSplitActionSurfaceState
    extends State<_PlateEditorSplitActionSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.press;
    final statusLabel = _statusLabel(widget.status);

    return Semantics(
      button: widget.onTap != null,
      label: [
        widget.label,
        widget.value.trim().isEmpty ? '미입력' : widget.value,
        if (statusLabel != null) statusLabel,
      ].join(', '),
      child: AnimatedScale(
        duration: duration,
        curve: CommonUiMotion.enter,
        scale: _pressed ? .98 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            onTap: widget.onTap,
            onHighlightChanged: widget.onTap == null
                ? null
                : (value) {
                    if (!mounted) return;
                    setState(() => _pressed = value);
                  },
            child: AnimatedContainer(
              duration: duration,
              curve: CommonUiMotion.standard,
              constraints: const BoxConstraints(minHeight: 20),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: _pressed
                    ? tokens.surfaceSelected.withOpacity(.58)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(color: Colors.transparent),
              ),
              alignment: Alignment.centerLeft,
              child: AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : CommonUiMotion.selection,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                child: SizedBox(
                  key: ValueKey<String>(widget.value),
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.value,
                      maxLines: 1,
                      softWrap: false,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w900,
                            height: 1.3,
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

class PlateEditorOverviewPhotoSection extends StatelessWidget {
  const PlateEditorOverviewPhotoSection({
    super.key,
    required this.summary,
    required this.onTap,
    this.status = PlateEditorSectionStatus.none,
  });

  final String summary;
  final VoidCallback onTap;
  final PlateEditorSectionStatus status;

  @override
  Widget build(BuildContext context) {
    return PlateEditorOverviewSection(
      icon: Icons.photo_library_rounded,
      title: '사진',
      value: summary,
      status: status,
      onTap: onTap,
    );
  }
}

class _PlateEditorListSurface extends StatelessWidget {
  const _PlateEditorListSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: child,
      ),
    );
  }
}

class _PlateEditorActionRowSurface extends StatefulWidget {
  const _PlateEditorActionRowSurface({
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PlateEditorActionRowSurface> createState() =>
      _PlateEditorActionRowSurfaceState();
}

class _PlateEditorActionRowSurfaceState
    extends State<_PlateEditorActionRowSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedScale(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
      curve: CommonUiMotion.enter,
      scale: _pressed ? .985 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (value) {
            if (!mounted) return;
            setState(() => _pressed = value);
          },
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
            curve: CommonUiMotion.standard,
            color: _pressed
                ? tokens.surfaceSelected.withOpacity(.55)
                : Colors.transparent,
            padding: const EdgeInsets.fromLTRB(11, 10, 13, 10),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _PlateEditorStatusDot extends StatelessWidget {
  const _PlateEditorStatusDot({required this.status});

  final PlateEditorSectionStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final color = _statusColor(tokens, status);
    final icon = switch (status) {
      PlateEditorSectionStatus.error => Icons.error_rounded,
      PlateEditorSectionStatus.loading => Icons.pending_rounded,
      PlateEditorSectionStatus.incomplete => Icons.radio_button_unchecked_rounded,
      PlateEditorSectionStatus.pending => Icons.pending_actions_rounded,
      PlateEditorSectionStatus.none => Icons.radio_button_unchecked_rounded,
      PlateEditorSectionStatus.changed => Icons.circle_rounded,
      PlateEditorSectionStatus.complete => Icons.circle_rounded,
    };
    return Icon(icon, size: 11, color: color);
  }
}

String? _statusLabel(PlateEditorSectionStatus status) {
  switch (status) {
    case PlateEditorSectionStatus.none:
      return null;
    case PlateEditorSectionStatus.changed:
      return '변경됨';
    case PlateEditorSectionStatus.complete:
      return '완료';
    case PlateEditorSectionStatus.incomplete:
      return '미완료';
    case PlateEditorSectionStatus.pending:
      return '적용 대기';
    case PlateEditorSectionStatus.loading:
      return '확인 중';
    case PlateEditorSectionStatus.error:
      return '확인 필요';
  }
}

Color _statusColor(CommonUiTokens tokens, PlateEditorSectionStatus status) {
  switch (status) {
    case PlateEditorSectionStatus.changed:
    case PlateEditorSectionStatus.complete:
      return tokens.accent;
    case PlateEditorSectionStatus.incomplete:
    case PlateEditorSectionStatus.pending:
      return tokens.warning;
    case PlateEditorSectionStatus.error:
      return tokens.danger;
    case PlateEditorSectionStatus.loading:
    case PlateEditorSectionStatus.none:
      return tokens.textSecondary;
  }
}
