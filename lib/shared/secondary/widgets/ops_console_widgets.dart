import 'package:flutter/material.dart';

class OpsMetric {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const OpsMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });
}

class OpsConsoleScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final String? areaLabel;
  final List<OpsMetric> metrics;
  final Widget? commandBar;
  final Widget body;
  final Widget? trailing;
  final Widget? bottomBar;
  final bool loading;

  const OpsConsoleScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.body,
    this.areaLabel,
    this.metrics = const <OpsMetric>[],
    this.commandBar,
    this.trailing,
    this.bottomBar,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceVariant.withOpacity(.22),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            OpsConsoleHeader(
              title: title,
              subtitle: subtitle,
              icon: icon,
              areaLabel: areaLabel,
              metrics: metrics,
              trailing: trailing,
            ),
            if (commandBar != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: commandBar!,
              ),
            Expanded(
              child: Stack(
                children: [
                  body,
                  if (loading)
                    Positioned.fill(
                      child: Container(
                        color: cs.scrim.withOpacity(.08),
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: bottomBar,
    );
  }
}

class OpsConsoleHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final String? areaLabel;
  final List<OpsMetric> metrics;
  final Widget? trailing;

  const OpsConsoleHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.areaLabel,
    this.metrics = const <OpsMetric>[],
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final titleStyle = (tt.titleLarge ?? const TextStyle(fontSize: 21)).copyWith(
      color: cs.onInverseSurface,
      fontWeight: FontWeight.w900,
      letterSpacing: -.25,
    );
    final subtitleText = subtitle?.trim() ?? '';
    final subtitleStyle = (tt.bodySmall ?? const TextStyle(fontSize: 12.5)).copyWith(
      color: cs.onInverseSurface.withOpacity(.72),
      fontWeight: FontWeight.w800,
      height: 1.25,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(.35))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: cs.onPrimary, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitleText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(subtitleText, style: subtitleStyle, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              if (areaLabel != null && areaLabel!.trim().isNotEmpty) ...[
                const SizedBox(width: 10),
                OpsHeaderPill(text: areaLabel!),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: metrics.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) => OpsMetricCard(metric: metrics[index]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class OpsHeaderPill extends StatelessWidget {
  final String text;

  const OpsHeaderPill({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.onInverseSurface.withOpacity(.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.onInverseSurface.withOpacity(.18)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: cs.onInverseSurface,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class OpsMetricCard extends StatelessWidget {
  final OpsMetric metric;

  const OpsMetricCard({super.key, required this.metric});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = metric.color ?? cs.primary;
    return Container(
      width: 118,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cs.onInverseSurface.withOpacity(.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onInverseSurface.withOpacity(.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(metric.icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onInverseSurface.withOpacity(.70),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -.3,
            ),
          ),
        ],
      ),
    );
  }
}

class OpsCommandPanel extends StatelessWidget {
  final List<Widget> children;

  const OpsCommandPanel({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(.82)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class OpsSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  const OpsSearchField({super.key, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800, fontSize: 13.5),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),

        hintStyle: TextStyle(color: cs.onSurfaceVariant.withOpacity(.78), fontWeight: FontWeight.w800),
        filled: true,
        fillColor: cs.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.primary, width: 1.4),
        ),
      ),
    );
  }
}

class OpsFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final IconData? icon;

  const OpsFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onPrimary : cs.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant.withOpacity(.86)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class OpsPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final bool selected;
  final Color? accentColor;

  const OpsPanel({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.only(bottom: 10),
    this.padding = const EdgeInsets.all(14),
    this.selected = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = accentColor ?? cs.primary;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: selected ? Color.alphaBlend(accent.withOpacity(.08), cs.surface) : cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? accent : cs.outlineVariant.withOpacity(.82), width: selected ? 1.35 : 1),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class OpsSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;

  const OpsSectionTitle({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(.10),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: cs.primary.withOpacity(.18)),
          ),
          child: Icon(icon, color: cs.primary, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: (tt.titleSmall ?? const TextStyle(fontSize: 14)).copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.15,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: (tt.bodySmall ?? const TextStyle(fontSize: 12)).copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class OpsStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const OpsStatusBadge({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class OpsInfoPill extends StatelessWidget {
  final String text;
  final IconData? icon;

  const OpsInfoPill({super.key, required this.text, this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(.75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class OpsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const OpsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.primary.withOpacity(.20)),
              ),
              child: Icon(icon, color: cs.primary, size: 28),
            ),
            const SizedBox(height: 13),
            Text(
              title,
              textAlign: TextAlign.center,
              style: (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(color: cs.onSurface, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: (tt.bodySmall ?? const TextStyle(fontSize: 12.5)).copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 14),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class OpsBottomActionBar extends StatelessWidget {
  final List<Widget> children;

  const OpsBottomActionBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(.82))),
        ),
        child: Row(children: children),
      ),
    );
  }
}

class OpsActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;
  final bool tonal;

  const OpsActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
    this.tonal = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (tonal) {
      return FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        backgroundColor: danger ? cs.error : cs.primary,
        foregroundColor: danger ? cs.onError : cs.onPrimary,
        disabledBackgroundColor: cs.surfaceVariant,
        disabledForegroundColor: cs.onSurfaceVariant.withOpacity(.55),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    );
  }
}

class OpsDivider extends StatelessWidget {
  const OpsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(height: 1, color: cs.outlineVariant.withOpacity(.75));
  }
}

class OpsWorkSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String? areaLabel;
  final List<OpsMetric> metrics;
  final Widget body;
  final Widget? bottomBar;
  final Widget? trailing;
  final EdgeInsetsGeometry bodyPadding;

  const OpsWorkSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.body,
    this.areaLabel,
    this.metrics = const <OpsMetric>[],
    this.bottomBar,
    this.trailing,
    this.bodyPadding = const EdgeInsets.fromLTRB(16, 14, 16, 24),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(.22),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(.7))),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant.withOpacity(.75),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 10),
                OpsConsoleHeader(
                  title: title,
                  subtitle: subtitle,
                  icon: icon,
                  areaLabel: areaLabel,
                  metrics: metrics,
                  trailing: trailing ?? IconButton.filledTonal(
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: bodyPadding,
                    child: body,
                  ),
                ),
                if (bottomBar != null) bottomBar!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OpsWorkSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const OpsWorkSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    return OpsPanel(
      margin: margin,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpsSectionTitle(title: title, subtitle: subtitle, icon: icon, trailing: trailing),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class OpsInlineMessage extends StatelessWidget {
  final String? message;
  final bool danger;
  final IconData icon;

  const OpsInlineMessage({super.key, required this.message, this.danger = true, this.icon = Icons.error_outline_rounded});

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.trim().isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final bg = danger ? cs.errorContainer.withOpacity(.62) : cs.primaryContainer.withOpacity(.35);
    final fg = danger ? cs.onErrorContainer : cs.onPrimaryContainer;
    final border = danger ? cs.error.withOpacity(.35) : cs.primary.withOpacity(.24);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message!,
              style: TextStyle(color: fg, fontWeight: FontWeight.w800, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration opsInputDecoration(
  BuildContext context, {
  required String label,
  String? helperText,
  String? errorText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? suffixText,
  bool locked = false,
}) {
  final cs = Theme.of(context).colorScheme;
  return InputDecoration(
    labelText: label,

    helperText: helperText,
    errorText: errorText,
    prefixIcon: prefixIcon,
    suffixIcon: locked ? Icon(Icons.lock_rounded, color: cs.onSurfaceVariant) : suffixIcon,
    suffixText: suffixText,
    isDense: true,
    filled: true,
    fillColor: locked ? cs.surfaceVariant.withOpacity(.28) : cs.surface,
    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    labelStyle: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800),
    hintStyle: TextStyle(color: cs.onSurfaceVariant.withOpacity(.70), fontWeight: FontWeight.w700),
    helperStyle: TextStyle(color: cs.onSurfaceVariant.withOpacity(.78), fontWeight: FontWeight.w700),
    suffixStyle: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.86)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.primary, width: 1.45),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.error.withOpacity(.75)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.error, width: 1.45),
    ),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  );
}

class OpsFormChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const OpsFormChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withOpacity(.10) : cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant.withOpacity(.82), width: selected ? 1.35 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 6),
            ],
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}
