import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/di/routes.dart';
import '../../../../app/utils/dev_firebase_debug_dialog.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/tablet/applications/tablet_pad_mode_state.dart';
import '../../../../shared/auth/five_digit_password_generator.dart';
import '../../../selector/application/dev_auth.dart';
import '../../applications/tablet/tablet_login_network_service.dart';

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

class PersonalAccountCreateResult {
  const PersonalAccountCreateResult({
    required this.success,
    required this.message,
    this.password,
  });

  final bool success;
  final String message;
  final String? password;
}

class PersonalLoginController {
  PersonalLoginController(this.context);

  final BuildContext context;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final FocusNode nameFocus = FocusNode();
  final FocusNode phoneFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  bool isLoading = false;
  bool obscurePassword = true;
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
    _restorePersonalSession();
  }

  Future<void> _restorePersonalSession() async {
    var mode = '';
    var phone = '';
    var selectedArea = '';
    var accountId = '';

    try {
      final prefs = await SharedPreferences.getInstance();
      mode = (prefs.getString('mode') ?? '').trim().toLowerCase();
      phone = _normalizePhone(
        prefs.getString('phone') ?? prefs.getString('personalPhone') ?? '',
      );
      selectedArea = (prefs.getString('selectedArea') ?? '').trim();
      if (mode != _savedMode || phone.isEmpty || selectedArea.isEmpty) return;

      accountId = _accountDocId(phone: phone, area: selectedArea);
      if (accountId.isEmpty) return;

      final snap = await _personalAccountsRef.doc(accountId).get();
      final data = snap.data();
      final active = (data?['isActive'] as bool?) ?? true;
      if (!snap.exists || data == null || !active) return;

      final storedPhone = _normalizePhone((data['phone'] ?? phone).toString());
      final storedSelectedArea = _selectedAreaFromData(data);
      if (storedPhone != phone || storedSelectedArea != selectedArea) return;

      isLoggedIn = true;
      loggedInAccountId = snap.id;
      loggedInName = (data['name'] ?? prefs.getString('personalName') ?? '').toString();
      nameController.text = loggedInName ?? '';
      phoneController.text = _formatPhoneForDisplay(storedPhone);
      if (context.mounted) {
        final division = _divisionFromData(data);
        context.read<AreaState>().setAreaLocalOnly(
              storedSelectedArea,
              division: division,
            );
        context.read<TabletPadModeState>().setMode(_targetPadMode);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          Navigator.of(context).pushReplacementNamed(AppRoutes.personal);
        });
      }
      debugPrint('[LOGIN-PERSONAL][${_ts()}] restore personal session ok: ${snap.id}');
    } catch (e, st) {
      debugPrint('[LOGIN-PERSONAL][${_ts()}] restore personal session error: $e\n$st');
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'personal_accounts.restoreSession',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'personal_accounts',
          'docId': accountId,
          'mode': mode,
          'phone': phone,
          'selectedArea': selectedArea,
          'read': 'doc($accountId).get()',
          'queryShape': 'direct-document-read',
          'compositeIndex': 'not-required',
        },
      );
    }
  }

  String _normalizePhone(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _formatPhoneForDisplay(String digits) {
    if (digits.length <= 3) return digits;
    if (digits.length <= 7) {
      return '${digits.substring(0, 3)}-${digits.substring(3)}';
    }
    if (digits.length <= 10) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    final end = digits.length > 11 ? 11 : digits.length;
    return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7, end)}';
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
    required String phone,
    required String area,
  }) {
    return '${_normalizePhone(phone)}-${_normalizeArea(area)}'.replaceAll('/', '_');
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

  String? _validatePhone(String phone) {
    final digits = _normalizePhone(phone);
    if (digits.isEmpty) return '전화번호를 입력하세요.';
    if (!RegExp(r'^\d{9,11}$').hasMatch(digits)) return '전화번호를 다시 확인하세요.';
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

  String? _validatePassword(String password) {
    final value = password.trim();
    if (value.isEmpty) return '비밀번호를 입력하세요.';
    if (!RegExp(r'^\d{5}$').hasMatch(value)) return '비밀번호는 5자리 숫자입니다.';
    return null;
  }

  String? _validateDivision(String division) {
    if (division.trim().isEmpty) return '구역을 입력하세요.';
    return null;
  }

  String? validatePersonalInputs({
    required String name,
    required String phone,
    String? password,
  }) {
    final basicError = _validateName(name) ?? _validatePhone(phone);
    if (basicError != null) return basicError;
    if (password != null) return _validatePassword(password);
    return null;
  }

  String? validatePersonalAccountCreateInputs({
    required String name,
    required String phone,
    required String gmail,
    required String password,
    required String area,
    required String division,
  }) {
    return validatePersonalInputs(
          name: name,
          phone: phone,
          password: password,
        ) ??
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
    final inputPhone = _normalizePhone(phoneController.text);
    final inputPassword = passwordController.text.trim();
    final inputSelectedArea = '';
    final docId = inputPhone.isEmpty || inputSelectedArea.isEmpty
        ? ''
        : _accountDocId(phone: inputPhone, area: inputSelectedArea);
    final lines = <String>[
      '개인형 로그인 실패',
      '시간: ${DateTime.now().toIso8601String()}',
      '사유: $message',
      '컬렉션: personal_accounts',
      if (docId.isNotEmpty) '문서 ID: $docId',
      '입력 이름: $inputName',
      '입력 전화번호: $inputPhone',
      '입력 비밀번호 길이: ${inputPassword.length}',
      if (inputSelectedArea.isNotEmpty) '입력 지역: $inputSelectedArea',
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
    required String phone,
    required String email,
    required String password,
    required String area,
    required String division,
  }) {
    final digits = _normalizePhone(phone);
    final normalizedArea = _normalizeArea(area);
    final normalizedDivision = division.trim();
    return <String, dynamic>{
      'name': name.trim(),
      'phone': digits,
      'email': _normalizeGmail(email),
      'gmail': _normalizeGmail(email),
      'password': password.trim(),
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

  Future<bool> isDeveloperModeEnabled() async {
    return DevAuth.isDeveloperLoggedIn();
  }

  String generatePersonalPassword() {
    return FiveDigitPasswordGenerator.generate();
  }

  Future<PersonalAccountCreateResult> createPersonalAccount({
    required String name,
    required String phone,
    required String gmail,
    required String password,
    required String area,
    required String division,
  }) async {
    final error = validatePersonalAccountCreateInputs(
      name: name,
      phone: phone,
      gmail: gmail,
      password: password,
      area: area,
      division: division,
    );
    if (error != null) {
      return PersonalAccountCreateResult(success: false, message: error);
    }

    final passwordError = _validatePassword(password);
    if (passwordError != null) {
      return PersonalAccountCreateResult(success: false, message: passwordError);
    }

    final isConn = await TabletLoginNetworkService().isConnected();
    if (!isConn) {
      return const PersonalAccountCreateResult(
        success: false,
        message: '네트워크 연결을 확인하세요.',
      );
    }

    final phoneDigits = _normalizePhone(phone);
    final email = _normalizeGmail(gmail);
    final normalizedArea = _normalizeArea(area);
    final docId = _accountDocId(phone: phoneDigits, area: normalizedArea);

    try {
      final docRef = _personalAccountsRef.doc(docId);
      final snap = await docRef.get();
      if (snap.exists) {
        return const PersonalAccountCreateResult(
          success: false,
          message: '이미 등록된 전화번호/지역 개인형 계정입니다.',
        );
      }

      await docRef.set(
        _newPersonalAccountMap(
          name: name,
          phone: phoneDigits,
          email: email,
          password: password.trim(),
          area: normalizedArea,
          division: division,
        ),
      );
      debugPrint('[LOGIN-PERSONAL][${_ts()}] personal account created: $docId');
      return PersonalAccountCreateResult(
        success: true,
        message: '개인형 계정을 생성했습니다.',
        password: password.trim(),
      );
    } catch (e, st) {
      debugPrint('[LOGIN-PERSONAL][${_ts()}] create personal account error: $e\n$st');
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'personal_accounts.createPersonalAccount',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'personal_accounts',
          'docId': docId,
          'phone': phoneDigits,
          'email': email,
          'area': normalizedArea,
          'division': division,
          'phase': 'exists-check-or-create-set',
          'read': 'doc($docId).get()',
          'write': 'doc($docId).set(newPersonalAccountMap)',
          'queryShape': 'direct-document-read-and-write',
          'compositeIndex': 'not-required',
        },
      );
      return const PersonalAccountCreateResult(
        success: false,
        message: '계정을 생성하지 못했습니다.',
      );
    }
  }

  Future<PersonalLoginResult> login(StateSetter setState) async {
    final name = nameController.text.trim();
    final phoneDigits = _normalizePhone(phoneController.text);
    final password = passwordController.text.trim();

    final error = validatePersonalInputs(
      name: name,
      phone: phoneDigits,
      password: password,
    );
    if (error != null) {
      return _loginFailureResult(error);
    }

    setState(() => isLoading = true);

    final isConn = await TabletLoginNetworkService().isConnected();
    if (!isConn) {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
      return _loginFailureResult('네트워크 연결을 확인하세요.');
    }

    try {
      final query = await _personalAccountsRef
          .where('phone', isEqualTo: phoneDigits)
          .limit(20)
          .get();

      QueryDocumentSnapshot<Map<String, dynamic>>? matchedDoc;
      Map<String, dynamic>? matchedData;
      var profileMatched = false;
      var passwordMissingForMatchedProfile = false;

      for (final doc in query.docs) {
        final data = doc.data();
        final active = (data['isActive'] as bool?) ?? true;
        if (!active) continue;

        final storedName = (data['name'] ?? '').toString().trim();
        final storedPhone = _normalizePhone((data['phone'] ?? '').toString());
        final profileMatches = storedName == name && storedPhone == phoneDigits;
        if (!profileMatches) continue;

        profileMatched = true;
        final storedPassword = (data['password'] ?? '').toString().trim();
        if (storedPassword.isEmpty) {
          passwordMissingForMatchedProfile = true;
          continue;
        }
        if (storedPassword != password) continue;

        matchedDoc = doc;
        matchedData = data;
        break;
      }

      if (query.docs.isEmpty) {
        return _loginFailureResult('개인형 계정을 찾을 수 없습니다.');
      }

      final hasInactiveOnly = query.docs.every((doc) {
        final data = doc.data();
        return ((data['isActive'] as bool?) ?? true) == false;
      });
      if (hasInactiveOnly) {
        return _loginFailureResult('비활성화된 개인형 계정입니다.');
      }

      if (matchedDoc == null || matchedData == null) {
        if (passwordMissingForMatchedProfile) {
          return _loginFailureResult('개인형 계정에 비밀번호가 없습니다. 개발자 모드에서 비밀번호가 포함된 계정으로 다시 생성하세요.');
        }
        if (profileMatched) {
          return _loginFailureResult('비밀번호가 일치하지 않습니다.');
        }
        return _loginFailureResult('입력한 계정 정보가 일치하지 않습니다.');
      }

      final storedName = (matchedData['name'] ?? '').toString().trim();
      final storedPhone = _normalizePhone((matchedData['phone'] ?? '').toString());
      final selectedArea = _selectedAreaFromData(matchedData);
      final division = _divisionFromData(matchedData);
      if (selectedArea.isEmpty) {
        return _loginFailureResult('개인형 계정의 지역 정보가 없습니다.');
      }

      final expectedDocId = _accountDocId(phone: storedPhone, area: selectedArea);
      if (matchedDoc.id != expectedDocId) {
        return _loginFailureResult('개인형 계정 문서 ID가 전화번호-지역 구조와 일치하지 않습니다.');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mode', _savedMode);
      await prefs.setString('phone', storedPhone);
      await prefs.setString('selectedArea', selectedArea);
      await prefs.setString('division', division);
      await prefs.setString('role', (matchedData['role'] ?? 'personal').toString());
      await prefs.setString('position', (matchedData['position'] ?? '').toString());
      await prefs.setString('personalAccountId', matchedDoc.id);
      await prefs.setString('personalName', storedName);
      await prefs.setString('personalPhone', storedPhone);

      await _personalAccountsRef.doc(matchedDoc.id).set(
        <String, dynamic>{
          'isSaved': true,
          'lastLoginAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (context.mounted) {
        context.read<AreaState>().setAreaLocalOnly(
              selectedArea,
              division: division,
            );
        context.read<TabletPadModeState>().setMode(_targetPadMode);
      }

      isLoggedIn = true;
      loggedInAccountId = matchedDoc.id;
      loggedInName = storedName;

      return PersonalLoginResult(success: true, message: '$storedName님, 개인형 로그인에 성공했습니다.');
    } catch (e, st) {
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'personal_accounts.login',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'personal_accounts',
          'inputName': name,
          'inputPhone': phoneDigits,
          'inputPasswordLength': password.length,
          'query': 'where(phone == $phoneDigits).limit(20)',
          'queryShape': 'single-field-equality-with-limit',
          'filters': 'phone == $phoneDigits',
          'orderBy': 'none',
          'limit': 20,
          'compositeIndex': 'not-required-for-this-shape-unless-rules-or-console-error-requires-it',
          'indexDebug': 'if FirebaseException.code == failed-precondition, use firebase.message console index link',
          'postLoginWrite': 'doc(matchedDoc.id).set(isSaved,lastLoginAt,updatedAt,merge)',
        },
      );
      return _loginFailureResult('로그인 중 오류가 발생했습니다.', error: e, stackTrace: st);
    } finally {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<PersonalLoginResult> logout(StateSetter setState) async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final accountId = loggedInAccountId ?? (prefs.getString('personalAccountId') ?? '').trim();
      if (accountId.isNotEmpty) {
        await _personalAccountsRef.doc(accountId).set(
          <String, dynamic>{
            'isSaved': false,
            'lastLogoutAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await prefs.remove('mode');
      await prefs.remove('phone');
      await prefs.remove('selectedArea');
      await prefs.remove('division');
      await prefs.remove('role');
      await prefs.remove('position');
      await prefs.remove('personalAccountId');
      await prefs.remove('personalName');
      await prefs.remove('personalPhone');
      await prefs.remove('personalEmail');

      passwordController.clear();
      isLoggedIn = false;
      loggedInAccountId = null;
      loggedInName = null;

      return const PersonalLoginResult(success: true, message: '개인형 로그아웃이 완료되었습니다.');
    } catch (e, st) {
      debugPrint('[LOGIN-PERSONAL][${_ts()}] logout error: $e\n$st');
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'personal_accounts.loginScreenLogout',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'personal_accounts',
          'accountId': loggedInAccountId,
          'write': 'doc(accountId).set(isSaved=false,lastLogoutAt,updatedAt,merge)',
          'queryShape': 'direct-document-write',
          'compositeIndex': 'not-required',
        },
      );
      return const PersonalLoginResult(success: false, message: '로그아웃 중 오류가 발생했습니다.');
    } finally {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void togglePassword() {
    obscurePassword = !obscurePassword;
  }

  void formatPhoneNumber(String value, StateSetter setState) {
    final digits = _normalizePhone(value);
    final limited = digits.length > 11 ? digits.substring(0, 11) : digits;
    final formatted = _formatPhoneForDisplay(limited);
    setState(() {
      phoneController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    });
  }


  void fillLoginFields({
    required String name,
    required String phone,
    String? password,
  }) {
    nameController.text = name.trim();
    phoneController.text = _formatPhoneForDisplay(_normalizePhone(phone));
    if (password != null) {
      passwordController.text = password.trim();
    }
  }

  InputDecoration inputDecoration({
    required String label,
    IconData? icon,
    Widget? suffixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: label,
      hintText: label,
      prefixIcon: icon != null ? Icon(icon) : null,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      filled: true,
      fillColor: cs.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.primary, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.error, width: 1.8),
      ),
      prefixIconColor: MaterialStateColor.resolveWith(
        (states) => states.contains(MaterialState.focused)
            ? cs.primary
            : cs.onSurfaceVariant,
      ),
      suffixIconColor: MaterialStateColor.resolveWith(
        (states) => states.contains(MaterialState.focused)
            ? cs.primary
            : cs.onSurfaceVariant,
      ),
    );
  }

  Future<void> openExternalSignUpForm() async {
    final uri = Uri.parse('https://forms.gle/ZjHEC4QrtAvHs5TQ8');
    var opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
    if (!opened) {
      debugPrint('[LOGIN-PERSONAL][${_ts()}] signUpForm open failed');
    }
  }

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    passwordFocus.dispose();
  }
}
