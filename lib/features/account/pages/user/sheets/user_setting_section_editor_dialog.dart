import 'package:flutter/material.dart';
import '../../../presentation/widgets/permission_detail_list.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../applications/user_state.dart';
import '../../../domain/models/account_permission_policy.dart';
import '../../../data/services/company_grade_policy_service.dart';

import '../../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../../app/utils/snackbar_helper.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../../shared/auth/account_code_number.dart';
import '../../../../../shared/secondary/application/secondary_account_workspace_state.dart';
import '../../../../../shared/secondary/widgets/ops_console_widgets.dart';
import 'models/user_settings_draft.dart';

class UserSettingSectionEditorDialog extends StatefulWidget {
  const UserSettingSectionEditorDialog({
    super.key,
    required this.section,
    required this.companyId,
    required this.initialDraft,
    required this.isEditMode,
    required this.manualCodeAllowed,
    required this.onRequestManualCodeEntry,
    required this.trace,
    required this.onApply,
  });

  final UserSettingsSection section;
  final String companyId;
  final UserSettingsDraft initialDraft;
  final bool isEditMode;
  final bool manualCodeAllowed;
  final Future<bool> Function() onRequestManualCodeEntry;
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
  late final TextEditingController _codeNumberController;
  late final TextEditingController _emailController;
  late final TextEditingController _positionController;
  late Set<String> _permissionKeys;
  final CompanyGradePolicyService _gradeService = CompanyGradePolicyService();
  Map<String, CompanyGradePolicy> _gradePolicies = <String, CompanyGradePolicy>{};
  bool _gradeLoading = false;
  String? _gradeError;
  late String _accountGradeId;
  late UserCodeEntryMode _codeEntryMode;
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
    _codeEntryMode = draft.codeEntryMode;
    _codeNumberController = TextEditingController(
      text: draft.codeEntryMode == UserCodeEntryMode.developerManual
          ? draft.codeNumber
          : AccountCodeNumber.format(draft.codeNumber),
    );
    _emailController = TextEditingController(text: draft.emailLocal);
    _positionController = TextEditingController(text: draft.position);
    _permissionKeys = AccountPermissionPolicy.sanitize(draft.permissionKeys);
    _accountGradeId = draft.accountGradeId;
    _modes = Set<String>.of(draft.modes);
    _startByDay = Map<String, TimeOfDay?>.of(draft.startByDay);
    _endByDay = Map<String, TimeOfDay?>.of(draft.endByDay);
    _breakDays = Set<String>.of(draft.breakDays);
    widget.trace.log('편집 화면이 열렸습니다: section=${widget.section.name}');
    if (widget.section == UserSettingsSection.permission &&
        _accountGradeId != 'headquartersAdmin') {
      _loadGradePolicies();
    }
  }

  Future<void> _loadGradePolicies() async {
    setState(() {
      _gradeLoading = true;
      _gradeError = null;
    });
    try {
      final values = await _gradeService.loadAll(widget.companyId);
      if (!mounted) return;
      setState(() {
        _gradePolicies = <String, CompanyGradePolicy>{
          for (final entry in values.entries)
            if (entry.value.enabled) entry.key: entry.value,
        };
        final policy = _gradePolicies[_accountGradeId];
        if (policy != null) {
          _permissionKeys = Set<String>.of(policy.permissionKeys);
        }
        _gradeLoading = false;
      });
    } catch (error, stackTrace) {
      widget.trace.log('등급 정책 조회 실패: company=${widget.companyId} error=$error stack=$stackTrace');
      if (!mounted) return;
      setState(() {
        _gradeLoading = false;
        _gradeError = error.toString();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeNumberController.dispose();
    _emailController.dispose();
    _positionController.dispose();
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
      case UserSettingsSection.schedule:
        return Icons.schedule_rounded;
    }
  }

  bool get _identityOk {
    final name = _nameController.text.trim();
    final codeNumber = _codeNumberController.text.trim();
    final email = _emailController.text.trim();
    final codeNumberOk = widget.isEditMode
        ? AccountCodeNumber.isValid(codeNumber)
        : switch (_codeEntryMode) {
            UserCodeEntryMode.generated =>
              AccountCodeNumber.isGeneratedCode(codeNumber),
            UserCodeEntryMode.developerManual =>
              widget.manualCodeAllowed &&
                  AccountCodeNumber.isDeveloperManualCode(
                    AccountCodeNumber.normalize(codeNumber),
                  ),
          };
    return name.isNotEmpty &&
        codeNumberOk &&
        email.isNotEmpty &&
        _isValidEmailLocalPart(email);
  }

  bool get _permissionOk => _modes.isNotEmpty &&
      (_accountGradeId == 'headquartersAdmin' ||
          (!_gradeLoading && _gradeError == null &&
              (_gradePolicies[_accountGradeId]?.matches(_permissionKeys) ?? false)));

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
          codeNumber: AccountCodeNumber.normalize(_codeNumberController.text),
          codeEntryMode: _codeEntryMode,
          emailLocal: _emailController.text.trim(),
        );
      case UserSettingsSection.permission:
        return base.copyWith(
          accountGradeId: _accountGradeId,
          permissionKeys: _permissionKeys,
          modes: _modes,
        );
      case UserSettingsSection.position:
        return base.copyWith(position: _positionController.text.trim());
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
      '편집 적용: section=${widget.section.name} modes=${result.modes.length} workingDays=$workingDays passwordPolicy=manual_firestore_only',
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
    if (widget.section == UserSettingsSection.schedule) {
      widget.trace.log(
        '휴게 정책 상태: timeIndependent=true breakDays=${_breakDays.length} breakEnabledWithoutScheduledTimes=true',
      );
    }
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '$_title 편집 로그',
      description: '현재 편집 동작의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
    );
  }

  Future<void> _copyCodeNumber() async {
    final codeNumber = AccountCodeNumber.normalize(_codeNumberController.text);
    final copyValue = _codeEntryMode == UserCodeEntryMode.developerManual
        ? codeNumber
        : AccountCodeNumber.format(codeNumber);
    await Clipboard.setData(ClipboardData(text: copyValue));
    widget.trace.log('코드번호 클립보드 복사: code=${AccountCodeNumber.mask(codeNumber)}');
    if (!mounted) return;
    showSelectedSnackbar(
      context,
      '코드번호를 복사했습니다.',
      useCommonUi: true,
    );
  }

  void _regenerateCodeNumber() {
    if (widget.isEditMode ||
        _codeEntryMode != UserCodeEntryMode.generated) {
      return;
    }
    final next = AccountCodeNumber.generate();
    setState(() => _codeNumberController.text = AccountCodeNumber.format(next));
    widget.trace.log('코드번호 재생성: code=${AccountCodeNumber.mask(next)}');
  }

  Future<void> _setCodeEntryMode(UserCodeEntryMode mode) async {
    if (widget.isEditMode || mode == _codeEntryMode) return;
    if (mode == UserCodeEntryMode.developerManual) {
      if (!widget.manualCodeAllowed) {
        widget.trace.log('코드번호 직접 입력 거부: reason=developer_capability_unavailable');
        if (widget.trace.developerMode && mounted) {
          await widget.trace.showSnapshotStatusDialog(
            context,
            title: '코드번호 직접 입력 불가',
            description: '개발자 모드와 개발자 계정 인증 상태를 확인하세요.',
            failure: true,
          );
        }
        return;
      }
      final authorized = await widget.onRequestManualCodeEntry();
      if (!mounted) return;
      if (!authorized) {
        widget.trace.log('코드번호 직접 입력 재인증 실패');
        if (widget.trace.developerMode) {
          await widget.trace.showSnapshotStatusDialog(
            context,
            title: '코드번호 직접 입력 인증 실패',
            description: '개발자 계정 재인증에 실패했습니다.',
            failure: true,
          );
        }
        return;
      }
      setState(() {
        _codeEntryMode = UserCodeEntryMode.developerManual;
        _codeNumberController.clear();
        _submitted = false;
      });
      widget.trace.log('코드번호 직접 입력 모드 활성화: digits=11');
      return;
    }
    final next = AccountCodeNumber.generate();
    setState(() {
      _codeEntryMode = UserCodeEntryMode.generated;
      _codeNumberController.text = AccountCodeNumber.format(next);
      _submitted = false;
    });
    widget.trace.log(
      '코드번호 자동 생성 모드 활성화: code=${AccountCodeNumber.mask(next)}',
    );
  }

  Widget _codeEntryModeSelector(BuildContext context) {
    if (widget.isEditMode || !widget.manualCodeAllowed) {
      return const SizedBox.shrink();
    }
    return AnimatedSize(
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.enter,
      child: Row(
        children: [
          Expanded(
            child: ChoiceChip(
              label: const Text('자동 생성'),
              selected: _codeEntryMode == UserCodeEntryMode.generated,
              onSelected: (_) =>
                  _setCodeEntryMode(UserCodeEntryMode.generated),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ChoiceChip(
              label: const Text('직접 입력'),
              selected:
                  _codeEntryMode == UserCodeEntryMode.developerManual,
              onSelected: (_) =>
                  _setCodeEntryMode(UserCodeEntryMode.developerManual),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeNumberEditor(BuildContext context) {
    final manual = _codeEntryMode == UserCodeEntryMode.developerManual;
    final valid = widget.isEditMode
        ? AccountCodeNumber.isValid(_codeNumberController.text)
        : manual
            ? AccountCodeNumber.isDeveloperManualCode(
                AccountCodeNumber.normalize(_codeNumberController.text),
              )
            : AccountCodeNumber.isGeneratedCode(_codeNumberController.text);
    return AnimatedSwitcher(
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
      switchInCurve: CommonUiMotion.enter,
      switchOutCurve: CommonUiMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .97, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: TextField(
        key: ValueKey<String>('code_entry_${_codeEntryMode.name}_${widget.isEditMode}'),
        controller: _codeNumberController,
        readOnly: widget.isEditMode || !manual,
        enableInteractiveSelection: true,
        keyboardType: manual ? TextInputType.number : null,
        inputFormatters: manual
            ? <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ]
            : null,
        textInputAction: TextInputAction.next,
        onChanged: (_) {
          if (_submitted) setState(() {});
        },
        decoration: opsInputDecoration(
          context,
          label: '코드번호',
          prefixIcon: const Icon(Icons.tag_rounded),
          locked: widget.isEditMode || !manual,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: _copyCodeNumber,
                icon: const Icon(Icons.copy_rounded),
              ),
              if (!widget.isEditMode && !manual)
                IconButton(
                  onPressed: _regenerateCodeNumber,
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
          errorText: _submitted && !valid
              ? manual
                  ? '코드번호는 숫자 11자리로 입력하세요.'
                  : '코드번호를 다시 생성하세요.'
              : null,
        ),
      ),
    );
  }

  Future<void> _pickTime({required String day, required bool isStart}) async {
    final current = isStart ? _startByDay[day] : _endByDay[day];
    final initial = current ??
        (isStart
            ? const TimeOfDay(hour: 9, minute: 0)
            : const TimeOfDay(hour: 18, minute: 0));
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
    });
    widget.trace.log('근무 시간 변경: day=$day field=${isStart ? 'start' : 'end'}');
  }

  void _setHoliday(String day, bool value) {
    setState(() {
      if (value) {
        _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = null;
        _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = null;
      } else {
        _startByDay = Map<String, TimeOfDay?>.of(_startByDay)
          ..[day] = _startByDay[day] ?? const TimeOfDay(hour: 9, minute: 0);
        _endByDay = Map<String, TimeOfDay?>.of(_endByDay)
          ..[day] = _endByDay[day] ?? const TimeOfDay(hour: 18, minute: 0);
      }
    });
    widget.trace.log('휴무 상태 변경: day=$day holiday=$value');
  }

  void _toggleBreak(String day, bool value) {
    setState(() {
      _breakDays = <String>{..._breakDays};
      if (value) {
        _breakDays.add(day);
      } else {
        _breakDays.remove(day);
      }
    });
    widget.trace.log('휴게 상태 변경: day=$day break=$value timeIndependent=true');
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
        _codeEntryModeSelector(context),
        if (!widget.isEditMode && widget.manualCodeAllowed)
          const SizedBox(height: 10),
        _codeNumberEditor(context),
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
    final actor = context.read<UserState>();
    final selectedPreset = _accountGradeId;
    final selectedLabel = selectedPreset == 'headquartersAdmin'
        ? AccountPermissionPolicy.gradeLabel(selectedPreset)
        : _gradePolicies[selectedPreset]?.name;
    final permissionSignature = (_permissionKeys.toList()..sort()).join('|');
    final editable = actor.hasPermission('accounts.grantPermissions');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('계정 등급', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        AnimatedSize(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.enter,
          alignment: Alignment.topLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _gradePolicies.entries.map((entry) {
              final selected = selectedPreset == entry.key;
              final canApply = editable && !_gradeLoading &&
                  selectedPreset != 'headquartersAdmin' &&
                  AccountPermissionPolicy.mayGrant(actor.permissionKeys, entry.value.permissionKeys);
              return OpsFormChip(
                label: entry.value.name,
                selected: selected,
                icon: selected ? Icons.check_circle_rounded : Icons.shield_outlined,
                onTap: () {
                  if (!canApply) {
                    widget.trace.log('계정 등급 선택 거부: preset=${entry.key}');
                    return;
                  }
                  setState(() {
                    _accountGradeId = entry.key;
                    _permissionKeys = Set<String>.of(entry.value.permissionKeys);
                  });
                  widget.trace.log('계정 등급 선택: preset=${entry.key} count=${entry.value.permissionKeys.length}');
                },
              );
            }).toList(growable: false),
          ),
        ),
        if (_gradeLoading) const LinearProgressIndicator(),
        if (_gradeError != null) Text('등급 정책 조회 실패: $_gradeError'),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          switchInCurve: CommonUiMotion.enter,
          switchOutCurve: CommonUiMotion.exit,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(sizeFactor: animation, child: child),
          ),
          child: Column(
            key: ValueKey<String>('$selectedPreset:$permissionSignature'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selectedLabel == null
                    ? '등록되지 않은 계정 등급 · ${_permissionKeys.length}개 권한'
                    : '$selectedLabel · ${_permissionKeys.length}개 권한',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              PermissionDetailList(
                permissions: (selectedPreset == 'headquartersAdmin'
                    ? AccountPermissionPolicy.keys
                    : AccountPermissionPolicy.generalPermissionKeys).toList()..sort(),
                selected: _permissionKeys,
                enabled: false,
                height: 288,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('허용 모드', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableModes.map((mode) {
            final selected = _modes.contains(mode);
            return OpsFormChip(
              label: AccountPermissionPolicy.modeLabel(mode),
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

  Widget _scheduleDay(BuildContext context, String day) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final start = _startByDay[day];
    final end = _endByDay[day];
    final working = start != null && end != null;
    final holiday = start == null && end == null;
    final hasBreak = _breakDays.contains(day);
    final partial = (start == null) != (end == null);
    final invalidRange =
        start != null && end != null && _toMinutes(start) > _toMinutes(end);
    final invalid = partial || invalidRange;
    final status = invalid
        ? '시간 확인 필요'
        : working
            ? '${_formatTime(start)} ~ ${_formatTime(end)} · ${hasBreak ? '휴게 있음' : '휴게 없음'}'
            : '휴무 · ${hasBreak ? '휴게 있음' : '휴게 없음'}';
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
                  onChanged: (value) => _toggleBreak(day, value ?? false),
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
