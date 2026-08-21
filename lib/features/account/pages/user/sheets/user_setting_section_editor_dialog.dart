import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../../app/utils/snackbar_helper.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../../shared/auth/five_digit_password_generator.dart';
import '../../../../../shared/secondary/application/secondary_account_workspace_state.dart';
import '../../../../../shared/secondary/widgets/ops_console_widgets.dart';
import 'models/user_settings_draft.dart';
import 'widgets/user_role_type_section.dart';

class UserSettingSectionEditorDialog extends StatefulWidget {
  const UserSettingSectionEditorDialog({
    super.key,
    required this.section,
    required this.initialDraft,
    required this.isEditMode,
    required this.trace,
    required this.onApply,
  });

  final UserSettingsSection section;
  final UserSettingsDraft initialDraft;
  final bool isEditMode;
  final DeveloperOperationTrace trace;
  final ValueChanged<UserSettingsDraft> onApply;

  @override
  State<UserSettingSectionEditorDialog> createState() =>
      _UserSettingSectionEditorDialogState();
}

class _UserSettingSectionEditorDialogState
    extends State<UserSettingSectionEditorDialog> {
  static const List<String> _days = <String>['월', '화', '수', '목', '금', '토', '일'];
  static const List<String> _availableModes = <String>[
    'single',
    'double',
    'triple',
    'minor',
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _positionController;
  late final TextEditingController _passwordController;
  late RoleType _role;
  late Set<String> _modes;
  late Map<String, TimeOfDay?> _startByDay;
  late Map<String, TimeOfDay?> _endByDay;
  late Set<String> _breakDays;
  bool _submitted = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _nameController = TextEditingController(text: draft.name);
    _phoneController = TextEditingController(text: draft.phone);
    _emailController = TextEditingController(text: draft.emailLocal);
    _positionController = TextEditingController(text: draft.position);
    _passwordController = TextEditingController(text: draft.password);
    _role = draft.role;
    _modes = Set<String>.of(draft.modes);
    _startByDay = Map<String, TimeOfDay?>.of(draft.startByDay);
    _endByDay = Map<String, TimeOfDay?>.of(draft.endByDay);
    _breakDays = Set<String>.of(draft.breakDays);
    widget.trace.log('편집 화면이 열렸습니다: section=${widget.section.name}');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _positionController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  String _formatTime(TimeOfDay? time) {
    if (time == null) return '--:--';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  bool _isValidEmailLocalPart(String value) {
    return RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value.trim());
  }

  String get _title {
    switch (widget.section) {
      case UserSettingsSection.identity:
        return '기본 정보';
      case UserSettingsSection.permission:
        return '권한과 허용 모드';
      case UserSettingsSection.position:
        return '현장 직책';
      case UserSettingsSection.password:
        return '초기 비밀번호';
      case UserSettingsSection.schedule:
        return '요일별 근무 시간';
    }
  }

  IconData get _icon {
    switch (widget.section) {
      case UserSettingsSection.identity:
        return Icons.person_rounded;
      case UserSettingsSection.permission:
        return Icons.verified_user_rounded;
      case UserSettingsSection.position:
        return Icons.badge_rounded;
      case UserSettingsSection.password:
        return Icons.password_rounded;
      case UserSettingsSection.schedule:
        return Icons.schedule_rounded;
    }
  }

  bool get _identityOk {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    return name.isNotEmpty &&
        RegExp(r'^\d{9,}$').hasMatch(phone) &&
        email.isNotEmpty &&
        _isValidEmailLocalPart(email);
  }

  bool get _permissionOk => _modes.isNotEmpty;

  bool get _passwordOk =>
      RegExp(r'^\d{5}$').hasMatch(_passwordController.text.trim());

  bool get _scheduleOk {
    for (final day in _days) {
      final start = _startByDay[day];
      final end = _endByDay[day];
      if ((start == null) != (end == null)) return false;
      if (start != null && end != null && _toMinutes(start) > _toMinutes(end)) {
        return false;
      }
    }
    return true;
  }

  String? get _scheduleError {
    if (_scheduleOk) return null;
    for (final day in _days) {
      final start = _startByDay[day];
      final end = _endByDay[day];
      if ((start == null) != (end == null)) {
        return '$day 요일의 출근/퇴근 시간을 모두 입력하세요.';
      }
      if (start != null && end != null && _toMinutes(start) > _toMinutes(end)) {
        return '$day 요일의 출근/퇴근 시간을 다시 확인하세요.';
      }
    }
    return '근무 일정을 다시 확인하세요.';
  }

  bool _validate() {
    switch (widget.section) {
      case UserSettingsSection.identity:
        return _identityOk;
      case UserSettingsSection.permission:
        return _permissionOk;
      case UserSettingsSection.position:
        return true;
      case UserSettingsSection.password:
        return _passwordOk;
      case UserSettingsSection.schedule:
        return _scheduleOk;
    }
  }

  UserSettingsDraft _resultDraft() {
    final base = widget.initialDraft;
    switch (widget.section) {
      case UserSettingsSection.identity:
        return base.copyWith(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          emailLocal: _emailController.text.trim(),
        );
      case UserSettingsSection.permission:
        return base.copyWith(
          role: _role,
          modes: _modes,
        );
      case UserSettingsSection.position:
        return base.copyWith(position: _positionController.text.trim());
      case UserSettingsSection.password:
        return base.copyWith(password: _passwordController.text.trim());
      case UserSettingsSection.schedule:
        return base.copyWith(
          startByDay: _startByDay,
          endByDay: _endByDay,
          breakDays: _breakDays,
        );
    }
  }

  Future<void> _apply() async {
    setState(() => _submitted = true);
    if (!_validate()) {
      widget.trace.log('입력 검증 실패: section=${widget.section.name}');
      await HapticFeedback.mediumImpact();
      return;
    }
    final result = _resultDraft();
    final workingDays = _days.where((day) {
      return result.startByDay[day] != null && result.endByDay[day] != null;
    }).length;
    widget.trace.log(
      '편집 적용: section=${widget.section.name} modes=${result.modes.length} workingDays=$workingDays passwordLength=${result.password.length}',
    );
    widget.onApply(result);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(true);
  }

  void _cancel() {
    widget.trace.log('편집 취소: section=${widget.section.name}');
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  Future<void> _showDeveloperTrace() async {
    widget.trace.log('개발자 로그 Status Dialog 요청: section=${widget.section.name}');
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '$_title 편집 로그',
      description: '현재 편집 동작의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
    );
  }

  Future<void> _copyPassword() async {
    await Clipboard.setData(
      ClipboardData(text: _passwordController.text.trim()),
    );
    widget.trace.log('비밀번호 클립보드 복사: length=${_passwordController.text.trim().length}');
    if (!mounted) return;
    showSelectedSnackbar(
      context,
      '비밀번호를 복사했습니다.',
      useCommonUi: true,
    );
  }

  void _regeneratePassword() {
    final next = FiveDigitPasswordGenerator.generate();
    setState(() => _passwordController.text = next);
    widget.trace.log('비밀번호 재생성: length=${next.length}');
  }

  Future<void> _pickTime({required String day, required bool isStart}) async {
    final current = isStart ? _startByDay[day] : _endByDay[day];
    final initial = current ??
        (isStart
            ? const TimeOfDay(hour: 9, minute: 0)
            : const TimeOfDay(hour: 18, minute: 0));
    final wasHoliday = _startByDay[day] == null && _endByDay[day] == null;
    final picked = await showCommonTimePicker(
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
    setState(() {
      if (isStart) {
        _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = picked;
        if (_endByDay[day] == null) {
          _endByDay = Map<String, TimeOfDay?>.of(_endByDay)
            ..[day] = const TimeOfDay(hour: 18, minute: 0);
        }
      } else {
        _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = picked;
        if (_startByDay[day] == null) {
          _startByDay = Map<String, TimeOfDay?>.of(_startByDay)
            ..[day] = const TimeOfDay(hour: 9, minute: 0);
        }
      }
      if (wasHoliday) {
        _breakDays = <String>{..._breakDays, day};
      }
    });
    widget.trace.log('근무 시간 변경: day=$day field=${isStart ? 'start' : 'end'}');
  }

  void _setHoliday(String day, bool value) {
    setState(() {
      if (value) {
        _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = null;
        _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = null;
        _breakDays = <String>{..._breakDays}..remove(day);
      } else {
        _startByDay = Map<String, TimeOfDay?>.of(_startByDay)
          ..[day] = _startByDay[day] ?? const TimeOfDay(hour: 9, minute: 0);
        _endByDay = Map<String, TimeOfDay?>.of(_endByDay)
          ..[day] = _endByDay[day] ?? const TimeOfDay(hour: 18, minute: 0);
        _breakDays = <String>{..._breakDays, day};
      }
    });
    widget.trace.log('휴무 상태 변경: day=$day holiday=$value');
  }

  void _toggleBreak(String day, bool value) {
    setState(() {
      _breakDays = <String>{..._breakDays};
      if (value) {
        if (_startByDay[day] != null && _endByDay[day] != null) {
          _breakDays.add(day);
        }
      } else {
        _breakDays.remove(day);
      }
    });
    widget.trace.log('휴게 상태 변경: day=$day break=$value');
  }

  Widget _inlineError(BuildContext context, String? message) {
    if (message == null || message.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: tokens.danger),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message.trim(),
              style: textTheme.labelSmall?.copyWith(
                color: tokens.danger,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _identityEditor(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _nameController,
          readOnly: widget.isEditMode,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_submitted) setState(() {});
          },
          autofillHints: const <String>[AutofillHints.name],
          decoration: opsInputDecoration(
            context,
            label: '이름',
            prefixIcon: const Icon(Icons.person_rounded),
            locked: widget.isEditMode,
            errorText: _submitted && _nameController.text.trim().isEmpty
                ? '이름을 입력하세요.'
                : null,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phoneController,
          readOnly: widget.isEditMode,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.phone,
          onChanged: (_) {
            if (_submitted) setState(() {});
          },
          autofillHints: const <String>[AutofillHints.telephoneNumber],
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: opsInputDecoration(
            context,
            label: '전화번호',
            prefixIcon: const Icon(Icons.phone_rounded),
            locked: widget.isEditMode,
            errorText: _submitted &&
                    !RegExp(r'^\d{9,}$')
                        .hasMatch(_phoneController.text.trim())
                ? '전화번호를 다시 확인하세요.'
                : null,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _emailController,
          textInputAction: TextInputAction.done,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) {
            if (_submitted) setState(() {});
          },
          autofillHints: const <String>[AutofillHints.username],
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.deny(RegExp(r'\s')),
          ],
          decoration: opsInputDecoration(
            context,
            label: '이메일',
            suffixText: '@gmail.com',
            prefixIcon: const Icon(Icons.mail_rounded),
            errorText: _submitted &&
                    (_emailController.text.trim().isEmpty ||
                        !_isValidEmailLocalPart(_emailController.text))
                ? '이메일을 다시 확인하세요.'
                : null,
          ),
        ),
      ],
    );
  }

  Widget _permissionEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<RoleType>(
          value: _role,
          isExpanded: true,
          decoration: opsInputDecoration(
            context,
            label: '권한',
            prefixIcon: const Icon(Icons.verified_user_rounded),
          ),
          items: RoleType.values
              .map(
                (role) => DropdownMenuItem<RoleType>(
                  value: role,
                  child: Text(role.label, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _role = value);
            widget.trace.log('권한 선택 변경: role=${value.name}');
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableModes.map((mode) {
            final selected = _modes.contains(mode);
            return OpsFormChip(
              label: mode,
              selected: selected,
              icon: Icons.widgets_rounded,
              onTap: () {
                setState(() {
                  _modes = <String>{..._modes};
                  if (selected) {
                    _modes.remove(mode);
                  } else {
                    _modes.add(mode);
                  }
                });
                widget.trace.log('허용 모드 변경: mode=$mode selected=${!selected}');
              },
            );
          }).toList(growable: false),
        ),
        AnimatedSize(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.enter,
          child: _inlineError(
            context,
            _submitted && !_permissionOk ? '허용 모드를 1개 이상 선택하세요.' : null,
          ),
        ),
      ],
    );
  }

  Widget _positionEditor(BuildContext context) {
    return TextField(
      controller: _positionController,
      textInputAction: TextInputAction.done,
      decoration: opsInputDecoration(
        context,
        label: '직책',
        prefixIcon: const Icon(Icons.badge_rounded),
      ),
    );
  }

  Widget _passwordEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _passwordController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_submitted) setState(() {});
          },
          enableSuggestions: false,
          autocorrect: false,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          decoration: opsInputDecoration(
            context,
            label: '비밀번호',
            prefixIcon: const Icon(Icons.password_rounded),
            suffixIcon: IconButton(
              tooltip: '복사',
              onPressed: _copyPassword,
              icon: const Icon(Icons.copy_rounded),
            ),
            errorText: _submitted && !_passwordOk
                ? '5자리 숫자 비밀번호를 입력하세요.'
                : null,
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _regeneratePassword,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('새 비밀번호 생성'),
        ),
      ],
    );
  }

  Widget _scheduleDay(BuildContext context, String day) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final start = _startByDay[day];
    final end = _endByDay[day];
    final working = start != null && end != null;
    final holiday = start == null && end == null;
    final hasBreak = _breakDays.contains(day) && working;
    final partial = (start == null) != (end == null);
    final invalidRange =
        start != null && end != null && _toMinutes(start) > _toMinutes(end);
    final invalid = partial || invalidRange;
    final status = invalid
        ? '시간 확인 필요'
        : working
            ? '${_formatTime(start)} ~ ${_formatTime(end)} · ${hasBreak ? '휴게 있음' : '휴게 없음'}'
            : '휴무';
    final color = invalid
        ? tokens.danger
        : working
            ? tokens.accent
            : tokens.textSecondary;

    return AnimatedContainer(
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      color: invalid
          ? tokens.dangerContainer.withOpacity(.12)
          : working
              ? tokens.accentContainer.withOpacity(.05)
              : Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  day,
                  style: textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration:
                      _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  switchInCurve: CommonUiMotion.enter,
                  switchOutCurve: CommonUiMotion.exit,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(.03, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    status,
                    key: ValueKey<String>(status),
                    style: textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTime(day: day, isStart: true),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: Text('출근 ${_formatTime(start)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTime(day: day, isStart: false),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: Text('퇴근 ${_formatTime(end)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  value: holiday,
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
                  onChanged:
                      working ? (value) => _toggleBreak(day, value ?? false) : null,
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

  Widget _scheduleEditor(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Column(
      children: [
        for (var index = 0; index < _days.length; index++) ...[
          _scheduleDay(context, _days[index]),
          if (index != _days.length - 1)
            Container(height: 1, color: tokens.borderSubtle),
        ],
        AnimatedSize(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.enter,
          child: _inlineError(context, _submitted ? _scheduleError : null),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    switch (widget.section) {
      case UserSettingsSection.identity:
        return _identityEditor(context);
      case UserSettingsSection.permission:
        return _permissionEditor(context);
      case UserSettingsSection.position:
        return _positionEditor(context);
      case UserSettingsSection.password:
        return _passwordEditor(context);
      case UserSettingsSection.schedule:
        return _scheduleEditor(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
            child: Row(
              children: [
                Icon(_icon, size: 20, color: tokens.accent),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _title,
                    style: textTheme.titleSmall?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (widget.trace.developerMode)
                  IconButton(
                    tooltip: '개발자 로그',
                    onPressed: _showDeveloperTrace,
                    icon: Icon(
                      Icons.bug_report_rounded,
                      size: 19,
                      color: tokens.warning,
                    ),
                  ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: _cancel,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Container(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: _body(context),
            ),
          ),
          Container(height: 1, color: tokens.borderSubtle),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: CommonButton(
                    label: '취소',
                    icon: Icons.close_rounded,
                    onPressed: _cancel,
                    variant: CommonButtonVariant.secondary,
                    haptic: CommonHaptic.selection,
                    minHeight: 42,
                    expand: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CommonButton(
                    label: '적용',
                    icon: Icons.check_rounded,
                    onPressed: _apply,
                    variant: CommonButtonVariant.primary,
                    haptic: CommonHaptic.selection,
                    minHeight: 42,
                    expand: true,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
