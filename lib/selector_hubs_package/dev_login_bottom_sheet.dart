import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'dev_auth.dart';
import 'brand_theme.dart';
import '../theme_prefs_controller.dart';

@immutable
class _DevSheetTokens {
  const _DevSheetTokens({
    required this.sheetBg,
    required this.handleBg,
    required this.titleFg,
    required this.bodyFg,
    required this.mutedFg,
    required this.dangerFg,
    required this.divider,
    required this.sectionBg,
    required this.sectionBorder,
  });

  final Color sheetBg;
  final Color handleBg;
  final Color titleFg;
  final Color bodyFg;
  final Color mutedFg;
  final Color dangerFg;

  final Color divider;
  final Color sectionBg;
  final Color sectionBorder;

  factory _DevSheetTokens.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _DevSheetTokens(
      sheetBg: cs.surface,
      handleBg: cs.outlineVariant.withOpacity(0.9),
      titleFg: cs.onSurface,
      bodyFg: cs.onSurface,
      mutedFg: cs.onSurfaceVariant,
      dangerFg: cs.error,
      divider: cs.outlineVariant.withOpacity(0.7),
      sectionBg: cs.surfaceContainerLow,
      sectionBorder: cs.outlineVariant.withOpacity(0.6),
    );
  }
}

class DevLoginBottomSheet extends StatefulWidget {
  const DevLoginBottomSheet({
    super.key,
    required this.onSuccess,
    required this.onReset,
    this.initialPresetId = 'system',
    this.initialThemeModeId = 'system',
    this.onPresetChanged,
    this.onThemeModeChanged,
  });

  final Future<void> Function(String id, String pw) onSuccess;
  final Future<void> Function() onReset;

  final String initialPresetId;
  final String initialThemeModeId;

  final ValueChanged<String>? onPresetChanged;
  final ValueChanged<String>? onThemeModeChanged;

  @override
  State<DevLoginBottomSheet> createState() => _DevLoginBottomSheetState();
}

class _DevLoginBottomSheetState extends State<DevLoginBottomSheet> {
  final _codeCtrl = TextEditingController();
  String? _error;

  late String _presetId;
  late String _themeModeId; // system | light | dark

  @override
  void initState() {
    super.initState();
    _presetId = widget.initialPresetId;
    _themeModeId = widget.initialThemeModeId;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim();
    if (DevAuth.verifyDevCode(code)) {
      HapticFeedback.selectionClick();
      await widget.onSuccess('dev', 'ok');
    } else {
      setState(() => _error = '개발 코드가 올바르지 않습니다.');
      HapticFeedback.vibrate();
    }
  }

  Future<void> _reset() async {
    await widget.onReset();
  }

  Future<void> _selectPreset(String id) async {
    if (_presetId == id) return;
    setState(() => _presetId = id);

    // ✅ 전역 테마 즉시 반영
    await context.read<ThemePrefsController>().setPresetId(id);

    // (호환) 상위가 별도 상태를 쓰는 경우 유지
    widget.onPresetChanged?.call(id);
  }

  Future<void> _selectThemeMode(String id) async {
    if (_themeModeId == id) return;
    setState(() => _themeModeId = id);

    // ✅ 전역 테마 즉시 반영
    await context.read<ThemePrefsController>().setThemeModeId(id);

    widget.onThemeModeChanged?.call(id);
  }

  ThemeData _buildThemed(ThemeData baseTheme, Brightness brightness, String presetId) {
    final base = withBrightness(baseTheme, brightness);

    final effectivePreset = presetById(presetId);
    final accent =
    (effectivePreset.id == 'system' || effectivePreset.accent == null) ? base.colorScheme.primary : effectivePreset.accent!;

    final scheme = buildConceptScheme(brightness: brightness, accent: accent);

    return base.copyWith(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: base.dividerTheme.copyWith(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
    );
  }

  Widget _buildThemeModeChips(BuildContext context) {
    final t = _DevSheetTokens.of(context);
    final text = Theme.of(context).textTheme;
    final modes = themeModeSpecs();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '테마 모드',
          style: text.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: t.bodyFg,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '시스템/라이트/다크를 선택합니다. 선택 즉시 전체 화면에 적용됩니다.',
          style: text.bodySmall?.copyWith(color: t.mutedFg),
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
    final t = _DevSheetTokens.of(context);
    final text = Theme.of(context).textTheme;
    final presets = brandPresets();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '색 패키지',
          style: text.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: t.bodyFg,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '컨셉 컬러는 포인트로만 사용되고, 표면은 중립으로 유지됩니다.',
          style: text.bodySmall?.copyWith(color: t.mutedFg),
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

  Widget _buildBottomPanel(BuildContext context) {
    final t = _DevSheetTokens.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: t.sectionBg,
        border: Border(top: BorderSide(color: t.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildThemeModeChips(context),
          const SizedBox(height: 12),
          Divider(height: 1, color: t.divider),
          const SizedBox(height: 12),
          _buildPresetChips(context),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final brightness = resolveBrightness(_themeModeId, systemBrightness);

    final baseTheme = Theme.of(context);
    final themed = _buildThemed(baseTheme, brightness, _presetId);

    return Theme(
      data: themed,
      child: Builder(
        builder: (context) {
          final t = _DevSheetTokens.of(context);
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;
          final screenHeight = MediaQuery.of(context).size.height;
          final effectiveHeight = screenHeight - bottomInset;
          final cs = Theme.of(context).colorScheme;
          final text = Theme.of(context).textTheme;

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SizedBox(
                height: effectiveHeight,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: t.sheetBg,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      border: Border.all(color: t.sectionBorder),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: t.handleBg,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Text(
                          '개발자 로그인',
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: t.titleFg,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '개발 전용 코드를 입력하세요. 인증되면 앱을 재시작해도 접근 권한이 유지됩니다.',
                            textAlign: TextAlign.center,
                            style: text.bodySmall?.copyWith(color: t.mutedFg),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _codeCtrl,
                                  decoration: const InputDecoration(
                                    labelText: '개발 코드',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.vpn_key_outlined),
                                  ),
                                  obscureText: true,
                                  enableSuggestions: false,
                                  autocorrect: false,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submit(),
                                ),
                                const SizedBox(height: 12),
                                if (_error != null)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: cs.errorContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _error!,
                                      style: TextStyle(
                                        color: cs.onErrorContainer,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: const StadiumBorder(),
                                        ),
                                        child: const Text('취소'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _submit,
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: const StadiumBorder(),
                                        ),
                                        icon: const Icon(Icons.login),
                                        label: const Text(
                                          '로그인',
                                          style: TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: _reset,
                                    icon: const Icon(Icons.restart_alt),
                                    label: const Text('초기화'),
                                    style: TextButton.styleFrom(foregroundColor: t.dangerFg),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ),
                          ),
                        ),
                        _buildBottomPanel(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
              color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.6),
            ),
          ),
        );
      }),
    );
  }
}
