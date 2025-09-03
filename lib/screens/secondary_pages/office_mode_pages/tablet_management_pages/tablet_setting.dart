import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../models/tablet_model.dart';
import 'sections/tablet_password_display.dart';
import 'sections/tablet_role_type.dart';
import 'sections/tablet_input_section.dart';
import 'sections/tablet_role_dropdown_section.dart';
import 'sections/tablet_validation_helpers.dart';

class TabletSettingBottomSheet extends StatefulWidget {
  /// 축소안: onSave 시그니처 최소화
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
  // --- Controllers & Focus ---
  final _nameController = TextEditingController();
  final _handleController = TextEditingController(); // 소문자 영문 아이디
  final _emailController = TextEditingController();  // 로컬파트만 입력
  final _passwordController = TextEditingController();

  final _nameFocus = FocusNode();
  final _handleFocus = FocusNode();
  final _emailFocus = FocusNode();

  // --- States ---
  TabletRoleType _selectedRole = TabletRoleType.lowField;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final user = widget.initialUser;

    if (user != null) {
      _nameController.text = user.name;
      _handleController.text = user.handle;
      _emailController.text = user.email.split('@').first; // 로컬파트
      _passwordController.text = user.password;
      _selectedRole = TabletRoleType.values.firstWhere(
            (r) => r.name == user.role,
        orElse: () => TabletRoleType.lowField,
      );
    } else {
      _passwordController.text = _generateRandomPassword();
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

  // --- Helpers ---

  bool _validateInputs() {
    final error = validateInputs({
      '이름': _nameController.text,
      '아이디': _handleController.text,
      '이메일': _emailController.text, // 로컬파트
    });
    _setErrorMessage(error);
    return error == null;
  }

  void _setErrorMessage(String? message) {
    setState(() => _errorMessage = message);
  }

  // 로컬파트 검증: 영문/숫자/._- 만 허용
  bool _isValidEmailLocalPart(String input) {
    final reg = RegExp(r'^[a-zA-Z0-9._-]+$');
    return input.isNotEmpty && reg.hasMatch(input);
  }

  String _generateRandomPassword() {
    final random = Random();
    return (10000 + random.nextInt(90000)).toString(); // 5자리 숫자
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isEditMode = widget.isEditMode || (widget.initialUser != null);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: theme.dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                const Text(
                  '👤 사용자 정보',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // 입력 섹션(이름/아이디/이메일 로컬파트)
                TabletInputSection(
                  nameController: _nameController,
                  handleController: _handleController,
                  emailController: _emailController,
                  nameFocus: _nameFocus,
                  handleFocus: _handleFocus,
                  emailFocus: _emailFocus,
                  errorMessage: _errorMessage,
                ),
                const SizedBox(height: 16),

                // 권한 드롭다운
                TabletRoleDropdownSection(
                  selectedRole: _selectedRole,
                  onChanged: (value) => setState(() => _selectedRole = value),
                ),
                const SizedBox(height: 16),

                // 비밀번호 표시
                TabletPasswordDisplay(controller: _passwordController),

                const SizedBox(height: 16),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '현재 지역: ${widget.areaValue}',
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 24),

                // 하단 버튼
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          FocusScope.of(context).unfocus();

                          // 1) 필드 검증
                          if (!_validateInputs()) return;

                          // 2) 이메일 로컬파트 추가 검증
                          if (!_isValidEmailLocalPart(_emailController.text)) {
                            _setErrorMessage('이메일을 다시 확인하세요');
                            return;
                          }

                          final fullEmail = '${_emailController.text}@gmail.com';

                          // 3) 저장 콜백
                          widget.onSave(
                            _nameController.text,
                            _handleController.text,
                            fullEmail,
                            _selectedRole.name,
                            _passwordController.text,
                            widget.areaValue,
                            widget.division,
                          );

                          // onSave가 async여도 즉시 닫음
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                        ),
                        child: Text(isEditMode ? '수정' : '생성'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
