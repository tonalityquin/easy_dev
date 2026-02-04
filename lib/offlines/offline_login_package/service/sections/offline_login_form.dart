import 'package:flutter/material.dart';
import '../../../../routes.dart'; // ✅ AppRoutes 사용 (경로는 현재 파일 위치 기준)
import '../offline_login_controller.dart';

// ✅ AppCardPalette 정의 파일을 프로젝트 경로에 맞게 import 하세요.
// 예) import 'package:your_app/theme/app_card_palette.dart';
import '../../../../theme.dart';

/// ❌ HubCardsPalette / _OfflineCardPalette 제거
/// ✅ AppCardPalette(parkingBase/parkingLight)를 오프라인 로그인 팔레트로 사용

class OfflineLoginForm extends StatefulWidget {
  final OfflineLoginController controller;

  const OfflineLoginForm({super.key, required this.controller});

  @override
  State<OfflineLoginForm> createState() => _OfflineLoginFormState();
}

class _OfflineLoginFormState extends State<OfflineLoginForm> {
  late final OfflineLoginController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
  }

  void _handleLogin() {
    _controller.login(context, setState);
  }

  void _onLoginButtonPressed() {
    if (!_controller.isLoading) {
      _handleLogin();
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);

    final palette = AppCardPalette.of(context);

    // ✅ 오프라인(= Parking/Offline Service) 팔레트 매핑
    final base = palette.parkingBase;
    final tint = palette.parkingLight;

    final themed = baseTheme.copyWith(
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: base,
        onPrimary: Colors.white,
        primaryContainer: tint,
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
        selectionColor: tint.withOpacity(.35),
        selectionHandleColor: base,
      ),
    );

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Theme(
          data: themed,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {},
                  child: SizedBox(
                    height: 360,
                    child: Image.asset('assets/images/pelican.png'),
                  ),
                ),
                const SizedBox(height: 12),

                // 이름
                TextField(
                  controller: _controller.nameController,
                  focusNode: _controller.nameFocus,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_controller.phoneFocus),
                  decoration: _controller
                      .inputDecoration(
                    label: "이름",
                    icon: Icons.person,
                  )
                      .copyWith(
                    hintText: 'tester',
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
                  onSubmitted: (_) => FocusScope.of(context)
                      .requestFocus(_controller.passwordFocus),
                  decoration: _controller
                      .inputDecoration(
                    label: "전화번호",
                    icon: Icons.phone,
                  )
                      .copyWith(
                    hintText: '01012345678',
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
                  decoration: _controller
                      .inputDecoration(
                    label: "비밀번호(5자리 이상)",
                    icon: Icons.lock,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _controller.obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _controller.togglePassword()),
                      tooltip: _controller.obscurePassword ? '표시' : '숨기기',
                    ),
                  )
                      .copyWith(
                    hintText: '12345',
                  ),
                ),

                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.login),
                    label: Text(
                      _controller.isLoading ? '로딩 중...' : '오프라인 로그인',
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
