import '../../../../../app/diagnostics/firebase_activity_meter.dart';
import '../../../../../app/models/account_role.dart';
import '../../../../../app/models/account_role_diagnostics.dart';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../../features/account/applications/user_state.dart';

import '../../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../../app/utils/status_dialog.dart';
import '../../../data/services/dev_user_write_service.dart';
import '../../../../../features/account/data/services/user_account_show_map.dart';
import '../../../../../features/account/domain/models/user/user_model.dart';
import '../../../../../features/dev/application/developer_account_authorization.dart';
import '../../../../../features/selector/application/dev_auth.dart';
import '../../../../../shared/auth/account_code_number.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../widgets/ops_console_widgets.dart';


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

typedef _DevUserListEntries = List<MapEntry<String, Map<String, dynamic>>>;

class _UserAccountsTabState extends State<UserAccountsTab> {
  static final List<String> _roles = RoleType.values.map((role) => role.name).toList(growable: false);

  final Map<String, Map<String, dynamic>> _editedUsers = <String, Map<String, dynamic>>{};
  final DevUserWriteService _devUserWriteService = DevUserWriteService();
  final Map<String, Future<List<String>>> _primaryAreaFutures = <String, Future<List<String>>>{};
  final Map<String, Future<_DevUserListEntries>> _userListFutures =
      <String, Future<_DevUserListEntries>>{};
  final Map<String, int> _userListReuseCounts = <String, int>{};
  final Map<String, int> _userListInFlightRequests = <String, int>{};
  static const int _userListCacheLimit = 12;
  int _userListRequestSequence = 0;
  final Set<String> _savingIds = <String>{};
  bool _creating = false;
  String? _selectedUserId;
  String? _editingUserId;
  String? _loadingRootUserId;
  int _refreshTick = 0;
  String? _scopeAreasDivision;
  Future<List<String>>? _scopeAreasFuture;

  String _requireRequesterManagerRole(String operation) {
    final roleName = context.read<UserState>().role;
    final role = RoleType.fromName(roleName);
    if (role?.canManageAccounts != true) {
      AccountRoleDiagnostics.recordCreation(
        'ops_user_${operation}_blocked reason=role_denied',
      );
      throw StateError('ACCOUNT_MANAGEMENT_ROLE_DENIED');
    }
    return role!.name;
  }

  Future<bool> _isManualCodeAuthorized({bool interactive = false}) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled) return false;
    if (interactive) {
      return DeveloperAccountAuthorization.authorizeInteractive(
        source: 'secondary_user_manual_code_entry',
      );
    }
    return DeveloperAccountAuthorization.isAuthorized;
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
    final storedPrimaryDivision = (d['_primaryDivision'] ?? '').toString().trim();
    final resolvedPrimaryDivision = (primaryDivision ?? '').trim().isNotEmpty
        ? primaryDivision!.trim()
        : storedPrimaryDivision.isNotEmpty
            ? storedPrimaryDivision
            : divisions.isNotEmpty
                ? divisions.first.trim()
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
      'role': d['role'] ?? '',
      'modes': List<String>.from(d['modes'] ?? const <String>[]),
      'position': d['position'] ?? '',
      'currentArea': resolvedPrimaryArea.isEmpty ? null : resolvedPrimaryArea,
      'selectedArea': resolvedPrimaryArea.isEmpty ? null : resolvedPrimaryArea,
      '_primaryDivision': resolvedPrimaryDivision,
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
    if (divisions.isEmpty) return <String>[];
    final fs = FirebaseFirestore.instance;
    final set = <String>{};

    for (var i = 0; i < divisions.length; i += 10) {
      final end = math.min(i + 10, divisions.length);
      final chunk = divisions.sublist(i, end);
      final qs = await fs
          .collection('areas')
          .where('division', whereIn: chunk)
          .get(const GetOptions(source: Source.server)).trackFirestore('QUERY', 'shared/secondary/pages/sheets/tabs/user_account_tab.dart', collection: 'areas', pathTemplate: 'areas',);


      for (final d in qs.docs) {
        final name = (d.data()['name'] ?? '').toString().trim();
        if (name.isNotEmpty) set.add(name);
      }
    }
    return set.toList()..sort();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _fetchAreasForDivision(
    String division,
  ) async {
    final qs = await FirebaseFirestore.instance
        .collection('areas')
        .where('division', isEqualTo: division)
        .get(const GetOptions(source: Source.serverAndCache)).trackFirestore('QUERY', 'shared/secondary/pages/sheets/tabs/user_account_tab.dart', collection: 'areas', pathTemplate: 'areas',);

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

  String _primaryDivisionOf(Map<String, dynamic> data) {
    final explicit = (data['_primaryDivision'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;
    final divisions = List<String>.from(data['divisions'] ?? const <String>[]);
    if (divisions.isNotEmpty) return divisions.first.trim();
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
      _primaryAreaFutures.clear();
    }
    if (oldWidget.selectedDivision != widget.selectedDivision ||
        oldWidget.selectedArea != widget.selectedArea) {
      _selectedUserId = null;
      _editingUserId = null;
      _editedUsers.clear();
    }
  }

  Future<String?> _fetchEnglishNameByArea(String division, String area) async {
    final docId = '${division.trim()}-${area.trim()}';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('areas')
          .doc(docId)
          .get(const GetOptions(source: Source.server)).trackFirestore('GET', 'shared/secondary/pages/sheets/tabs/user_account_tab.dart', collection: 'areas', pathTemplate: 'areas/*', readPurpose: 'USER_MANAGEMENT_AREA_ENGLISH_NAME_FETCH');


      final data = snap.data();
      final englishName = (data?['englishName'] ?? '').toString().trim();
      return englishName.isEmpty ? null : englishName;
    } catch (_) {
      return null;
    }
  }

  String _userListScopeKey(String division, String area) =>
      '${division.trim()}\u0000${area.trim()}';

  void _invalidateUserListScope(
    String division,
    String area, {
    required String reason,
  }) {
    final key = _userListScopeKey(division, area);
    final hadCache = _userListFutures.remove(key) != null;
    final reuses = _userListReuseCounts.remove(key) ?? 0;
    AccountRoleDiagnostics.record(
      'dev_user_list_cache_invalidated scopeId=${key.hashCode.toRadixString(16)} '
      'reason=$reason cached=$hadCache reuses=$reuses',
    );
  }

  Future<_DevUserListEntries> _usersForArea(String division, String area) {
    final key = _userListScopeKey(division, area);
    final cached = _userListFutures[key];
    if (cached != null) {
      final reuses = (_userListReuseCounts[key] ?? 0) + 1;
      _userListReuseCounts[key] = reuses;
      if (reuses == 1 || reuses % 50 == 0) {
        AccountRoleDiagnostics.record(
          'dev_user_list_fetch_reused scopeId=${key.hashCode.toRadixString(16)} '
          'reuses=$reuses',
        );
      }
      return cached;
    }

    while (_userListFutures.length >= _userListCacheLimit) {
      final oldestKey = _userListFutures.keys.first;
      _userListFutures.remove(oldestKey);
      _userListReuseCounts.remove(oldestKey);
      AccountRoleDiagnostics.record(
        'dev_user_list_cache_evicted scopeId=${oldestKey.hashCode.toRadixString(16)} '
        'reason=capacity',
      );
    }

    final requestId = ++_userListRequestSequence;
    _userListInFlightRequests[key] = requestId;
    final scopeId = key.hashCode.toRadixString(16);
    final stopwatch = Stopwatch()..start();
    AccountRoleDiagnostics.record(
      'dev_user_list_fetch_started scopeId=$scopeId requestId=$requestId '
      'reason=cache_miss',
    );

    late final Future<_DevUserListEntries> future;
    future = _fetchUsersForArea(division, area).then(
      (entries) {
        stopwatch.stop();
        if (_userListInFlightRequests[key] == requestId) {
          _userListInFlightRequests.remove(key);
        }
        AccountRoleDiagnostics.record(
          'dev_user_list_fetch_completed scopeId=$scopeId requestId=$requestId '
          'users=${entries.length} elapsedMs=${stopwatch.elapsedMilliseconds} '
          'cached=${identical(_userListFutures[key], future)}',
        );
        return entries;
      },
      onError: (Object error, StackTrace stackTrace) {
        stopwatch.stop();
        if (_userListInFlightRequests[key] == requestId) {
          _userListInFlightRequests.remove(key);
        }
        if (identical(_userListFutures[key], future)) {
          _userListFutures.remove(key);
          _userListReuseCounts.remove(key);
        }
        AccountRoleDiagnostics.recordList(
          'dev_user_list_fetch_failed reason=${error is StateError ? error.message : error.runtimeType} '
          'elapsedMs=${stopwatch.elapsedMilliseconds}',
        );
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _userListFutures[key] = future;
    return future;
  }

  void _refreshSelectedUserList({required String reason}) {
    final division = widget.selectedDivision?.trim();
    final area = widget.selectedArea?.trim();
    if (division == null || division.isEmpty || area == null || area.isEmpty) {
      return;
    }
    final key = _userListScopeKey(division, area);
    if (_userListInFlightRequests.containsKey(key)) {
      AccountRoleDiagnostics.record(
        'dev_user_list_refresh_skipped scopeId=${key.hashCode.toRadixString(16)} '
        'reason=request_in_flight',
      );
      return;
    }
    _invalidateUserListScope(division, area, reason: reason);
    setState(() => _refreshTick++);
  }

  Future<_DevUserListEntries> _fetchUsersForArea(
    String division,
    String area,
  ) async {
    final showId = _showDocId(division, area);
    final parent = FirebaseFirestore.instance
        .collection('user_accounts_show').doc(showId);
    AccountRoleDiagnostics.recordList(
      'dev_user_map_only_start expectedGets=1 legacyQueries=0',
    );
    final snapshot = await parent.get(
      const GetOptions(source: Source.serverAndCache),
    ).trackFirestore('GET', 'shared/secondary/pages/sheets/tabs/user_account_tab.dart', collection: 'user_accounts_show', pathTemplate: 'user_accounts_show/*', readPurpose: 'USER_MANAGEMENT_ACCOUNT_LIST_SHOW_FETCH');
    try {
      final entries = UserAccountShowMap.validatedEntries(snapshot.data());
      AccountRoleDiagnostics.recordList(
        'dev_user_map_only_complete users=${entries.length} documentGetRequests=1 legacyQueries=0 fromCache=${snapshot.metadata.isFromCache}',
      );
      return entries;
    } catch (error) {
      AccountRoleDiagnostics.recordList(
        'dev_user_map_only_failed reason=${error is StateError ? error.message : error.runtimeType}',
      );
      rethrow;
    }
  }

  String _showDocId(String? division, String? area) {
    final d = (division ?? '').trim().isEmpty ? 'unknownDivision' : (division ?? '').trim();
    final a = (area ?? '').trim().isEmpty ? 'unknownArea' : (area ?? '').trim();
    return '$d-$a';
  }

  Future<void> _showAccountSaveFailureDialog(
    Object e, {
    required String fallbackTitle,
  }) async {
    final raw = e.toString();
    if (raw.contains('MANUAL_CODE_NOT_AUTHORIZED')) {
      await StatusDialog.showFailure(
        context,
        title: '개발자 인증이 필요합니다',
        description: '개발자 모드와 계정 인증 상태를 확인하세요.',
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
        description: '코드번호 또는 계정 ID가 중복되었습니다.',
        useCommonUi: true,
      );
      return;
    }
    await StatusDialog.showFailure(
      context,
      title: fallbackTitle,
      description: '계정 저장 중 문제가 발생했습니다. 입력값과 네트워크 상태를 확인하세요.',
      useCommonUi: true,
    );
  }

  Future<void> _saveChanges(
    String oldId,
    Map<String, dynamic> oldData,
    Map<String, dynamic> newData,
  ) async {
    var primaryDivision = _primaryDivisionOf(newData);
    var primaryArea = _primaryAreaOf(newData);
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '운영 계정 수정',
      initialMessage: '운영 계정 수정 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 운영 계정 수정 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 운영 계정 수정 로그를 콘솔에 기록합니다.',
    );

    var serverCommitted = false;
    try {
      final requesterRole = _requireRequesterManagerRole('update');
      final originalSnapshot = await FirebaseFirestore.instance
          .collection('user_accounts')
          .doc(oldId)
          .get(const GetOptions(source: Source.server))
          .trackFirestore(
            'GET',
            'shared/secondary/pages/sheets/tabs/user_account_tab.dart',
            collection: 'user_accounts',
            pathTemplate: 'user_accounts/*',
            readPurpose: 'USER_MANAGEMENT_EDIT_ORIGINAL_SERVER_VALIDATION',
          );
      if (!originalSnapshot.exists || originalSnapshot.data() == null) {
        throw StateError('USER_NOT_FOUND');
      }
      final storedData = originalSnapshot.data()!;
      primaryDivision = _primaryDivisionOf(storedData);
      primaryArea = _primaryAreaOf(storedData);
      trace.log('account_assignments_read_from_server assignedCount=${List<dynamic>.from(storedData['areas'] ?? const <dynamic>[]).length}');
      if (RoleType.fromName((newData['role'] ?? '').toString()) == null) {
        throw StateError('INVALID_ACCOUNT_ROLE');
      }
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
      final normalizedNewData = <String, dynamic>{...storedData, ...newData};
      normalizedNewData['divisions'] =
          List<String>.from(storedData['divisions'] ?? const <String>[]);
      normalizedNewData['areas'] =
          List<String>.from(storedData['areas'] ?? const <String>[]);
      normalizedNewData['currentArea'] = storedData['currentArea'];
      normalizedNewData['selectedArea'] = storedData['selectedArea'];
      normalizedNewData['englishSelectedAreaName'] =
          storedData['englishSelectedAreaName'] ?? englishName;
      normalizedNewData.remove('_primaryDivision');

      final user = UserModel.fromMap(newId, normalizedNewData);
      trace.log(
        '현재 소속 검증 완료: division=$primaryDivision area=$primaryArea oldId=$oldId newId=$newId',
        progress: 0.18,
      );
      trace.log(
        'DevUserWriteService 전용 경로로 원본/경량 View 업데이트를 요청합니다. breakDays=${user.breakDays.join(',')}',
        progress: 0.38,
      );
      final previousDivision = (widget.selectedDivision ?? '').trim();
      final previousArea = (widget.selectedArea ?? '').trim();
      if (previousDivision.isEmpty || previousArea.isEmpty) {
        throw StateError('PREVIOUS_PRIMARY_ASSIGNMENT_REQUIRED');
      }
      await _devUserWriteService.updateUser(
        requesterRole: requesterRole,
        user: user,
        previousUserId: oldId,
        previousDivision: previousDivision,
        previousArea: previousArea,
        targetDivision: primaryDivision,
        targetArea: primaryArea,
        log: (message) => trace.log(message),
      );
      serverCommitted = true;
      AccountRoleDiagnostics.recordList(
        'ops_user_update_server_committed transaction=true',
      );
      _invalidateUserListScope(
        previousDivision,
        previousArea,
        reason: 'account_update_previous_scope',
      );
      if (previousDivision != primaryDivision || previousArea != primaryArea) {
        _invalidateUserListScope(
          primaryDivision,
          primaryArea,
          reason: 'account_update_target_scope',
        );
      }
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
        _editingUserId = null;
        _refreshTick++;
      });
    } catch (e, st) {
      if (serverCommitted) {
        AccountRoleDiagnostics.recordList(
          'ops_user_update_postcommit_failed type=${e.runtimeType} serverCommitted=true',
        );
        debugPrint('[ACCOUNT_UPDATE] serverCommitted=true uiFollowup=${e.runtimeType}');
        if (mounted) {
          setState(() {
            _selectedUserId = null;
            _editingUserId = null;
            _refreshTick++;
          });
          if (!trace.developerMode) {
            try {
              await StatusDialog.showSuccess(
                context,
                title: StatusDialog.userAccountSaveSuccess,
                useCommonUi: true,
              );
            } catch (_) {}
          }
        }
        return;
      }
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
      await _showAccountSaveFailureDialog(
        e,
        fallbackTitle: StatusDialog.userAccountSaveFailed,
      );
    }
  }

  Future<void> _openCreateDialog(List<String> divisionList) async {
    if (_creating) return;
    final manualCodeAllowed = await _isManualCodeAuthorized();
    if (!mounted) return;

    final draft = await showCommonOverlayDialog<_CreateUserAccountDraft>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _CreateUserAccountDialog(
        divisionList: divisionList,
        roleList: _roles,
        initialDivision: widget.selectedDivision,
        initialArea: widget.selectedArea,
        manualCodeAllowed: manualCodeAllowed,
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

    var serverCommitted = false;
    try {
      final requesterRole = _requireRequesterManagerRole('create');
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
        role: draft.role,
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
        '전역 코드 인덱스 정책 적용: user_account_codes reservation과 일반 User 저장을 동일 batch로 요청합니다.',
        progress: 0.34,
      );
      trace.log(
        'DevUserWriteService 전용 경로로 계정 생성을 요청합니다. breakDays=${user.breakDays.join(',')}',
        progress: 0.38,
      );
      await _devUserWriteService.createUser(
        requesterRole: requesterRole,
        user: user,
        division: draft.division,
        area: draft.area,
        log: (message) => trace.log(message),
      );
      serverCommitted = true;
      AccountRoleDiagnostics.recordCreation(
        'ops_user_create_server_committed writes=3',
      );
      _invalidateUserListScope(
        draft.division,
        draft.area,
        reason: 'account_create_success',
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
      if (serverCommitted) {
        AccountRoleDiagnostics.recordCreation(
          'ops_user_create_postcommit_failed type=${e.runtimeType} serverCommitted=true',
        );
        debugPrint('[ACCOUNT_CREATE] serverCommitted=true uiFollowup=${e.runtimeType}');
        if (mounted) {
          setState(() => _refreshTick++);
          if (!trace.developerMode) {
            try {
              await StatusDialog.showSuccess(
                context,
                title: StatusDialog.userAccountSaveSuccess,
                useCommonUi: true,
              );
            } catch (_) {}
          }
        }
        return;
      }
      debugPrint('❌ 계정 생성 실패: $e');
      await trace.fail(
        '운영 계정 생성 중 예외가 발생했습니다.',
        error: e,
        stackTrace: st,
      );
      if (!mounted || trace.developerMode) return;
      await _showAccountSaveFailureDialog(
        e,
        fallbackTitle: StatusDialog.userAccountSaveFailed,
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
                        _editingUserId = null;
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
                                  setState(() {
                                    _selectedUserId = null;
                                    _editingUserId = null;
                                  });
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
    final canRefresh = !_creating && _savingIds.isEmpty &&
        (widget.selectedDivision ?? '').trim().isNotEmpty &&
        (widget.selectedArea ?? '').trim().isNotEmpty;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
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
                    '계정 원본과 경량 목록 정보를 함께 저장합니다.',
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
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: CommonIconButton(
                key: ValueKey<String>('user_list_refresh_$_refreshTick'),
                icon: Icons.refresh_rounded,
                tooltip: '계정 목록 새로고침',
                onPressed: canRefresh
                    ? () => _refreshSelectedUserList(reason: 'manual_refresh')
                    : null,
                haptic: CommonHaptic.selection,
              ),
            ),
            const SizedBox(width: 6),
            AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              switchInCurve: CommonUiMotion.enter,
              switchOutCurve: CommonUiMotion.exit,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
                  child: child,
                ),
              ),
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
    required List<String> divisionList,
  }) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final primaryDivision = _primaryDivisionOf(updated);
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
              onChanged: null,
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
                          onChanged: null,
                          decoration: opsInputDecoration(
                            context,
                            label: '현재 지역',
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

  Future<void> _openUserEditor(
    String id, {
    required String division,
    required String area,
  }) async {
    if (_loadingRootUserId != null || _selectedUserId != id) return;
    setState(() => _loadingRootUserId = id);
    AccountRoleDiagnostics.recordList(
      'dev_user_edit_root_load_start reason=explicit_edit',
    );
    try {
      final original = await FirebaseFirestore.instance
          .collection('user_accounts')
          .doc(id)
          .get(const GetOptions(source: Source.server))
          .trackFirestore(
            'GET',
            'shared/secondary/pages/sheets/tabs/user_account_tab.dart',
            collection: 'user_accounts',
            pathTemplate: 'user_accounts/*',
           readPurpose: 'USER_MANAGEMENT_EDIT_ROOT_SERVER_FETCH');
      if (!original.exists || original.data() == null) {
        throw StateError('USER_NOT_FOUND');
      }
      if (!mounted || _selectedUserId != id ||
          widget.selectedDivision != division || widget.selectedArea != area) {
        return;
      }
      setState(() {
        _editedUsers[id] = _copyUser(
          original.data()!,
          primaryDivision: division,
          primaryArea: area,
        );
        _editingUserId = id;
      });
      AccountRoleDiagnostics.recordList(
        'dev_user_edit_root_load_complete found=true firestoreGets=1',
      );
    } catch (error) {
      AccountRoleDiagnostics.recordList(
        'dev_user_edit_root_load_failed reason=${error is StateError ? error.message : error.runtimeType}',
      );
      if (!mounted) return;
      await StatusDialog.showFailure(
        context,
        title: '계정 원본을 불러오지 못했습니다',
        description: '네트워크 상태를 확인하고 다시 시도하세요.',
        useCommonUi: true,
      );
    } finally {
      if (mounted) setState(() => _loadingRootUserId = null);
    }
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
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final division in List<String>.from(updated['divisions'] ?? const <String>[]))
              InputChip(label: Text(division)),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '접근 가능 지역 · DB에서 관리',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final area in List<String>.from(updated['areas'] ?? const <String>[]))
              InputChip(label: Text(area)),
          ],
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _roles.contains(updated['role']) ? updated['role'] as String : null,
          items: _roles
              .map(
                (role) => DropdownMenuItem<String>(
                  value: role,
                  child: Text(RoleType.fromName(role)?.label ?? role),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              updated['role'] = value;
              _editedUsers[id] = _copyUser(updated);
            });
          },
          decoration: opsInputDecoration(
            context,
            label: 'Role',
            prefixIcon: const Icon(Icons.admin_panel_settings_rounded),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '허용 모드: ${List<String>.from(updated['modes'] ?? const <String>[]).join(', ')}',
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
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .035),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: FutureBuilder<List<MapEntry<String, Map<String, dynamic>>>>(
          key: ValueKey<String>('$division-$area-$_refreshTick'),
          future: _usersForArea(division, area),
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
                  message: snapshot.error.toString().contains(
                          'USER_ACCOUNT_VIEW_MISSING')
                      ? '계정 목록 문서가 없습니다. 관리자 복구가 필요합니다.'
                      : snapshot.error.toString().contains(
                          'USER_ACCOUNT_VIEW_USERS_INVALID')
                          ? '계정 목록 데이터 형식을 확인해야 합니다.'
                      : snapshot.error.toString(),
                ),
              );
            }
            final docs = snapshot.data ?? const <MapEntry<String, Map<String, dynamic>>>[];
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
                final data = doc.value;
                final id = doc.key;
                final base = _editedUsers[id] ?? _copyUser(
                  data,
                  primaryDivision: division,
                  primaryArea: area,
                );
                final updated = _copyUser(base);
                final selected = _selectedUserId == id;
                final active = (updated['isActive'] as bool?) ?? true;
                final role = (updated['role'] ?? '').toString();
                final position = (updated['position'] ?? '').toString().trim();
                return CommonAnimatedReveal(
                  delay: reduceMotion ? Duration.zero : Duration(milliseconds: index * 22),
                  offset: const Offset(.016, 0),
                  child: OpsDockSelectableRowSurface(
                    selected: selected,
                    selectionColor: tokens.accent,
                    selectedContainer: tokens.accentContainer,
                    onTap: () {
                      if (_loadingRootUserId != null) return;
                      setState(() {
                        _selectedUserId = selected ? null : id;
                        _editingUserId = null;
                        if (selected) _editedUsers.remove(id);
                      });
                      AccountRoleDiagnostics.recordList(
                        'dev_user_row_selection source=view rootGets=0',
                      );
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
                                    '$role${position.isEmpty ? '' : ' · $position'} · ${active ? '활성' : '비활성'}',
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
                            AnimatedSwitcher(
                              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                              child: _loadingRootUserId == id
                                  ? SizedBox(
                                      key: ValueKey<String>('root_loading_$id'),
                                      width: 20,
                                      height: 20,
                                      child: const CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : AnimatedRotation(
                                      key: ValueKey<String>('root_loaded_$id'),
                                      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                                      turns: selected ? .5 : 0,
                                      child: Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: tokens.iconSecondary,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                        AnimatedSize(
                          duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: selected
                              ? AnimatedSwitcher(
                                  duration: reduceMotion
                                      ? Duration.zero
                                      : CommonUiMotion.selection,
                                  switchInCurve: CommonUiMotion.enter,
                                  switchOutCurve: CommonUiMotion.exit,
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, -0.035),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                                  child: _editingUserId == id
                                      ? KeyedSubtree(
                                          key: ValueKey<String>('editor_$id'),
                                          child: _buildUserEditor(
                                            context,
                                            id: id,
                                            data: data,
                                            updated: updated,
                                            divisionList: divisionList,
                                          ),
                                        )
                                      : Padding(
                                          key: ValueKey<String>('open_editor_$id'),
                                          padding: const EdgeInsets.only(top: 10),
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: OutlinedButton.icon(
                                              onPressed: _loadingRootUserId == null
                                                  ? () => _openUserEditor(
                                                        id,
                                                        division: division,
                                                        area: area,
                                                      )
                                                  : null,
                                              icon: const Icon(Icons.edit_outlined),
                                              label: const Text('상세 수정'),
                                            ),
                                          ),
                                        ),
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
      ),
    );
  }

  @override
  void dispose() {
    _userListFutures.clear();
    _userListReuseCounts.clear();
    _userListInFlightRequests.clear();
    super.dispose();
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
    required this.role,
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
  final String role;
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
    required this.roleList,
    required this.initialDivision,
    required this.initialArea,
    required this.manualCodeAllowed,
    required this.onRequestManualCodeEntry,
    required this.fetchAreasForDivision,
  });

  final List<String> divisionList;
  final List<String> roleList;
  final String? initialDivision;
  final String? initialArea;
  final bool manualCodeAllowed;
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
  String _selectedRole = 'branchStaff';
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
    _selectedRole = widget.roleList.contains('branchStaff')
        ? 'branchStaff'
        : (widget.roleList.isNotEmpty ? widget.roleList.last : 'branchStaff');
    _codeNumberController.text = AccountCodeNumber.format(AccountCodeNumber.generate());
    _startByDay = <String, TimeOfDay?>{
      for (final day in _days) day: null,
    };
    _endByDay = <String, TimeOfDay?>{
      for (final day in _days) day: null,
    };
    _breakDays = Set<String>.of(_days);
    _loadAreas(keepInitialArea: true);
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

  void _submit() {
    final error = _validate();
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }

    Navigator.of(context).pop(
      _CreateUserAccountDraft(
        name: _nameController.text.trim(),
        codeNumber: _normalizedCodeNumber(),
        codeEntryMode: _codeEntryMode,
        email: '${_emailController.text.trim()}@gmail.com',
        division: _selectedDivision!.trim(),
        area: _selectedArea!.trim(),
        role: _selectedRole,
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
        setState(() => _errorText = '개발자 계정 인증에 실패했습니다');
        final developerMode = await DevAuth.isDevModeEnabled();
        if (developerMode && mounted) {
          await StatusDialog.showFailure(
            context,
            title: '코드번호 직접 입력 인증 실패',
            description: '개발자 계정 재인증에 실패했습니다.',
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
              label: Text(mode),
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
                      DropdownButtonFormField<String>(
                        value: widget.roleList.contains(_selectedRole)
                            ? _selectedRole
                            : null,
                        isExpanded: true,
                        decoration: opsInputDecoration(
                          context,
                          label: 'Role',
                          prefixIcon: const Icon(Icons.admin_panel_settings_rounded),
                        ),
                        items: widget.roleList
                            .map(
                              (role) => DropdownMenuItem<String>(
                                value: role,
                                child: Text(
                                  RoleType.fromName(role)?.label ?? role,
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
                            _selectedRole = value;
                          });
                        },
                      ),
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
