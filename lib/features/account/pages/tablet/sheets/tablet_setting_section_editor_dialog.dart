import 'package:flutter/material.dart';
import '../../../presentation/widgets/permission_detail_list.dart';
import '../../../domain/models/account_permission_policy.dart';
import 'package:flutter/services.dart';

import '../../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../../app/utils/snackbar_helper.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../../shared/auth/account_code_number.dart';
import '../../../../../shared/secondary/application/secondary_tablet_workspace_state.dart';
import '../../../../../shared/secondary/widgets/ops_console_widgets.dart';
import 'models/tablet_settings_draft.dart';

class TabletSettingSectionEditorDialog extends StatefulWidget {
  const TabletSettingSectionEditorDialog({
    super.key,
    required this.section,
    required this.initialDraft,
    required this.trace,
    required this.isEditMode,
    required this.onApply,
  });

  final TabletSettingsSection section;
  final TabletSettingsDraft initialDraft;
  final DeveloperOperationTrace trace;
  final bool isEditMode;
  final ValueChanged<TabletSettingsDraft> onApply;

  @override
  State<TabletSettingSectionEditorDialog> createState() =>
      _TabletSettingSectionEditorDialogState();
}

class _TabletSettingSectionEditorDialogState
    extends State<TabletSettingSectionEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _codeNumberController;
  late final TextEditingController _emailController;
  late Set<String> _permissionKeys;
  bool _submitted = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _nameController = TextEditingController(text: draft.name);
    _codeNumberController = TextEditingController(text: AccountCodeNumber.format(draft.codeNumber));
    _emailController = TextEditingController(text: draft.emailLocal);
    _permissionKeys = AccountPermissionPolicy.sanitize(draft.permissionKeys);
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
    _codeNumberController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.section) {
      case TabletSettingsSection.identity:
        return '태블릿 식별 정보';
      case TabletSettingsSection.permission:
        return '운영 권한';
    }
  }

  IconData get _icon {
    switch (widget.section) {
      case TabletSettingsSection.identity:
        return Icons.tablet_mac_rounded;
      case TabletSettingsSection.permission:
        return Icons.verified_user_rounded;
    }
  }

  bool get _nameOk => _nameController.text.trim().isNotEmpty;
  bool get _codeNumberOk => AccountCodeNumber.isGeneratedCode(_codeNumberController.text);

  bool _isValidEmailLocalPart(String value) {
    return RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value.trim());
  }

  bool get _emailOk =>
      _emailController.text.trim().isNotEmpty &&
      _isValidEmailLocalPart(_emailController.text);

  bool get _identityOk => _nameOk && _codeNumberOk && _emailOk;
  bool _validate() {
    switch (widget.section) {
      case TabletSettingsSection.identity:
        return _identityOk;
      case TabletSettingsSection.permission:
        return true;
    }
  }

  TabletSettingsDraft _resultDraft() {
    final base = widget.initialDraft;
    switch (widget.section) {
      case TabletSettingsSection.identity:
        return base.copyWith(
          name: _nameController.text.trim(),
          codeNumber: AccountCodeNumber.normalize(_codeNumberController.text),
          emailLocal: _emailController.text.trim(),
        );
      case TabletSettingsSection.permission:
        return base.copyWith(permissionKeys: _permissionKeys);
    }
  }

  Future<void> _apply() async {
    setState(() => _submitted = true);
    if (!_validate()) {
      widget.trace.log(
        '입력 검증 실패: section=${widget.section.name} emailSet=${_emailController.text.trim().isNotEmpty} emailValid=$_emailOk domain=gmail.com',
      );
      await HapticFeedback.mediumImpact();
      return;
    }
    final result = _resultDraft();
    widget.trace.log(
      '편집 적용: section=${widget.section.name} nameLength=${result.name.length} codeNumber=${AccountCodeNumber.mask(result.codeNumber)} emailSet=${result.emailLocal.isNotEmpty} emailDomain=gmail.com permissionCount=${result.permissionKeys.length} passwordPolicy=manual_firestore_only',
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

  Future<void> _copyCodeNumber() async {
    final codeNumber = AccountCodeNumber.normalize(_codeNumberController.text);
    await Clipboard.setData(
      ClipboardData(text: AccountCodeNumber.format(codeNumber)),
    );
    widget.trace.log(
      '코드번호 클립보드 복사: code=${AccountCodeNumber.mask(codeNumber)}',
    );
    if (!mounted) return;
    showSelectedSnackbar(
      context,
      '코드번호를 복사했습니다.',
      useCommonUi: true,
    );
  }

  void _regenerateCodeNumber() {
    if (widget.isEditMode) return;
    final next = AccountCodeNumber.generate();
    setState(() {
      _codeNumberController.text = AccountCodeNumber.format(next);
      _submitted = false;
    });
    widget.trace.log(
      '코드번호 재생성: code=${AccountCodeNumber.mask(next)}',
    );
  }

  Widget _identityEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameController,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_submitted) setState(() {});
          },
          decoration: opsInputDecoration(
            context,
            label: '태블릿 이름',
            prefixIcon: const Icon(Icons.tablet_mac_rounded),
            errorText:
                _submitted && !_nameOk ? '태블릿 이름을 입력하세요.' : null,
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            );
          },
          child: TextField(
            key: ValueKey<String>(_codeNumberController.text),
            controller: _codeNumberController,
            readOnly: true,
            enableInteractiveSelection: true,
            textInputAction: TextInputAction.done,
            decoration: opsInputDecoration(
              context,
              label: '코드번호',
              prefixIcon: const Icon(Icons.tag_rounded),
              locked: true,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _copyCodeNumber,
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  if (!widget.isEditMode)
                    IconButton(
                      onPressed: _regenerateCodeNumber,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                ],
              ),
              errorText: _submitted && !_codeNumberOk
                  ? '코드번호를 다시 생성하세요.'
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSize(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.enter,
          alignment: Alignment.topCenter,
          child: TextField(
            controller: _emailController,
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            autofillHints: const <String>[AutofillHints.username],
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
            ],
            decoration: opsInputDecoration(
              context,
              label: '이메일',
              suffixText: '@gmail.com',
              prefixIcon: AnimatedSwitcher(
                duration: _reduceMotion
                    ? Duration.zero
                    : CommonUiMotion.selection,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: .88, end: 1).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Icon(
                  _emailOk ? Icons.mark_email_read_rounded : Icons.mail_rounded,
                  key: ValueKey<bool>(_emailOk),
                ),
              ),
              errorText: _submitted && !_emailOk
                  ? '이메일을 다시 확인하세요.'
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _permissionEditor(BuildContext context) {
    final keys = AccountPermissionPolicy.keys.toList()..sort();
    return AnimatedSize(
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.enter,
      child: PermissionDetailList(
        permissions: keys,
        selected: _permissionKeys,
        height: 340,
        onToggle: (permission) {
          setState(() {
            _permissionKeys = <String>{..._permissionKeys};
            if (_permissionKeys.contains(permission)) {
              _permissionKeys.remove(permission);
            } else {
              _permissionKeys.add(permission);
            }
          });
          widget.trace.log('태블릿 권한 변경: key=$permission selected=${_permissionKeys.contains(permission)}');
        },
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (widget.section) {
      case TabletSettingsSection.identity:
        return _identityEditor(context);
      case TabletSettingsSection.permission:
        return _permissionEditor(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
          child: Row(
            children: [
              Icon(_icon, size: 20, color: tokens.accent),
              const SizedBox(width: 9),
              Expanded(
                child: AnimatedSwitcher(
                  duration: _reduceMotion
                      ? Duration.zero
                      : CommonUiMotion.selection,
                  child: Text(
                    _title,
                    key: ValueKey<String>(_title),
                    style: textTheme.titleSmall?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (widget.trace.developerMode)
                IconButton(
                  tooltip: '개발자 로그',
                  onPressed: _showDeveloperTrace,
                  icon: Icon(
                    Icons.bug_report_rounded,
                    size: 19,
                    color: tokens.warning,
                  ),
                ),
              IconButton(
                tooltip: '닫기',
                onPressed: _cancel,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Container(height: 1, color: tokens.borderSubtle),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: _body(context),
          ),
        ),
        Container(height: 1, color: tokens.borderSubtle),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: CommonButton(
                  label: '취소',
                  icon: Icons.close_rounded,
                  onPressed: _cancel,
                  variant: CommonButtonVariant.secondary,
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
                  variant: CommonButtonVariant.primary,
                  haptic: CommonHaptic.selection,
                  minHeight: 42,
                  expand: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
