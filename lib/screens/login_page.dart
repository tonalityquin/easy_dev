import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../states/user/user_state.dart';
import '../states/area/area_state.dart';
import '../repositories/user/user_repository.dart';
import '../utils/show_snackbar.dart';
import 'dart:io';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkLoginState();
  }

  Future<void> _checkLoginState() async {
    print("[DEBUG] _checkLoginState() 실행됨");

    final userState = Provider.of<UserState>(context, listen: false);
    await userState.loadUserToLogIn();

    print("[DEBUG] 로그인 상태 확인: isLoggedIn = ${userState.isLoggedIn}");

    if (userState.isLoggedIn) {
      print("[DEBUG] 로그인된 상태 - '/home'으로 이동");
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      print("[DEBUG] 로그인되지 않음 - 로그인 페이지 유지");
    }
  }

  String? _validatePhone(String phone) {
    final trimmedPhone = phone.trim();
    final phoneRegex = RegExp(r'^[0-9]{10,11}$');
    if (trimmedPhone.isEmpty) return '전화번호를 입력해주세요.';
    if (!phoneRegex.hasMatch(trimmedPhone)) return '유효한 전화번호를 입력해주세요.';
    return null;
  }

  String? _validatePassword(String password) {
    if (password.isEmpty) return '비밀번호를 입력해주세요.';
    if (password.length < 5) return '비밀번호는 최소 5자 이상이어야 합니다.';
    return null;
  }

  Future<bool> _isInternetConnected() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _login() async {
    print("[DEBUG] 로그인 시도");

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final password = _passwordController.text.trim();

    print("[DEBUG] 입력값 - name: $name, phone: $phone, password: (보안상 미출력)");

    final phoneError = _validatePhone(phone);
    final passwordError = _validatePassword(password);

    if (name.isEmpty) {
      print("[DEBUG] 로그인 실패 - 이름 미입력");
      showSnackbar(context, '이름을 입력해주세요.');
      return;
    }
    if (phoneError != null) {
      print("[DEBUG] 로그인 실패 - 전화번호 오류: $phoneError");
      showSnackbar(context, phoneError);
      return;
    }
    if (passwordError != null) {
      print("[DEBUG] 로그인 실패 - 비밀번호 오류: $passwordError");
      showSnackbar(context, passwordError);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    if (!await _isInternetConnected()) {
      print("[DEBUG] 로그인 실패 - 인터넷 연결 없음");
      showSnackbar(context, '인터넷 연결이 필요합니다.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      print("[DEBUG] Firestore에서 사용자 조회 시도 - phone: $phone");

      final userRepository = context.read<UserRepository>();
      final user = await userRepository.getUserByPhone(phone);

      if (user != null) {
        print("[DEBUG] 사용자 정보 찾음 - ID: ${user.id}, name: ${user.name}");

        if (user.name == name && user.password == password) {
          print("[DEBUG] 로그인 성공 - 사용자 인증 완료");

          final userState = Provider.of<UserState>(context, listen: false);
          final areaState = Provider.of<AreaState>(context, listen: false);

          // ✅ isSaved를 true로 변경한 객체 생성
          final updatedUser = user.copyWith(isSaved: true);

          userState.updateUserCard(updatedUser);  // ✅ isSaved 반영된 updatedUser 사용
          areaState.updateArea(updatedUser.area);

          print("[DEBUG] 상태 업데이트 완료 - 이동할 화면: /home");
          Navigator.pushReplacementNamed(context, '/home');
        }
        else {
          print("[DEBUG] 로그인 실패 - 이름 또는 비밀번호 불일치");
          showSnackbar(context, '이름 또는 비밀번호가 올바르지 않습니다.');
        }
      } else {
        print("[DEBUG] 로그인 실패 - 해당 전화번호 등록되지 않음");
        showSnackbar(context, '해당 전화번호가 등록되지 않았습니다.');
      }
    } catch (e) {
      print("[DEBUG] 로그인 중 예외 발생: $e");
      showSnackbar(context, '로그인 실패: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
      print("[DEBUG] 로그인 프로세스 종료 - _isLoading = false");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 120,
              child: Image.asset('assets/images/belivus_logo.PNG'),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "이름",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: "전화번호",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "비밀번호(5자리)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
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
