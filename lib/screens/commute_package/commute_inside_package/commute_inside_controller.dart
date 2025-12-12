import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../routes.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import '../../../utils/snackbar_helper.dart';
import 'utils/commute_inside_clock_in_log_uploader.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:easydev/services/endtime_reminder_service.dart';

// ✅ commute_true_false(출근시각 Timestamp) 기록용 Firestore 레포지토리
import '../../../repositories/commute_true_false_repository.dart';

// ✅ 추가: 기기별 commute_true_false Firestore 업데이트 ON/OFF
import '../../../utils/commute_true_false_mode_config.dart';

const kIsWorkingPrefsKey = 'isWorking';

// ✅ 라우팅을 밖에서 수행하기 위한 목적지 enum
enum CommuteDestination { none, headquarter, type }

class CommuteInsideController {
  // ✅ commute_true_false 전용 레포지토리 인스턴스
  final CommuteTrueFalseRepository _commuteTrueFalseRepo =
  CommuteTrueFalseRepository();

  void initialize(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final areaToInit = userState.area.trim();

      final alreadyInitialized = areaState.currentArea == areaToInit &&
          areaState.capabilitiesOfCurrentArea.isNotEmpty;

      if (!alreadyInitialized) {
        await areaState.initializeArea(areaToInit);
        debugPrint('[GoToWork] initializeArea 호출: $areaToInit');
      } else {
        debugPrint('[GoToWork] 초기화 스킵 (이미 준비됨): $areaToInit');
      }

      debugPrint('[GoToWork] currentArea: ${areaState.currentArea}');
    });
  }

  Future<CommuteDestination> _decideDestination(
      BuildContext context,
      UserState userState,
      ) async {
    if (!userState.isWorking) return CommuteDestination.none;
    if (!context.mounted) return CommuteDestination.none;

    final division = userState.user?.divisions.first ?? '';
    final area = userState.area;
    final docId = '$division-$area';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('areas')
          .doc(docId)
          .get();

      if (!context.mounted) return CommuteDestination.none;

      final isHq = doc.exists && (doc.data()?['isHeadquarter'] == true);
      return isHq ? CommuteDestination.headquarter : CommuteDestination.type;
    } catch (e) {
      debugPrint('❌ _decideDestination 실패: $e');
      return CommuteDestination.none;
    }
  }

  /// ✅ 서비스 로그인 화면의 "출근하기" 버튼에서 호출:
  /// - 출근 중복 여부 검사
  /// - 출근 로그 업로드(SQLite)
  /// - user_accounts.isWorking 토글(true)
  /// - 오늘 출근 캐시(markClockInToday)
  /// - commute_true_false 에 "출근 시각 Timestamp" 기록 (퇴근과 무관)
  /// - 이후 목적지(본사/타입) 판별
  Future<CommuteDestination> handleWorkStatusAndDecide(
      BuildContext context,
      UserState userState,
      ) async {
    try {
      // 1) 오늘 출근 여부 캐시 보장 (실제 Firestore read는 UserState에서 하루 1번)
      await userState.ensureTodayClockInStatus();

      // 2) 이미 오늘 출근한 상태라면 중복 출근 방지
      if (userState.hasClockInToday) {
        showFailedSnackbar(context, '이미 오늘 출근 기록이 있습니다.');
        return CommuteDestination.none;
      }

      // 3) 출근 로그 저장 + 로컬 isWorking prefs/알림 세팅
      final uploadResult = await _uploadAttendanceSilently(context);

      // 저장 실패/취소 시에는 여기서 종료
      if (uploadResult == null || uploadResult.success != true) {
        return CommuteDestination.none;
      }

      // 4) 출근 성공 시: Firestore user_accounts.isWorking 토글(false → true)
      await userState.isHeWorking();

      // 5) 출근 성공 시: 오늘 출근했다는 사실을 캐시에 반영
      userState.markClockInToday();

      // 6) ✅ commute_true_false 에 "출근 시각" 기록 (Timestamp)
      //    - 단, 기기 설정 OFF면 내부에서 스킵
      await _recordClockInAtToCommuteTrueFalse(userState);

      // 상태가 true면 목적지 결정
      return _decideDestination(context, userState);
    } catch (e, st) {
      debugPrint('handleWorkStatusAndDecide error: $e\n$st');
      _showWorkError(context);
      return CommuteDestination.none;
    }
  }

  // ✅ 자동 경로: (모달 아님) 현재 근무중이면 목적지 판단 후 즉시 라우팅
  void redirectIfWorking(BuildContext context, UserState userState) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final dest = await _decideDestination(context, userState);
      if (!context.mounted) return;

      switch (dest) {
        case CommuteDestination.headquarter:
          Navigator.pushReplacementNamed(context, AppRoutes.headquarterPage);
          break;
        case CommuteDestination.type:
          Navigator.pushReplacementNamed(context, AppRoutes.typePage);
          break;
        case CommuteDestination.none:
          break;
      }
    });
  }

  /// 출근 기록을 **로컬(SQLite, simple_mode 테이블)** 에 저장하고,
  /// 성공 시 로컬 isWorking prefs 및 퇴근 알림까지 세팅하는 헬퍼.
  ///
  /// - 실제 저장은 CommuteInsideClockInLogUploader.uploadAttendanceJson(...) 에서
  ///   SimpleModeAttendanceRepository.insertEvent(...) 를 호출해 수행.
  /// - 성공/실패 여부는 반환값의 `success` 필드로 판단(dynamic 사용)
  /// - 스낵바는 이 함수 안에서 처리
  Future<dynamic> _uploadAttendanceSilently(BuildContext context) async {
    final userState = Provider.of<UserState>(context, listen: false);
    final area = userState.area;
    final name = userState.name;

    if (area.isEmpty || name.isEmpty) {
      showFailedSnackbar(
        context,
        '출근 기록 업로드 실패: 사용자 정보(area/name)가 비어 있습니다.\n'
            '관리자에게 계정/근무지 설정을 확인해 달라고 요청해 주세요.',
      );
      return null;
    }

    final now = DateTime.now();
    final nowTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final result = await CommuteInsideClockInLogUploader.uploadAttendanceJson(
      context: context,
      data: {
        'recordedTime': nowTime,
      },
    );

    if (!context.mounted) return null;

    if (result.success == true) {
      showSuccessSnackbar(context, result.message);

      // ✅ 출근 상태를 로컬에 저장하고, 알림을 즉시 반영
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kIsWorkingPrefsKey, true);
      final end = prefs.getString('endTime');
      if (end != null && end.isNotEmpty) {
        await EndTimeReminderService.instance.scheduleDailyOneHourBefore(end);
      }
    } else {
      showFailedSnackbar(context, result.message);
    }

    return result;
  }

  /// ✅ 서비스 출근 성공 시 commute_true_false 에 "출근 시각(Timestamp)" 기록
  ///
  /// - 문서 ID: 회사명/사업부명(company=division)
  /// - 필드: area(지역명) → { workerName: Timestamp }
  ///
  /// ⚠️ 정책: 퇴근(workOut)에서는 이 컬렉션을 절대 수정하지 않습니다.
  Future<void> _recordClockInAtToCommuteTrueFalse(UserState userState) async {
    // ✅ 기기 설정이 OFF면 commute_true_false 업데이트 스킵 (SQLite/기타 로직은 유지)
    final enabled = await CommuteTrueFalseModeConfig.isEnabled();
    if (!enabled) {
      debugPrint(
        '[CommuteInsideController] commute_true_false OFF(기기 설정) → 업데이트 스킵',
      );
      return;
    }

    final company = userState.division.trim(); // 회사명/사업부명
    final area = userState.area.trim(); // 지역명
    final workerName = userState.name.trim(); // 사용자 이름
    final clockInAt = DateTime.now();

    if (company.isEmpty || area.isEmpty || workerName.isEmpty) {
      debugPrint(
        '[CommuteInsideController] commute_true_false(clockInAt) 업데이트 스킵 '
            '(company="$company", area="$area", workerName="$workerName")',
      );
      return;
    }

    try {
      await _commuteTrueFalseRepo.setClockInAt(
        company: company,
        area: area,
        workerName: workerName,
        clockInAt: clockInAt,
      );
      debugPrint(
        '[CommuteInsideController] commute_true_false(clockInAt) 반영 완료 '
            '(company="$company", area="$area", workerName="$workerName", clockInAt="$clockInAt")',
      );
    } catch (e, st) {
      debugPrint(
        '[CommuteInsideController] commute_true_false(clockInAt) 업데이트 실패: $e\n$st',
      );
    }
  }

  void _showWorkError(BuildContext context) {
    if (!context.mounted) return;
    showFailedSnackbar(
      context,
      '작업 처리 중 오류가 발생했습니다. 다시 시도해주세요.',
    );
  }
}
