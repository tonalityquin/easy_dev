import 'package:flutter/material.dart';
import '../belivus/service_cooperation_calendar.dart';
import '../outside_login_controller.dart';

class OutsideLoginForm extends StatefulWidget {
  final OutsideLoginController controller;

  const OutsideLoginForm({super.key, required this.controller});

  @override
  State<OutsideLoginForm> createState() => _OutsideLoginFormState();
}

class _OutsideLoginFormState extends State<OutsideLoginForm> {
  late final OutsideLoginController _controller;

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
              const SizedBox(height: 12),

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

              // ▼ 펠리컨: 탭하면 LoginSelectorPage로 복귀
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
    );
  }
}
