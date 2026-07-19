import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/init/app_navigator.dart';
import '../../../app/models/capability.dart';
import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../account/applications/user_state.dart';
import '../../dev/application/area_state.dart';
import '../../monthly/application/monthly_area_resolver.dart';
import '../../monthly/page/monthly_parking_management.dart';

enum ProductivitySheetTab { monthly, focus, todo, calendar, memo }

class ProductivitySheet {
  ProductivitySheet._();

  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  static final enabled = ValueNotifier<bool>(true);

  static bool _inited = false;
  static bool _isPanelOpen = false;
  static Future<void>? _panelFuture;

  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
  }

  static void mountIfNeeded() {
    if (_inited) return;
    init();
  }

  static BuildContext? _bestContext() {
    final state = navigatorKey.currentState;
    final overlayContext = state?.overlay?.context;
    return overlayContext ?? state?.context;
  }

  static Future<void> togglePanel() async {
    if (!_inited) await init();
    final context = _bestContext();
    if (context == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ProductivitySheet.togglePanel(),
      );
      return;
    }

    if (_isPanelOpen) {
      Navigator.of(context).maybePop();
      return;
    }

    await openPanel();
  }

  static Future<void> openPanel({
    ProductivitySheetTab tab = ProductivitySheetTab.monthly,
  }) async {
    if (!_inited) await init();
    final context = _bestContext();
    if (context == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ProductivitySheet.openPanel(tab: tab),
      );
      return;
    }
    if (_isPanelOpen || _panelFuture != null) return;

    _isPanelOpen = true;
    _panelFuture = showPromptOverlayBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      useRootNavigator: true,
      transparentBackground: true,
      builder: (_) => const _ProductivitySheetBody(),
    ).whenComplete(() {
      _isPanelOpen = false;
      _panelFuture = null;
    });

    await _panelFuture;
  }
}

class _ProductivitySheetBody extends StatelessWidget {
  const _ProductivitySheetBody();

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 1,
      child: PromptSheetScaffold(
        title: '정기 주차',
        icon: Icons.dashboard_customize_rounded,
        onClose: () => Navigator.of(context).maybePop(),
        body: const _MonthlyProductivityBody(),
      ),
    );
  }
}

class _MonthlyProductivityBody extends StatelessWidget {
  const _MonthlyProductivityBody();

  @override
  Widget build(BuildContext context) {
    final userArea =
        context.select<UserState, String>((state) => state.currentArea.trim());
    final selectedArea =
        context.select<AreaState, String>((state) => state.currentArea.trim());
    final area = MonthlyAreaResolver.resolve(
      userArea: userArea,
      areaStateArea: selectedArea,
    );
    final canUseMonthly = context.select<AreaState, bool>((state) {
      final stateArea = state.currentArea.trim();
      if (stateArea.isEmpty || stateArea != area) return true;
      return state.capabilitiesOfCurrentArea.contains(Capability.monthly);
    });

    return AnimatedSwitcher(
      duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
          ? Duration.zero
          : PromptUiMotion.component,
      switchInCurve: PromptUiMotion.enter,
      switchOutCurve: PromptUiMotion.exit,
      child: area.isEmpty
          ? const _MonthlyAccessNotice(
              key: ValueKey<String>('area-empty'),
              icon: Icons.location_off_rounded,
              title: '지점이 선택되지 않았습니다',
              message: '정기 주차 관리를 사용하려면 먼저 현재 지점을 선택하세요.',
            )
          : !canUseMonthly
              ? const _MonthlyAccessNotice(
                  key: ValueKey<String>('permission-denied'),
                  icon: Icons.lock_outline_rounded,
                  title: '정기 주차 권한이 없습니다',
                  message: '현재 지점에서 정기 주차 기능이 열려 있을 때 사용할 수 있습니다.',
                )
              : const MonthlyParkingManagement(
                  key: ValueKey<String>('monthly-management'),
                ),
    );
  }
}

class _MonthlyAccessNotice extends StatelessWidget {
  const _MonthlyAccessNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return PromptAnimatedReveal(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: BorderRadius.circular(PromptUiShapes.card),
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: tokens.warningContainer,
                    borderRadius:
                        BorderRadius.circular(PromptUiShapes.control),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 30, color: tokens.warning),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
