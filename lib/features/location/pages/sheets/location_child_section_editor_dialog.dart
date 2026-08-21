import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import 'models/location_child_settings_draft.dart';

class LocationChildSectionEditorDialog extends StatefulWidget {
  const LocationChildSectionEditorDialog({
    super.key,
    required this.initialDraft,
    required this.trace,
    required this.onApply,
  });

  final LocationChildSettingsDraft initialDraft;
  final DeveloperOperationTrace trace;
  final ValueChanged<LocationChildSettingsDraft> onApply;

  @override
  State<LocationChildSectionEditorDialog> createState() =>
      _LocationChildSectionEditorDialogState();
}

class _LocationChildSectionEditorDialogState
    extends State<LocationChildSectionEditorDialog> {
  late final TextEditingController _nameController;
  bool _submitted = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialDraft.name);
    widget.trace.log(
      '자식구역 기본 정보 editor open parentId=${widget.initialDraft.parentId} nameLength=${widget.initialDraft.name.length}',
    );
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

  String get _nameError {
    final name = _nameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) return '자식구역명을 입력해 주세요.';
    if (name.length > 40) return '자식구역명은 40자 이하로 입력해 주세요.';
    if (name.toLowerCase() == widget.initialDraft.parentName.trim().toLowerCase()) {
      return '자식구역명은 부모구역명과 같을 수 없습니다.';
    }
    return '';
  }

  void _cancel() {
    widget.trace.log('자식구역 기본 정보 editor cancel');
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  void _apply() {
    setState(() => _submitted = true);
    final error = _nameError;
    if (error.isNotEmpty) {
      widget.trace.log('자식구역 기본 정보 validation fail reason=$error');
      return;
    }
    final name = _nameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    widget.trace.log('자식구역 기본 정보 apply nameLength=${name.length}');
    widget.onApply(widget.initialDraft.copyWith(name: name));
    Navigator.of(context, rootNavigator: true).pop(true);
  }

  Future<void> _showDeveloperTrace() async {
    widget.trace.log('자식구역 기본 정보 developer status requested');
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '자식구역 기본 정보 편집 로그',
      description: '현재 편집 동작의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final error = _submitted && _nameError.isNotEmpty ? _nameError : null;
    return Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
        curve: CommonUiMotion.standard,
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
          border: Border.all(color: tokens.borderSubtle),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '자식구역 기본 정보',
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
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
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_tree_rounded, size: 18, color: tokens.iconSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '부모구역',
                          style: textTheme.labelSmall?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.initialDraft.parentName,
                          style: textTheme.bodyMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
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
                label: '자식구역명',
                prefixIcon: const Icon(Icons.location_on_outlined),
                errorText: error,
              ),
            ),
            const Spacer(),
            Row(
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
          ],
        ),
      ),
    );
  }
}
