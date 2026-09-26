import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../design_system/common_ui/common_ui_components.dart';
import '../../design_system/common_ui/common_ui_overlays.dart';
import '../../features/selector/application/dev_auth.dart';
import 'brand_theme.dart';
import 'theme_debug_trace.dart';
import 'theme_prefs_controller.dart';

Future<void> showCommonThemeSettingsDialog({
  required BuildContext context,
  required String source,
}) async {
  final normalizedSource = source.trim().isEmpty ? 'unknown' : source.trim();
  final themeController = context.read<ThemePrefsController>();
  unawaited(DevAuth.isDevModeEnabled());
  ThemeDebugTrace.record(
    'dialog_open_requested',
    source: normalizedSource,
    details: themeController.debugDetails,
  );

  await showCommonOverlayDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '테마 설정',
    builder: (dialogContext) {
      return Consumer<ThemePrefsController>(
        builder: (ctx, themeCtrl, _) {
          final cs = Theme.of(ctx).colorScheme;
          final text = Theme.of(ctx).textTheme;
          final reduceMotion =
              MediaQuery.maybeOf(ctx)?.disableAnimations ?? false;
          final duration = reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 220);
          final presets = brandPresets();
          final effectivePreset = themeCtrl.effectivePreset;

          Widget animatedChoice({
            required bool selected,
            required Widget child,
          }) {
            return AnimatedScale(
              scale: selected ? 1.025 : 1.0,
              duration: duration,
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: selected ? 1.0 : 0.92,
                duration: duration,
                curve: Curves.easeOutCubic,
                child: child,
              ),
            );
          }

          return AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            title: Row(
              children: <Widget>[
                const Icon(Icons.palette_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '테마 설정',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        animatedChoice(
                          selected: themeCtrl.isAutomatic,
                          child: ChoiceChip(
                            selected: themeCtrl.isAutomatic,
                            onSelected: (selected) async {
                              if (!selected || themeCtrl.isAutomatic) return;
                              await HapticFeedback.selectionClick();
                              ThemeDebugTrace.record(
                                'automatic_requested',
                                source: normalizedSource,
                                details: themeCtrl.debugDetails,
                              );
                              await themeCtrl.clearPresetOverride(
                                source: normalizedSource,
                              );
                            },
                            label: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(Icons.auto_awesome_rounded, size: 16),
                                SizedBox(width: 6),
                                Text('자동'),
                              ],
                            ),
                          ),
                        ),
                        for (final preset in presets)
                          animatedChoice(
                            selected: !themeCtrl.isAutomatic &&
                                themeCtrl.presetId == preset.id,
                            child: ChoiceChip(
                              selected: !themeCtrl.isAutomatic &&
                                  themeCtrl.presetId == preset.id,
                              onSelected: (selected) async {
                                if (!selected ||
                                    (!themeCtrl.isAutomatic &&
                                        themeCtrl.presetId == preset.id)) {
                                  return;
                                }
                                await HapticFeedback.selectionClick();
                                ThemeDebugTrace.record(
                                  'theme_preset_change_requested',
                                  source: normalizedSource,
                                  details: <String, Object?>{
                                    ...themeCtrl.debugDetails,
                                    'target': preset.id,
                                  },
                                );
                                await themeCtrl.setPresetId(
                                  preset.id,
                                  source: normalizedSource,
                                );
                              },
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  _PresetPreviewDots(colors: preset.preview),
                                  const SizedBox(width: 8),
                                  Text(preset.label),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
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
                      child: Container(
                        key: ValueKey<String>(
                          '${themeCtrl.selectedArea}:${themeCtrl.isAutomatic}:${themeCtrl.presetId}',
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: cs.outlineVariant.withOpacity(0.75),
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            _PresetPreviewDots(
                              colors: effectivePreset.preview,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                themeCtrl.isAutomatic
                                    ? '자동 / ${effectivePreset.label}'
                                    : effectivePreset.label,
                                style: text.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              ValueListenableBuilder<bool>(
                valueListenable: DevAuth.devModeEnabled,
                builder: (context, enabled, _) {
                  return AnimatedSwitcher(
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
                    child: enabled
                        ? CommonButton(
                            key: const ValueKey<String>('theme_debug_on'),
                            label: 'DEBUG',
                            icon: Icons.bug_report_outlined,
                            variant: CommonButtonVariant.secondary,
                            minHeight: 44,
                            haptic: CommonHaptic.selection,
                            onPressed: () => ThemeDebugTrace.showStatusDialog(
                              ctx,
                              source: normalizedSource,
                              details: themeCtrl.debugDetails,
                            ),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey<String>('theme_debug_off'),
                          ),
                  );
                },
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

  ThemeDebugTrace.record(
    'dialog_closed',
    source: normalizedSource,
    details: themeController.debugDetails,
  );
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
