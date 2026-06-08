import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../app/init/app_exit_service.dart';
import '../../../../../app/init/logout_helper.dart';
import '../../../../../app/utils/ops_delayed_refresh_gate.dart';
import '../../../../../app/theme/brand_theme.dart';
import '../../../../../app/utils/dev_firebase_debug_dialog.dart';
import '../../../../../app/theme/theme_prefs_controller.dart';
import '../../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../../dev/application/area_state.dart';
import '../../../../location/applications/location_state.dart';
import '../../../../payment/applications/bill_state.dart';
import '../../../applications/tablet_pad_mode_state.dart';
import '../../../applications/tablet_parking_completed_view_toggle_state.dart';
import '../../../applications/tablet_work_session_state.dart';

class TabletTopNavigation extends StatefulWidget {
  final bool isAreaSelectable;

  const TabletTopNavigation({
    super.key,
    this.isAreaSelectable = true,
  });

  @override
  State<TabletTopNavigation> createState() => _TabletTopNavigationState();
}

class _TabletTopNavigationState extends State<TabletTopNavigation> {
  static const String _prefsHasMonthlyKey = 'has_monthly_parking';

  bool _refreshing = false;
  DateTime? _lastRefreshAt;

  Color _tintOnSurface(ColorScheme cs, double opacity) {
    return Color.alphaBlend(cs.primary.withOpacity(opacity), cs.surface);
  }

  ButtonStyle _accentOutlinedBtnStyle(BuildContext context,
      {double minHeight = 48}) {
    final cs = Theme.of(context).colorScheme;

    return ElevatedButton.styleFrom(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      minimumSize: Size(double.infinity, minHeight),
      padding: EdgeInsets.zero,
      elevation: 0,
      side: BorderSide(color: cs.primary.withOpacity(0.85), width: 1.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed)
            ? cs.primary
            .withOpacity(cs.brightness == Brightness.dark ? 0.12 : 0.08)
            : null,
      ),
    );
  }

  String _themeModeLabel(String id) {
    return themeModeSpecs()
        .firstWhere((m) => m.id == id, orElse: () => themeModeSpecs().first)
        .label;
  }

  String _formatLastSync(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = dt.toLocal();
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<bool?> _syncHasMonthlyParkingFlag() async {
    final area = context.read<AreaState>().currentArea.trim();

    if (area.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsHasMonthlyKey, false);
      return false;
    }

    try {
      final repo = context.read<PlateRepository>();
      final exists = await repo.hasMonthlyParkingByArea(area: area);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsHasMonthlyKey, exists);

      return exists;
    } catch (e, st) {
      debugPrint('월주차 존재 여부 확인 실패: $e');
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'tablet.monthly_plate_status.exists',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'area': area,
          'widget': 'TabletTopNavigation',
        },
      );
      return null;
    }
  }

  Future<void> _manualRefreshAll({
    StateSetter? setDialogState,
    BuildContext? dialogContext,
  }) async {
    if (_refreshing) return;

    void refreshDialog() {
      if (dialogContext != null && dialogContext.mounted) {
        setDialogState?.call(() {});
      }
    }

    setState(() => _refreshing = true);
    refreshDialog();

    try {
      final shouldRefresh = await OpsDelayedRefreshGate.waitIfNeeded(
        context: context,
        title: '데이터 새로고침',
        message: '주차 구역, 정산 데이터, 월정기 사용 여부를 새로고침하기 전 요청을 준비하고 있습니다.',
      );
      if (!shouldRefresh || !mounted) return;

      final locationState = context.read<LocationState>();
      final billState = context.read<BillState>();

      await locationState.manualLocationRefresh();
      await billState.manualBillRefresh();
      await _syncHasMonthlyParkingFlag();

      if (!mounted) return;

      setState(() => _lastRefreshAt = DateTime.now());
      refreshDialog();
      debugPrint('데이터를 새로고침했습니다.');
    } catch (e, st) {
      debugPrint('수동 새로고침 실패: $e');
      if (!mounted) return;
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'tablet.manualRefreshAll',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'area': context.read<AreaState>().currentArea.trim(),
          'widgets': 'LocationState.manualLocationRefresh, BillState.manualBillRefresh, monthly_plate_status',
          'widget': 'TabletTopNavigation',
        },
      );
      refreshDialog();
      debugPrint('새로고침 실패: $e');
    } finally {
      if (!mounted) return;
      setState(() => _refreshing = false);
      refreshDialog();
    }
  }

  Future<void> _openThemeSettingsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Consumer<ThemePrefsController>(
          builder: (ctx, themeCtrl, _) {
            final cs = Theme.of(ctx).colorScheme;
            final text = Theme.of(ctx).textTheme;

            final modes = themeModeSpecs();
            final presets = brandPresets();

            return AlertDialog(
              insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              title: Row(
                children: [
                  const Icon(Icons.tune_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '테마 설정',
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
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
                    children: [
                      Text(
                        '테마 모드(시스템/라이트/다크)와 색 프리셋을 선택하면 앱 전체에 즉시 적용됩니다.',
                        style: text.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '테마 모드',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: modes.map((m) {
                          final selected = m.id == themeCtrl.themeModeId;
                          return ChoiceChip(
                            selected: selected,
                            onSelected: (_) async {
                              HapticFeedback.selectionClick();
                              await themeCtrl.setThemeModeId(m.id);
                            },
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(m.icon, size: 16),
                                const SizedBox(width: 6),
                                Text(m.label),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      Divider(
                          height: 1, color: cs.outlineVariant.withOpacity(0.7)),
                      const SizedBox(height: 14),
                      Text(
                        '테마 색(프리셋)',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '컨셉 컬러는 포인트(primary)만 변경되고, 표면(surfaces)은 중립으로 유지됩니다.',
                        style: text.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: presets.map((p) {
                          final selected = p.id == themeCtrl.presetId;
                          return ChoiceChip(
                            selected: selected,
                            onSelected: (_) async {
                              HapticFeedback.selectionClick();
                              await themeCtrl.setPresetId(p.id);
                            },
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _PresetPreviewDots(colors: p.preview),
                                const SizedBox(width: 8),
                                Text(p.label),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: cs.outlineVariant.withOpacity(0.75)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: cs.onSurfaceVariant, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '현재: ${_themeModeLabel(themeCtrl.themeModeId)} / ${presetById(themeCtrl.presetId).label}',
                                style: text.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('닫기'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedArea = context.watch<AreaState>().currentArea;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final overlay = MaterialStateProperty.resolveWith<Color?>(
          (states) {
        if (states.contains(MaterialState.pressed)) {
          return cs.primary
              .withOpacity(cs.brightness == Brightness.dark ? 0.14 : 0.10);
        }
        if (states.contains(MaterialState.hovered) ||
            states.contains(MaterialState.focused)) {
          return cs.primary
              .withOpacity(cs.brightness == Brightness.dark ? 0.10 : 0.06);
        }
        return null;
      },
    );

    return Material(
      color: cs.surface,
      child: InkWell(
        onTap: widget.isAreaSelectable ? () => _openTopNavDialog(context) : null,
        overlayColor: overlay,
        child: SizedBox(
          width: double.infinity,
          height: kToolbarHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.car, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                (selectedArea.trim().isNotEmpty) ? selectedArea : '지역 없음',
                style: (text.titleMedium ?? const TextStyle()).copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              if (widget.isAreaSelectable) ...[
                const SizedBox(width: 4),
                Icon(CupertinoIcons.chevron_down,
                    size: 14, color: cs.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTopNavDialog(BuildContext context) async {
    final area = context.read<AreaState>().currentArea;
    final padMode = context.read<TabletPadModeState>().mode;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        final cs = Theme.of(dialogCtx).colorScheme;
        final text = Theme.of(dialogCtx).textTheme;

        Color tint(double opacity) => _tintOnSurface(cs, opacity);

        Color bgForMode(PadMode m) {
          final dark = cs.brightness == Brightness.dark;
          switch (m) {
            case PadMode.big:
              return tint(dark ? 0.10 : 0.05);
            case PadMode.small:
              return tint(dark ? 0.14 : 0.07);
            case PadMode.show:
              return tint(dark ? 0.08 : 0.04);
            case PadMode.mobile:
              return tint(dark ? 0.12 : 0.06);
            case PadMode.gridPad:
              return tint(dark ? 0.15 : 0.075);
            case PadMode.grid:
              return tint(dark ? 0.16 : 0.08);
          }
        }

        Widget modeButton({
          required PadMode target,
          required String title,
          required String subtitle,
          required IconData icon,
        }) {
          final bool selected = padMode == target;

          final sideColor = selected ? cs.primary : cs.outlineVariant;
          final bg = bgForMode(target);

          return SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                dialogCtx.read<TabletPadModeState>().setMode(target);
                Navigator.of(dialogCtx, rootNavigator: true).pop();
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                side: BorderSide(
                  color: sideColor.withOpacity(selected ? 0.95 : 0.85),
                  width: selected ? 1.5 : 1.0,
                ),
                backgroundColor: bg,
                foregroundColor: cs.onSurface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ).copyWith(
                overlayColor: MaterialStateProperty.resolveWith<Color?>(
                      (states) => states.contains(MaterialState.pressed)
                      ? cs.primary.withOpacity(
                      cs.brightness == Brightness.dark ? 0.14 : 0.10)
                      : null,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: (text.bodyLarge ?? const TextStyle()).copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: (text.bodySmall ?? const TextStyle()).copyWith(
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check_circle, color: cs.primary),
                  ],
                ],
              ),
            ),
          );
        }

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: cs.surface,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.of(dialogCtx).size.height * 0.85,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: StatefulBuilder(
                builder: (innerCtx, setSB) {
                  final headerIconBg =
                  tint(cs.brightness == Brightness.dark ? 0.18 : 0.10);

                  final infoBg =
                  tint(cs.brightness == Brightness.dark ? 0.12 : 0.06);
                  final infoBorder = cs.primary.withOpacity(
                    cs.brightness == Brightness.dark ? 0.28 : 0.20,
                  );

                  final sectionTitleStyle =
                  (text.labelLarge ?? const TextStyle()).copyWith(
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  );

                  final parkingCompletedToggle =
                      innerCtx.watch<TabletParkingCompletedViewToggleState>();
                  final includeParkingCompletedView =
                      parkingCompletedToggle.includeParkingCompletedView;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: headerIconBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: cs.outline.withOpacity(.10)),
                            ),
                            child: Icon(CupertinoIcons.car,
                                color: cs.primary, size: 18),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '상단 메뉴',
                            style: (text.titleMedium ?? const TextStyle())
                                .copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            tooltip: '닫기',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: infoBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: infoBorder),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.map,
                                        size: 18, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '현재 지역: ${(area.trim().isNotEmpty) ? area : "지역 없음"}',
                                        style: (text.bodyMedium ??
                                            const TextStyle())
                                            .copyWith(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: cs.onSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text('업무 상태', style: sectionTitleStyle),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () async {
                                    final navigator = Navigator.of(dialogCtx);
                                    final workState =
                                        context.read<TabletWorkSessionState>();
                                    HapticFeedback.selectionClick();
                                    await workState.stopWork();
                                    navigator.pop();
                                    await Future<void>.delayed(
                                      const Duration(milliseconds: 32),
                                    );
                                    if (!context.mounted) return;
                                    await AppExitService.exitApp(context);
                                  },
                                  icon: const Icon(Icons.power_settings_new),
                                  label: const Text('업무 종료'),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(50),
                                    backgroundColor: cs.errorContainer,
                                    foregroundColor: cs.onErrorContainer,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '로컬에 태블릿 모드 사용 종료 상태를 저장한 뒤 현재 view 컬렉션 구독을 끊고 앱을 종료합니다.',
                                style: (text.bodySmall ?? const TextStyle()).copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text('화면 모드', style: sectionTitleStyle),
                              ),
                              const SizedBox(height: 8),
                              modeButton(
                                target: PadMode.big,
                                title: 'Big Pad (기본)',
                                subtitle: '왼쪽: 출차 요청 / 오른쪽: 검색 + 키패드(하단 45%)',
                                icon: Icons.dashboard_customize_outlined,
                              ),
                              const SizedBox(height: 8),
                              modeButton(
                                target: PadMode.small,
                                title: 'Small Pad',
                                subtitle: '왼쪽 유지 / 오른쪽: 키패드가 패널 높이 100%',
                                icon: Icons.keyboard_alt_outlined,
                              ),
                              const SizedBox(height: 8),
                              modeButton(
                                target: PadMode.show,
                                title: 'Show',
                                subtitle: '왼쪽 패널만 전체 화면(출차 요청 차량만 표시)',
                                icon: Icons.view_list_outlined,
                              ),
                              const SizedBox(height: 8),
                              modeButton(
                                target: PadMode.mobile,
                                title: 'Mobile',
                                subtitle:
                                '단일 화면: 상단 입력 표시 + 하단 키패드(좌/우 패널 분할 없음)',
                                icon: Icons.phone_iphone_outlined,
                              ),
                              const SizedBox(height: 8),
                              modeButton(
                                target: PadMode.gridPad,
                                title: 'Grid Pad',
                                subtitle: '왼쪽: 2D 주차 그리드 / 오른쪽: 번호판 검색',
                                icon: Icons.grid_view_outlined,
                              ),
                              const SizedBox(height: 8),
                              modeButton(
                                target: PadMode.grid,
                                title: 'Grid',
                                subtitle: '3D 주차 그리드 미리보기를 전체 화면으로 표시',
                                icon: Icons.grid_view_rounded,
                              ),
                              const SizedBox(height: 20),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text('그리드 색 반영', style: sectionTitleStyle),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: cs.outlineVariant.withOpacity(.85),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '입차 완료 view 구독',
                                            style: (text.bodyMedium ??
                                                    const TextStyle())
                                                .copyWith(
                                              color: cs.onSurface,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            includeParkingCompletedView
                                                ? 'ON 상태에서는 parking_completed_view를 함께 구독하여 주차 완료 구역 색을 반영합니다.'
                                                : 'OFF 상태에서는 departure_requests_view만 반영합니다. 설정은 앱 재실행 후에도 유지됩니다.',
                                            style: (text.bodySmall ??
                                                    const TextStyle())
                                                .copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Switch.adaptive(
                                      value: includeParkingCompletedView,
                                      onChanged: (next) async {
                                        HapticFeedback.selectionClick();
                                        await parkingCompletedToggle
                                            .setIncludeParkingCompletedView(
                                          next,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text('테마', style: sectionTitleStyle),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.palette_outlined),
                                  label: const Text('테마 설정(다크/색상)'),
                                  style: _accentOutlinedBtnStyle(innerCtx,
                                      minHeight: 48),
                                  onPressed: () async {
                                    Navigator.of(dialogCtx).pop();
                                    await _openThemeSettingsDialog(context);
                                  },
                                ),
                              ),
                              const SizedBox(height: 20),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text('데이터 새로고침', style: sectionTitleStyle),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color:
                                      cs.outlineVariant.withOpacity(.85)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '주차 구역/정산 데이터를 수동으로 동기화합니다.',
                                            style: (text.bodyMedium ??
                                                const TextStyle())
                                                .copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w700,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                        if (_refreshing)
                                          const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        else if (_lastRefreshAt != null)
                                          _DialogPill(
                                            text:
                                            '마지막: ${_formatLastSync(_lastRefreshAt!)}',
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: _refreshing
                                            ? null
                                            : () => _manualRefreshAll(
                                          setDialogState: setSB,
                                          dialogContext: innerCtx,
                                        ),
                                        icon: _refreshing
                                            ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child:
                                          CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                            AlwaysStoppedAnimation<
                                                Color>(
                                              cs.onPrimary,
                                            ),
                                          ),
                                        )
                                            : const Icon(Icons.sync),
                                        label: const Text('지금 새로고침'),
                                        style: FilledButton.styleFrom(
                                          minimumSize:
                                          const Size.fromHeight(48),
                                          backgroundColor: cs.primary,
                                          foregroundColor: cs.onPrimary,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                            BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: Icon(Icons.logout, color: cs.primary),
                                  label: Text(
                                    '로그아웃',
                                    style:
                                    (text.labelLarge ?? const TextStyle())
                                        .copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  onPressed: () async {
                                    Navigator.of(dialogCtx).pop();
                                    await _logout(context);
                                  },
                                  style: OutlinedButton.styleFrom(
                                    minimumSize:
                                    const Size(double.infinity, 48),
                                    backgroundColor: cs.surface,
                                    foregroundColor: cs.onSurface,
                                    side: BorderSide(
                                        color:
                                        cs.outlineVariant.withOpacity(.85)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ).copyWith(
                                    overlayColor: MaterialStateProperty
                                        .resolveWith<Color?>(
                                          (states) => states
                                          .contains(MaterialState.pressed)
                                          ? cs.primary.withOpacity(
                                        cs.brightness == Brightness.dark
                                            ? 0.12
                                            : 0.08,
                                      )
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          child: Text(
                            '닫기',
                            style:
                            (text.labelLarge ?? const TextStyle()).copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _logout(BuildContext context) async {
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: true,
      delay: const Duration(seconds: 1),
    );
  }
}

class _DialogPill extends StatelessWidget {
  const _DialogPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(.85)),
      ),
      child: Text(
        text,
        style: (tt.labelSmall ?? const TextStyle(fontSize: 11.5)).copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PresetPreviewDots extends StatelessWidget {
  const _PresetPreviewDots({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final dots = colors.take(3).toList();
    final outline =
    Theme.of(context).colorScheme.outlineVariant.withOpacity(0.6);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(dots.length, (i) {
        final c = dots[i];
        return Container(
          width: 10,
          height: 10,
          margin: EdgeInsets.only(right: i == dots.length - 1 ? 0 : 4),
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: outline),
          ),
        );
      }),
    );
  }
}
