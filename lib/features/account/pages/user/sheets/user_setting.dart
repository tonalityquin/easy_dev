import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../../app/utils/snackbar_helper.dart';
import '../../../../../app/utils/status_dialog.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_origin_morph_dialog.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../../shared/auth/five_digit_password_generator.dart';
import '../../../../../shared/secondary/application/secondary_account_workspace_state.dart';
import '../../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../../dev/application/area_state.dart';
import '../../../applications/user_state.dart';
import '../../../domain/models/user/user_model.dart';
import '../../../domain/repositories/user_repository.dart';
import 'models/user_settings_draft.dart';
import 'user_setting_section_editor_dialog.dart';
import 'widgets/user_role_type_section.dart';

class UserSettingWorkspace extends StatefulWidget {
  const UserSettingWorkspace({
    super.key,
    required this.initialUser,
  });

  final UserModel? initialUser;

  @override
  State<UserSettingWorkspace> createState() => _UserSettingWorkspaceState();
}

class _UserSettingWorkspaceState extends State<UserSettingWorkspace> {
  static const List<String> _days = <String>['월', '화', '수', '목', '금', '토', '일'];
  static const List<String> _availableModes = <String>['single', 'double', 'triple', 'minor'];
  static const Map<String, String> _modeLabels = <String, String>{
    'single': 'single',
    'double': 'double',
    'triple': 'triple',
    'minor': 'minor',
  };

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _positionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _scrollViewportKey = GlobalKey();
  final Map<UserSettingsSection, GlobalKey> _sectionKeys =
      <UserSettingsSection, GlobalKey>{
    for (final section in UserSettingsSection.values) section: GlobalKey(),
  };

  RoleType _selectedRole = RoleType.fieldCommon;
  final Set<String> _selectedModes = <String>{};
  Map<String, TimeOfDay?> _startByDay = <String, TimeOfDay?>{};
  Map<String, TimeOfDay?> _endByDay = <String, TimeOfDay?>{};
  Set<String> _breakDays = <String>{};
  String? _saveError;
  bool _saving = false;
  bool _validationSubmitted = false;
  bool _reduceMotion = false;
  int _handledNavigationRequestId = -1;
  UserSettingsSection? _pendingVisibleSection;
  UserSettingsSection? _editingSection;
  bool _visibleSectionScheduled = false;
  SecondaryAccountWorkspaceState? _workspace;

  bool get isEditMode => widget.initialUser != null;

  @override
  void initState() {
    super.initState();
    _startByDay = <String, TimeOfDay?>{
      for (final day in _days) day: null,
    };
    _endByDay = <String, TimeOfDay?>{
      for (final day in _days) day: null,
    };
    _populateInitialValues();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSectionStates(source: 'initial_form_state');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _workspace ??= context.read<SecondaryAccountWorkspaceState>();
  }

  @override
  void didUpdateWidget(covariant UserSettingWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialUser?.id == widget.initialUser?.id) return;
    _populateInitialValues();
    _validationSubmitted = false;
    _saveError = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSectionStates(source: 'editing_target_changed');
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _positionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _populateInitialValues() {
    final user = widget.initialUser;
    if (user == null) {
      _nameController.clear();
      _phoneController.clear();
      _emailController.clear();
      _positionController.clear();
      _passwordController.text = FiveDigitPasswordGenerator.generate();
      _selectedRole = RoleType.fieldCommon;
      _selectedModes
        ..clear()
        ..add('single');
      _startByDay = <String, TimeOfDay?>{
        for (final day in _days) day: null,
      };
      _endByDay = <String, TimeOfDay?>{
        for (final day in _days) day: null,
      };
      _breakDays = <String>{};
      return;
    }
    _nameController.text = user.name;
    _phoneController.text = user.phone;
    _emailController.text = user.email.split('@').first;
    _passwordController.text = user.password;
    _positionController.text = user.position ?? '';
    _selectedRole = RoleType.values.firstWhere(
      (role) => role.name == user.role,
      orElse: () => RoleType.fieldCommon,
    );
    _selectedModes
      ..clear()
      ..addAll(_normalizeAndFilterModes(user.modes));
    if (_selectedModes.isEmpty) {
      _selectedModes.add('single');
    }
    _startByDay = _normalizeWeekMap(user.startTimeByWeekday);
    _endByDay = _normalizeWeekMap(user.endTimeByWeekday);
    _breakDays = _normalizeDaySet(user.breakDays).intersection(_workingDaySet());
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
    return raw
        .map((value) => value.trim())
        .where((value) => _days.contains(value))
        .toSet();
  }

  Map<String, TimeOfDay?> _normalizeWeekMap(Map<String, TimeOfDay?> raw) {
    return <String, TimeOfDay?>{
      for (final day in _days) day: raw[day],
    };
  }

  String _modeLabel(String mode) => _modeLabels[mode] ?? mode;

  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  Set<String> _workingDaySet() {
    final out = <String>{};
    for (final day in _days) {
      if (_startByDay[day] != null && _endByDay[day] != null) {
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

  bool _isValidEmailLocalPart(String input) {
    return RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(input.trim());
  }

  bool get _nameOk => _nameController.text.trim().isNotEmpty;
  bool get _phoneOk =>
      RegExp(r'^\d{9,}$').hasMatch(_phoneController.text.trim());
  bool get _emailOk => _emailController.text.trim().isNotEmpty &&
      _isValidEmailLocalPart(_emailController.text);
  bool get _identityOk => _nameOk && _phoneOk && _emailOk;
  bool get _permissionOk => _selectedModes.isNotEmpty;
  bool get _passwordOk => RegExp(r'^\d{5}$').hasMatch(_passwordController.text);

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

  UserSettingsSectionState _sectionState(UserSettingsSection section) {
    switch (section) {
      case UserSettingsSection.identity:
        if (_identityOk) return UserSettingsSectionState.complete;
        return _validationSubmitted
            ? UserSettingsSectionState.error
            : UserSettingsSectionState.incomplete;
      case UserSettingsSection.permission:
        if (_permissionOk) return UserSettingsSectionState.complete;
        return _validationSubmitted
            ? UserSettingsSectionState.error
            : UserSettingsSectionState.incomplete;
      case UserSettingsSection.position:
        return _positionController.text.trim().isEmpty
            ? UserSettingsSectionState.optional
            : UserSettingsSectionState.complete;
      case UserSettingsSection.password:
        if (_passwordOk) return UserSettingsSectionState.complete;
        return UserSettingsSectionState.error;
      case UserSettingsSection.schedule:
        if (_scheduleOk) return UserSettingsSectionState.complete;
        return UserSettingsSectionState.error;
    }
  }

  Map<UserSettingsSection, UserSettingsSectionState> _allSectionStates() {
    return <UserSettingsSection, UserSettingsSectionState>{
      for (final section in UserSettingsSection.values)
        section: _sectionState(section),
    };
  }

  void _syncSectionStates({required String source}) {
    final workspace = _workspace;
    if (workspace == null) return;
    workspace.updateSectionStates(_allSectionStates(), source: source);
  }

  void _markDirty(UserSettingsSection section, {required String source}) {
    final workspace = _workspace;
    workspace?.setSettingsDirty(true, source: source);
    if (_saveError != null) {
      setState(() => _saveError = null);
    }
    _syncSectionStates(source: source);
    workspace?.log('settings_input_changed section=${section.name} source=$source');
  }

  UserSettingsDraft _currentDraft() {
    return UserSettingsDraft(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      emailLocal: _emailController.text.trim(),
      position: _positionController.text.trim(),
      password: _passwordController.text.trim(),
      role: _selectedRole,
      modes: Set<String>.of(_selectedModes),
      startByDay: Map<String, TimeOfDay?>.of(_startByDay),
      endByDay: Map<String, TimeOfDay?>.of(_endByDay),
      breakDays: Set<String>.of(_breakDays),
    );
  }

  void _applyEditorDraft(
    UserSettingsSection section,
    UserSettingsDraft draft,
  ) {
    if (!mounted || _saving) return;
    setState(() {
      switch (section) {
        case UserSettingsSection.identity:
          _nameController.text = draft.name;
          _phoneController.text = draft.phone;
          _emailController.text = draft.emailLocal;
          break;
        case UserSettingsSection.permission:
          _selectedRole = draft.role;
          _selectedModes
            ..clear()
            ..addAll(_normalizeAndFilterModes(draft.modes));
          break;
        case UserSettingsSection.position:
          _positionController.text = draft.position;
          break;
        case UserSettingsSection.password:
          _passwordController.text = draft.password;
          break;
        case UserSettingsSection.schedule:
          _startByDay = _normalizeWeekMap(draft.startByDay);
          _endByDay = _normalizeWeekMap(draft.endByDay);
          _breakDays = _normalizeDaySet(draft.breakDays).intersection(_workingDaySet());
          break;
      }
      _saveError = null;
    });
    _markDirty(section, source: 'editor_apply');
    final workingDays = _workingDaySet().length;
    _workspace?.log(
      'settings_editor_applied section=${section.name} modes=${_selectedModes.length} workingDays=$workingDays passwordLength=${_passwordController.text.trim().length}',
    );
  }

  Rect? _sectionRect(UserSettingsSection section) {
    final sectionContext = _sectionKeys[section]?.currentContext;
    final box = sectionContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  Size _editorTargetSize(UserSettingsSection section) {
    switch (section) {
      case UserSettingsSection.identity:
        return const Size(520, 470);
      case UserSettingsSection.permission:
        return const Size(540, 460);
      case UserSettingsSection.position:
        return const Size(460, 310);
      case UserSettingsSection.password:
        return const Size(480, 370);
      case UserSettingsSection.schedule:
        return const Size(620, 720);
    }
  }

  String _sectionTitle(UserSettingsSection section) {
    switch (section) {
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

  Future<void> _openSectionEditor(
    UserSettingsSection section, {
    bool ensureVisible = true,
  }) async {
    if (_saving || _editingSection != null) return;
    setState(() => _editingSection = section);
    _workspace?.selectSettingsSection(section, source: 'settings_row_tap');
    try {
      if (ensureVisible) {
        await _scrollToSection(section);
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final sourceRect = _sectionRect(section);
      if (sourceRect == null) {
        _workspace?.log(
          'settings_editor_open_failed section=${section.name} reason=no_source_rect',
        );
        return;
      }
      _workspace?.log(
        'settings_editor_open_requested section=${section.name} width=${sourceRect.width.toStringAsFixed(1)} height=${sourceRect.height.toStringAsFixed(1)}',
      );
      final trace = await DeveloperOperationTrace.start(
        context: context,
        title: '${_sectionTitle(section)} 편집',
        initialMessage: '계정 설정 편집을 시작합니다: section=${section.name}',
        useCommonUi: true,
        developerModeMessage:
            '개발자 모드 ON: 편집 Dialog의 버그 아이콘에서 debugPrint 코드를 복사할 수 있습니다.',
        standardModeMessage: '개발자 모드 OFF: 편집 동작을 콘솔에 기록합니다.',
        showDialogImmediately: false,
      );
      if (!mounted) return;
      trace.log(
        '원본 row bounds 확보: width=${sourceRect.width.toStringAsFixed(1)}, height=${sourceRect.height.toStringAsFixed(1)}',
      );
      final applied = await showCommonOriginMorphDialog<bool>(
        context: context,
        sourceRect: sourceRect,
        targetSize: _editorTargetSize(section),
        barrierDismissible: false,
        barrierLabel: '${_sectionTitle(section)} 편집',
        builder: (dialogContext) {
          return UserSettingSectionEditorDialog(
            section: section,
            initialDraft: _currentDraft().detached(),
            isEditMode: isEditMode,
            trace: trace,
            onApply: (draft) => _applyEditorDraft(section, draft),
          );
        },
      );
      trace.log(
        '편집 Dialog 종료: section=${section.name} applied=${applied == true}',
      );
      _workspace?.log(
        'settings_editor_closed section=${section.name} applied=${applied == true}',
      );
    } finally {
      if (mounted && _editingSection == section) {
        setState(() => _editingSection = null);
      }
    }
  }

  Future<void> _scrollToSection(UserSettingsSection section) async {
    final sectionContext = _sectionKeys[section]?.currentContext;
    if (sectionContext == null) return;
    _workspace?.log('settings_scroll_requested section=${section.name}');
    await Scrollable.ensureVisible(
      sectionContext,
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.enter,
      alignment: 0.02,
    );
  }

  void _scheduleNavigationRequest(SecondaryAccountWorkspaceState workspace) {
    final requestId = workspace.settingsNavigationRequestId;
    if (requestId == _handledNavigationRequestId) return;
    _handledNavigationRequestId = requestId;
    final target = workspace.activeSettingsSection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_scrollToSection(target));
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification &&
        notification is! UserScrollNotification) {
      return false;
    }
    final viewportContext = _scrollViewportKey.currentContext;
    final viewportBox = viewportContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.attached) return false;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    UserSettingsSection? best;
    double bestDistance = double.infinity;
    for (final section in UserSettingsSection.values) {
      final sectionContext = _sectionKeys[section]?.currentContext;
      final box = sectionContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final distance = (top - viewportTop - 18).abs();
      if (top <= viewportTop + 96) {
        if (distance < bestDistance) {
          best = section;
          bestDistance = distance;
        }
      } else if (best == null && distance < bestDistance) {
        best = section;
        bestDistance = distance;
      }
    }
    if (best == null || best == _workspace?.activeSettingsSection) return false;
    _pendingVisibleSection = best;
    if (_visibleSectionScheduled) return false;
    _visibleSectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleSectionScheduled = false;
      if (!mounted) return;
      final section = _pendingVisibleSection;
      _pendingVisibleSection = null;
      if (section == null) return;
      _workspace?.selectSettingsSection(section, source: 'form_scroll');
    });
    return false;
  }

  UserSettingsSection? _firstInvalidSection() {
    final states = _allSectionStates();
    for (final section in UserSettingsSection.values) {
      final state = states[section];
      if (state == UserSettingsSectionState.error ||
          state == UserSettingsSectionState.incomplete) {
        return section;
      }
    }
    return null;
  }

  String _maskName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '-';
    if (trimmed.length == 1) return '*';
    return '${trimmed.substring(0, 1)}${List<String>.filled(trimmed.length - 1, '*').join()}';
  }

  String _maskPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return '***';
    final tail = digits.substring(digits.length - 4);
    return '${digits.substring(0, digits.length >= 10 ? 3 : 2)}-****-$tail';
  }

  String _friendlySaveError(String message) {
    final limit = RegExp(r'최대\s*(\d+)').firstMatch(message)?.group(1);
    if (message.contains('활성화 제한')) {
      return limit == null
          ? '선택한 지역의 활성 계정 한도에 도달했습니다.'
          : '선택한 지역의 활성 계정은 최대 $limit개까지 사용할 수 있습니다.';
    }
    if (message.contains('전체 계정 제한')) {
      return limit == null
          ? '선택한 지역의 전체 계정 한도에 도달했습니다.'
          : '선택한 지역의 계정은 최대 $limit개까지 등록할 수 있습니다.';
    }
    return message.trim().isEmpty
        ? '계정 정보를 저장하지 못했습니다. 입력 내용을 유지했습니다.'
        : message.trim();
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _validationSubmitted = true;
      _saveError = null;
    });
    _syncSectionStates(source: 'submit_validation');
    final invalidSection = _firstInvalidSection();
    if (invalidSection != null) {
      _workspace?.log('settings_validation_failed section=${invalidSection.name}');
      _workspace?.requestSettingsSection(
        invalidSection,
        source: 'submit_validation_failed',
      );
      await HapticFeedback.mediumImpact();
      await _scrollToSection(invalidSection);
      if (!mounted) return;
      await _openSectionEditor(invalidSection, ensureVisible: false);
      return;
    }

    final workspace = _workspace;
    final areaState = context.read<AreaState>();
    final userState = context.read<UserState>();
    final repository = context.read<UserRepository>();
    final area = areaState.currentArea.trim();
    final division = areaState.currentDivision.trim();
    final selectedArea = area;
    final normalizedModes = _normalizeAndFilterModes(_selectedModes);
    final initialUser = widget.initialUser;
    final operationTitle = isEditMode ? '계정 수정' : '계정 생성';

    setState(() => _saving = true);
    workspace?.setSettingsSaving(true, source: 'submit_started');
    workspace?.log(
      'settings_submit_started mode=${isEditMode ? 'edit' : 'create'} user=${_maskName(_nameController.text)}',
    );

    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: operationTitle,
      initialMessage: '$operationTitle 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 계정 설정 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 계정 설정 로그를 콘솔에 기록합니다.',
    );

    try {
      trace.log(
        '입력값 검증 통과: 사용자 ${_maskName(_nameController.text)}, 전화 ${_maskPhone(_phoneController.text)}, 허용 모드 ${normalizedModes.length}개',
        progress: 0.12,
      );
      final englishName =
          await repository.getEnglishNameByArea(selectedArea, division);
      trace.log(
        '지역 메타데이터 조회 완료: division=$division, area=$selectedArea',
        progress: 0.28,
      );

      final normalizedBreakDays = _normalizedBreakDaysForWorkingDays();
      final workingDays = _workingDaySet().toList(growable: false);
      trace.log(
        '근무 일정 정규화 완료: 근무일 ${workingDays.length}일, 휴게일 ${normalizedBreakDays.length}일',
        progress: 0.42,
      );

      final user = UserModel(
        id: initialUser?.id ?? '${_phoneController.text.trim()}-$area',
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: '${_emailController.text.trim()}@gmail.com',
        role: _selectedRole.name,
        modes: normalizedModes,
        password: _passwordController.text.trim(),
        position: _positionController.text.trim(),
        areas: <String>[area],
        divisions: <String>[division],
        currentArea: area,
        selectedArea: selectedArea,
        englishSelectedAreaName: englishName ?? area,
        isSelected: initialUser?.isSelected ?? false,
        isWorking: false,
        isSaved: false,
        breakDays: normalizedBreakDays,
        startTimeByWeekday: Map<String, TimeOfDay?>.of(_startByDay),
        endTimeByWeekday: Map<String, TimeOfDay?>.of(_endByDay),
        isActive: initialUser?.isActive ?? true,
      );

      trace.log('계정 모델 구성 완료: Firestore 저장을 요청합니다.', progress: 0.58);
      String? saveError;
      bool saved = true;
      if (isEditMode) {
        saved = await userState.updateUserCardAsAdmin(
          user,
          onError: (message) {
            saveError = message;
          },
        );
      } else {
        await userState.addUserCard(
          user,
          onError: (message) {
            saveError = message;
          },
        );
        saved = saveError == null;
      }

      if (!saved || saveError != null) {
        final message = _friendlySaveError(
          saveError ?? '계정 정보를 저장하지 못했습니다.',
        );
        trace.log('계정 저장 실패 응답: $message', progress: 0.9);
        await trace.fail('$operationTitle에 실패했습니다.');
        if (!mounted) return;
        setState(() => _saveError = '$message 입력 내용은 유지됩니다.');
        workspace?.log('settings_submit_failed message=$message');
        if (!trace.developerMode) {
          await StatusDialog.showFailure(
            context,
            title: '$operationTitle 불가',
            description: '$message\n입력 내용은 유지됩니다. 다시 시도할 수 있습니다.',
            visibleDuration: const Duration(seconds: 5),
            useCommonUi: true,
          );
        }
        return;
      }

      trace.log('Firestore 및 사용자 캐시 반영 완료', progress: 0.92);
      await trace.succeed('$operationTitle이 완료되었습니다.');
      if (!mounted) return;
      workspace?.setSettingsDirty(false, source: 'submit_success');
      workspace?.log('settings_submit_completed mode=${isEditMode ? 'edit' : 'create'}');
      showSuccessSnackbar(
        context,
        isEditMode ? '계정 수정이 완료되었습니다.' : '계정 생성이 완료되었습니다.',
        useCommonUi: true,
      );
      workspace?.returnToManagement(source: 'submit_success');
    } catch (error, stackTrace) {
      await trace.fail(
        '$operationTitle 중 예외가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      final message = '$operationTitle 중 문제가 발생했습니다. 입력 내용은 유지됩니다.';
      setState(() => _saveError = message);
      workspace?.log('settings_submit_exception error=$error');
      if (!trace.developerMode) {
        await StatusDialog.showFailure(
          context,
          title: '$operationTitle 불가',
          description: '$message\n네트워크 상태를 확인한 뒤 다시 시도하세요.',
          visibleDuration: const Duration(seconds: 5),
          useCommonUi: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
      workspace?.setSettingsSaving(false, source: 'submit_finished');
    }
  }

  void _returnToManagement() {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    _workspace?.returnToManagement(source: 'settings_footer_back');
  }

  Widget _sectionContainer(
    UserSettingsSection section,
    Widget child,
  ) {
    return KeyedSubtree(
      key: _sectionKeys[section],
      child: child,
    );
  }

  ({Color color, IconData icon, String label}) _sectionStatusVisual(
    BuildContext context,
    UserSettingsSectionState state,
  ) {
    final tokens = CommonUiTheme.of(context);
    switch (state) {
      case UserSettingsSectionState.complete:
        return (
          color: tokens.success,
          icon: Icons.check_circle_rounded,
          label: '완료',
        );
      case UserSettingsSectionState.incomplete:
        return (
          color: tokens.warning,
          icon: Icons.priority_high_rounded,
          label: '입력 필요',
        );
      case UserSettingsSectionState.error:
        return (
          color: tokens.danger,
          icon: Icons.error_rounded,
          label: '오류',
        );
      case UserSettingsSectionState.optional:
        return (
          color: tokens.textSecondary,
          icon: Icons.remove_circle_outline_rounded,
          label: '선택',
        );
    }
  }

  Widget _buildSectionStatusTrailing(
    BuildContext context, {
    required String title,
    required UserSettingsSection section,
    required SecondaryAccountWorkspaceState workspace,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final state = workspace.stateFor(section);
    final status = _sectionStatusVisual(context, state);
    final child = state == UserSettingsSectionState.optional
        ? Text(
            status.label,
            key: ValueKey<String>('${section.name}_${state.name}'),
            style: textTheme.labelSmall?.copyWith(
              color: status.color,
              fontWeight: FontWeight.w900,
            ),
          )
        : Icon(
            status.icon,
            key: ValueKey<String>('${section.name}_${state.name}'),
            size: 16,
            color: status.color,
          );

    return Semantics(
      label: '$title, ${status.label}',
      child: AnimatedSwitcher(
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .94, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _buildFlatInlineMessage(
    BuildContext context,
    String? message,
  ) {
    if (message == null || message.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 9),
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

  String _maskEmailLocal(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '이메일 입력 필요';
    if (trimmed.length == 1) return '*@gmail.com';
    return '${trimmed.substring(0, 1)}${List<String>.filled(trimmed.length - 1, '*').join()}@gmail.com';
  }

  String _identitySummary() {
    if (!_identityOk) return '이름 · 전화번호 · 이메일 입력 필요';
    return '${_maskName(_nameController.text)} · ${_maskPhone(_phoneController.text)} · ${_maskEmailLocal(_emailController.text)}';
  }

  String _permissionSummary() {
    final modes = _normalizeAndFilterModes(_selectedModes)
        .map(_modeLabel)
        .toList(growable: false);
    if (modes.isEmpty) return '${_selectedRole.label} · 허용 모드 입력 필요';
    return '${_selectedRole.label} · ${modes.join(' · ')}';
  }

  String _positionSummary() {
    final value = _positionController.text.trim();
    return value.isEmpty ? '미지정' : value;
  }

  String _passwordSummary() {
    return _passwordOk ? '5자리 비밀번호 설정됨' : '비밀번호 입력 필요';
  }

  String _scheduleSummary() {
    final workingDays = _workingDaySet();
    final breakDays = _normalizedBreakDaysForWorkingDays();
    if (!_scheduleOk) return '근무 시간 확인 필요';
    if (workingDays.isEmpty) return '전체 휴무';
    return '근무 ${workingDays.length}일 · 휴게 ${breakDays.length}일';
  }

  Widget _buildSummarySection(
    BuildContext context, {
    required UserSettingsSection section,
    required String title,
    required String summary,
  }) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final workspace = context.watch<SecondaryAccountWorkspaceState>();
    final active = workspace.activeSettingsSection == section ||
        _editingSection == section;

    return _sectionContainer(
      section,
      Semantics(
        button: true,
        label: '$title, $summary',
        child: OpsDockSelectableRowSurface(
          selected: active,
          selectionColor: tokens.accent,
          selectedContainer: tokens.accentContainer,
          onTap: () => unawaited(_openSectionEditor(section)),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: textTheme.bodyMedium?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildSectionStatusTrailing(
                          context,
                          title: title,
                          section: section,
                          workspace: workspace,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    AnimatedSwitcher(
                      duration: _reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      switchInCurve: CommonUiMotion.enter,
                      switchOutCurve: CommonUiMotion.exit,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(.02, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        summary,
                        key: ValueKey<String>('${section.name}_$summary'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedRotation(
                turns: _editingSection == section ? .25 : 0,
                duration:
                    _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                curve: CommonUiMotion.standard,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: active ? tokens.accent : tokens.iconSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentitySection(BuildContext context) {
    return _buildSummarySection(
      context,
      section: UserSettingsSection.identity,
      title: '기본 정보',
      summary: _identitySummary(),
    );
  }

  Widget _buildPermissionSection(BuildContext context) {
    return _buildSummarySection(
      context,
      section: UserSettingsSection.permission,
      title: '권한과 허용 모드',
      summary: _permissionSummary(),
    );
  }

  Widget _buildPositionSection(BuildContext context) {
    return _buildSummarySection(
      context,
      section: UserSettingsSection.position,
      title: '현장 직책',
      summary: _positionSummary(),
    );
  }

  Widget _buildPasswordSection(BuildContext context) {
    return _buildSummarySection(
      context,
      section: UserSettingsSection.password,
      title: '초기 비밀번호',
      summary: _passwordSummary(),
    );
  }

  Widget _buildScheduleSection(BuildContext context) {
    return _buildSummarySection(
      context,
      section: UserSettingsSection.schedule,
      title: '요일별 근무 시간',
      summary: _scheduleSummary(),
    );
  }

  Widget _buildStatusStrip(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final workspace = context.watch<SecondaryAccountWorkspaceState>();
    final incompleteCount = workspace.incompleteSectionCount;
    final hasSaveError = _saveError != null && _saveError!.trim().isNotEmpty;
    final label = hasSaveError
        ? '저장 확인 필요'
        : incompleteCount == 0
            ? '입력 확인 완료'
            : '확인 필요 $incompleteCount개';
    final icon = hasSaveError
        ? Icons.error_rounded
        : incompleteCount == 0
            ? Icons.check_circle_rounded
            : Icons.error_outline_rounded;
    final color = hasSaveError
        ? tokens.danger
        : incompleteCount == 0
            ? tokens.success
            : tokens.warning;

    return Row(
      children: [
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        AnimatedSwitcher(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          switchInCurve: CommonUiMotion.enter,
          switchOutCurve: CommonUiMotion.exit,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: .96, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: Icon(
            icon,
            key: ValueKey<String>(label),
            size: 16,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildContentSurface(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final divider = Container(height: 1, color: tokens.borderSubtle);
    return OpsDockListSurface(
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: SingleChildScrollView(
          key: _scrollViewportKey,
          controller: _scrollController,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSize(
                duration:
                    _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                curve: CommonUiMotion.enter,
                child: _saveError == null
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                            child: _buildFlatInlineMessage(context, _saveError),
                          ),
                          divider,
                        ],
                      ),
              ),
              _buildIdentitySection(context),
              divider,
              _buildPermissionSection(context),
              divider,
              _buildPositionSection(context),
              divider,
              _buildPasswordSection(context),
              divider,
              _buildScheduleSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final footerKey = _saving
        ? 'settings_footer_saving'
        : isEditMode
            ? 'settings_footer_edit'
            : 'settings_footer_create';
    return OpsDockContextFooter(
      key: ValueKey<String>(footerKey),
      children: [
        Expanded(
          child: CommonButton(
            label: '계정 목록',
            icon: Icons.arrow_back_rounded,
            onPressed: _saving ? null : _returnToManagement,
            variant: CommonButtonVariant.secondary,
            haptic: CommonHaptic.selection,
            minHeight: 42,
            expand: true,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: CommonButton(
            label: isEditMode ? '수정 완료' : '생성 완료',
            icon: isEditMode ? Icons.save_rounded : Icons.person_add_alt_1_rounded,
            onPressed: _saving ? null : _handleSave,
            variant: CommonButtonVariant.primary,
            loading: _saving,
            haptic: CommonHaptic.selection,
            minHeight: 42,
            expand: true,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final workspace = context.watch<SecondaryAccountWorkspaceState>();
    _scheduleNavigationRequest(workspace);

    return Material(
      color: tokens.canvas,
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                child: _buildStatusStrip(context),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  child: _buildContentSurface(context),
                ),
              ),
              OpsDockContextFooterTransition(
                child: _buildFooter(context),
              ),
            ],
          ),
          OpsDockLoadingOverlay(loading: _saving),
        ],
      ),
    );
  }
}
