import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand_theme.dart';
import '../theme_prefs_controller.dart';

class BrandThemeDebugSelector extends StatelessWidget {
  const BrandThemeDebugSelector({
    super.key,
    required this.controller,
    required this.source,
    required this.routePhase,
    required this.onSelectActualTheme,
    required this.onSelectPreset,
  });

  final ThemePrefsController controller;
  final String source;
  final String routePhase;
  final Future<void> Function() onSelectActualTheme;
  final Future<void> Function(BrandPresetSpec preset) onSelectPreset;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 240);
    final presets = brandPresets();
    final requested = controller.requestedPreset;
    final effective = controller.effectivePreset;
    final requestedScheme = buildBrandColorScheme(requested.colors);
    final effectiveScheme = buildBrandColorScheme(effective.colors);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _AnimatedChoice(
              selected: controller.debugPresetId == null,
              duration: duration,
              child: ChoiceChip(
                selected: controller.debugPresetId == null,
                onSelected: (selected) async {
                  if (!selected || controller.debugPresetId == null) return;
                  await HapticFeedback.selectionClick();
                  await onSelectActualTheme();
                },
                label: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.restart_alt_rounded, size: 16),
                    SizedBox(width: 6),
                    Text('실제 테마'),
                  ],
                ),
              ),
            ),
            for (final preset in presets)
              _AnimatedChoice(
                selected: controller.debugPresetId == preset.id,
                duration: duration,
                child: ChoiceChip(
                  selected: controller.debugPresetId == preset.id,
                  onSelected: (_) async {
                    await HapticFeedback.selectionClick();
                    await onSelectPreset(preset);
                  },
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _PresetPreviewDots(
                        colors: preset.preview,
                        duration: duration,
                      ),
                      const SizedBox(width: 8),
                      Text(preset.label),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: duration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            if (reduceMotion) return child;
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: slide,
                child: child,
              ),
            );
          },
          child: AnimatedContainer(
            key: ValueKey<String>(
              '$source:${controller.debugModeEnabled}:${controller.debugPresetId}:${controller.requestedPresetId}:${controller.brandThemeEnabled}',
            ),
            duration: duration,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: requestedScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: controller.debugOverrideAvailable
                    ? requestedScheme.primary.withOpacity(0.55)
                    : requestedScheme.outlineVariant.withOpacity(0.8),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _PresetPreviewDots(
                      colors: requested.preview,
                      duration: duration,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        requested.label,
                        style: text.bodyMedium?.copyWith(
                          color: requestedScheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: duration,
                      child: controller.debugOverrideAvailable
                          ? Icon(
                              Icons.bug_report_rounded,
                              key: const ValueKey<String>(
                                'debug_theme_available',
                              ),
                              size: 18,
                              color: requestedScheme.primary,
                            )
                          : Icon(
                              Icons.verified_outlined,
                              key: const ValueKey<String>(
                                'normal_theme_available',
                              ),
                              size: 18,
                              color: requestedScheme.onSurfaceVariant,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ThemeColorBar(
                  colors: requested.preview,
                  duration: duration,
                ),
                const SizedBox(height: 14),
                AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: effectiveScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: effectiveScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      AnimatedSwitcher(
                        duration: duration,
                        child: Icon(
                          controller.debugOverrideApplied
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          key: ValueKey<bool>(
                            controller.debugOverrideApplied,
                          ),
                          size: 18,
                          color: controller.debugOverrideApplied
                              ? effectiveScheme.primary
                              : effectiveScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '실제 적용 ${effective.label}',
                          style: text.bodySmall?.copyWith(
                            color: effectiveScheme.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: duration,
                        child: Text(
                          routePhase,
                          key: ValueKey<String>(routePhase),
                          style: text.labelSmall?.copyWith(
                            color: effectiveScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedChoice extends StatelessWidget {
  const _AnimatedChoice({
    required this.selected,
    required this.duration,
    required this.child,
  });

  final bool selected;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1.035 : 1.0,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: selected ? 1.0 : 0.88,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}

class _PresetPreviewDots extends StatelessWidget {
  const _PresetPreviewDots({
    required this.colors,
    required this.duration,
  });

  final List<Color> colors;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final dots = colors.take(3).toList(growable: false);
    final outline =
        Theme.of(context).colorScheme.outlineVariant.withOpacity(0.6);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(dots.length, (index) {
        return AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          width: 10,
          height: 10,
          margin: EdgeInsets.only(right: index == dots.length - 1 ? 0 : 4),
          decoration: BoxDecoration(
            color: dots[index],
            shape: BoxShape.circle,
            border: Border.all(color: outline),
          ),
        );
      }),
    );
  }
}

class _ThemeColorBar extends StatelessWidget {
  const _ThemeColorBar({
    required this.colors,
    required this.duration,
  });

  final List<Color> colors;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final items = colors.take(3).toList(growable: false);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 8,
        child: Row(
          children: <Widget>[
            for (final color in items)
              Expanded(
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  color: color,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
