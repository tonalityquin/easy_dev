import 'package:flutter/material.dart';
import '../outside_login_controller.dart';

class OutsideLoginForm extends StatefulWidget {
  final OutsideLoginController controller;

  const OutsideLoginForm({super.key, required this.controller});

  @override
  State<OutsideLoginForm> createState() => _OutsideLoginFormState();
}

class _OutsideLoginFormState extends State<OutsideLoginForm> {
  late final OutsideLoginController _controller;

  // 출퇴근(Outside) 팔레트 — _ClockCard와 동일
  static const Color _navy = Color(0xFF122232);     // 카드/배경 느낌
  static const Color _amber700 = Color(0xFFFFB300); // 액센트(버튼/배지/강조 텍스트)
  static const Color _onAmber = Color(0xFF1A1A1A);  // 앰버 위 아이콘/텍스트

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller.initState();
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
    return Theme(
      // ✅ 입력 포커스/커서/아이콘에 앰버 포인트, 기본 톤은 네이비 계열로 조정
      data: Theme.of(context).copyWith(
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: _amber700,
          selectionColor: _amber700.withOpacity(.25),
          selectionHandleColor: _amber700,
        ),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _amber700, width: 1.6),
          ),
          labelStyle: TextStyle(color: _navy.withOpacity(.85)),
          floatingLabelStyle: const TextStyle(
            color: _amber700,
            fontWeight: FontWeight.w700,
          ),
          prefixIconColor: MaterialStateColor.resolveWith(
                (states) => states.contains(MaterialState.focused)
                ? _amber700
                : _navy.withOpacity(.75),
          ),
          suffixIconColor: MaterialStateColor.resolveWith(
                (states) => states.contains(MaterialState.focused)
                ? _amber700
                : _navy.withOpacity(.75),
          ),
        ),
      ),
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
                  focusNode: _controller.phoneFocus,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  onChanged: (value) =>
                      _controller.formatPhoneNumber(value, setState),
                  onSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_controller.passwordFocus),
                  decoration: _controller.inputDecoration(
                    label: "전화번호",
                    icon: Icons.phone,
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
                      _controller.isLoading ? '로딩 중...' : '출퇴근 로그인',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _amber700, // ▶ _ClockCard와 동일한 버튼 배경
                      foregroundColor: _onAmber,  // ▶ 버튼 전경(텍스트/아이콘)
                      minimumSize: const Size.fromHeight(55),
                      padding: EdgeInsets.zero,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _controller.isLoading ? null : _onLoginButtonPressed,
                  ),
                ),

                const SizedBox(height: 1),

                // ▼ 펠리컨: 탭하면 LoginSelectorPage로 복귀 (이미지는 흰 배경에 최적화)
                Center(
                  child: InkWell(
                    onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
                      '/selector', // AppRoutes.selector 사용 시 import 후 교체 가능
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
