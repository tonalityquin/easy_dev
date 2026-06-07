import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/personal/personal_login_controller.dart';

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

  void _showSnack(String message, {required bool success}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  String _normalizePhone(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _formatPhoneForDisplay(String digits) {
    if (digits.length <= 3) return digits;
    if (digits.length <= 7) return '${digits.substring(0, 3)}-${digits.substring(3)}';
    if (digits.length <= 10) return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
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
    final normalized = value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9._%+@-]'), '');
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
    _showSnack('비밀번호를 복사했습니다.', success: true);
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showSnack(result.message, success: true);
      });
      return;
    }

    setState(() => _errorMessage = result.message);
    _showSnack(result.message, success: false);
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    String? helperText,
    Widget? suffixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: cs.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.primary, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AlertDialog(
      icon: Icon(Icons.person_add_alt_1_rounded, color: cs.primary),
      title: const Text('개인형 회원가입'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '개발자 모드에서 personal_accounts에 전화번호-지역 문서 ID와 자동 생성 5자리 비밀번호로 개인형 계정을 생성합니다.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                focusNode: _nameFocus,
                enabled: !_isSaving,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() => _errorMessage = null),
                onSubmitted: (_) => FocusScope.of(context).requestFocus(_phoneFocus),
                decoration: _decoration(
                  label: '이름',
                  icon: Icons.person,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                focusNode: _phoneFocus,
                enabled: !_isSaving,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                onChanged: _formatPhone,
                onSubmitted: (_) => FocusScope.of(context).requestFocus(_gmailFocus),
                decoration: _decoration(
                  label: '전화번호',
                  icon: Icons.phone,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _gmailController,
                focusNode: _gmailFocus,
                enabled: !_isSaving,
                keyboardType: TextInputType.emailAddress,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                onChanged: _formatGmail,
                onSubmitted: (_) => FocusScope.of(context).requestFocus(_areaFocus),
                decoration: _decoration(
                  label: '지메일 계정',
                  icon: Icons.alternate_email,
                  helperText: 'local-part 또는 전체 gmail.com 주소를 입력하세요.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                enabled: !_isSaving,
                readOnly: true,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                decoration: _decoration(
                  label: '자동 생성 비밀번호',
                  icon: Icons.lock_rounded,
                  helperText: '생성 후 개인형 로그인 비밀번호로 사용됩니다.',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        onPressed: _isSaving ? null : _regeneratePassword,
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: '재생성',
                      ),
                      IconButton(
                        onPressed: _isSaving ? null : _copyPassword,
                        icon: const Icon(Icons.copy_rounded),
                        tooltip: '복사',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _areaController,
                focusNode: _areaFocus,
                enabled: !_isSaving,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() => _errorMessage = null),
                onSubmitted: (_) => FocusScope.of(context).requestFocus(_divisionFocus),
                decoration: _decoration(
                  label: '지역',
                  icon: Icons.location_on_rounded,
                  helperText: '문서 ID는 전화번호-지역 구조로 생성됩니다.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _divisionController,
                focusNode: _divisionFocus,
                enabled: !_isSaving,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _errorMessage = null),
                onSubmitted: (_) {
                  if (!_isSaving) {
                    _create();
                  }
                },
                decoration: _decoration(
                  label: '구역',
                  icon: Icons.apartment_rounded,
                ),
              ),
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: cs.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _create,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(_isSaving ? '생성 중...' : '생성'),
        ),
      ],
    );
  }
}
