import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../../models/user_model.dart';
import 'sections/user_password_display_section.dart';
import 'sections/user_role_type_section.dart';
import 'sections/user_input_section.dart';
import 'sections/user_role_dropdown_section.dart';
import 'sections/user_validation_helpers_section.dart';

// 🔔 endTime 리마인더 서비스 (프로젝트 실제 파일명/대소문자에 맞추세요)
import '../../../../../services/endTime_reminder_service.dart';

import '../../../../../theme.dart';

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
  final _positionFocus = FocusNode();

  // --- States ---
  RoleType _selectedRole = RoleType.fieldCommon;
  String? _errorMessage;

  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  static const List<String> _days = ['월', '화', '수', '목', '금', '토', '일'];
  final Set<String> _selectedHolidays = {};

  // --- UI: 단계형(확장패널) 구성 ---
  static const int _panelBasic = 0;
  static const int _panelRole = 1;
  static const int _panelPosition = 2;
  static const int _panelPassword = 3;
  static const int _panelTime = 4;
  static const int _panelHoliday = 5;

  late final List<bool> _expanded;
  final ScrollController _scrollController = ScrollController();

  final GlobalKey _keyBasic = GlobalKey();
  final GlobalKey _keyRole = GlobalKey();
  final GlobalKey _keyPosition = GlobalKey();
  final GlobalKey _keyPassword = GlobalKey();
  final GlobalKey _keyTime = GlobalKey();
  final GlobalKey _keyHoliday = GlobalKey();

  @override
  void initState() {
    super.initState();

    _expanded = List<bool>.filled(6, false);
    _expanded[_panelBasic] = true;

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

    _nameFocus.addListener(() {
      if (_nameFocus.hasFocus) _openPanelAndScroll(_panelBasic);
    });
    _phoneFocus.addListener(() {
      if (_phoneFocus.hasFocus) _openPanelAndScroll(_panelBasic);
    });
    _emailFocus.addListener(() {
      if (_emailFocus.hasFocus) _openPanelAndScroll(_panelBasic);
    });
    _positionFocus.addListener(() {
      if (_positionFocus.hasFocus) _openPanelAndScroll(_panelPosition);
    });
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
    _positionFocus.dispose();

    _scrollController.dispose();
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

  // --- Helpers: validation/format ---

  void _setErrorMessage(String? message) {
    setState(() => _errorMessage = message);
  }

  void _clearErrorIfAny() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  bool _validateInputs() {
    final error = validateInputs({
      '이름': _nameController.text,
      '전화번호': _phoneController.text,
      '이메일': _emailController.text, // 로컬파트
    });
    _setErrorMessage(error);
    return error == null;
  }

  bool _isValidEmailLocalPart(String input) {
    final reg = RegExp(r'^[a-zA-Z0-9._-]+$');
    return input.isNotEmpty && reg.hasMatch(input);
  }

  String _generateRandomPassword() {
    final random = Random();
    return (10000 + random.nextInt(90000)).toString();
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
    final palette = AppCardPalette.of(context);
    final base = palette.serviceBase;
    final light = palette.serviceLight;

    final initial = isStartTime
        ? (_startTime ?? const TimeOfDay(hour: 9, minute: 0))
        : (_endTime ?? const TimeOfDay(hour: 18, minute: 0));

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) {
        final mq = MediaQuery.of(ctx);
        final branded = theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(
            primary: base,
            secondary: light,
          ),
        );
        return MediaQuery(
          data: mq.copyWith(alwaysUse24HourFormat: true),
          child: Theme(data: branded, child: child!),
        );
      },
    );

    if (picked != null) {
      _clearErrorIfAny();
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

  // --- UI helpers: 단계/요약/완료 표시 ---

  bool get _isBasicInfoComplete {
    final nameOk = _nameController.text.trim().isNotEmpty;
    final phoneOk = RegExp(r'^\d{9,}$').hasMatch(_phoneController.text.trim());
    final emailOk = _emailController.text.trim().isNotEmpty;
    return nameOk && phoneOk && emailOk;
  }

  bool get _isEmailLocalPartValid {
    return _isValidEmailLocalPart(_emailController.text.trim());
  }

  String get _basicSummary {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final shownName = name.isEmpty ? '이름 미입력' : name;
    final shownPhone = phone.isEmpty ? '전화 미입력' : phone;
    final shownEmail = email.isEmpty ? '이메일 미입력' : '$email@gmail.com';
    return '$shownName · $shownPhone · $shownEmail';
  }

  String get _roleSummary => _selectedRole.label;

  String get _positionSummary {
    final p = _positionController.text.trim();
    return p.isEmpty ? '직책(선택)' : p;
  }

  String get _timeSummary {
    final s = _formatTimeOfDay(_startTime);
    final e = _formatTimeOfDay(_endTime);
    if (_startTime == null && _endTime == null) return '근무시간(선택)';
    return '$s ~ $e';
  }

  String get _holidaySummary {
    if (_selectedHolidays.isEmpty) return '고정 휴일(선택)';
    return '고정 휴일 ${_selectedHolidays.length}개 선택';
  }

  void _openPanelAndScroll(int panelIndex) {
    if (!mounted) return;

    setState(() {
      for (int i = 0; i < _expanded.length; i++) {
        _expanded[i] = i == panelIndex;
      }
    });

    final key = switch (panelIndex) {
      _panelBasic => _keyBasic,
      _panelRole => _keyRole,
      _panelPosition => _keyPosition,
      _panelPassword => _keyPassword,
      _panelTime => _keyTime,
      _panelHoliday => _keyHoliday,
      _ => _keyBasic,
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.12,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildPanelHeader({
    required Color base,
    required Color dark,
    required Color light,
    required int step,
    required String title,
    required String summary,
    required bool isDone,
    required bool isExpanded,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isExpanded ? base.withOpacity(.12) : light.withOpacity(.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isExpanded ? base.withOpacity(.35) : light.withOpacity(.35),
          ),
        ),
        child: Center(
          child: isDone
              ? Icon(Icons.check, color: dark, size: 20)
              : Text(
                  '$step',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: dark,
                  ),
                ),
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: dark,
        ),
      ),
      subtitle: Text(
        summary,
        style: TextStyle(
          color: Colors.black.withOpacity(.60),
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Icon(
        isExpanded ? Icons.expand_less : Icons.expand_more,
        color: dark,
      ),
    );
  }

  Widget _buildPanelBody({
    required Color dark,
    required Color light,
    required Widget child,
    int? nextPanel,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          if (nextPanel != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openPanelAndScroll(nextPanel),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('다음 단계로 이동'),
              style: OutlinedButton.styleFrom(
                foregroundColor: dark,
                side: BorderSide(color: light.withOpacity(.75)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final palette = AppCardPalette.of(context);
    final base = palette.serviceBase;
    final dark = palette.serviceDark;
    final light = palette.serviceLight;
    final fg = cs.onPrimary;

    final isEditMode = widget.isEditMode || (widget.initialUser != null);

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final effectiveHeight = screenHeight - bottomInset;

    return SafeArea(
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SizedBox(
              height: effectiveHeight,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
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

                    // 타이틀
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: light.withOpacity(.20),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: light.withOpacity(.45)),
                          ),
                          child: Icon(Icons.person_outline, color: dark),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isEditMode ? '사용자 정보 수정' : '사용자 정보 생성',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: dark,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: light.withOpacity(.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: light.withOpacity(.35)),
                          ),
                          child: Text(
                            widget.areaValue,
                            style: TextStyle(
                              color: dark,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 입력 가이드
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: light.withOpacity(.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: light.withOpacity(.25)),
                      ),
                      child: Text(
                        isEditMode
                            ? '수정 모드에서는 이름/전화번호는 변경할 수 없습니다. 다른 항목만 수정하세요.'
                            : '아래 단계별로 하나씩 입력하면 됩니다. 각 단계를 열어 입력하고, 완료되면 체크 표시로 바뀝니다.',
                        style: TextStyle(
                          color: dark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: ExpansionPanelList(
                          expansionCallback: (index, isExpanded) {
                            _clearErrorIfAny();
                            setState(() {
                              for (int i = 0; i < _expanded.length; i++) {
                                _expanded[i] = (i == index) ? !isExpanded : false;
                              }
                            });
                          },
                          children: [
                            // 1) 기본 정보
                            ExpansionPanel(
                              canTapOnHeader: true,
                              isExpanded: _expanded[_panelBasic],
                              headerBuilder: (ctx, _) => KeyedSubtree(
                                key: _keyBasic,
                                child: _buildPanelHeader(
                                  base: base,
                                  dark: dark,
                                  light: light,
                                  step: 1,
                                  title: '기본 정보',
                                  summary: _basicSummary,
                                  isDone: _isBasicInfoComplete && _isEmailLocalPartValid,
                                  isExpanded: _expanded[_panelBasic],
                                ),
                              ),
                              body: _buildPanelBody(
                                dark: dark,
                                light: light,
                                nextPanel: _panelRole,
                                child: UserInputSection(
                                  nameController: _nameController,
                                  phoneController: _phoneController,
                                  emailController: _emailController,
                                  nameFocus: _nameFocus,
                                  phoneFocus: _phoneFocus,
                                  emailFocus: _emailFocus,
                                  errorMessage: _errorMessage,
                                  onEdited: _clearErrorIfAny,
                                  emailLocalPartValidator: _isValidEmailLocalPart,
                                  lockNameAndPhone: isEditMode, // ✅ 수정 모드 잠금
                                ),
                              ),
                            ),

                            // 2) 권한
                            ExpansionPanel(
                              canTapOnHeader: true,
                              isExpanded: _expanded[_panelRole],
                              headerBuilder: (ctx, _) => KeyedSubtree(
                                key: _keyRole,
                                child: _buildPanelHeader(
                                  base: base,
                                  dark: dark,
                                  light: light,
                                  step: 2,
                                  title: '권한',
                                  summary: _roleSummary,
                                  isDone: true,
                                  isExpanded: _expanded[_panelRole],
                                ),
                              ),
                              body: _buildPanelBody(
                                dark: dark,
                                light: light,
                                nextPanel: _panelPosition,
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: light.withOpacity(.06),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: light.withOpacity(.35)),
                                  ),
                                  child: UserRoleDropdownSection(
                                    selectedRole: _selectedRole,
                                    onChanged: (value) {
                                      _clearErrorIfAny();
                                      setState(() => _selectedRole = value);
                                    },
                                  ),
                                ),
                              ),
                            ),

                            // 3) 직책(선택)
                            ExpansionPanel(
                              canTapOnHeader: true,
                              isExpanded: _expanded[_panelPosition],
                              headerBuilder: (ctx, _) => KeyedSubtree(
                                key: _keyPosition,
                                child: _buildPanelHeader(
                                  base: base,
                                  dark: dark,
                                  light: light,
                                  step: 3,
                                  title: '직책(선택)',
                                  summary: _positionSummary,
                                  isDone: _positionController.text.trim().isNotEmpty,
                                  isExpanded: _expanded[_panelPosition],
                                ),
                              ),
                              body: _buildPanelBody(
                                dark: dark,
                                light: light,
                                nextPanel: _panelPassword,
                                child: TextField(
                                  controller: _positionController,
                                  focusNode: _positionFocus,
                                  onChanged: (_) => _clearErrorIfAny(),
                                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                                  decoration: InputDecoration(
                                    labelText: '직책',
                                    helperText: '예: 과장, 매니저, 기사 등 (미입력 가능)',
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: base, width: 1.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: light.withOpacity(.45)),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // 4) 비밀번호(읽기 전용)
                            ExpansionPanel(
                              canTapOnHeader: true,
                              isExpanded: _expanded[_panelPassword],
                              headerBuilder: (ctx, _) => KeyedSubtree(
                                key: _keyPassword,
                                child: _buildPanelHeader(
                                  base: base,
                                  dark: dark,
                                  light: light,
                                  step: 4,
                                  title: '비밀번호',
                                  summary: '자동 생성/복사 가능',
                                  isDone: _passwordController.text.trim().isNotEmpty,
                                  isExpanded: _expanded[_panelPassword],
                                ),
                              ),
                              body: _buildPanelBody(
                                dark: dark,
                                light: light,
                                nextPanel: _panelTime,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    UserPasswordDisplaySection(
                                      controller: _passwordController,
                                      enableMonospace: true,
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: light.withOpacity(.06),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: light.withOpacity(.25)),
                                      ),
                                      child: Text(
                                        '비밀번호는 읽기 전용입니다. 우측 복사 버튼으로 전달하세요.',
                                        style: TextStyle(
                                          color: dark,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // 5) 근무 시간(선택)
                            ExpansionPanel(
                              canTapOnHeader: true,
                              isExpanded: _expanded[_panelTime],
                              headerBuilder: (ctx, _) => KeyedSubtree(
                                key: _keyTime,
                                child: _buildPanelHeader(
                                  base: base,
                                  dark: dark,
                                  light: light,
                                  step: 5,
                                  title: '근무 시간(선택)',
                                  summary: _timeSummary,
                                  isDone: _startTime != null || _endTime != null,
                                  isExpanded: _expanded[_panelTime],
                                ),
                              ),
                              body: _buildPanelBody(
                                dark: dark,
                                light: light,
                                nextPanel: _panelHoliday,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: light.withOpacity(.06),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: light.withOpacity(.25)),
                                      ),
                                      child: Text(
                                        '퇴근 시간이 설정되면 “퇴근 1시간 전” 알림이 자동 예약됩니다.',
                                        style: TextStyle(
                                          color: dark,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () {
                                              _openPanelAndScroll(_panelTime);
                                              _selectTime(isStartTime: true);
                                            },
                                            icon: const Icon(Icons.schedule),
                                            label: Text('출근: ${_formatTimeOfDay(_startTime)}'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: dark,
                                              side: BorderSide(color: light.withOpacity(.75)),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              padding: const EdgeInsets.symmetric(
                                                vertical: 12,
                                                horizontal: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () {
                                              _openPanelAndScroll(_panelTime);
                                              _selectTime(isStartTime: false);
                                            },
                                            icon: const Icon(Icons.schedule),
                                            label: Text('퇴근: ${_formatTimeOfDay(_endTime)}'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: dark,
                                              side: BorderSide(color: light.withOpacity(.75)),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              padding: const EdgeInsets.symmetric(
                                                vertical: 12,
                                                horizontal: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // 6) 고정 휴일(선택)
                            ExpansionPanel(
                              canTapOnHeader: true,
                              isExpanded: _expanded[_panelHoliday],
                              headerBuilder: (ctx, _) => KeyedSubtree(
                                key: _keyHoliday,
                                child: _buildPanelHeader(
                                  base: base,
                                  dark: dark,
                                  light: light,
                                  step: 6,
                                  title: '고정 휴일(선택)',
                                  summary: _holidaySummary,
                                  isDone: _selectedHolidays.isNotEmpty,
                                  isExpanded: _expanded[_panelHoliday],
                                ),
                              ),
                              body: _buildPanelBody(
                                dark: dark,
                                light: light,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '요일을 선택하세요',
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: dark,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _days.map((day) {
                                        final isSelected = _selectedHolidays.contains(day);
                                        return FilterChip(
                                          label: Text(day),
                                          selected: isSelected,
                                          selectedColor: light.withOpacity(.25),
                                          checkmarkColor: dark,
                                          onSelected: (selected) {
                                            _clearErrorIfAny();
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
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (_errorMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.error.withOpacity(.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.error.withOpacity(.30)),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: cs.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: dark,
                              side: BorderSide(color: light.withOpacity(.75)),
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('취소'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              FocusScope.of(context).unfocus();

                              if (!_validateInputs()) {
                                _openPanelAndScroll(_panelBasic);
                                return;
                              }

                              if (!_isValidEmailLocalPart(_emailController.text)) {
                                _setErrorMessage('이메일을 다시 확인하세요');
                                _openPanelAndScroll(_panelBasic);
                                return;
                              }

                              if (!_validateTimes()) {
                                _openPanelAndScroll(_panelTime);
                                return;
                              }

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
                                _positionController.text,
                              );

                              final endTime = _timeToString(_endTime);
                              if (endTime != null) {
                                await EndTimeReminderService.instance.scheduleDailyOneHourBefore(endTime);
                              } else {
                                await EndTimeReminderService.instance.cancel();
                              }

                              if (mounted) {
                                Navigator.pop(context);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: base,
                              foregroundColor: fg,
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(vertical: 14),
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
          _buildScreenTag(context),
        ],
      ),
    );
  }
}
