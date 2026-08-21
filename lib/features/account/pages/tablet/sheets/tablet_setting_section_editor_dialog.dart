import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../../app/utils/snackbar_helper.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../../shared/auth/five_digit_password_generator.dart';
import '../../../../../shared/secondary/application/secondary_tablet_workspace_state.dart';
import '../../../../../shared/secondary/widgets/ops_console_widgets.dart';
import 'models/tablet_settings_draft.dart';
import 'widgets/tablet_role_type.dart';

class TabletSettingSectionEditorDialog extends StatefulWidget {
  const TabletSettingSectionEditorDialog({
    super.key,
    required this.section,
    required this.initialDraft,
    required this.trace,
    required this.onApply,
  });

  final TabletSettingsSection section;
  final TabletSettingsDraft initialDraft;
  final DeveloperOperationTrace trace;
  final ValueChanged<TabletSettingsDraft> onApply;

  @override
  State<TabletSettingSectionEditorDialog> createState() =>
      _TabletSettingSectionEditorDialogState();
}

class _TabletSettingSectionEditorDialogState
    extends State<TabletSettingSectionEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _handleController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late TabletRoleType _role;
  bool _submitted = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _nameController = TextEditingController(text: draft.name);
    _handleController = TextEditingController(text: draft.handle);
    _emailController = TextEditingController(text: draft.emailLocal);
    _passwordController = TextEditingController(text: draft.password);
    _role = draft.role;
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
    _handleController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.section) {
      case TabletSettingsSection.identity:
        return '태블릿 식별 정보';
      case TabletSettingsSection.permission:
        return '운영 권한';
      case TabletSettingsSection.password:
        return '로그인 비밀번호';
    }
  }

  IconData get _icon {
    switch (widget.section) {
      case TabletSettingsSection.identity:
        return Icons.tablet_mac_rounded;
      case TabletSettingsSection.permission:
        return Icons.verified_user_rounded;
      case TabletSettingsSection.password:
        return Icons.password_rounded;
    }
  }

  bool _isValidEmailLocalPart(String value) {
    return RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value.trim());
  }

  bool get _nameOk => _nameController.text.trim().isNotEmpty;
  bool get _handleOk =>
      RegExp(r'^[a-z]{3,20}$').hasMatch(_handleController.text.trim());
  bool get _emailOk => _emailController.text.trim().isNotEmpty &&
      _isValidEmailLocalPart(_emailController.text);
  bool get _identityOk => _nameOk && _handleOk && _emailOk;
  bool get _passwordOk =>
      RegExp(r'^\d{5}$').hasMatch(_passwordController.text.trim());

  bool _validate() {
    switch (widget.section) {
      case TabletSettingsSection.identity:
        return _identityOk;
      case TabletSettingsSection.permission:
        return true;
      case TabletSettingsSection.password:
        return _passwordOk;
    }
  }

  TabletSettingsDraft _resultDraft() {
    final base = widget.initialDraft;
    switch (widget.section) {
      case TabletSettingsSection.identity:
        return base.copyWith(
          name: _nameController.text.trim(),
          handle: _handleController.text.trim(),
          emailLocal: _emailController.text.trim(),
        );
      case TabletSettingsSection.permission:
        return base.copyWith(role: _role);
      case TabletSettingsSection.password:
        return base.copyWith(password: _passwordController.text.trim());
    }
  }

  Future<void> _apply() async {
    setState(() => _submitted = true);
    if (!_validate()) {
      widget.trace.log('입력 검증 실패: section=${widget.section.name}');
      await HapticFeedback.mediumImpact();
      return;
    }
    final result = _resultDraft();
    widget.trace.log(
      '편집 적용: section=${widget.section.name} nameLength=${result.name.length} handleLength=${result.handle.length} emailLength=${result.emailLocal.length} role=${result.role.name} passwordLength=${result.password.length}',
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

  Future<void> _copyPassword() async {
    final value = _passwordController.text.trim();
    await Clipboard.setData(ClipboardData(text: value));
    widget.trace.log('비밀번호 클립보드 복사: length=${value.length}');
    if (!mounted) return;
    showSelectedSnackbar(
      context,
      '태블릿 비밀번호를 복사했습니다.',
      useCommonUi: true,
    );
  }

  void _regeneratePassword() {
    final next = FiveDigitPasswordGenerator.generate();
    setState(() => _passwordController.text = next);
    widget.trace.log('비밀번호 재생성: length=${next.length}');
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
            errorText: _submitted && !_nameOk ? '태블릿 이름을 입력하세요.' : null,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _handleController,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_submitted) setState(() {});
          },
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[a-z]')),
            LengthLimitingTextInputFormatter(20),
          ],
          decoration: opsInputDecoration(
            context,
            label: '태블릿 아이디',
            prefixIcon: const Icon(Icons.alternate_email_rounded),
            errorText: _submitted && !_handleOk
                ? '아이디는 소문자 영어 3~20자로 입력하세요.'
                : null,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailController,
          textInputAction: TextInputAction.done,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) {
            if (_submitted) setState(() {});
          },
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.deny(RegExp(r'\s')),
          ],
          decoration: opsInputDecoration(
            context,
            label: '이메일',
            suffixText: '@gmail.com',
            prefixIcon: const Icon(Icons.mail_rounded),
            errorText: _submitted && !_emailOk
                ? _emailController.text.trim().isEmpty
                    ? '이메일을 입력하세요.'
                    : '이메일을 다시 확인하세요.'
                : null,
          ),
        ),
      ],
    );
  }

  Widget _permissionEditor(BuildContext context) {
    return DropdownButtonFormField<TabletRoleType>(
      value: _role,
      isExpanded: true,
      decoration: opsInputDecoration(
        context,
        label: '권한',
        prefixIcon: const Icon(Icons.admin_panel_settings_rounded),
      ),
      items: TabletRoleType.values
          .map(
            (role) => DropdownMenuItem<TabletRoleType>(
              value: role,
              child: Text(role.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(growable: false),
      onChanged: (role) {
        if (role == null) return;
        setState(() => _role = role);
        widget.trace.log('권한 변경: role=${role.name}');
      },
    );
  }

  Widget _passwordEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _passwordController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_submitted) setState(() {});
          },
          enableSuggestions: false,
          autocorrect: false,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          decoration: opsInputDecoration(
            context,
            label: '비밀번호',
            prefixIcon: const Icon(Icons.password_rounded),
            suffixIcon: IconButton(
              tooltip: '복사',
              onPressed: _copyPassword,
              icon: const Icon(Icons.copy_rounded),
            ),
            errorText: _submitted && !_passwordOk
                ? '5자리 숫자 비밀번호를 입력하세요.'
                : null,
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _regeneratePassword,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('새 비밀번호 생성'),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    switch (widget.section) {
      case TabletSettingsSection.identity:
        return _identityEditor(context);
      case TabletSettingsSection.permission:
        return _permissionEditor(context);
      case TabletSettingsSection.password:
        return _passwordEditor(context);
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
