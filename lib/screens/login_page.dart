import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// LoginPage 위젯
/// 사용자가 이메일과 비밀번호를 통해 Firebase 인증으로 로그인할 수 있는 화면
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // 이메일과 비밀번호 입력을 제어하는 텍스트 컨트롤러
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Firebase Authentication 인스턴스 초기화
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 로딩 상태 및 비밀번호 표시 여부를 제어하는 플래그
  bool _isLoading = false;
  bool _passwordVisible = false;

  /// 이메일 유효성을 검사하는 메서드
  /// @param email - 사용자가 입력한 이메일
  /// @return null - 유효한 이메일, 에러 메시지 - 유효하지 않은 이메일
  String? _validateEmail(String email) {
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (email.isEmpty) return '이메일을 입력해주세요.';
    if (!emailRegex.hasMatch(email)) return '유효한 이메일 형식이 아닙니다.';
    return null;
  }

  /// 비밀번호 유효성을 검사하는 메서드
  /// @param password - 사용자가 입력한 비밀번호
  /// @return null - 유효한 비밀번호, 에러 메시지 - 유효하지 않은 비밀번호
  String? _validatePassword(String password) {
    if (password.isEmpty) return '비밀번호를 입력해주세요.';
    if (password.length < 6) return '비밀번호는 6자리 이상이어야 합니다.';
    return null;
  }

  /// Firebase Authentication을 이용한 로그인 메서드
  /// 유효성 검사 후 이메일 및 비밀번호로 인증을 시도
  void _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // 이메일 및 비밀번호 유효성 검사
    final emailError = _validateEmail(email);
    final passwordError = _validatePassword(password);

    if (emailError != null || passwordError != null) {
      // 유효하지 않을 경우 에러 메시지를 표시
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(emailError ?? passwordError!)),
      );
      return;
    }

    setState(() {
      _isLoading = true; // 로딩 상태 활성화
    });

    try {
      // Firebase 로그인 시도
      await _auth.signInWithEmailAndPassword(email: email, password: password);

      // 로그인 성공 시 홈 화면으로 이동
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on FirebaseAuthException catch (e) {
      // Firebase 로그인 실패 시 에러 처리
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

      // 에러 메시지를 화면에 표시
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
              obscureText: !_passwordVisible, // 비밀번호 표시 여부
              decoration: InputDecoration(
                labelText: "비밀번호",
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _passwordVisible ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    // 비밀번호 표시 상태를 토글
                    setState(() {
                      _passwordVisible = !_passwordVisible;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 로그인 버튼 또는 로딩 스피너
            _isLoading
                ? const CircularProgressIndicator() // 로딩 상태 표시
                : ElevatedButton(
              onPressed: _login, // 로그인 메서드 호출
              child: const Text("로그인"),
            ),
          ],
        ),
      ),
    );
  }
}
