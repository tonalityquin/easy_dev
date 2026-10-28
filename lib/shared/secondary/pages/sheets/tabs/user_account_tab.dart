import '../../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../../features/account/presentation/widgets/permission_detail_list.dart';
import 'package:provider/provider.dart';
import '../../../../../features/account/domain/models/account_permission_policy.dart';
import '../../../../../features/account/data/services/company_grade_policy_service.dart';
import '../../../application/account_assignment_resolver.dart';
import '../../../application/account_primary_assignment.dart';
import 'package:flutter/services.dart';

import '../../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../../app/utils/status_dialog.dart';
import '../../../data/services/dev_user_write_service.dart';
import '../../../../../features/account/domain/models/user/user_model.dart';
import '../../../../../features/dev/application/account_group_authorization.dart';
import '../../../../../features/account/data/services/company_bootstrap_service.dart';
import '../../../../../features/selector/application/dev_auth.dart';
import '../../../../../features/account/applications/user_state.dart';
import '../../../../../shared/auth/account_code_number.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../widgets/ops_console_widgets.dart';
import 'account_grade_policy_dialog.dart';
import 'document_access_policy_dialog.dart';


class UserAccountsTab extends StatefulWidget {
  final String? selectedDivision;
  final String? selectedArea;
  final List<String> divisionList;
  final ValueChanged<String?> onDivisionChanged;
  final ValueChanged<String?> onAreaChanged;

  const UserAccountsTab({
    super.key,
    required this.selectedDivision,
    required this.selectedArea,
    required this.divisionList,
    required this.onDivisionChanged,
    required this.onAreaChanged,
  });

  @override
  State<UserAccountsTab> createState() => _UserAccountsTabState();
}

class _UserAccountsTabState extends State<UserAccountsTab> {
  bool _groupAuthorized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshGroupAuthorization(source: 'secondary_user_tab_init');
      }
    });
  }

  Future<bool> _refreshGroupAuthorization({
    required String source,
    bool showStatus = false,
  }) async {
    final approved = showStatus
        ? await AccountGroupAuthorization.verifyWithStatus(
            context,
            source: source,
          )
        : await AccountGroupAuthorization.verify(source: source);
    if (mounted && _groupAuthorized != approved) {
      setState(() => _groupAuthorized = approved);
    }
    return approved;
  }

  List<String> _assignablePermissions(UserState actor) {
    if (!actor.hasPermission('accounts.grantPermissions')) {
      return const <String>[];
    }
    return (AccountPermissionPolicy.generalPermissionKeys.intersection(actor.permissionKeys).toList()..sort());
  }

  String? _validatePermissionChange(
    UserState actor, {
    required Iterable<String> permissions,
    required String division,
    required String area,
    Map<String, dynamic>? previous,
  }) {
    final oldPermissions = List<String>.from(previous?['permissionKeys'] ?? const <String>[]);
    final nextPermissions = AccountPermissionPolicy.sanitize(permissions);
    final scopes = AccountPermissionPolicy.validateAssignments(
      actorPermissions: actor.permissionKeys,
      actorDivisions: actor.assignedDivisions,
      actorAreas: actor.assignedAreas,
      newDivisions: <String>[division],
      newAreas: <String>[area],
    );
    if (scopes != null) return scopes;
    return AccountPermissionPolicy.validateChange(
      actorPermissions: actor.permissionKeys,
      previousPermissions: oldPermissions,
      nextPermissions: nextPermissions,
      isCreating: previous == null,
      changesPermissions: previous == null && nextPermissions.isNotEmpty ||
          oldPermissions.toSet().difference(nextPermissions).isNotEmpty ||
          nextPermissions.difference(oldPermissions.toSet()).isNotEmpty,
    );
  }

  final Map<String, Map<String, dynamic>> _editedUsers = <String, Map<String, dynamic>>{};
  final DevUserWriteService _devUserWriteService = DevUserWriteService();
  final Map<String, Future<List<String>>> _primaryAreaFutures = <String, Future<List<String>>>{};
  final Map<String, Future<Map<String, CompanyGradePolicy>>> _gradePolicyFutures =
      <String, Future<Map<String, CompanyGradePolicy>>>{};
  final Set<String> _savingIds = <String>{};
  bool _creating = false;
  String? _selectedUserId;
  int _refreshTick = 0;
  String? _scopeAreasDivision;
  Future<List<String>>? _scopeAreasFuture;

  Future<bool> _isManualCodeAuthorized({bool interactive = false}) async {
    return _refreshGroupAuthorization(
      source: interactive
          ? 'secondary_user_manual_code_interactive'
          : 'secondary_user_manual_code',
      showStatus: interactive,
    );
  }

  Map<String, dynamic> _normalizedWeekMapFromData(
    Map<String, dynamic> data,
    String mapKey,
    String legacyKey,
  ) {
    final raw = data[mapKey];
    if (raw is Map) {
      return <String, dynamic>{
        for (final day in _CreateUserAccountDraft.weekdays) day: raw[day],
      };
    }

    final holidays = List<String>.from(data['fixedHolidays'] ?? const <String>[])
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final legacy = data[legacyKey];
    return <String, dynamic>{
      for (final day in _CreateUserAccountDraft.weekdays)
        day: holidays.contains(day) ? null : legacy,
    };
  }

  Map<String, dynamic> _copyUser(
    Map<String, dynamic> d, {
    String? primaryDivision,
    String? primaryArea,
  }) {
    final startByWeekday = _normalizedWeekMapFromData(
      d,
      'startTimeByWeekday',
      'startTime',
    );
    final endByWeekday = _normalizedWeekMapFromData(
      d,
      'endTimeByWeekday',
      'endTime',
    );
    final fixedHolidays = <String>[
      for (final day in _CreateUserAccountDraft.weekdays)
        if (startByWeekday[day] == null && endByWeekday[day] == null) day,
    ];
    final rawBreakDays = d['breakDays'];
    final breakDays = rawBreakDays is Iterable
        ? rawBreakDays
            .map((value) => value.toString().trim())
            .where(
              (day) => _CreateUserAccountDraft.weekdays.contains(day),
            )
            .toSet()
            .toList(growable: false)
        : <String>[
            for (final day in _CreateUserAccountDraft.weekdays)
              if (startByWeekday[day] != null && endByWeekday[day] != null) day,
          ];
    final divisions = List<String>.from(d['divisions'] ?? const <String>[]);
    final areas = List<String>.from(d['areas'] ?? const <String>[]);
    final storedPrimaryDivision = (d['companyId'] ?? d['_primaryDivision'] ?? '').toString().trim();
    final resolvedPrimaryDivision = (primaryDivision ?? '').trim().isNotEmpty
        ? primaryDivision!.trim()
        : storedPrimaryDivision.isNotEmpty
            ? storedPrimaryDivision
            : '';
    final hasCurrentAreaKey = d.containsKey('currentArea');
    final storedCurrentArea = hasCurrentAreaKey ? (d['currentArea'] ?? '').toString().trim() : '';
    final storedSelectedArea = (d['selectedArea'] ?? '').toString().trim();
    final resolvedPrimaryArea = (primaryArea ?? '').trim().isNotEmpty
        ? primaryArea!.trim()
        : hasCurrentAreaKey
            ? storedCurrentArea
            : storedSelectedArea.isNotEmpty
                ? storedSelectedArea
                : areas.isNotEmpty
                    ? areas.first.trim()
                    : '';
    return <String, dynamic>{
      'name': d['name'] ?? '',
      'codeNumber': d['codeNumber'] ?? d['phone'] ?? '',
      'email': d['email'] ?? '',
      'divisions': divisions,
      'areas': areas,
      'permissionKeys': d['permissionKeys'] ?? const <String>[],
      'accountGradeId': d['accountGradeId'] ?? '',
      'modes': List<String>.from(d['modes'] ?? const <String>[]),
      'position': d['position'] ?? '',
      'currentArea': resolvedPrimaryArea.isEmpty ? null : resolvedPrimaryArea,
      'selectedArea': resolvedPrimaryArea.isEmpty ? null : resolvedPrimaryArea,
      '_primaryDivision': resolvedPrimaryDivision,
      '_retainPreviousPrimary': d['_retainPreviousPrimary'] == true,
      'englishSelectedAreaName': d['englishSelectedAreaName'],
      'startTimeByWeekday': startByWeekday,
      'endTimeByWeekday': endByWeekday,
      'fixedHolidays': fixedHolidays,
      'breakDays': breakDays,
      'isSaved': d['isSaved'] ?? false,
      'isSelected': d['isSelected'] ?? false,
      'isWorking': d['isWorking'] ?? false,
      'isActive': d['isActive'] ?? true,
      'createdAt': d['createdAt'],
      'updatedAt': d['updatedAt'],
    };
  }

  Future<List<String>> getAreasByDivisions(List<String> divisions) async {
    final relations = await AccountAssignmentResolver.load(divisions);
    return relations.entries
        .where((entry) => entry.value.length == 1)
        .map((entry) => entry.key)
        .toList(growable: false)
      ..sort();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _fetchAreasForDivision(
    String division,
  ) async {
    final qs = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => FirebaseFirestore.instance
        .collection('areas')
        .where('division', isEqualTo: division)
        .get(const GetOptions(source: Source.serverAndCache)), source: 'user_account_tab.get');

    return qs;
  }

  Future<List<String>> _fetchAreaNamesForDivision(String division) async {
    final snapshot = await _fetchAreasForDivision(division);
    return snapshot.docs
        .map((doc) => (doc.data()['name'] ?? '').toString().trim())
        .where((area) => area.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Future<List<String>> _scopeAreaNames(String division) {
    if (_scopeAreasDivision != division || _scopeAreasFuture == null) {
      _scopeAreasDivision = division;
      _scopeAreasFuture = _fetchAreaNamesForDivision(division);
    }
    return _scopeAreasFuture!;
  }

  Future<List<String>> _primaryAreaNames(String division) {
    final cached = _primaryAreaFutures[division];
    if (cached != null) return cached;
    final future = _fetchAreaNamesForDivision(division).catchError(
      (Object error, StackTrace stackTrace) {
        _primaryAreaFutures.remove(division);
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _primaryAreaFutures[division] = future;
    return future;
  }

  List<String> _withPrimaryFirst(List<String> source, String primary) {
    final normalized = source
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && value != primary)
        .toSet()
        .toList(growable: true);
    normalized.insert(0, primary);
    return normalized;
  }

  String _primaryDivisionOf(Map<String, dynamic> data) {
    final explicit = (data['companyId'] ?? data['_primaryDivision'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;
    return '';
  }

  String _primaryAreaOf(Map<String, dynamic> data) {
    final current = (data['currentArea'] ?? '').toString().trim();
    if (current.isNotEmpty) return current;
    final selected = (data['selectedArea'] ?? '').toString().trim();
    if (selected.isNotEmpty) return selected;
    return '';
  }

  @override
  void didUpdateWidget(covariant UserAccountsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDivision != widget.selectedDivision) {
      _scopeAreasDivision = null;
      _scopeAreasFuture = null;
      _selectedUserId = null;
      _primaryAreaFutures.clear();
    }
  }

  Future<String?> _fetchEnglishNameByArea(String division, String area) async {
    final docId = '${division.trim()}-${area.trim()}';
    try {
      final snap = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => FirebaseFirestore.instance
          .collection('areas')
          .doc(docId)
          .get(const GetOptions(source: Source.server)), source: 'user_account_tab.get');


      final data = snap.data();
      final englishName = (data?['englishName'] ?? '').toString().trim();
      return englishName.isEmpty ? null : englishName;
    } catch (_) {
      return null;
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _fetchUsersForArea(
    String division,
    String area,
  ) async {
    final showId = _showDocId(division, area);
    return FirebaseActivityMonitor.track(
      FirebaseActivityKind.read,
      () => FirebaseFirestore.instance
          .collection('user_accounts_show')
          .doc(showId)
          .collection('users')
          .get(const GetOptions(source: Source.serverAndCache)),
      source: 'accounts.display.fetch',
    );
  }

  String _showDocId(String? division, String? area) {
    final d = (division ?? '').trim().isEmpty ? 'unknownDivision' : (division ?? '').trim();
    final a = (area ?? '').trim().isEmpty ? 'unknownArea' : (area ?? '').trim();
    return '$d-$a';
  }

  String? _limitValueFromError(Object e, String key) {
    final raw = e.toString();
    final idx = raw.indexOf(key);
    if (idx < 0) return null;
    final rest = raw.substring(idx + key.length).trim();
    final end = rest.indexOf(RegExp(r'[^0-9]'));
    final value = end < 0 ? rest : rest.substring(0, end);
    return value.trim().isEmpty ? null : value.trim();
  }

  String? _activeLimitFromError(Object e) {
    return _limitValueFromError(e, 'ACTIVE_LIMIT_REACHED:');
  }

  String? _totalLimitFromError(Object e) {
    return _limitValueFromError(e, 'TOTAL_LIMIT_REACHED:');
  }

  Future<void> _showAccountLimitFailureDialog(
    Object e, {
    required String fallbackTitle,
    required String activeTitle,
    required String totalTitle,
  }) async {
    final raw = e.toString();
    if (raw.contains('MANUAL_CODE_NOT_AUTHORIZED')) {
      await StatusDialog.showFailure(
        context,
        title: '개발자 인증이 필요합니다',
        description: '개발자 모드와 개발자 계정 인증 상태를 확인한 뒤 다시 시도하세요.',
        useCommonUi: true,
      );
      return;
    }
    if (raw.contains('MANUAL_CODE_INVALID')) {
      await StatusDialog.showFailure(
        context,
        title: '코드번호를 확인하세요',
        description: '직접 입력 코드번호는 숫자 11자리여야 합니다.',
        useCommonUi: true,
      );
      return;
    }
    if (raw.contains('CODE_NUMBER_ALREADY_EXISTS') ||
        raw.contains('USER_ALREADY_EXISTS') ||
        raw.contains('SHOW_USER_ALREADY_EXISTS')) {
      await StatusDialog.showFailure(
        context,
        title: '동일 계정이 이미 존재합니다',
        description: '같은 계정 ID 또는 동일 지역 projection이 이미 존재합니다. 코드번호와 현재 지역을 확인하세요.',
        useCommonUi: true,
      );
      return;
    }
    if (raw.contains('USER_NOT_FOUND')) {
      await StatusDialog.showFailure(
        context,
        title: '원본 계정을 찾지 못했습니다',
        description: '계정 목록을 새로 불러온 뒤 다시 수정하세요.',
        useCommonUi: true,
      );
      return;
    }
    if (raw.contains('ACCOUNT_LIMIT_NOT_CONFIGURED')) {
      await StatusDialog.showFailure(
        context,
        title: '계정 리밋 설정 필요',
        description: '선택한 지역의 activeLimit과 totalLimit이 설정되지 않았습니다. 리밋 관리에서 두 값을 저장한 뒤 다시 시도하세요.',
        useCommonUi: true,
      );
      return;
    }
    final activeLimit = _activeLimitFromError(e);
    if (activeLimit != null) {
      await StatusDialog.showFailure(
        context,
        title: activeTitle,
        description:
            '선택한 지역의 활성 계정 한도에 도달했습니다. 활성 계정은 최대 ${activeLimit}개까지만 사용할 수 있습니다. 기존 활성 계정을 비활성화하거나 리밋 설정에서 활성 한도를 늘린 뒤 다시 시도하세요.',
        useCommonUi: true,
      );
      return;
    }

    final totalLimit = _totalLimitFromError(e);
    if (totalLimit != null) {
      await StatusDialog.showFailure(
        context,
        title: totalTitle,
        description:
            '선택한 지역의 전체 계정 생성 한도에 도달했습니다. 활성 계정과 비활성 계정을 합쳐 최대 ${totalLimit}개까지만 생성할 수 있습니다. 기존 계정을 삭제하거나 리밋 설정에서 전체 한도를 늘린 뒤 다시 시도하세요.',
        useCommonUi: true,
      );
      return;
    }

    await StatusDialog.showFailure(
      context,
      title: fallbackTitle,
      description: '계정 정보를 저장하는 중 문제가 발생했습니다. 입력값과 네트워크 상태를 확인한 뒤 다시 시도하세요.',
      useCommonUi: true,
    );
  }

  Future<void> _saveChanges(
    String oldId,
    Map<String, dynamic> oldData,
    Map<String, dynamic> newData,
  ) async {
    final primaryDivision = _primaryDivisionOf(newData);
    final primaryArea = _primaryAreaOf(newData);
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '운영 계정 수정',
      initialMessage: '운영 계정 수정 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 운영 계정 수정 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 운영 계정 수정 로그를 콘솔에 기록합니다.',
    );

    try {
      final approved = await _refreshGroupAuthorization(
        source: 'secondary_user_update',
      );
      trace.log('server_access_gate approved=$approved');
      if (!approved) throw StateError('GROUP_ACCESS_DENIED');
      final actorForWrite = context.read<UserState>();
      if (!actorForWrite.hasPermission('accounts.update')) {
        await CompanyBootstrapService.requireDeveloper(
          source: 'secondary_user_account_write',
          forceAccountSelection: false,
        );
      }
      trace.log('server_account_write_gate_approved');
      final actor = context.read<UserState>();
      if (oldData['isInitialAdmin'] != true) {
        final gradeId = (newData['accountGradeId'] ?? '').toString();
        final companyId = (newData['companyId'] ?? oldData['companyId'] ?? '').toString();
        final policy = await CompanyGradePolicyService().load(companyId, gradeId);
        newData['permissionKeys'] = policy.permissionKeys.toList(growable: false)..sort();
        trace.log('현재 회사 등급 정책 적용: company=$companyId grade=$gradeId version=${policy.version} permissions=${policy.permissionKeys.length}');
      }
      final permissionKeys = AccountPermissionPolicy.sanitize(
          List<String>.from(newData['permissionKeys'] ?? const <String>[]));
      final previousDivision = (widget.selectedDivision ?? '').trim();
      final previousArea = (widget.selectedArea ?? '').trim();
      final oldDivisions = _withPrimaryFirst(
        List<String>.from(oldData['divisions'] ?? const <String>[]),
        previousDivision,
      );
      final oldAreas = _withPrimaryFirst(
        List<String>.from(oldData['areas'] ?? const <String>[]),
        previousArea,
      );
      final retainPreviousPrimary = newData['_retainPreviousPrimary'] == true;
      final changedPrimary = AccountPrimaryAssignment.primaryChanged(
        oldDivision: previousDivision,
        oldArea: previousArea,
        newDivision: primaryDivision,
        newArea: primaryArea,
      );
      var nextDivisions = AccountPrimaryAssignment.replacePrimary(
        existing: List<String>.from(newData['divisions'] ?? const <String>[]),
        previousPrimary: previousDivision,
        nextPrimary: primaryDivision,
        retainPreviousPrimary: retainPreviousPrimary,
      );
      final nextAreas = AccountPrimaryAssignment.replacePrimary(
        existing: List<String>.from(newData['areas'] ?? const <String>[]),
        previousPrimary: previousArea,
        nextPrimary: primaryArea,
        retainPreviousPrimary: retainPreviousPrimary,
      );
      final assignmentsChanged =
          !AccountPermissionPolicy.normalizedAssignments(nextDivisions)
              .containsAll(AccountPermissionPolicy.normalizedAssignments(oldDivisions)) ||
          !AccountPermissionPolicy.normalizedAssignments(oldDivisions)
              .containsAll(AccountPermissionPolicy.normalizedAssignments(nextDivisions)) ||
          !AccountPermissionPolicy.normalizedAssignments(nextAreas)
              .containsAll(AccountPermissionPolicy.normalizedAssignments(oldAreas)) ||
          !AccountPermissionPolicy.normalizedAssignments(oldAreas)
              .containsAll(AccountPermissionPolicy.normalizedAssignments(nextAreas));
      final relations = assignmentsChanged || changedPrimary
          ? await AccountAssignmentResolver.load(<String>{...nextDivisions, ...oldDivisions})
          : <String, Set<String>>{};
      if (relations.isNotEmpty) {
        final supportingDivisions = <String>{...nextDivisions};
        for (final assignedArea in nextAreas) {
          final related = relations[assignedArea] ?? const <String>{};
          final covered = related.intersection(supportingDivisions);
          if (covered.isNotEmpty) continue;
          if (related.length == 1 && oldDivisions.contains(related.first)) {
            supportingDivisions.add(related.first);
          }
        }
        nextDivisions = AccountPrimaryAssignment.replacePrimary(
          existing: supportingDivisions,
          previousPrimary: primaryDivision,
          nextPrimary: primaryDivision,
        );
      }
      final assignmentDenied = AccountPermissionPolicy.validateAssignments(
        actorPermissions: actor.permissionKeys,
        actorDivisions: actor.assignedDivisions,
        actorAreas: actor.assignedAreas,
        newDivisions: nextDivisions,
        newAreas: nextAreas,
      );
      trace.log('primary_assignment_check old=$previousDivision/$previousArea new=$primaryDivision/$primaryArea moved=$changedPrimary retainOld=$retainPreviousPrimary');
      trace.log('assignment_list_check allowed=${assignmentDenied == null} reason=${assignmentDenied ?? 'ok'} divisions=${nextDivisions.length} areas=${nextAreas.length}');
      if (assignmentDenied != null) throw StateError(assignmentDenied);
      final oldGrade = (oldData['accountGradeId'] ?? '').toString();
      final nextGrade = (newData['accountGradeId'] ?? '').toString();
      final validationPrevious = oldGrade == nextGrade &&
              oldData['isInitialAdmin'] != true
          ? <String, dynamic>{...oldData, 'permissionKeys': permissionKeys.toList()}
          : oldData;
      final denied = _validatePermissionChange(
        actor,
        permissions: permissionKeys,
        division: primaryDivision,
        area: primaryArea,
        previous: validationPrevious,
      );
      trace.log('permission_policy_update allowed=${denied == null} reason=${denied ?? 'ok'}');
      if (denied != null) throw StateError(denied);
      if (primaryDivision.isEmpty || primaryArea.isEmpty) {
        throw StateError('PRIMARY_ASSIGNMENT_REQUIRED');
      }
      final validAreas = await _primaryAreaNames(primaryDivision);
      if (!validAreas.contains(primaryArea)) {
        throw StateError('PRIMARY_AREA_NOT_IN_DIVISION');
      }

      var codeNumber = AccountCodeNumber.normalize(
        (oldData['codeNumber'] ?? oldData['phone'] ?? '').toString(),
      );
      if (!AccountCodeNumber.isValid(codeNumber)) {
        codeNumber = AccountCodeNumber.generate();
        trace.log(
          '유효하지 않은 기존 식별값을 새 코드번호로 교체합니다. code=${AccountCodeNumber.mask(codeNumber)}',
          progress: 0.12,
        );
      }
      final newId = AccountCodeNumber.documentId(
        codeNumber: codeNumber,
        area: primaryArea,
      );
      newData['codeNumber'] = codeNumber;
      newData.remove('phone');
      final englishName = await _fetchEnglishNameByArea(primaryDivision, primaryArea) ?? primaryArea;
      final normalizedNewData = Map<String, dynamic>.from(newData);
      normalizedNewData['divisions'] = nextDivisions;
      normalizedNewData['areas'] = nextAreas;
      normalizedNewData['currentArea'] = primaryArea;
      normalizedNewData['selectedArea'] = primaryArea;
      normalizedNewData['englishSelectedAreaName'] = englishName;
      normalizedNewData['permissionKeys'] = permissionKeys.toList(growable: false);
      normalizedNewData['accountGradeId'] = newData['accountGradeId'] ?? oldData['accountGradeId'] ?? ''; 
      normalizedNewData['companyId'] = (oldData['companyId'] ?? primaryDivision).toString();
      normalizedNewData.remove('role');
      normalizedNewData.remove('roleProfileId');
      normalizedNewData.remove('managementScopeType');
      normalizedNewData.remove('_primaryDivision');
      normalizedNewData.remove('_retainPreviousPrimary');

      final user = UserModel.fromMap(newId, normalizedNewData);
      trace.log(
        'permission_policy_update count=${user.permissionKeys.length}',
      );
      trace.log(
        '현재 소속 검증 완료: division=$primaryDivision area=$primaryArea oldId=$oldId newId=$newId',
        progress: 0.18,
      );
      trace.log(
        'DevUserWriteService 전용 경로로 원본/projection/count/limit 업데이트를 요청합니다. breakDays=${user.breakDays.join(',')}',
        progress: 0.38,
      );
      if (previousDivision.isEmpty || previousArea.isEmpty) {
        throw StateError('PREVIOUS_PRIMARY_ASSIGNMENT_REQUIRED');
      }
      await _devUserWriteService.updateUser(
        user: user,
        previousUserId: oldId,
        previousDivision: previousDivision,
        previousArea: previousArea,
        targetDivision: primaryDivision,
        targetArea: primaryArea,
        log: (message) => trace.log(message),
      );
      trace.log('DevUserWriteService 계정 수정 완료', progress: 0.92);
      await trace.succeed('운영 계정 수정이 완료되었습니다.');
      if (!mounted) return;

      if (widget.selectedDivision != primaryDivision) {
        widget.onDivisionChanged(primaryDivision);
      }
      if (widget.selectedArea != primaryArea) {
        widget.onAreaChanged(primaryArea);
      }
      if (!trace.developerMode) {
        await StatusDialog.showSuccess(
          context,
          title: StatusDialog.userAccountSaveSuccess,
          useCommonUi: true,
        );
      }
      if (!mounted) return;
      setState(() {
        _editedUsers.remove(oldId);
        _editedUsers.remove(newId);
        _selectedUserId = null;
        _refreshTick++;
      });
    } catch (e, st) {
      debugPrint('❌ 계정 저장 실패: $e');
      await trace.fail(
        '운영 계정 수정 중 예외가 발생했습니다.',
        error: e,
        stackTrace: st,
      );
      if (!mounted || trace.developerMode) return;
      if (e.toString().contains('PRIMARY_ASSIGNMENT_REQUIRED') ||
          e.toString().contains('PREVIOUS_PRIMARY_ASSIGNMENT_REQUIRED') ||
          e.toString().contains('PRIMARY_AREA_NOT_IN_DIVISION')) {
        await StatusDialog.showFailure(
          context,
          title: '현재 소속을 확인하세요',
          description: '현재 회사와 해당 회사에 속한 현재 지역을 선택한 뒤 다시 저장하세요.',
          useCommonUi: true,
        );
        return;
      }
      await _showAccountLimitFailureDialog(
        e,
        fallbackTitle: StatusDialog.userAccountSaveFailed,
        activeTitle: '계정 저장 불가',
        totalTitle: '계정 저장 불가',
      );
    }
  }

  Future<void> _openCreateDialog(List<String> divisionList) async {
    if (_creating) return;
    final groupApproved = await AccountGroupAuthorization.verifyWithStatus(
      context,
      source: 'secondary_user_open_create',
    );
    if (!mounted || !groupApproved) return;
    if (_groupAuthorized != groupApproved) {
      setState(() => _groupAuthorized = groupApproved);
    }
    final manualCodeAllowed = await _isManualCodeAuthorized();
    if (!mounted) return;
    final actor = context.read<UserState>();
    final assignablePermissions = _assignablePermissions(actor);
    if (!actor.hasPermission('accounts.create')) {
      await StatusDialog.showFailure(
        context,
        title: '계정 생성 권한 없음',
        description: '계정 생성 권한이 확인되지 않았습니다.',
        useCommonUi: true,
      );
      return;
    }

    final draft = await showCommonOverlayDialog<_CreateUserAccountDraft>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _CreateUserAccountDialog(
        divisionList: divisionList,
        permissionList: assignablePermissions,
        initialDivision: widget.selectedDivision,
        initialArea: widget.selectedArea,
        manualCodeAllowed: manualCodeAllowed,
        groupApproved: _groupAuthorized,
        onRequestManualCodeEntry: () =>
            _isManualCodeAuthorized(interactive: true),
        fetchAreasForDivision: _fetchAreaNamesForDivision,
      ),
    );

    if (draft == null) return;
    await _createAccount(draft);
  }

  Future<void> _createAccount(_CreateUserAccountDraft draft) async {
    if (_creating) return;
    setState(() => _creating = true);
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '운영 계정 생성',
      initialMessage: '운영 계정 생성 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 운영 계정 생성 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 운영 계정 생성 로그를 콘솔에 기록합니다.',
    );

    trace.log('passwordPolicy=manual_firestore_only appPasswordWrite=false');

    try {
      final approved = await _refreshGroupAuthorization(
        source: 'secondary_user_create',
      );
      trace.log('server_access_gate approved=$approved');
      if (!approved) throw StateError('GROUP_ACCESS_DENIED');
      final actorForWrite = context.read<UserState>();
      if (!actorForWrite.hasPermission('accounts.create')) {
        await CompanyBootstrapService.requireDeveloper(
          source: 'secondary_user_account_write',
          forceAccountSelection: false,
        );
      }
      trace.log('server_account_write_gate_approved');
      final actor = context.read<UserState>();
      final livePolicy = await CompanyGradePolicyService()
          .load(draft.division, draft.accountGradeId);
      final currentPermissions = livePolicy.permissionKeys;
      trace.log('현재 등급 정책 조회: grade=${draft.accountGradeId} version=${livePolicy.version} count=${currentPermissions.length}');
      final denied = _validatePermissionChange(
        actor,
        permissions: currentPermissions,
        division: draft.division,
        area: draft.area,
      );
      trace.log('permission_policy_create allowed=${denied == null} reason=${denied ?? 'ok'}');
      if (denied != null) throw StateError(denied);
      if (draft.codeEntryMode == UserCodeEntryMode.developerManual) {
        final authorized = await _isManualCodeAuthorized();
        if (!authorized) {
          throw StateError('MANUAL_CODE_NOT_AUTHORIZED');
        }
        if (!AccountCodeNumber.isDeveloperManualCode(draft.codeNumber)) {
          throw StateError('MANUAL_CODE_INVALID');
        }
      }
      trace.log(
        '코드번호 할당 방식 확인: mode=${draft.codeEntryMode.name} code=${AccountCodeNumber.mask(draft.codeNumber)}',
        progress: 0.1,
      );
      final englishName = await _fetchEnglishNameByArea(draft.division, draft.area) ?? draft.area;
      trace.log(
        'permission_policy_create count=${currentPermissions.length}',
      );
      final user = UserModel(
        id: draft.documentId,
        areas: <String>[draft.area],
        currentArea: draft.area,
        divisions: <String>[draft.division],
        modes: List<String>.from(draft.modes),
        email: draft.email,
        englishSelectedAreaName: englishName,
        breakDays: draft.breakDays.toList(growable: false),
        isSaved: false,
        isSelected: false,
        isWorking: false,
        name: draft.name,
        codeNumber: draft.codeNumber,
        position: draft.position,
        companyId: draft.division,
        permissionKeys: currentPermissions.toList(growable: false),
        accountGradeId: draft.accountGradeId,
        selectedArea: draft.area,
        startTimeByWeekday: Map<String, TimeOfDay?>.from(draft.startTimeByWeekday),
        endTimeByWeekday: Map<String, TimeOfDay?>.from(draft.endTimeByWeekday),
        isActive: true,
      );
      trace.log(
        '현재 소속 확정: division=${draft.division} area=${draft.area} id=${AccountCodeNumber.maskDocumentId(draft.documentId)}',
        progress: 0.16,
      );
      trace.log(
        '휴게 정책: timeIndependent=true breakDays=${user.breakDays.length} breakEnabledWithoutScheduledTimes=true',
        progress: 0.3,
      );
      trace.log(
        '전역 코드 인덱스 정책 적용: user_account_codes reservation과 일반 User 저장을 동일 transaction으로 요청합니다.',
        progress: 0.34,
      );
      trace.log(
        'DevUserWriteService 전용 경로로 계정 생성을 요청합니다. breakDays=${user.breakDays.join(',')}',
        progress: 0.38,
      );
      await _devUserWriteService.createUser(
        user: user,
        division: draft.division,
        area: draft.area,
        log: (message) => trace.log(message),
      );
      trace.log('DevUserWriteService 계정 생성 완료', progress: 0.92);
      await trace.succeed('운영 계정 생성이 완료되었습니다.');
      if (!mounted) return;

      if (widget.selectedDivision != draft.division) {
        widget.onDivisionChanged(draft.division);
      }
      if (widget.selectedArea != draft.area) {
        widget.onAreaChanged(draft.area);
      }
      if (!trace.developerMode) {
        await StatusDialog.showSuccess(
          context,
          title: StatusDialog.userAccountSaveSuccess,
          useCommonUi: true,
        );
      }
      if (!mounted) return;
      setState(() => _refreshTick++);
    } catch (e, st) {
      debugPrint('❌ 계정 생성 실패: $e');
      await trace.fail(
        '운영 계정 생성 중 예외가 발생했습니다.',
        error: e,
        stackTrace: st,
      );
      if (!mounted || trace.developerMode) return;
      await _showAccountLimitFailureDialog(
        e,
        fallbackTitle: StatusDialog.userAccountSaveFailed,
        activeTitle: '계정 생성 불가',
        totalTitle: '계정 생성 불가',
      );
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Widget _buildScopeSurface(
    BuildContext context, {
    required List<String> divisionList,
  }) {
    final selectedDivision = divisionList.contains(widget.selectedDivision)
        ? widget.selectedDivision
        : null;
    return OpsDockListSurface(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: selectedDivision,
              isExpanded: true,
              items: divisionList
                  .map(
                    (division) => DropdownMenuItem<String>(
                      value: division,
                      child: Text(
                        division,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _creating
                  ? null
                  : (value) {
                      setState(() {
                        _selectedUserId = null;
                        _scopeAreasDivision = null;
                        _scopeAreasFuture = null;
                      });
                      widget.onDivisionChanged(value);
                      widget.onAreaChanged(null);
                    },
              decoration: opsInputDecoration(
                context,
                label: '회사 선택',
                prefixIcon: const Icon(Icons.business_rounded),
              ),
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                  ? Duration.zero
                  : CommonUiMotion.selection,
              child: selectedDivision == null
                  ? const SizedBox.shrink(key: ValueKey<String>('user_area_none'))
                  : FutureBuilder<List<String>>(
                      key: ValueKey<String>('user_area_$selectedDivision'),
                      future: _scopeAreaNames(selectedDivision),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            ),
                          );
                        }
                        final areas = snapshot.data ?? const <String>[];
                        return DropdownButtonFormField<String>(
                          value: areas.contains(widget.selectedArea) ? widget.selectedArea : null,
                          isExpanded: true,
                          items: areas
                              .map(
                                (area) => DropdownMenuItem<String>(
                                  value: area,
                                  child: Text(
                                    area,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _creating
                              ? null
                              : (value) {
                                  setState(() => _selectedUserId = null);
                                  widget.onAreaChanged(value);
                                },
                          decoration: opsInputDecoration(
                            context,
                            label: '지역 선택',
                            prefixIcon: const Icon(Icons.location_on_rounded),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateSurface(
    BuildContext context, {
    required List<String> divisionList,
  }) {
    final tokens = CommonUiTheme.of(context);
    final canCreate = !_creating && divisionList.isNotEmpty;
    return OpsDockListSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 11, 9, 11),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tokens.accentContainer,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.person_add_alt_1_rounded,
                size: 19,
                color: tokens.onAccentContainer,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '신규 계정',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '최신 근무 스키마와 지역 리밋을 기준으로 생성합니다.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                  ? Duration.zero
                  : CommonUiMotion.selection,
              child: _creating
                  ? SizedBox(
                      key: const ValueKey<String>('user_creating'),
                      width: 34,
                      height: 34,
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.3,
                          color: tokens.accent,
                        ),
                      ),
                    )
                  : CommonIconButton(
                      key: const ValueKey<String>('user_create'),
                      icon: Icons.add_rounded,
                      tooltip: '신규 계정 생성',
                      onPressed: canCreate ? () => _openCreateDialog(divisionList) : null,
                      haptic: CommonHaptic.selection,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryAssignmentSurface(
    BuildContext context, {
    required String id,
    required Map<String, dynamic> updated,
    required Map<String, dynamic> original,
    required List<String> divisionList,
  }) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final divisions = List<String>.from(updated['divisions'] ?? const <String>[]);
    final primaryDivision = _primaryDivisionOf(updated);
    final originalDivision = _primaryDivisionOf(original);
    final originalArea = _primaryAreaOf(original);
    final retainPreviousPrimary = updated['_retainPreviousPrimary'] == true;
    final movingPrimary = _primaryAreaOf(updated).isNotEmpty &&
        AccountPrimaryAssignment.primaryChanged(
          oldDivision: originalDivision,
          oldArea: originalArea,
          newDivision: primaryDivision,
          newArea: _primaryAreaOf(updated),
        );
    final divisionValue = divisionList.contains(primaryDivision) ? primaryDivision : null;
    return OpsDockListSurface(
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '현재 소속',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: divisionValue,
              isExpanded: true,
              items: divisionList
                  .map(
                    (division) => DropdownMenuItem<String>(
                      value: division,
                      child: Text(division),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  if (primaryDivision == value) return;
                  final withoutIntermediate = AccountPrimaryAssignment.replacePrimary(
                    existing: divisions,
                    previousPrimary: primaryDivision,
                    nextPrimary: value,
                  );
                  final nextDivisions = AccountPrimaryAssignment.replacePrimary(
                    existing: withoutIntermediate,
                    previousPrimary: originalDivision,
                    nextPrimary: value,
                    retainPreviousPrimary: retainPreviousPrimary,
                  );
                  updated['_primaryDivision'] = value;
                  updated['divisions'] = nextDivisions;
                  updated['currentArea'] = null;
                  updated['selectedArea'] = null;
                  _editedUsers[id] = _copyUser(updated);
                });
              },
              decoration: opsInputDecoration(
                context,
                label: '현재 회사',
                prefixIcon: const Icon(Icons.corporate_fare_rounded),
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              child: divisionValue == null
                  ? const SizedBox.shrink(key: ValueKey<String>('primary_area_none'))
                  : FutureBuilder<List<String>>(
                      key: ValueKey<String>('primary_area_$divisionValue'),
                      future: _primaryAreaNames(divisionValue),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const SizedBox(
                            key: ValueKey<String>('primary_area_loading'),
                            height: 52,
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
                          );
                        }
                        if (snapshot.hasError) {
                          return OpsDockListSurface(
                            key: const ValueKey<String>('primary_area_error'),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(11, 9, 7, 9),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '현재 지역 목록을 불러오지 못했습니다.',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: tokens.textSecondary,
                                          ),
                                    ),
                                  ),
                                  CommonIconButton(
                                    icon: Icons.refresh_rounded,
                                    tooltip: '지역 목록 다시 불러오기',
                                    onPressed: () {
                                      setState(() {
                                        _primaryAreaFutures.remove(divisionValue);
                                      });
                                    },
                                    haptic: CommonHaptic.selection,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        final areaList = snapshot.data ?? const <String>[];
                        final primaryArea = _primaryAreaOf(updated);
                        final areaValue = areaList.contains(primaryArea) ? primaryArea : null;
                        return DropdownButtonFormField<String>(
                          key: ValueKey<String>('primary_area_ready_$divisionValue'),
                          value: areaValue,
                          isExpanded: true,
                          items: areaList
                              .map(
                                (area) => DropdownMenuItem<String>(
                                  value: area,
                                  child: Text(area),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              final currentAreas = List<String>.from(updated['areas'] ?? const <String>[]);
                              final precedingArea = _primaryAreaOf(updated).isNotEmpty
                                  ? _primaryAreaOf(updated)
                                  : originalArea;
                              final withoutIntermediate = AccountPrimaryAssignment.replacePrimary(
                                existing: currentAreas,
                                previousPrimary: precedingArea,
                                nextPrimary: value,
                              );
                              updated['areas'] = AccountPrimaryAssignment.replacePrimary(
                                existing: withoutIntermediate,
                                previousPrimary: originalArea,
                                nextPrimary: value,
                                retainPreviousPrimary: retainPreviousPrimary,
                              );
                              updated['currentArea'] = value;
                              updated['selectedArea'] = value;
                              _editedUsers[id] = _copyUser(updated);
                            });
                          },
                          decoration: opsInputDecoration(
                            context,
                            label: '현재 지역',
                            prefixIcon: const Icon(Icons.location_on_rounded),
                          ),
                        );
                      },
                    ),
            ),
            AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(sizeFactor: animation, child: child),
              ),
              child: movingPrimary
                  ? SwitchListTile.adaptive(
                      key: ValueKey<String>('retain_primary_${primaryDivision}_${_primaryAreaOf(updated)}'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('이전 주 소속을 추가 소속으로 유지'),
                      value: retainPreviousPrimary,
                      onChanged: (value) {
                        setState(() {
                          updated['_retainPreviousPrimary'] = value;
                          updated['divisions'] = AccountPrimaryAssignment.replacePrimary(
                            existing: <String>[
                              ...List<String>.from(updated['divisions'] ?? const <String>[]),
                              if (value) originalDivision,
                            ],
                            previousPrimary: originalDivision,
                            nextPrimary: _primaryDivisionOf(updated),
                            retainPreviousPrimary: value,
                          );
                          updated['areas'] = AccountPrimaryAssignment.replacePrimary(
                            existing: <String>[
                              ...List<String>.from(updated['areas'] ?? const <String>[]),
                              if (value) originalArea,
                            ],
                            previousPrimary: originalArea,
                            nextPrimary: _primaryAreaOf(updated),
                            retainPreviousPrimary: value,
                          );
                          _editedUsers[id] = _copyUser(updated);
                        });
                      },
                    )
                  : const SizedBox.shrink(key: ValueKey<String>('retain_primary_none')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserEditor(
    BuildContext context, {
    required String id,
    required Map<String, dynamic> data,
    required Map<String, dynamic> updated,
    required List<String> divisionList,
  }) {
    final tokens = CommonUiTheme.of(context);
    final breakDays = List<String>.from(updated['breakDays'] ?? const <String>[]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 18, thickness: 1, color: tokens.borderSubtle),
        _buildPrimaryAssignmentSurface(
          context,
          id: id,
          updated: updated,
          original: _copyUser(
            data,
            primaryDivision: widget.selectedDivision,
            primaryArea: widget.selectedArea,
          ),
          divisionList: divisionList,
        ),
        const SizedBox(height: 10),
        Text(
          '접근 가능 회사',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        AnimatedSize(
          duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
              ? Duration.zero
              : const Duration(milliseconds: 220),
          alignment: Alignment.topLeft,
          child: Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final division in List<String>.from(updated['divisions'] ?? const <String>[]))
              InputChip(
                label: Text(division),
                onDeleted: division == _primaryDivisionOf(updated)
                    ? null
                    : () {
                  setState(() {
                    final list = List<String>.from(updated['divisions'] ?? const <String>[]);
                    list.remove(division);
                    updated['divisions'] = list;
                    _editedUsers[id] = _copyUser(updated);
                  });
                },
              ),
            ActionChip(
              label: const Text('회사 추가'),
              onPressed: () async {
                final current = List<String>.from(updated['divisions'] ?? const <String>[]).toSet();
                final candidates = divisionList.where((value) => !current.contains(value)).toList();
                if (candidates.isEmpty) return;
                final selected = await showCommonOverlayDialog<String>(
                  context: context,
                  builder: (dialogContext) => SimpleDialog(
                    title: const Text('회사 추가'),
                    children: candidates
                        .map(
                          (division) => SimpleDialogOption(
                            onPressed: () => Navigator.of(dialogContext).pop(division),
                            child: Text(division),
                          ),
                        )
                        .toList(growable: false),
                  ),
                );
                if (selected == null || !mounted) return;
                setState(() {
                  final list = List<String>.from(updated['divisions'] ?? const <String>[]);
                  list.add(selected);
                  updated['divisions'] = list;
                  _editedUsers[id] = _copyUser(updated);
                });
              },
            ),
          ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '접근 가능 지역',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        AnimatedSize(
          duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
              ? Duration.zero
              : const Duration(milliseconds: 220),
          alignment: Alignment.topLeft,
          child: Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final area in List<String>.from(updated['areas'] ?? const <String>[]))
              InputChip(
                label: Text(area),
                onDeleted: area == _primaryAreaOf(updated)
                    ? null
                    : () {
                  setState(() {
                    final list = List<String>.from(updated['areas'] ?? const <String>[]);
                    list.remove(area);
                    updated['areas'] = list;
                    _editedUsers[id] = _copyUser(updated);
                  });
                },
              ),
            ActionChip(
              label: const Text('지역 추가'),
              onPressed: () async {
                final divisions = List<String>.from(updated['divisions'] ?? const <String>[]);
                final areas = await getAreasByDivisions(divisions);
                if (!mounted) return;
                final current = List<String>.from(updated['areas'] ?? const <String>[]).toSet();
                final candidates = areas.where((value) => !current.contains(value)).toList();
                if (candidates.isEmpty) return;
                final selected = await showCommonOverlayDialog<String>(
                  context: context,
                  builder: (dialogContext) => SimpleDialog(
                    title: const Text('지역 추가'),
                    children: candidates
                        .map(
                          (area) => SimpleDialogOption(
                            onPressed: () => Navigator.of(dialogContext).pop(area),
                            child: Text(area),
                          ),
                        )
                        .toList(growable: false),
                  ),
                );
                if (selected == null || !mounted) return;
                setState(() {
                  final list = List<String>.from(updated['areas'] ?? const <String>[]);
                  list.add(selected);
                  updated['areas'] = list;
                  _editedUsers[id] = _copyUser(updated);
                });
              },
            ),
          ],
          ),
        ),
        const SizedBox(height: 10),
        FutureBuilder<Map<String, CompanyGradePolicy>>(
          future: _gradePolicyFutures.putIfAbsent(
            (updated['companyId'] ?? widget.selectedDivision ?? '').toString(),
            () => CompanyGradePolicyService().loadAll(
              (updated['companyId'] ?? widget.selectedDivision ?? '').toString(),
            ),
          ),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('등급 정책 조회 실패: ${snapshot.error}');
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final policies = snapshot.data!;
            return AnimatedSize(
              duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                  ? Duration.zero : CommonUiMotion.selection,
              curve: Curves.easeInOutCubic,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final entry in policies.entries)
                    ChoiceChip(
                      label: Text(entry.value.name),
                      selected: updated['accountGradeId'] == entry.key,
                      onSelected: updated['isInitialAdmin'] != true &&
                              entry.value.enabled &&
                              AccountPermissionPolicy.mayGrant(
                                context.read<UserState>().permissionKeys,
                                entry.value.permissionKeys,
                              )
                          ? (_) {
                              setState(() {
                                updated['accountGradeId'] = entry.key;
                                updated['permissionKeys'] =
                                    entry.value.permissionKeys.toList(growable: false)..sort();
                                _editedUsers[id] = _copyUser(updated);
                              });
                            }
                          : null,
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
              ? Duration.zero
              : CommonUiMotion.selection,
          child: Text(
            AccountPermissionPolicy.gradeLabel(
              (updated['accountGradeId'] ?? '').toString(),
            ),
            key: ValueKey<String>(
              (updated['accountGradeId'] ?? '').toString(),
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 5),
        PermissionDetailList(
          permissions: ((updated['isInitialAdmin'] == true)
              ? AccountPermissionPolicy.keys
              : AccountPermissionPolicy.generalPermissionKeys).toList()..sort(),
          selected: AccountPermissionPolicy.sanitize(
            List<String>.from(updated['permissionKeys'] ?? const <String>[]),
          ),
          enabled: false,
          height: 264,
        ),
        const SizedBox(height: 8),
        Text(
          '허용 모드: ${List<String>.from(updated['modes'] ?? const <String>[]).map(AccountPermissionPolicy.modeLabel).join(', ')}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
        ),
        const SizedBox(height: 3),
        Text(
          '휴게 적용: ${breakDays.isEmpty ? '없음' : breakDays.join(', ')}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
        ),
        if ((updated['position'] ?? '').toString().trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            '직책: ${updated['position']}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                ),
          ),
        ],
        const SizedBox(height: 10),
        CommonButton(
          label: _savingIds.contains(id) ? '저장 중' : '저장',
          icon: Icons.save_rounded,
          loading: _savingIds.contains(id),
          onPressed: _savingIds.contains(id)
              ? null
              : () async {
                  setState(() => _savingIds.add(id));
                  await _saveChanges(id, data, updated);
                  if (!mounted) return;
                  setState(() => _savingIds.remove(id));
                },
          expand: true,
          haptic: CommonHaptic.medium,
        ),
      ],
    );
  }

  Widget _buildUserList({required List<String> divisionList}) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final division = widget.selectedDivision;
    final area = widget.selectedArea;
    if (division == null || area == null) {
      return const OpsDockListSurface(
        child: SizedBox(
          height: 280,
          child: OpsEmptyState(
            icon: Icons.manage_accounts_rounded,
            title: '회사와 지역을 선택하세요',
            message: '선택한 범위의 계정을 List Surface에서 관리할 수 있습니다.',
          ),
        ),
      );
    }
    return OpsDockListSurface(
      child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        key: ValueKey<String>('$division-$area-$_refreshTick'),
        future: _fetchUsersForArea(division, area),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 280,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return SizedBox(
              height: 280,
              child: OpsEmptyState(
                icon: Icons.error_outline_rounded,
                title: '계정 목록을 불러오지 못했습니다',
                message: snapshot.error.toString(),
              ),
            );
          }
          final docs = snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          if (docs.isEmpty) {
            return const SizedBox(
              height: 280,
              child: OpsEmptyState(
                icon: Icons.person_off_outlined,
                title: '등록된 계정이 없습니다',
                message: '신규 계정에서 첫 운영 계정을 생성하세요.',
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: docs.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              thickness: 1,
              color: tokens.borderSubtle,
            ),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final id = doc.id;
              final base = _editedUsers[id] ?? _copyUser(
                data,
                primaryDivision: division,
                primaryArea: area,
              );
              final updated = _copyUser(base);
              final selected = _selectedUserId == id;
              final active = (updated['isActive'] as bool?) ?? true;
              final permissionSummary = AccountPermissionPolicy.gradeLabel(
                (updated['accountGradeId'] ?? '').toString(),
              );
              final position = (updated['position'] ?? '').toString().trim();
              return CommonAnimatedReveal(
                delay: reduceMotion ? Duration.zero : Duration(milliseconds: index * 22),
                offset: const Offset(.016, 0),
                child: OpsDockSelectableRowSurface(
                  selected: selected,
                  selectionColor: tokens.accent,
                  selectedContainer: tokens.accentContainer,
                  onTap: () {
                    setState(() {
                      _selectedUserId = selected ? null : id;
                      if (!selected) {
                        _editedUsers.putIfAbsent(
                          id,
                          () => _copyUser(
                            data,
                            primaryDivision: division,
                            primaryArea: area,
                          ),
                        );
                      }
                    });
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: active ? tokens.successContainer : tokens.surfaceSelected,
                              borderRadius: BorderRadius.circular(CommonUiShapes.control),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              active ? Icons.person_rounded : Icons.person_off_rounded,
                              size: 20,
                              color: active ? tokens.success : tokens.iconSecondary,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (updated['name'] ?? '').toString().trim().isEmpty
                                      ? id
                                      : (updated['name'] ?? '').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: tokens.textPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$permissionSummary${position.isEmpty ? '' : ' · $position'} · ${active ? '활성' : '비활성'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: tokens.textSecondary,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  id,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: tokens.textSecondary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          AnimatedRotation(
                            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                            turns: selected ? .5 : 0,
                            child: Icon(Icons.keyboard_arrow_down_rounded, color: tokens.iconSecondary),
                          ),
                        ],
                      ),
                      AnimatedSize(
                        duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: selected
                            ? _buildUserEditor(
                                context,
                                id: id,
                                data: data,
                                updated: updated,
                                divisionList: divisionList,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final divisionList = widget.divisionList;
    return ColoredBox(
      color: tokens.canvas,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          12,
          12,
          12 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: divisionList.isEmpty
            ? const OpsDockListSurface(
                child: SizedBox(
                  height: 280,
                  child: OpsEmptyState(
                    icon: Icons.business_outlined,
                    title: '등록된 회사가 없습니다',
                    message: '회사 관리에서 먼저 회사를 생성하세요.',
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CommonAnimatedReveal(
                    child: _buildScopeSurface(
                      context,
                      divisionList: divisionList,
                    ),
                  ),
                  const SizedBox(height: 9),
                  CommonAnimatedReveal(
                    delay: const Duration(milliseconds: 35),
                    child: _buildCreateSurface(
                      context,
                      divisionList: divisionList,
                    ),
                  ),
                  const SizedBox(height: 9),
                  if (widget.selectedDivision != null &&
                      context.watch<UserState>().session?.isInitialAdmin == true)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await AccountGradePolicyDialog.open(
                            context, widget.selectedDivision!,
                          );
                          if (!mounted) return;
                          setState(() {
                            _gradePolicyFutures.clear();
                            _refreshTick++;
                          });
                        },
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text('등급별 컬렉션 권한 설정'),
                      ),
                    ),
                  if (widget.selectedDivision != null &&
                      context.watch<UserState>().hasPermission('security.acl.manage'))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: OutlinedButton.icon(
                        onPressed: () => DocumentAccessPolicyDialog.open(
                          context,
                          companyId: widget.selectedDivision!,
                          initialDocumentPath: _selectedUserId == null
                              ? ''
                              : 'user_accounts/$_selectedUserId',
                        ),
                        icon: const Icon(Icons.shield_outlined),
                        label: const Text('문서별 접근 권한 설정'),
                      ),
                    ),
                  Expanded(
                    child: _buildUserList(divisionList: divisionList),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CreateUserAccountDraft {
  _CreateUserAccountDraft({
    required this.name,
    required this.codeNumber,
    required this.codeEntryMode,
    required this.email,
    required this.division,
    required this.area,
    required this.permissionKeys,
    required this.accountGradeId,
    required this.modes,
    required this.position,
    required this.startTimeByWeekday,
    required this.endTimeByWeekday,
    required this.breakDays,
  });

  static const List<String> weekdays = <String>['월', '화', '수', '목', '금', '토', '일'];

  final String name;
  final String codeNumber;
  final UserCodeEntryMode codeEntryMode;
  final String email;
  final String division;
  final String area;
  final Set<String> permissionKeys;
  final String accountGradeId;
  final List<String> modes;
  final String position;
  final Map<String, TimeOfDay?> startTimeByWeekday;
  final Map<String, TimeOfDay?> endTimeByWeekday;
  final Set<String> breakDays;

  String get documentId => AccountCodeNumber.documentId(codeNumber: codeNumber, area: area);


}

class _CreateUserAccountDialog extends StatefulWidget {
  const _CreateUserAccountDialog({
    required this.divisionList,
    required this.permissionList,
    required this.initialDivision,
    required this.initialArea,
    required this.manualCodeAllowed,
    required this.groupApproved,
    required this.onRequestManualCodeEntry,
    required this.fetchAreasForDivision,
  });

  final List<String> divisionList;
  final List<String> permissionList;
  final String? initialDivision;
  final String? initialArea;
  final bool manualCodeAllowed;
  final bool groupApproved;
  final Future<bool> Function() onRequestManualCodeEntry;
  final Future<List<String>> Function(String division) fetchAreasForDivision;

  @override
  State<_CreateUserAccountDialog> createState() => _CreateUserAccountDialogState();
}

class _CreateUserAccountDialogState extends State<_CreateUserAccountDialog> {
  static const List<String> _days = <String>['월', '화', '수', '목', '금', '토', '일'];
  static const List<String> _availableModes = <String>['single', 'double', 'triple', 'minor'];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeNumberController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _positionController = TextEditingController();

  String? _selectedDivision;
  String? _selectedArea;
  final Set<String> _selectedPermissionKeys = <String>{};
  String _accountGradeId = '';
  final CompanyGradePolicyService _policyService = CompanyGradePolicyService();
  Map<String, CompanyGradePolicy> _gradePolicies = <String, CompanyGradePolicy>{};
  bool _loadingGradePolicies = false;
  String? _gradePolicyError;
  UserCodeEntryMode _codeEntryMode = UserCodeEntryMode.generated;
  final Set<String> _selectedModes = <String>{'single'};
  Map<String, TimeOfDay?> _startByDay = <String, TimeOfDay?>{};
  Map<String, TimeOfDay?> _endByDay = <String, TimeOfDay?>{};
  Set<String> _breakDays = <String>{};
  List<String> _areaList = <String>[];
  bool _loadingAreas = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _selectedDivision = widget.divisionList.contains(widget.initialDivision)
        ? widget.initialDivision
        : (widget.divisionList.isNotEmpty ? widget.divisionList.first : null);
    _codeNumberController.text = AccountCodeNumber.format(AccountCodeNumber.generate());
    _startByDay = <String, TimeOfDay?>{
      for (final day in _days) day: null,
    };
    _endByDay = <String, TimeOfDay?>{
      for (final day in _days) day: null,
    };
    _breakDays = Set<String>.of(_days);
    _loadAreas(keepInitialArea: true);
    _loadGradePolicies();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeNumberController.dispose();
    _emailController.dispose();
    _positionController.dispose();
    super.dispose();
  }

  String _normalizedCodeNumber() => AccountCodeNumber.normalize(_codeNumberController.text);

  String _documentIdPreview() {
    final codeNumber = _normalizedCodeNumber();
    final area = (_selectedArea ?? '').trim();
    final valid = switch (_codeEntryMode) {
      UserCodeEntryMode.generated =>
        AccountCodeNumber.isGeneratedCode(codeNumber),
      UserCodeEntryMode.developerManual =>
        widget.manualCodeAllowed &&
            AccountCodeNumber.isDeveloperManualCode(codeNumber),
    };
    if (!valid || area.isEmpty) return '-';
    return AccountCodeNumber.documentId(codeNumber: codeNumber, area: area);
  }

  bool _isValidEmailLocalPart(String input) {
    return RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(input.trim());
  }

  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  String _formatTime(TimeOfDay? time) {
    if (time == null) return '--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _loadAreas({bool keepInitialArea = false}) async {
    final division = _selectedDivision;
    if (division == null || division.trim().isEmpty) {
      setState(() {
        _areaList = <String>[];
        _selectedArea = null;
      });
      return;
    }

    setState(() => _loadingAreas = true);
    final areas = await widget.fetchAreasForDivision(division);
    if (!mounted) return;

    setState(() {
      _areaList = areas;
      final candidate = keepInitialArea ? widget.initialArea : _selectedArea;
      _selectedArea = areas.contains(candidate) ? candidate : (areas.isNotEmpty ? areas.first : null);
      _loadingAreas = false;
    });
  }

  Future<void> _loadGradePolicies() async {
    final company = _selectedDivision?.trim() ?? '';
    setState(() {
      _loadingGradePolicies = true;
      _gradePolicyError = null;
      _gradePolicies = <String, CompanyGradePolicy>{};
      _selectedPermissionKeys.clear();
      _accountGradeId = '';
    });
    if (company.isEmpty) {
      if (mounted) setState(() => _loadingGradePolicies = false);
      return;
    }
    try {
      final policies = await _policyService.loadAll(company);
      if (!mounted || _selectedDivision != company) return;
      setState(() {
        _gradePolicies = <String, CompanyGradePolicy>{
          for (final entry in policies.entries)
            if (entry.value.enabled) entry.key: entry.value,
        };
        _loadingGradePolicies = false;
      });
    } catch (error, stackTrace) {
      debugPrint('[ACCOUNT-CREATE] grade policies failed: $error\n$stackTrace');
      if (!mounted || _selectedDivision != company) return;
      setState(() {
        _loadingGradePolicies = false;
        _gradePolicyError = error.toString();
      });
      if (DevAuth.devModeEnabled.value) {
        await StatusDialog.showFailure(
          context,
          title: '계정 등급 정책 조회 실패',
          description: '회사별 등급 정책을 확인하지 못했습니다.',
          copyText: 'debugPrint(${jsonEncode('[ACCOUNT-CREATE] policy company=$company error=$error')});\ndebugPrint(${jsonEncode(stackTrace.toString())});',
          copyButtonLabel: 'debugPrint 코드 복사',
          visibleDuration: Duration.zero,
          awaitManualClose: true,
          useCommonUi: true,
        );
      }
    }
  }

  Future<void> _pickTime(String day, {required bool isStart}) async {
    final current = isStart ? _startByDay[day] : _endByDay[day];
    final initial = current ?? (isStart ? const TimeOfDay(hour: 9, minute: 0) : const TimeOfDay(hour: 18, minute: 0));
    final picked = await showCommonTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) {
        final mq = MediaQuery.of(ctx);
        return MediaQuery(
          data: mq.copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null || !mounted) return;

    setState(() {
      _errorText = null;
      if (isStart) {
        _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = picked;
      } else {
        _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = picked;
      }
    });
  }

  void _clearDay(String day) {
    setState(() {
      _errorText = null;
      _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = null;
      _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = null;
    });
  }

  void _toggleBreak(String day, bool value) {
    setState(() {
      _errorText = null;
      _breakDays = <String>{..._breakDays};
      if (value) {
        _breakDays.add(day);
      } else {
        _breakDays.remove(day);
      }
    });
  }

  String? _validate() {
    final name = _nameController.text.trim();
    final codeNumber = _normalizedCodeNumber();
    final emailLocal = _emailController.text.trim();
    if (name.isEmpty) return '이름을 입력하세요';
    if (_codeEntryMode == UserCodeEntryMode.generated) {
      if (!AccountCodeNumber.isGeneratedCode(codeNumber)) {
        return '코드번호를 다시 생성하세요';
      }
    } else {
      if (!widget.manualCodeAllowed) {
        return '개발자 인증 상태를 다시 확인하세요';
      }
      if (!AccountCodeNumber.isDeveloperManualCode(codeNumber)) {
        return '코드번호는 숫자 11자리로 입력하세요';
      }
    }
    if (emailLocal.isEmpty || !_isValidEmailLocalPart(emailLocal)) return '이메일을 다시 확인하세요';
    if ((_selectedDivision ?? '').trim().isEmpty) return '회사를 선택하세요';
    if ((_selectedArea ?? '').trim().isEmpty) return '지역을 선택하세요';
    if (_selectedModes.isEmpty) return '허용 모드를 1개 이상 선택하세요';
    if (_loadingGradePolicies || _gradePolicyError != null) {
      return '회사별 등급 정책을 확인할 수 없습니다. 다시 조회하세요.';
    }
    final policy = _gradePolicies[_accountGradeId];
    if (policy == null || !policy.enabled) return '계정 등급을 선택하세요';
    if (!policy.permissionKeys.every(widget.permissionList.contains)) {
      return '현재 계정으로 부여할 수 없는 권한이 등급에 포함되어 있습니다.';
    }
    if (!policy.matches(_selectedPermissionKeys)) {
      return '현재 회사 등급 정책과 선택된 권한이 일치하지 않습니다.';
    }

    for (final day in _days) {
      final start = _startByDay[day];
      final end = _endByDay[day];
      final hasStart = start != null;
      final hasEnd = end != null;
      if (hasStart != hasEnd) return '$day 요일의 출근/퇴근 시간을 모두 입력하세요';
      if (start != null && end != null) {
        if (_toMinutes(start) > _toMinutes(end)) {
          return '$day 요일의 출근/퇴근 시간을 다시 확인하세요';
        }
      }
    }

    return null;
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      final message = 'account_create_validation_failed permissionCount=${_selectedPermissionKeys.length} reason=$error';
      debugPrint(message);
      setState(() => _errorText = error);
      if (DevAuth.devModeEnabled.value && mounted) {
        await StatusDialog.showFailure(
          context,
          title: '운영 계정 입력 검증 실패',
          description: error,
          copyText: 'debugPrint(${jsonEncode(message)});',
          copyButtonLabel: 'debugPrint 코드 복사',
          visibleDuration: Duration.zero,
          useCommonUi: true,
          awaitManualClose: true,
        );
      }
      return;
    }

    try {
      final policy = await _policyService.load(_selectedDivision!, _accountGradeId);
      if (!policy.matches(_selectedPermissionKeys)) {
        await _loadGradePolicies();
        throw StateError('ACCOUNT_GRADE_POLICY_CHANGED');
      }
    } catch (error, stackTrace) {
      final message = 'account_create_policy_validation_failed grade=$_accountGradeId error=$error';
      debugPrint('[ACCOUNT-CREATE] $message\n$stackTrace');
      if (!mounted) return;
      setState(() => _errorText = '회사별 등급 정책이 변경됐거나 조회되지 않습니다. 등급을 다시 선택하세요.');
      if (DevAuth.devModeEnabled.value) {
        await StatusDialog.showFailure(
          context,
          title: '회사별 등급 정책 확인 실패',
          description: _errorText!,
          copyText: 'debugPrint(${jsonEncode(message)});\ndebugPrint(${jsonEncode(stackTrace.toString())});',
          copyButtonLabel: 'debugPrint 코드 복사',
          useCommonUi: true,
          visibleDuration: Duration.zero,
          awaitManualClose: true,
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      _CreateUserAccountDraft(
        name: _nameController.text.trim(),
        codeNumber: _normalizedCodeNumber(),
        codeEntryMode: _codeEntryMode,
        email: '${_emailController.text.trim()}@gmail.com',
        division: _selectedDivision!.trim(),
        area: _selectedArea!.trim(),
        permissionKeys: Set<String>.of(_selectedPermissionKeys),
        accountGradeId: _accountGradeId,
        modes: _selectedModes.toList(growable: false)..sort(),
        position: _positionController.text.trim(),
        startTimeByWeekday: Map<String, TimeOfDay?>.from(_startByDay),
        endTimeByWeekday: Map<String, TimeOfDay?>.from(_endByDay),
        breakDays: Set<String>.of(_breakDays),
      ),
    );
  }

  Widget _buildTextField({
    Key? key,
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    bool readOnly = false,
    Widget? suffixIcon,
    ValueChanged<String>? onChanged,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      key: key,
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
      decoration: opsInputDecoration(
        context,
        label: label,
        suffixIcon: suffixIcon,
      ),
    );
  }

  Future<void> _setCodeEntryMode(UserCodeEntryMode mode) async {
    if (mode == _codeEntryMode) return;
    if (mode == UserCodeEntryMode.developerManual) {
      if (!widget.manualCodeAllowed) return;
      final authorized = await widget.onRequestManualCodeEntry();
      if (!mounted) return;
      if (!authorized) {
        const logLine = 'secondary user manual code entry authorization failed';
        debugPrint(logLine);
        setState(() => _errorText = '서버 접근 승인이 확인되지 않았습니다');
        final developerMode = await DevAuth.isDevModeEnabled();
        if (developerMode && mounted) {
          await StatusDialog.showFailure(
            context,
            title: '코드번호 직접 입력 인증 실패',
            description: '서버 접근 승인이 확인되지 않았습니다.',
            copyText: "debugPrint('secondary user manual code entry authorization failed');",
            copyButtonLabel: 'debugPrint 코드 복사',
            visibleDuration: Duration.zero,
            useCommonUi: true,
            awaitManualClose: true,
          );
        }
        return;
      }
      setState(() {
        _codeEntryMode = UserCodeEntryMode.developerManual;
        _codeNumberController.clear();
        _errorText = null;
      });
      debugPrint('secondary user manual code entry enabled: digits=11');
      return;
    }
    setState(() {
      _codeEntryMode = UserCodeEntryMode.generated;
      _codeNumberController.text = AccountCodeNumber.format(
        AccountCodeNumber.generate(),
      );
      _errorText = null;
    });
    debugPrint('secondary user generated code entry enabled');
  }

  Widget _buildCodeEntryModeSelector(bool reduceMotion) {
    if (!widget.manualCodeAllowed) return const SizedBox.shrink();
    return AnimatedSize(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
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

  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('허용 모드', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableModes.map((mode) {
            final selected = _selectedModes.contains(mode);
            return FilterChip(
              label: Text(AccountPermissionPolicy.modeLabel(mode)),
              selected: selected,
              onSelected: (value) {
                setState(() {
                  _errorText = null;
                  if (value) {
                    _selectedModes.add(mode);
                  } else {
                    _selectedModes.remove(mode);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildWeekdayEditor() {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tokens = CommonUiTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '요일별 근무 시간',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        for (final day in _days)
          AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            curve: CommonUiMotion.standard,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _startByDay[day] != null && _endByDay[day] != null
                  ? tokens.accentContainer.withOpacity(.16)
                  : tokens.surfaceSelected.withOpacity(.55),
              border: Border.all(color: tokens.borderSubtle),
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        day,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                        child: Builder(
                          key: ValueKey<String>(
                            '${day}_${_formatTime(_startByDay[day])}_${_formatTime(_endByDay[day])}_${_breakDays.contains(day)}',
                          ),
                          builder: (_) {
                            final working = _startByDay[day] != null && _endByDay[day] != null;
                            return Text(
                              working
                                  ? '${_formatTime(_startByDay[day])} ~ ${_formatTime(_endByDay[day])} · ${_breakDays.contains(day) ? '휴게 있음' : '휴게 없음'}'
                                  : '휴무 · ${_breakDays.contains(day) ? '휴게 있음' : '휴게 없음'}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: tokens.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            );
                          },
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _clearDay(day),
                      child: const Text('비우기'),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(day, isStart: true),
                        icon: const Icon(Icons.login_rounded),
                        label: Text('출근 ${_formatTime(_startByDay[day])}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(day, isStart: false),
                        icon: const Icon(Icons.logout_rounded),
                        label: Text('퇴근 ${_formatTime(_endByDay[day])}'),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Row(
                    children: [
                      Icon(
                        Icons.free_breakfast_rounded,
                        size: 18,
                        color: tokens.iconSecondary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '휴게 적용',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      Switch.adaptive(
                        value: _breakDays.contains(day),
                        onChanged: (value) => _toggleBreak(day, value),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AlertDialog(
      title: const Text('신규 계정 생성'),
      content: SizedBox(
        width: 590,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSize(
                duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                curve: CommonUiMotion.enter,
                child: AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  child: _errorText == null
                      ? const SizedBox.shrink(key: ValueKey<String>('user_create_error_none'))
                      : Container(
                          key: ValueKey<String>(_errorText!),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: tokens.dangerContainer,
                            borderRadius: BorderRadius.circular(CommonUiShapes.control),
                            border: Border.all(color: tokens.danger),
                          ),
                          child: Text(
                            _errorText!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: tokens.onDangerContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                ),
              ),
              OpsDockListSurface(
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTextField(
                        controller: _nameController,
                        label: '이름',
                        onChanged: (_) => setState(() => _errorText = null),
                      ),
                      const SizedBox(height: 12),
                      _buildCodeEntryModeSelector(reduceMotion),
                      if (widget.manualCodeAllowed) const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                        switchInCurve: CommonUiMotion.enter,
                        switchOutCurve: CommonUiMotion.exit,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: .97, end: 1).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: _buildTextField(
                          key: ValueKey<String>('user_create_code_${_codeEntryMode.name}'),
                          controller: _codeNumberController,
                          label: '코드번호',
                          keyboardType: _codeEntryMode == UserCodeEntryMode.developerManual
                              ? TextInputType.number
                              : null,
                          readOnly: _codeEntryMode == UserCodeEntryMode.generated,
                          inputFormatters:
                              _codeEntryMode == UserCodeEntryMode.developerManual
                                  ? <TextInputFormatter>[
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(11),
                                    ]
                                  : null,
                          onChanged: (_) => setState(() => _errorText = null),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () async {
                                  final code = _normalizedCodeNumber();
                                  final value = _codeEntryMode ==
                                          UserCodeEntryMode.developerManual
                                      ? code
                                      : AccountCodeNumber.format(code);
                                  await Clipboard.setData(
                                    ClipboardData(text: value),
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded),
                              ),
                              if (_codeEntryMode == UserCodeEntryMode.generated)
                                IconButton(
                                  onPressed: () => setState(() {
                                    _errorText = null;
                                    _codeNumberController.text = AccountCodeNumber.format(
                                      AccountCodeNumber.generate(),
                                    );
                                  }),
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _emailController,
                        label: '이메일 아이디(@gmail.com 제외)',
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (_) => setState(() => _errorText = null),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedDivision,
                        isExpanded: true,
                        decoration: opsInputDecoration(
                          context,
                          label: '회사',
                          prefixIcon: const Icon(Icons.business_rounded),
                        ),
                        items: widget.divisionList
                            .map(
                              (division) => DropdownMenuItem<String>(
                                value: division,
                                child: Text(
                                  division,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _errorText = null;
                            _selectedDivision = value;
                            _selectedArea = null;
                          });
                          _loadAreas();
                          _loadGradePolicies();
                        },
                      ),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                        child: _loadingAreas
                            ? const SizedBox(
                                key: ValueKey<String>('user_create_area_loading'),
                                height: 52,
                                child: Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.2),
                                  ),
                                ),
                              )
                            : DropdownButtonFormField<String>(
                                key: ValueKey<String>(
                                  'user_create_area_${_selectedDivision ?? ''}_${_areaList.join('|')}',
                                ),
                                value: _areaList.contains(_selectedArea) ? _selectedArea : null,
                                isExpanded: true,
                                decoration: opsInputDecoration(
                                  context,
                                  label: '지역',
                                  prefixIcon: const Icon(Icons.location_on_rounded),
                                ),
                                items: _areaList
                                    .map(
                                      (area) => DropdownMenuItem<String>(
                                        value: area,
                                        child: Text(
                                          area,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) => setState(() {
                                  _errorText = null;
                                  _selectedArea = value;
                                }),
                              ),
                      ),
                      const SizedBox(height: 9),
                      AnimatedSwitcher(
                        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                        child: Text(
                          '생성 문서 ID: ${_documentIdPreview()}',
                          key: ValueKey<String>(_documentIdPreview()),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: tokens.textSecondary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      AnimatedSize(
                        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
                        curve: Curves.easeInOutCubic,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final entry in _gradePolicies.entries)
                              ChoiceChip(
                                label: Text(entry.value.name),
                                selected: _accountGradeId == entry.key,
                                onSelected: !_loadingGradePolicies &&
                                        entry.value.permissionKeys.every(widget.permissionList.contains)
                                    ? (_) => setState(() {
                                        _errorText = null;
                                        _accountGradeId = entry.key;
                                        _selectedPermissionKeys
                                          ..clear()
                                          ..addAll(entry.value.permissionKeys);
                                      })
                                    : null,
                              ),
                          ],
                        ),
                      ),
                      if (_loadingGradePolicies)
                        const LinearProgressIndicator(),
                      if (_gradePolicyError != null)
                        Text('등급 정책 조회 실패: $_gradePolicyError'),
                      AnimatedSwitcher(
                        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                        child: Column(
                          key: ValueKey<String>(
                            _accountGradeId,
                          ),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _accountGradeId.isEmpty
                                  ? '계정 등급을 선택하세요.'
                                  : (_gradePolicies[_accountGradeId]?.name ??
                                      AccountPermissionPolicy.gradeLabel(_accountGradeId)),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 5),
                            PermissionDetailList(
                              permissions: AccountPermissionPolicy.generalPermissionKeys.toList()..sort(),
                              selected: _selectedPermissionKeys,
                              enabled: false,
                              height: 264,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _positionController,
                        label: '직책(선택)',
                        onChanged: (_) => setState(() => _errorText = null),
                      ),
                      const SizedBox(height: 14),
                      _buildModeSelector(),
                      const SizedBox(height: 14),
                      _buildWeekdayEditor(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        CommonButton(
          label: '취소',
          onPressed: () => Navigator.of(context).pop(),
          variant: CommonButtonVariant.tertiary,
          haptic: CommonHaptic.selection,
        ),
        CommonButton(
          label: '생성',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: _submit,
          variant: CommonButtonVariant.primary,
          haptic: CommonHaptic.medium,
        ),
      ],
    );
  }
}
