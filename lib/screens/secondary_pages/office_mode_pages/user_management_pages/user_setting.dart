import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UserSetting extends StatefulWidget {
  final Function(String name, String phone, String email, String role, String password, String access, bool isWorking)
      onSave;
  final String areaValue;
  final List<String> roleOptions;

  const UserSetting({
    super.key,
    required this.onSave,
    required this.areaValue,
    this.roleOptions = const ['Dev', 'Officer', 'Field Leader', 'Fielder', '대표 이사', '본부장', '팀장', '팀원'],
  });

  @override
  State<UserSetting> createState() => _UserAccountsState();
}

class _UserAccountsState extends State<UserSetting> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  String _selectedRole = 'Fielder';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _passwordController.text = _generateRandomPassword();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  final Map<String, String Function(String)> validationRules = {
    '이름': (value) => value.isEmpty ? '이름을 다시 입력하세요' : '',
    '전화번호': (value) => RegExp(r'^\d{9,}$').hasMatch(value) ? '' : '전화번호를 다시 입력 하세요',
    '이메일(구글)': (value) => value.isEmpty ? '이메일을 다시 입력 하세요' : '',
  };

  bool _validateInputs() {
    String? errorMessage;
    if ((errorMessage = validationRules['이름']!(_nameController.text)).isNotEmpty) {
      _setErrorMessage(errorMessage);
      return false;
    }
    if ((errorMessage = validationRules['전화번호']!(_phoneController.text)).isNotEmpty) {
      _setErrorMessage(errorMessage);
      return false;
    }
    if ((errorMessage = validationRules['이메일(구글)']!(_emailController.text)).isNotEmpty) {
      _setErrorMessage(errorMessage);
      return false;
    }
    _setErrorMessage(null);
    return true;
  }

  void _setErrorMessage(String? message) {
    setState(() {
      _errorMessage = message;
    });
  }

  String _generateRandomPassword() {
    final random = Random();
    return (10000 + random.nextInt(90000)).toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('계정 생성')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          TextField(
            controller: _nameController,
            focusNode: _nameFocus,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).requestFocus(_phoneFocus),
            decoration: InputDecoration(
              labelText: '이름',
              border: const OutlineInputBorder(),
              errorText: _errorMessage == '이름을 다시 입력하세요' ? _errorMessage : null,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            focusNode: _phoneFocus,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).requestFocus(_emailFocus),
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: '전화번호',
              border: const OutlineInputBorder(),
              errorText: _errorMessage == '전화번호를 다시 입력하세요' ? _errorMessage : null,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: '이메일(구글)',
                    border: const OutlineInputBorder(),
                    errorText: _errorMessage == '이메일(구글)' ? _errorMessage : null,
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
          DropdownButtonFormField<String>(
            value: _selectedRole,
            decoration: const InputDecoration(
              labelText: '직책',
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
          TextField(
            controller: _passwordController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: '비밀번호',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '현재 지역: ${widget.areaValue}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                child: const Text('취소'),
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
                      _passwordController.text,
                      false,
                    );
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                child: const Text('생성'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
