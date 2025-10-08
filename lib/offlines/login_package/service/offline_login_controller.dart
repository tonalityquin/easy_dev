import 'package:flutter/material.dart';
import 'package:easydev/offlines/offline_auth_service.dart';

// (선택) 마스터 저장소가 프로젝트에 존재한다면 주석 해제하세요.
// import 'package:easydev/offlines/repositories/offline_master_repository.dart';

/// 오프라인 모드 전용 로그인 컨트롤러
/// - 고정 자격증명 성공 시:
///   - SQLite offline_sessions 에 세션 저장
///   - area 기본값은 "HQ 지역"으로 저장(요구사항)
///   - (있다면) OfflineMasterRepository 를 통해 tester.isSaved = true 로 마킹
class OfflineLoginController {
  // 고정 자격증명
  static const String allowedName = 'tester';
  static const String allowedPhone = '01012345678';
  static const String allowedPassword = '12345';

  // 요구사항 기본값(테스터 계정)
  static const String defaultDivision = 'dev';      // division
  static const String defaultAreaHQ = 'HQ 지역';     // areas[0]
  static const String defaultAreaWorking = 'WorkingArea 지역'; // areas[1]

  // 상태
  bool isLoading = false;
  bool obscurePassword = true;

  // 폼 컨트롤러
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // 포커스
  final FocusNode nameFocus = FocusNode();
  final FocusNode phoneFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  /// 로그인 성공 시 화면 전환 등 외부에서 주입할 콜백(선택)
  final VoidCallback? onLoginSucceeded;

  OfflineLoginController({this.onLoginSucceeded});

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    passwordFocus.dispose();
  }

  /// Deep Blue 팔레트 기반의 공통 인풋 데코레이션
  InputDecoration inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  /// 비밀번호 표시/숨김 토글 (무인자) — UI에서 setState로 래핑해 호출
  void togglePassword() {
    obscurePassword = !obscurePassword;
  }

  /// 숫자만 남기고 간단 포맷 적용(필요 시 고도화 가능)
  void formatPhoneNumber(String value, StateSetter setState) {
    final digits = _digitsOnly(value);
    final selectionIndex = phoneController.selection.baseOffset;
    setState(() {
      phoneController.text = digits;
      final pos = digits.length;
      phoneController.selection = TextSelection.collapsed(
        offset: selectionIndex < 0 ? pos : (selectionIndex > pos ? pos : selectionIndex),
      );
    });
  }

  /// ServiceLoginForm 호환용: setState를 받아 로딩상태 토글 + 실제 시도
  void login(BuildContext context, StateSetter setState) async {
    if (isLoading) return;
    setState(() => isLoading = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 150)); // UX 보완용 소딜레이
      await attemptLogin(context);
    } finally {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  /// 오프라인 전용 로그인 시도
  /// - 성공 시: SQLite 세션 저장(division=dev, area="HQ 지역")
  /// - 추가: (있다면) 마스터 저장소에 tester.isSaved = true 마킹
  Future<void> attemptLogin(BuildContext context) async {
    final name = nameController.text.trim();
    final phone = _digitsOnly(phoneController.text.trim());
    final password = passwordController.text;

    final ok = name.toLowerCase() == allowedName &&
        phone == allowedPhone &&
        password == allowedPassword;

    if (!ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('오프라인 로그인 정보가 올바르지 않습니다.')),
        );
      }
      return;
    }

    try {
      // ✅ 세션 저장: area 기본값은 요구사항대로 "HQ 지역"으로 기록
      await OfflineAuthService.instance.signInOffline(
        userId: phone,
        name: name,                 // 입력값 유지
        position: defaultDivision,  // division=dev → 세션의 position 필드에 저장
        phone: phone,               // 01012345678
        area: defaultAreaHQ,        // 기본: HQ 지역 (areas[0])
      );

      // (선택) 마스터 저장소가 있으면 seed + tester.isSaved=true 마킹
      // try {
      //   final repo = OfflineMasterRepository.instance;
      //   await repo.ensureSeededDefaults(); // division/dev, area/HQ·WorkingArea 등 기본값 보장
      //   await repo.markTesterSaved(phone: phone, isSaved: true);
      //   // 필요 시 tester의 areas 순서(0=HQ, 1=WorkingArea)와 division=dev도 보정
      //   await repo.ensureTesterAreasOrder(
      //     phone: phone,
      //     areas: const [defaultAreaHQ, defaultAreaWorking],
      //   );
      //   await repo.ensureTesterDivision(phone: phone, division: defaultDivision);
      // } catch (_) {
      //   // 마스터 저장소가 아직 없거나 API가 다를 수 있으니 조용히 스킵
      // }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오프라인 로그인 성공')),
      );

      // ✅ 네비게이션
      if (onLoginSucceeded != null) {
        onLoginSucceeded!();
      } else {
        Navigator.of(context).pushReplacementNamed('/offline_commute');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오프라인 세션 저장 실패: $e')),
        );
      }
    }
  }

  /// 하이픈/공백 제거 및 숫자만 남기기
  String _digitsOnly(String input) {
    final codeUnits = input.codeUnits;
    final buf = StringBuffer();
    for (final u in codeUnits) {
      if (u >= 48 && u <= 57) buf.writeCharCode(u);
    }
    return buf.toString();
  }
}
