import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../app/utils/snackbar_helper.dart';
import '../../../../../shared/auth/five_digit_password_generator.dart';
import '../../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../domain/models/tablet/tablet_model.dart';
import 'widgets/tablet_role_type.dart';

class TabletSettingBottomSheet extends StatefulWidget {
  final Function(
    String name,
    String handle,
    String email,
    String role,
    String password,
    String area,
    String division,
  ) onSave;

  final String areaValue;
  final String division;
  final TabletModel? initialUser;
  final bool isEditMode;

  const TabletSettingBottomSheet({
    super.key,
    required this.onSave,
    required this.areaValue,
    required this.division,
    this.initialUser,
    this.isEditMode = false,
  });

  @override
  State<TabletSettingBottomSheet> createState() => _TabletSettingBottomSheetState();
}

class _TabletSettingBottomSheetState extends State<TabletSettingBottomSheet> {
  final _nameController = TextEditingController();
  final _handleController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _nameFocus = FocusNode();
  final _handleFocus = FocusNode();
  final _emailFocus = FocusNode();

  TabletRoleType _selectedRole = TabletRoleType.lowField;
  String? _errorMessage;

  bool get isEditMode => widget.isEditMode;
  bool get _nameOk => _nameController.text.trim().isNotEmpty;
  bool get _handleOk => RegExp(r'^[a-z]{3,20}$').hasMatch(_handleController.text.trim());
  bool get _emailOk => _emailController.text.trim().isNotEmpty && _isValidEmailLocalPart(_emailController.text.trim());

  @override
  void initState() {
    super.initState();
    final user = widget.initialUser;
    if (user != null) {
      _nameController.text = user.name;
      _handleController.text = user.handle;
      _emailController.text = user.email.split('@').first;
      _passwordController.text = user.password;
      _selectedRole = TabletRoleType.values.firstWhere(
        (role) => role.name == user.role,
        orElse: () => TabletRoleType.lowField,
      );
    } else {
      _passwordController.text = FiveDigitPasswordGenerator.generate();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _handleController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameFocus.dispose();
    _handleFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  bool _isValidEmailLocalPart(String input) {
    return RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(input.trim());
  }

  void _setErrorMessage(String? message) {
    setState(() => _errorMessage = message);
  }

  void _clearErrorIfAny() {
    setState(() => _errorMessage = null);
  }

  Future<void> _copyPassword() async {
    await Clipboard.setData(ClipboardData(text: _passwordController.text));
    if (!mounted) return;
    showSelectedSnackbar(
      context,
      '태블릿 비밀번호를 복사했습니다.',
      usePromptUi: true,
    );
  }

  void _handleSave() {
    FocusScope.of(context).unfocus();
    if (!_nameOk) {
      _setErrorMessage('태블릿 이름을 입력하세요');
      return;
    }
    if (!_handleOk) {
      _setErrorMessage('아이디는 소문자 영어 3~20자로 입력하세요');
      return;
    }
    if (!_emailOk) {
      _setErrorMessage(_emailController.text.trim().isEmpty ? '이메일을 입력하세요' : '이메일을 다시 확인하세요');
      return;
    }

    widget.onSave(
      _nameController.text.trim(),
      _handleController.text.trim(),
      '${_emailController.text.trim()}@gmail.com',
      _selectedRole.name,
      _passwordController.text.trim(),
      widget.areaValue,
      widget.division,
    );

    if (mounted) Navigator.pop(context);
  }

  Widget _buildIdentitySection(BuildContext context) {
    return OpsWorkSection(
      title: '태블릿 식별 정보',
      subtitle: isEditMode ? '운영 단말의 이름, 핸들, 구글 이메일을 갱신합니다.' : '현장에 배정할 태블릿 계정의 식별값을 등록합니다.',
      icon: Icons.tablet_mac_rounded,
      child: Column(
        children: [
          TextField(
            controller: _nameController,
            focusNode: _nameFocus,
            onChanged: (_) => _clearErrorIfAny(),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: opsInputDecoration(
              context,
              label: '태블릿 이름',
              prefixIcon: const Icon(Icons.tablet_mac_rounded),
              errorText: _errorMessage == '태블릿 이름을 입력하세요' ? _errorMessage : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _handleController,
            focusNode: _handleFocus,
            onChanged: (_) => _clearErrorIfAny(),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-z]')), LengthLimitingTextInputFormatter(20)],
            decoration: opsInputDecoration(
              context,
              label: '태블릿 아이디',
              prefixIcon: const Icon(Icons.alternate_email_rounded),
              errorText: _errorMessage == '아이디는 소문자 영어 3~20자로 입력하세요' ? _errorMessage : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            focusNode: _emailFocus,
            onChanged: (_) => _clearErrorIfAny(),
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.emailAddress,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            decoration: opsInputDecoration(
              context,
              label: '이메일',
              suffixText: '@gmail.com',
              prefixIcon: const Icon(Icons.mail_rounded),
              errorText: (_errorMessage == '이메일을 입력하세요' || _errorMessage == '이메일을 다시 확인하세요') ? _errorMessage : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OpsWorkSection(
      title: '운영 권한',
      subtitle: '태블릿 단말이 수행할 수 있는 현장 역할을 지정합니다.',
      icon: Icons.security_rounded,
      trailing: OpsStatusBadge(label: _selectedRole.label, color: cs.primary, icon: Icons.verified_user_rounded),
      child: DropdownButtonFormField<TabletRoleType>(
        value: _selectedRole,
        isExpanded: true,
        decoration: opsInputDecoration(context, label: '권한', prefixIcon: const Icon(Icons.admin_panel_settings_rounded)),
        items: TabletRoleType.values
            .map((role) => DropdownMenuItem<TabletRoleType>(
                  value: role,
                  child: Text(role.label, overflow: TextOverflow.ellipsis),
                ))
            .toList(growable: false),
        onChanged: (role) {
          if (role == null) return;
          _clearErrorIfAny();
          setState(() => _selectedRole = role);
        },
      ),
    );
  }

  Widget _buildPasswordSection(BuildContext context) {
    return OpsWorkSection(
      title: '단말 로그인 비밀번호',
      subtitle: '자동 생성된 비밀번호를 태블릿 초기 세팅 시 사용합니다.',
      icon: Icons.lock_rounded,
      child: TextField(
        controller: _passwordController,
        readOnly: true,
        enableSuggestions: false,
        autocorrect: false,
        decoration: opsInputDecoration(
          context,
          label: '비밀번호',
          prefixIcon: const Icon(Icons.password_rounded),
          suffixIcon: IconButton(
            tooltip: '복사',
            onPressed: _copyPassword,
            icon: const Icon(Icons.copy_rounded),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = isEditMode ? '태블릿 계정 수정' : '태블릿 등록';
    final subtitle = isEditMode ? '현장 단말의 배정 정보와 권한을 갱신합니다.' : '운영 구역에 배정할 태블릿 계정을 프로비저닝합니다.';
    final areaLabel = widget.division.trim().isEmpty ? widget.areaValue : '${widget.division} · ${widget.areaValue}';

    return OpsWorkSheet(
      title: title,
      subtitle: subtitle,
      icon: Icons.tablet_mac_rounded,
      areaLabel: areaLabel,
      metrics: [
        OpsMetric(label: '이름', value: _nameOk ? '완료' : '필수', icon: Icons.tablet_rounded, color: _nameOk ? cs.primary : cs.error),
        OpsMetric(label: '아이디', value: _handleOk ? '정상' : '검증', icon: Icons.alternate_email_rounded, color: _handleOk ? cs.primary : cs.error),
        OpsMetric(label: '권한', value: _selectedRole.label, icon: Icons.security_rounded, color: cs.primary),
        OpsMetric(label: '이메일', value: _emailOk ? '정상' : '필수', icon: Icons.mail_rounded, color: _emailOk ? cs.primary : cs.error),
      ],
      bottomBar: OpsBottomActionBar(
        children: [
          Expanded(
            child: OpsActionButton(
              label: '취소',
              icon: Icons.close_rounded,
              onPressed: () => Navigator.pop(context),
              tonal: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OpsActionButton(
              label: isEditMode ? '태블릿 수정' : '태블릿 등록',
              icon: isEditMode ? Icons.save_rounded : Icons.add_to_queue_rounded,
              onPressed: _handleSave,
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpsInlineMessage(message: _errorMessage),
          OpsCommandPanel(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OpsInfoPill(text: isEditMode ? '수정 모드' : '등록 모드', icon: isEditMode ? Icons.edit_rounded : Icons.add_to_queue_rounded),
                  OpsInfoPill(text: _selectedRole.label, icon: Icons.verified_user_rounded),
                  OpsInfoPill(text: widget.areaValue.trim().isEmpty ? '지역 미설정' : widget.areaValue, icon: Icons.business_rounded),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildIdentitySection(context),
          _buildRoleSection(context),
          _buildPasswordSection(context),
        ],
      ),
    );
  }
}
