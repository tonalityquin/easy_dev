import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../account/applications/user_state.dart';
import '../../dev/application/area_state.dart';

class SingleInsideController {
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
}
