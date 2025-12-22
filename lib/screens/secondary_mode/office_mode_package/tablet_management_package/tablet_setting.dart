// lib/screens/secondary_package/office_mode_package/tablet_management_package/tablet_setting.dart
import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../../models/tablet_model.dart';
import 'sections/tablet_password_display.dart';
import 'sections/tablet_role_type.dart';
import 'sections/tablet_input_section.dart';
import 'sections/tablet_role_dropdown_section.dart';
import 'sections/tablet_validation_helpers.dart';

// ✅ AppCardPalette 정의가 있는 파일을 프로젝트 경로에 맞게 import 하세요.
// 예) import 'package:your_app/theme/app_theme.dart';
// 예) import 'package:your_app/theme/app_card_palette.dart';
import '../../../../../../theme.dart';

class TabletSettingBottomSheet extends StatefulWidget {
  /// onSave 시그니처 유지
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
  State<TabletSettingBottomSheet> createState() =>
      _TabletSettingBottomSheetState();
}

class _TabletSettingBottomSheetState extends State<TabletSettingBottomSheet> {
  // 좌측 상단(11시) 라벨 텍스트
  static const String _screenTag = 'tablet setting';

  // --- Controllers & Focus ---
  final _nameController = TextEditingController();
  final _handleController = TextEditingController(); // 소문자 영문 아이디
  final _emailController = TextEditingController(); // 로컬파트만 입력
  final _passwordController = TextEditingController();

  final _nameFocus = FocusNode();
  final _handleFocus = FocusNode();
  final _emailFocus = FocusNode();

  // --- States ---
  TabletRoleType _selectedRole = TabletRoleType.lowField;
  String? _errorMessage;

  // --- UI: 단계형(확장패널) 구성 ---
  static const int _panelBasic = 0;
  static const int _panelRole = 1;
  static const int _panelPassword = 2;

  late final List<bool> _expanded;
  final ScrollController _scrollController = ScrollController();

  final GlobalKey _keyBasic = GlobalKey();
  final GlobalKey _keyRole = GlobalKey();
  final GlobalKey _keyPassword = GlobalKey();

  @override
  void initState() {
    super.initState();

    _expanded = List<bool>.filled(3, false);
    _expanded[_panelBasic] = true;

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

    // 포커스 이동 시 해당 섹션으로 열고 스크롤
    _nameFocus.addListener(() {
      if (_nameFocus.hasFocus) _openPanelAndScroll(_panelBasic);
    });
    _handleFocus.addListener(() {
      if (_handleFocus.hasFocus) _openPanelAndScroll(_panelBasic);
    });
    _emailFocus.addListener(() {
      if (_emailFocus.hasFocus) _openPanelAndScroll(_panelBasic);
    });
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

    _scrollController.dispose();
    super.dispose();
  }

  // --- Helpers (로직 유지) ---

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

  void _clearErrorIfAny() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  // 로컬파트 검증: 영문/숫자/._- 만 허용
  bool _isValidEmailLocalPart(String input) {
    final reg = RegExp(r'^[a-zA-Z0-9._-]+$');
    return input.isNotEmpty && reg.hasMatch(input);
  }

  // 아이디 규칙(검증 helpers와 동일 기준)
  bool _isValidHandle(String input) {
    return RegExp(r'^[a-z]{3,20}$').hasMatch(input);
  }

  String _generateRandomPassword() {
    final random = Random();
    return (10000 + random.nextInt(90000)).toString(); // 5자리 숫자
  }

  // 11시 라벨 위젯
  Widget _buildScreenTag(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ??
        const TextStyle(
          fontSize: 11,
          color: Colors.black54,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 4),
          child: Semantics(
            label: 'screen_tag: $_screenTag',
            child: Text(_screenTag, style: style),
          ),
        ),
      ),
    );
  }

  // --- UI Helpers: 요약/완료/스크롤 ---

  bool get _isBasicInfoComplete {
    final nameOk = _nameController.text.trim().isNotEmpty;
    final handleOk = _isValidHandle(_handleController.text.trim());
    final emailOk = _emailController.text.trim().isNotEmpty;
    final emailLocalOk = _isValidEmailLocalPart(_emailController.text.trim());
    return nameOk && handleOk && emailOk && emailLocalOk;
  }

  String get _basicSummary {
    final name = _nameController.text.trim();
    final handle = _handleController.text.trim();
    final email = _emailController.text.trim();
    final shownName = name.isEmpty ? '이름 미입력' : name;
    final shownHandle = handle.isEmpty ? '아이디 미입력' : handle;
    final shownEmail = email.isEmpty ? '이메일 미입력' : '$email@gmail.com';
    return '$shownName · $shownHandle · $shownEmail';
  }

  String get _roleSummary => _selectedRole.label;

  void _openPanelAndScroll(int panelIndex) {
    if (!mounted) return;

    setState(() {
      for (int i = 0; i < _expanded.length; i++) {
        _expanded[i] = i == panelIndex;
      }
    });

    GlobalKey key = _keyBasic;
    if (panelIndex == _panelRole) key = _keyRole;
    if (panelIndex == _panelPassword) key = _keyPassword;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.12,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildPanelHeader({
    required Color base,
    required Color dark,
    required Color light,
    required int step,
    required String title,
    required String summary,
    required bool isDone,
    required bool isExpanded,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isExpanded ? base.withOpacity(.12) : light.withOpacity(.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isExpanded ? base.withOpacity(.35) : light.withOpacity(.35),
          ),
        ),
        child: Center(
          child: isDone
              ? Icon(Icons.check, color: dark, size: 20)
              : Text(
            '$step',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: dark,
            ),
          ),
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: dark,
        ),
      ),
      subtitle: Text(
        summary,
        style: TextStyle(
          color: Colors.black.withOpacity(.60),
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Icon(
        isExpanded ? Icons.expand_less : Icons.expand_more,
        color: dark,
      ),
    );
  }

  Widget _buildPanelBody({
    required Color dark,
    required Color light,
    required Widget child,
    int? nextPanel,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          if (nextPanel != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openPanelAndScroll(nextPanel),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('다음 단계로 이동'),
              style: OutlinedButton.styleFrom(
                foregroundColor: dark,
                side: BorderSide(color: light.withOpacity(.75)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final palette = AppCardPalette.of(context);
    final base = palette.serviceBase;
    final dark = palette.serviceDark;
    final light = palette.serviceLight;
    const fg = Colors.white;

    final isEditMode = widget.isEditMode || (widget.initialUser != null);

    // 최상단까지 차오르도록 높이 고정 + 키보드 여백 반영
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final effectiveHeight = screenHeight - bottomInset;

    return SafeArea(
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SizedBox(
              height: effectiveHeight,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
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

                    // 타이틀 + 지역 pill
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: light.withOpacity(.20),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: light.withOpacity(.45),
                            ),
                          ),
                          child: Icon(
                            Icons.tablet_mac_rounded,
                            color: dark,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isEditMode ? '태블릿 사용자 수정' : '태블릿 사용자 생성',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: dark,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: light.withOpacity(.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: light.withOpacity(.35),
                            ),
                          ),
                          child: Text(
                            widget.areaValue,
                            style: TextStyle(
                              color: dark,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 입력 가이드
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: light.withOpacity(.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: light.withOpacity(.25)),
                      ),
                      child: Text(
                        '단계별로 하나씩 입력하세요. 완료된 단계는 체크 표시로 바뀝니다.',
                        style: TextStyle(
                          color: dark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 본문(단계형)
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: ExpansionPanelList(
                          expansionCallback: (index, isExpanded) {
                            _clearErrorIfAny();
                            setState(() {
                              for (int i = 0; i < _expanded.length; i++) {
                                _expanded[i] =
                                (i == index) ? !isExpanded : false;
                              }
                            });
                          },
                          children: [
                            // 1) 기본 정보
                            ExpansionPanel(
                              canTapOnHeader: true,
                              isExpanded: _expanded[_panelBasic],
                              headerBuilder: (ctx, _) => KeyedSubtree(
                                key: _keyBasic,
                                child: _buildPanelHeader(
                                  base: base,
                                  dark: dark,
                                  light: light,
                                  step: 1,
                                  title: '기본 정보',
                                  summary: _basicSummary,
                                  isDone: _isBasicInfoComplete,
                                  isExpanded: _expanded[_panelBasic],
                                ),
                              ),
                              body: _buildPanelBody(
                                dark: dark,
                                light: light,
                                nextPanel: _panelRole,
                                child: TabletInputSection(
                                  nameController: _nameController,
                                  handleController: _handleController,
                                  emailController: _emailController,
                                  nameFocus: _nameFocus,
                                  handleFocus: _handleFocus,
                                  emailFocus: _emailFocus,
                                  errorMessage: _errorMessage,
                                  onEdited: _clearErrorIfAny,
                                  emailLocalPartValidator:
                                  _isValidEmailLocalPart,
                                ),
                              ),
                            ),

                            // 2) 권한
                            ExpansionPanel(
                              canTapOnHeader: true,
                              isExpanded: _expanded[_panelRole],
                              headerBuilder: (ctx, _) => KeyedSubtree(
                                key: _keyRole,
                                child: _buildPanelHeader(
                                  base: base,
                                  dark: dark,
                                  light: light,
                                  step: 2,
                                  title: '권한',
                                  summary: _roleSummary,
                                  isDone: true,
                                  isExpanded: _expanded[_panelRole],
                                ),
                              ),
                              body: _buildPanelBody(
                                dark: dark,
                                light: light,
                                nextPanel: _panelPassword,
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: light.withOpacity(.06),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: light.withOpacity(.35),
                                    ),
                                  ),
                                  child: TabletRoleDropdownSection(
                                    selectedRole: _selectedRole,
                                    onChanged: (value) {
                                      _clearErrorIfAny();
                                      setState(() => _selectedRole = value);
                                    },
                                  ),
                                ),
                              ),
                            ),

                            // 3) 비밀번호
                            ExpansionPanel(
                              canTapOnHeader: true,
                              isExpanded: _expanded[_panelPassword],
                              headerBuilder: (ctx, _) => KeyedSubtree(
                                key: _keyPassword,
                                child: _buildPanelHeader(
                                  base: base,
                                  dark: dark,
                                  light: light,
                                  step: 3,
                                  title: '비밀번호',
                                  summary: '자동 생성/복사 가능',
                                  isDone: _passwordController.text
                                      .trim()
                                      .isNotEmpty,
                                  isExpanded: _expanded[_panelPassword],
                                ),
                              ),
                              body: _buildPanelBody(
                                dark: dark,
                                light: light,
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                                  children: [
                                    TabletPasswordDisplay(
                                      controller: _passwordController,
                                      enableMonospace: true,
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: light.withOpacity(.06),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: light.withOpacity(.25),
                                        ),
                                      ),
                                      child: Text(
                                        '비밀번호는 읽기 전용입니다. 우측 복사 버튼으로 전달하세요.',
                                        style: TextStyle(
                                          color: dark,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // 전역 에러 박스
                    if (_errorMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.error.withOpacity(.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.error.withOpacity(.30)),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: cs.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),

                    // 하단 버튼
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: dark,
                              side: BorderSide(color: light.withOpacity(.75)),
                              shape: const StadiumBorder(),
                              padding:
                              const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('취소'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              FocusScope.of(context).unfocus();

                              // 1) 필드 검증 (로직 유지)
                              if (!_validateInputs()) {
                                _openPanelAndScroll(_panelBasic);
                                return;
                              }

                              // 2) 이메일 로컬파트 추가 검증 (로직 유지)
                              if (!_isValidEmailLocalPart(
                                  _emailController.text)) {
                                _setErrorMessage('이메일을 다시 확인하세요');
                                _openPanelAndScroll(_panelBasic);
                                return;
                              }

                              final fullEmail =
                                  '${_emailController.text}@gmail.com';

                              // 3) 저장 콜백 (로직 유지)
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
                              backgroundColor: base,
                              foregroundColor: fg,
                              shape: const StadiumBorder(),
                              padding:
                              const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
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

          // 11시 라벨 오버레이
          _buildScreenTag(context),
        ],
      ),
    );
  }
}
