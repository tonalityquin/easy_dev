import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/config/email_config.dart';
import '../../../app/config/overlay_edge_side_config.dart';
import '../../../app/config/overlay_mode_config.dart';
import '../../../app/theme/brand_theme.dart';
import '../../../app/theme/theme_prefs_controller.dart';
import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../dev/page/sheets/dev_quick_actions.dart';
import '../application/dev_auth.dart';

const String kParkingRequestsWriteEnabledKey =
    'parking_requests_realtime_write_enabled_v1';
const String kParkingCompletedWriteEnabledKey =
    'parking_completed_realtime_write_enabled_v1';
const String kDepartureRequestsWriteEnabledKey =
    'departure_requests_realtime_write_enabled_v1';

const String kDevModeEnabledKey = 'dev_mode_enabled_v1';

const String _kPrivateAdminPassword = 'blsnc150119';

const String _kKbPresetId = 'kb';
const String _kDefaultIndependentPresetId = 'soft_linen';
const Set<String> _kKbThemeAllowedAreas = <String>{
  'KB라이프타워',
  'KB라이프역삼',
};

class ServiceBottomSheet {
  const ServiceBottomSheet._();

  static Future<void> show({
    required BuildContext context,
  }) async {
    await showPromptOverlayBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) {
        return _ServiceBottomSheetView(
          parentContext: context,
        );
      },
    );
  }
}

class _ServiceBottomSheetView extends StatefulWidget {
  const _ServiceBottomSheetView({
    required this.parentContext,
  });

  final BuildContext parentContext;

  @override
  State<_ServiceBottomSheetView> createState() =>
      _ServiceBottomSheetViewState();
}

class _ServiceBottomSheetViewState extends State<_ServiceBottomSheetView> {
  late String _presetId;
  late String _themeModeId;

  String _selectedArea = '';

  bool _adminUnlocked = false;
  bool _devModeEnabled = false;

  final TextEditingController _privateCodeCtrl = TextEditingController();
  bool _privateCodeObscure = true;

  bool _bootLoading = true;
  bool _isSimpleAppMode = false;
  OverlayMode _overlayMode = OverlayMode.bubble;

  OverlayEdgeSide _edgeSide = OverlayEdgeSide.left;

  final TextEditingController _mailToCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();

    final themeCtrl = context.read<ThemePrefsController>();
    _presetId = themeCtrl.presetId;
    _themeModeId = themeCtrl.themeModeId;

    _bootstrapPrivateSettings();
  }

  @override
  void dispose() {
    _privateCodeCtrl.dispose();
    _mailToCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrapPrivateSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedArea = (prefs.getString('selectedArea') ?? '').trim();
      await _ensureRealtimeDefaults(prefs);
      if (!mounted) return;
      await _ensureBrandPresetAllowedForSelectedArea();

      _devModeEnabled = prefs.getBool(kDevModeEnabledKey) ?? false;
      _isSimpleAppMode =
          (prefs.getString('mode') ?? '').trim().toLowerCase() == 'simple';

      final currentOverlayMode = await OverlayModeConfig.getMode();
      if (_isSimpleAppMode) {
        _overlayMode = OverlayMode.bubble;
        if (currentOverlayMode != OverlayMode.bubble) {
          await OverlayModeConfig.setMode(OverlayMode.bubble);
        }
      } else {
        _overlayMode = currentOverlayMode;
      }

      _edgeSide = await OverlayEdgeSideConfig.getSide();

      final emailCfg = await EmailConfig.load();
      _mailToCtrl.text = emailCfg.to;
    } catch (_) {
    } finally {
      if (!mounted) return;
      setState(() => _bootLoading = false);
    }
  }

  Future<void> _ensureRealtimeDefaults(SharedPreferences prefs) async {
    await prefs.setBool(kParkingCompletedWriteEnabledKey, true);
    await prefs.setBool(kDepartureRequestsWriteEnabledKey, true);
    await prefs.setBool(kParkingRequestsWriteEnabledKey, true);

    await prefs.setBool('parking_completed_realtime_tab_enabled_v1', true);
    await prefs.setBool('departure_requests_realtime_tab_enabled_v1', true);
    await prefs.setBool('parking_requests_realtime_tab_enabled_v1', true);
  }

  bool get _isKbThemeArea => _kKbThemeAllowedAreas.contains(_selectedArea.trim());

  bool _isPresetAllowedForSelectedArea(BrandPresetSpec preset) {
    if (preset.id != _kKbPresetId) return true;
    return _isKbThemeArea;
  }

  List<BrandPresetSpec> _brandPresetsForSelectedArea(String themeModeId) {
    return brandPresetsForThemeMode(themeModeId)
        .where(_isPresetAllowedForSelectedArea)
        .toList(growable: false);
  }

  String _fallbackPresetIdForThemeMode(String themeModeId) {
    final candidates = _brandPresetsForSelectedArea(themeModeId);
    if (candidates.isEmpty) return 'system';

    if (themeModeId == 'independent') {
      final preferred = candidates.where((p) => p.id == _kDefaultIndependentPresetId);
      if (preferred.isNotEmpty) return preferred.first.id;
    }

    final systemPreset = candidates.where((p) => p.id == 'system');
    if (systemPreset.isNotEmpty) return systemPreset.first.id;

    return candidates.first.id;
  }

  Future<void> _ensureBrandPresetAllowedForSelectedArea() async {
    final currentPreset = presetById(_presetId);
    if (_isPresetAllowedForSelectedArea(currentPreset)) return;

    final fallback = _fallbackPresetIdForThemeMode(_themeModeId);
    _presetId = fallback;
    await context.read<ThemePrefsController>().setPresetId(fallback);
  }

  ThemeData _buildConceptThemed(
      ThemeData baseTheme, Brightness brightness, String presetId) {
    final base = withBrightness(baseTheme, brightness);

    final effectivePreset = presetById(presetId);
    final accent =
    (effectivePreset.id == 'system' || effectivePreset.accent == null)
        ? base.colorScheme.primary
        : effectivePreset.accent!;

    final scheme = buildConceptScheme(brightness: brightness, accent: accent);

    return base.copyWith(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surface.withOpacity(0),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: scheme.surface.withOpacity(0),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: scheme.surface.withOpacity(0),
        surfaceTintColor: scheme.surface.withOpacity(0),
      ),
      dividerTheme: base.dividerTheme.copyWith(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
    );
  }

  ThemeData _buildIndependentThemed(ThemeData baseTheme, String presetId) {
    return applyIndependentTheme(baseTheme, presetId);
  }

  Future<void> _selectPreset(String id) async {
    final preset = presetById(id);
    if (!_isPresetAllowedForSelectedArea(preset)) return;
    if (_presetId == id) return;
    setState(() => _presetId = id);

    await context.read<ThemePrefsController>().setPresetId(id);
  }

  Future<void> _selectThemeMode(String id) async {
    if (_themeModeId == id) return;
    setState(() => _themeModeId = id);

    await context.read<ThemePrefsController>().setThemeModeId(id);

    final cur = presetById(_presetId);
    final currentAllowed = _isPresetAllowedForSelectedArea(cur);

    if (id == 'independent') {
      if (cur.independentTokens == null || !currentAllowed) {
        final fallback = _fallbackPresetIdForThemeMode('independent');
        setState(() => _presetId = fallback);
        await context.read<ThemePrefsController>().setPresetId(fallback);
      }
    } else {
      if (cur.independentTokens != null || !currentAllowed) {
        final fallback = _fallbackPresetIdForThemeMode(id);
        setState(() => _presetId = fallback);
        await context.read<ThemePrefsController>().setPresetId(fallback);
      }
    }
  }

  Widget _buildThemeModeChips(BuildContext context) {
    final t = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final modes = themeModeSpecs();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '테마 모드',
          style: text.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '시스템/라이트/다크/독립을 선택합니다. 선택 즉시 전체 화면에 적용됩니다.',
          style: text.bodySmall?.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: modes.map((m) {
            final selected = m.id == _themeModeId;
            return ChoiceChip(
              selected: selected,
              onSelected: (_) => _selectThemeMode(m.id),
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
      ],
    );
  }

  Widget _buildPresetChips(BuildContext context) {
    final t = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    final presets = _brandPresetsForSelectedArea(_themeModeId);

    final descriptionText = (_themeModeId == 'independent')
        ? '독립 모드는 프리셋마다 배경/글자색이 고정됩니다(프리셋이 밝기까지 결정).'
        : '컨셉 컬러는 포인트로만 사용되고, 표면은 중립으로 유지됩니다.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '색 패키지',
          style: text.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          descriptionText,
          style: text.bodySmall?.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: presets.map((p) {
              final selected = p.id == _presetId;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: selected,
                  onSelected: (_) => _selectPreset(p.id),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PresetPreviewDots(colors: p.preview),
                      const SizedBox(width: 8),
                      Text(p.label),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Future<void> _applyPrivateCode() async {
    final input = _privateCodeCtrl.text.trim();

    if (input.isEmpty) {
      return;
    }

    if (input == _kPrivateAdminPassword) {
      if (!mounted) return;
      setState(() {
        _adminUnlocked = true;
        _privateCodeCtrl.clear();
      });
      FocusScope.of(context).unfocus();
      return;
    }

    final isDev = DevAuth.verifyDevCode(input);
    if (isDev) {
      await DevQuickActions.enableDeveloperMode();
      if (!mounted) return;
      setState(() {
        _devModeEnabled = true;
        _privateCodeCtrl.clear();
      });

      FocusScope.of(context).unfocus();
      return;
    }
  }

  void _lockAdmin() {
    setState(() {
      _adminUnlocked = false;
    });
  }

  Future<void> _disableDevMode() async {
    await DevQuickActions.disableDeveloperMode();
    if (!mounted) return;
    setState(() {
      _devModeEnabled = false;
    });
  }

  Widget _sectionBox({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    final t = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    return PromptAnimatedReveal(
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: t.surfaceOverlay,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          border: Border.all(color: t.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: t.accentContainer,
                    borderRadius: BorderRadius.circular(PromptUiShapes.control),
                    border: Border.all(
                      color: t.accent.withOpacity(t.isDark ? 0.48 : 0.30),
                    ),
                  ),
                  child: Icon(icon, size: 20, color: t.onAccentContainer),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayEdgeSideSection(BuildContext context) {
    final t = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    String labelFor(OverlayEdgeSide side) {
      return side == OverlayEdgeSide.left ? '왼쪽' : '오른쪽';
    }

    Future<void> apply(OverlayEdgeSide side) async {
      setState(() => _edgeSide = side);
      await OverlayEdgeSideConfig.setSide(side);
      try {
        if (await FlutterOverlayWindow.isActive()) {
          await FlutterOverlayWindow.closeOverlay();
        }
      } catch (_) {}
      if (!mounted) return;
    }

    return _sectionBox(
      context: context,
      icon: Icons.swap_horiz_rounded,
      title: '공개 섹션: 플로팅 버튼 위치',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '플로팅(오버레이) 버튼이 기본으로 붙을 위치를 선택합니다.\n'
                '앱이 백그라운드로 이동해 오버레이가 실행될 때 적용됩니다.\n'
                '이미 오버레이가 떠 있다면, 저장 시 자동으로 종료되어 다음 실행부터 반영됩니다.',
            style: text.bodyMedium?.copyWith(fontSize: 13, color: t.textPrimary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('왼쪽'),
                selected: _edgeSide == OverlayEdgeSide.left,
                onSelected: (selected) async {
                  if (!selected) return;
                  await apply(OverlayEdgeSide.left);
                },
              ),
              ChoiceChip(
                label: const Text('오른쪽'),
                selected: _edgeSide == OverlayEdgeSide.right,
                onSelected: (selected) async {
                  if (!selected) return;
                  await apply(OverlayEdgeSide.right);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '현재 선택: ${labelFor(_edgeSide)}',
            style: text.bodySmall?.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivateGateSection(BuildContext context) {
    final t = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    final adminStatus = _adminUnlocked ? 'ON' : 'OFF';
    final devStatus = _devModeEnabled ? 'ON' : 'OFF';

    return _sectionBox(
      context: context,
      icon: Icons.lock_outline_rounded,
      title: '비공개 섹션: 해금/개발자 모드',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_adminUnlocked)
            PromptIconButton(
              icon: Icons.lock_rounded,
              tooltip: '앱설정 잠그기',
              onPressed: _lockAdmin,
              destructive: true,
              haptic: PromptHaptic.selection,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '코드 입력으로 기능을 활성화합니다.\n'
                '• 관리자 코드 → 앱 설정(앱관리) 섹션 ON\n'
                '• 개발자 코드 → 개발자 모드와 개발자 플로팅 버블 ON',
            style: text.bodyMedium?.copyWith(fontSize: 13, color: t.textPrimary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatusPill(label: '앱설정', value: adminStatus),
              const SizedBox(width: 8),
              _StatusPill(label: '개발자', value: devStatus),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _privateCodeCtrl,
            obscureText: _privateCodeObscure,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: '코드 입력',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.password_rounded),
              suffixIcon: PromptIconButton(
                icon: _privateCodeObscure
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                tooltip: _privateCodeObscure ? '표시' : '숨김',
                size: 42,
                onPressed: () =>
                    setState(() => _privateCodeObscure = !_privateCodeObscure),
              ),
            ),
            onSubmitted: (_) => _applyPrivateCode(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PromptButton(
                  label: '적용',
                  icon: Icons.check_rounded,
                  onPressed: _applyPrivateCode,
                  expand: true,
                  haptic: PromptHaptic.medium,
                ),
              ),
              if (_devModeEnabled) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: PromptButton(
                    label: '개발자 모드 OFF',
                    icon: Icons.power_settings_new,
                    onPressed: _disableDevMode,
                    variant: PromptButtonVariant.destructive,
                    expand: true,
                    haptic: PromptHaptic.heavy,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayModeSection(BuildContext context) {
    final t = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    String labelFor(OverlayMode mode) {
      switch (mode) {
        case OverlayMode.topHalf:
          return '상단 50% 포그라운드';
        case OverlayMode.bubble:
          return '플로팅 버블';
      }
    }

    return _sectionBox(
      context: context,
      icon: Icons.view_sidebar_outlined,
      title: '오버레이 형태 선택',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isSimpleAppMode
                ? '싱글모드는 단순 출퇴근 및 휴게 기록기 용도이므로 퇴근 시간이 지나도 상단 50% 포그라운드를 사용하지 않고 플로팅 버블만 사용합니다.'
                : '앱이 백그라운드로 이동했을 때 사용할 오버레이 형태를 선택합니다.\n하나만 선택되며, 선택된 모드만 실행/종료 조건을 공유합니다.',
            style: text.bodyMedium?.copyWith(fontSize: 13, color: t.textPrimary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('플로팅 버블'),
                selected: _overlayMode == OverlayMode.bubble,
                onSelected: (selected) async {
                  if (!selected) return;
                  setState(() => _overlayMode = OverlayMode.bubble);
                  await OverlayModeConfig.setMode(OverlayMode.bubble);

                  try {
                    if (await FlutterOverlayWindow.isActive()) {
                      await FlutterOverlayWindow.shareData('__mode:bubble__');
                      await FlutterOverlayWindow.shareData('__collapse__');
                    }
                  } catch (_) {}

                  if (!mounted) return;
                },
              ),
              ChoiceChip(
                label: const Text('상단 50% 포그라운드'),
                selected:
                    !_isSimpleAppMode && _overlayMode == OverlayMode.topHalf,
                onSelected: _isSimpleAppMode
                    ? null
                    : (selected) async {
                        if (!selected) return;
                        setState(() => _overlayMode = OverlayMode.topHalf);
                        await OverlayModeConfig.setMode(OverlayMode.topHalf);

                        try {
                          if (await FlutterOverlayWindow.isActive()) {
                            await FlutterOverlayWindow.shareData('__mode:topHalf__');
                            await FlutterOverlayWindow.shareData('__collapse__');
                          }
                        } catch (_) {}

                        if (!mounted) return;
                      },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '현재 선택: ${labelFor(_overlayMode)}',
            style: text.bodySmall?.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildGmailSection(BuildContext context) {
    final t = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    return _sectionBox(
      context: context,
      icon: Icons.mail_outline,
      title: '메일 전송 설정 (수신자만)',
      trailing: PromptIconButton(
        icon: Icons.restore,
        tooltip: '기본값으로 초기화',
        destructive: true,
        haptic: PromptHaptic.selection,
        onPressed: () async {
          await EmailConfig.clear();
          final cfg = await EmailConfig.load();
          _mailToCtrl.text = cfg.to;
          if (!mounted) return;
          setState(() {});
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _mailToCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '수신자(To)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_add_alt_1_outlined),
            ),
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PromptButton(
                  label: '저장',
                  icon: Icons.check_circle_outline,
                  variant: PromptButtonVariant.secondary,
                  expand: true,
                  haptic: PromptHaptic.medium,
                  onPressed: () async {
                    final to = _mailToCtrl.text.trim();
                    if (!EmailConfig.isValidToList(to)) {
                      if (!mounted) return;
                      return;
                    }
                    await EmailConfig.save(EmailConfig(to: to));
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PromptButton(
                  label: '설정 복사',
                  icon: Icons.copy_all_outlined,
                  variant: PromptButtonVariant.tertiary,
                  expand: true,
                  haptic: PromptHaptic.selection,
                  onPressed: () async {
                    final raw = 'To: ${_mailToCtrl.text}';
                    await Clipboard.setData(ClipboardData(text: raw));
                    if (!mounted) return;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '※ 저장되는 항목은 수신자(To)뿐입니다. 메일 제목·본문은 경위서 화면에서 작성합니다.',
            style: text.bodySmall?.copyWith(fontSize: 12, color: t.textSecondary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(widget.parentContext);

    final ThemeData themed;
    if (_themeModeId == 'independent') {
      themed = _buildIndependentThemed(baseTheme, _presetId);
    } else {
      final systemBrightness = MediaQuery.platformBrightnessOf(context);
      final brightness = resolveBrightness(_themeModeId, systemBrightness);
      themed = _buildConceptThemed(baseTheme, brightness, _presetId);
    }

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedTheme(
      data: PromptUiTheme.scoped(themed),
      duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
      curve: PromptUiMotion.standard,
      child: Builder(
        builder: (context) {
          final tokens = PromptUiTheme.of(context);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 1,
            maxChildSize: 1,
            minChildSize: 0.4,
            builder: (sheetContext, scrollController) {
              final keyboardBottom =
                  MediaQuery.of(sheetContext).viewInsets.bottom;

              return PromptSheetScaffold(
                title: '서비스 설정',
                icon: Icons.tune_rounded,
                onClose: () => Navigator.pop(sheetContext),
                body: AnimatedPadding(
                  duration:
                      reduceMotion ? Duration.zero : PromptUiMotion.component,
                  curve: PromptUiMotion.standard,
                  padding: EdgeInsets.only(bottom: keyboardBottom),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionBox(
                          context: context,
                          icon: Icons.palette_outlined,
                          title: '공개 섹션: 브랜드 테마',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildThemeModeChips(context),
                              const SizedBox(height: 12),
                              Divider(
                                height: 1,
                                color: tokens.borderSubtle,
                              ),
                              const SizedBox(height: 12),
                              _buildPresetChips(context),
                            ],
                          ),
                        ),
                        _buildOverlayEdgeSideSection(context),
                        _buildPrivateGateSection(context),
                        AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : PromptUiMotion.component,
                          switchInCurve: PromptUiMotion.enter,
                          switchOutCurve: PromptUiMotion.exit,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SizeTransition(
                                sizeFactor: animation,
                                axisAlignment: -1,
                                child: child,
                              ),
                            );
                          },
                          child: _bootLoading
                              ? Padding(
                                  key: const ValueKey<String>('loading'),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 18),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: tokens.accent,
                                    ),
                                  ),
                                )
                              : _adminUnlocked
                                  ? Column(
                                      key: const ValueKey<String>('unlocked'),
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildOverlayModeSection(context),
                                        _buildGmailSection(context),
                                      ],
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey<String>('locked'),
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
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
    final tokens = PromptUiTheme.of(context);
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
            border: Border.all(
              color: tokens.borderStrong.withOpacity(0.72),
            ),
          ),
        );
      }),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final isOn = value == 'ON';
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
      curve: PromptUiMotion.standard,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isOn ? tokens.accentContainer : tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
        border: Border.all(
          color: isOn ? tokens.accent : tokens.borderSubtle,
        ),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: isOn ? tokens.onAccentContainer : tokens.textSecondary,
        ),
      ),
    );
  }
}
