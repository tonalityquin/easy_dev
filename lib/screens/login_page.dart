import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../states/user_state.dart';
import '../states/area_state.dart';
import '../repositories/user_repository.dart'; // UserRepository 가져오기
import 'dart:io';

/// 사용자가 이름과 전화번호를 통해 인증할 수 있는 화면
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkLoginState();
  }

  /// 로그인 상태 확인 및 자동 로그인
  Future<void> _checkLoginState() async {
    final userState = Provider.of<UserState>(context, listen: false);
    await userState.loadUser();

    if (userState.isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      debugPrint('자동 로그인 실패: 유효한 사용자 데이터가 없습니다.');
    }
  }

  /// SnackBar 메시지 출력 함수
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 전화번호 유효성 검사
  String? _validatePhone(String phone) {
    final trimmedPhone = phone.trim();
    final phoneRegex = RegExp(r'^[0-9]{10,11}$');
    if (trimmedPhone.isEmpty) return '전화번호를 입력해주세요.';
    if (!phoneRegex.hasMatch(trimmedPhone)) return '유효한 전화번호를 입력해주세요.';
    return null;
  }

  /// 인터넷 연결 확인
  Future<bool> _isInternetConnected() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Repository를 통해 사용자 인증
  Future<void> _login() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');

    final phoneError = _validatePhone(phone);
    if (name.isEmpty) {
      _showSnackBar('이름을 입력해주세요.');
      return;
    }
    if (phoneError != null) {
      _showSnackBar(phoneError);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    if (!await _isInternetConnected()) {
      _showSnackBar('인터넷 연결이 필요합니다.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final userRepository = context.read<UserRepository>();

      // UserRepository를 통해 사용자 인증
      final user = await userRepository.getUserByPhone(phone);
      if (user != null && user['name'] == name) {
        final userState = Provider.of<UserState>(context, listen: false);
        final areaState = Provider.of<AreaState>(context, listen: false);

        // 사용자 상태 업데이트
        userState.updateUser(
          name: user['name'],
          phone: phone,
          role: user['role'],
          area: user['area'],
        );
        areaState.updateArea(user['area']);

        Navigator.pushReplacementNamed(context, '/home');
      } else {
        _showSnackBar(user == null ? '해당 전화번호가 등록되지 않았습니다.' : '이름이 올바르지 않습니다.');
      }
    } catch (e) {
      _showSnackBar('로그인 실패: $e');
    } finally {
      setState(() {
        _isLoading = false;
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
