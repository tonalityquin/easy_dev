import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/di/routes.dart';
import '../../../../app/utils/dev_firebase_debug_dialog.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/tablet/applications/tablet_pad_mode_state.dart';
import '../../../../shared/auth/account_code_number.dart';
import 'personal_account_diagnostics.dart';
import '../../applications/tablet/tablet_login_network_service.dart';
import '../area_login_session_refresher.dart';

String _ts() => DateTime.now().toIso8601String();

class PersonalLoginResult {
  const PersonalLoginResult({
    required this.success,
    required this.message,
    this.copyText,
  });

  final bool success;
  final String message;
  final String? copyText;
}


class PersonalAuthenticatedAccount {
  const PersonalAuthenticatedAccount({
    required this.documentId,
    required this.data,
    required this.name,
    required this.codeNumber,
    required this.selectedArea,
    required this.division,
  });

  final String documentId;
  final Map<String, dynamic> data;
  final String name;
  final String codeNumber;
  final String selectedArea;
  final String division;
}

enum PersonalIdentityFailureKind {
  none,
  invalidInput,
  networkError,
  accountNotFound,
  inactiveAccount,
  nameMismatch,
  ambiguousAccount,
  invalidAccountData,
  lookupError,
}

class PersonalCredentialAuthenticationResult {
  const PersonalCredentialAuthenticationResult({
    required this.success,
    required this.message,
    this.account,
    this.copyText,
    this.failureKind = PersonalIdentityFailureKind.none,
  });

  final bool success;
  final String message;
  final PersonalAuthenticatedAccount? account;
  final String? copyText;
  final PersonalIdentityFailureKind failureKind;
}

class PersonalAccountCreateResult {
  const PersonalAccountCreateResult({
    required this.success,
    required this.message,
    this.codeNumber,
  });

  final bool success;
  final String message;
  final String? codeNumber;
}

class PersonalLoginController {
  PersonalLoginController(this.context);

  final BuildContext context;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController codeNumberController = TextEditingController();

  final FocusNode nameFocus = FocusNode();
  final FocusNode codeNumberFocus = FocusNode();

  bool isLoading = false;
  bool isLoggedIn = false;
  String? loggedInAccountId;
  String? loggedInName;

  bool _inited = false;

  CollectionReference<Map<String, dynamic>> get _personalAccountsRef =>
      _firestore.collection('personal_accounts');

  PadMode get _targetPadMode => PadMode.mobile;

  String get _savedMode => 'personal';


  void initState() {
    if (_inited) return;
    _inited = true;
    unawaited(tryRestoreSession());
  }

  Future<bool> tryRestoreSession({bool navigateOnSuccess = true}) async {
    var mode = '';
    var codeNumber = '';
    var selectedArea = '';
    var accountId = '';

    try {
      final prefs = await SharedPreferences.getInstance();
      mode = (prefs.getString('mode') ?? '').trim().toLowerCase();
      codeNumber = _normalizeCodeNumber(
        prefs.getString('personalCodeNumber') ?? prefs.getString('codeNumber') ?? '',
      );
      selectedArea = (prefs.getString('selectedArea') ?? '').trim();
      if (mode != _savedMode || codeNumber.isEmpty || selectedArea.isEmpty) {
        return false;
      }

      accountId = _accountDocId(codeNumber: codeNumber, area: selectedArea);
      if (accountId.isEmpty) return false;

      final snap = await _personalAccountsRef.doc(accountId).get();
      final data = snap.data();
      final active = (data?['isActive'] as bool?) ?? true;
      if (!snap.exists || data == null || !active) return false;

      final storedCodeNumber = _codeNumberFromData(data, fallback: codeNumber);
      final storedSelectedArea = _selectedAreaFromData(data);
      if (storedCodeNumber != codeNumber || storedSelectedArea != selectedArea) {
        return false;
      }

      if (!context.mounted) return false;
      final division = _divisionFromData(data);
      final areaState = context.read<AreaState>();
      await AreaLoginSessionRefresher.refresh(
        context: context,
        areaState: areaState,
        division: division,
        area: storedSelectedArea,
        operationLabel: 'personal-restore',
      );
      if (!context.mounted) return false;

      isLoggedIn = true;
      loggedInAccountId = snap.id;
      loggedInName =
          (data['name'] ?? prefs.getString('personalName') ?? '').toString();
      nameController.text = loggedInName ?? '';
      codeNumberController.text = _formatCodeNumberForDisplay(storedCodeNumber);
      context.read<TabletPadModeState>().setMode(_targetPadMode);
      if (navigateOnSuccess) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          Navigator.of(context).pushReplacementNamed(AppRoutes.personal);
        });
      }
      debugPrint(
        '[LOGIN-PERSONAL][${_ts()}] restore personal session ok: ${snap.id}',
      );
      return true;
    } catch (e, st) {
      debugPrint(
        '[LOGIN-PERSONAL][${_ts()}] restore personal session error: $e\n$st',
      );
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'personal_accounts.restoreSession',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'personal_accounts',
          'docId': accountId,
          'mode': mode,
          'codeNumber': AccountCodeNumber.mask(codeNumber),
          'selectedArea': selectedArea,
          'read': 'doc($accountId).get()',
          'queryShape': 'direct-document-read',
          'compositeIndex': 'not-required',
        },
      );
      return false;
    }
  }

  String _normalizeCodeNumber(String value) {
    return AccountCodeNumber.normalize(value);
  }

  String _formatCodeNumberForDisplay(String value) {
    return AccountCodeNumber.format(value);
  }

  String _normalizeGmail(String value) {
    final raw = value.trim().toLowerCase();
    if (raw.isEmpty) return '';
    if (raw.contains('@')) return raw;
    return '$raw@gmail.com';
  }

  String _normalizeArea(String value) {
    return value.trim();
  }

  String _accountDocId({
    required String codeNumber,
    required String area,
  }) {
    final normalized = _normalizeCodeNumber(codeNumber);
    final normalizedArea = _normalizeArea(area);
    if (!AccountCodeNumber.isValid(normalized) || normalizedArea.isEmpty) {
      return '';
    }
    return AccountCodeNumber.documentId(
      codeNumber: normalized,
      area: normalizedArea,
    );
  }

  bool _isLegacyNumericCodeNumber(String value) {
    return RegExp(r'^\d{10,11}$').hasMatch(_normalizeCodeNumber(value));
  }

  String _codeNumberFromData(
    Map<String, dynamic> data, {
    String fallback = '',
  }) {
    final candidates = <Object?>[
      data['codeNumber'],
      data['phone'],
      data['personalPhone'],
      data['handle'],
      fallback,
    ];
    for (final candidate in candidates) {
      final normalized = _normalizeCodeNumber((candidate ?? '').toString());
      if (AccountCodeNumber.isValid(normalized)) return normalized;
    }
    for (final candidate in candidates) {
      final normalized = _normalizeCodeNumber((candidate ?? '').toString());
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _findPersonalAccountCandidates(String codeNumber) async {
    final normalized = _normalizeCodeNumber(codeNumber);
    if (!AccountCodeNumber.isValid(normalized)) {
      return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }
    final legacyNumeric = _isLegacyNumericCodeNumber(normalized);
    final fields = <String>[
      'codeNumber',
      if (legacyNumeric) 'phone',
      if (legacyNumeric) 'personalPhone',
      if (legacyNumeric) 'handle',
    ];
    PersonalAccountDiagnostics.record(
      'credential_candidates_lookup_start',
      meta: <String, Object?>{
        'codeNumber': AccountCodeNumber.mask(normalized),
        'legacyNumeric': legacyNumeric,
        'fields': fields.join(','),
      },
    );
    final snapshots = await Future.wait(
      fields.map(
        (field) => _personalAccountsRef
            .where(field, isEqualTo: normalized)
            .limit(20)
            .get(),
      ),
    );
    final byId =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        byId[doc.id] = doc;
      }
    }
    final result = byId.values.toList(growable: false);
    PersonalAccountDiagnostics.record(
      'credential_candidates_lookup_complete',
      meta: <String, Object?>{
        'codeNumber': AccountCodeNumber.mask(normalized),
        'legacyNumeric': legacyNumeric,
        'count': result.length,
        'documentIds': result
            .map((doc) => AccountCodeNumber.maskDocumentId(doc.id))
            .join(','),
      },
    );
    return result;
  }

  List<String> _stringListFromDynamic(dynamic value) {
    if (value is Iterable) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    final v = (value ?? '').toString().trim();
    return v.isEmpty ? const <String>[] : <String>[v];
  }

  String _selectedAreaFromData(Map<String, dynamic> data) {
    final selectedArea = (data['selectedArea'] ?? '').toString().trim();
    if (selectedArea.isNotEmpty) return selectedArea;
    final currentArea = (data['currentArea'] ?? '').toString().trim();
    if (currentArea.isNotEmpty) return currentArea;
    final areas = _stringListFromDynamic(data['areas']);
    return areas.isNotEmpty ? areas.first : '';
  }

  String _divisionFromData(Map<String, dynamic> data) {
    final divisions = _stringListFromDynamic(data['divisions']);
    return divisions.isNotEmpty ? divisions.first : '';
  }

  String? _validateName(String name) {
    if (name.trim().isEmpty) return '이름을 입력하세요.';
    return null;
  }

  String? _validateLoginCodeNumber(String codeNumber) {
    final normalized = _normalizeCodeNumber(codeNumber);
    if (normalized.isEmpty) return '코드번호를 입력하세요.';
    if (!AccountCodeNumber.isValid(normalized)) {
      return '유효한 코드번호를 입력하세요.';
    }
    return null;
  }

  String? _validateGeneratedCodeNumber(String codeNumber) {
    final normalized = _normalizeCodeNumber(codeNumber);
    if (normalized.isEmpty) return '코드번호를 입력하세요.';
    if (!AccountCodeNumber.isGeneratedCode(normalized)) {
      return '신규 코드번호 형식을 확인하세요.';
    }
    return null;
  }

  String? _validateGmail(String gmail) {
    final normalized = _normalizeGmail(gmail);
    if (normalized.isEmpty) return '지메일 계정을 입력하세요.';
    final re = RegExp(r'^[a-z0-9._%+-]+@gmail\.com$');
    if (!re.hasMatch(normalized)) return 'gmail.com 계정만 입력할 수 있습니다.';
    return null;
  }

  String? _validateArea(String area) {
    if (_normalizeArea(area).isEmpty) return '지역을 입력하세요.';
    return null;
  }


  String? _validateDivision(String division) {
    if (division.trim().isEmpty) return '구역을 입력하세요.';
    return null;
  }


  String? validatePersonalInputs({
    required String name,
    required String codeNumber,
  }) {
    return _validateName(name) ?? _validateLoginCodeNumber(codeNumber);
  }


  String? validatePersonalAccountCreateInputs({
    required String name,
    required String codeNumber,
    required String gmail,
    required String area,
    required String division,
  }) {
    return _validateName(name) ??
        _validateGeneratedCodeNumber(codeNumber) ??
        _validateGmail(gmail) ??
        _validateArea(area) ??
        _validateDivision(division);
  }

  String _buildLoginFailureCopyText({
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final inputName = nameController.text.trim();
    final inputCodeNumber = _normalizeCodeNumber(codeNumberController.text);
    final lines = <String>[
      '개인형 계정 확인 실패',
      '시간: ${DateTime.now().toIso8601String()}',
      '사유: $message',
      '컬렉션: personal_accounts',
      '입력 이름: $inputName',
      '입력 코드번호: ${AccountCodeNumber.mask(inputCodeNumber)}',
      if (error != null) '오류: $error',
      if (stackTrace != null) '스택: $stackTrace',
    ];
    return lines.join('\n');
  }

  PersonalLoginResult _loginFailureResult(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    return PersonalLoginResult(
      success: false,
      message: message,
      copyText: _buildLoginFailureCopyText(
        message: message,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  Map<String, dynamic> _newPersonalAccountMap({
    required String name,
    required String codeNumber,
    required String email,
    required String area,
    required String division,
  }) {
    final normalizedCodeNumber = _normalizeCodeNumber(codeNumber);
    final normalizedArea = _normalizeArea(area);
    final normalizedDivision = division.trim();
    return <String, dynamic>{
      'name': name.trim(),
      'codeNumber': normalizedCodeNumber,
      'email': _normalizeGmail(email),
      'gmail': _normalizeGmail(email),
      'mode': 'personal',
      'modes': const <String>['personal'],
      'role': 'personal',
      'areas': <String>[normalizedArea],
      'divisions': <String>[normalizedDivision],
      'currentArea': normalizedArea,
      'selectedArea': normalizedArea,
      'isActive': true,
      'isSaved': false,
      'isWorking': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  String generatePersonalCodeNumber() {
    return AccountCodeNumber.generate();
  }

  Future<PersonalAccountCreateResult> createPersonalAccount({
    required String name,
    required String codeNumber,
    required String gmail,
    required String area,
    required String division,
  }) async {
    final error = validatePersonalAccountCreateInputs(
      name: name,
      codeNumber: codeNumber,
      gmail: gmail,
      area: area,
      division: division,
    );
    if (error != null) {
      return PersonalAccountCreateResult(success: false, message: error);
    }

    final isConn = await TabletLoginNetworkService().isConnected();
    if (!isConn) {
      return const PersonalAccountCreateResult(
        success: false,
        message: '네트워크 연결을 확인하세요.',
      );
    }

    final email = _normalizeGmail(gmail);
    final normalizedArea = _normalizeArea(area);
    var normalizedCodeNumber = _normalizeCodeNumber(codeNumber);
    PersonalAccountDiagnostics.clear();
    PersonalAccountDiagnostics.record(
      'create_start',
      meta: <String, Object?>{
        'codeNumber': AccountCodeNumber.mask(normalizedCodeNumber),
        'area': normalizedArea,
        'division': division.trim(),
      },
    );

    try {
      var attempts = 0;
      while (attempts < 8) {
        final duplicate = await _personalAccountsRef
            .where('codeNumber', isEqualTo: normalizedCodeNumber)
            .limit(1)
            .get();
        if (duplicate.docs.isEmpty) break;
        attempts += 1;
        normalizedCodeNumber = AccountCodeNumber.generate();
        PersonalAccountDiagnostics.record(
          'create_code_regenerated',
          meta: <String, Object?>{
            'attempt': attempts,
            'codeNumber': AccountCodeNumber.mask(normalizedCodeNumber),
          },
        );
      }

      final duplicate = await _personalAccountsRef
          .where('codeNumber', isEqualTo: normalizedCodeNumber)
          .limit(1)
          .get();
      if (duplicate.docs.isNotEmpty) {
        throw StateError('CODE_NUMBER_GENERATION_FAILED');
      }

      final docId = _accountDocId(
        codeNumber: normalizedCodeNumber,
        area: normalizedArea,
      );
      if (docId.isEmpty) {
        throw StateError('INVALID_PERSONAL_DOCUMENT_ID');
      }
      final docRef = _personalAccountsRef.doc(docId);
      final existingDoc = await docRef.get();
      if (existingDoc.exists) {
        throw StateError('PERSONAL_DOCUMENT_ID_CONFLICT');
      }

      await docRef.set(
        _newPersonalAccountMap(
          name: name,
          codeNumber: normalizedCodeNumber,
          email: email,
          area: normalizedArea,
          division: division,
        ),
      );
      PersonalAccountDiagnostics.record(
        'create_success',
        meta: <String, Object?>{
          'documentId': AccountCodeNumber.maskDocumentId(docId),
          'codeNumber': AccountCodeNumber.mask(normalizedCodeNumber),
        },
      );
      await PersonalAccountDiagnostics.showStatusDialog(
        context,
        title: '개인형 계정 생성 상태',
        description: '개인형 계정 생성이 완료되었습니다.',
      );
      return PersonalAccountCreateResult(
        success: true,
        message: '개인형 계정을 생성했습니다.',
        codeNumber: normalizedCodeNumber,
      );
    } catch (e, st) {
      PersonalAccountDiagnostics.record(
        'create_failure',
        meta: <String, Object?>{
          'error': e,
          'codeNumber': AccountCodeNumber.mask(normalizedCodeNumber),
          'area': normalizedArea,
        },
      );
      debugPrint('[LOGIN-PERSONAL][${_ts()}] create personal account error: $e\n$st');
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'personal_accounts.createPersonalAccount',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'personal_accounts',
          'codeNumber': AccountCodeNumber.mask(normalizedCodeNumber),
          'email': email,
          'area': normalizedArea,
          'division': division,
        },
      );
      await PersonalAccountDiagnostics.showStatusDialog(
        context,
        title: '개인형 계정 생성 상태',
        description: '개인형 계정을 생성하지 못했습니다.',
        failure: true,
      );
      return const PersonalAccountCreateResult(
        success: false,
        message: '계정을 생성하지 못했습니다.',
      );
    }
  }

  Future<PersonalCredentialAuthenticationResult> resolveIdentity({
    String? name,
    String? codeNumber,
  }) async {
    final resolvedName = (name ?? nameController.text).trim();
    final resolvedCodeNumber = _normalizeCodeNumber(
      codeNumber ?? codeNumberController.text,
    );

    final error = validatePersonalInputs(
      name: resolvedName,
      codeNumber: resolvedCodeNumber,
    );
    if (error != null) {
      final failure = _loginFailureResult(error);
      return PersonalCredentialAuthenticationResult(
        success: false,
        message: failure.message,
        copyText: failure.copyText,
        failureKind: PersonalIdentityFailureKind.invalidInput,
      );
    }

    final isConn = await TabletLoginNetworkService().isConnected();
    if (!isConn) {
      final failure = _loginFailureResult('네트워크 연결을 확인하세요.');
      return PersonalCredentialAuthenticationResult(
        success: false,
        message: failure.message,
        copyText: failure.copyText,
        failureKind: PersonalIdentityFailureKind.networkError,
      );
    }

    try {
      final candidates =
          await _findPersonalAccountCandidates(resolvedCodeNumber);

      PersonalCredentialAuthenticationResult failureResult(
        String message,
        PersonalIdentityFailureKind failureKind,
      ) {
        final failure = _loginFailureResult(message);
        return PersonalCredentialAuthenticationResult(
          success: false,
          message: failure.message,
          copyText: failure.copyText,
          failureKind: failureKind,
        );
      }

      if (candidates.isEmpty) {
        return failureResult(
          '개인형 계정을 찾을 수 없습니다.',
          PersonalIdentityFailureKind.accountNotFound,
        );
      }

      final activeCandidates = candidates.where((doc) {
        final data = doc.data();
        return (data['isActive'] as bool?) ?? true;
      }).toList(growable: false);
      if (activeCandidates.isEmpty) {
        return failureResult(
          '비활성화된 개인형 계정입니다.',
          PersonalIdentityFailureKind.inactiveAccount,
        );
      }

      final matches = activeCandidates.where((doc) {
        final data = doc.data();
        final storedName = (data['name'] ?? '').toString().trim();
        final storedCodeNumber = _codeNumberFromData(data);
        return storedName == resolvedName &&
            storedCodeNumber == resolvedCodeNumber;
      }).toList(growable: false);

      PersonalAccountDiagnostics.record(
        'manual_identity_candidates_resolved',
        meta: <String, Object?>{
          'codeNumber': AccountCodeNumber.mask(resolvedCodeNumber),
          'candidateCount': candidates.length,
          'activeCandidateCount': activeCandidates.length,
          'identityMatchCount': matches.length,
        },
      );
      if (matches.isEmpty) {
        return failureResult(
          '입력한 계정 정보가 일치하지 않습니다.',
          PersonalIdentityFailureKind.nameMismatch,
        );
      }
      if (matches.length > 1) {
        return failureResult(
          '같은 계정 정보의 개인형 계정이 여러 업무 지역에 존재합니다.',
          PersonalIdentityFailureKind.ambiguousAccount,
        );
      }

      final matchedDoc = matches.single;
      final matchedData = matchedDoc.data();
      final storedName = (matchedData['name'] ?? '').toString().trim();
      final storedCodeNumber = _codeNumberFromData(matchedData);
      final selectedArea = _selectedAreaFromData(matchedData);
      final division = _divisionFromData(matchedData);
      if (selectedArea.isEmpty) {
        return failureResult(
          '개인형 계정의 지역 정보가 없습니다.',
          PersonalIdentityFailureKind.invalidAccountData,
        );
      }

      final expectedDocId = _accountDocId(
        codeNumber: storedCodeNumber,
        area: selectedArea,
      );
      if (matchedDoc.id != expectedDocId) {
        return failureResult(
          '개인형 계정 문서 ID가 코드번호-지역 구조와 일치하지 않습니다.',
          PersonalIdentityFailureKind.invalidAccountData,
        );
      }

      return PersonalCredentialAuthenticationResult(
        success: true,
        message: '$storedName님의 개인형 계정 정보를 확인했습니다.',
        account: PersonalAuthenticatedAccount(
          documentId: matchedDoc.id,
          data: Map<String, dynamic>.from(matchedData),
          name: storedName,
          codeNumber: storedCodeNumber,
          selectedArea: selectedArea,
          division: division,
        ),
      );
    } catch (e, st) {
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'personal_accounts.resolveIdentity',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'personal_accounts',
          'inputNameLength': resolvedName.length,
          'inputCodeNumber': AccountCodeNumber.mask(resolvedCodeNumber),
          'query': _isLegacyNumericCodeNumber(resolvedCodeNumber)
              ? 'where(codeNumber|phone|personalPhone|handle == masked).limit(20)'
              : 'where(codeNumber == masked).limit(20)',
          'queryShape': _isLegacyNumericCodeNumber(resolvedCodeNumber)
              ? 'legacy-compatible-multi-single-field-equality'
              : 'single-field-equality-with-limit',
          'orderBy': 'none',
          'limit': 20,
        },
      );
      final failure = _loginFailureResult(
        '계정 확인 중 오류가 발생했습니다.',
        error: e,
        stackTrace: st,
      );
      return PersonalCredentialAuthenticationResult(
        success: false,
        message: failure.message,
        copyText: failure.copyText,
        failureKind: PersonalIdentityFailureKind.lookupError,
      );
    }
  }

  Future<PersonalLoginResult> activateAuthenticatedAccount(
    PersonalAuthenticatedAccount account, {
    bool persistSession = true,
  }) async {
    try {
      if (!context.mounted) {
        return _loginFailureResult(
          '로그인 화면이 종료되어 Area 세션을 준비할 수 없습니다.',
        );
      }

      final areaState = context.read<AreaState>();
      await AreaLoginSessionRefresher.refresh(
        context: context,
        areaState: areaState,
        division: account.division,
        area: account.selectedArea,
        operationLabel: 'personal',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mode', _savedMode);
      await prefs.setString('codeNumber', account.codeNumber);
      await prefs.setString('selectedArea', account.selectedArea);
      await prefs.setString('division', account.division);
      await prefs.setString(
        'role',
        (account.data['role'] ?? 'personal').toString(),
      );
      await prefs.setString(
        'position',
        (account.data['position'] ?? '').toString(),
      );
      await prefs.setString('personalAccountId', account.documentId);
      await prefs.setString('personalName', account.name);
      await prefs.setString('personalCodeNumber', account.codeNumber);
      await prefs.remove('phone');
      await prefs.remove('personalPhone');

      if (persistSession) {
        await _personalAccountsRef.doc(account.documentId).set(
          <String, dynamic>{
            'isSaved': true,
            'lastLoginAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      debugPrint(
        '[LOGIN-PERSONAL][${_ts()}] session activated persistence=${persistSession ? 'persistent' : 'ephemeral'} accountId=${account.documentId} area=${account.selectedArea}',
      );

      if (context.mounted) {
        context.read<TabletPadModeState>().setMode(_targetPadMode);
      }

      isLoggedIn = true;
      loggedInAccountId = account.documentId;
      loggedInName = account.name;

      return PersonalLoginResult(
        success: true,
        message: '${account.name}님, 개인형 로그인에 성공했습니다.',
      );
    } catch (e, st) {
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'personal_accounts.activateAuthenticatedAccount',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'personal_accounts',
          'accountId': account.documentId,
          'codeNumber': AccountCodeNumber.mask(account.codeNumber),
          'area': account.selectedArea,
          'division': account.division,
          'write': persistSession
              ? 'doc(account.documentId).set(isSaved,lastLoginAt,updatedAt,merge)'
              : 'skipped_ephemeral_debug_session',
          'persistSession': persistSession,
        },
      );
      return _loginFailureResult(
        '로그인 세션을 활성화하지 못했습니다.',
        error: e,
        stackTrace: st,
      );
    }
  }

  void fillLoginFields({
    required String name,
    required String codeNumber,
  }) {
    nameController.text = name.trim();
    codeNumberController.text =
        _formatCodeNumberForDisplay(_normalizeCodeNumber(codeNumber));
  }

  void dispose() {
    nameController.dispose();
    codeNumberController.dispose();
    nameFocus.dispose();
    codeNumberFocus.dispose();
  }
}
