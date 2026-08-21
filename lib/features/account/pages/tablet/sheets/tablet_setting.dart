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
import '../../../../../shared/secondary/application/secondary_tablet_workspace_state.dart';
import '../../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../../dev/application/area_state.dart';
import '../../../applications/user_state.dart';
import '../../../domain/models/tablet/tablet_model.dart';
import '../../../domain/repositories/user_repository.dart';
import 'models/tablet_settings_draft.dart';
import 'tablet_setting_section_editor_dialog.dart';
import 'widgets/tablet_role_type.dart';

class TabletSettingWorkspace extends StatefulWidget {
  const TabletSettingWorkspace({
    super.key,
    required this.initialTablet,
  });

  final TabletModel? initialTablet;

  @override
  State<TabletSettingWorkspace> createState() => _TabletSettingWorkspaceState();
}

class _TabletSettingWorkspaceState extends State<TabletSettingWorkspace> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _handleController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _scrollViewportKey = GlobalKey();
  final Map<TabletSettingsSection, GlobalKey> _sectionKeys =
      <TabletSettingsSection, GlobalKey>{
    for (final section in TabletSettingsSection.values) section: GlobalKey(),
  };

  TabletRoleType _selectedRole = TabletRoleType.lowField;
  String? _saveError;
  bool _saving = false;
  bool _validationSubmitted = false;
  bool _reduceMotion = false;
  int _handledNavigationRequestId = -1;
  TabletSettingsSection? _pendingVisibleSection;
  TabletSettingsSection? _editingSection;
  bool _visibleSectionScheduled = false;
  SecondaryTabletWorkspaceState? _workspace;
  TabletModel? _initialTabletSnapshot;

  bool get isEditMode => _initialTabletSnapshot != null;

  @override
  void initState() {
    super.initState();
    _initialTabletSnapshot = widget.initialTablet;
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
    _workspace ??= context.read<SecondaryTabletWorkspaceState>();
  }

  @override
  void didUpdateWidget(covariant TabletSettingWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTablet?.id == widget.initialTablet?.id) return;
    if (widget.initialTablet == null && _saving && _initialTabletSnapshot != null) {
      return;
    }
    _initialTabletSnapshot = widget.initialTablet;
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
    _handleController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _populateInitialValues() {
    final tablet = _initialTabletSnapshot;
    if (tablet == null) {
      _nameController.clear();
      _handleController.clear();
      _emailController.clear();
      _passwordController.text = FiveDigitPasswordGenerator.generate();
      _selectedRole = TabletRoleType.lowField;
      return;
    }
    _nameController.text = tablet.name;
    _handleController.text = tablet.handle;
    _emailController.text = tablet.email.split('@').first;
    _passwordController.text = tablet.password;
    _selectedRole = TabletRoleType.fromName(tablet.role);
  }

  bool _isValidEmailLocalPart(String value) {
    return RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value.trim());
  }

  bool get _nameOk => _nameController.text.trim().isNotEmpty;
  bool get _handleOk =>
      RegExp(r'^[a-z]{3,20}$').hasMatch(_handleController.text.trim());
  bool get _emailOk => _emailController.text.trim().isNotEmpty &&
      _isValidEmailLocalPart(_emailController.text);
  bool get _identityOk => _nameOk && _handleOk && _emailOk;
  bool get _passwordOk =>
      RegExp(r'^\d{5}$').hasMatch(_passwordController.text.trim());

  TabletSettingsSectionState _sectionState(TabletSettingsSection section) {
    switch (section) {
      case TabletSettingsSection.identity:
        if (_identityOk) return TabletSettingsSectionState.complete;
        return _validationSubmitted
            ? TabletSettingsSectionState.error
            : TabletSettingsSectionState.incomplete;
      case TabletSettingsSection.permission:
        return TabletSettingsSectionState.complete;
      case TabletSettingsSection.password:
        if (_passwordOk) return TabletSettingsSectionState.complete;
        return TabletSettingsSectionState.error;
    }
  }

  Map<TabletSettingsSection, TabletSettingsSectionState> _allSectionStates() {
    return <TabletSettingsSection, TabletSettingsSectionState>{
      for (final section in TabletSettingsSection.values)
        section: _sectionState(section),
    };
  }

  void _syncSectionStates({required String source}) {
    _workspace?.updateSectionStates(_allSectionStates(), source: source);
  }

  TabletSettingsDraft _currentDraft() {
    return TabletSettingsDraft(
      name: _nameController.text.trim(),
      handle: _handleController.text.trim(),
      emailLocal: _emailController.text.trim(),
      role: _selectedRole,
      password: _passwordController.text.trim(),
    );
  }

  void _applyEditorDraft(
    TabletSettingsSection section,
    TabletSettingsDraft draft,
  ) {
    setState(() {
      switch (section) {
        case TabletSettingsSection.identity:
          _nameController.text = draft.name;
          _handleController.text = draft.handle;
          _emailController.text = draft.emailLocal;
          break;
        case TabletSettingsSection.permission:
          _selectedRole = draft.role;
          break;
        case TabletSettingsSection.password:
          _passwordController.text = draft.password;
          break;
      }
      _saveError = null;
    });
    _workspace?.setSettingsDirty(true, source: 'editor_apply_${section.name}');
    _workspace?.selectSettingsSection(section, source: 'editor_apply');
    _syncSectionStates(source: 'editor_apply_${section.name}');
  }

  String _sectionTitle(TabletSettingsSection section) {
    switch (section) {
      case TabletSettingsSection.identity:
        return '태블릿 식별 정보';
      case TabletSettingsSection.permission:
        return '운영 권한';
      case TabletSettingsSection.password:
        return '로그인 비밀번호';
    }
  }

  Size _editorTargetSize(TabletSettingsSection section) {
    switch (section) {
      case TabletSettingsSection.identity:
        return const Size(520, 470);
      case TabletSettingsSection.permission:
        return const Size(460, 320);
      case TabletSettingsSection.password:
        return const Size(460, 360);
    }
  }

  Rect? _sourceRectFor(TabletSettingsSection section) {
    final sectionContext = _sectionKeys[section]?.currentContext;
    final box = sectionContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  Future<void> _openSectionEditor(
    TabletSettingsSection section, {
    bool ensureVisible = true,
  }) async {
    if (_saving || _editingSection != null) return;
    _workspace?.selectSettingsSection(section, source: 'summary_row_tap');
    if (ensureVisible) {
      await _scrollToSection(section);
      if (!mounted) return;
    }
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final sourceRect = _sourceRectFor(section);
    if (sourceRect == null) {
      _workspace?.log('settings_editor_open_failed section=${section.name} reason=no_source_rect');
      return;
    }
    setState(() => _editingSection = section);
    _workspace?.log('settings_editor_open_requested section=${section.name}');
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    final trace = await DeveloperOperationTrace.start(
      context: rootContext,
      title: '${_sectionTitle(section)} 편집',
      initialMessage: '태블릿 설정 편집을 시작합니다: section=${section.name}',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 편집 Dialog의 버그 아이콘에서 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 편집 동작을 콘솔에 기록합니다.',
      showDialogImmediately: false,
    );
    try {
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
          return TabletSettingSectionEditorDialog(
            section: section,
            initialDraft: _currentDraft().detached(),
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

  Future<void> _scrollToSection(TabletSettingsSection section) async {
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

  void _scheduleNavigationRequest(SecondaryTabletWorkspaceState workspace) {
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
    TabletSettingsSection? best;
    double bestDistance = double.infinity;
    for (final section in TabletSettingsSection.values) {
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

  TabletSettingsSection? _firstInvalidSection() {
    final states = _allSectionStates();
    for (final section in TabletSettingsSection.values) {
      final state = states[section];
      if (state == TabletSettingsSectionState.error ||
          state == TabletSettingsSectionState.incomplete) {
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

  String _maskEmailLocal(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '이메일 입력 필요';
    if (trimmed.length == 1) return '*@gmail.com';
    return '${trimmed.substring(0, 1)}${List<String>.filled(trimmed.length - 1, '*').join()}@gmail.com';
  }

  String _identitySummary() {
    if (!_identityOk) return '이름 · 아이디 · 이메일 입력 필요';
    return '${_maskName(_nameController.text)} · ${_handleController.text.trim()} · ${_maskEmailLocal(_emailController.text)}';
  }

  String _permissionSummary() => _selectedRole.label;

  String _passwordSummary() {
    return _passwordOk ? '5자리 비밀번호 설정됨' : '비밀번호 입력 필요';
  }

  String _friendlySaveError(String message) {
    final value = message.trim();
    return value.isEmpty ? '태블릿 정보를 저장하지 못했습니다.' : value;
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
    final initialTablet = _initialTabletSnapshot;
    final operationTitle = isEditMode ? '태블릿 수정' : '태블릿 등록';

    setState(() => _saving = true);
    workspace?.setSettingsSaving(true, source: 'submit_started');
    workspace?.log(
      'settings_submit_started mode=${isEditMode ? 'edit' : 'create'} nameLength=${_nameController.text.trim().length} handleLength=${_handleController.text.trim().length}',
    );

    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: operationTitle,
      initialMessage: '$operationTitle 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 태블릿 설정 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 태블릿 설정 로그를 콘솔에 기록합니다.',
    );

    try {
      if (area.isEmpty) {
        throw StateError('현재 지역 정보가 없습니다.');
      }
      trace.log(
        '입력값 검증 통과: nameLength=${_nameController.text.trim().length}, handleLength=${_handleController.text.trim().length}, role=${_selectedRole.name}',
        progress: .14,
      );
      final englishName = await repository.getEnglishNameByArea(area, division);
      trace.log(
        '지역 메타데이터 조회 완료: area=$area, division=${division.isEmpty ? '-' : division}',
        progress: .32,
      );

      final email = '${_emailController.text.trim()}@gmail.com';
      final nextTablet = initialTablet == null
          ? TabletModel(
              id: '${_handleController.text.trim()}-$area',
              name: _nameController.text.trim(),
              handle: _handleController.text.trim(),
              email: email,
              role: _selectedRole.name,
              password: _passwordController.text.trim(),
              position: null,
              areas: <String>[area],
              divisions: <String>[division],
              currentArea: area,
              selectedArea: area,
              englishSelectedAreaName: englishName ?? area,
              isWorking: false,
              isSaved: false,
              fixedHolidays: const <String>[],
            )
          : initialTablet.copyWith(
              id: '${_handleController.text.trim()}-$area',
              name: _nameController.text.trim(),
              handle: _handleController.text.trim(),
              email: email,
              role: _selectedRole.name,
              password: _passwordController.text.trim(),
              areas: <String>[area],
              divisions: <String>[division],
              currentArea: area,
              selectedArea: area,
              englishSelectedAreaName: englishName ?? area,
            );

      trace.log('태블릿 모델 구성 완료: Firestore 저장을 요청합니다.', progress: .56);
      String? saveError;
      bool saved = true;
      if (isEditMode) {
        saved = await userState.updateTabletCardAsAdmin(
          nextTablet,
          previousId: initialTablet!.id,
          onError: (message) {
            saveError = message;
          },
        );
      } else {
        await userState.addTabletCard(
          nextTablet,
          onError: (message) {
            saveError = message;
          },
        );
        saved = saveError == null;
      }

      if (!saved || saveError != null) {
        final message = _friendlySaveError(
          saveError ?? '태블릿 정보를 저장하지 못했습니다.',
        );
        trace.log('태블릿 저장 실패 응답: $message', progress: .9);
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

      trace.log('Firestore 및 태블릿 캐시 반영 완료', progress: .92);
      await trace.succeed('$operationTitle이 완료되었습니다.');
      if (!mounted) return;
      workspace?.setSettingsDirty(false, source: 'submit_success');
      workspace?.log('settings_submit_completed mode=${isEditMode ? 'edit' : 'create'}');
      final selectedId = userState.selectedUserId;
      if (selectedId != null) {
        unawaited(userState.toggleUserCard(selectedId));
      }
      showSuccessSnackbar(
        context,
        isEditMode ? '태블릿 수정이 완료되었습니다.' : '태블릿 등록이 완료되었습니다.',
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
    TabletSettingsSection section,
    Widget child,
  ) {
    return KeyedSubtree(
      key: _sectionKeys[section],
      child: child,
    );
  }

  ({Color color, IconData icon, String label}) _sectionStatusVisual(
    BuildContext context,
    TabletSettingsSectionState state,
  ) {
    final tokens = CommonUiTheme.of(context);
    switch (state) {
      case TabletSettingsSectionState.complete:
        return (
          color: tokens.success,
          icon: Icons.check_circle_rounded,
          label: '완료',
        );
      case TabletSettingsSectionState.incomplete:
        return (
          color: tokens.warning,
          icon: Icons.priority_high_rounded,
          label: '입력 필요',
        );
      case TabletSettingsSectionState.error:
        return (
          color: tokens.danger,
          icon: Icons.error_rounded,
          label: '오류',
        );
    }
  }

  Widget _buildSectionStatusTrailing(
    BuildContext context, {
    required String title,
    required TabletSettingsSection section,
    required SecondaryTabletWorkspaceState workspace,
  }) {
    final state = workspace.stateFor(section);
    final visual = _sectionStatusVisual(context, state);
    return Semantics(
      label: '$title, ${visual.label}',
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
        child: Icon(
          visual.icon,
          key: ValueKey<TabletSettingsSectionState>(state),
          size: 17,
          color: visual.color,
        ),
      ),
    );
  }

  Widget _buildSummarySection(
    BuildContext context, {
    required TabletSettingsSection section,
    required String title,
    required String summary,
  }) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final workspace = context.watch<SecondaryTabletWorkspaceState>();
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

  Widget _buildStatusStrip(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final workspace = context.watch<SecondaryTabletWorkspaceState>();
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

  Widget _buildFlatInlineMessage(BuildContext context, String? message) {
    if (message == null || message.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                          _buildFlatInlineMessage(context, _saveError),
                          divider,
                        ],
                      ),
              ),
              _buildSummarySection(
                context,
                section: TabletSettingsSection.identity,
                title: '태블릿 식별 정보',
                summary: _identitySummary(),
              ),
              divider,
              _buildSummarySection(
                context,
                section: TabletSettingsSection.permission,
                title: '운영 권한',
                summary: _permissionSummary(),
              ),
              divider,
              _buildSummarySection(
                context,
                section: TabletSettingsSection.password,
                title: '로그인 비밀번호',
                summary: _passwordSummary(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final key = _saving
        ? 'tablet_settings_footer_saving'
        : isEditMode
            ? 'tablet_settings_footer_edit'
            : 'tablet_settings_footer_create';
    return OpsDockContextFooter(
      key: ValueKey<String>(key),
      children: [
        Expanded(
          child: CommonButton(
            label: '태블릿 목록',
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
            label: isEditMode ? '수정 완료' : '등록 완료',
            icon: isEditMode ? Icons.save_rounded : Icons.add_to_queue_rounded,
            onPressed: _saving ? null : _handleSave,
            loading: _saving,
            variant: CommonButtonVariant.primary,
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
    final workspace = context.watch<SecondaryTabletWorkspaceState>();
    _scheduleNavigationRequest(workspace);

    return Material(
      color: tokens.canvas,
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
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
