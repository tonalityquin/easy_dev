import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';

class SupportInsideController {
  /// 화면 최초 진입 시, 사용자 area 에 맞는 AreaState 초기화만 수행하는 컨트롤러.
  ///
  /// 기존에는 출근 처리 / 근무 상태 토글 / 시트 업로드 / 알림 / 라우팅 등의
  /// 로직도 함께 가지고 있었지만, 현재는 모두 제거하고
  /// "근무지/권한 초기화" 역할만 담당합니다.
  void initialize(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final areaToInit = userState.area.trim();

      final alreadyInitialized =
          areaState.currentArea == areaToInit &&
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
}
