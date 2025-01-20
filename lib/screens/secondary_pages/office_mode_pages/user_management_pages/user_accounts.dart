import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 사용자 계정을 입력받아 저장하는 화면
class UserAccounts extends StatefulWidget {
  /// 저장 콜백 함수
  final Function(String name, String phone, String email, String role, String access) onSave;

  /// TopNavigation에서 전달받은 지역 값
  final String areaValue;

  /// 역할 목록 (기본값 제공)
  final List<String> roleOptions;

  const UserAccounts({
    Key? key,
    required this.onSave,
    required this.areaValue,
    this.roleOptions = const ['Dev', 'Officer', 'Field Leader', 'Fielder'],
  }) : super(key: key);

  @override
  State<UserAccounts> createState() => _UserAccountsState();
}

class _UserAccountsState extends State<UserAccounts> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();

  String _selectedRole = 'Fielder'; // 초기 역할 값
  String? _errorMessage; // 에러 메시지 상태

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  /// 입력값 유효성 검증
  bool _validateInputs() {
    if (_nameController.text.isEmpty) {
      _setErrorMessage('name');
      return false;
    }
    if (!RegExp(r'^\d{9,}$').hasMatch(_phoneController.text)) {
      _setErrorMessage('number');
      return false;
    }
    if (_emailController.text.isEmpty) {
      _setErrorMessage('Email');
      return false;
    }
    _setErrorMessage(null); // 에러 메시지 초기화
    return true;
  }

  /// 에러 메시지 설정
  void _setErrorMessage(String? message) {
    setState(() {
      _errorMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Accounts'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 이름 입력 필드
            TextField(
              controller: _nameController,
              focusNode: _nameFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).requestFocus(_phoneFocus),
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // 전화번호 입력 필드
            TextField(
              controller: _phoneController,
              focusNode: _phoneFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).requestFocus(_emailFocus),
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // 이메일 입력 필드 및 접미사
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                      labelText: 'Email Prefix',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Container(
                    alignment: Alignment.center,
                    height: 56,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('@gmail.com'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 역할 선택 드롭다운
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(),
              ),
              items: widget.roleOptions
                  .map((role) => DropdownMenuItem(
                        value: role,
                        child: Text(role),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedRole = value!;
                });
              },
            ),
            const SizedBox(height: 16),
            // 지역 표시
            Text(
              'Area: ${widget.areaValue}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            // 에러 메시지 표시
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            const Spacer(),
            // 버튼 (취소 및 저장)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_validateInputs()) {
                      final fullEmail = '${_emailController.text}@gmail.com';
                      widget.onSave(
                        _nameController.text,
                        _phoneController.text,
                        fullEmail,
                        _selectedRole,
                        widget.areaValue,
                      );
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
