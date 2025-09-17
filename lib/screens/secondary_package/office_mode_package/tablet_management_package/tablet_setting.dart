import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../models/tablet_model.dart';
import 'sections/tablet_password_display.dart';
import 'sections/tablet_role_type.dart';
import 'sections/tablet_input_section.dart';
import 'sections/tablet_role_dropdown_section.dart';
import 'sections/tablet_validation_helpers.dart';

/// 서비스(로그인 카드)와 동일 계열 팔레트
class _SvcColors {
  static const base = Color(0xFF0D47A1);  // primary
  static const dark = Color(0xFF09367D);  // 진한 텍스트/아이콘
}

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
    final isEditMode = widget.isEditMode || (widget.initialUser != null);

    // ✅ 최상단까지 차오르도록 높이 고정 + 키보드 여백 반영
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final effectiveHeight = screenHeight - bottomInset;

    final titleStyle = const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: _SvcColors.dark, // 서비스 톤 적용
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset), // 키보드 여백
        child: SizedBox(
          height: effectiveHeight, // 화면 높이(키보드 제외)만큼 고정
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: _SvcColors.base.withOpacity(.06)), // 미세한 톤 라인
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
                      color: _SvcColors.base.withOpacity(.25), // 서비스 톤으로 살짝
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // 헤더
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                        color: _SvcColors.base,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.tablet_mac_rounded, size: 16, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text('사용자 정보', style: titleStyle),
                  ],
                ),
                const SizedBox(height: 16),

                // ===== 본문 스크롤 영역 =====
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _SvcColors.dark, // 포인트 컬러
                            ),
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
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ===== 하단 버튼 =====
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _SvcColors.base,
                          side: BorderSide(color: _SvcColors.base.withOpacity(.35)),
                        ),
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

                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _SvcColors.base, // 서비스 톤
                          foregroundColor: Colors.white,
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
