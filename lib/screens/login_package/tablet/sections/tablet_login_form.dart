import 'package:flutter/material.dart';
import '../../../../routes.dart'; // ✅ AppRoutes 사용 (경로는 현재 파일 위치 기준)
import '../belivus/tablet_cooperation_calendar.dart';
import '../tablet_login_controller.dart';

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
                      builder: (_) => const TabletCooperationCalendar(
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

              // ▼ 서비스 로그인으로 전환 (현재 화면을 완전히 대체)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // ✅ named route 사용: LoginScreen(mode: 'service')로 진입
                    Navigator.pushReplacementNamed(context, AppRoutes.login);
                  },
                  icon: const Icon(Icons.manage_accounts, size: 22),
                  label: const Text('서비스 로그인으로 전환'),
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
                controller: _controller.phoneController,       // 핸들 입력용 컨트롤러 유지
                focusNode: _controller.phoneFocus,
                keyboardType: TextInputType.text,               // ← 텍스트(핸들)
                textCapitalization: TextCapitalization.none,    // ← 자동 대문자 방지
                autocorrect: false,                             // ← 자동 교정 끔
                enableSuggestions: false,                       // ← 추천 끔
                textInputAction: TextInputAction.next,
                onChanged: (value) =>
                    _controller.formatPhoneNumber(value, setState),
                onSubmitted: (_) => FocusScope.of(context)
                    .requestFocus(_controller.passwordFocus),
                decoration: _controller.inputDecoration(
                  label: "영어 아이디(핸들)",                    // ← 라벨 명확화
                  icon: Icons.alternate_email,                  // ← 핸들 느낌 아이콘
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
