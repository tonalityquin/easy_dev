import 'package:flutter/material.dart';
import '../dev/personal_calendar.dart';
import '../login_controller.dart';
import '../debugs/login_debug_bottom_sheet.dart';

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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 96),

        // 로고 클릭 시 개인 캘린더 화면으로 이동
        GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PersonalCalendar()),
            );
          },
          child: SizedBox(
            height: 240,
            child: Image.asset('assets/images/pelican_logo.png'),
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
          onSubmitted: (_) => _handleLogin(),
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

        // ✅ 로그인 버튼 (디자인 완전 통일)
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
            onPressed: _controller.isLoading ? null : _handleLogin,
          ),
        ),

        const SizedBox(height: 12),

        // 디버깅 버튼
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.bug_report, size: 18),
            label: const Text("디버깅"),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => const LoginDebugBottomSheet(),
              );
            },
          ),
        ),
      ],
    );
  }
}
