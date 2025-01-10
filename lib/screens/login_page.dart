import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // Provider를 사용하기 위해 추가
import '../states/user_state.dart'; // UserState 가져오기

/// LoginPage 위젯
/// 사용자가 이름과 전화번호를 통해 Firestore에서 인증할 수 있는 화면
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // 이름과 전화번호 입력을 제어하는 텍스트 컨트롤러
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // 로딩 상태를 제어하는 플래그
  bool _isLoading = false;

  /// 전화번호 유효성을 검사하는 메서드
  String? _validatePhone(String phone) {
    final phoneRegex = RegExp(r'^[0-9]{10,11}$'); // 10~11자리 숫자만 허용
    if (phone.isEmpty) return '전화번호를 입력해주세요.';
    if (!phoneRegex.hasMatch(phone)) return '유효한 전화번호를 입력해주세요.';
    return null;
  }

  /// Firestore에서 이름과 전화번호로 사용자 인증
  Future<void> _login() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    // 전화번호 유효성 검사
    final phoneError = _validatePhone(phone);
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이름을 입력해주세요.')),
      );
      return;
    }
    if (phoneError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(phoneError)),
      );
      return;
    }

    setState(() {
      _isLoading = true; // 로딩 상태 활성화
    });

    try {
      // Firestore에서 전화번호로 사용자 문서 조회
      final docSnapshot = await FirebaseFirestore.instance
          .collection('accounts')
          .doc(phone)
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        if (data?['name'] == name) {
          // 로그인 성공 - UserState 업데이트
          final userState = Provider.of<UserState>(context, listen: false);
          userState.setUserName(name); // UserState에 이름 저장

          Navigator.pushReplacementNamed(context, '/home'); // 홈 화면으로 이동
        } else {
          // 이름 불일치
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이름이 올바르지 않습니다.')),
          );
        }
      } else {
        // 전화번호가 존재하지 않음
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('해당 전화번호가 등록되지 않았습니다.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그인 실패: $e')),
      );
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
