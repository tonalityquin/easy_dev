import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum RoleType {
  dev,
  officer,
  fieldLeader,
  fielder;

  String get label {
    switch (this) {
      case RoleType.dev:
        return '개발자';
      case RoleType.officer:
        return '내근직';
      case RoleType.fieldLeader:
        return '필드 팀장';
      case RoleType.fielder:
        return '외근직';
    }
  }

  static RoleType fromName(String name) {
    return RoleType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => RoleType.fielder,
    );
  }

  static RoleType fromLabel(String label) {
    return RoleType.values.firstWhere(
      (e) => e.label == label,
      orElse: () => RoleType.fielder,
    );
  }
}

class UserSetting extends StatefulWidget {
  final Function(
    String name,
    String phone,
    String email,
    String role,
    String password,
    String area,
    String division,
    bool isWorking,
    bool isSaved,
    String selectedArea,
  ) onSave;

  final String areaValue;
  final String division;

  const UserSetting({
    super.key,
    required this.onSave,
    required this.areaValue,
    required this.division,
  });

  @override
  State<UserSetting> createState() => _UserAccountsState();
}

class _UserAccountsState extends State<UserSetting> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();

  RoleType _selectedRole = RoleType.fielder;
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

  final Map<String, String Function(String)> _validationRules = {
    '이름': (value) => value.isEmpty ? '이름을 다시 입력하세요' : '',
    '전화번호': (value) => RegExp(r'^\d{9,}$').hasMatch(value) ? '' : '전화번호를 다시 입력하세요',
    '이메일': (value) => value.isEmpty ? '이메일을 입력하세요' : '',
  };

  bool _validateInputs() {
    for (var entry in _validationRules.entries) {
      final field = entry.key;
      final validator = entry.value;
      String inputValue = switch (field) {
        '이름' => _nameController.text,
        '전화번호' => _phoneController.text,
        '이메일' => _emailController.text,
        _ => '',
      };
      final errorMessage = validator(inputValue);
      if (errorMessage.isNotEmpty) {
        _setErrorMessage(errorMessage);
        return false;
      }
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '계정 생성',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            focusNode: _nameFocus,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).requestFocus(_phoneFocus),
            decoration: InputDecoration(
              labelText: '이름',
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.green),
                borderRadius: BorderRadius.circular(8),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
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
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.green),
                borderRadius: BorderRadius.circular(8),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
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
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.green),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    errorText: _errorMessage == '이메일을 입력하세요' ? _errorMessage : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                flex: 2,
                child: SizedBox(
                  height: 56,
                  child: Center(
                    child: Text(
                      '@gmail.com',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<RoleType>(
            value: _selectedRole,
            decoration: InputDecoration(
              labelText: '직책',
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.green),
                borderRadius: BorderRadius.circular(8),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            dropdownColor: Colors.white,
            iconEnabledColor: Colors.green,
            items: RoleType.values
                .map((role) => DropdownMenuItem<RoleType>(
                      value: role,
                      child: Text(
                        role.label,
                        style: TextStyle(
                          color: role == _selectedRole ? Colors.green : Colors.purple,
                        ),
                      ),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedRole = value;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: '비밀번호',
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.green),
                borderRadius: BorderRadius.circular(8),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '현재 지역: ${widget.areaValue}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.withOpacity(0.2),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('취소'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    if (_validateInputs()) {
                      final fullEmail = '${_emailController.text}@gmail.com';
                      widget.onSave(
                        _nameController.text,
                        _phoneController.text,
                        fullEmail,
                        _selectedRole.name,
                        _passwordController.text,
                        widget.areaValue,
                        widget.division,
                        false,
                        false,
                        widget.areaValue,
                      );
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('생성'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
