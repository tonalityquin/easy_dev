import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../models/user_model.dart';
import 'sections/user_password_display_section.dart';
import 'sections/user_role_type_section.dart';
import 'sections/user_input_section.dart';
import 'sections/user_role_dropdown_section.dart';
import 'sections/user_validation_helpers_section.dart';

class UserSettingBottomSheet extends StatefulWidget {
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
    String position,
  ) onSave;

  final String areaValue;
  final String division;
  final UserModel? initialUser;
  final bool isEditMode;

  const UserSettingBottomSheet({
    super.key,
    required this.onSave,
    required this.areaValue,
    required this.division,
    this.initialUser,
    this.isEditMode = false,
  });

  @override
  State<UserSettingBottomSheet> createState() => _UserSettingBottomSheetState();
}

class _UserSettingBottomSheetState extends State<UserSettingBottomSheet> {
  // --- Controllers & Focus ---
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController(); // 로컬파트만 입력
  final _passwordController = TextEditingController();
  final _positionController = TextEditingController();

  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();

  // --- States ---
  RoleType _selectedRole = RoleType.lowField;
  String? _errorMessage;

  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  static const List<String> _days = ['월', '화', '수', '목', '금', '토', '일'];
  final Set<String> _selectedHolidays = {};

  @override
  void initState() {
    super.initState();
    final user = widget.initialUser;

    if (user != null) {
      _nameController.text = user.name;
      _phoneController.text = user.phone;
      _emailController.text = user.email.split('@').first; // 로컬파트
      _passwordController.text = user.password;
      _positionController.text = user.position ?? '';
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
    _positionController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  // --- Helpers ---

  bool _validateInputs() {
    final error = validateInputs({
      '이름': _nameController.text,
      '전화번호': _phoneController.text,
      '이메일': _emailController.text, // 로컬파트
    });
    _setErrorMessage(error);
    return error == null;
  }

  void _setErrorMessage(String? message) {
    setState(() => _errorMessage = message);
  }

  // 로컬파트 검증: 영문/숫자/._- 만 허용(필요 시 정책에 맞게 보강)
  bool _isValidEmailLocalPart(String input) {
    final reg = RegExp(r'^[a-zA-Z0-9._-]+$');
    return input.isNotEmpty && reg.hasMatch(input);
  }

  String _generateRandomPassword() {
    final random = Random();
    return (10000 + random.nextInt(90000)).toString(); // 기존 정책 유지(5자리 숫자)
  }

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  bool _validateTimes() {
    if (_startTime != null && _endTime != null) {
      if (_toMinutes(_startTime!) > _toMinutes(_endTime!)) {
        _setErrorMessage('출근/퇴근 시간을 다시 확인하세요');
        return false;
      }
    }
    return true;
  }

  Future<void> _selectTime({required bool isStartTime}) async {
    final theme = Theme.of(context);
    final initial = isStartTime
        ? (_startTime ?? const TimeOfDay(hour: 9, minute: 0))
        : (_endTime ?? const TimeOfDay(hour: 18, minute: 0));

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) {
        // 24시간제 강제(원치 않으면 제거)
        final mq = MediaQuery.of(ctx);
        return MediaQuery(
          data: mq.copyWith(alwaysUse24HourFormat: true),
          child: Theme(data: theme, child: child!),
        );
      },
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

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isEditMode = widget.isEditMode || (widget.initialUser != null);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              // ✅ 배경 하얀색으로 고정
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: theme.dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                const Text(
                  '👤 사용자 정보',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // 입력 섹션(이름/전화/이메일 로컬파트)
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

                // 권한 드롭다운
                UserRoleDropdownSection(
                  selectedRole: _selectedRole,
                  onChanged: (value) => setState(() => _selectedRole = value),
                ),
                const SizedBox(height: 16),

                // 직책
                TextField(
                  controller: _positionController,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    labelText: '직책',
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: cs.primary),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                ),
                const SizedBox(height: 16),

                // 비밀번호 표시
                UserPasswordDisplaySection(controller: _passwordController),
                const SizedBox(height: 16),

                // 출근/퇴근 시간 선택
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _selectTime(isStartTime: true),
                        icon: const Icon(Icons.schedule),
                        label: Text('출근: ${_formatTimeOfDay(_startTime)}'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _selectTime(isStartTime: false),
                        icon: const Icon(Icons.schedule),
                        label: Text('퇴근: ${_formatTimeOfDay(_endTime)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 고정 휴일
                Align(
                  alignment: Alignment.centerLeft,
                  child:
                      Text('고정 휴일 선택 (선택사항)', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _days.map((day) {
                    final isSelected = _selectedHolidays.contains(day);
                    return FilterChip(
                      label: Text(day),
                      selected: isSelected,
                      selectedColor: cs.primaryContainer,
                      checkmarkColor: cs.onPrimaryContainer,
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

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('현재 지역: ${widget.areaValue}',
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                ),

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                const SizedBox(height: 24),

                // 하단 버튼
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          FocusScope.of(context).unfocus();

                          // 1) 필드 검증
                          if (!_validateInputs()) return;

                          // 2) 이메일 로컬파트 추가 검증(선택 강화)
                          if (!_isValidEmailLocalPart(_emailController.text)) {
                            _setErrorMessage('이메일을 다시 확인하세요');
                            return;
                          }

                          // 3) 시간 정합성 검증
                          if (!_validateTimes()) return;

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
                            // isWorking (초기값 정책 유지)
                            false,
                            // isSaved   (초기값 정책 유지)
                            widget.areaValue,
                            // selectedArea (정책 유지)
                            _timeToString(_startTime),
                            _timeToString(_endTime),
                            _selectedHolidays.toList(),
                            _positionController.text,
                          );

                          // onSave가 async여도 기존 패턴과 동일하게 즉시 닫음
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                        ),
                        child: Text(isEditMode ? '수정' : '생성'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
