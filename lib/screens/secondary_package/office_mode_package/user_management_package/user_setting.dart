import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../models/user_model.dart';
import 'sections/user_password_display_section.dart';
import 'sections/user_role_type_section.dart';
import 'sections/user_input_section.dart';
import 'sections/user_role_dropdown_section.dart';
import 'sections/user_validation_helpers_section.dart';

// 🔔 추가: endTime 리마인더 서비스
import '../../../../services/endtime_reminder_service.dart';

/// 서비스 로그인 카드 팔레트(브랜드 톤)
class _SvcColors {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 진한 텍스트/아이콘
  static const light = Color(0xFF5472D3); // 라이트 톤/보더
  static const fg = Color(0xFFFFFFFF);
}

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
  RoleType _selectedRole = RoleType.fieldCommon;
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
      _emailController.text = user.email.split('@').first;
      _passwordController.text = user.password;
      _positionController.text = user.position ?? '';
      _selectedRole = RoleType.values.firstWhere(
            (r) => r.name == user.role,
        orElse: () => RoleType.fieldCommon,
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

  // 11시 라벨(상단 좌측 고정)
  Widget _buildScreenTag(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ??
        const TextStyle(
          fontSize: 11,
          color: Colors.black54,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 4),
          child: Semantics(
            label: 'screen_tag: user setting',
            child: Text('user setting', style: style),
          ),
        ),
      ),
    );
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

  // 로컬파트 검증: 영문/숫자/._- 만 허용(필요 시 정책 보강)
  bool _isValidEmailLocalPart(String input) {
    final reg = RegExp(r'^[a-zA-Z0-9._-]+$');
    return input.isNotEmpty && reg.hasMatch(input);
  }

  String _generateRandomPassword() {
    final random = Random();
    return (10000 + random.nextInt(90000)).toString(); // 5자리 숫자
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
        // 브랜드 컬러를 다이얼에도 살짝 반영
        final colorScheme = theme.colorScheme.copyWith(
          primary: _SvcColors.base,
          secondary: _SvcColors.light,
        );
        final branded = theme.copyWith(colorScheme: colorScheme);
        return MediaQuery(
          data: mq.copyWith(alwaysUse24HourFormat: true),
          child: Theme(data: branded, child: child!),
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
    return time != null
        ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
        : null;
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isEditMode = widget.isEditMode || (widget.initialUser != null);

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final effectiveHeight = screenHeight - bottomInset; // ✅ 최상단까지 차오르도록 높이 고정

    return SafeArea(
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: bottomInset), // ✅ 키보드 여백
            child: SizedBox(
              height: effectiveHeight,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white, // 바텀시트 배경
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

                    // 상단 브랜드 배지 느낌의 타이틀
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _SvcColors.light.withOpacity(.20),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _SvcColors.light.withOpacity(.45)),
                          ),
                          child: const Icon(Icons.person_outline,
                              color: _SvcColors.dark),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '사용자 정보',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _SvcColors.dark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ===== 본문 스크롤 영역 =====
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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

                            // 권한 드롭다운 (브랜드 테두리 감싸기)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _SvcColors.light.withOpacity(.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color:
                                    _SvcColors.light.withOpacity(.35)),
                              ),
                              child: UserRoleDropdownSection(
                                selectedRole: _selectedRole,
                                onChanged: (value) =>
                                    setState(() => _selectedRole = value),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 직책
                            TextField(
                              controller: _positionController,
                              onTapOutside: (_) =>
                                  FocusScope.of(context).unfocus(),
                              decoration: InputDecoration(
                                labelText: '직책',
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(
                                      color: _SvcColors.base, width: 1.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: _SvcColors.light.withOpacity(.45),
                                  ),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                isDense: true,
                                contentPadding:
                                const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 12),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 비밀번호 표시
                            UserPasswordDisplaySection(
                                controller: _passwordController),
                            const SizedBox(height: 16),

                            // 출근/퇴근 시간 선택 (브랜드 톤 Outlined)
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _selectTime(isStartTime: true),
                                    icon: const Icon(Icons.schedule),
                                    label: Text(
                                        '출근: ${_formatTimeOfDay(_startTime)}'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _SvcColors.dark,
                                      side: BorderSide(
                                          color: _SvcColors.light
                                              .withOpacity(.75)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius.circular(12),
                                      ),
                                      padding:
                                      const EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _selectTime(isStartTime: false),
                                    icon: const Icon(Icons.schedule),
                                    label: Text(
                                        '퇴근: ${_formatTimeOfDay(_endTime)}'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _SvcColors.dark,
                                      side: BorderSide(
                                          color: _SvcColors.light
                                              .withOpacity(.75)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius.circular(12),
                                      ),
                                      padding:
                                      const EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // 고정 휴일
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '고정 휴일 선택 (선택사항)',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: _SvcColors.dark,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: _days.map((day) {
                                final isSelected =
                                _selectedHolidays.contains(day);
                                return FilterChip(
                                  label: Text(day),
                                  selected: isSelected,
                                  selectedColor:
                                  _SvcColors.light.withOpacity(.25),
                                  checkmarkColor: _SvcColors.dark,
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

                            // 현재 지역 Pill
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _SvcColors.light.withOpacity(.18),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                      color: _SvcColors.light
                                          .withOpacity(.35)),
                                ),
                                child: Text(
                                  '현재 지역: ${widget.areaValue}',
                                  style: const TextStyle(
                                    color: _SvcColors.dark,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),

                            if (_errorMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(color: cs.error),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ===== 하단 버튼 =====
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _SvcColors.dark,
                              side: BorderSide(
                                  color:
                                  _SvcColors.light.withOpacity(.75)),
                              shape: const StadiumBorder(),
                              padding:
                              const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('취소'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              FocusScope.of(context).unfocus();

                              // 1) 필드 검증
                              if (!_validateInputs()) return;

                              // 2) 이메일 로컬파트 추가 검증
                              if (!_isValidEmailLocalPart(
                                  _emailController.text)) {
                                _setErrorMessage('이메일을 다시 확인하세요');
                                return;
                              }

                              // 3) 시간 정합성 검증
                              if (!_validateTimes()) return;

                              final fullEmail =
                                  '${_emailController.text}@gmail.com';

                              // 저장 콜백
                              widget.onSave(
                                _nameController.text,
                                _phoneController.text,
                                fullEmail,
                                _selectedRole.name,
                                _passwordController.text,
                                widget.areaValue,
                                widget.division,
                                false, // isWorking 초기 정책
                                false, // isSaved 초기 정책
                                widget.areaValue, // selectedArea
                                _timeToString(_startTime),
                                _timeToString(_endTime),
                                _selectedHolidays.toList(),
                                _positionController.text,
                              );

                              // 🔔 endTime 기준 알림 스케줄링/취소
                              final endTime = _timeToString(_endTime);
                              if (endTime != null) {
                                await EndtimeReminderService.instance
                                    .scheduleDailyOneHourBefore(endTime);
                              } else {
                                await EndtimeReminderService.instance
                                    .cancel();
                              }

                              if (mounted) {
                                Navigator.pop(context);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _SvcColors.base,
                              foregroundColor: _SvcColors.fg,
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
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

          // 11시 라벨 오버레이
          _buildScreenTag(context),
        ],
      ),
    );
  }
}
