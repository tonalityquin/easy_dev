import 'dart:math';

import 'package:flutter/material.dart';

import '../../../domain/models/user/user_model.dart';
import '../sheets/widgets/user_input_section.dart';
import '../sheets/widgets/user_password_display_section.dart';
import '../sheets/widgets/user_role_dropdown_section.dart';
import '../sheets/widgets/user_role_type_section.dart';
import '../sheets/widgets/user_validation_helpers_section.dart';

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

  static const int _panelBasic = 0;
  static const int _panelRole = 1;
  static const int _panelPosition = 2;
  static const int _panelPassword = 3;
  static const int _panelTime = 4;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _positionController = TextEditingController();

  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _positionFocus = FocusNode();

  final ScrollController _scrollController = ScrollController();

  final GlobalKey _keyBasic = GlobalKey();
  final GlobalKey _keyRole = GlobalKey();
  final GlobalKey _keyPosition = GlobalKey();
  final GlobalKey _keyPassword = GlobalKey();
  final GlobalKey _keyTime = GlobalKey();

  late final List<bool> _expanded;

  RoleType _selectedRole = RoleType.fieldCommon;
  final Set<String> _selectedModes = <String>{};
  Map<String, TimeOfDay?> _startByDay = <String, TimeOfDay?>{};
  Map<String, TimeOfDay?> _endByDay = <String, TimeOfDay?>{};
  String? _errorMessage;

  bool get isEditMode => widget.isEditMode;

  @override
  void initState() {
    super.initState();
    _expanded = List<bool>.filled(5, false);
    _expanded[_panelBasic] = true;
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
      _startByDay = _normalizeWeekMap(
        user.startTimeByWeekday,
        fallback: user.startTime,
        excludedDays: excludedDays,
      );
      _endByDay = _normalizeWeekMap(
        user.endTimeByWeekday,
        fallback: user.endTime,
        excludedDays: excludedDays,
      );
    } else {
      _passwordController.text = _generateRandomPassword();
    }

    if (_selectedModes.isEmpty) {
      _selectedModes.add('single');
    }

    _nameFocus.addListener(() {
      if (_nameFocus.hasFocus) {
        _openPanelAndScroll(_panelBasic);
      }
    });
    _phoneFocus.addListener(() {
      if (_phoneFocus.hasFocus) {
        _openPanelAndScroll(_panelBasic);
      }
    });
    _emailFocus.addListener(() {
      if (_emailFocus.hasFocus) {
        _openPanelAndScroll(_panelBasic);
      }
    });
    _positionFocus.addListener(() {
      if (_positionFocus.hasFocus) {
        _openPanelAndScroll(_panelPosition);
      }
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

  void _setErrorMessage(String? message) {
    setState(() => _errorMessage = message);
  }

  void _clearErrorIfAny() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  bool _validateInputs() {
    final error = validateInputs(<String, String>{
      '이름': _nameController.text,
      '전화번호': _phoneController.text,
      '이메일': _emailController.text,
    });
    _setErrorMessage(error);
    return error == null;
  }

  bool _isValidEmailLocalPart(String input) {
    return RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(input.trim());
  }

  String _generateRandomPassword() {
    final random = Random();
    return (10000 + random.nextInt(90000)).toString();
  }

  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  bool _validateWeeklyTimes() {
    bool hasWorkingDay = false;

    for (final day in _days) {
      final start = _startByDay[day];
      final end = _endByDay[day];
      final hasStart = start != null;
      final hasEnd = end != null;

      if (hasStart != hasEnd) {
        _setErrorMessage('$day 요일의 출근/퇴근 시간을 모두 입력하세요');
        return false;
      }

      if (hasStart && hasEnd) {
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

  Future<void> _pickWeeklyTime({
    required String day,
    required bool isStart,
  }) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final current = isStart ? _startByDay[day] : _endByDay[day];
    final initial = current ?? (isStart ? const TimeOfDay(hour: 9, minute: 0) : const TimeOfDay(hour: 18, minute: 0));

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? '$day 출근 시간' : '$day 퇴근 시간',
      confirmText: '확인',
      cancelText: '취소',
      builder: (ctx, child) {
        final mq = MediaQuery.of(ctx);
        final branded = theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(
            primary: cs.primary,
            secondary: cs.primaryContainer,
            surface: cs.surface,
            onSurface: cs.onSurface,
          ),
        );
        return MediaQuery(
          data: mq.copyWith(alwaysUse24HourFormat: true),
          child: Theme(data: branded, child: child!),
        );
      },
    );

    if (picked == null || !mounted) {
      return;
    }

    _clearErrorIfAny();
    setState(() {
      if (isStart) {
        _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = picked;
      } else {
        _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = picked;
      }
    });
  }

  void _clearWeeklyTime(String day) {
    _clearErrorIfAny();
    setState(() {
      _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = null;
      _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = null;
    });
  }

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

  bool get _isBasicInfoComplete {
    final nameOk = _nameController.text.trim().isNotEmpty;
    final phoneOk = RegExp(r'^\d{9,}$').hasMatch(_phoneController.text.trim());
    final emailOk = _emailController.text.trim().isNotEmpty;
    return nameOk && phoneOk && emailOk;
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

  String get _modesSummary {
    if (_selectedModes.isEmpty) return '모드 미선택';
    return _selectedModes.map(_modeLabel).join(', ');
  }

  String get _roleSummary => '${_selectedRole.label} · $_modesSummary';

  String get _positionSummary {
    final position = _positionController.text.trim();
    return position.isEmpty ? '직책(선택)' : position;
  }

  int get _workingDayCount {
    var count = 0;
    for (final day in _days) {
      if (_startByDay[day] != null && _endByDay[day] != null) {
        count += 1;
      }
    }
    return count;
  }

  String get _timeSummary {
    if (_workingDayCount == 0) {
      return '근무시간 미설정';
    }
    final parts = <String>[];
    for (final day in _days) {
      final start = _startByDay[day];
      final end = _endByDay[day];
      if (start != null && end != null) {
        parts.add('$day ${_formatTimeOfDay(start)}~${_formatTimeOfDay(end)}');
      }
    }
    if (parts.length <= 2) {
      return parts.join(' · ');
    }
    return '${parts.take(2).join(' · ')} 외 ${parts.length - 2}일';
  }

  void _openPanelAndScroll(int panelIndex) {
    if (!mounted) return;

    setState(() {
      for (var i = 0; i < _expanded.length; i++) {
        _expanded[i] = i == panelIndex;
      }
    });

    final key = switch (panelIndex) {
      _panelBasic => _keyBasic,
      _panelRole => _keyRole,
      _panelPosition => _keyPosition,
      _panelPassword => _keyPassword,
      _panelTime => _keyTime,
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

  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ?? const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)).copyWith(
      color: cs.onSurfaceVariant.withOpacity(.72),
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

  Widget _buildPanelHeader({
    required ColorScheme cs,
    required int step,
    required String title,
    required String summary,
    required bool isDone,
    required bool isExpanded,
  }) {
    final base = cs.primary;
    final dark = cs.onSurface;
    final container = cs.primaryContainer;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isExpanded ? base.withOpacity(.12) : container.withOpacity(.30),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isExpanded ? base.withOpacity(.35) : cs.outlineVariant.withOpacity(.65),
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
          color: cs.onSurfaceVariant.withOpacity(.78),
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
    required ColorScheme cs,
    required Widget child,
    int? nextPanel,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          child,
          if (nextPanel != null) ...<Widget>[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openPanelAndScroll(nextPanel),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('다음 단계로 이동'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurface,
                side: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
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

  Widget _buildModesSelector({required ColorScheme cs}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '허용 모드(필수)',
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '선택된 모드에 포함된 로그인 화면에서만 로그인할 수 있습니다.',
            style: TextStyle(
              color: cs.onSurfaceVariant.withOpacity(.78),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableModes.map((mode) {
              final selected = _selectedModes.contains(mode);
              return FilterChip(
                label: Text(_modeLabel(mode)),
                selected: selected,
                selectedColor: cs.primaryContainer.withOpacity(.65),
                checkmarkColor: cs.onPrimaryContainer,
                side: BorderSide(
                  color: selected ? cs.primary.withOpacity(.35) : cs.outlineVariant.withOpacity(.65),
                ),
                onSelected: (value) {
                  _clearErrorIfAny();
                  setState(() {
                    if (value) {
                      _selectedModes.add(mode);
                    } else {
                      _selectedModes.remove(mode);
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

  Widget _buildWeeklyTimeSection({required ThemeData theme, required ColorScheme cs}) {
    Widget dayRow(String day) {
      final start = _startByDay[day];
      final end = _endByDay[day];
      final isWorking = start != null && end != null;
      final hasPartial = (start == null) != (end == null);

      final borderColor = hasPartial
          ? cs.error.withOpacity(.35)
          : (isWorking ? cs.primary.withOpacity(.25) : cs.outlineVariant.withOpacity(.75));
      final backgroundColor = isWorking ? cs.primaryContainer.withOpacity(.12) : cs.surfaceContainerLow;

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outlineVariant.withOpacity(.75)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    day,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isWorking ? '${_formatTimeOfDay(start)} ~ ${_formatTimeOfDay(end)}' : '휴무',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                if (isWorking || hasPartial)
                  TextButton.icon(
                    onPressed: () => _clearWeeklyTime(day),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('비우기'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickWeeklyTime(day: day, isStart: true),
                    icon: const Icon(Icons.login),
                    label: Text('출근 ${_formatTimeOfDay(start)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickWeeklyTime(day: day, isStart: false),
                    icon: const Icon(Icons.logout),
                    label: Text('퇴근 ${_formatTimeOfDay(end)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '시간이 비어 있으면 휴무로 처리됩니다.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant.withOpacity(.78),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '요일별 근무 시간',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '휴일 선택은 따로 하지 않습니다. 시간을 입력한 요일만 근무일로 저장됩니다.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant.withOpacity(.82),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        for (final day in _days) dayRow(day),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: <Widget>[
          SafeArea(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                isEditMode ? '유저 수정' : '유저 생성',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${widget.division} · ${widget.areaValue}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant.withOpacity(.82),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '닫기',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: ExpansionPanelList(
                          elevation: 0,
                          expandedHeaderPadding: EdgeInsets.zero,
                          expansionCallback: (index, isExpanded) {
                            setState(() {
                              for (var i = 0; i < _expanded.length; i++) {
                                _expanded[i] = i == index ? !isExpanded : false;
                              }
                            });
                          },
                          children: <ExpansionPanel>[
                            ExpansionPanel(
                              canTapOnHeader: true,
                              isExpanded: _expanded[_panelBasic],
                              headerBuilder: (ctx, _) => KeyedSubtree(
                                key: _keyBasic,
                                child: _buildPanelHeader(
                                  cs: cs,
                                  step: 1,
                                  title: '기본 정보',
                                  summary: _basicSummary,
                                  isDone: _isBasicInfoComplete,
                                  isExpanded: _expanded[_panelBasic],
                                ),
                              ),
                              body: _buildPanelBody(
                                cs: cs,
                                nextPanel: _panelRole,
                                child: UserInputSection(
                                  nameController: _nameController,
                                  phoneController: _phoneController,
                                  emailController: _emailController,
                                  nameFocus: _nameFocus,
                                  phoneFocus: _phoneFocus,
                                  emailFocus: _emailFocus,
                                  errorMessage: _errorMessage,
                                  lockNameAndPhone: isEditMode,
                                  emailLocalPartValidator: _isValidEmailLocalPart,
                                  onEdited: _clearErrorIfAny,
                                ),
                              ),
                            ),
                            ExpansionPanel(
                              canTapOnHeader: true,
                              isExpanded: _expanded[_panelRole],
                              headerBuilder: (ctx, _) => KeyedSubtree(
                                key: _keyRole,
                                child: _buildPanelHeader(
                                  cs: cs,
                                  step: 2,
                                  title: '권한 및 허용 모드',
                                  summary: _roleSummary,
                                  isDone: _selectedModes.isNotEmpty,
                                  isExpanded: _expanded[_panelRole],
                                ),
                              ),
                              body: _buildPanelBody(
                                cs: cs,
                                nextPanel: _panelPosition,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    UserRoleDropdownSection(
                                      selectedRole: _selectedRole,
                                      onChanged: (role) {
                                        _clearErrorIfAny();
                                        setState(() => _selectedRole = role);
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    _buildModesSelector(cs: cs),
                                  ],
                                ),
                              ),
                            ),
                            ExpansionPanel(
                              canTapOnHeader: true,
                              isExpanded: _expanded[_panelPosition],
                              headerBuilder: (ctx, _) => KeyedSubtree(
                                key: _keyPosition,
                                child: _buildPanelHeader(
                                  cs: cs,
                                  step: 3,
                                  title: '직책',
                                  summary: _positionSummary,
                                  isDone: _positionController.text.trim().isNotEmpty,
                                  isExpanded: _expanded[_panelPosition],
                                ),
                              ),
                              body: _buildPanelBody(
                                cs: cs,
                                nextPanel: _panelPassword,
                                child: TextField(
                                  controller: _positionController,
                                  focusNode: _positionFocus,
                                  textInputAction: TextInputAction.done,
                                  onChanged: (_) => _clearErrorIfAny(),
                                  decoration: InputDecoration(
                                    labelText: '직책(선택)',
                                    helperText: '예: 매니저, 총괄, 팀장',
                                    filled: true,
                                    fillColor: cs.surfaceVariant.withOpacity(.45),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: cs.primary, width: 1.3),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            ExpansionPanel(
                              canTapOnHeader: true,
                              isExpanded: _expanded[_panelPassword],
                              headerBuilder: (ctx, _) => KeyedSubtree(
                                key: _keyPassword,
                                child: _buildPanelHeader(
                                  cs: cs,
                                  step: 4,
                                  title: '비밀번호',
                                  summary: '자동 생성 / 복사 가능',
                                  isDone: _passwordController.text.trim().isNotEmpty,
                                  isExpanded: _expanded[_panelPassword],
                                ),
                              ),
                              body: _buildPanelBody(
                                cs: cs,
                                nextPanel: _panelTime,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    UserPasswordDisplaySection(
                                      controller: _passwordController,
                                      enableMonospace: true,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '비밀번호는 읽기 전용입니다. 복사 버튼으로 전달하세요.',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant.withOpacity(.78),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            ExpansionPanel(
                              canTapOnHeader: true,
                              isExpanded: _expanded[_panelTime],
                              headerBuilder: (ctx, _) => KeyedSubtree(
                                key: _keyTime,
                                child: _buildPanelHeader(
                                  cs: cs,
                                  step: 5,
                                  title: '요일별 근무 시간',
                                  summary: _timeSummary,
                                  isDone: _workingDayCount > 0,
                                  isExpanded: _expanded[_panelTime],
                                ),
                              ),
                              body: _buildPanelBody(
                                cs: cs,
                                child: _buildWeeklyTimeSection(theme: theme, cs: cs),
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
                          color: cs.errorContainer.withOpacity(.55),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.error.withOpacity(.35)),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: cs.onErrorContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: cs.onSurface,
                              side: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('취소'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
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

                              if (_selectedModes.isEmpty) {
                                _setErrorMessage('허용 모드를 1개 이상 선택하세요');
                                _openPanelAndScroll(_panelRole);
                                return;
                              }

                              if (!_validateWeeklyTimes()) {
                                _openPanelAndScroll(_panelTime);
                                return;
                              }

                              final fullEmail = '${_emailController.text.trim()}@gmail.com';
                              final normalizedModes = _normalizeAndFilterModes(_selectedModes);
                              if (normalizedModes.isEmpty) {
                                _setErrorMessage('허용 모드를 1개 이상 선택하세요');
                                _openPanelAndScroll(_panelRole);
                                return;
                              }

                              widget.onSave(
                                _nameController.text.trim(),
                                _phoneController.text.trim(),
                                fullEmail,
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
                                _positionController.text.trim(),
                              );

                              if (mounted) {
                                Navigator.pop(context);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
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
