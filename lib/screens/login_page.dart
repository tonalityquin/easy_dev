import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../states/user_state.dart'; // 사용자 상태 관리
import '../states/area_state.dart'; // 지역 상태 관리
import '../repositories/user_repository.dart'; // UserRepository 가져오기
import 'dart:io';

/// 로그인 페이지
/// - 사용자 이름과 전화번호로 인증
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nameController = TextEditingController(); // 이름 입력 컨트롤러
  final TextEditingController _phoneController = TextEditingController(); // 전화번호 입력 컨트롤러
  bool _isLoading = false; // 로딩 상태

  @override
  void initState() {
    super.initState();
    _checkLoginState(); // 자동 로그인 확인
  }

  /// 자동 로그인 상태 확인
  Future<void> _checkLoginState() async {
    final userState = Provider.of<UserState>(context, listen: false);
    await userState.loadUser();

    if (userState.isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      debugPrint('자동 로그인 실패: 유효한 사용자 데이터가 없습니다.');
    }
  }

  /// SnackBar로 메시지 출력
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

  /// 사용자 인증 및 로그인 처리
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

      // 사용자 인증
      final user = await userRepository.getUserByPhone(phone);
      if (user != null && user['name'] == name) {
        final userState = Provider.of<UserState>(context, listen: false);
        final areaState = Provider.of<AreaState>(context, listen: false);

        // 사용자 및 지역 상태 업데이트
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
            // 이름 입력 필드
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "이름",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // 전화번호 입력 필드
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: "전화번호",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            // 로그인 버튼 또는 로딩 인디케이터
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
