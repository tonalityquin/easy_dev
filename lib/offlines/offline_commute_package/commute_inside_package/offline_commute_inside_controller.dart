import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../routes.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import '../../../utils/snackbar_helper.dart';


// ✅ 라우팅을 밖에서 수행하기 위한 목적지 enum
enum CommuteDestination { none, headquarter, type }

class OfflineCommuteInsideController {
  void initialize(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final areaToInit = userState.area.trim();

      final alreadyInitialized =
          areaState.currentArea == areaToInit && areaState.capabilitiesOfCurrentArea.isNotEmpty;

      if (!alreadyInitialized) {
        await areaState.initializeArea(areaToInit);
        debugPrint('[GoToWork] initializeArea 호출: $areaToInit');
      } else {
        debugPrint('[GoToWork] 초기화 스킵 (이미 준비됨): $areaToInit');
      }

      debugPrint('[GoToWork] currentArea: ${areaState.currentArea}');
    });
  }

  // ✅ Firestore 의존 제거: 간단한 폴백 규칙으로 대체
  Future<CommuteDestination> _decideDestination(
      BuildContext context,
      UserState userState,
      ) async {
    // 오프라인 모드: SQLite tester는 HQ 계정 → 본사 여부와 관계없이 OfflineHeadPage로 보냄
    if (!context.mounted) return CommuteDestination.none;
    return CommuteDestination.headquarter;
  }

  // ✅ 버튼 경로: 모달 안에서 호출 — 상태 갱신 + 목적지 판단만 수행
  Future<CommuteDestination> handleWorkStatusAndDecide(
      BuildContext context,
      UserState userState,
      ) async {
    try {
      await _uploadAttendanceSilently(context); // (Sheets append)
      await userState.isHeWorking(); // 근무 상태 갱신

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
          Navigator.pushReplacementNamed(context, AppRoutes.offlineHeadquarterPage);
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
    var area = userState.area;
    var name = userState.name;

    if (area.isEmpty || name.isEmpty) {
      // 업로드 필수 정보 부족 시 업로드 스킵
      return;
    }

    if (!context.mounted) return;
  }

  void _showWorkError(BuildContext context) {
    if (!context.mounted) return;
    showFailedSnackbar(context, '작업 처리 중 오류가 발생했습니다. 다시 시도해주세요.');
  }
}
