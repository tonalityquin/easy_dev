import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../routes.dart';
import '../../../../../theme.dart'; // ✅ AppCardPalette 사용 (theme.dart 연결)
import '../tablet_login_controller.dart';

// ✅ Trace 기록용 Recorder
import '../../../../../screens/hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

class TabletLoginForm extends StatefulWidget {
  final TabletLoginController controller;

  const TabletLoginForm({super.key, required this.controller});

  @override
  State<TabletLoginForm> createState() => _TabletLoginFormState();
}

class _TabletLoginFormState extends State<TabletLoginForm> {
  late final TabletLoginController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller; // ✅ init은 상위(LoginScreen)에서만
  }

  void _trace(String name, {Map<String, dynamic>? meta}) {
    // ✅ Trace 기록 (기록 중이 아닐 때는 Recorder 내부에서 무시됨)
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  void _handleLogin() {
    _controller.login(setState);
  }

  void _onLoginButtonPressed() {
    if (_controller.isLoading) return;

    // ✅ 태블릿 로그인 버튼 Trace 기록
    _trace(
      '태블릿 로그인 버튼',
      meta: <String, dynamic>{
        'screen': 'tablet_login',
        'action': 'login',
      },
    );

    _handleLogin();
  }

  void _onTopCompanyLogoTapped() {
    // ✅ 상단 회사 로고 탭 Trace 기록 (기존 동작 변경 없이 기록만)
    _trace(
      '회사 로고(상단)',
      meta: <String, dynamic>{
        'screen': 'tablet_login',
        'asset': 'assets/images/easyvalet_logo_car.png',
        'action': 'tap',
      },
    );

    HapticFeedback.selectionClick();
  }

  void _onPelicanLogoTapped() {
    // ✅ 하단 펠리컨 로고 탭 Trace 기록 + 기존 네비게이션 유지
    _trace(
      '회사 로고(펠리컨)',
      meta: <String, dynamic>{
        'screen': 'tablet_login',
        'asset': 'assets/images/pelican.png',
        'action': 'back_to_selector',
        'to': AppRoutes.selector,
      },
    );

    HapticFeedback.selectionClick();

    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.selector,
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ theme.dart(AppCardPalette)에서 Tablet 팔레트 획득
    final palette = AppCardPalette.of(context);
    final base = palette.tabletBase; // 기존 _base
    final dark = palette.tabletDark; // 기존 _dark

    // 이 폼 하위에만 적용되는 테마(입력창/아이콘/라벨 컬러 조정)
    final themed = Theme.of(context).copyWith(
      inputDecorationTheme: InputDecorationTheme(
        // 라벨
        labelStyle: const TextStyle(color: Colors.black87),
        floatingLabelStyle: TextStyle(
          color: dark,
          fontWeight: FontWeight.w700,
        ),
        // 아이콘 컬러(Decoration의 icon / prefix/suffix)
        iconColor: base,
        prefixIconColor: base,
        suffixIconColor: base,
        // 보더
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: base, width: 1.8),
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
      iconTheme: IconThemeData(color: base),
      // 버튼 배경/전경 기본
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: base,
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

                // ✅ 상단 회사 로고 탭 시 Trace 기록
                GestureDetector(
                  onTap: _onTopCompanyLogoTapped,
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
                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_controller.phoneFocus),
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
                  onChanged: (value) => _controller.formatPhoneNumber(value, setState),
                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_controller.passwordFocus),
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
                        foregroundColor: base, // ✅ tabletBase로 톤 맞춤
                      ),
                      icon: Icon(
                        _controller.obscurePassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _controller.togglePassword()),
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

                // ▼ 펠리컨: 탭하면 LoginSelectorPage로 복귀 + Trace 기록
                Center(
                  child: InkWell(
                    onTap: _onPelicanLogoTapped,
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
