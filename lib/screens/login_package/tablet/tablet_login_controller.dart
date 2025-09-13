import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart'; // ✅ 유지
import '../../../models/user_model.dart';
import 'utils/tablet_login_network_service.dart';
import 'utils/tablet_login_validate.dart'; // 비밀번호 검증만 사용
import '../../../repositories/user_repo_services/user_repository.dart';
import '../../../states/area/area_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../routes.dart'; // ✅ 라우트 상수 사용 (TabletPage로 이동)
// ⬇️ 추가: TTS 오너십 스위치
import '../../../utils/tts/tts_ownership.dart';
// ⬇️ 추가: TTS 사용자 필터
import '../../../utils/tts/tts_user_filters.dart';

String _ts() => DateTime.now().toIso8601String();

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
  String _normalizeHandle(String v) {
    final lower = v.trim().toLowerCase();
    final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return cleaned;
  }

  String? _validateHandle(String handle) {
    final h = _normalizeHandle(handle);
    if (h.isEmpty) return '영어 아이디(핸들)를 입력해주세요.';
    final re = RegExp(r'^[a-z][a-z0-9_]{2,31}$');
    if (!re.hasMatch(h)) return '영어 소문자/숫자/_(언더스코어), 3~32자 (첫 글자는 영문)';
    return null;
  }

  void initState() {
    Provider.of<UserState>(context, listen: false).loadTabletToLogIn().then((_) {
      final isLoggedIn = Provider.of<UserState>(context, listen: false).isLoggedIn;
      debugPrint('[LOGIN-TABLET][${_ts()}] autoLogin check → isLoggedIn=$isLoggedIn');
      if (isLoggedIn && context.mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          debugPrint('[LOGIN-TABLET][${_ts()}] autoLogin → pushReplacementNamed(AppRoutes.tablet)');
          Navigator.pushReplacementNamed(context, AppRoutes.tablet);
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
      debugPrint('[LOGIN-TABLET][${_ts()}] backdoor bypass');
      return;
    }

    // ===== 입력 검증 =====
    final handleError = _validateHandle(handle);
    final passwordError = TabletLoginValidate.validatePassword(password);

    if (name.isEmpty) {
      showFailedSnackbar(context, '이름을 입력해주세요.');
      return;
    }
    if (handleError != null) {
      showFailedSnackbar(context, handleError);
      return;
    }
    if (passwordError != null) {
      showFailedSnackbar(context, passwordError);
      return;
    }

    setState(() => isLoading = true);

    // 네트워크 체크
    final isConn = await TabletLoginNetworkService().isConnected();
    debugPrint('[LOGIN-TABLET][${_ts()}] isConnected=$isConn');
    if (!isConn) {
      if (context.mounted) {
        showFailedSnackbar(context, '인터넷 연결이 필요합니다.');
      }
      setState(() => isLoading = false);
      return;
    }

    try {
      final repo = context.read<UserRepository>();
      final tablet = await repo.getTabletByHandle(handle);

      if (context.mounted) {
        debugPrint('[LOGIN-TABLET][${_ts()}] input name="$name" handle="$handle" pwLen=${password.length}');
        if (tablet != null) {
          debugPrint('[LOGIN-TABLET][${_ts()}] DB tablet: name=${tablet.name}, handle=${tablet.handle}');
        } else {
          debugPrint('[LOGIN-TABLET][${_ts()}] DB no tablet for handle="$handle"');
        }
      }

      // ===== 인증: 이름 & 비밀번호 일치 확인 =====
      if (tablet != null && tablet.name == name && tablet.password == password) {
        final userState = context.read<UserState>();
        final areaState = context.read<AreaState>();

        // 표시/저장용 지역명 결정(한글 지역명 우선)
        final areaName =
        (tablet.selectedArea ?? tablet.currentArea ?? (tablet.areas.isNotEmpty ? tablet.areas.first : '')).trim();
        debugPrint('[LOGIN-TABLET][${_ts()}] resolved areaName="$areaName" from tablet.selected/current/areas');

        if (areaName.isEmpty) {
          showFailedSnackbar(context, '해당 계정에 등록된 지역이 없습니다.');
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
          isSaved: true,
          isSelected: tablet.isSelected,
          isWorking: tablet.isWorking,
          name: tablet.name,
          password: tablet.password,
          phone: tablet.handle, // 핸들을 phone 슬롯에 넣어 상태/UI 호환
          position: tablet.position,
          role: tablet.role,
          selectedArea: areaName, // 한글 지역명
          startTime: tablet.startTime,
        );

        // SharedPreferences(핸들/지역키/모드) 보존
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('handle', handle);
        await prefs.setString('selectedArea', areaName); // 한글 지역명
        await prefs.setString('englishSelectedAreaName', englishAreaName);
        await prefs.setString('mode', 'tablet'); // ✅ 로그인 모드 저장
        // ✅ 오너십: 포그라운드가 Plate TTS를 담당하도록 설정
        await TtsOwnership.setOwner(TtsOwner.foreground);
        debugPrint('[LOGIN-TABLET][${_ts()}] prefs saved (handle/selectedArea/englishSelectedAreaName/mode & owner=foreground)');

        // 상태 업데이트
        await userState.updateLoginTablet(userAsTablet);
        debugPrint('[LOGIN-TABLET][${_ts()}] userState.updateLoginTablet done');

        // ✅ 1) 먼저 AreaState 갱신 (currentArea가 확정됨)
        areaState.updateArea(areaName);
        debugPrint('[LOGIN-TABLET][${_ts()}] areaState.updateArea("$areaName")');

        // ✅ 2) 그리고 갱신된 currentArea를 TTS로 전달 (+ 필터 동봉)
        final current = context.read<AreaState>().currentArea;
        debugPrint('[LOGIN-TABLET][${_ts()}] send area to FG (currentArea="$current")');
        if (current.isNotEmpty) {
          final filters = await TtsUserFilters.load(); // ⬅️ 추가
          FlutterForegroundTask.sendDataToTask({
            'area': current,
            'ttsFilters': filters.toMap(), // ⬅️ 추가
          });
          debugPrint('[LOGIN-TABLET][${_ts()}] sendDataToTask ok (with filters ${filters.toMap()})');
        } else {
          debugPrint('[LOGIN-TABLET][${_ts()}] currentArea is empty → skip send');
        }

        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint('[LOGIN-TABLET][${_ts()}] navigate → AppRoutes.tablet');
            Navigator.pushReplacementNamed(context, AppRoutes.tablet);
          });
        }
      } else {
        if (context.mounted) {
          debugPrint('[LOGIN-TABLET][${_ts()}] auth failed (name/password mismatch or no tablet)');
          showFailedSnackbar(context, '이름 또는 비밀번호가 올바르지 않습니다.');
        }
      }
    } catch (e, st) {
      debugPrint('[LOGIN-TABLET][${_ts()}] login error: $e\n$st');
      if (context.mounted) {
        showFailedSnackbar(context, '로그인 실패: $e');
      }
    } finally {
      setState(() => isLoading = false);
      debugPrint('[LOGIN-TABLET][${_ts()}] set isLoading=false');
    }
  }

  void togglePassword() {
    obscurePassword = !obscurePassword;
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
          borderRadius: BorderRadius.circular(16)),
    );
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
