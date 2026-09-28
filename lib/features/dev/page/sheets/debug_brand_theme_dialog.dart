import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/init/app_navigator.dart';
import '../../../../app/theme/brand_theme.dart';
import '../../../../app/theme/brand_theme_route_policy.dart';
import '../../../../app/theme/theme_debug_trace.dart';
import '../../../../app/theme/theme_prefs_controller.dart';
import '../../../../app/theme/widgets/brand_theme_debug_selector.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../selector/application/dev_auth.dart';
import '../../application/debug_session_controller.dart';

Future<void> showDebugBrandThemeDialog({
  required BuildContext context,
}) async {
  final enabled = await DevAuth.isDevModeEnabled();
  if (!enabled || !context.mounted) return;

  final controller = context.read<ThemePrefsController>();
  final openRoute = AppNavigator.currentRoute;
  final openPhase = BrandThemeRoutePolicy.resolve(openRoute);
  ThemeDebugTrace.record(
    'debug_brand_dialog_open_requested',
    source: 'developer_hub',
    details: <String, Object?>{
      ...controller.debugDetails,
      'route': openRoute ?? '-',
      'routePhase': openPhase.name,
    },
  );

  await showCommonOverlayDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '브랜드 테마',
    builder: (dialogContext) {
      return Consumer<ThemePrefsController>(
        builder: (ctx, themeCtrl, _) {
          final text = Theme.of(ctx).textTheme;
          final currentRoute = AppNavigator.currentRoute;
          final routePhase = BrandThemeRoutePolicy.resolve(currentRoute);

          Future<void> selectActualTheme() async {
            await DebugSessionController.enable(
              source: 'developer_hub_brand_theme',
            );
            if (themeCtrl.debugPresetId != null) {
              await themeCtrl.clearDebugPreset(
                source: 'developer_hub_brand_theme',
              );
            } else {
              ThemeDebugTrace.record(
                'debug_actual_theme_reaffirmed',
                source: 'developer_hub_brand_theme',
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
              source: 'developer_hub_brand_theme',
            );
            if (themeCtrl.debugPresetId != preset.id) {
              await themeCtrl.setDebugPresetId(
                preset.id,
                source: 'developer_hub_brand_theme',
              );
            } else {
              ThemeDebugTrace.record(
                'debug_override_reaffirmed',
                source: 'developer_hub_brand_theme',
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
                    '브랜드 테마',
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
                child: BrandThemeDebugSelector(
                  controller: themeCtrl,
                  source: 'developer_hub_brand_theme',
                  routePhase: routePhase.name,
                  onSelectActualTheme: selectActualTheme,
                  onSelectPreset: selectPreset,
                ),
              ),
            ),
            actions: <Widget>[
              CommonButton(
                label: 'STATUS',
                icon: Icons.monitor_heart_outlined,
                variant: CommonButtonVariant.secondary,
                minHeight: 44,
                haptic: CommonHaptic.selection,
                onPressed: () => ThemeDebugTrace.showStatusDialog(
                  ctx,
                  source: 'developer_hub_brand_theme',
                  details: <String, Object?>{
                    ...themeCtrl.debugDetails,
                    'route': currentRoute ?? '-',
                    'routePhase': routePhase.name,
                  },
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
    'debug_brand_dialog_closed',
    source: 'developer_hub',
    details: <String, Object?>{
      ...controller.debugDetails,
      'route': closeRoute ?? '-',
      'routePhase': closePhase.name,
    },
  );
}
