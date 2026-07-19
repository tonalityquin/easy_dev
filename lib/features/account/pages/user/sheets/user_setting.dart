import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../app/utils/snackbar_helper.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../../shared/auth/five_digit_password_generator.dart';
import '../../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../domain/models/user/user_model.dart';
import 'widgets/user_role_type_section.dart';

class UserSettingBottomSheet extends StatefulWidget {
  final void Function(
    String name,
    String phone,
    String email,
    String role,
    List<String> modes,
    String password,
    String area,
    String division,
    bool isWorking,
    bool isSaved,
    String selectedArea,
    Map<String, String?> startTimeByWeekday,
    Map<String, String?> endTimeByWeekday,
    List<String> fixedHolidays,
    List<String> breakDays,
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
  static const List<String> _days = <String>['월', '화', '수', '목', '금', '토', '일'];
  static const List<String> _availableModes = <String>['single', 'double', 'triple', 'minor'];
  static const Map<String, String> _modeLabels = <String, String>{
    'single': 'single',
    'double': 'double',
    'triple': 'triple',
    'minor': 'minor',
  };

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _positionController = TextEditingController();

  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _positionFocus = FocusNode();

  RoleType _selectedRole = RoleType.fieldCommon;
  final Set<String> _selectedModes = <String>{};
  Map<String, TimeOfDay?> _startByDay = <String, TimeOfDay?>{};
  Map<String, TimeOfDay?> _endByDay = <String, TimeOfDay?>{};
  Set<String> _breakDays = <String>{};
  String? _errorMessage;

  bool get isEditMode => widget.isEditMode;

  @override
  void initState() {
    super.initState();
    _startByDay = {for (final day in _days) day: null};
    _endByDay = {for (final day in _days) day: null};

    final user = widget.initialUser;
    if (user != null) {
      _nameController.text = user.name;
      _phoneController.text = user.phone;
      _emailController.text = user.email.split('@').first;
      _passwordController.text = user.password;
      _positionController.text = user.position ?? '';
      _selectedRole = RoleType.values.firstWhere(
        (role) => role.name == user.role,
        orElse: () => RoleType.fieldCommon,
      );
      _selectedModes.addAll(_normalizeAndFilterModes(user.modes));
      final excludedDays = user.fixedHolidays.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
      _startByDay = _normalizeWeekMap(user.startTimeByWeekday, fallback: user.startTime, excludedDays: excludedDays);
      _endByDay = _normalizeWeekMap(user.endTimeByWeekday, fallback: user.endTime, excludedDays: excludedDays);
      _breakDays = _normalizeDaySet(user.breakDays).intersection(_workingDaySet());
    } else {
      _passwordController.text = FiveDigitPasswordGenerator.generate();
    }

    if (_selectedModes.isEmpty) {
      _selectedModes.add('single');
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
    _positionFocus.dispose();
    super.dispose();
  }

  String? _normalizeModeToken(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return null;
    switch (value) {
      case 'single':
      case 'double':
      case 'triple':
      case 'minor':
        return value;
      case 'service':
      case 'simple':
        return 'single';
      case 'lite':
      case 'light':
        return 'double';
      case 'normal':
        return 'triple';
      default:
        return null;
    }
  }

  List<String> _normalizeAndFilterModes(Iterable<String> modes) {
    final out = <String>{};
    for (final mode in modes) {
      final normalized = _normalizeModeToken(mode);
      if (normalized != null && _availableModes.contains(normalized)) {
        out.add(normalized);
      }
    }
    return out.toList(growable: false);
  }

  Set<String> _normalizeDaySet(Iterable<String> raw) {
    return raw.map((value) => value.trim()).where((value) => _days.contains(value)).toSet();
  }

  List<String> _normalizeDayList(Iterable<String> raw) {
    final set = _normalizeDaySet(raw);
    return <String>[
      for (final day in _days)
        if (set.contains(day)) day,
    ];
  }

  Map<String, TimeOfDay?> _normalizeWeekMap(
    Map<String, TimeOfDay?> raw, {
    TimeOfDay? fallback,
    Set<String> excludedDays = const <String>{},
  }) {
    final out = <String, TimeOfDay?>{};
    final hasWeekly = raw.values.any((value) => value != null);
    for (final day in _days) {
      out[day] = hasWeekly ? raw[day] : (excludedDays.contains(day) ? null : fallback);
    }
    return out;
  }

  String _modeLabel(String mode) => _modeLabels[mode] ?? mode;

  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  String _formatTimeOfDay(TimeOfDay? time) {
    if (time == null) return '--:--';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Map<String, String?> _weekMapToStringMap(Map<String, TimeOfDay?> map) {
    final out = <String, String?>{};
    for (final day in _days) {
      out[day] = map[day] == null ? null : _formatTimeOfDay(map[day]);
    }
    return out;
  }

  Set<String> _workingDaySet() {
    final out = <String>{};
    for (final day in _days) {
      if (_startByDay[day] != null && _endByDay[day] != null) {
        out.add(day);
      }
    }
    return out;
  }

  List<String> _fixedHolidaysFromWeekMaps() {
    final out = <String>[];
    for (final day in _days) {
      if (_startByDay[day] == null && _endByDay[day] == null) {
        out.add(day);
      }
    }
    return out;
  }

  List<String> _normalizedBreakDaysForWorkingDays() {
    final workingDays = _workingDaySet();
    return <String>[
      for (final day in _days)
        if (workingDays.contains(day) && _breakDays.contains(day)) day,
    ];
  }

  bool _isHoliday(String day) => _startByDay[day] == null && _endByDay[day] == null;

  bool _isValidEmailLocalPart(String input) {
    return RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(input.trim());
  }

  bool get _nameOk => _nameController.text.trim().isNotEmpty;
  bool get _phoneOk => RegExp(r'^\d{9,}$').hasMatch(_phoneController.text.trim());
  bool get _emailOk => _emailController.text.trim().isNotEmpty && _isValidEmailLocalPart(_emailController.text);
  bool get _roleOk => _selectedModes.isNotEmpty;

  int get _workingDayCount {
    var count = 0;
    for (final day in _days) {
      if (_startByDay[day] != null && _endByDay[day] != null) count += 1;
    }
    return count;
  }

  String get _modesSummary => _selectedModes.isEmpty ? '모드 미선택' : _selectedModes.map(_modeLabel).join(', ');

  String get _timeSummary {
    if (_workingDayCount == 0) return '근무시간 미설정';
    final parts = <String>[];
    for (final day in _days) {
      final start = _startByDay[day];
      final end = _endByDay[day];
      if (start != null && end != null) {
        final breakLabel = _breakDays.contains(day) ? '휴게' : '휴게없음';
        parts.add('$day ${_formatTimeOfDay(start)}~${_formatTimeOfDay(end)} $breakLabel');
      }
    }
    if (parts.length <= 2) return parts.join(' · ');
    return '${parts.take(2).join(' · ')} 외 ${parts.length - 2}일';
  }

  void _setErrorMessage(String? message) {
    setState(() => _errorMessage = message);
  }

  void _clearErrorIfAny() {
    setState(() => _errorMessage = null);
  }

  bool _validateWeeklyTimes() {
    var hasWorkingDay = false;
    for (final day in _days) {
      final start = _startByDay[day];
      final end = _endByDay[day];
      final hasStart = start != null;
      final hasEnd = end != null;
      if (hasStart != hasEnd) {
        _setErrorMessage('$day 요일의 출근/퇴근 시간을 모두 입력하세요');
        return false;
      }
      if (start != null && end != null) {
        hasWorkingDay = true;
        if (_toMinutes(start) > _toMinutes(end)) {
          _setErrorMessage('$day 요일의 출근/퇴근 시간을 다시 확인하세요');
          return false;
        }
      }
    }
    if (!hasWorkingDay) {
      _setErrorMessage('최소 1개 요일의 근무 시간을 입력하세요');
      return false;
    }
    return true;
  }

  Future<void> _pickWeeklyTime({required String day, required bool isStart}) async {
    final current = isStart ? _startByDay[day] : _endByDay[day];
    final initial = current ??
        (isStart
            ? const TimeOfDay(hour: 9, minute: 0)
            : const TimeOfDay(hour: 18, minute: 0));
    final wasHoliday = _isHoliday(day);
    final picked = await showPromptTimePicker(
      context: context,
      initialTime: initial,
      builder: (pickerContext, child) {
        return MediaQuery(
          data: MediaQuery.of(pickerContext).copyWith(
            alwaysUse24HourFormat: true,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null || !mounted) return;
    _clearErrorIfAny();
    setState(() {
      if (isStart) {
        _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = picked;
        if (_endByDay[day] == null) {
          _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = const TimeOfDay(hour: 18, minute: 0);
        }
      } else {
        _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = picked;
        if (_startByDay[day] == null) {
          _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = const TimeOfDay(hour: 9, minute: 0);
        }
      }
      if (wasHoliday) {
        _breakDays = <String>{..._breakDays, day};
      }
    });
  }

  void _setHoliday(String day, bool value) {
    _clearErrorIfAny();
    setState(() {
      if (value) {
        _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = null;
        _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = null;
        _breakDays = <String>{..._breakDays}..remove(day);
      } else {
        _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = _startByDay[day] ?? const TimeOfDay(hour: 9, minute: 0);
        _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = _endByDay[day] ?? const TimeOfDay(hour: 18, minute: 0);
        _breakDays = <String>{..._breakDays, day};
      }
    });
  }

  void _toggleBreakDay(String day, bool value) {
    if (_isHoliday(day)) return;
    _clearErrorIfAny();
    setState(() {
      final next = <String>{..._breakDays};
      if (value) {
        next.add(day);
      } else {
        next.remove(day);
      }
      _breakDays = next;
    });
  }

  Future<void> _copyPassword() async {
    await Clipboard.setData(ClipboardData(text: _passwordController.text));
    if (!mounted) return;
    showSelectedSnackbar(
      context,
      '비밀번호를 복사했습니다.',
      usePromptUi: true,
    );
  }

  void _handleSave() {
    FocusScope.of(context).unfocus();
    if (!_nameOk) {
      _setErrorMessage('이름을 다시 입력하세요');
      return;
    }
    if (!_phoneOk) {
      _setErrorMessage('전화번호를 다시 입력하세요');
      return;
    }
    if (!_emailOk) {
      _setErrorMessage(_emailController.text.trim().isEmpty ? '이메일을 입력하세요' : '이메일을 다시 확인하세요');
      return;
    }
    if (_selectedModes.isEmpty) {
      _setErrorMessage('허용 모드를 1개 이상 선택하세요');
      return;
    }
    if (!_validateWeeklyTimes()) return;

    final normalizedModes = _normalizeAndFilterModes(_selectedModes);
    if (normalizedModes.isEmpty) {
      _setErrorMessage('허용 모드를 1개 이상 선택하세요');
      return;
    }

    widget.onSave(
      _nameController.text.trim(),
      _phoneController.text.trim(),
      '${_emailController.text.trim()}@gmail.com',
      _selectedRole.name,
      normalizedModes,
      _passwordController.text.trim(),
      widget.areaValue,
      widget.division,
      false,
      false,
      widget.areaValue,
      _weekMapToStringMap(_startByDay),
      _weekMapToStringMap(_endByDay),
      _normalizeDayList(_fixedHolidaysFromWeekMaps()),
      _normalizeDayList(_normalizedBreakDaysForWorkingDays()),
      _positionController.text.trim(),
    );

    if (mounted) Navigator.pop(context);
  }

  Widget _buildBasicSection(BuildContext context) {
    return OpsWorkSection(
      title: '계정 식별 정보',
      subtitle: isEditMode ? '기존 계정의 이름과 전화번호는 고정하고 이메일만 갱신합니다.' : '로그인 계정의 실명, 연락처, 구글 이메일을 입력합니다.',
      icon: Icons.badge_rounded,
      child: Column(
        children: [
          TextField(
            controller: _nameController,
            focusNode: _nameFocus,
            readOnly: isEditMode,
            onChanged: (_) => _clearErrorIfAny(),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            autofillHints: const [AutofillHints.name],
            decoration: opsInputDecoration(
              context,
              label: '이름',

              prefixIcon: const Icon(Icons.person_rounded),
              locked: isEditMode,
              errorText: _errorMessage == '이름을 다시 입력하세요' ? _errorMessage : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            focusNode: _phoneFocus,
            readOnly: isEditMode,
            onChanged: (_) => _clearErrorIfAny(),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: isEditMode ? null : [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
            decoration: opsInputDecoration(
              context,
              label: '전화번호',

              prefixIcon: const Icon(Icons.phone_rounded),
              locked: isEditMode,
              errorText: _errorMessage == '전화번호를 다시 입력하세요' ? _errorMessage : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            focusNode: _emailFocus,
            onChanged: (_) => _clearErrorIfAny(),
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username],
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            decoration: opsInputDecoration(
              context,
              label: '이메일',

              suffixText: '@gmail.com',
              prefixIcon: const Icon(Icons.mail_rounded),
              errorText: (_errorMessage == '이메일을 입력하세요' || _errorMessage == '이메일을 다시 확인하세요') ? _errorMessage : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OpsWorkSection(
      title: '권한과 허용 모드',
      subtitle: '역할은 계정의 접근 범위를 결정하고, 모드는 로그인 가능한 현장 화면을 제한합니다.',
      icon: Icons.admin_panel_settings_rounded,
      trailing: OpsStatusBadge(label: _roleOk ? '설정됨' : '필수', color: _roleOk ? cs.primary : cs.error, icon: _roleOk ? Icons.check_rounded : Icons.priority_high_rounded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<RoleType>(
            value: _selectedRole,
            isExpanded: true,
            decoration: opsInputDecoration(context, label: '권한', prefixIcon: const Icon(Icons.verified_user_rounded)),
            items: RoleType.values
                .map((role) => DropdownMenuItem<RoleType>(
                      value: role,
                      child: Text(role.label, overflow: TextOverflow.ellipsis),
                    ))
                .toList(growable: false),
            onChanged: (role) {
              if (role == null) return;
              _clearErrorIfAny();
              setState(() => _selectedRole = role);
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableModes.map((mode) {
              final selected = _selectedModes.contains(mode);
              return OpsFormChip(
                label: _modeLabel(mode),
                selected: selected,
                icon: Icons.widgets_rounded,
                onTap: () {
                  _clearErrorIfAny();
                  setState(() {
                    if (selected) {
                      _selectedModes.remove(mode);
                    } else {
                      _selectedModes.add(mode);
                    }
                  });
                },
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionSection(BuildContext context) {
    return OpsWorkSection(
      title: '현장 직책',
      subtitle: '목록과 근무 기록에서 계정을 구분하기 위한 보조 정보입니다.',
      icon: Icons.work_rounded,
      child: TextField(
        controller: _positionController,
        focusNode: _positionFocus,
        onChanged: (_) => _clearErrorIfAny(),
        textInputAction: TextInputAction.done,
        decoration: opsInputDecoration(
          context,
          label: '직책',

          prefixIcon: const Icon(Icons.badge_rounded),
        ),
      ),
    );
  }

  Widget _buildPasswordSection(BuildContext context) {
    return OpsWorkSection(
      title: '초기 비밀번호',
      subtitle: '자동 생성된 5자리 비밀번호를 복사해 사용자에게 전달합니다.',
      icon: Icons.lock_rounded,
      child: TextField(
        controller: _passwordController,
        readOnly: true,
        enableSuggestions: false,
        autocorrect: false,
        decoration: opsInputDecoration(
          context,
          label: '비밀번호',
          prefixIcon: const Icon(Icons.password_rounded),
          suffixIcon: IconButton(
            tooltip: '복사',
            onPressed: _copyPassword,
            icon: const Icon(Icons.copy_rounded),
          ),
        ),
      ),
    );
  }

  Widget _buildDayRow(BuildContext context, String day) {
    final cs = Theme.of(context).colorScheme;
    final start = _startByDay[day];
    final end = _endByDay[day];
    final isWorking = start != null && end != null;
    final isHoliday = !isWorking && start == null && end == null;
    final hasBreak = _breakDays.contains(day) && isWorking;
    final hasPartial = (start == null) != (end == null);
    final borderColor = hasPartial ? cs.error.withOpacity(.45) : (isWorking ? cs.primary.withOpacity(.45) : cs.outlineVariant.withOpacity(.82));
    final statusText = hasPartial ? '시간 확인 필요' : isWorking ? '${_formatTimeOfDay(start)} ~ ${_formatTimeOfDay(end)} · ${hasBreak ? '휴게 있음' : '휴게 없음'}' : '휴무';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWorking ? cs.primary.withOpacity(.06) : cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isWorking ? cs.primary : cs.surfaceVariant.withOpacity(.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(day, style: TextStyle(color: isWorking ? cs.onPrimary : cs.onSurfaceVariant, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(color: hasPartial ? cs.error : cs.onSurface, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickWeeklyTime(day: day, isStart: true),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: Text('출근 ${_formatTimeOfDay(start)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickWeeklyTime(day: day, isStart: false),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: Text('퇴근 ${_formatTimeOfDay(end)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  value: isHoliday,
                  onChanged: (value) => _setHoliday(day, value ?? false),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('휴무'),
                ),
              ),
              Expanded(
                child: CheckboxListTile(
                  value: hasBreak,
                  onChanged: isWorking ? (value) => _toggleBreakDay(day, value ?? false) : null,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('휴게'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSection(BuildContext context) {
    return OpsWorkSection(
      title: '요일별 근무 시간',
      subtitle: '휴무 요일은 기존 휴무 저장값으로 저장되고, 휴게 체크 요일만 퇴근 전 휴게 펀칭이 필요합니다.',
      icon: Icons.schedule_rounded,
      child: Column(
        children: [
          for (final day in _days) _buildDayRow(context, day),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = isEditMode ? '계정 수정' : '신규 계정 등록';
    final subtitle = isEditMode ? '계정 권한, 이메일, 직책, 근무 시간, 휴무와 휴게 요일을 운영 정책에 맞게 갱신합니다.' : '현장 사용자를 등록하고 접근 권한, 근무 시간, 휴무와 휴게 요일을 지정합니다.';
    final areaLabel = widget.division.trim().isEmpty ? widget.areaValue : '${widget.division} · ${widget.areaValue}';

    return OpsWorkSheet(
      title: title,
      subtitle: subtitle,
      icon: Icons.manage_accounts_rounded,
      areaLabel: areaLabel,
      metrics: [
        OpsMetric(label: '식별', value: _nameOk && _phoneOk && _emailOk ? '완료' : '필수', icon: Icons.badge_rounded, color: _nameOk && _phoneOk && _emailOk ? cs.primary : cs.error),
        OpsMetric(label: '권한', value: _selectedRole.label.split('(').first, icon: Icons.verified_user_rounded, color: cs.primary),
        OpsMetric(label: '모드', value: '${_selectedModes.length}', icon: Icons.widgets_rounded, color: _selectedModes.isEmpty ? cs.error : cs.primary),
        OpsMetric(label: '근무일', value: '$_workingDayCount', icon: Icons.schedule_rounded, color: _workingDayCount == 0 ? cs.error : cs.primary),
      ],
      bottomBar: OpsBottomActionBar(
        children: [
          Expanded(
            child: OpsActionButton(
              label: '취소',
              icon: Icons.close_rounded,
              onPressed: () => Navigator.pop(context),
              tonal: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OpsActionButton(
              label: isEditMode ? '계정 수정' : '계정 등록',
              icon: isEditMode ? Icons.save_rounded : Icons.person_add_alt_1_rounded,
              onPressed: _handleSave,
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpsInlineMessage(message: _errorMessage),
          OpsCommandPanel(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OpsInfoPill(text: isEditMode ? '수정 모드' : '등록 모드', icon: isEditMode ? Icons.edit_rounded : Icons.person_add_alt_1_rounded),
                  OpsInfoPill(text: _modesSummary, icon: Icons.widgets_rounded),
                  OpsInfoPill(text: _timeSummary, icon: Icons.schedule_rounded),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildBasicSection(context),
          _buildRoleSection(context),
          _buildPositionSection(context),
          _buildPasswordSection(context),
          _buildTimeSection(context),
        ],
      ),
    );
  }
}
