import 'package:flutter/material.dart';
import '../../../../routes.dart'; // ✅ AppRoutes 사용 (경로는 현재 파일 위치 기준)
import '../belivus/service_cooperation_calendar.dart';
import '../service_login_controller.dart';

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
    return Material(
      // ✅ Material ancestor 보장
      color: Colors.transparent,
      child: SafeArea(
        child: SingleChildScrollView(
          // ✅ overflow 방지
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 96),

              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CooperationCalendar(
                        calendarId: 'belivus150119@gmail.com',
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

              // ▼ 태블릿 로그인으로 전환 (현재 화면을 완전히 대체)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // ✅ named route 사용: LoginScreen(mode: 'tablet')로 진입
                    Navigator.pushReplacementNamed(
                      context,
                      AppRoutes.loginTablet,
                    );
                  },
                  icon: const Icon(Icons.tablet, size: 22),
                  label: const Text('태블릿 로그인으로 전환'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(55),
                    padding: EdgeInsets.zero,
                    side: const BorderSide(color: Colors.grey, width: 1.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

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
                  onPressed:
                  _controller.isLoading ? null : _onLoginButtonPressed,
                ),
              ),

              const SizedBox(height: 1),

              Center(
                child: SizedBox(
                  height: 80,
                  child: Image.asset('assets/images/pelican.png'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
