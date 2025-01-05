import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false; // 로딩 상태 추가
  bool _passwordVisible = false; // 비밀번호 가시성 상태 추가

  // 이메일 검증 함수
  String? _validateEmail(String email) {
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (email.isEmpty) return '이메일을 입력해주세요.';
    if (!emailRegex.hasMatch(email)) return '유효한 이메일 형식이 아닙니다.';
    return null;
  }

  // 비밀번호 검증 함수
  String? _validatePassword(String password) {
    if (password.isEmpty) return '비밀번호를 입력해주세요.';
    if (password.length < 6) return '비밀번호는 6자리 이상이어야 합니다.';
    return null;
  }

  void _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // 입력값 검증
    final emailError = _validateEmail(email);
    final passwordError = _validatePassword(password);

    if (emailError != null || passwordError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(emailError ?? passwordError!)),
      );
      return;
    }

    setState(() {
      _isLoading = true; // 로딩 상태 활성화
    });

    try {
      // Firebase 인증
      await _auth.signInWithEmailAndPassword(email: email, password: password);

      // 로그인 성공 시 홈으로 이동
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on FirebaseAuthException catch (e) {
      // Firebase 인증 에러 처리
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = '등록되지 않은 사용자입니다.';
          break;
        case 'wrong-password':
          errorMessage = '잘못된 비밀번호입니다.';
          break;
        default:
          errorMessage = '로그인 실패: ${e.message}';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } finally {
      setState(() {
        _isLoading = false; // 로딩 상태 비활성화
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("로그인 페이지"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 이메일 입력 필드
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: "이메일",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 비밀번호 입력 필드
            TextField(
              controller: _passwordController,
              obscureText: !_passwordVisible,
              decoration: InputDecoration(
                labelText: "비밀번호",
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _passwordVisible ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _passwordVisible = !_passwordVisible; // 비밀번호 가시성 토글
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 로그인 버튼 또는 로딩 표시
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _login,
                    child: const Text("로그인"),
                  ),
          ],
        ),
      ),
    );
  }
}
