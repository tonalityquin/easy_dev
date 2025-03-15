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
    final userState = Provider.of<UserState>(context, listen: false);
    await userState.loadUser();
    if (userState.isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      debugPrint('자동 로그인 실패: 유효한 사용자 데이터가 없습니다.');
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
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final password = _passwordController.text.trim();
    final phoneError = _validatePhone(phone);
    final passwordError = _validatePassword(password);

    if (name.isEmpty) {
      showSnackbar(context, '이름을 입력해주세요.');
      return;
    }
    if (phoneError != null) {
      showSnackbar(context, phoneError);
      return;
    }
    if (passwordError != null) {
      showSnackbar(context, passwordError);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    if (!await _isInternetConnected()) {
      showSnackbar(context, '인터넷 연결이 필요합니다.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final userRepository = context.read<UserRepository>();
      final user = await userRepository.getUserByPhone(phone);

      if (user != null && user.name == name && user.password == password) {
        final userState = Provider.of<UserState>(context, listen: false);
        final areaState = Provider.of<AreaState>(context, listen: false);

        // ✅ `UserModel`을 사용하여 updateUser()에 전달
        userState.updateUser(user);
        areaState.updateArea(user.area);

        Navigator.pushReplacementNamed(context, '/home');
      } else {
        showSnackbar(context, user == null ? '해당 전화번호가 등록되지 않았습니다.' : '이름 또는 비밀번호가 올바르지 않습니다.');
      }
    } catch (e) {
      showSnackbar(context, '로그인 실패: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
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
