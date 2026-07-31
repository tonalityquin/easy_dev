import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../domain/models/sector_model.dart';

class SectorSetting extends StatefulWidget {
  const SectorSetting({
    super.key,
    required this.currentArea,
    required this.onSave,
    this.initialSector,
  });

  final String currentArea;
  final SectorModel? initialSector;
  final Future<bool> Function(String name) onSave;

  @override
  State<SectorSetting> createState() => _SectorSettingState();
}

class _SectorSettingState extends State<SectorSetting>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _nameController;
  late final AnimationController _entryController;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  bool _saving = false;
  String? _errorText;

  bool get _editing => widget.initialSector != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialSector?.name ?? '',
    );
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _opacity = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _offset = Tween<Offset>(
      begin: const Offset(0, .035),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: Curves.easeOutCubic,
      ),
    );
    _entryController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = '섹터명을 입력해야 합니다.');
      return;
    }
    if (name.contains('/')) {
      setState(() => _errorText = '섹터명에는 / 문자를 사용할 수 없습니다.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      final saved = await widget.onSave(name);
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorText = _errorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _errorMessage(Object error) {
    if (error is SectorDuplicateNameException ||
        error is SectorAreaMismatchException ||
        error is SectorNotFoundException) {
      return error.toString();
    }
    if (error is ArgumentError) {
      return error.message?.toString() ?? '입력값을 확인해 주세요.';
    }
    if (error is StateError) {
      return error.message.toString();
    }
    return '섹터 저장에 실패했습니다.';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    final content = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CommonUiShapes.sheet),
        ),
        border: Border.all(color: tokens.borderSubtle),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 30,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 14, 18, 18 + keyboardInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.borderStrong,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: tokens.accentContainer,
                      borderRadius:
                          BorderRadius.circular(CommonUiShapes.control),
                      border: Border.all(color: tokens.borderSubtle),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _editing
                          ? Icons.edit_location_alt_rounded
                          : Icons.add_location_alt_rounded,
                      color: tokens.onAccentContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _editing ? '섹터 수정' : '섹터 등록',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.currentArea,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: tokens.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  CommonIconButton(
                    icon: Icons.close_rounded,
                    tooltip: '닫기',
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    haptic: CommonHaptic.selection,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : CommonUiMotion.selection,
                curve: CommonUiMotion.standard,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: tokens.surfaceOverlay,
                  borderRadius: BorderRadius.circular(CommonUiShapes.card),
                  border: Border.all(
                    color: _errorText == null
                        ? tokens.borderSubtle
                        : tokens.danger,
                  ),
                ),
                child: TextField(
                  controller: _nameController,
                  enabled: !_saving,
                  autofocus: true,
                  maxLength: 40,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  onChanged: (_) {
                    if (_errorText != null) {
                      setState(() => _errorText = null);
                    }
                  },
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                  decoration: opsInputDecoration(
                    context,
                    label: '섹터명',
                    errorText: _errorText,
                    prefixIcon: const Icon(Icons.place_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : CommonUiMotion.component,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                child: Row(
                  key: ValueKey<bool>(_saving),
                  children: <Widget>[
                    Expanded(
                      child: CommonButton(
                        label: '취소',
                        icon: Icons.close_rounded,
                        variant: CommonButtonVariant.secondary,
                        onPressed:
                            _saving ? null : () => Navigator.of(context).pop(),
                        haptic: CommonHaptic.selection,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CommonButton(
                        label: _editing ? '수정 저장' : '등록 저장',
                        icon: Icons.save_rounded,
                        loading: _saving,
                        onPressed: _saving ? null : _save,
                        haptic: CommonHaptic.medium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (reduceMotion) return content;
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: content),
    );
  }
}
