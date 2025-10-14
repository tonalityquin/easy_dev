// lib/screens/login/tablet/sections/tablet_login_form.dart
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../../../../routes.dart';
import '../tablet_login_controller.dart';

class TabletLoginForm extends StatefulWidget {
  final TabletLoginController controller;

  const TabletLoginForm({super.key, required this.controller});

  @override
  State<TabletLoginForm> createState() => _TabletLoginFormState();
}

class _TabletLoginFormState extends State<TabletLoginForm> {
  late final TabletLoginController _controller;

  // Cyan 팔레트
  static const Color _base  = Color(0xFF00ACC1); // 버튼/배지/포커스
  static const Color _dark  = Color(0xFF00838F); // 타이틀/라벨(떠있을 때)

  @override
  void initState() {
    super.initState();
    _controller = widget.controller; // ✅ init은 상위(LoginScreen)에서만
  }

  void _handleLogin() {
    _controller.login(setState);
  }

  void _onLoginButtonPressed() {
    if (!_controller.isLoading) {
      _handleLogin();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 이 폼 하위에만 적용되는 테마(입력창/아이콘/라벨 컬러 조정)
    final themed = Theme.of(context).copyWith(
      inputDecorationTheme: InputDecorationTheme(
        // 라벨
        labelStyle: const TextStyle(color: Colors.black87),
        floatingLabelStyle: const TextStyle(
          color: _dark,
          fontWeight: FontWeight.w700,
        ),
        // 아이콘 컬러(Decoration의 icon / prefix/suffix)
        iconColor: _base,
        prefixIconColor: _base,
        suffixIconColor: _base,
        // 보더
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _base, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
        ),
        // 내용 패딩 기본값
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      // 버튼 계열 대비(아이콘 버튼 등) 미세 톤
      iconTheme: const IconThemeData(color: _base),
      // 버튼 배경/전경 기본
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _base,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(55),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
      ),
    );

    return Theme(
      data: themed,
      child: Material(
        // ✅ Material ancestor 보장
        color: Colors.transparent,
        child: SafeArea(
          child: SingleChildScrollView(
            // ✅ overflow 방지
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 12),

                // ⬇️ 화면 식별 태그(11시 고정 느낌으로 상단에 작게 표기)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Semantics(
                      label: 'screen_tag: tablet login',
                      child: const Text(
                        'tablet login',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ),

                GestureDetector(
                  child: SizedBox(
                    height: 360,
                    child: Image.asset('assets/images/easyvalet_logo_car.png'),
                  ),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: _controller.nameController,
                  focusNode: _controller.nameFocus,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_controller.phoneFocus),
                  decoration: _controller.inputDecoration(
                    label: "이름",
                    icon: Icons.person,
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _controller.phoneController,
                  // 핸들 입력용 컨트롤러 유지
                  focusNode: _controller.phoneFocus,
                  keyboardType: TextInputType.text, // ← 텍스트(핸들)
                  textCapitalization: TextCapitalization.none, // ← 자동 대문자 방지
                  autocorrect: false, // ← 자동 교정 끔
                  enableSuggestions: false, // ← 추천 끔
                  textInputAction: TextInputAction.next,
                  onChanged: (value) =>
                      _controller.formatPhoneNumber(value, setState),
                  onSubmitted: (_) => FocusScope.of(context)
                      .requestFocus(_controller.passwordFocus),
                  decoration: _controller.inputDecoration(
                    label: "영어 아이디(핸들)", // ← 라벨 명확화
                    icon: Icons.alternate_email, // ← 핸들 느낌 아이콘
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _controller.passwordController,
                  focusNode: _controller.passwordFocus,
                  obscureText: _controller.obscurePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _onLoginButtonPressed(),
                  decoration: _controller.inputDecoration(
                    label: "비밀번호(5자리 이상)",
                    icon: Icons.lock,
                    suffixIcon: IconButton(
                      style: IconButton.styleFrom(
                        foregroundColor: _base, // 눈아이콘 컬러 톤 맞춤
                      ),
                      icon: Icon(
                        _controller.obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _controller.togglePassword()),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.login),
                    label: Text(
                      _controller.isLoading ? '로딩 중...' : '태블릿 로그인',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    // 버튼 스타일은 Theme.elevatedButtonTheme로 통일
                    onPressed: _controller.isLoading ? null : _onLoginButtonPressed,
                  ),
                ),

                const SizedBox(height: 1),

                // ▼ 펠리컨: 탭하면 LoginSelectorPage로 복귀
                Center(
                  child: InkWell(
                    onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
                      AppRoutes.selector,
                          (route) => false,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 80,
                      child: Image.asset('assets/images/pelican.png'),
                    ),
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
