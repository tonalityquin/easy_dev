import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../models/user_model.dart';
import 'sections/password_display.dart';
import 'sections/role_type.dart';
import 'sections/user_input_section.dart';
import 'sections/role_dropdown_section.dart';
import 'sections/validation_helpers.dart';

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
      String? startTime,
      String? endTime,
      List<String> fixedHolidays,
      String position, // ✅ 추가된 항목
      ) onSave;

  final String areaValue;
  final String division;
  final UserModel? initialUser;
  final bool isEditMode;

  const UserSetting({
    super.key,
    required this.onSave,
    required this.areaValue,
    required this.division,
    this.isEditMode = false,
    this.initialUser,
  });

  @override
  State<UserSetting> createState() => _UserSettingState();
}

class _UserSettingState extends State<UserSetting> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _positionController = TextEditingController(); // ✅ 직책 컨트롤러

  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();

  RoleType _selectedRole = RoleType.lowField;
  String? _errorMessage;

  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  final List<String> _days = ['월', '화', '수', '목', '금', '토', '일'];
  final Set<String> _selectedHolidays = {};

  @override
  void initState() {
    super.initState();
    final user = widget.initialUser;

    if (user != null) {
      _nameController.text = user.name;
      _phoneController.text = user.phone;
      _emailController.text = user.email.split('@').first;
      _passwordController.text = user.password;
      _positionController.text = user.position ?? ''; // ✅ 직책 초기화
      _selectedRole = RoleType.values.firstWhere(
            (r) => r.name == user.role,
        orElse: () => RoleType.lowField,
      );
      _startTime = user.startTime;
      _endTime = user.endTime;
      _selectedHolidays.addAll(user.fixedHolidays);
    } else {
      _passwordController.text = _generateRandomPassword();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _positionController.dispose(); // ✅ 컨트롤러 해제
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  bool _validateInputs() {
    final error = validateInputs({
      '이름': _nameController.text,
      '전화번호': _phoneController.text,
      '이메일': _emailController.text,
    });
    _setErrorMessage(error);
    return error == null;
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

  Future<void> _selectTime({required bool isStartTime}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  String _formatTimeOfDay(TimeOfDay? time) {
    if (time == null) return '--:--';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String? _timeToString(TimeOfDay? time) {
    return time != null ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}' : null;
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.initialUser != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          isEditMode ? '계정 수정' : '계정 생성',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          UserInputSection(
            nameController: _nameController,
            phoneController: _phoneController,
            emailController: _emailController,
            nameFocus: _nameFocus,
            phoneFocus: _phoneFocus,
            emailFocus: _emailFocus,
            errorMessage: _errorMessage,
          ),
          const SizedBox(height: 16),
          RoleDropdownSection(
            selectedRole: _selectedRole,
            onChanged: (value) {
              setState(() {
                _selectedRole = value;
              });
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _positionController,
            decoration: InputDecoration(
              labelText: '직책',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),
          PasswordDisplaySection(controller: _passwordController),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _selectTime(isStartTime: true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '출근 시간: ${_formatTimeOfDay(_startTime)}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => _selectTime(isStartTime: false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '퇴근 시간: ${_formatTimeOfDay(_endTime)}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '고정 휴일 선택 (선택사항)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Wrap(
            spacing: 8,
            children: _days.map((day) {
              final isSelected = _selectedHolidays.contains(day);
              return FilterChip(
                label: Text(day),
                selected: isSelected,
                selectedColor: Colors.green.shade100,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedHolidays.add(day);
                    } else {
                      _selectedHolidays.remove(day);
                    }
                  });
                },
              );
            }).toList(),
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
                        _timeToString(_startTime),
                        _timeToString(_endTime),
                        _selectedHolidays.toList(),
                        _positionController.text, // ✅ 직책 전달
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
                  child: Text(isEditMode ? '수정' : '생성'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
