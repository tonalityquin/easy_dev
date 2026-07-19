import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';

class ParkingCompletedSheetTitleRow extends StatelessWidget {
  const ParkingCompletedSheetTitleRow({
    super.key,
    required this.title,
    required this.icon,
    this.onClose,
    this.closeEnabled = true,
    this.colorScheme,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onClose;
  final bool closeEnabled;
  final ColorScheme? colorScheme;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return PromptAnimatedReveal(
      offset: const Offset(0, .02),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tokens.accentContainer,
              borderRadius: BorderRadius.circular(PromptUiShapes.control),
              border: Border.all(color: tokens.borderSubtle),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: tokens.onAccentContainer, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (onClose != null)
            PromptIconButton(
              icon: Icons.close_rounded,
              tooltip: '닫기',
              onPressed: closeEnabled ? onClose : null,
              haptic: PromptHaptic.selection,
              size: 42,
              iconSize: 21,
            ),
        ],
      ),
    );
  }
}

class ParkingCompletedPlateSummaryCard extends StatelessWidget {
  const ParkingCompletedPlateSummaryCard({
    super.key,
    required this.plateNumber,
    required this.area,
    required this.location,
    required this.billingType,
    required this.isLocked,
    required this.lockedFee,
    required this.paymentMethod,
    required this.statusMemo,
    this.attention = 0,
    this.colorScheme,
    this.lockedBadgeColor,
    this.unlockedBadgeColor,
    this.warningText = '정산이 필요합니다.',
    this.borderColorResolver,
    this.backgroundColorResolver,
  });

  final String plateNumber;
  final String area;
  final String location;
  final String billingType;
  final bool isLocked;
  final int? lockedFee;
  final String paymentMethod;
  final String statusMemo;
  final double attention;
  final ColorScheme? colorScheme;
  final Color? lockedBadgeColor;
  final Color? unlockedBadgeColor;
  final String warningText;
  final Color Function(ColorScheme cs, double attention)? borderColorResolver;
  final Color Function(ColorScheme cs, double attention)? backgroundColorResolver;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final cs = colorScheme ?? Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final safeAttention = reduceMotion ? 0.0 : attention.clamp(0.0, 1.0).toDouble();
    final badgeColor = isLocked
        ? (lockedBadgeColor ?? tokens.success)
        : (unlockedBadgeColor ?? tokens.iconSecondary);
    final badgeBackground = isLocked
        ? tokens.successContainer
        : tokens.surfaceOverlay;
    final badgeForeground = isLocked
        ? tokens.onSuccessContainer
        : tokens.textSecondary;
    final badgeText = isLocked ? '사전정산 잠김' : '사전정산 없음';
    final feeText = isLocked && lockedFee != null
        ? '₩$lockedFee${paymentMethod.isNotEmpty ? " ($paymentMethod)" : ""}'
        : '—';
    final billingText = billingType.isNotEmpty ? billingType : '미지정';
    final memoText = statusMemo.trim().isNotEmpty ? statusMemo.trim() : '—';
    final resolvedBorder = borderColorResolver?.call(cs, safeAttention);
    final resolvedBackground =
        backgroundColorResolver?.call(cs, safeAttention);
    final borderColor = resolvedBorder ??
        Color.lerp(
          tokens.borderSubtle,
          tokens.danger,
          safeAttention * .8,
        )!;
    final backgroundColor = resolvedBackground ??
        Color.lerp(
          tokens.surfaceRaised,
          tokens.dangerContainer,
          safeAttention * .28,
        )!;

    return PromptAnimatedReveal(
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow.withOpacity(tokens.isDark ? .28 : .10),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tokens.accentContainer,
                    borderRadius:
                        BorderRadius.circular(PromptUiShapes.control),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.directions_car_filled_rounded,
                    color: tokens.onAccentContainer,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    plateNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleLarge?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration:
                      reduceMotion ? Duration.zero : PromptUiMotion.selection,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: badgeBackground,
                    borderRadius: BorderRadius.circular(PromptUiShapes.pill),
                    border: Border.all(color: badgeColor.withOpacity(.42)),
                  ),
                  child: Text(
                    badgeText,
                    style: textTheme.labelSmall?.copyWith(
                      color: badgeForeground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
              switchInCurve: PromptUiMotion.enter,
              switchOutCurve: PromptUiMotion.exit,
              child: safeAttention > .001 && !isLocked
                  ? Container(
                      key: const ValueKey<String>('billing-warning'),
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.dangerContainer,
                        borderRadius:
                            BorderRadius.circular(PromptUiShapes.control),
                        border: Border.all(
                          color: tokens.danger.withOpacity(.42),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: tokens.danger,
                            size: 19,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              warningText,
                              style: textTheme.labelMedium?.copyWith(
                                color: tokens.onDangerContainer,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey<String>('billing-safe'),
                    ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.surfaceOverlay,
                borderRadius: BorderRadius.circular(PromptUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _ParkingCompletedInfoLine(
                          icon: Icons.apartment_rounded,
                          label: '지역',
                          value: area,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ParkingCompletedInfoLine(
                          icon: Icons.location_on_rounded,
                          label: '위치',
                          value: location,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ParkingCompletedInfoLine(
                          icon: Icons.receipt_long_rounded,
                          label: '정산 타입',
                          value: billingText,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ParkingCompletedInfoLine(
                          icon: Icons.lock_rounded,
                          label: '잠금 금액',
                          value: feeText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ParkingCompletedInfoLine(
                    icon: Icons.notes_rounded,
                    label: '상태 메모',
                    value: memoText,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParkingCompletedInfoLine extends StatelessWidget {
  const _ParkingCompletedInfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final displayValue = value.trim().isEmpty ? '—' : value.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: tokens.iconSecondary),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                displayValue,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ParkingCompletedSectionCard extends StatelessWidget {
  const ParkingCompletedSectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.colorScheme,
    this.borderColor,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final ColorScheme? colorScheme;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return PromptAnimatedReveal(
      offset: const Offset(0, .018),
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          border: Border.all(color: borderColor ?? tokens.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow.withOpacity(tokens.isDark ? .24 : .08),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class ParkingCompletedPrimaryCtaButton extends StatelessWidget {
  const ParkingCompletedPrimaryCtaButton({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.enabled = true,
    this.backgroundColor,
    this.foregroundColor,
    this.colorScheme,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final FutureOr<void> Function() onPressed;
  final bool enabled;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final ColorScheme? colorScheme;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return _ParkingCompletedActionButton(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onPressed: enabled ? onPressed : null,
      background: backgroundColor ?? tokens.accent,
      foreground: foregroundColor ?? tokens.onAccent,
      border: backgroundColor == null
          ? tokens.transparent
          : (foregroundColor ?? tokens.onAccent).withOpacity(.26),
      defaultBackground: backgroundColor == null,
      haptic: PromptHaptic.medium,
    );
  }
}

class ParkingCompletedSecondaryActionButton extends StatelessWidget {
  const ParkingCompletedSecondaryActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.badgeText,
    this.backgroundColor,
    this.borderColor,
    this.foregroundColor,
    this.attention = 0,
    this.iconColor,
    this.badgeColor,
    this.baseBackgroundColor,
    this.baseBorderColor,
    this.colorScheme,
  });

  final IconData icon;
  final String label;
  final FutureOr<void> Function() onPressed;
  final bool enabled;
  final String? badgeText;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? foregroundColor;
  final double attention;
  final Color? iconColor;
  final Color? badgeColor;
  final Color? baseBackgroundColor;
  final Color? baseBorderColor;
  final ColorScheme? colorScheme;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final safeAttention = reduceMotion ? 0.0 : attention.clamp(0.0, 1.0).toDouble();
    final baseBg = backgroundColor ?? baseBackgroundColor ?? tokens.accentContainer;
    final baseBd = borderColor ?? baseBorderColor ?? tokens.borderSubtle;
    final effectiveForeground = foregroundColor ?? tokens.onAccentContainer;
    final effectiveIcon = iconColor ?? effectiveForeground;
    final effectiveBadge = badgeColor ?? effectiveForeground;
    final bg = Color.lerp(baseBg, tokens.dangerContainer, safeAttention * .48)!;
    final bd = Color.lerp(baseBd, tokens.danger, safeAttention * .52)!;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _ParkingCompletedActionButton(
          icon: icon,
          title: label,
          onPressed: enabled ? onPressed : null,
          background: bg,
          foreground: effectiveForeground,
          iconColor: effectiveIcon,
          border: bd,
          minHeight: 48,
          haptic: PromptHaptic.selection,
        ),
        if (badgeText != null && badgeText!.trim().isNotEmpty)
          Positioned(
            top: -7,
            right: -5,
            child: AnimatedContainer(
              duration:
                  reduceMotion ? Duration.zero : PromptUiMotion.selection,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(PromptUiShapes.pill),
                border: Border.all(color: effectiveBadge.withOpacity(.48)),
                boxShadow: [
                  BoxShadow(
                    color: tokens.shadow.withOpacity(.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                badgeText!.trim(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: effectiveBadge,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

class ParkingCompletedDangerActionButton extends StatelessWidget {
  const ParkingCompletedDangerActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.colorScheme,
  });

  final IconData icon;
  final String label;
  final FutureOr<void> Function() onPressed;
  final bool enabled;
  final ColorScheme? colorScheme;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return _ParkingCompletedActionButton(
      icon: icon,
      title: label,
      onPressed: enabled ? onPressed : null,
      background: tokens.dangerContainer,
      foreground: tokens.onDangerContainer,
      iconColor: tokens.danger,
      border: tokens.danger,
      minHeight: 50,
      haptic: PromptHaptic.medium,
    );
  }
}

class _ParkingCompletedActionButton extends StatefulWidget {
  const _ParkingCompletedActionButton({
    required this.icon,
    required this.title,
    required this.onPressed,
    required this.background,
    required this.foreground,
    required this.border,
    required this.haptic,
    this.subtitle,
    this.iconColor,
    this.minHeight = 54,
    this.defaultBackground = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final FutureOr<void> Function()? onPressed;
  final Color background;
  final Color foreground;
  final Color border;
  final Color? iconColor;
  final double minHeight;
  final bool defaultBackground;
  final PromptHaptic haptic;

  @override
  State<_ParkingCompletedActionButton> createState() =>
      _ParkingCompletedActionButtonState();
}

class _ParkingCompletedActionButtonState
    extends State<_ParkingCompletedActionButton> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  bool _invoking = false;
  bool? _pendingPressed;
  bool? _pendingHovered;
  bool? _pendingFocused;
  bool _frameScheduled = false;

  bool get _available => widget.onPressed != null;
  bool get _enabled => _available && !_invoking;

  void _queue({bool? pressed, bool? hovered, bool? focused}) {
    if (pressed != null) _pendingPressed = pressed;
    if (hovered != null) _pendingHovered = hovered;
    if (focused != null) _pendingFocused = focused;
    if (_frameScheduled) return;
    _frameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameScheduled = false;
      if (!mounted) return;
      final pressedValue = _pendingPressed;
      final hoveredValue = _pendingHovered;
      final focusedValue = _pendingFocused;
      _pendingPressed = null;
      _pendingHovered = null;
      _pendingFocused = null;
      final changed =
          pressedValue != null && pressedValue != _pressed ||
          hoveredValue != null && hoveredValue != _hovered ||
          focusedValue != null && focusedValue != _focused;
      if (!changed) return;
      setState(() {
        if (pressedValue != null) _pressed = pressedValue;
        if (hoveredValue != null) _hovered = hoveredValue;
        if (focusedValue != null) _focused = focusedValue;
      });
    });
  }

  Future<void> _activate() async {
    if (!_enabled) return;
    setState(() => _invoking = true);
    try {
      switch (widget.haptic) {
        case PromptHaptic.none:
          break;
        case PromptHaptic.selection:
          await HapticFeedback.selectionClick();
          break;
        case PromptHaptic.light:
          await HapticFeedback.lightImpact();
          break;
        case PromptHaptic.medium:
          await HapticFeedback.mediumImpact();
          break;
        case PromptHaptic.heavy:
          await HapticFeedback.heavyImpact();
          break;
      }
      await widget.onPressed!.call();
    } finally {
      if (mounted) {
        setState(() {
          _invoking = false;
          _pressed = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final disabled = !_available;
    final background = disabled
        ? tokens.surfaceDisabled
        : widget.defaultBackground
            ? _pressed
                ? tokens.accentPressed
                : _hovered
                    ? tokens.accentHover
                    : widget.background
            : widget.background;
    final foreground = disabled ? tokens.textDisabled : widget.foreground;
    final border = disabled ? tokens.borderSubtle : widget.border;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.title,
      value: _invoking ? '처리 중' : null,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        constraints: BoxConstraints(minHeight: widget.minHeight),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(PromptUiShapes.button),
          border: Border.all(
            color: _focused ? tokens.focusRing : border,
            width: _focused ? 2 : 1,
          ),
          boxShadow: [
            if (_hovered && _enabled)
              BoxShadow(
                color: tokens.shadow,
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
          ],
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(PromptUiShapes.button),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _available ? _activate : null,
            onHighlightChanged: (value) => _queue(pressed: value),
            onHover: (value) => _queue(hovered: value),
            onFocusChange: (value) => _queue(focused: value),
            borderRadius: BorderRadius.circular(PromptUiShapes.button),
            overlayColor: WidgetStatePropertyAll(
              foreground.withOpacity(_pressed ? .12 : .06),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedOpacity(
                    duration:
                        reduceMotion ? Duration.zero : PromptUiMotion.instant,
                    opacity: _invoking ? 0 : 1,
                    child: AnimatedScale(
                      scale: _pressed && _enabled ? .98 : 1,
                      duration:
                          reduceMotion ? Duration.zero : PromptUiMotion.press,
                      curve: PromptUiMotion.enter,
                      child: Row(
                        children: [
                          Icon(
                            widget.icon,
                            size: 20,
                            color: disabled
                                ? tokens.iconDisabled
                                : widget.iconColor ?? foreground,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.labelLarge?.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (widget.subtitle != null &&
                                    widget.subtitle!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.subtitle!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: foreground.withOpacity(.88),
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 21,
                            color: foreground,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_invoking)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: foreground,
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
