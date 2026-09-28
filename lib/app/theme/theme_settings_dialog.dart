import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design_system/common_ui/common_ui_components.dart';
import '../../design_system/common_ui/common_ui_overlays.dart';
import '../../features/dev/application/debug_session_controller.dart';
import '../init/app_navigator.dart';
import 'brand_theme.dart';
import 'brand_theme_route_policy.dart';
import 'theme_debug_trace.dart';
import 'theme_prefs_controller.dart';
import 'widgets/brand_theme_debug_selector.dart';

Future<void> showCommonThemeSettingsDialog({
  required BuildContext context,
  required String source,
}) async {
  final normalizedSource = source.trim().isEmpty ? 'unknown' : source.trim();
  final themeController = context.read<ThemePrefsController>();
  final openRoute = AppNavigator.currentRoute;
  final openPhase = BrandThemeRoutePolicy.resolve(openRoute);
  ThemeDebugTrace.record(
    'dialog_open_requested',
    source: normalizedSource,
    details: <String, Object?>{
      ...themeController.debugDetails,
      'route': openRoute ?? '-',
      'routePhase': openPhase.name,
    },
  );

  await showCommonOverlayDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '테마',
    builder: (dialogContext) {
      return Consumer<ThemePrefsController>(
        builder: (ctx, themeCtrl, _) {
          final cs = Theme.of(ctx).colorScheme;
          final text = Theme.of(ctx).textTheme;
          final reduceMotion =
              MediaQuery.maybeOf(ctx)?.disableAnimations ?? false;
          final duration = reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 240);
          final currentRoute = AppNavigator.currentRoute;
          final routePhase = BrandThemeRoutePolicy.resolve(currentRoute);
          final effectivePreset = themeCtrl.normalEffectivePreset;

          Future<void> selectActualTheme() async {
            await DebugSessionController.enable(
              source: normalizedSource,
            );
            if (themeCtrl.debugPresetId != null) {
              await themeCtrl.clearDebugPreset(
                source: normalizedSource,
              );
            } else {
              ThemeDebugTrace.record(
                'debug_actual_theme_reaffirmed',
                source: normalizedSource,
                details: <String, Object?>{
                  ...themeCtrl.debugDetails,
                  'route': currentRoute ?? '-',
                  'routePhase': routePhase.name,
                },
              );
            }
          }

          Future<void> selectPreset(BrandPresetSpec preset) async {
            await DebugSessionController.enable(
              source: normalizedSource,
            );
            if (themeCtrl.debugPresetId != preset.id) {
              await themeCtrl.setDebugPresetId(
                preset.id,
                source: normalizedSource,
              );
            } else {
              ThemeDebugTrace.record(
                'debug_override_reaffirmed',
                source: normalizedSource,
                details: <String, Object?>{
                  ...themeCtrl.debugDetails,
                  'route': currentRoute ?? '-',
                  'routePhase': routePhase.name,
                },
              );
            }
          }

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            title: Row(
              children: <Widget>[
                const Icon(Icons.palette_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '테마',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: duration,
                  child: themeCtrl.debugModeEnabled
                      ? Icon(
                          Icons.bug_report_rounded,
                          key: const ValueKey<String>('theme_dev_mode_on'),
                          size: 18,
                          color: cs.primary,
                        )
                      : const SizedBox.shrink(
                          key: ValueKey<String>('theme_dev_mode_off'),
                        ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    if (reduceMotion) return child;
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.06),
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
                  child: themeCtrl.debugModeEnabled
                      ? BrandThemeDebugSelector(
                          key: const ValueKey<String>(
                            'theme_debug_selector',
                          ),
                          controller: themeCtrl,
                          source: normalizedSource,
                          routePhase: routePhase.name,
                          onSelectActualTheme: selectActualTheme,
                          onSelectPreset: selectPreset,
                        )
                      : _NormalThemeCard(
                          key: const ValueKey<String>('theme_normal_card'),
                          controller: themeCtrl,
                          preset: effectivePreset,
                          duration: duration,
                        ),
                ),
              ),
            ),
            actions: <Widget>[
              AnimatedSwitcher(
                duration: duration,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  if (reduceMotion) return child;
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.96, end: 1.0)
                          .animate(animation),
                      child: child,
                    ),
                  );
                },
                child: themeCtrl.debugModeEnabled
                    ? CommonButton(
                        key: const ValueKey<String>('theme_status_on'),
                        label: 'STATUS',
                        icon: Icons.monitor_heart_outlined,
                        variant: CommonButtonVariant.secondary,
                        minHeight: 44,
                        haptic: CommonHaptic.selection,
                        onPressed: () => ThemeDebugTrace.showStatusDialog(
                          ctx,
                          source: normalizedSource,
                          details: <String, Object?>{
                            ...themeCtrl.debugDetails,
                            'route': currentRoute ?? '-',
                            'routePhase': routePhase.name,
                          },
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey<String>('theme_status_off'),
                      ),
              ),
              CommonButton(
                label: '닫기',
                variant: CommonButtonVariant.tertiary,
                minHeight: 44,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          );
        },
      );
    },
  );

  final closeRoute = AppNavigator.currentRoute;
  final closePhase = BrandThemeRoutePolicy.resolve(closeRoute);
  ThemeDebugTrace.record(
    'dialog_closed',
    source: normalizedSource,
    details: <String, Object?>{
      ...themeController.debugDetails,
      'route': closeRoute ?? '-',
      'routePhase': closePhase.name,
    },
  );
}

class _NormalThemeCard extends StatelessWidget {
  const _NormalThemeCard({
    super.key,
    required this.controller,
    required this.preset,
    required this.duration,
  });

  final ThemePrefsController controller;
  final BrandPresetSpec preset;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.75),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _PresetPreviewDots(colors: preset.preview),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  preset.label,
                  style: text.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: controller.brandThemeEnabled ? 1 : 0,
                duration: duration,
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 18,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ThemeColorBar(
            colors: preset.preview,
            duration: duration,
          ),
        ],
      ),
    );
  }
}

class _PresetPreviewDots extends StatelessWidget {
  const _PresetPreviewDots({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final dots = colors.take(3).toList(growable: false);
    final outline =
        Theme.of(context).colorScheme.outlineVariant.withOpacity(0.6);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(dots.length, (index) {
        return Container(
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
