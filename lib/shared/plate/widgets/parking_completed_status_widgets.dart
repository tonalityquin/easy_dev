import 'dart:async';

import 'package:flutter/material.dart';

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
    final cs = colorScheme ?? Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
        ),
        if (onClose != null)
          IconButton(
            tooltip: '닫기',
            onPressed: closeEnabled ? onClose : null,
            icon: Icon(
              Icons.close,
              color: closeEnabled
                  ? cs.onSurfaceVariant
                  : cs.onSurfaceVariant.withOpacity(0.35),
            ),
          ),
      ],
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
    final cs = colorScheme ?? Theme.of(context).colorScheme;
    final badgeColor = isLocked
        ? (lockedBadgeColor ?? cs.tertiary)
        : (unlockedBadgeColor ?? cs.onSurfaceVariant);
    final badgeText = isLocked ? '사전정산 잠김' : '사전정산 없음';
    final feeText = (isLocked && lockedFee != null)
        ? '₩$lockedFee${paymentMethod.isNotEmpty ? " ($paymentMethod)" : ""}'
        : '—';
    final billingText = billingType.isNotEmpty ? billingType : '미지정';
    final memoText = statusMemo.trim().isNotEmpty ? statusMemo.trim() : '—';
    final borderColor = borderColorResolver?.call(cs, attention) ??
        Color.lerp(
          cs.outlineVariant.withOpacity(0.85),
          cs.error,
          (attention * 0.9).clamp(0, 1),
        )!;
    final backgroundColor = backgroundColorResolver?.call(cs, attention) ??
        Color.lerp(
          cs.surfaceContainerLow,
          cs.errorContainer.withOpacity(0.35),
          (attention * 0.8).clamp(0, 1),
        )!;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
          if (attention > 0.001)
            BoxShadow(
              color: cs.error.withOpacity(0.18 * attention),
              blurRadius: 18 * attention,
              spreadRadius: 1 * attention,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plateNumber,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeColor.withOpacity(0.35)),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (attention > 0.001 && !isLocked) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.errorContainer.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.error.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: cs.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warningText,
                      style: TextStyle(
                        color: cs.error,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              Expanded(child: _ParkingCompletedInfoLine(label: '지역', value: area, colorScheme: cs)),
              const SizedBox(width: 12),
              Expanded(child: _ParkingCompletedInfoLine(label: '위치', value: location, colorScheme: cs)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _ParkingCompletedInfoLine(label: '정산 타입', value: billingText, colorScheme: cs)),
              const SizedBox(width: 12),
              Expanded(child: _ParkingCompletedInfoLine(label: '잠금 금액', value: feeText, colorScheme: cs)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _ParkingCompletedInfoLine(label: '상태 메모', value: memoText, colorScheme: cs)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ParkingCompletedInfoLine extends StatelessWidget {
  const _ParkingCompletedInfoLine({
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  final String label;
  final String value;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final v = value.trim().isEmpty ? '—' : value.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          v,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w800,
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
    final cs = colorScheme ?? Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? cs.outlineVariant.withOpacity(0.85)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 12),
          child,
        ],
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
    final cs = colorScheme ?? Theme.of(context).colorScheme;
    final bg = backgroundColor ?? cs.primary;
    final fg = foregroundColor ?? cs.onPrimary;

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        onPressed: enabled ? () async { await onPressed(); } : null,
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: fg.withOpacity(0.90),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
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
    final cs = colorScheme ?? Theme.of(context).colorScheme;
    final fgBase = foregroundColor ?? cs.onSurface;
    final backgroundBase = backgroundColor ?? baseBackgroundColor ?? cs.surfaceContainerLow;
    final borderBase = borderColor ?? baseBorderColor ?? cs.outlineVariant.withOpacity(0.85);
    final effectiveIconColor = iconColor ?? fgBase;
    final effectiveBadgeColor = badgeColor ?? fgBase;

    final bg = Color.lerp(
      backgroundBase,
      cs.errorContainer.withOpacity(0.35),
      (attention * 0.45).clamp(0, 1),
    )!;
    final bd = Color.lerp(
      borderBase,
      cs.error.withOpacity(0.60),
      (attention * 0.45).clamp(0, 1),
    )!;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        OutlinedButton.icon(
          icon: Icon(icon, size: 18, color: effectiveIconColor),
          label: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w900, color: fgBase),
            textAlign: TextAlign.center,
          ),
          onPressed: enabled ? () async { await onPressed(); } : null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
            foregroundColor: fgBase,
            side: BorderSide(color: bd),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: bg,
            visualDensity: VisualDensity.compact,
          ),
        ),
        if (badgeText != null && badgeText!.trim().isNotEmpty)
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: effectiveBadgeColor.withOpacity(0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: effectiveBadgeColor.withOpacity(0.35)),
              ),
              child: Text(
                badgeText!.trim(),
                style: TextStyle(
                  color: effectiveBadgeColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
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
    final cs = colorScheme ?? Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(icon, color: cs.error),
        label: Text(
          label,
          style: TextStyle(color: cs.error, fontWeight: FontWeight.w900),
        ),
        onPressed: enabled ? () async { await onPressed(); } : null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          side: BorderSide(color: cs.error.withOpacity(0.55)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: cs.errorContainer.withOpacity(0.35),
        ),
      ),
    );
  }
}
