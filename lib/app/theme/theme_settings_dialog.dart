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
import 'widgets/brand_theme_area_selector.dart';
import 'widgets/brand_theme_debug_selector.dart';

class _ThemeDialogMetrics {
  const _ThemeDialogMetrics({
    required this.viewport,
    required this.tabletLayout,
    required this.reduceMotion,
    required this.maxWidth,
    required this.insetPadding,
  });

  final Size viewport;
  final bool tabletLayout;
  final bool reduceMotion;
  final double maxWidth;
  final EdgeInsets insetPadding;

  factory _ThemeDialogMetrics.of(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final viewport = media?.size ?? Size.zero;
    final tabletLayout = viewport.shortestSide >= 600;
    final horizontalInset = tabletLayout ? 48.0 : 16.0;
    final verticalInset = tabletLayout ? 32.0 : 24.0;
    final widthCap = tabletLayout ? 720.0 : 560.0;
    final availableWidth = viewport.width > 0
        ? viewport.width - horizontalInset * 2 - 40
        : widthCap;
    final maxWidth = availableWidth > 0
        ? (availableWidth < widthCap ? availableWidth : widthCap)
        : widthCap;
    return _ThemeDialogMetrics(
      viewport: viewport,
      tabletLayout: tabletLayout,
      reduceMotion: media?.disableAnimations ?? false,
      maxWidth: maxWidth,
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
    );
  }

  Map<String, Object?> get debugDetails => <String, Object?>{
        'layoutClass': tabletLayout ? 'tablet' : 'phone',
        'viewportWidth': viewport.width.round(),
        'viewportHeight': viewport.height.round(),
        'shortestSide': viewport.shortestSide.round(),
        'dialogMaxWidth': maxWidth.round(),
        'reduceMotion': reduceMotion,
      };
}

Future<void> showCommonThemeSettingsDialog({
  required BuildContext context,
  required String source,
}) async {
  final normalizedSource = source.trim().isEmpty ? 'unknown' : source.trim();
  final themeController = context.read<ThemePrefsController>();
  final openMetrics = _ThemeDialogMetrics.of(context);
  final openRoute = AppNavigator.currentRoute;
  final openPhase = BrandThemeRoutePolicy.resolve(openRoute);
  ThemeDebugTrace.record(
    'dialog_open_requested',
    source: normalizedSource,
    details: <String, Object?>{
      ...themeController.debugDetails,
      ...openMetrics.debugDetails,
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
          final metrics = _ThemeDialogMetrics.of(ctx);
          final reduceMotion = metrics.reduceMotion;
          final duration = reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 240);
          final currentRoute = AppNavigator.currentRoute;
          final routePhase = BrandThemeRoutePolicy.resolve(currentRoute);

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
            insetPadding: metrics.insetPadding,
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
            content: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              width: metrics.maxWidth,
              constraints: BoxConstraints(maxWidth: metrics.maxWidth),
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
                      : BrandThemeAreaSelector(
                          key: const ValueKey<String>(
                            'theme_area_selector',
                          ),
                          controller: themeCtrl,
                          source: normalizedSource,
                          routePhase: routePhase.name,
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
                            ...metrics.debugDetails,
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
      ...openMetrics.debugDetails,
      'route': closeRoute ?? '-',
      'routePhase': closePhase.name,
    },
  );
}
