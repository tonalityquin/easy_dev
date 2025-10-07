import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


import '../../../routes.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import '../../../utils/snackbar_helper.dart';
import 'utils/offline_commute_inside_clock_in_log_uploader.dart';


import 'package:shared_preferences/shared_preferences.dart';
import 'package:easydev/services/endtime_reminder_service.dart';
const kIsWorkingPrefsKey = 'isWorking';


// ✅ 라우팅을 밖에서 수행하기 위한 목적지 enum
enum CommuteDestination { none, headquarter, type }


class OfflineCommuteInsideController {
  void initialize(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final areaToInit = userState.area.trim();


      final alreadyInitialized = areaState.currentArea == areaToInit && areaState.capabilitiesOfCurrentArea.isNotEmpty;


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
      final doc = await FirebaseFirestore.instance.collection('areas').doc(docId).get();


      /*await UsageReporter.instance.report(
       area: area.isNotEmpty ? area : 'unknown',
       action: 'read',
       n: 1,
       source: 'CommuteInsideController._decideDestination/areas.doc.get',
     );*/


      if (!context.mounted) return CommuteDestination.none;


      final isHq = doc.exists && (doc.data()?['isHeadquarter'] == true);
      return isHq ? CommuteDestination.headquarter : CommuteDestination.type;
    } catch (e) {
      debugPrint('❌ _decideDestination 실패: $e');
      return CommuteDestination.none;
    }
  }


  // ✅ 버튼 경로: 모달 안에서 호출 — 상태 갱신 + 목적지 판단만 수행
  Future<CommuteDestination> handleWorkStatusAndDecide(
      BuildContext context,
      UserState userState,
      ) async {
    try {
      await _uploadAttendanceSilently(context); // (Sheets append)
      await userState.isHeWorking(); // 근무 상태 갱신(내부 read는 해당 서비스에서 계측)


      // 상태가 true면 목적지 결정
      return _decideDestination(context, userState);
    } catch (e) {
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


  Future<void> _uploadAttendanceSilently(BuildContext context) async {
    final userState = Provider.of<UserState>(context, listen: false);
    final area = userState.area;
    final name = userState.name;


    if (area.isEmpty || name.isEmpty) {
      return;
    }


    final now = DateTime.now();
    final nowTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';


    final success = await OfflineCommuteInsideClockInLogUploader.uploadAttendanceJson(
      context: context,
      data: {
        'recordedTime': nowTime,
      },
    );


    if (!context.mounted) return;


    if (success) {
      /*await UsageReporter.instance.report(
       area: area,
       action: 'write',
       n: 1,
       source: 'CommuteInsideController._uploadAttendanceSilently',
     );*/
      showSuccessSnackbar(context, '출근 기록 업로드 완료');


      // ✅ 출근 상태를 로컬에 저장하고, 알림을 즉시 반영
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kIsWorkingPrefsKey, true);
      final end = prefs.getString('endTime');
      if (end != null && end.isNotEmpty) {
        await EndtimeReminderService.instance.scheduleDailyOneHourBefore(end);
      }
    } else {
      showFailedSnackbar(context, '출근 기록 업로드 실패');
    }
  }


  void _showWorkError(BuildContext context) {
    if (!context.mounted) return;
    showFailedSnackbar(context, '작업 처리 중 오류가 발생했습니다. 다시 시도해주세요.');
  }
}
