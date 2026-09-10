import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../account/applications/user_state.dart';
import '../../dev/application/area_state.dart';
import '../application/single_inside_diagnostics.dart';

class SingleInsideController {
  void initialize(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) return;

      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final areaToInit = userState.currentArea.trim();
      final accountArea = userState.area.trim();
      final areaStateDivision = areaState.currentDivision.trim();
      final userDivision = userState.division.trim();
      final divisionToInit = areaStateDivision.isNotEmpty
          ? areaStateDivision
          : userDivision;
      final currentAreaBefore = areaState.currentArea.trim();
      final currentDivisionBefore = areaState.currentDivision.trim();

      SingleInsideDiagnostics.log(
        'controller',
        'initialize_start currentArea=$areaToInit accountArea=$accountArea requested=$divisionToInit/$areaToInit current=$currentDivisionBefore/$currentAreaBefore',
      );

      if (areaToInit.isEmpty || divisionToInit.isEmpty) {
        SingleInsideDiagnostics.log(
          'controller',
          'initialize_skip reason=missing_area_or_division area=$areaToInit division=$divisionToInit',
        );
        return;
      }

      final alreadyInitialized = areaState.hasCurrentRecordFor(
        division: divisionToInit,
        area: areaToInit,
      );

      SingleInsideDiagnostics.log(
        'controller',
        'initialize_record_check requested=$divisionToInit/$areaToInit hasCurrentRecord=$alreadyInitialized',
      );

      if (!alreadyInitialized) {
        SingleInsideDiagnostics.log(
          'controller',
          'initialize_area_start requested=$divisionToInit/$areaToInit',
        );
        await areaState.initializeArea(
          areaToInit,
          division: divisionToInit,
        );
        SingleInsideDiagnostics.log(
          'controller',
          'initialize_area_complete requested=$divisionToInit/$areaToInit current=${areaState.currentDivision}/${areaState.currentArea} hasCurrentRecord=${areaState.hasCurrentRecordFor(division: divisionToInit, area: areaToInit)}',
        );
      } else {
        SingleInsideDiagnostics.log(
          'controller',
          'initialize_area_skip reason=current_session_record_reused requested=$divisionToInit/$areaToInit',
        );
      }

      final capabilityKeys = areaState.capabilitiesOfCurrentArea
          .map((capability) => capability.name)
          .toList(growable: false)
        ..sort();
      SingleInsideDiagnostics.log(
        'controller',
        'initialize_complete current=${areaState.currentDivision}/${areaState.currentArea} capabilities=$capabilityKeys',
      );
    });
  }
}
