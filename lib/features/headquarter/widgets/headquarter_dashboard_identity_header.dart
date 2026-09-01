import 'package:flutter/material.dart';

import '../../../design_system/common_ui/common_ui_theme.dart';
import '../application/headquarter_dashboard_context.dart';

enum HeadquarterDashboardIdentityVariant {
  dashboard,
  modeDock,
  quickDock,
}

class HeadquarterDashboardIdentityHeader extends StatefulWidget {
  const HeadquarterDashboardIdentityHeader({
    super.key,
    required this.name,
    required this.position,
    required this.modeKey,
    required this.variant,
    this.onTap,
  });

  final String name;
  final String position;
  final String modeKey;
  final HeadquarterDashboardIdentityVariant variant;
  final VoidCallback? onTap;

  @override
  State<HeadquarterDashboardIdentityHeader> createState() =>
      _HeadquarterDashboardIdentityHeaderState();
}

class _HeadquarterDashboardIdentityHeaderState
    extends State<HeadquarterDashboardIdentityHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _started = false;
  bool _pressed = false;

  bool get _animateEntrance =>
      widget.variant != HeadquarterDashboardIdentityVariant.dashboard;

  Duration get _duration {
    switch (widget.variant) {
      case HeadquarterDashboardIdentityVariant.modeDock:
        return const Duration(milliseconds: 200);
      case HeadquarterDashboardIdentityVariant.quickDock:
        return const Duration(milliseconds: 170);
      case HeadquarterDashboardIdentityVariant.dashboard:
        return Duration.zero;
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: CommonUiMotion.enter,
      reverseCurve: CommonUiMotion.exit,
    );
    if (!_animateEntrance) {
      _controller.value = 1;
      _started = true;
    }
  }

  @override
  void didUpdateWidget(covariant HeadquarterDashboardIdentityHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.variant != widget.variant) {
      _controller.duration = _duration;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.value = 1;
      _started = true;
      return;
    }
    if (_animateEntrance && !_started) {
      _started = true;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _safe(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? '-' : normalized;
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    if (!_animateEntrance) return content;

    return AnimatedBuilder(
      animation: _animation,
      child: content,
      builder: (context, child) {
        final value = _animation.value;
        final isQuick =
            widget.variant == HeadquarterDashboardIdentityVariant.quickDock;
        final beginScale = isQuick ? .98 : .985;
        final offsetY = (1 - value) * (isQuick ? 3.0 : 4.0);
        final scale = beginScale + ((1 - beginScale) * value);
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, offsetY),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final name = _safe(widget.name);
    final position = _safe(widget.position);
    final modeLabel = HeadquarterDashboardContext.modeLabel(widget.modeKey);
    final isDashboard =
        widget.variant == HeadquarterDashboardIdentityVariant.dashboard;
    final isQuick =
        widget.variant == HeadquarterDashboardIdentityVariant.quickDock;
    final iconSize = isDashboard ? 42.0 : (isQuick ? 34.0 : 38.0);
    final iconRadius = isDashboard ? 14.0 : (isQuick ? 11.0 : 12.0);
    final gap = isDashboard ? 12.0 : (isQuick ? 9.0 : 10.0);

    final body = Row(
      children: [
        Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            color: tokens.accentContainer,
            borderRadius: BorderRadius.circular(iconRadius),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.apartment_rounded,
            size: isDashboard ? 24 : (isQuick ? 19 : 21),
            color: tokens.onAccentContainer,
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '본사 대시보드',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _titleStyle(context, tokens),
                    ),
                  ),
                  SizedBox(width: isQuick ? 6 : 8),
                  _IdentityModeBadge(
                    label: modeLabel,
                    compact: !isDashboard,
                    extraCompact: isQuick,
                  ),
                ],
              ),
              SizedBox(height: isDashboard ? 6 : (isQuick ? 4 : 5)),
              if (isQuick)
                _QuickMetadataLine(
                  name: name,
                  position: position,
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _IdentityMetadataPill(
                      icon: Icons.person_rounded,
                      text: name,
                      compact: !isDashboard,
                    ),
                    _IdentityMetadataPill(
                      icon: Icons.badge_rounded,
                      text: position,
                      compact: !isDashboard,
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (isQuick && widget.onTap != null) ...[
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: tokens.iconSecondary,
          ),
        ],
      ],
    );

    final semantic = Semantics(
      container: true,
      button: widget.onTap != null,
      label: '본사 대시보드, $modeLabel, 사용자 $name, 직급 $position',
      child: body,
    );

    if (isDashboard) return semantic;

    final radius = BorderRadius.circular(isQuick ? 14 : 16);
    final panel = Container(
      padding: EdgeInsets.all(isQuick ? 10 : 12),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: radius,
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: semantic,
    );

    if (widget.onTap == null) return panel;

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedScale(
      scale: _pressed ? .985 : 1,
      duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
      curve: CommonUiMotion.enter,
      child: Material(
        color: tokens.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: radius,
          onTap: widget.onTap,
          onHighlightChanged: (value) {
            if (_pressed == value) return;
            setState(() => _pressed = value);
          },
          child: panel,
        ),
      ),
    );
  }

  TextStyle _titleStyle(BuildContext context, CommonUiTokens tokens) {
    final textTheme = Theme.of(context).textTheme;
    switch (widget.variant) {
      case HeadquarterDashboardIdentityVariant.dashboard:
        return (textTheme.titleLarge ?? const TextStyle(fontSize: 22)).copyWith(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: -.3,
        );
      case HeadquarterDashboardIdentityVariant.modeDock:
        return (textTheme.titleMedium ?? const TextStyle(fontSize: 16))
            .copyWith(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: -.2,
        );
      case HeadquarterDashboardIdentityVariant.quickDock:
        return (textTheme.titleSmall ?? const TextStyle(fontSize: 14))
            .copyWith(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: -.1,
        );
    }
  }
}

class _IdentityModeBadge extends StatelessWidget {
  const _IdentityModeBadge({
    required this.label,
    required this.compact,
    required this.extraCompact,
  });

  final String label;
  final bool compact;
  final bool extraCompact;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      switchInCurve: CommonUiMotion.enter,
      switchOutCurve: CommonUiMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .96, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey<String>(label),
        padding: EdgeInsets.symmetric(
          horizontal: extraCompact ? 7 : (compact ? 8 : 10),
          vertical: extraCompact ? 3 : (compact ? 4 : 6),
        ),
        decoration: BoxDecoration(
          color: tokens.accentContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.onAccentContainer,
            fontWeight: FontWeight.w900,
            fontSize: extraCompact ? 10.5 : (compact ? 11 : 12),
            letterSpacing: -.1,
          ),
        ),
      ),
    );
  }
}

class _IdentityMetadataPill extends StatelessWidget {
  const _IdentityMetadataPill({
    required this.icon,
    required this.text,
    required this.compact,
  });

  final IconData icon;
  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Container(
      constraints: BoxConstraints(maxWidth: compact ? 150 : 170),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 9,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: compact ? tokens.surfaceRaised : tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: compact ? 12 : 13,
            color: tokens.iconSecondary,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: AnimatedSwitcher(
              duration:
                  reduceMotion ? Duration.zero : CommonUiMotion.selection,
              child: Text(
                text,
                key: ValueKey<String>(text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: compact ? 11 : 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickMetadataLine extends StatelessWidget {
  const _QuickMetadataLine({
    required this.name,
    required this.position,
  });

  final String name;
  final String position;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final label = '$name · $position';
    return Row(
      children: [
        Icon(Icons.person_rounded, size: 12, color: tokens.iconSecondary),
        const SizedBox(width: 5),
        Expanded(
          child: AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            child: Text(
              label,
              key: ValueKey<String>(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
