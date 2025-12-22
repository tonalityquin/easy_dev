import 'package:flutter/material.dart';
import '../../../../../routes.dart';
import '../../../../../theme.dart';
import '../lite_login_controller.dart';

class LiteLoginForm extends StatefulWidget {
  final LiteLoginController controller;

  const LiteLoginForm({super.key, required this.controller});

  @override
  State<LiteLoginForm> createState() => _LiteLoginFormState();
}

class _LiteLoginFormState extends State<LiteLoginForm> {
  late final LiteLoginController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller; // ✅ init은 상위(LoginScreen)에서만 수행
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
    final baseTheme = Theme.of(context);

    // ✅ theme.dart(AppCardPalette)에서 Lite 팔레트 획득
    final palette = AppCardPalette.of(context);
    final base = palette.liteBase; // 기존 _base
    final dark = palette.liteDark; // 기존 _dark
    final light = palette.liteLight; // 기존 _light

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Theme(
          // ✅ 서비스 로그인 폼과 동일한 UI 구조 + Lite 팔레트만 theme.dart 기반으로 적용
          data: baseTheme.copyWith(
            colorScheme: baseTheme.colorScheme.copyWith(
              primary: base,
              onPrimary: Colors.white,
              primaryContainer: light,
              onPrimaryContainer: dark,
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

                // ⬇️ 화면 식별 태그 (Lite 팔레트의 dark로 톤 맞춤)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Semantics(
                      label: 'screen_tag: lite login',
                      child: Text(
                        'lite login',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: dark.withOpacity(0.75),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ),

                // 로고
                GestureDetector(
                  onTap: () {},
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

                // ▶ 버튼 라벨 (경량 로그인)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.login),
                    label: Text(
                      _controller.isLoading ? '로딩 중...' : '경량 로그인',
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

                // ▼ 펠리컨: 탭하면 Selector로 복귀
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
