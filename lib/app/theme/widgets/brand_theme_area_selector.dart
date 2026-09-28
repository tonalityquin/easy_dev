import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand_theme.dart';
import '../theme_prefs_controller.dart';

class BrandThemeAreaSelector extends StatelessWidget {
  const BrandThemeAreaSelector({
    super.key,
    required this.controller,
    required this.source,
    required this.routePhase,
  });

  final ThemePrefsController controller;
  final String source;
  final String routePhase;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 240);
    final areaPreset = controller.areaRegisteredPreset;
    final selectedChoice = controller.normalThemeChoice;
    final selectedPreset = controller.normalEffectivePreset;
    final effectivePreset = controller.effectivePreset;
    final selectedScheme = buildBrandColorScheme(selectedPreset.colors);
    final effectiveScheme = buildBrandColorScheme(effectivePreset.colors);

    Future<void> selectChoice(AreaThemeChoice choice) async {
      await HapticFeedback.selectionClick();
      await controller.setAreaThemeChoice(
        choice,
        source: source,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _AnimatedChoice(
              selected: selectedChoice == AreaThemeChoice.defaultTheme,
              duration: duration,
              child: ChoiceChip(
                selected: selectedChoice == AreaThemeChoice.defaultTheme,
                onSelected: (selected) async {
                  if (!selected) return;
                  await selectChoice(AreaThemeChoice.defaultTheme);
                },
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _PresetPreviewDots(
                      colors: kDefaultBrandPreset.preview,
                      duration: duration,
                    ),
                    const SizedBox(width: 8),
                    const Text('기본'),
                  ],
                ),
              ),
            ),
            if (areaPreset != null)
              _AnimatedChoice(
                selected: selectedChoice == AreaThemeChoice.brand,
                duration: duration,
                child: ChoiceChip(
                  selected: selectedChoice == AreaThemeChoice.brand,
                  onSelected: (selected) async {
                    if (!selected) return;
                    await selectChoice(AreaThemeChoice.brand);
                  },
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _PresetPreviewDots(
                        colors: areaPreset.preview,
                        duration: duration,
                      ),
                      const SizedBox(width: 8),
                      Text(areaPreset.label),
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
              '$source:${controller.selectedArea}:${controller.normalPresetId}:${controller.brandThemeEnabled}',
            ),
            duration: duration,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selectedScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selectedScheme.primary.withOpacity(0.42),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _PresetPreviewDots(
                      colors: selectedPreset.preview,
                      duration: duration,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: duration,
                        child: Text(
                          selectedPreset.label,
                          key: ValueKey<String>(selectedPreset.id),
                          style: text.bodyMedium?.copyWith(
                            color: selectedScheme.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: duration,
                      child: Icon(
                        selectedChoice == AreaThemeChoice.brand
                            ? Icons.location_on_rounded
                            : Icons.restart_alt_rounded,
                        key: ValueKey<AreaThemeChoice>(selectedChoice),
                        size: 18,
                        color: selectedScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ThemeColorBar(
                  colors: selectedPreset.preview,
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
                          controller.brandThemeEnabled &&
                                  effectivePreset.id == selectedPreset.id
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          key: ValueKey<String>(
                            '${controller.brandThemeEnabled}:${effectivePreset.id}:${selectedPreset.id}',
                          ),
                          size: 18,
                          color: effectiveScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: duration,
                          child: Text(
                            '실제 적용 ${effectivePreset.label}',
                            key: ValueKey<String>(effectivePreset.id),
                            style: text.bodySmall?.copyWith(
                              color: effectiveScheme.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
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
