import 'package:flutter/material.dart';
import '../belivus/cooperation_calendar.dart';
import '../login_controller.dart';

class LoginForm extends StatefulWidget {
  final LoginController controller;

  const LoginForm({super.key, required this.controller});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  late final LoginController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller.initState(); // 로그인 상태 확인 및 자동 이동 처리
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
    return Column(
      children: [
        const SizedBox(height: 96),

        // 상단 로고
        GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CooperationCalendar(
                  calendarId: 'belivus150119@gmail.com', // ✅ 로고 클릭용 캘린더
                ),
              ),
            );
          },
          child: SizedBox(
            height: 240,
            child: Image.asset('assets/images/easyvalet_logo_car.png'),
          ),
        ),

        const SizedBox(height: 48),

        // 이름 입력 필드
        TextField(
          controller: _controller.nameController,
          focusNode: _controller.nameFocus,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).requestFocus(_controller.phoneFocus),
          decoration: _controller.inputDecoration(label: "이름", icon: Icons.person),
        ),
        const SizedBox(height: 16),

        // 전화번호 입력 필드
        TextField(
          controller: _controller.phoneController,
          focusNode: _controller.phoneFocus,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          onChanged: (value) => _controller.formatPhoneNumber(value, setState),
          onSubmitted: (_) => FocusScope.of(context).requestFocus(_controller.passwordFocus),
          decoration: _controller.inputDecoration(label: "전화번호", icon: Icons.phone),
        ),
        const SizedBox(height: 16),

        // 비밀번호 입력 필드
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
                _controller.obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () => setState(() => _controller.togglePassword()),
            ),
          ),
        ),
        const SizedBox(height: 32),

        // 로그인 버튼
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.login),
            label: Text(
              _controller.isLoading ? '로딩 중...' : '로그인',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(55),
              padding: EdgeInsets.zero,
              side: const BorderSide(color: Colors.grey, width: 1.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _controller.isLoading ? null : _onLoginButtonPressed,
          ),
        ),

        const SizedBox(height: 1),

        // ✅ pelican 이미지 삽입 (중앙 정렬)
        Center(
          child: SizedBox(
            height: 80,
            child: Image.asset('assets/images/pelican.png'),
          ),
        ),
      ],
    );
  }
}
