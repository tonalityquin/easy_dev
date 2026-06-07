import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/init/app_navigator.dart';
import '../../../app/models/capability.dart';
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
    final overlayCtx = state?.overlay?.context;
    return overlayCtx ?? state?.context;
  }

  static Future<void> togglePanel() async {
    if (!_inited) await init();
    final ctx = _bestContext();
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ProductivitySheet.togglePanel());
      return;
    }

    if (_isPanelOpen) {
      Navigator.of(ctx).maybePop();
      return;
    }

    await openPanel();
  }

  static Future<void> openPanel({
    ProductivitySheetTab tab = ProductivitySheetTab.monthly,
  }) async {
    if (!_inited) await init();
    final ctx = _bestContext();
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ProductivitySheet.openPanel(tab: tab));
      return;
    }
    if (_isPanelOpen || _panelFuture != null) return;

    _isPanelOpen = true;
    _panelFuture = showModalBottomSheet(
      context: ctx,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
    final cs = Theme.of(context).colorScheme;

    return FractionallySizedBox(
      heightFactor: 1.0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Material(
          color: cs.surface,
          child: const SafeArea(
            top: false,
            child: Column(
              children: [
                SizedBox(height: 10),
                _SheetTopStrip(),
                SizedBox(height: 8),
                Expanded(child: _MonthlyProductivityBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetTopStrip extends StatelessWidget {
  const _SheetTopStrip();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 46,
            height: 5,
            decoration: BoxDecoration(
              color: cs.outlineVariant.withOpacity(.8),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Positioned(
            right: 10,
            child: IconButton(
              tooltip: '닫기',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyProductivityBody extends StatelessWidget {
  const _MonthlyProductivityBody();

  @override
  Widget build(BuildContext context) {
    final userArea = context.select<UserState, String>((s) => s.currentArea.trim());
    final areaStateArea = context.select<AreaState, String>((s) => s.currentArea.trim());
    final area = MonthlyAreaResolver.resolve(
      userArea: userArea,
      areaStateArea: areaStateArea,
    );
    final canUseMonthly = context.select<AreaState, bool>((s) {
      final stateArea = s.currentArea.trim();
      if (stateArea.isEmpty || stateArea != area) return true;
      return s.capabilitiesOfCurrentArea.contains(Capability.monthly);
    });

    if (area.isEmpty) {
      return const _MonthlyAccessNotice(
        icon: Icons.location_off_rounded,
        title: '지점이 선택되지 않았습니다',
        message: '정기 주차 관리를 사용하려면 먼저 현재 지점을 선택하세요.',
      );
    }
    if (!canUseMonthly) {
      return const _MonthlyAccessNotice(
        icon: Icons.lock_outline_rounded,
        title: '정기 주차 권한이 없습니다',
        message: '현재 지점에서 정기 주차 기능이 열려 있을 때 사용할 수 있습니다.',
      );
    }
    return const MonthlyParkingManagement();
  }
}

class _MonthlyAccessNotice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MonthlyAccessNotice({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.outline),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
