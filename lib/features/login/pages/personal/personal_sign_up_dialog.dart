import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../controllers/personal/personal_login_controller.dart';
import '../common/prompt_login_ui.dart';

class PersonalSignUpDialog extends StatefulWidget {
  const PersonalSignUpDialog({
    super.key,
    required this.controller,
  });

  final PersonalLoginController controller;

  @override
  State<PersonalSignUpDialog> createState() => _PersonalSignUpDialogState();
}

class _PersonalSignUpDialogState extends State<PersonalSignUpDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _gmailController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();
  final TextEditingController _divisionController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _gmailFocus = FocusNode();
  final FocusNode _areaFocus = FocusNode();
  final FocusNode _divisionFocus = FocusNode();

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _passwordController.text = widget.controller.generatePersonalPassword();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _gmailController.dispose();
    _areaController.dispose();
    _divisionController.dispose();
    _passwordController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _gmailFocus.dispose();
    _areaFocus.dispose();
    _divisionFocus.dispose();
    super.dispose();
  }

  String _normalizePhone(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _formatPhoneForDisplay(String digits) {
    if (digits.length <= 3) return digits;
    if (digits.length <= 7) {
      return '${digits.substring(0, 3)}-${digits.substring(3)}';
    }
    if (digits.length <= 10) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    final end = digits.length > 11 ? 11 : digits.length;
    return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7, end)}';
  }

  void _formatPhone(String value) {
    final digits = _normalizePhone(value);
    final limited = digits.length > 11 ? digits.substring(0, 11) : digits;
    final formatted = _formatPhoneForDisplay(limited);
    setState(() {
      _phoneController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      _errorMessage = null;
    });
  }

  void _formatGmail(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._%+@-]'), '');
    setState(() {
      _gmailController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
      _errorMessage = null;
    });
  }

  void _regeneratePassword() {
    if (_isSaving) return;
    setState(() {
      _passwordController.text = widget.controller.generatePersonalPassword();
      _errorMessage = null;
    });
  }

  Future<void> _copyPassword() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: password));
    if (!mounted) return;
    showPromptLoginSnack(
      context,
      message: '비밀번호를 복사했습니다.',
      success: true,
    );
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    final error = widget.controller.validatePersonalAccountCreateInputs(
      name: _nameController.text,
      phone: _phoneController.text,
      gmail: _gmailController.text,
      password: _passwordController.text,
      area: _areaController.text,
      division: _divisionController.text,
    );
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final result = await widget.controller.createPersonalAccount(
      name: _nameController.text,
      phone: _phoneController.text,
      gmail: _gmailController.text,
      password: _passwordController.text,
      area: _areaController.text,
      division: _divisionController.text,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.success) {
      widget.controller.fillLoginFields(
        name: _nameController.text,
        phone: _phoneController.text,
        password: result.password ?? _passwordController.text,
      );
      HapticFeedback.selectionClick();
      Navigator.of(context).pop(true);
      return;
    }

    setState(() => _errorMessage = result.message);
    showPromptLoginSnack(
      context,
      message: result.message,
      success: false,
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    FocusNode? focusNode,
    bool enabled = true,
    bool readOnly = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool autocorrect = true,
    bool enableSuggestions = true,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    List<TextInputFormatter>? inputFormatters,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      readOnly: readOnly,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      inputFormatters: inputFormatters,
      decoration: promptLoginInputDecoration(
        context,
        label: label,
        icon: icon,
        suffixIcon: suffixIcon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  borderRadius: BorderRadius.circular(PromptUiShapes.control),
                  border: Border.all(
                    color: tokens.accent.withOpacity(
                      tokens.isDark ? 0.62 : 0.42,
                    ),
                  ),
                ),
                child: Icon(
                  Icons.person_add_alt_1_rounded,
                  color: tokens.onAccentContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '개인형 회원가입',
                      style: textTheme.titleLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '개발자 모드에서 개인형 계정을 생성하고 로그인 입력값에 연결합니다.',
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              PromptIconButton(
                icon: Icons.close_rounded,
                tooltip: '닫기',
                onPressed:
                    _isSaving ? null : () => Navigator.of(context).pop(false),
                haptic: PromptHaptic.selection,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: tokens.borderSubtle),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _field(
                    controller: _nameController,
                    focusNode: _nameFocus,
                    enabled: !_isSaving,
                    label: '이름',
                    icon: Icons.person_rounded,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() => _errorMessage = null),
                    onSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(_phoneFocus),
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _phoneController,
                    focusNode: _phoneFocus,
                    enabled: !_isSaving,
                    label: '전화번호',
                    icon: Icons.phone_rounded,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    onChanged: _formatPhone,
                    onSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(_gmailFocus),
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _gmailController,
                    focusNode: _gmailFocus,
                    enabled: !_isSaving,
                    label: '지메일 계정',
                    icon: Icons.alternate_email_rounded,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: _formatGmail,
                    onSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(_areaFocus),
                  ),
                  const SizedBox(height: 8),
                  _PromptSignUpInfo(
                    icon: Icons.info_outline_rounded,
                    text: '지메일의 local-part 또는 전체 gmail.com 주소를 입력합니다.',
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _passwordController,
                    enabled: !_isSaving,
                    readOnly: true,
                    label: '자동 생성 비밀번호',
                    icon: Icons.lock_rounded,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(5),
                    ],
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        PromptIconButton(
                          icon: Icons.refresh_rounded,
                          tooltip: '비밀번호 재생성',
                          onPressed: _isSaving ? null : _regeneratePassword,
                          haptic: PromptHaptic.selection,
                          size: 40,
                          iconSize: 20,
                        ),
                        PromptIconButton(
                          icon: Icons.copy_rounded,
                          tooltip: '비밀번호 복사',
                          onPressed: _isSaving ? null : _copyPassword,
                          haptic: PromptHaptic.selection,
                          size: 40,
                          iconSize: 20,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PromptSignUpInfo(
                    icon: Icons.key_rounded,
                    text: '생성된 5자리 번호는 개인형 로그인 비밀번호로 사용됩니다.',
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _areaController,
                    focusNode: _areaFocus,
                    enabled: !_isSaving,
                    label: '지역',
                    icon: Icons.location_on_rounded,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() => _errorMessage = null),
                    onSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(_divisionFocus),
                  ),
                  const SizedBox(height: 8),
                  _PromptSignUpInfo(
                    icon: Icons.folder_outlined,
                    text: '계정 문서 ID는 전화번호와 지역을 조합해 생성됩니다.',
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _divisionController,
                    focusNode: _divisionFocus,
                    enabled: !_isSaving,
                    label: '구역',
                    icon: Icons.apartment_rounded,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() => _errorMessage = null),
                    onSubmitted: (_) {
                      if (!_isSaving) {
                        _create();
                      }
                    },
                  ),
                  AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : PromptUiMotion.component,
                    child: _errorMessage == null
                        ? const SizedBox.shrink(
                            key: ValueKey<String>('signup-error-hidden'),
                          )
                        : Padding(
                            key: const ValueKey<String>('signup-error-visible'),
                            padding: const EdgeInsets.only(top: 12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: tokens.dangerContainer,
                                borderRadius: BorderRadius.circular(
                                  PromptUiShapes.control,
                                ),
                                border: Border.all(
                                  color: tokens.danger.withOpacity(0.42),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: tokens.danger,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: tokens.onDangerContainer,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 360;
              final cancel = PromptButton(
                label: '취소',
                icon: Icons.close_rounded,
                variant: PromptButtonVariant.tertiary,
                expand: true,
                onPressed:
                    _isSaving ? null : () => Navigator.of(context).pop(false),
              );
              final create = PromptButton(
                label: _isSaving ? '생성 중' : '생성',
                icon: Icons.check_rounded,
                expand: true,
                loading: _isSaving,
                onPressed: _isSaving ? null : _create,
                haptic: PromptHaptic.light,
              );
              return narrow
                  ? Column(
                      children: <Widget>[
                        create,
                        const SizedBox(height: 8),
                        cancel,
                      ],
                    )
                  : Row(
                      children: <Widget>[
                        Expanded(child: cancel),
                        const SizedBox(width: 10),
                        Expanded(child: create),
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}

class _PromptSignUpInfo extends StatelessWidget {
  const _PromptSignUpInfo({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 17, color: tokens.iconSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
