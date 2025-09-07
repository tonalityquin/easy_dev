import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/user_model.dart';
import 'debugs/tablet_login_debug_firestore_logger.dart';
import 'personal/tablet_personal_calendar.dart';
import 'utils/tablet_login_network_service.dart';
import 'utils/tablet_login_validate.dart'; // 비밀번호 검증만 사용
import '../../../repositories/user/user_repository.dart';
import '../../../states/area/area_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../routes.dart'; // ✅ 라우트 상수 사용 (TabletPage로 이동)

class TabletLoginController {
  final BuildContext context;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController(); // <- 핸들 입력으로 재사용
  final TextEditingController passwordController = TextEditingController();

  final FocusNode nameFocus = FocusNode();
  final FocusNode phoneFocus = FocusNode(); // <- 핸들 포커스
  final FocusNode passwordFocus = FocusNode();

  bool isLoading = false;
  bool obscurePassword = true;

  TabletLoginController(this.context);

  // ====== Helpers (handle) ======
  /// 입력 핸들을 소문자/trim/불필요 문자를 제거하여 정규화
  String _normalizeHandle(String v) {
    // 소문자 + 앞뒤공백 제거 + 영문/숫자/언더스코어만 허용
    final lower = v.trim().toLowerCase();
    final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return cleaned;
  }

  /// 핸들 유효성 검사: 영어소문자/숫자/언더스코어, 3~32자, 첫글자 영문 권장
  String? _validateHandle(String handle) {
    final h = _normalizeHandle(handle);
    if (h.isEmpty) return '영어 아이디(핸들)를 입력해주세요.';
    // 첫 글자 영문, 총 3~32자, 나머지는 영문/숫자/_
    final re = RegExp(r'^[a-z][a-z0-9_]{2,31}$');
    if (!re.hasMatch(h)) return '영어 소문자/숫자/_(언더스코어), 3~32자 (첫 글자는 영문)';
    return null;
  }

  void initState() {
    TabletLoginDebugFirestoreLogger().log('TabletLoginController 초기화 시작', level: 'info');

    // ✅ 태블릿 자동로그인 진입점
    Provider.of<UserState>(context, listen: false).loadTabletToLogIn().then((_) {
      final isLoggedIn = Provider.of<UserState>(context, listen: false).isLoggedIn;

      TabletLoginDebugFirestoreLogger().log(
        '이전 로그인 정보 로드 완료(태블릿): isLoggedIn=$isLoggedIn',
        level: 'success',
      );

      if (isLoggedIn && context.mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          TabletLoginDebugFirestoreLogger().log('자동 로그인(태블릿): TabletPage로 이동', level: 'info');
          Navigator.pushReplacementNamed(context, AppRoutes.tablePage); // ✅ 변경: /tablet_page 로 이동
        });
      }
    });
  }

  Future<void> login(StateSetter setState) async {
    final name = nameController.text.trim();
    final rawHandle = phoneController.text; // UI 필드명은 phone이지만, 실제로는 핸들 입력
    final handle = _normalizeHandle(rawHandle);
    final password = passwordController.text.trim();

    // 백도어: 개인 캘린더
    if (name.isEmpty && handle.isEmpty && password == '00000') {
      TabletLoginDebugFirestoreLogger().log('비밀번호 00000으로 TabletPersonalCalendar 진입', level: 'info');
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TabletPersonalCalendar()),
      );
      return;
    }

    TabletLoginDebugFirestoreLogger().log('로그인 시도(태블릿): name="$name", handle="$handle"', level: 'called');

    // ===== 입력 검증 =====
    final handleError = _validateHandle(handle);
    final passwordError = TabletLoginValidate.validatePassword(password);

    if (name.isEmpty) {
      showFailedSnackbar(context, '이름을 입력해주세요.');
      TabletLoginDebugFirestoreLogger().log('이름 미입력', level: 'error');
      return;
    }
    if (handleError != null) {
      showFailedSnackbar(context, handleError);
      TabletLoginDebugFirestoreLogger().log('핸들 오류: $handleError', level: 'error');
      return;
    }
    if (passwordError != null) {
      showFailedSnackbar(context, passwordError);
      TabletLoginDebugFirestoreLogger().log('비밀번호 오류: $passwordError', level: 'error');
      return;
    }

    setState(() => isLoading = true);
    TabletLoginDebugFirestoreLogger().log('로그인 처리 중(태블릿)...', level: 'info');

    // 네트워크 체크
    if (!await TabletLoginNetworkService().isConnected()) {
      if (context.mounted) {
        showFailedSnackbar(context, '인터넷 연결이 필요합니다.');
      }
      TabletLoginDebugFirestoreLogger().log('네트워크 연결 실패', level: 'error');
      setState(() => isLoading = false);
      return;
    }

    try {
      final repo = context.read<UserRepository>();
      final tablet = await repo.getTabletByHandle(handle);

      if (tablet != null) {
        TabletLoginDebugFirestoreLogger().log('태블릿 계정 조회 성공: ${tablet.id}', level: 'success');
      } else {
        TabletLoginDebugFirestoreLogger().log('태블릿 계정 조회 실패(handle 미일치)', level: 'error');
      }

      if (context.mounted) {
        debugPrint('입력값: name=$name, handle=$handle, password=$password');
        if (tablet != null) {
          debugPrint('DB 태블릿: name=${tablet.name}, handle=${tablet.handle}, password=${tablet.password}');
        } else {
          debugPrint('DB에서 태블릿 계정 없음');
        }
      }

      // ===== 인증: 이름 & 비밀번호 일치 확인 =====
      if (tablet != null && tablet.name == name && tablet.password == password) {
        final userState = context.read<UserState>();
        final areaState = context.read<AreaState>();

        // 표시/저장용 지역명 결정(한글 지역명 우선)
        final areaName = (tablet.selectedArea ??
            tablet.currentArea ??
            (tablet.areas.isNotEmpty ? tablet.areas.first : ''))
            .trim();
        if (areaName.isEmpty) {
          showFailedSnackbar(context, '해당 계정에 등록된 지역이 없습니다.');
          TabletLoginDebugFirestoreLogger().log('인증 실패: areaName 비어있음', level: 'error');
          setState(() => isLoading = false);
          return;
        }
        final englishAreaName = tablet.englishSelectedAreaName ?? areaName;

        // ===== TabletModel → UserModel 매핑 (handle → phone 슬롯) =====
        final userAsTablet = UserModel(
          id: tablet.id,
          areas: List<String>.from(tablet.areas),
          currentArea: areaName,
          divisions: List<String>.from(tablet.divisions),
          email: tablet.email,
          endTime: tablet.endTime,
          englishSelectedAreaName: tablet.englishSelectedAreaName,
          fixedHolidays: List<String>.from(tablet.fixedHolidays),
          isSaved: true, // 로그인 성공 시 저장됨
          isSelected: tablet.isSelected,
          isWorking: tablet.isWorking,
          name: tablet.name,
          password: tablet.password,
          phone: tablet.handle, // 중요: handle을 phone 슬롯에 넣어 상태/UI 호환
          position: tablet.position,
          role: tablet.role,
          selectedArea: areaName, // 한글 지역명
          startTime: tablet.startTime,
        );

        // SharedPreferences(핸들/지역키)도 직접 보존
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('handle', handle);
        await prefs.setString('selectedArea', areaName); // 한글 지역명
        await prefs.setString('englishSelectedAreaName', englishAreaName);

        // 상태 업데이트: tablet_accounts 기준으로 저장/업서트 + prefs 저장 + 목록 리로드
        await userState.updateLoginTablet(userAsTablet);

        TabletLoginDebugFirestoreLogger().log(
          '로그인 성공(태블릿): user=${tablet.name}, area=$areaName',
          level: 'success',
        );

        // 현재 앱의 지역 컨텍스트 업데이트
        areaState.updateArea(areaName);

        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacementNamed(context, AppRoutes.tablePage); // ✅ 변경: TabletPage로 이동
          });
        }
      } else {
        if (context.mounted) {
          showFailedSnackbar(context, '이름 또는 비밀번호가 올바르지 않습니다.');
        }
        TabletLoginDebugFirestoreLogger().log('로그인 인증 실패(태블릿)', level: 'error');
      }
    } catch (e) {
      if (context.mounted) {
        showFailedSnackbar(context, '로그인 실패: $e');
      }
      TabletLoginDebugFirestoreLogger().log('예외 발생: $e', level: 'error');
    } finally {
      setState(() => isLoading = false);
      TabletLoginDebugFirestoreLogger().log('로그인 프로세스 종료(태블릿)', level: 'info');
    }
  }

  void togglePassword() {
    obscurePassword = !obscurePassword;
    TabletLoginDebugFirestoreLogger().log('비밀번호 가시성 변경: $obscurePassword', level: 'info');
  }

  /// UI에서 호출 중인 메서드명을 유지하면서 핸들 정규화로 동작 변경
  void formatPhoneNumber(String value, StateSetter setState) {
    final normalized = _normalizeHandle(value);
    setState(() {
      phoneController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    });
    TabletLoginDebugFirestoreLogger().log('핸들 포맷팅: $normalized', level: 'info');
  }

  InputDecoration inputDecoration({
    required String label,
    IconData? icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: label,
      prefixIcon: icon != null ? Icon(icon) : null,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.indigo, width: 2),
      ),
    );
  }

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    passwordFocus.dispose();
    TabletLoginDebugFirestoreLogger().log('TabletLoginDebugFirestoreLogger dispose() 호출됨', level: 'info');
  }
}
