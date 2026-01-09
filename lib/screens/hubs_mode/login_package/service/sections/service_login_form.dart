import 'package:flutter/material.dart';

import '../../../../../routes.dart'; // ✅ AppRoutes 사용 (경로는 현재 파일 위치 기준)
import '../../../../../theme.dart'; // ✅ AppCardPalette 사용 (theme.dart 연결)
import '../service_login_controller.dart';

// ✅ Trace 기록용 Recorder
import '../../../../../screens/hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

class ServiceLoginForm extends StatefulWidget {
  final ServiceLoginController controller;

  const ServiceLoginForm({super.key, required this.controller});

  @override
  State<ServiceLoginForm> createState() => _ServiceLoginFormState();
}

class _ServiceLoginFormState extends State<ServiceLoginForm> {
  late final ServiceLoginController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller; // ✅ init은 상위(LoginScreen)에서만 수행
  }

  // ✅ 공통 Trace 기록 헬퍼
  void _trace(String name, {Map<String, dynamic>? meta}) {
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

    // ✅ 서비스 로그인 버튼 Trace 기록
    _trace(
      '서비스 로그인 버튼',
      meta: <String, dynamic>{
        'screen': 'service_login',
        'action': 'login',
      },
    );

    _handleLogin();
  }

  void _onTopCompanyLogoTapped() {
    // ✅ 상단 회사 로고 탭 Trace 기록 (기존 동작 없음 유지)
    _trace(
      '회사 로고(상단)',
      meta: <String, dynamic>{
        'screen': 'service_login',
        'asset': 'assets/images/easyvalet_logo_car.png',
        'action': 'tap',
      },
    );
  }

  void _onPelicanLogoTapped() {
    // ✅ 하단 펠리컨 로고 탭 Trace 기록 + 기존 네비게이션 유지
    _trace(
      '회사 로고(펠리컨)',
      meta: <String, dynamic>{
        'screen': 'service_login',
        'asset': 'assets/images/pelican.png',
        'action': 'back_to_selector',
        'to': AppRoutes.selector,
      },
    );

    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.selector,
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);

    // ✅ theme.dart(AppCardPalette)에서 Service 팔레트 획득
    final palette = AppCardPalette.of(context);
    final base = palette.serviceBase; // 기존 _base
    final light = palette.serviceLight; // 기존 _light

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Theme(
          // ✅ 서비스 로그인 폼에만 팔레트 적용 (theme.dart 기반)
          data: baseTheme.copyWith(
            colorScheme: baseTheme.colorScheme.copyWith(
              primary: base,
              onPrimary: Colors.white,
              primaryContainer: light,
              onPrimaryContainer: Colors.white,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: base,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(55),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 1.5,
                shadowColor: base.withOpacity(0.25),
              ),
            ),
            iconButtonTheme: IconButtonThemeData(
              style: IconButton.styleFrom(
                foregroundColor: base,
                splashFactory: InkRipple.splashFactory,
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              // 라벨/힌트 기본은 테마 그대로 두고, 포커스/아이콘 색만 액센트
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: base, width: 1.6),
                borderRadius: BorderRadius.circular(10),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.black.withOpacity(0.15)),
                borderRadius: BorderRadius.circular(10),
              ),
              prefixIconColor: MaterialStateColor.resolveWith(
                    (states) => states.contains(MaterialState.focused) ? base : Colors.black54,
              ),
              suffixIconColor: MaterialStateColor.resolveWith(
                    (states) => states.contains(MaterialState.focused) ? base : Colors.black54,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: base,
              selectionColor: light.withOpacity(.35),
              selectionHandleColor: base,
            ),
          ),
          child: SingleChildScrollView(
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
                      label: 'screen_tag: service login',
                      child: const Text(
                        'service login',
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

                // ✅ 로고 탭 Trace 기록 (기존: onTap 빈 함수) → 기록만 남기도록 개선
                GestureDetector(
                  onTap: _onTopCompanyLogoTapped,
                  child: SizedBox(
                    height: 360,
                    child: Image.asset('assets/images/easyvalet_logo_car.png'),
                  ),
                ),

                const SizedBox(height: 12),

                // 이름
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

                // 전화번호
                TextField(
                  controller: _controller.phoneController,
                  focusNode: _controller.phoneFocus,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  onChanged: (value) => _controller.formatPhoneNumber(value, setState),
                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_controller.passwordFocus),
                  decoration: _controller.inputDecoration(
                    label: "전화번호",
                    icon: Icons.phone,
                  ),
                ),
                const SizedBox(height: 16),

                // 비밀번호
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
                      icon: Icon(_controller.obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _controller.togglePassword()),
                      tooltip: _controller.obscurePassword ? '표시' : '숨기기',
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ▶ 버튼 라벨: "서비스 로그인"
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.login),
                    label: Text(
                      _controller.isLoading ? '로딩 중...' : '서비스 로그인',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
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
