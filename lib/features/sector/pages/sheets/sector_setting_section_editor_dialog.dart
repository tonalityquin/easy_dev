import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/application/secondary_sector_workspace_state.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import 'models/sector_settings_draft.dart';

class SectorSettingSectionEditorDialog extends StatefulWidget {
  const SectorSettingSectionEditorDialog({
    super.key,
    required this.section,
    required this.initialDraft,
    required this.trace,
    required this.onApply,
  });

  final SectorSettingsSection section;
  final SectorSettingsDraft initialDraft;
  final DeveloperOperationTrace trace;
  final ValueChanged<SectorSettingsDraft> onApply;

  @override
  State<SectorSettingSectionEditorDialog> createState() =>
      _SectorSettingSectionEditorDialogState();
}

class _SectorSettingSectionEditorDialogState
    extends State<SectorSettingSectionEditorDialog> {
  late final TextEditingController _nameController;
  bool _submitted = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialDraft.name);
    widget.trace.log('편집 화면이 열렸습니다: section=${widget.section.name}');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String get _title => '섹터 기본 정보';

  String get _nameError {
    final value = _nameController.text.trim();
    if (value.isEmpty) return '섹터명을 입력해야 합니다.';
    if (value.contains('/')) return '섹터명에는 / 문자를 사용할 수 없습니다.';
    if (value.length > 40) return '섹터명은 40자 이하로 입력해 주세요.';
    return '';
  }

  bool get _nameOk => _nameError.isEmpty;

  Future<void> _apply() async {
    setState(() => _submitted = true);
    if (!_nameOk) {
      widget.trace.log(
        '입력 검증 실패: section=${widget.section.name} reason=${_nameController.text.trim().isEmpty ? 'empty' : 'invalid'}',
      );
      await HapticFeedback.mediumImpact();
      return;
    }
    final result = widget.initialDraft.copyWith(
      name: _nameController.text.trim(),
    );
    widget.trace.log(
      '편집 적용: section=${widget.section.name} nameLength=${result.name.length}',
    );
    widget.onApply(result);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(true);
  }

  void _cancel() {
    widget.trace.log('편집 취소: section=${widget.section.name}');
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  Future<void> _showDeveloperTrace() async {
    widget.trace.log(
      '개발자 로그 Status Dialog 요청: section=${widget.section.name}',
    );
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '$_title 편집 로그',
      description: '현재 편집 동작의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final errorText = _submitted && !_nameOk ? _nameError : null;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
          border: Border.all(color: tokens.borderSubtle),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: tokens.shadow,
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: tokens.accentContainer,
                        borderRadius:
                            BorderRadius.circular(CommonUiShapes.control),
                        border: Border.all(color: tokens.borderSubtle),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.hub_rounded,
                        size: 20,
                        color: tokens.onAccentContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _title,
                        style: textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (widget.trace.developerMode)
                      CommonIconButton(
                        icon: Icons.bug_report_outlined,
                        tooltip: '개발자 로그',
                        onPressed: _showDeveloperTrace,
                        haptic: CommonHaptic.selection,
                      ),
                    CommonIconButton(
                      icon: Icons.close_rounded,
                      tooltip: '닫기',
                      onPressed: _cancel,
                      haptic: CommonHaptic.selection,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                AnimatedContainer(
                  duration:
                      _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  curve: CommonUiMotion.standard,
                  child: TextField(
                    controller: _nameController,
                    autofocus: true,
                    maxLength: 40,
                    textInputAction: TextInputAction.done,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.deny(RegExp(r'[\n\r]')),
                    ],
                    onChanged: (_) {
                      if (_submitted) setState(() {});
                    },
                    onSubmitted: (_) => _apply(),
                    decoration: opsInputDecoration(
                      context,
                      label: '섹터명',
                      prefixIcon: const Icon(Icons.place_rounded),
                      errorText: errorText,
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration:
                      _reduceMotion ? Duration.zero : CommonUiMotion.component,
                  switchInCurve: CommonUiMotion.enter,
                  switchOutCurve: CommonUiMotion.exit,
                  child: Row(
                    key: ValueKey<bool>(_submitted && !_nameOk),
                    children: [
                      Expanded(
                        child: CommonButton(
                          label: '취소',
                          icon: Icons.close_rounded,
                          variant: CommonButtonVariant.secondary,
                          onPressed: _cancel,
                          haptic: CommonHaptic.selection,
                          minHeight: 42,
                          expand: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CommonButton(
                          label: '적용',
                          icon: Icons.check_rounded,
                          onPressed: _apply,
                          haptic: CommonHaptic.medium,
                          minHeight: 42,
                          expand: true,
                        ),
                      ),
                    ],
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
