import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';

import '../../../../../app/init/app_exit_service.dart';
import '../../../../../app/init/logout_helper.dart';
import '../../../../../app/utils/operational_data_sync_workflow.dart';
import '../../../../../app/utils/status_dialog.dart';
import '../../../../../app/theme/brand_theme.dart';
import '../../../../../app/theme/theme_prefs_controller.dart';
import '../../../../dev/application/area_state.dart';
import '../../../../sector/applications/sector_state.dart';
import '../../../../selector/application/dev_auth.dart';
import '../../../applications/tablet_grid_render_mode_state.dart';
import '../../../applications/tablet_pad_mode_state.dart';
import '../../../applications/tablet_parking_completed_view_toggle_state.dart';
import '../../../applications/tablet_plate_tail4_size_state.dart';
import '../../../applications/tablet_work_session_state.dart';
import '../../widgets/tablet_common_components.dart';

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
  final List<String> _settingsDebugLines = <String>[];
  bool _settingsDebugDialogShowing = false;

  bool _refreshing = false;
  DateTime? _lastRefreshAt;
  int? _localSectorCount;


  @override
  void initState() {
    super.initState();
    _loadSyncSnapshot();
  }

  Future<void> _loadSyncSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final value = DateTime.tryParse(
      prefs.getString(OperationalDataSyncWorkflow.lastSyncAtKey) ?? '',
    );
    final area = context.read<AreaState>().currentArea.trim();
    final sectorCount = SectorState.cachedCountOf(prefs, area);
    debugPrint(
      '[TabletTopNavigation] 로컬 동기화 상태 로드: '
      'area=$area, sectorCount=${sectorCount ?? -1}, syncedAt=$value',
    );
    if (!mounted) return;
    setState(() {
      _lastRefreshAt = value;
      _localSectorCount = sectorCount;
    });
  }

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
      final result = await OperationalDataSyncWorkflow.run(
        context: context,
        title: '데이터 새로고침',
        message: '주차 구역, 섹터, 정산 데이터, 월정기 사용 여부를 새로고침하기 전 요청을 준비하고 있습니다.',
        useCommonUi: true,
      );
      if (result == OperationalDataSyncResult.completed && mounted) {
        await _loadSyncSnapshot();
        refreshDialog();
      }
    } finally {
      if (!mounted) return;
      setState(() => _refreshing = false);
      refreshDialog();
    }
  }

  Future<void> _openThemeSettingsDialog(BuildContext context) async {
    await showCommonOverlayDialog<void>(
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
              actions: <Widget>[
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

  void _settingsDebugLog(
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {
    final buffer = StringBuffer()
      ..write('[TabletTopNavigation] ')
      ..write(DateTime.now().toIso8601String())
      ..write(' event=')
      ..write(event);
    for (final entry in details.entries) {
      if (entry.value == null) continue;
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('=')
        ..write(entry.value);
    }
    final line = buffer.toString();
    _settingsDebugLines.add(line);
    if (_settingsDebugLines.length > 120) {
      _settingsDebugLines.removeRange(0, _settingsDebugLines.length - 120);
    }
    debugPrint(line);
  }

  String get _settingsDebugPrintCode => _settingsDebugLines
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');

  Future<void> _showSettingsDeveloperDebugDialog(
    BuildContext dialogContext, {
    required String title,
  }) async {
    if (!mounted ||
        !dialogContext.mounted ||
        _settingsDebugDialogShowing ||
        _settingsDebugLines.isEmpty) {
      return;
    }
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled ||
        !mounted ||
        !dialogContext.mounted ||
        _settingsDebugDialogShowing) {
      return;
    }
    final code = _settingsDebugPrintCode.trim();
    if (code.isEmpty) return;
    _settingsDebugDialogShowing = true;
    try {
      await StatusDialog.showSuccess(
        dialogContext,
        title: title,
        description: _settingsDebugLines.join('\n'),
        copyText: code,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: const Duration(seconds: 45),
        useCommonUi: true,
      );
    } finally {
      _settingsDebugDialogShowing = false;
    }
  }

  Future<void> _setGridRenderMode(
    BuildContext dialogContext,
    TabletGridRenderMode next,
  ) async {
    final state = dialogContext.read<TabletGridRenderModeState>();
    if (!state.isReady || state.mode == next) return;
    final previous = state.mode;
    final area = context.read<AreaState>().currentArea.trim();
    HapticFeedback.selectionClick();
    _settingsDebugLog(
      'grid_render_mode_change_requested',
      <String, Object?>{
        'from': previous.name,
        'to': next.name,
        'area': area,
      },
    );
    await state.setMode(next);
    if (!mounted || !dialogContext.mounted) return;
    _settingsDebugLog(
      'grid_render_mode_changed',
      <String, Object?>{
        'mode': next.name,
        'persistKey': TabletGridRenderModeState.prefsKey,
        'area': area,
      },
    );
    await _showSettingsDeveloperDebugDialog(
      dialogContext,
      title: next == TabletGridRenderMode.threeD
          ? '3D 주차장 전환 디버그'
          : '2D 도면 전환 디버그',
    );
  }

  Future<void> _setPlateTail4Size(
    BuildContext dialogContext,
    TabletPlateTail4Size next,
  ) async {
    final state = dialogContext.read<TabletPlateTail4SizeState>();
    if (!state.isReady || state.size == next) return;
    final previous = state.size;
    final area = context.read<AreaState>().currentArea.trim();
    HapticFeedback.selectionClick();
    _settingsDebugLog(
      'plate_tail4_size_change_requested',
      <String, Object?>{
        'from': previous.name,
        'to': next.name,
        'fontSize': next.fontSize,
        'area': area,
      },
    );
    await state.setSize(next);
    if (!mounted || !dialogContext.mounted) return;
    _settingsDebugLog(
      'plate_tail4_size_changed',
      <String, Object?>{
        'size': next.name,
        'fontSize': next.fontSize,
        'persistKey': TabletPlateTail4SizeState.prefsKey,
        'area': area,
      },
    );
    await _showSettingsDeveloperDebugDialog(
      dialogContext,
      title: '차량번호 숫자 크기 디버그',
    );
  }

  Future<void> _openTopNavDialog(BuildContext context) async {
    final area = context.read<AreaState>().currentArea;
    final padMode = context.read<TabletPadModeState>().mode;

    await showCommonOverlayDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        final cs = Theme.of(dialogCtx).colorScheme;
        final text = Theme.of(dialogCtx).textTheme;
        final tokens = CommonUiTheme.of(dialogCtx);

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
          final selected = padMode == target;
          return Semantics(
            button: true,
            selected: selected,
            label: '$title, $subtitle',
            child: AnimatedContainer(
              duration: tabletCommonDuration(
                dialogCtx,
                CommonUiMotion.selection,
              ),
              curve: CommonUiMotion.standard,
              width: double.infinity,
              decoration: BoxDecoration(
                color: selected ? tokens.surfaceSelected : bgForMode(target),
                borderRadius: BorderRadius.circular(CommonUiShapes.button),
                border: Border.all(
                  color: selected ? tokens.accent : tokens.borderSubtle,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Material(
                color: tokens.transparent,
                borderRadius: BorderRadius.circular(CommonUiShapes.button),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    dialogCtx.read<TabletPadModeState>().setMode(target);
                    Navigator.of(dialogCtx, rootNavigator: true).pop();
                  },
                  borderRadius: BorderRadius.circular(CommonUiShapes.button),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 58),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(icon, color: tokens.accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  title,
                                  style: text.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  subtitle,
                                  style: text.bodySmall?.copyWith(
                                    color: tokens.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: tabletCommonDuration(
                              dialogCtx,
                              CommonUiMotion.selection,
                            ),
                            child: selected
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    key: const ValueKey<String>('selected'),
                                    color: tokens.accent,
                                  )
                                : const SizedBox.shrink(
                                    key: ValueKey<String>('unselected'),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
                  final gridRenderState =
                      innerCtx.watch<TabletGridRenderModeState>();
                  final plateTail4SizeState =
                      innerCtx.watch<TabletPlateTail4SizeState>();

                  Widget plateTail4SizeButton(TabletPlateTail4Size target) {
                    final selected = plateTail4SizeState.size == target;
                    final duration = tabletCommonDuration(
                      innerCtx,
                      CommonUiMotion.selection,
                    );
                    return Expanded(
                      child: Semantics(
                        button: true,
                        selected: selected,
                        label: '${target.label} 크기',
                        child: AnimatedContainer(
                          duration: duration,
                          curve: CommonUiMotion.standard,
                          constraints: const BoxConstraints(minHeight: 48),
                          decoration: BoxDecoration(
                            color: selected
                                ? tokens.surfaceSelected
                                : tokens.surface,
                            borderRadius:
                                BorderRadius.circular(CommonUiShapes.button),
                            border: Border.all(
                              color: selected
                                  ? tokens.accent
                                  : tokens.borderSubtle,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Material(
                            color: tokens.transparent,
                            borderRadius:
                                BorderRadius.circular(CommonUiShapes.button),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: !plateTail4SizeState.isReady || selected
                                  ? null
                                  : () => _setPlateTail4Size(
                                        innerCtx,
                                        target,
                                      ),
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: duration,
                                  curve: CommonUiMotion.standard,
                                  style: (text.labelLarge ?? const TextStyle())
                                      .copyWith(
                                    color: selected
                                        ? tokens.accent
                                        : tokens.textPrimary,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  child: Text(target.label),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  Widget plateTail4Preview() {
                    final duration = tabletCommonDuration(
                      innerCtx,
                      CommonUiMotion.component,
                    );
                    final fontSize = plateTail4SizeState.isReady
                        ? plateTail4SizeState.fontSize
                        : TabletPlateTail4Size.standard.fontSize;
                    return Center(
                      child: AnimatedSize(
                        duration: duration,
                        curve: CommonUiMotion.standard,
                        child: AnimatedContainer(
                          duration: duration,
                          curve: CommonUiMotion.standard,
                          padding: EdgeInsets.symmetric(
                            horizontal:
                                (fontSize * 0.44).clamp(11.0, 18.0).toDouble(),
                            vertical:
                                (fontSize * 0.30).clamp(8.0, 14.0).toDouble(),
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surfaceRaised,
                            borderRadius:
                                BorderRadius.circular(CommonUiShapes.card),
                            border: Border.all(color: tokens.accent),
                          ),
                          child: AnimatedDefaultTextStyle(
                            duration: duration,
                            curve: CommonUiMotion.standard,
                            style: (text.headlineSmall ?? const TextStyle())
                                .copyWith(
                              fontSize: fontSize,
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                            child: const Text(
                              '8888',
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  Widget gridRenderButton({
                    required TabletGridRenderMode target,
                    required String title,
                    required IconData icon,
                  }) {
                    final selected = gridRenderState.mode == target;
                    final duration = tabletCommonDuration(
                      innerCtx,
                      CommonUiMotion.selection,
                    );
                    return Expanded(
                      child: Semantics(
                        button: true,
                        selected: selected,
                        label: title,
                        child: AnimatedContainer(
                          duration: duration,
                          curve: CommonUiMotion.standard,
                          decoration: BoxDecoration(
                            color: selected
                                ? tokens.surfaceSelected
                                : tokens.surface,
                            borderRadius:
                                BorderRadius.circular(CommonUiShapes.button),
                            border: Border.all(
                              color: selected
                                  ? tokens.accent
                                  : tokens.borderSubtle,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Material(
                            color: tokens.transparent,
                            borderRadius:
                                BorderRadius.circular(CommonUiShapes.button),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: !gridRenderState.isReady || selected
                                  ? null
                                  : () => _setGridRenderMode(
                                        innerCtx,
                                        target,
                                      ),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(minHeight: 58),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      AnimatedScale(
                                        duration: duration,
                                        curve: CommonUiMotion.standard,
                                        scale: selected ? 1.08 : 1,
                                        child: Icon(
                                          icon,
                                          color: selected
                                              ? tokens.accent
                                              : tokens.iconSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          title,
                                          style: text.bodyLarge?.copyWith(
                                            color: tokens.textPrimary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      AnimatedSwitcher(
                                        duration: duration,
                                        child: selected
                                            ? Icon(
                                                Icons.check_circle_rounded,
                                                key: ValueKey<String>(
                                                  'grid-render-${target.name}',
                                                ),
                                                color: tokens.accent,
                                              )
                                            : const SizedBox.shrink(
                                                key: ValueKey<String>(
                                                  'grid-render-unselected',
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

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
                          CommonIconButton(
                            icon: Icons.close_rounded,
                            tooltip: '닫기',
                            onPressed: () => Navigator.of(dialogCtx).pop(),
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
                                    await AppExitService.exitApp(
                                      context,
                                      useCommonUi: true,
                                    );
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
                                subtitle: '전체 화면 주차장 보기',
                                icon: Icons.grid_view_rounded,
                              ),
                              const SizedBox(height: 20),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '차량번호 숫자 크기',
                                  style: sectionTitleStyle,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: <Widget>[
                                  plateTail4SizeButton(
                                    TabletPlateTail4Size.compact,
                                  ),
                                  const SizedBox(width: 6),
                                  plateTail4SizeButton(
                                    TabletPlateTail4Size.small,
                                  ),
                                  const SizedBox(width: 6),
                                  plateTail4SizeButton(
                                    TabletPlateTail4Size.standard,
                                  ),
                                  const SizedBox(width: 6),
                                  plateTail4SizeButton(
                                    TabletPlateTail4Size.large,
                                  ),
                                  const SizedBox(width: 6),
                                  plateTail4SizeButton(
                                    TabletPlateTail4Size.extraLarge,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              plateTail4Preview(),
                              const SizedBox(height: 20),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Grid 표시 방식',
                                  style: sectionTitleStyle,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: <Widget>[
                                  gridRenderButton(
                                    target: TabletGridRenderMode.twoD,
                                    title: '2D 도면',
                                    icon: Icons.grid_view_rounded,
                                  ),
                                  const SizedBox(width: 8),
                                  gridRenderButton(
                                    target: TabletGridRenderMode.threeD,
                                    title: '3D 주차장',
                                    icon: Icons.view_in_ar_rounded,
                                  ),
                                ],
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
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '주차 구역/섹터/정산 데이터를 현재 지역 기준으로 로컬에 내려받습니다.',
                                            style: (text.bodyMedium ??
                                                const TextStyle())
                                                .copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w700,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Flexible(
                                          child: AnimatedSwitcher(
                                            duration: const Duration(milliseconds: 280),
                                            switchInCurve: Curves.easeOutBack,
                                            switchOutCurve: Curves.easeInCubic,
                                            transitionBuilder: (child, animation) {
                                              return FadeTransition(
                                                opacity: animation,
                                                child: ScaleTransition(
                                                  scale: animation,
                                                  child: child,
                                                ),
                                              );
                                            },
                                            child: _refreshing
                                                ? const Align(
                                                    key: ValueKey<String>('refreshing'),
                                                    alignment: Alignment.topRight,
                                                    child: SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    ),
                                                  )
                                                : Wrap(
                                                    key: ValueKey<String>(
                                                      'snapshot_${_localSectorCount}_${_lastRefreshAt?.millisecondsSinceEpoch}',
                                                    ),
                                                    alignment: WrapAlignment.end,
                                                    spacing: 6,
                                                    runSpacing: 6,
                                                    children: [
                                                      if (_localSectorCount != null)
                                                        _DialogPill(
                                                          text: '섹터 ${_localSectorCount!}개 로컬',
                                                        ),
                                                      if (_lastRefreshAt != null)
                                                        _DialogPill(
                                                          text: '마지막: ${_formatLastSync(_lastRefreshAt!)}',
                                                        ),
                                                    ],
                                                  ),
                                          ),
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
                                        icon: AnimatedSwitcher(
                                          duration: const Duration(milliseconds: 240),
                                          child: _refreshing
                                              ? SizedBox(
                                                  key: const ValueKey<String>('syncing'),
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor: AlwaysStoppedAnimation<Color>(
                                                      cs.onPrimary,
                                                    ),
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.download_rounded,
                                                  key: ValueKey<String>('download'),
                                                ),
                                        ),
                                        label: AnimatedSwitcher(
                                          duration: const Duration(milliseconds: 240),
                                          child: Text(
                                            _refreshing ? '로컬 저장 중' : '지금 내려받기',
                                            key: ValueKey<bool>(_refreshing),
                                          ),
                                        ),
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
                        child: CommonButton(
                          label: '닫기',
                          variant: CommonButtonVariant.tertiary,
                          minHeight: 44,
                          onPressed: () => Navigator.of(dialogCtx).pop(),
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
      useCommonUi: true,
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
