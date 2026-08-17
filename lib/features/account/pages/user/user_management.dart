import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/application/secondary_account_workspace_state.dart';
import '../../../../shared/secondary/widgets/ops_console_dialogs.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../dev/application/area_state.dart';
import '../../applications/user_state.dart';
import '../../domain/models/user/user_model.dart';
import '../../domain/repositories/user_repository.dart';
import 'sheets/user_setting.dart';

extension IterableX<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}

enum _UserStatusFilter { all, active, inactive }

class UserManagement extends StatefulWidget {
  const UserManagement({super.key});

  @override
  State<UserManagement> createState() => _UserManagementState();
}

class _UserManagementState extends State<UserManagement> {
  final TextEditingController _searchController = TextEditingController();
  SecondaryAccountWorkspaceState? _workspaceState;
  String _query = '';
  _UserStatusFilter _statusFilter = _UserStatusFilter.all;
  bool _refreshing = false;
  bool _selectionClearScheduled = false;

  void _log(String message) {
    final workspace = _workspaceState;
    if (workspace != null) {
      workspace.log(message);
      return;
    }
    debugPrint('[UserManagement] $message');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_initialRefresh());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_workspaceState != null) return;
    _workspaceState = context.read<SecondaryAccountWorkspaceState>();
    _log('user_management_mounted');
  }

  @override
  void dispose() {
    _log('user_management_disposed');
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialRefresh() async {
    final userState = context.read<UserState>();
    _log('initial_refresh_started');
    try {
      await userState.refreshUsersBySelectedAreaAndCache();
      if (!mounted) return;
      _clearSelection(userState, reason: 'initial_refresh');
      _log('initial_refresh_completed count=${userState.users.length}');
    } catch (error) {
      _log('initial_refresh_failed error=$error');
    }
  }

  Future<void> _refreshUsersForCurrentArea(BuildContext context) async {
    if (_refreshing) return;
    final userState = context.read<UserState>();
    setState(() => _refreshing = true);
    _log('refresh_started');
    try {
      await userState.refreshUsersBySelectedAreaAndCache();
      if (!context.mounted) return;
      _clearSelection(userState, reason: 'refresh');
      _log('refresh_completed count=${userState.users.length}');
    } catch (error) {
      _log('refresh_failed error=$error');
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  void _clearSelection(
    UserState userState, {
    String reason = 'manual',
  }) {
    final id = userState.selectedUserId;
    if (id == null) return;
    unawaited(userState.toggleUserCard(id));
    _log('selection_cleared reason=$reason');
  }

  void _setQuery(String value) {
    if (_query == value) return;
    setState(() => _query = value);
    _log('query_changed length=${value.trim().length}');
  }

  void _clearQuery() {
    if (_query.isEmpty && _searchController.text.isEmpty) return;
    _searchController.clear();
    setState(() => _query = '');
    _log('query_cleared');
  }

  void _setStatusFilter(_UserStatusFilter filter) {
    if (_statusFilter == filter) return;
    HapticFeedback.selectionClick();
    setState(() => _statusFilter = filter);
    _log('status_filter_changed value=${filter.name}');
  }

  void _scheduleSelectionValidation(
    UserState userState,
    List<UserModel> scopedUsers,
    List<UserModel> visibleUsers,
  ) {
    final selectedId = userState.selectedUserId;
    if (selectedId == null) return;
    if (visibleUsers.any((user) => user.id == selectedId)) return;
    if (_selectionClearScheduled) return;
    _selectionClearScheduled = true;
    final inScope = scopedUsers.any((user) => user.id == selectedId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionClearScheduled = false;
      if (!mounted) return;
      final current = context.read<UserState>();
      if (current.selectedUserId != selectedId) return;
      _clearSelection(
        current,
        reason: inScope ? 'filtered_out' : 'scope_changed',
      );
    });
  }

  String? _limitNumberFromMessage(String message) {
    final match = RegExp(r'최대\s*(\d+)').firstMatch(message);
    return match?.group(1);
  }

  Future<void> _showAccountFailureDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String fallbackDescription,
  }) async {
    if (!context.mounted) return;

    final limit = _limitNumberFromMessage(message);
    String description = fallbackDescription;

    if (message.contains('활성화 제한')) {
      description = limit == null
          ? '선택한 지역의 활성 계정 한도에 도달했습니다. 기존 활성 계정을 비활성화하거나 리밋 설정에서 활성 한도를 늘린 뒤 다시 시도하세요.'
          : '선택한 지역의 활성 계정 한도에 도달했습니다. 활성 계정은 최대 ${limit}개까지만 사용할 수 있습니다. 기존 활성 계정을 비활성화하거나 리밋 설정에서 활성 한도를 늘린 뒤 다시 시도하세요.';
    } else if (message.contains('전체 계정 제한')) {
      description = limit == null
          ? '선택한 지역의 전체 계정 생성 한도에 도달했습니다. 기존 계정을 삭제하거나 리밋 설정에서 전체 한도를 늘린 뒤 다시 시도하세요.'
          : '선택한 지역의 전체 계정 생성 한도에 도달했습니다. 활성 계정과 비활성 계정을 합쳐 최대 ${limit}개까지만 생성할 수 있습니다. 기존 계정을 삭제하거나 리밋 설정에서 전체 한도를 늘린 뒤 다시 시도하세요.';
    }

    await StatusDialog.showFailure(
      context,
      title: title,
      description: description,
      useCommonUi: true,
    );
  }

  TimeOfDay? _stringToTimeOfDay(String? timeString) {
    if (timeString == null) return null;
    final parts = timeString.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Map<String, TimeOfDay?> _stringWeekMapToTimeMap(Map<String, String?> raw) {
    final out = <String, TimeOfDay?>{};
    for (final day in UserModel.weekdays) {
      out[day] = _stringToTimeOfDay(raw[day]);
    }
    return out;
  }

  List<String> _normalizeDayList(Iterable<String> raw) {
    final set = raw.map((value) => value.trim()).where((value) => value.isNotEmpty).toSet();
    return <String>[
      for (final day in UserModel.weekdays)
        if (set.contains(day)) day,
      for (final value in set)
        if (!UserModel.weekdays.contains(value)) value,
    ];
  }

  List<String> _fixedHolidaysFromWeekMaps({
    required Map<String, TimeOfDay?> startByWeekday,
    required Map<String, TimeOfDay?> endByWeekday,
  }) {
    return <String>[
      for (final day in UserModel.weekdays)
        if (startByWeekday[day] == null && endByWeekday[day] == null) day,
    ];
  }

  List<String> _normalizeBreakDaysForWorkingMap({
    required Iterable<String> breakDays,
    required Map<String, TimeOfDay?> startByWeekday,
    required Map<String, TimeOfDay?> endByWeekday,
  }) {
    final breakSet = _normalizeDayList(breakDays).toSet();
    return <String>[
      for (final day in UserModel.weekdays)
        if (breakSet.contains(day) && startByWeekday[day] != null && endByWeekday[day] != null) day,
    ];
  }

  String _maskName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final runes = trimmed.runes.toList();
    if (runes.length <= 1) return trimmed;
    final mask = List.filled(runes.length - 1, '*').join();
    return '${String.fromCharCode(runes.first)}$mask';
  }

  String _maskPhone(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    final digitMatches = RegExp(r'\d').allMatches(trimmed).toList();
    if (digitMatches.isEmpty) return trimmed;

    final maskIndexes = <int>{};
    if (digitMatches.length >= 8) {
      final start = ((digitMatches.length - 4) / 2).floor();
      for (var i = start; i < start + 4 && i < digitMatches.length; i++) {
        maskIndexes.add(digitMatches[i].start);
      }
    } else if (digitMatches.length <= 2) {
      for (final match in digitMatches) {
        maskIndexes.add(match.start);
      }
    } else {
      for (var i = 1; i < digitMatches.length - 1; i++) {
        maskIndexes.add(digitMatches[i].start);
      }
    }

    final buffer = StringBuffer();
    for (var i = 0; i < trimmed.length; i++) {
      buffer.write(maskIndexes.contains(i) ? '*' : trimmed[i]);
    }
    return buffer.toString();
  }

  void buildUserBottomSheet({
    required BuildContext context,
    required void Function(
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
    ) onSave,
    UserModel? initialUser,
  }) {
    final areaState = context.read<AreaState>();
    final currentArea = areaState.currentArea;
    final currentDivision = areaState.currentDivision;
    _log('form_opened mode=${initialUser == null ? 'create' : 'edit'}');

    showCommonOverlayBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 1,
        child: UserSettingBottomSheet(
          onSave: onSave,
          areaValue: currentArea,
          division: currentDivision,
          isEditMode: initialUser != null,
          initialUser: initialUser,
        ),
      ),
    );
  }

  Future<bool> _confirmToggleActive(
    BuildContext context, {
    required bool toActive,
  }) {
    return showOpsConfirmDialog(
      context: context,
      title: toActive ? '활성화 확인' : '비활성화 확인',
      message: toActive
          ? '선택한 계정을 활성화하시겠습니까?'
          : '선택한 계정을 비활성화하시겠습니까?',
      confirmLabel: toActive ? '활성화' : '비활성화',
      icon: toActive
          ? Icons.play_circle_fill_rounded
          : Icons.pause_circle_filled_rounded,
      destructive: !toActive,
    );
  }

  Future<bool> _confirmDeleteUser(BuildContext context) {
    return showOpsConfirmDialog(
      context: context,
      title: '계정 삭제 확인',
      message: '선택한 계정을 삭제하시겠습니까? 삭제 후 복구할 수 없습니다.',
      confirmLabel: '삭제',
      icon: Icons.delete_forever_rounded,
      destructive: true,
    );
  }

  Future<void> _handlePrimaryAction(
    BuildContext context, {
    bool forceCreate = false,
  }) async {
    final userState = context.read<UserState>();
    if (forceCreate) {
      _clearSelection(userState, reason: 'create_opened');
    }
    final selectedId = forceCreate ? null : userState.selectedUserId;

    if (selectedId == null) {
      buildUserBottomSheet(
        context: context,
        onSave: (
          name,
          phone,
          email,
          role,
          modes,
          password,
          area,
          division,
          isWorking,
          isSaved,
          selectedArea,
          startTimeByWeekday,
          endTimeByWeekday,
          fixedHolidays,
          breakDays,
          position,
        ) async {
          final trace = await DeveloperOperationTrace.start(
            context: context,
            title: '계정 생성',
            initialMessage: '계정 생성 요청을 시작합니다.',
            useCommonUi: true,
            developerModeMessage: '개발자 모드 ON: 계정 생성 로그를 debugPrint 코드로 복사할 수 있습니다.',
            standardModeMessage: '개발자 모드 OFF: 계정 생성 로그를 콘솔에 기록합니다.',
          );

          try {
            trace.log(
              '입력값 검증 통과: 사용자 ${_maskName(name)}, 전화 ${_maskPhone(phone)}, 허용 모드 ${modes.length}개',
              progress: 0.12,
            );

            final englishName = await context.read<UserRepository>().getEnglishNameByArea(selectedArea, division);
            trace.log(
              '지역 메타데이터 조회 완료: division=$division, area=$selectedArea',
              progress: 0.24,
            );

            final parsedStartMap = _stringWeekMapToTimeMap(startTimeByWeekday);
            final parsedEndMap = _stringWeekMapToTimeMap(endTimeByWeekday);
            final submittedHolidays = _normalizeDayList(fixedHolidays);
            final normalizedHolidays = _fixedHolidaysFromWeekMaps(
              startByWeekday: parsedStartMap,
              endByWeekday: parsedEndMap,
            );
            final normalizedBreakDays = _normalizeBreakDaysForWorkingMap(
              breakDays: breakDays,
              startByWeekday: parsedStartMap,
              endByWeekday: parsedEndMap,
            );
            final workingDays = UserModel.weekdays
                .where((day) => parsedStartMap[day] != null && parsedEndMap[day] != null)
                .toList(growable: false);

            trace.log(
              '근무 일정 정규화 완료: 근무일 ${workingDays.length}일, 휴무일 ${normalizedHolidays.length}일, 휴게일 ${normalizedBreakDays.length}일',
              progress: 0.38,
            );
            if (submittedHolidays.join('|') != normalizedHolidays.join('|')) {
              trace.log(
                '휴무일 정합성 보정: 요일별 출퇴근 시간 기준으로 휴무일을 재계산했습니다.',
                progress: 0.42,
              );
            }
            if (workingDays.isEmpty) {
              trace.log(
                '전 요일 휴무 일정 확인: 월~일 요일별 근무 시간이 모두 휴무 상태입니다.',
                progress: 0.44,
              );
            }

            final newUser = UserModel(
              id: '$phone-$area',
              name: name,
              phone: phone,
              email: email,
              role: role,
              modes: modes,
              password: password,
              position: position,
              areas: [area],
              divisions: [division],
              currentArea: area,
              selectedArea: selectedArea,
              englishSelectedAreaName: englishName ?? area,
              isSelected: false,
              isWorking: isWorking,
              isSaved: isSaved,
              breakDays: normalizedBreakDays,
              startTimeByWeekday: parsedStartMap,
              endTimeByWeekday: parsedEndMap,
            );

            trace.log('계정 모델 구성 완료: Firestore 저장을 요청합니다.', progress: 0.58);

            String? saveError;
            await userState.addUserCard(
              newUser,
              onError: (message) {
                saveError = message;
              },
            );

            if (saveError != null) {
              trace.log('계정 생성 실패 응답: $saveError', progress: 0.9);
              await trace.fail('계정 생성에 실패했습니다.');
              if (!trace.developerMode && context.mounted) {
                await _showAccountFailureDialog(
                  context,
                  title: '계정 생성 불가',
                  message: saveError!,
                  fallbackDescription: '계정을 생성하는 중 문제가 발생했습니다. 입력값과 네트워크 상태를 확인한 뒤 다시 시도하세요.',
                );
              }
              return;
            }

            trace.log('Firestore 및 사용자 캐시 반영 완료', progress: 0.92);
            await trace.succeed('계정 생성이 완료되었습니다.');

            if (!context.mounted) return;
            _clearSelection(userState);
          } catch (error, stackTrace) {
            await trace.fail(
              '계정 생성 중 예외가 발생했습니다.',
              error: error,
              stackTrace: stackTrace,
            );
            if (!trace.developerMode && context.mounted) {
              await _showAccountFailureDialog(
                context,
                title: '계정 생성 불가',
                message: '사용자 추가 실패: $error',
                fallbackDescription: '계정을 생성하는 중 문제가 발생했습니다. 입력값과 네트워크 상태를 확인한 뒤 다시 시도하세요.',
              );
            }
            if (!context.mounted) return;
            _clearSelection(userState);
          }
        },
      );
      return;
    }

    final selectedUser = userState.users.firstWhereOrNull((u) => u.id == selectedId);
    if (selectedUser == null) {
      _clearSelection(userState);
      return;
    }

    buildUserBottomSheet(
      context: context,
      initialUser: selectedUser,
      onSave: (
        name,
        phone,
        email,
        role,
        modes,
        password,
        area,
        division,
        isWorking,
        isSaved,
        selectedArea,
        startTimeByWeekday,
        endTimeByWeekday,
        fixedHolidays,
        breakDays,
        position,
      ) async {
        final trace = await DeveloperOperationTrace.start(
          context: context,
          title: '계정 수정',
          initialMessage: '계정 수정 요청을 시작합니다.',
          useCommonUi: true,
          developerModeMessage: '개발자 모드 ON: 계정 수정 로그를 debugPrint 코드로 복사할 수 있습니다.',
          standardModeMessage: '개발자 모드 OFF: 계정 수정 로그를 콘솔에 기록합니다.',
        );

        try {
          trace.log(
            '수정 대상 확인: 사용자 ${_maskName(selectedUser.name)}, 전화 ${_maskPhone(selectedUser.phone)}',
            progress: 0.1,
          );

          final englishName = await context.read<UserRepository>().getEnglishNameByArea(selectedArea, division);
          trace.log(
            '지역 메타데이터 조회 완료: division=$division, area=$selectedArea',
            progress: 0.22,
          );

          final parsedStartMap = _stringWeekMapToTimeMap(startTimeByWeekday);
          final parsedEndMap = _stringWeekMapToTimeMap(endTimeByWeekday);
          final submittedHolidays = _normalizeDayList(fixedHolidays);
          final normalizedHolidays = _fixedHolidaysFromWeekMaps(
            startByWeekday: parsedStartMap,
            endByWeekday: parsedEndMap,
          );
          final normalizedBreakDays = _normalizeBreakDaysForWorkingMap(
            breakDays: breakDays,
            startByWeekday: parsedStartMap,
            endByWeekday: parsedEndMap,
          );
          final workingDays = UserModel.weekdays
              .where((day) => parsedStartMap[day] != null && parsedEndMap[day] != null)
              .toList(growable: false);

          trace.log(
            '근무 일정 정규화 완료: 근무일 ${workingDays.length}일, 휴무일 ${normalizedHolidays.length}일, 휴게일 ${normalizedBreakDays.length}일',
            progress: 0.38,
          );
          if (submittedHolidays.join('|') != normalizedHolidays.join('|')) {
            trace.log(
              '휴무일 정합성 보정: 요일별 출퇴근 시간 기준으로 휴무일을 재계산했습니다.',
              progress: 0.42,
            );
          }
          if (workingDays.isEmpty) {
            trace.log(
              '전 요일 휴무 일정 확인: 월~일 요일별 근무 시간이 모두 휴무 상태입니다.',
              progress: 0.46,
            );
          }

          final updatedUser = UserModel(
            id: selectedUser.id,
            name: name,
            phone: phone,
            email: email,
            role: role,
            modes: modes,
            password: password,
            position: position,
            areas: [area],
            divisions: [division],
            currentArea: area,
            selectedArea: selectedArea,
            englishSelectedAreaName: englishName ?? area,
            isSelected: selectedUser.isSelected,
            isWorking: isWorking,
            isSaved: isSaved,
            breakDays: normalizedBreakDays,
            startTimeByWeekday: parsedStartMap,
            endTimeByWeekday: parsedEndMap,
            isActive: selectedUser.isActive,
          );

          trace.log('수정 모델 구성 완료: Firestore 저장을 요청합니다.', progress: 0.6);

          String? saveError;
          final saved = await userState.updateUserCardAsAdmin(
            updatedUser,
            onError: (message) {
              saveError = message;
            },
          );

          if (!saved) {
            final message = saveError ?? '사용자 수정에 실패했습니다.';
            trace.log('계정 수정 실패 응답: $message', progress: 0.9);
            await trace.fail('계정 수정에 실패했습니다.');
            if (!trace.developerMode && context.mounted) {
              await _showAccountFailureDialog(
                context,
                title: '계정 저장 불가',
                message: message,
                fallbackDescription: '계정 정보를 저장하는 중 문제가 발생했습니다. 입력값과 네트워크 상태를 확인한 뒤 다시 시도하세요.',
              );
            }
            return;
          }

          trace.log('Firestore 및 사용자 캐시 반영 완료', progress: 0.92);
          await trace.succeed('계정 수정이 완료되었습니다.');
        } catch (error, stackTrace) {
          await trace.fail(
            '계정 수정 중 예외가 발생했습니다.',
            error: error,
            stackTrace: stackTrace,
          );
          if (!trace.developerMode && context.mounted) {
            await _showAccountFailureDialog(
              context,
              title: '계정 저장 불가',
              message: '사용자 수정 실패: $error',
              fallbackDescription: '계정 정보를 저장하는 중 문제가 발생했습니다. 입력값과 네트워크 상태를 확인한 뒤 다시 시도하세요.',
            );
          }
        } finally {
          _clearSelection(userState);
        }
      },
    );
  }

  Future<void> _handleToggleActive(BuildContext context) async {
    final userState = context.read<UserState>();
    final selectedId = userState.selectedUserId;
    if (selectedId == null) return;

    final selectedUser = userState.users.firstWhereOrNull((u) => u.id == selectedId);
    if (selectedUser == null) {
      _clearSelection(userState);
      return;
    }

    final toActive = !selectedUser.isActive;
    final ok = await _confirmToggleActive(context, toActive: toActive);
    if (!ok) return;

    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: toActive ? '계정 활성화' : '계정 비활성화',
      initialMessage: toActive ? '계정 활성화 요청을 시작합니다.' : '계정 비활성화 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 활성 상태 변경 및 legacy 근무시간 마이그레이션 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 활성 상태 변경 및 legacy 근무시간 마이그레이션 로그를 콘솔에 기록합니다.',
    );

    String? statusError;

    try {
      trace.log(
        '대상 계정 확인: 사용자 ${_maskName(selectedUser.name)}, 전화 ${_maskPhone(selectedUser.phone)}',
        progress: 0.12,
      );
      trace.log(
        '요일별 근무시간 스키마 보호 준비: legacy scalar-only 데이터는 월~일 맵으로 승격 저장한 뒤 startTime/endTime을 삭제합니다.',
        progress: 0.3,
      );
      trace.log(
        toActive ? 'Firestore 계정 활성화 transaction을 시작합니다.' : 'Firestore 계정 비활성화 transaction을 시작합니다.',
        progress: 0.5,
      );

      await userState.setSelectedUserActiveStatus(
        toActive,
        onError: (message) {
          statusError = message;
        },
      );

      if (statusError != null) {
        trace.log('활성 상태 변경 실패 응답: $statusError', progress: 0.9);
        await trace.fail(toActive ? '계정 활성화에 실패했습니다.' : '계정 비활성화에 실패했습니다.');
        if (!trace.developerMode && context.mounted) {
          await _showAccountFailureDialog(
            context,
            title: toActive ? '계정 활성화 불가' : '계정 비활성화 불가',
            message: statusError!,
            fallbackDescription: toActive
                ? '계정을 활성화하는 중 문제가 발생했습니다. 선택한 지역의 계정 제한과 네트워크 상태를 확인한 뒤 다시 시도하세요.'
                : '계정을 비활성화하는 중 문제가 발생했습니다. 네트워크 상태를 확인한 뒤 다시 시도하세요.',
          );
        }
        return;
      }

      trace.log(
        '요일별 근무시간 마이그레이션과 활성 상태 변경 및 사용자 캐시 반영이 완료되었습니다.',
        progress: 0.92,
      );
      await trace.succeed(toActive ? '계정 활성화가 완료되었습니다.' : '계정 비활성화가 완료되었습니다.');
    } catch (error, stackTrace) {
      await trace.fail(
        toActive ? '계정 활성화 중 예외가 발생했습니다.' : '계정 비활성화 중 예외가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!trace.developerMode && context.mounted) {
        await _showAccountFailureDialog(
          context,
          title: toActive ? '계정 활성화 불가' : '계정 비활성화 불가',
          message: '${toActive ? '계정 활성화' : '계정 비활성화'} 실패: $error',
          fallbackDescription: toActive
              ? '계정을 활성화하는 중 문제가 발생했습니다. 선택한 지역의 계정 제한과 네트워크 상태를 확인한 뒤 다시 시도하세요.'
              : '계정을 비활성화하는 중 문제가 발생했습니다. 네트워크 상태를 확인한 뒤 다시 시도하세요.',
        );
      }
    } finally {
      if (context.mounted) {
        _clearSelection(userState);
      }
    }
  }

  Future<void> _handleDeleteSelectedUser(BuildContext context) async {
    final userState = context.read<UserState>();
    final selectedId = userState.selectedUserId;
    if (selectedId == null) return;

    final selectedUser =
        userState.users.firstWhereOrNull((user) => user.id == selectedId);
    if (selectedUser == null) {
      _clearSelection(userState, reason: 'delete_target_missing');
      return;
    }

    _log('delete_confirm_opened name=${_maskName(selectedUser.name)}');
    final ok = await _confirmDeleteUser(context);
    if (!ok) {
      _log('delete_cancelled name=${_maskName(selectedUser.name)}');
      return;
    }

    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '계정 삭제',
      initialMessage: '계정 삭제 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 계정 삭제 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 계정 삭제 로그를 콘솔에 기록합니다.',
    );

    String? deleteError;
    try {
      trace.log(
        '삭제 대상 확인: 사용자 ${_maskName(selectedUser.name)}, 전화 ${_maskPhone(selectedUser.phone)}',
        progress: 0.2,
      );
      trace.log('계정 삭제와 사용자 캐시 갱신을 요청합니다.', progress: 0.5);
      await userState.deleteUserCard(
        [selectedId],
        onError: (message) {
          deleteError = message;
        },
      );
      if (deleteError != null) {
        trace.log('계정 삭제 실패 응답: $deleteError', progress: 0.9);
        await trace.fail('계정 삭제에 실패했습니다.');
        if (!trace.developerMode && context.mounted) {
          await _showAccountFailureDialog(
            context,
            title: '계정 삭제 불가',
            message: deleteError!,
            fallbackDescription:
                '계정을 삭제하는 중 문제가 발생했습니다. 네트워크 상태를 확인한 뒤 다시 시도하세요.',
          );
        }
        return;
      }
      trace.log('계정 삭제 및 사용자 캐시 반영 완료', progress: 0.92);
      await trace.succeed('계정 삭제가 완료되었습니다.');
      _log('delete_completed name=${_maskName(selectedUser.name)}');
    } catch (error, stackTrace) {
      await trace.fail(
        '계정 삭제 중 예외가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!trace.developerMode && context.mounted) {
        await _showAccountFailureDialog(
          context,
          title: '계정 삭제 불가',
          message: '계정 삭제 실패: $error',
          fallbackDescription:
              '계정을 삭제하는 중 문제가 발생했습니다. 네트워크 상태를 확인한 뒤 다시 시도하세요.',
        );
      }
    } finally {
      if (context.mounted) {
        _clearSelection(userState, reason: 'delete_finished');
      }
    }
  }

  bool _matchesSearch(UserModel user) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final haystack = <String>[
      user.name,
      user.phone,
      user.email,
      user.role,
      user.position ?? '',
      user.modes.join(' '),
      user.areas.join(' '),
      user.divisions.join(' '),
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }

  bool _matchesStatus(UserModel user) {
    switch (_statusFilter) {
      case _UserStatusFilter.all:
        return true;
      case _UserStatusFilter.active:
        return user.isActive;
      case _UserStatusFilter.inactive:
        return !user.isActive;
    }
  }

  String _maskEmail(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final at = trimmed.indexOf('@');
    if (at <= 0 || at == trimmed.length - 1) {
      return trimmed.length <= 2
          ? List.filled(trimmed.length, '*').join()
          : '${trimmed[0]}***${trimmed[trimmed.length - 1]}';
    }
    final local = trimmed.substring(0, at);
    final domain = trimmed.substring(at + 1);
    final localMasked = local.length <= 1 ? '${local}***' : '${local[0]}***';
    return '$localMasked@$domain';
  }

  Future<void> _selectUser(
    UserState userState,
    UserModel user,
    SecondaryAccountMode mode,
  ) async {
    await HapticFeedback.selectionClick();
    final wasSelected = userState.selectedUserId == user.id;
    await userState.toggleUserCard(user.id);
    _log(
      '${wasSelected ? 'user_deselected' : 'user_selected'} name=${_maskName(user.name)} mode=${mode.name}',
    );
  }

  Widget _buildToolbar(
    BuildContext context, {
    required bool refreshing,
    required bool deleteMode,
  }) {
    return Row(
      children: [
        Expanded(
          child: OpsDockSearchField(
            controller: _searchController,
            query: _query,
            semanticLabel: '계정 검색',
            onChanged: _setQuery,
            onClear: _clearQuery,
          ),
        ),
        const SizedBox(width: 6),
        CommonIconButton(
          icon: Icons.refresh_rounded,
          tooltip: '새로고침',
          onPressed: refreshing ? null : () => _refreshUsersForCurrentArea(context),
          loading: refreshing,
          haptic: CommonHaptic.selection,
          size: 40,
          iconSize: 19,
        ),
        const SizedBox(width: 4),
        AnimatedOpacity(
          duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
              ? Duration.zero
              : CommonUiMotion.selection,
          opacity: deleteMode ? .34 : 1,
          child: CommonIconButton(
            icon: Icons.person_add_alt_1_rounded,
            tooltip: '계정 등록',
            onPressed: deleteMode
                ? null
                : () => _handlePrimaryAction(context, forceCreate: true),
            haptic: CommonHaptic.selection,
            size: 40,
            iconSize: 19,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusSegments({
    required BuildContext context,
    required int totalCount,
    required int activeCount,
    required int inactiveCount,
  }) {
    final tokens = CommonUiTheme.of(context);
    return OpsDockStatusSegments<_UserStatusFilter>(
      selected: _statusFilter,
      items: [
        OpsDockStatusSegmentItem<_UserStatusFilter>(
          value: _UserStatusFilter.all,
          label: '전체',
          count: totalCount,
          color: tokens.accent,
        ),
        OpsDockStatusSegmentItem<_UserStatusFilter>(
          value: _UserStatusFilter.active,
          label: '활성',
          count: activeCount,
          color: tokens.success,
        ),
        OpsDockStatusSegmentItem<_UserStatusFilter>(
          value: _UserStatusFilter.inactive,
          label: '비활성',
          count: inactiveCount,
          color: tokens.iconSecondary,
        ),
      ],
      onSelected: _setStatusFilter,
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required bool scopedEmpty,
    required bool deleteMode,
  }) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final queryActive = _query.trim().isNotEmpty;
    final filtered = _statusFilter != _UserStatusFilter.all;
    final title = scopedEmpty
        ? '등록된 계정이 없습니다'
        : queryActive
            ? '일치하는 계정이 없습니다'
            : filtered
                ? '${_statusFilter == _UserStatusFilter.active ? '활성' : '비활성'} 계정이 없습니다'
                : '표시할 계정이 없습니다';

    Widget? action;
    if (scopedEmpty && !deleteMode) {
      action = CommonButton(
        label: '계정 등록',
        icon: Icons.person_add_alt_1_rounded,
        onPressed: () => _handlePrimaryAction(context, forceCreate: true),
        haptic: CommonHaptic.selection,
        minHeight: 42,
      );
    } else if (queryActive) {
      action = CommonButton(
        label: '검색 초기화',
        icon: Icons.search_off_rounded,
        onPressed: _clearQuery,
        variant: CommonButtonVariant.secondary,
        haptic: CommonHaptic.selection,
        minHeight: 42,
      );
    } else if (filtered) {
      action = CommonButton(
        label: '전체 보기',
        icon: Icons.groups_rounded,
        onPressed: () => _setStatusFilter(_UserStatusFilter.all),
        variant: CommonButtonVariant.secondary,
        haptic: CommonHaptic.selection,
        minHeight: 42,
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              alignment: Alignment.center,
              child: Icon(
                queryActive ? Icons.person_search_rounded : Icons.group_off_rounded,
                color: tokens.iconSecondary,
                size: 22,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: action,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUserList(
    BuildContext context, {
    required UserState userState,
    required List<UserModel> users,
    required SecondaryAccountMode mode,
  }) {
    final tokens = CommonUiTheme.of(context);
    return OpsDockListSurface(
      child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: users.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            thickness: 1,
            color: tokens.borderSubtle,
          ),
          itemBuilder: (context, index) {
            final user = users[index];
            return _UserDockRow(
              key: ValueKey<String>(user.id),
              name: _maskName(user.name),
              phone: _maskPhone(user.phone),
              email: _maskEmail(user.email),
              role: user.role,
              position: user.position ?? '',
              modes: user.modes,
              active: user.isActive,
              selected: userState.selectedUserId == user.id,
              deleteMode: mode == SecondaryAccountMode.delete,
              onTap: () {
                unawaited(_selectUser(userState, user, mode));
              },
            );
          },
      ),
    );
  }

  Widget _buildContextFooter(
    BuildContext context, {
    required UserModel? selectedUser,
    required SecondaryAccountMode mode,
  }) {
    if (selectedUser == null) {
      return const SizedBox.shrink(key: ValueKey<String>('footer_none'));
    }

    if (mode == SecondaryAccountMode.delete) {
      return OpsDockContextFooter(
        key: const ValueKey<String>('footer_delete'),
        children: [
          Expanded(
            child: CommonButton(
              label: '계정 삭제',
              icon: Icons.delete_forever_rounded,
              onPressed: () => _handleDeleteSelectedUser(context),
              variant: CommonButtonVariant.destructive,
              haptic: CommonHaptic.medium,
              minHeight: 42,
              expand: true,
            ),
          ),
        ],
      );
    }

    return OpsDockContextFooter(
      key: ValueKey<String>('footer_operation_${selectedUser.isActive}'),
      children: [
        Expanded(
          child: CommonButton(
            label: '수정',
            icon: Icons.edit_rounded,
            onPressed: () => _handlePrimaryAction(context),
            variant: CommonButtonVariant.secondary,
            haptic: CommonHaptic.selection,
            minHeight: 42,
            expand: true,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: CommonButton(
            label: selectedUser.isActive ? '비활성화' : '활성화',
            icon: selectedUser.isActive
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_fill_rounded,
            onPressed: () => _handleToggleActive(context),
            variant: selectedUser.isActive
                ? CommonButtonVariant.destructive
                : CommonButtonVariant.primary,
            haptic: selectedUser.isActive
                ? CommonHaptic.medium
                : CommonHaptic.selection,
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
    final textTheme = Theme.of(context).textTheme;
    final media = MediaQuery.maybeOf(context);
    final reduceMotion = media?.disableAnimations ?? false;
    final userState = context.watch<UserState>();
    final areaState = context.watch<AreaState>();
    final workspace = context.watch<SecondaryAccountWorkspaceState>();
    final currentArea = areaState.currentArea.trim();
    final currentDivision = areaState.currentDivision.trim();

    bool inCurrentScope(UserModel user) {
      final areaOk = currentArea.isEmpty || user.areas.contains(currentArea);
      final divisionOk =
          currentDivision.isEmpty || user.divisions.contains(currentDivision);
      return areaOk && divisionOk;
    }

    final scopedUsers = userState.users.where(inCurrentScope).toList();
    final visibleUsers =
        scopedUsers.where(_matchesStatus).where(_matchesSearch).toList();
    final activeCount = scopedUsers.where((user) => user.isActive).length;
    final inactiveCount = scopedUsers.length - activeCount;
    final selectedUser = visibleUsers.firstWhereOrNull(
      (user) => user.id == userState.selectedUserId,
    );
    final initialLoading = userState.isLoading && scopedUsers.isEmpty;
    final refreshing = _refreshing || (userState.isLoading && !initialLoading);
    final deleteMode = workspace.mode == SecondaryAccountMode.delete;

    _scheduleSelectionValidation(userState, scopedUsers, visibleUsers);

    final listBody = initialLoading
        ? const SizedBox.expand(key: ValueKey<String>('initial_loading'))
        : visibleUsers.isEmpty
            ? KeyedSubtree(
                key: ValueKey<String>(
                  'empty_${scopedUsers.isEmpty}_${_query.trim().isNotEmpty}_${_statusFilter.name}',
                ),
                child: _buildEmptyState(
                  context,
                  scopedEmpty: scopedUsers.isEmpty,
                  deleteMode: deleteMode,
                ),
              )
            : KeyedSubtree(
                key: ValueKey<String>(
                  'account_list_${_statusFilter.name}_${_query.trim().toLowerCase()}_${visibleUsers.length}',
                ),
                child: _buildUserList(
                  context,
                  userState: userState,
                  users: visibleUsers,
                  mode: workspace.mode,
                ),
              );

    return Material(
      color: tokens.canvas,
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: _buildToolbar(
                  context,
                  refreshing: refreshing,
                  deleteMode: deleteMode,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: _buildStatusSegments(
                  context: context,
                  totalCount: scopedUsers.length,
                  activeCount: activeCount,
                  inactiveCount: inactiveCount,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                child: Row(
                  children: [
                    Text(
                      '${visibleUsers.length}명 표시',
                      style: textTheme.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration:
                          reduceMotion ? Duration.zero : CommonUiMotion.selection,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: .96, end: 1).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Icon(
                        deleteMode
                            ? Icons.delete_sweep_rounded
                            : Icons.admin_panel_settings_rounded,
                        key: ValueKey<SecondaryAccountMode>(workspace.mode),
                        size: 16,
                        color: deleteMode ? tokens.danger : tokens.success,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  child: OpsDockResultSwitcher(child: listBody),
                ),
              ),
              OpsDockContextFooterTransition(
                child: _buildContextFooter(
                  context,
                  selectedUser: selectedUser,
                  mode: workspace.mode,
                ),
              ),
            ],
          ),
          OpsDockLoadingOverlay(loading: initialLoading),
        ],
      ),
    );
  }
}

class _UserDockRow extends StatelessWidget {
  const _UserDockRow({
    super.key,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    required this.position,
    required this.modes,
    required this.active,
    required this.selected,
    required this.deleteMode,
    required this.onTap,
  });

  final String name;
  final String phone;
  final String email;
  final String role;
  final String position;
  final List<String> modes;
  final bool active;
  final bool selected;
  final bool deleteMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selectionColor = deleteMode ? tokens.danger : tokens.accent;
    final selectedContainer =
        deleteMode ? tokens.dangerContainer : tokens.accentContainer;
    final rolePosition = [
      if (role.trim().isNotEmpty) role.trim(),
      if (position.trim().isNotEmpty) position.trim(),
    ].join(' · ');
    final modeText = modes.isEmpty ? '모드 없음' : modes.join(' · ');

    return OpsDockSelectableRowSurface(
      selected: selected,
      selectionColor: selectionColor,
      selectedContainer: selectedContainer,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? tokens.success : tokens.iconDisabled,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  name.isEmpty ? '이름 없음' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                active ? '활성' : '비활성',
                style: textTheme.labelSmall?.copyWith(
                  color: active ? tokens.success : tokens.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 5),
              AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                ),
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  key: ValueKey<bool>(selected),
                  size: 18,
                  color: selected ? selectionColor : tokens.iconSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            rolePosition.isEmpty ? '역할 없음' : rolePosition,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            phone.isEmpty ? '전화 미등록' : phone,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (selected) ...[
            const SizedBox(height: 8),
            Container(height: 1, color: tokens.borderSubtle),
            const SizedBox(height: 7),
            Text(
              email.isEmpty ? '이메일 미등록' : email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              modeText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
