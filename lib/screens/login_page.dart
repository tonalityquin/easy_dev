import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../states/user_state.dart'; // UserState 가져오기
import '../states/area_state.dart'; // AreaState 가져오기
import 'dart:io'; // 인터넷 연결 확인을 위한 패키지

/// 사용자가 이름과 전화번호를 통해 Firestore에서 인증할 수 있는 화면
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nameController = TextEditingController(); // 이름 입력 필드 컨트롤러
  final TextEditingController _phoneController = TextEditingController(); // 전화번호 입력 필드 컨트롤러
  bool _isLoading = false; // 로딩 상태 관리

  @override
  void initState() {
    super.initState();
    _checkLoginState(); // 앱 실행 시 로그인 상태 확인
  }

  /// 로그인 상태 확인 및 자동 로그인
  Future<void> _checkLoginState() async {
    final userState = Provider.of<UserState>(context, listen: false);
    await userState.loadUser(); // 사용자 정보 불러오기

    if (userState.isLoggedIn) {
      // 이미 로그인된 경우 홈 화면으로 이동
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      // 로그인 실패 시 로그인 화면 유지
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

  /// Firestore에서 이름과 전화번호로 사용자 인증
  Future<void> _login() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim().replaceAll(RegExp(r'\D'), ''); // 숫자만 남김

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

    // 인터넷 연결 확인
    if (!await _isInternetConnected()) {
      _showSnackBar('인터넷 연결이 필요합니다.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      // Firestore에서 전화번호로 사용자 데이터 조회
      final querySnapshot =
          await FirebaseFirestore.instance.collection('user_accounts').where('phone', isEqualTo: phone).get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final data = doc.data();
        final role = data['role'];
        final area = data['area'];

        if (role == null || area == null) {
          throw Exception('사용자 데이터가 완전하지 않습니다.');
        }

        if (data['name'] == name) {
          final userState = Provider.of<UserState>(context, listen: false);
          final areaState = Provider.of<AreaState>(context, listen: false);

          // 사용자 상태 업데이트
          userState.updateUser(name: name, phone: phone, role: role, area: area);
          areaState.updateArea(area);

          Navigator.pushReplacementNamed(context, '/home'); // 홈 화면으로 이동
        } else {
          _showSnackBar('이름이 올바르지 않습니다.');
        }
      } else {
        _showSnackBar('해당 전화번호가 등록되지 않았습니다.');
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
